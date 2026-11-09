//! Deterministic scenario playback: a port of
//! `simulator/powerstroke/lib/src/engine.dart`.
//!
//! The Flutter app runs the Dart engine and the gateway runs this one, so both
//! must produce identical observations for the same scenario and time. The
//! golden test (`tests/golden.rs`) checks that against files the Dart engine
//! wrote.

use crate::scenario::{Fault, FaultKind, Scenario, SignalTrack};

/// What the simulated gateway saw for one request of one signal.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ObservationKind {
    /// A decodable positive response carrying [`Observation::value`].
    Response,
    /// No answer before the timeout.
    NoResponse,
    /// A negative response with [`Observation::nrc`].
    NegativeResponse,
    /// An answer that could not be decoded.
    InvalidResponse,
    /// The diagnostic link itself is down; nothing was sent.
    LinkDown,
}

impl ObservationKind {
    /// Snake-case name (as in the golden files).
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Response => "response",
            Self::NoResponse => "no_response",
            Self::NegativeResponse => "negative_response",
            Self::InvalidResponse => "invalid_response",
            Self::LinkDown => "link_down",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Observation {
    pub signal_id: String,
    /// Milliseconds since the run started (monotonic; does not wrap on loop).
    pub at_ms: u64,
    pub kind: ObservationKind,
    /// Canonical-unit value for [`ObservationKind::Response`].
    pub value: Option<f64>,
    /// Negative response code for [`ObservationKind::NegativeResponse`].
    pub nrc: Option<i64>,
    /// Simulated request→response latency (40–80 ms) for answered requests:
    /// response, negative response and invalid response.
    pub latency_ms: Option<u32>,
}

/// Deterministic scenario playback. Stateless: the same scenario and run time
/// always produce the same observations, however the time range is split
/// across calls.
#[derive(Debug, Clone)]
pub struct ScenarioEngine {
    scenario: Scenario,
}

const MASK32: u64 = 0xffff_ffff;

impl ScenarioEngine {
    /// Upper bound on the window one [`poll`](Self::poll) call generates. A
    /// caller that was suspended for longer skips ahead instead of replaying
    /// a backlog.
    pub const MAX_WINDOW_MS: u64 = 10_000;

    pub fn new(scenario: Scenario) -> Self {
        Self { scenario }
    }

    pub fn scenario(&self) -> &Scenario {
        &self.scenario
    }

    /// Scenario clock for a run time: wraps when looping, otherwise holds at
    /// the end.
    pub fn scenario_seconds(&self, at_ms: u64) -> f64 {
        let s = at_ms as f64 / 1000.0;
        let duration = self.scenario.duration_seconds();
        if self.scenario.looping() {
            dart_modulo(s, duration)
        } else if s > duration {
            duration
        } else {
            s
        }
    }

    /// False while a `link_down` fault is active.
    pub fn link_up_at(&self, at_ms: u64) -> bool {
        let t = self.scenario_seconds(at_ms);
        !self
            .scenario
            .faults()
            .iter()
            .any(|f| f.kind == FaultKind::LinkDown && f.active_at(t))
    }

    /// Every poll scheduled in the half-open window `(from_ms, to_ms]`, in
    /// time order. Poll `k` of a signal happens at `k × interval_ms`. Polls
    /// at the same time keep track order (the sort is stable). A window
    /// longer than [`MAX_WINDOW_MS`](Self::MAX_WINDOW_MS) is cut to its last
    /// `MAX_WINDOW_MS`.
    pub fn poll(&self, from_ms: u64, to_ms: u64) -> Vec<Observation> {
        if to_ms <= from_ms {
            return Vec::new();
        }
        let from_ms = from_ms.max(to_ms.saturating_sub(Self::MAX_WINDOW_MS));
        let mut out = Vec::new();
        for track in self.scenario.tracks() {
            let interval = track.interval_ms();
            let mut k = from_ms / interval + 1;
            while let Some(at_ms) = k.checked_mul(interval).filter(|at| *at <= to_ms) {
                out.push(self.observe_poll(track, k, at_ms));
                k += 1;
            }
        }
        out.sort_by_key(|o| o.at_ms);
        out
    }

    /// What a request for `signal_id` at run time `at_ms` would report. Uses
    /// noise index `k = at_ms / interval_ms` (floor), so a request that lands
    /// on a scheduled poll time returns exactly that poll's observation.
    /// `None` for a signal the scenario does not define.
    pub fn observe(&self, signal_id: &str, at_ms: u64) -> Option<Observation> {
        let track = self.scenario.track(signal_id)?;
        Some(self.observe_poll(track, at_ms / track.interval_ms(), at_ms))
    }

    /// Interpolated value plus deterministic noise for poll `k`, clamped to
    /// the track's limits.
    pub fn value_at(&self, track: &SignalTrack, seconds: f64, k: u64) -> f64 {
        let frames = track.keyframes();
        let (Some(first), Some(last)) = (frames.first(), frames.last()) else {
            // The parser never builds a track without keyframes.
            return f64::NAN;
        };
        let base = if seconds <= first.at_seconds {
            first.value
        } else if seconds >= last.at_seconds {
            last.value
        } else {
            match frames.windows(2).find(|w| w[1].at_seconds >= seconds) {
                Some([a, b]) => {
                    let f = (seconds - a.at_seconds) / (b.at_seconds - a.at_seconds);
                    a.value + (b.value - a.value) * f
                }
                _ => last.value,
            }
        };
        let noise = track.noise();
        let mut v = if noise == 0.0 {
            base
        } else {
            base + noise * (2.0 * self.unit(track.id(), k) - 1.0)
        };
        if let Some(min) = track.min()
            && v < min
        {
            v = min;
        }
        if let Some(max) = track.max()
            && v > max
        {
            v = max;
        }
        v
    }

    fn observe_poll(&self, track: &SignalTrack, k: u64, at_ms: u64) -> Observation {
        let t = self.scenario_seconds(at_ms);
        let id = track.id();
        let first = |kind: FaultKind| -> Option<&Fault> {
            self.scenario
                .faults()
                .iter()
                .find(|f| f.kind == kind && f.active_at(t) && f.affects(id))
        };
        let observation = |kind, value, nrc, latency_ms| Observation {
            signal_id: id.to_owned(),
            at_ms,
            kind,
            value,
            nrc,
            latency_ms,
        };

        // Precedence: link_down, no_response, negative_response,
        // invalid_response, value_override.
        if first(FaultKind::LinkDown).is_some() {
            return observation(ObservationKind::LinkDown, None, None, None);
        }
        if first(FaultKind::NoResponse).is_some() {
            return observation(ObservationKind::NoResponse, None, None, None);
        }
        let latency = 40 + (self.unit(&format!("{id}#lat"), k) * 40.0).round() as u32;
        if let Some(negative) = first(FaultKind::NegativeResponse) {
            return observation(
                ObservationKind::NegativeResponse,
                None,
                negative.nrc,
                Some(latency),
            );
        }
        if first(FaultKind::InvalidResponse).is_some() {
            return observation(ObservationKind::InvalidResponse, None, None, Some(latency));
        }
        let value = first(FaultKind::ValueOverride)
            .and_then(|f| f.value)
            .unwrap_or_else(|| self.value_at(track, t, k));
        observation(ObservationKind::Response, Some(value), None, Some(latency))
    }

    /// Uniform `[0, 1)` from `(seed, key, k)`.
    fn unit(&self, key: &str, k: u64) -> f64 {
        noise_unit(self.scenario.seed(), key, k)
    }
}

/// The Dart engine's `_unit`, bit for bit.
///
/// Dart (VM/AOT) ints are 64-bit two's complement with wrapping `*`; every
/// step masks to 32 bits. `u64` with `wrapping_mul` yields the same bits, and
/// XOR/AND do not care about signedness. Each `>>` is applied to a value
/// already masked to 32 bits (non-negative), so arithmetic and logical shifts
/// agree. Keys are hashed by UTF-16 code unit, like Dart's `codeUnits`.
pub(crate) fn noise_unit(seed: i64, key: &str, k: u64) -> f64 {
    let mut h: u64 = 0x811c_9dc5 ^ (seed as u64);
    for c in key.encode_utf16() {
        h = ((h ^ u64::from(c)).wrapping_mul(0x0100_0193)) & MASK32;
    }
    let mut x = (h ^ k.wrapping_mul(0x9e37_79b1)) & MASK32;
    x = ((x ^ (x >> 16)).wrapping_mul(0x045d_9f3b)) & MASK32;
    x = ((x ^ (x >> 16)).wrapping_mul(0x045d_9f3b)) & MASK32;
    x ^= x >> 16;
    // x < 2^32, so both the conversion and the division are exact.
    x as f64 / 4_294_967_296.0
}

/// Dart's `double % double` (VM `DartModulo`): IEEE `fmod`, then shifted into
/// `[0, |b|)`, with a zero result normalised to `+0.0`.
fn dart_modulo(a: f64, b: f64) -> f64 {
    let r = a % b;
    if r == 0.0 {
        0.0
    } else if r < 0.0 {
        if b < 0.0 { r - b } else { r + b }
    } else {
        r
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dart_modulo_is_euclidean_with_positive_zero() {
        assert_eq!(dart_modulo(12.5, 10.0), 2.5);
        assert_eq!(dart_modulo(-2.5, 10.0), 7.5);
        assert_eq!(dart_modulo(-2.5, -10.0), 7.5);
        assert!(dart_modulo(-10.0, 10.0).is_sign_positive());
    }

    #[test]
    fn noise_unit_masks_after_a_negative_seed_and_empty_key() {
        // With an empty key the 64-bit seed survives to the k mix, as in Dart.
        let u = noise_unit(-1, "", 7);
        assert!((0.0..1.0).contains(&u));
        assert_eq!(u, noise_unit(-1, "", 7));
    }
}
