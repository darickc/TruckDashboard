//! The telemetry model: per-signal state, validity, computed signals, link
//! health, alerts and an event log.
//!
//! A port of `apps/infotainment/lib/telemetry/telemetry_store.dart`, with
//! the same rules, but clock-free: every time is a [`Duration`] since an
//! arbitrary monotonic origin, passed in by the caller. Validity is
//! recomputed from timestamps on every [`TelemetryStore::refresh`], not only
//! when data arrives, so a source that dies still ages every value into
//! `STALE`.
//!
//! A [`SignalState`]'s `value` is `Some` **only** while its validity is
//! `VALID`. A display that wants the last reading must ask for
//! `last_good_value` and show its age, which makes "a frozen number shown as
//! current" impossible to write by accident.

use std::collections::{HashMap, VecDeque};
use std::fmt;
use std::time::Duration;

use crate::calibration::Calibration;
use crate::registry::{Registry, SignalDef};
use crate::warnings::{Alert, AlertKind, AlertLevel, WarningEngine, WarningRule};

/// Whether a sample may be shown as current (telemetry-model.md).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Validity {
    Valid,
    Stale,
    NoData,
    OutOfRange,
    DecodeError,
    Unsupported,
    Disabled,
}

impl fmt::Display for Validity {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Validity::Valid => "VALID",
            Validity::Stale => "STALE",
            Validity::NoData => "NO_DATA",
            Validity::OutOfRange => "OUT_OF_RANGE",
            Validity::DecodeError => "DECODE_ERROR",
            Validity::Unsupported => "UNSUPPORTED",
            Validity::Disabled => "DISABLED",
        })
    }
}

/// One request's outcome, independent of the transport.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Outcome {
    /// A decoded value in the canonical unit, **before** calibration.
    Response(f64),
    NoResponse,
    /// The ECU refused, e.g. `7F 22 31`.
    NegativeResponse {
        nrc: u8,
    },
    /// An answer arrived but could not be decoded.
    InvalidResponse,
    LinkDown,
}

/// [`Outcome`] without its data, as kept in [`SignalState::last_outcome`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum OutcomeKind {
    Response,
    NoResponse,
    NegativeResponse,
    InvalidResponse,
    LinkDown,
}

impl Outcome {
    pub fn kind(&self) -> OutcomeKind {
        match self {
            Outcome::Response(_) => OutcomeKind::Response,
            Outcome::NoResponse => OutcomeKind::NoResponse,
            Outcome::NegativeResponse { .. } => OutcomeKind::NegativeResponse,
            Outcome::InvalidResponse => OutcomeKind::InvalidResponse,
            Outcome::LinkDown => OutcomeKind::LinkDown,
        }
    }
}

/// One request outcome for one signal.
#[derive(Debug, Clone, PartialEq)]
pub struct PollResult {
    pub signal_id: String,
    /// Monotonic time of the response, or of the give-up for failures.
    pub at: Duration,
    pub outcome: Outcome,
    pub latency_ms: Option<u32>,
    /// CAN id of the module that answered.
    pub responder: Option<u32>,
}

impl PollResult {
    pub fn new(signal_id: impl Into<String>, at: Duration, outcome: Outcome) -> Self {
        Self {
            signal_id: signal_id.into(),
            at,
            outcome,
            latency_ms: None,
            responder: None,
        }
    }
}

/// Everything known about one signal right now.
#[derive(Debug, Clone, PartialEq)]
pub struct SignalState {
    pub def: SignalDef,
    pub validity: Validity,
    /// `Some` only while `validity` is `Valid`.
    pub value: Option<f64>,
    /// Last reading that passed validation (calibrated), and when it was
    /// measured.
    pub last_good_value: Option<f64>,
    pub last_good_at: Option<Duration>,
    /// The decoded value before calibration, for the last good reading.
    pub last_good_raw: Option<f64>,
    /// Most recent request outcome of any kind.
    pub last_outcome: Option<OutcomeKind>,
    pub last_outcome_at: Option<Duration>,
    pub last_nrc: Option<u8>,
    pub last_responder: Option<u32>,
    pub last_latency_ms: Option<u32>,
    /// The latest response, when it was outside the plausible range
    /// (calibrated). Cleared by the next good one.
    pub last_rejected_value: Option<f64>,
    pub successes: u64,
    pub failures: u64,
    pub consecutive_failures: u64,
    /// Computed signals: ids of inputs that are not valid.
    pub invalid_inputs: Vec<String>,
}

impl SignalState {
    fn new(def: SignalDef) -> Self {
        let mut s = Self {
            def,
            validity: Validity::NoData,
            value: None,
            last_good_value: None,
            last_good_at: None,
            last_good_raw: None,
            last_outcome: None,
            last_outcome_at: None,
            last_nrc: None,
            last_responder: None,
            last_latency_ms: None,
            last_rejected_value: None,
            successes: 0,
            failures: 0,
            consecutive_failures: 0,
            invalid_inputs: Vec::new(),
        };
        s.reset();
        s
    }

    /// Age of the last good reading at `now`.
    pub fn age_at(&self, now: Duration) -> Option<Duration> {
        self.last_good_at.map(|t| now.saturating_sub(t))
    }

    pub fn is_valid(&self) -> bool {
        self.validity == Validity::Valid
    }

    fn reset(&mut self) {
        self.validity = if self.def.enabled {
            Validity::NoData
        } else {
            Validity::Disabled
        };
        self.value = None;
        self.last_good_value = None;
        self.last_good_raw = None;
        self.last_rejected_value = None;
        self.last_good_at = None;
        self.last_outcome_at = None;
        self.last_outcome = None;
        self.last_nrc = None;
        self.last_latency_ms = None;
        self.last_responder = None;
        self.successes = 0;
        self.failures = 0;
        self.consecutive_failures = 0;
        self.invalid_inputs.clear();
    }

    fn record_failure(&mut self) {
        self.failures += 1;
        self.consecutive_failures += 1;
    }
}

/// Health of the vehicle-data link.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum LinkState {
    /// Nothing heard yet.
    Connecting,
    /// Requests are being answered.
    Up,
    /// Up, but some watched signals are not updating.
    Degraded,
    /// No vehicle data at all.
    Down,
}

impl fmt::Display for LinkState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            LinkState::Connecting => "connecting",
            LinkState::Up => "up",
            LinkState::Degraded => "degraded",
            LinkState::Down => "down",
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum EventSeverity {
    Info,
    Advisory,
    Critical,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TelemetryEvent {
    /// Monotonic time. The caller stamps wall time when it persists events.
    pub at: Duration,
    pub severity: EventSeverity,
    pub message: String,
}

/// Bounded, newest-first event history, so a flapping signal can't grow
/// memory without limit.
#[derive(Debug, Clone)]
pub struct EventLog {
    capacity: usize,
    events: VecDeque<TelemetryEvent>,
    dropped: u64,
}

impl EventLog {
    pub const DEFAULT_CAPACITY: usize = 300;

    pub fn new(capacity: usize) -> Self {
        Self {
            capacity,
            events: VecDeque::new(),
            dropped: 0,
        }
    }

    pub fn capacity(&self) -> usize {
        self.capacity
    }

    pub fn len(&self) -> usize {
        self.events.len()
    }

    pub fn is_empty(&self) -> bool {
        self.events.is_empty()
    }

    /// Events evicted to stay within capacity.
    pub fn dropped(&self) -> u64 {
        self.dropped
    }

    pub fn newest_first(&self) -> impl Iterator<Item = &TelemetryEvent> {
        self.events.iter()
    }

    pub fn add(&mut self, event: TelemetryEvent) {
        self.events.push_front(event);
        while self.events.len() > self.capacity {
            self.events.pop_back();
            self.dropped += 1;
        }
    }

    pub fn clear(&mut self) {
        self.events.clear();
        self.dropped = 0;
    }
}

impl Default for EventLog {
    fn default() -> Self {
        Self::new(Self::DEFAULT_CAPACITY)
    }
}

/// Store construction options.
#[derive(Debug, Clone)]
pub struct StoreConfig {
    pub rules: Vec<WarningRule>,
    /// Signals whose silence raises a "not updating" alert.
    pub watched_signals: Vec<String>,
    /// With no response of any kind for this long, the link is down.
    pub link_lost_after: Duration,
    pub event_capacity: usize,
}

impl Default for StoreConfig {
    fn default() -> Self {
        Self {
            rules: Vec::new(),
            watched_signals: Vec::new(),
            link_lost_after: Duration::from_secs(3),
            event_capacity: EventLog::DEFAULT_CAPACITY,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum StoreError {
    #[error("unknown signal {0:?}")]
    UnknownSignal(String),
    #[error("{0:?} is computed; computed signals follow their inputs, calibrate those")]
    ComputedNotCalibrated(String),
}

/// Window for [`TelemetryStore::requests_per_second`].
const RATE_WINDOW: Duration = Duration::from_secs(10);

/// The model of the vehicle.
#[derive(Debug, Clone)]
pub struct TelemetryStore {
    states: Vec<SignalState>,
    index: HashMap<String, usize>,
    calibrations: HashMap<String, Calibration>,
    warnings: WarningEngine,
    watched_signals: Vec<String>,
    link_lost_after: Duration,
    events: EventLog,
    link: LinkState,
    link_since: Duration,
    started_at: Duration,
    source_reports_link_down: bool,
    last_any_response: Option<Duration>,
    alerts: Vec<Alert>,
    recent_requests: VecDeque<Duration>,
}

impl TelemetryStore {
    /// A store over every signal of `registry`, started at `now`.
    /// Calibrations come from the registry's `calibration` blocks.
    pub fn new(registry: &Registry, config: StoreConfig, now: Duration) -> Self {
        let states: Vec<SignalState> = registry.iter().cloned().map(SignalState::new).collect();
        let index = states
            .iter()
            .enumerate()
            .map(|(i, s)| (s.def.id.clone(), i))
            .collect();
        let calibrations = registry
            .iter()
            .filter_map(|d| d.calibration.clone().map(|c| (d.id.clone(), c)))
            .collect();
        Self {
            states,
            index,
            calibrations,
            warnings: WarningEngine::new(config.rules),
            watched_signals: config.watched_signals,
            link_lost_after: config.link_lost_after,
            events: EventLog::new(config.event_capacity),
            link: LinkState::Connecting,
            link_since: now,
            started_at: now,
            source_reports_link_down: false,
            last_any_response: None,
            alerts: Vec::new(),
            recent_requests: VecDeque::new(),
        }
    }

    pub fn get(&self, id: &str) -> Option<&SignalState> {
        self.index.get(id).and_then(|&i| self.states.get(i))
    }

    /// Signals in registry order.
    pub fn ordered(&self) -> impl Iterator<Item = &SignalState> {
        self.states.iter()
    }

    /// Current value of `id`, only while it is valid.
    pub fn value(&self, id: &str) -> Option<f64> {
        self.get(id).and_then(|s| s.value)
    }

    pub fn link(&self) -> LinkState {
        self.link
    }

    pub fn link_since(&self) -> Duration {
        self.link_since
    }

    pub fn link_lost_after(&self) -> Duration {
        self.link_lost_after
    }

    /// Active alerts, critical first, then oldest first.
    pub fn alerts(&self) -> &[Alert] {
        &self.alerts
    }

    pub fn events(&self) -> &EventLog {
        &self.events
    }

    pub fn warnings(&self) -> &WarningEngine {
        &self.warnings
    }

    /// Requests per second over the last 10 s.
    pub fn requests_per_second(&mut self, now: Duration) -> f64 {
        self.trim_requests(now);
        self.recent_requests.len() as f64 / RATE_WINDOW.as_secs_f64()
    }

    fn trim_requests(&mut self, now: Duration) {
        while self
            .recent_requests
            .front()
            .is_some_and(|&t| now.saturating_sub(t) > RATE_WINDOW)
        {
            self.recent_requests.pop_front();
        }
    }

    pub fn calibration_of(&self, id: &str) -> Calibration {
        self.calibrations
            .get(id)
            .cloned()
            .unwrap_or(Calibration::IDENTITY)
    }

    /// Changes a signal's calibration at runtime. The last good reading is
    /// rescaled from its raw value, so the display changes at once instead of
    /// mixing old and new factors. Refreshes the model.
    pub fn set_calibration(
        &mut self,
        id: &str,
        calibration: Calibration,
        now: Duration,
    ) -> Result<(), StoreError> {
        let &i = self
            .index
            .get(id)
            .ok_or_else(|| StoreError::UnknownSignal(id.to_owned()))?;
        let Some(s) = self.states.get_mut(i) else {
            return Err(StoreError::UnknownSignal(id.to_owned()));
        };
        if s.def.is_computed() {
            return Err(StoreError::ComputedNotCalibrated(id.to_owned()));
        }
        if let Some(raw) = s.last_good_raw {
            s.last_good_value = Some(calibration.apply(raw));
        }
        let message = format!("{} calibration {calibration}", s.def.short_name);
        self.calibrations.insert(id.to_owned(), calibration);
        self.events.add(TelemetryEvent {
            at: now,
            severity: EventSeverity::Info,
            message,
        });
        self.refresh(now);
        Ok(())
    }

    /// Clears every reading, counter, alert and event.
    pub fn reset(&mut self, now: Duration) {
        for s in &mut self.states {
            s.reset();
        }
        self.warnings.reset();
        self.events.clear();
        self.recent_requests.clear();
        self.alerts.clear();
        self.last_any_response = None;
        self.source_reports_link_down = false;
        self.link = LinkState::Connecting;
        self.link_since = now;
        self.started_at = now;
    }

    /// Records one request outcome; call [`TelemetryStore::refresh`] after.
    /// Returns `false` (and changes nothing) for unknown, disabled and
    /// computed signals.
    pub fn apply(&mut self, r: &PollResult) -> bool {
        let Some(&i) = self.index.get(&r.signal_id) else {
            return false;
        };
        let calibration = self.calibration_of(&r.signal_id);
        let Some(s) = self.states.get_mut(i) else {
            return false;
        };
        if !s.def.enabled || s.def.is_computed() {
            return false;
        }
        if r.outcome != Outcome::LinkDown {
            self.recent_requests.push_back(r.at);
        }
        s.last_outcome = Some(r.outcome.kind());
        s.last_outcome_at = Some(r.at);
        if r.latency_ms.is_some() {
            s.last_latency_ms = r.latency_ms;
        }
        if r.responder.is_some() {
            s.last_responder = r.responder;
        }
        match r.outcome {
            Outcome::Response(raw) => {
                let v = calibration.apply(raw);
                self.last_any_response = Some(r.at);
                if s.def.range.contains(v) {
                    s.last_good_value = Some(v);
                    s.last_good_raw = Some(raw);
                    s.last_good_at = Some(r.at);
                    s.last_rejected_value = None;
                    s.successes += 1;
                    s.consecutive_failures = 0;
                } else {
                    s.last_rejected_value = Some(v);
                    s.record_failure();
                }
            }
            Outcome::NegativeResponse { nrc } => {
                // The module answered, so the link works.
                self.last_any_response = Some(r.at);
                s.last_nrc = Some(nrc);
                s.record_failure();
            }
            Outcome::InvalidResponse => {
                self.last_any_response = Some(r.at);
                s.record_failure();
            }
            Outcome::NoResponse | Outcome::LinkDown => s.record_failure(),
        }
        self.trim_requests(r.at);
        true
    }

    /// The data source's own view of the link (e.g. the adapter
    /// disconnected).
    pub fn set_source_link_down(&mut self, down: bool) {
        self.source_reports_link_down = down;
    }

    /// Recomputes validity, computed signals, link state and alerts at `now`.
    pub fn refresh(&mut self, now: Duration) {
        for i in 0..self.states.len() {
            if self.states.get(i).is_some_and(|s| !s.def.is_computed()) {
                self.update_validity(i, now);
            }
        }
        for i in 0..self.states.len() {
            if self.states.get(i).is_some_and(|s| s.def.is_computed()) {
                self.update_computed(i, now);
            }
        }
        self.update_link(now);
        self.update_alerts(now);
    }

    fn update_validity(&mut self, i: usize, now: Duration) {
        let Some(s) = self.states.get_mut(i) else {
            return;
        };
        let before = s.validity;
        let next = if !s.def.enabled {
            Validity::Disabled
        } else if s.last_rejected_value.is_some() && s.last_outcome == Some(OutcomeKind::Response) {
            // The latest answer was implausible. Say so; the last good value
            // must not stand in for it, however recent.
            Validity::OutOfRange
        } else if let Some(at) = s.last_good_at {
            match s.def.stale_after {
                Some(limit) if now.saturating_sub(at) <= limit => Validity::Valid,
                // No staleness limit can't happen after validation; never
                // call a reading current without one.
                _ => Validity::Stale,
            }
        } else {
            match s.last_outcome {
                Some(OutcomeKind::NegativeResponse) => Validity::Unsupported,
                Some(OutcomeKind::InvalidResponse) => Validity::DecodeError,
                _ => Validity::NoData,
            }
        };
        s.validity = next;
        s.value = if next == Validity::Valid {
            s.last_good_value
        } else {
            None
        };
        let short = s.def.short_name.clone();
        self.log_transition(&short, before, next, now);
    }

    fn update_computed(&mut self, i: usize, now: Duration) {
        let Some(def) = self.states.get(i).map(|s| &s.def) else {
            return;
        };
        // (id, validity, value, last_good_at) per input.
        let inputs: Vec<(String, Validity, Option<f64>, Option<Duration>)> = def
            .inputs
            .iter()
            .map(|id| match self.get(id) {
                Some(s) => (id.clone(), s.validity, s.value, s.last_good_at),
                // Validation guarantees inputs exist; treat a missing one as
                // never heard from.
                None => (id.clone(), Validity::NoData, None, None),
            })
            .collect();
        let bad: Vec<String> = inputs
            .iter()
            .filter(|(_, v, _, _)| *v != Validity::Valid)
            .map(|(id, ..)| id.clone())
            .collect();
        let enabled = def.enabled;
        let skew_limit = def.input_skew_limit();

        let times: Vec<Duration> = inputs.iter().filter_map(|(.., t)| *t).collect();
        let mut next = if !enabled {
            Validity::Disabled
        } else if !bad.is_empty() {
            worst(
                inputs
                    .iter()
                    .filter(|(_, v, _, _)| *v != Validity::Valid)
                    .map(|(_, v, _, _)| *v),
            )
        } else {
            match (times.iter().min(), times.iter().max()) {
                (Some(first), Some(last)) if times.len() == inputs.len() => {
                    if last.saturating_sub(*first) > skew_limit {
                        Validity::Stale
                    } else {
                        Validity::Valid
                    }
                }
                _ => Validity::Stale,
            }
        };

        let mut value = None;
        if next == Validity::Valid {
            let lookup = |id: &str| {
                inputs
                    .iter()
                    .find(|(input, ..)| input == id)
                    .and_then(|(_, _, v, _)| *v)
            };
            let result = def.compute.as_ref().map(|f| f.eval(&[], &lookup));
            match result {
                Some(Ok(v)) if def.range.contains(v) => value = Some(v),
                _ => next = Validity::OutOfRange,
            }
        }
        let oldest_input = times.iter().min().copied();

        let Some(s) = self.states.get_mut(i) else {
            return;
        };
        let before = s.validity;
        s.invalid_inputs = bad;
        s.validity = next;
        s.value = value;
        if value.is_some() {
            s.last_good_value = value;
            s.last_good_at = oldest_input;
        }
        let short = s.def.short_name.clone();
        self.log_transition(&short, before, next, now);
    }

    fn update_link(&mut self, now: Duration) {
        let before = self.link;
        let next = if self.source_reports_link_down {
            LinkState::Down
        } else {
            match self.last_any_response {
                // Never answered: a grace period after start before "down".
                None => {
                    if now.saturating_sub(self.started_at) > self.link_lost_after {
                        LinkState::Down
                    } else {
                        LinkState::Connecting
                    }
                }
                Some(last) if now.saturating_sub(last) > self.link_lost_after => LinkState::Down,
                Some(_) => {
                    let degraded = self
                        .watched_signals
                        .iter()
                        .any(|id| self.get(id).is_some_and(|s| !s.is_valid()));
                    if degraded {
                        LinkState::Degraded
                    } else {
                        LinkState::Up
                    }
                }
            }
        };
        if next != before {
            self.link = next;
            self.link_since = now;
            self.events.add(TelemetryEvent {
                at: now,
                severity: if next == LinkState::Down {
                    EventSeverity::Critical
                } else {
                    EventSeverity::Info
                },
                message: format!("Link {before} → {next}"),
            });
        }
    }

    fn update_alerts(&mut self, now: Duration) {
        let states = &self.states;
        let index = &self.index;
        let valid_value = |id: &str| -> Option<f64> {
            index
                .get(id)
                .and_then(|&i| states.get(i))
                .and_then(|s| s.value)
        };
        let (thresholds, changes) = self.warnings.evaluate(&valid_value, now);
        for change in changes {
            self.events.add(TelemetryEvent {
                at: now,
                severity: match change.to {
                    AlertLevel::Critical => EventSeverity::Critical,
                    AlertLevel::Advisory => EventSeverity::Advisory,
                    AlertLevel::None => EventSeverity::Info,
                },
                message: format!(
                    "Warning {}: {} → {}",
                    change.rule_id, change.from, change.to
                ),
            });
        }
        let mut alerts = Vec::new();
        if self.link == LinkState::Down {
            alerts.push(Alert {
                id: "link".into(),
                kind: AlertKind::LinkLost,
                level: AlertLevel::Critical,
                since: self.link_since,
                signal_id: None,
                rule_id: None,
                threshold: None,
                direction: None,
            });
        } else if self.link != LinkState::Connecting {
            for id in &self.watched_signals {
                let Some(s) = self.get(id) else { continue };
                if !s.def.enabled || s.is_valid() {
                    continue;
                }
                alerts.push(Alert {
                    id: format!("stale:{id}"),
                    kind: AlertKind::SignalNotUpdating,
                    level: AlertLevel::Advisory,
                    since: s.last_good_at.unwrap_or(self.link_since),
                    signal_id: Some(id.clone()),
                    rule_id: None,
                    threshold: None,
                    direction: None,
                });
            }
        }
        alerts.extend(thresholds);
        alerts.sort_by(|a, b| b.level.cmp(&a.level).then(a.since.cmp(&b.since)));
        self.alerts = alerts;
    }

    fn log_transition(&mut self, short_name: &str, from: Validity, to: Validity, now: Duration) {
        // Start-up noise (NO_DATA → VALID) is not worth a log line.
        if from == to || (from == Validity::NoData && to == Validity::Valid) {
            return;
        }
        self.events.add(TelemetryEvent {
            at: now,
            severity: if to == Validity::Valid {
                EventSeverity::Info
            } else {
                EventSeverity::Advisory
            },
            message: format!("{short_name}: {from} → {to}"),
        });
    }
}

/// The worst of several non-valid validities, in the Flutter app's order.
fn worst(validities: impl Iterator<Item = Validity> + Clone) -> Validity {
    const RANK: [Validity; 6] = [
        Validity::Disabled,
        Validity::NoData,
        Validity::Unsupported,
        Validity::DecodeError,
        Validity::Stale,
        Validity::OutOfRange,
    ];
    RANK.into_iter()
        .find(|r| validities.clone().any(|v| v == *r))
        .unwrap_or(Validity::Stale)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn worst_follows_the_dart_ranking() {
        use Validity::*;
        assert_eq!(worst([Stale, NoData].into_iter()), NoData);
        assert_eq!(worst([OutOfRange, Stale].into_iter()), Stale);
        assert_eq!(worst([OutOfRange, Disabled].into_iter()), Disabled);
        assert_eq!(worst([Unsupported, DecodeError].into_iter()), Unsupported);
        assert_eq!(worst([Valid].into_iter()), Stale);
    }

    #[test]
    fn event_log_is_bounded_newest_first() {
        let mut log = EventLog::new(3);
        for i in 0..5u64 {
            log.add(TelemetryEvent {
                at: Duration::from_secs(i),
                severity: EventSeverity::Info,
                message: format!("{i}"),
            });
        }
        assert_eq!(log.len(), 3);
        assert_eq!(log.dropped(), 2);
        let order: Vec<_> = log.newest_first().map(|e| e.message.as_str()).collect();
        assert_eq!(order, ["4", "3", "2"]);
        log.clear();
        assert!(log.is_empty());
        assert_eq!(log.dropped(), 0);
    }
}
