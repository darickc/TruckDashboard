//! Day/night and the backlight ([ADR-0028](../../../docs/architecture/adr/0028-day-night-and-backlight.md)).
//!
//! [`DisplayState`] is the logic, with no I/O and no clock of its own: the
//! driver's settings, the sun's day/night (`crates/daylight`), and what the
//! backlight writer reported. [`run`] is the task around it: it re-evaluates
//! every [`EVALUATE_EVERY`], takes the dashboard's changes, keeps the
//! settings in a file, sends targets to the backlight thread and publishes
//! the state for `WatchDisplay`.
//!
//! The location and the clock for the sun come from GPS when there is one
//! ([`crate::gps`], ADR-0028 amendment); the snapshot says which.
//!
//! Nothing here can hold up the power key: the clock check (`timedatectl`)
//! and the files run on the blocking pool, and the backlight on its own
//! thread.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};

use daylight::brightness::{Levels, clamp_pct, pct_of, raw_for};
use daylight::prefs::Prefs;
use daylight::{
    Basis, Choice, DayNight, Decision, Location, Mode, SunState, Thresholds, Unavailable,
};
use f250_proto::nav::v1 as nav;
use f250_proto::power::v1 as pb;
use tokio::sync::{mpsc, oneshot, watch};

use crate::backlight::{Report, Writer};
use crate::gps::{GpsInput, Located, LocationSource};

/// How often the sun is looked at again. It moves about a quarter of a
/// degree a minute at most.
pub const EVALUATE_EVERY: Duration = Duration::from_secs(30);

/// Which clock the sun was worked out from.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClockSource {
    None,
    System,
    Gps,
    Trusted,
}

impl ClockSource {
    pub fn to_pb(self) -> pb::ClockSource {
        match self {
            ClockSource::None => pb::ClockSource::None,
            ClockSource::System => pb::ClockSource::System,
            ClockSource::Gps => pb::ClockSource::Gps,
            ClockSource::Trusted => pb::ClockSource::Trusted,
        }
    }
}

/// The system's wall clock, read off the loop.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SystemClock {
    /// Seconds since 1970 (UTC).
    pub unix: f64,
    /// The system reports it synchronized.
    pub synchronized: bool,
}

/// When the clock counts as trustworthy (ADR-0028 decision 3).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TrustClock {
    /// Only while the system reports it synchronized.
    Synchronized,
    /// Always (the bench, or once the RTC cell is verified, H20). A clock
    /// before 2026 is still never believed.
    Always,
}

impl TrustClock {
    pub fn parse(s: &str) -> Option<Self> {
        match s.trim() {
            "synchronized" | "synced" | "" => Some(TrustClock::Synchronized),
            "always" => Some(TrustClock::Always),
            _ => None,
        }
    }
}

/// The display settings as they come from `/etc/default/f250`, unparsed.
/// A bad value must never stop power-manager (the power key matters more):
/// [`RawSettings::resolve`] keeps the default for it and says so.
#[derive(Debug, Clone, Default)]
pub struct RawSettings {
    pub latitude: Option<String>,
    pub longitude: Option<String>,
    pub night_below_deg: Option<String>,
    pub hysteresis_deg: Option<String>,
    pub fallback: Option<String>,
    pub trust_clock: Option<String>,
    pub min_brightness_pct: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Settings {
    pub location: Option<Location>,
    pub thresholds: Thresholds,
    pub fallback: Mode,
    pub trust: TrustClock,
    pub min_pct: u8,
}

/// A setting's value, unless it is missing or blank (an empty line in
/// `/etc/default/f250`).
fn given(v: &Option<String>) -> Option<&str> {
    v.as_deref().map(str::trim).filter(|s| !s.is_empty())
}

/// Example value (ADR-0028): the screen never goes below it.
pub const DEFAULT_MIN_PCT: u8 = 10;

impl RawSettings {
    /// The settings, and a note for each value that was ignored.
    pub fn resolve(&self) -> (Settings, Vec<String>) {
        let mut notes = Vec::new();
        let mut num = |name: &str, v: &Option<String>| -> Option<f64> {
            let s = given(v)?;
            match s.parse::<f64>() {
                Ok(x) if x.is_finite() => Some(x),
                _ => {
                    notes.push(format!("{name} {s:?} isn't a number: ignored"));
                    None
                }
            }
        };
        let lat = num("latitude", &self.latitude);
        let lon = num("longitude", &self.longitude);
        let night = num("night threshold", &self.night_below_deg);
        let hyst = num("hysteresis", &self.hysteresis_deg);
        let location = match (lat, lon) {
            (Some(lat), Some(lon)) => match Location::new(lat, lon) {
                Ok(l) => Some(l),
                Err(e) => {
                    notes.push(format!("{e}: no location"));
                    None
                }
            },
            (None, None) => None,
            _ => {
                notes.push("latitude and longitude go together: no location".to_string());
                None
            }
        };
        let mut thresholds = Thresholds::default();
        if let Some(n) = night {
            thresholds.night_below_deg = n;
        }
        if let Some(h) = hyst {
            thresholds.hysteresis_deg = h;
        }
        if let Err(e) = thresholds.validate() {
            notes.push(format!("{e}: the defaults"));
            thresholds = Thresholds::default();
        }
        let fallback = match given(&self.fallback) {
            None => Mode::Day,
            Some(s) => Mode::parse(s).unwrap_or_else(|| {
                notes.push(format!("fallback {s:?} must be day or night: day"));
                Mode::Day
            }),
        };
        let trust = match given(&self.trust_clock) {
            None => TrustClock::Synchronized,
            Some(s) => TrustClock::parse(s).unwrap_or_else(|| {
                notes.push(format!(
                    "trust-clock {s:?} must be synchronized or always: synchronized"
                ));
                TrustClock::Synchronized
            }),
        };
        let min_pct = match given(&self.min_brightness_pct) {
            None => DEFAULT_MIN_PCT,
            Some(s) => match s.parse::<u8>() {
                Ok(p) if (1..=100).contains(&p) => p,
                _ => {
                    notes.push(format!(
                        "minimum brightness {s:?} must be 1 to 100 %: {DEFAULT_MIN_PCT}"
                    ));
                    DEFAULT_MIN_PCT
                }
            },
        };
        (
            Settings {
                location,
                thresholds,
                fallback,
                trust,
                min_pct,
            },
            notes,
        )
    }
}

/// The backlight as the state knows it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BacklightInfo {
    pub name: String,
    pub max: u32,
}

/// A change from the API. `None`: unchanged.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Change {
    pub choice: Option<Choice>,
    pub day_pct: Option<u32>,
    pub night_pct: Option<u32>,
}

#[derive(Debug, Clone)]
pub struct DisplayState {
    /// DISPLAY_LATITUDE/LONGITUDE: the last resort.
    configured: Option<Location>,
    gps: GpsInput,
    trust: TrustClock,
    day_night: DayNight,
    min_pct: u8,
    prefs: Prefs,
    backlight: Option<BacklightInfo>,
    /// Why the backlight isn't following; `None` when it is.
    problem: Option<String>,
    decision: Option<Decision>,
    /// Where the location and the clock came from at the last evaluation.
    located: Option<Located>,
    clock: Option<ClockSource>,
}

impl DisplayState {
    /// `configured`: DISPLAY_LATITUDE/LONGITUDE; `gps`: navigation's
    /// positions and the saved one. `backlight`: the device found, or why
    /// there is none.
    pub fn new(
        configured: Option<Location>,
        gps: GpsInput,
        trust: TrustClock,
        day_night: DayNight,
        min_pct: u8,
        prefs: Prefs,
        backlight: Result<BacklightInfo, String>,
    ) -> Self {
        let min_pct = min_pct.clamp(1, 100);
        let (backlight, problem) = match backlight {
            Ok(b) => (Some(b), None),
            Err(e) => (None, Some(e)),
        };
        Self {
            configured,
            gps,
            trust,
            day_night,
            min_pct,
            prefs: Prefs {
                levels: prefs.levels.clamped(min_pct),
                ..prefs
            },
            backlight,
            problem,
            decision: None,
            located: None,
            clock: None,
        }
    }

    /// Takes a position from navigation; a position to save, if any.
    pub fn position(&mut self, p: &nav::Position, at: Instant) -> Option<Location> {
        self.gps.position(p, at)
    }

    /// Where the location and the clock would come from at `now`: a change
    /// is worth evaluating at once rather than at the next tick.
    pub fn sources(&self, sys: SystemClock, now: Instant) -> (LocationSource, ClockSource) {
        (
            self.gps.locate(self.configured, now).source,
            self.clock_at(sys, now).2,
        )
    }

    /// The time for the sun, whether it is believed, and why.
    fn clock_at(&self, sys: SystemClock, now: Instant) -> (f64, bool, ClockSource) {
        if sys.synchronized {
            (sys.unix, true, ClockSource::System)
        } else if let Some(t) = self.gps.utc_now(now) {
            (t, true, ClockSource::Gps)
        } else if self.trust == TrustClock::Always {
            (sys.unix, true, ClockSource::Trusted)
        } else {
            (sys.unix, false, ClockSource::None)
        }
    }

    pub fn prefs(&self) -> Prefs {
        self.prefs
    }

    /// Applies a change; whether the settings changed.
    pub fn apply(&mut self, c: Change) -> bool {
        let before = self.prefs;
        if let Some(choice) = c.choice {
            self.prefs.choice = choice;
        }
        if let Some(p) = c.day_pct {
            self.prefs.levels.day_pct = clamp_pct(p, self.min_pct);
        }
        if let Some(p) = c.night_pct {
            self.prefs.levels.night_pct = clamp_pct(p, self.min_pct);
        }
        self.prefs != before
    }

    /// Decides the mode with the system clock `sys` at monotonic `now`.
    pub fn evaluate(&mut self, sys: SystemClock, now: Instant) -> Decision {
        let located = self.gps.locate(self.configured, now);
        let (now_unix, trusted, clock) = self.clock_at(sys, now);
        let d = self
            .day_night
            .decide(self.prefs.choice, located.location, trusted, now_unix);
        self.decision = Some(d);
        self.located = Some(located);
        self.clock = Some(clock);
        d
    }

    /// The device value for the current mode, if there is a backlight and a
    /// decision.
    pub fn target_raw(&self) -> Option<u32> {
        let (b, d) = (self.backlight.as_ref()?, self.decision?);
        Some(raw_for(self.prefs.levels.for_mode(d.mode), b.max))
    }

    /// What the writer thread said. A finished ramp clears a write problem;
    /// "no backlight" can't be cleared this way.
    pub fn report(&mut self, r: Report) {
        if self.backlight.is_none() {
            return;
        }
        self.problem = match r {
            Report::At(_) => None,
            Report::Failed(e) => Some(e),
        };
    }

    pub fn problem(&self) -> Option<&str> {
        self.problem.as_deref()
    }

    pub fn snapshot(&self) -> pb::Display {
        let levels: Levels = self.prefs.levels;
        let mut out = pb::Display {
            choice: choice_to_pb(self.prefs.choice) as i32,
            day_brightness_pct: u32::from(levels.day_pct),
            night_brightness_pct: u32::from(levels.night_pct),
            min_brightness_pct: u32::from(self.min_pct),
            backlight_present: self.backlight.is_some(),
            backlight: self
                .backlight
                .as_ref()
                .map(|b| b.name.clone())
                .unwrap_or_default(),
            backlight_problem: self.problem.clone().unwrap_or_default(),
            ..Default::default()
        };
        if let Some(d) = self.decision {
            out.mode = mode_to_pb(d.mode) as i32;
            out.basis = match d.basis {
                Basis::Sun => pb::ModeBasis::Sun,
                Basis::Manual => pb::ModeBasis::Manual,
                Basis::Fallback => pb::ModeBasis::Fallback,
            } as i32;
            out.sun = match d.sun {
                SunState::Known { elevation_deg, .. } => {
                    out.sun_elevation_deg = elevation_deg;
                    pb::SunStatus::Known
                }
                SunState::Unknown(Unavailable::NoLocation) => pb::SunStatus::NoLocation,
                SunState::Unknown(Unavailable::ClockNotSynchronized) => {
                    pb::SunStatus::ClockNotSynchronized
                }
                SunState::Unknown(Unavailable::ClockImplausible) => pb::SunStatus::ClockNotSet,
            } as i32;
            if let Some(l) = self.located {
                out.location_source = l.source.to_pb() as i32;
                out.location_age_s = l.age.map_or(0, |a| a.as_secs());
            }
            if let Some(c) = self.clock {
                out.clock_source = c.to_pb() as i32;
            }
            out.brightness_pct = u32::from(levels.for_mode(d.mode));
            if let Some(b) = &self.backlight {
                // What the device will actually get, after rounding.
                out.brightness_pct =
                    u32::from(pct_of(raw_for(levels.for_mode(d.mode), b.max), b.max));
            }
        }
        out
    }
}

pub fn choice_to_pb(c: Choice) -> pb::DisplayChoice {
    match c {
        Choice::Auto => pb::DisplayChoice::Auto,
        Choice::Day => pb::DisplayChoice::Day,
        Choice::Night => pb::DisplayChoice::Night,
    }
}

pub fn choice_from_pb(v: i32) -> Option<Choice> {
    match pb::DisplayChoice::try_from(v).ok()? {
        pb::DisplayChoice::Auto => Some(Choice::Auto),
        pb::DisplayChoice::Day => Some(Choice::Day),
        pb::DisplayChoice::Night => Some(Choice::Night),
        pb::DisplayChoice::Unspecified => None,
    }
}

fn mode_to_pb(m: Mode) -> pb::DisplayMode {
    match m {
        Mode::Day => pb::DisplayMode::Day,
        Mode::Night => pb::DisplayMode::Night,
    }
}

/// One line for the log.
pub fn describe(d: &pb::Display) -> String {
    let mode = if d.mode == pb::DisplayMode::Night as i32 {
        "night"
    } else {
        "day"
    };
    let why = match pb::ModeBasis::try_from(d.basis).unwrap_or_default() {
        pb::ModeBasis::Sun => format!(
            "auto, sun {:.1}° ({}, {})",
            d.sun_elevation_deg,
            describe_location(d),
            describe_clock(d)
        ),
        pb::ModeBasis::Manual => "chosen by hand".to_string(),
        pb::ModeBasis::Fallback => format!(
            "auto unavailable ({}): the fallback",
            match pb::SunStatus::try_from(d.sun).unwrap_or_default() {
                pb::SunStatus::NoLocation => "no GPS position, none configured",
                pb::SunStatus::ClockNotSynchronized => "clock not synchronized, no GPS time",
                pb::SunStatus::ClockNotSet => "clock not set",
                _ => "sun unknown",
            }
        ),
        pb::ModeBasis::Unspecified => "undecided".to_string(),
    };
    let light = if d.backlight_present {
        format!("backlight {} at {} %", d.backlight, d.brightness_pct)
    } else {
        "no backlight".to_string()
    };
    let problem = if d.backlight_problem.is_empty() {
        String::new()
    } else {
        format!(" ({})", d.backlight_problem)
    };
    format!("{mode}: {why}; {light}{problem}")
}

fn describe_location(d: &pb::Display) -> String {
    let what = match pb::LocationSource::try_from(d.location_source).unwrap_or_default() {
        pb::LocationSource::Gps => "GPS position",
        pb::LocationSource::GpsSaved => "saved GPS position",
        pb::LocationSource::Configured => "configured location",
        pb::LocationSource::GpsSimulated => "SIMULATED GPS position",
        pb::LocationSource::None | pb::LocationSource::Unspecified => "no location",
    };
    // Minutes: the log line changes only when something worth reading does.
    match pb::LocationSource::try_from(d.location_source).unwrap_or_default() {
        pb::LocationSource::Gps | pb::LocationSource::GpsSimulated if d.location_age_s >= 60 => {
            format!("{what} {} min old", d.location_age_s / 60)
        }
        _ => what.to_string(),
    }
}

fn describe_clock(d: &pb::Display) -> &'static str {
    match pb::ClockSource::try_from(d.clock_source).unwrap_or_default() {
        pb::ClockSource::System => "synchronized clock",
        pb::ClockSource::Gps => "GPS time",
        pb::ClockSource::Trusted => "clock trusted by configuration",
        pb::ClockSource::None | pb::ClockSource::Unspecified => "no clock",
    }
}

/// A request from the API.
pub struct Command {
    pub change: Change,
    pub source: String,
    pub reply: oneshot::Sender<pb::Display>,
}

/// Reads the settings file; defaults (and a note) if it is missing or bad.
pub fn load_prefs(path: Option<&Path>) -> (Prefs, Vec<String>) {
    let Some(path) = path else {
        return (Prefs::default(), Vec::new());
    };
    match std::fs::read_to_string(path) {
        Ok(text) => {
            let (p, notes) = Prefs::parse(&text);
            let notes = notes
                .into_iter()
                .map(|n| format!("{}: {n}", path.display()))
                .collect();
            (p, notes)
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => (Prefs::default(), Vec::new()),
        Err(e) => (
            Prefs::default(),
            vec![format!("{}: {e}: the defaults", path.display())],
        ),
    }
}

/// Writes the settings file whole (a temporary file, synced, then renamed),
/// so a power cut leaves the old file or the new one.
pub fn save_prefs(path: &Path, prefs: &Prefs) -> Result<(), String> {
    use std::io::Write;
    let tmp = path.with_extension("new");
    let write = || -> std::io::Result<()> {
        let mut f = std::fs::File::create(&tmp)?;
        f.write_all(prefs.format().as_bytes())?;
        f.sync_all()?;
        std::fs::rename(&tmp, path)
    };
    write().map_err(|e| format!("can't save {}: {e}", path.display()))
}

/// What [`run`] needs from outside.
pub struct DisplayIo {
    /// Whether the system reports the clock synchronized; blocking.
    pub clock_synchronized: Arc<dyn Fn() -> bool + Send + Sync>,
    /// Seconds since 1970 (UTC), now.
    pub now_unix: Arc<dyn Fn() -> f64 + Send + Sync>,
    /// Where the settings are kept; `None`: not kept.
    pub state_file: Option<PathBuf>,
    /// Where the last GPS position is kept; `None`: not kept.
    pub location_file: Option<PathBuf>,
    /// navigation's positions ([`crate::gps::follow`]); `None`: no GPS.
    pub positions: Option<watch::Receiver<Option<(nav::Position, Instant)>>>,
    pub writer: Option<Writer>,
    pub evaluate_every: Duration,
}

/// The display task. Ends when `cmds` and `reports` are both closed.
pub async fn run(
    mut state: DisplayState,
    io: DisplayIo,
    mut cmds: mpsc::Receiver<Command>,
    mut reports: mpsc::Receiver<Report>,
    out: watch::Sender<pb::Display>,
) {
    // The clock check is a process (timedatectl): off the loop, and only
    // once a tick. Between ticks the last answer stands.
    let synchronized = || {
        let check = io.clock_synchronized.clone();
        async move {
            tokio::task::spawn_blocking(move || check())
                .await
                .unwrap_or(false)
        }
    };
    let mut synced = synchronized().await;
    let sys = |synced: bool| SystemClock {
        unix: (io.now_unix)(),
        synchronized: synced,
    };
    state.evaluate(sys(synced), Instant::now());
    let mut sent: Option<u32> = None;
    let mut last_log = String::new();
    let mut tick = tokio::time::interval(io.evaluate_every);
    tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    tick.tick().await; // the first tick is immediate: just evaluated
    let mut positions = io.positions;
    let mut cmds_open = true;
    let mut reports_open = true;

    loop {
        // Publish, log and send the backlight its target.
        let snap = state.snapshot();
        let line = describe(&snap);
        if line != last_log {
            eprintln!("[power-manager] display: {line}");
            last_log = line;
        }
        out.send_if_modified(|cur| {
            if *cur == snap {
                false
            } else {
                *cur = snap.clone();
                true
            }
        });
        if let (Some(w), Some(t)) = (&io.writer, state.target_raw()) {
            // Again after a failed write, so it retries each evaluation.
            if sent != Some(t) || state.problem().is_some() {
                w.set(t);
                sent = Some(t);
            }
        }

        if !cmds_open && !reports_open {
            return;
        }
        tokio::select! {
            _ = tick.tick() => {
                synced = synchronized().await;
                state.evaluate(sys(synced), Instant::now());
            }
            changed = async {
                match positions.as_mut() {
                    Some(rx) => rx.changed().await.is_ok(),
                    None => std::future::pending().await,
                }
            } => {
                let Some(rx) = positions.as_mut() else { continue };
                if !changed {
                    // The follower ended (a bad endpoint, logged there).
                    positions = None;
                    continue;
                }
                let latest = rx.borrow_and_update().clone();
                if let Some((p, at)) = latest {
                    let now = Instant::now();
                    let before = state.sources(sys(synced), now);
                    if let (Some(save), Some(path)) =
                        (state.position(&p, at), io.location_file.clone())
                    {
                            let saved = tokio::task::spawn_blocking(move || {
                                crate::gps::save_location(&path, save)
                            })
                            .await;
                            if let Ok(Err(e)) = saved {
                                eprintln!("[power-manager] display: {e}");
                            }
                    }
                    // A first fix or GPS time decides now; otherwise the tick.
                    if state.sources(sys(synced), now) != before {
                        state.evaluate(sys(synced), now);
                    }
                }
            }
            cmd = cmds.recv(), if cmds_open => match cmd {
                None => cmds_open = false,
                Some(Command { change, source, reply }) => {
                    if state.apply(change) {
                        eprintln!("[power-manager] display: {source} set {}", describe_change(change));
                        if let Some(path) = io.state_file.clone() {
                            let prefs = state.prefs();
                            let saved = tokio::task::spawn_blocking(move || save_prefs(&path, &prefs)).await;
                            if let Ok(Err(e)) = saved {
                                eprintln!("[power-manager] display: {e}");
                            }
                        }
                    }
                    state.evaluate(sys(synced), Instant::now());
                    let _ = reply.send(state.snapshot());
                }
            },
            r = reports.recv(), if reports_open => match r {
                None => reports_open = false,
                Some(r) => {
                    // A failed write lets the next evaluation send again.
                    if matches!(r, Report::Failed(_)) {
                        sent = None;
                    }
                    state.report(r);
                }
            },
        }
    }
}

fn describe_change(c: Change) -> String {
    let mut parts = Vec::new();
    if let Some(ch) = c.choice {
        parts.push(format!("choice {}", ch.name()));
    }
    if let Some(p) = c.day_pct {
        parts.push(format!("day {p} %"));
    }
    if let Some(p) = c.night_pct {
        parts.push(format!("night {p} %"));
    }
    parts.join(", ")
}

#[cfg(test)]
mod tests {
    use super::*;

    // 2026-11-11T19:00Z (midday in Denver) and 06:00Z the next day (night).
    const MIDDAY: f64 = 1_794_423_600.0;
    const NIGHT: f64 = 1_794_463_200.0;

    fn denver() -> Option<Location> {
        Some(Location::new(39.739, -104.990).expect("valid"))
    }

    fn panel() -> Result<BacklightInfo, String> {
        Ok(BacklightInfo {
            name: "10-0045".into(),
            max: 255,
        })
    }

    fn at(unix: f64, synchronized: bool) -> SystemClock {
        SystemClock { unix, synchronized }
    }

    fn state(prefs: Prefs, backlight: Result<BacklightInfo, String>) -> DisplayState {
        DisplayState::new(
            denver(),
            GpsInput::new(None, false),
            TrustClock::Synchronized,
            DayNight::new(Thresholds::default(), Mode::Day),
            10,
            prefs,
            backlight,
        )
    }

    #[test]
    fn auto_by_day_and_by_night() {
        let mut s = state(Prefs::default(), panel());
        s.evaluate(at(MIDDAY, true), Instant::now());
        let d = s.snapshot();
        assert_eq!(d.mode, pb::DisplayMode::Day as i32);
        assert_eq!(d.basis, pb::ModeBasis::Sun as i32);
        assert_eq!(d.sun, pb::SunStatus::Known as i32);
        assert!(d.sun_elevation_deg > 20.0);
        assert_eq!(d.brightness_pct, 100);
        assert_eq!(s.target_raw(), Some(255));

        s.evaluate(at(NIGHT, true), Instant::now());
        let d = s.snapshot();
        assert_eq!(d.mode, pb::DisplayMode::Night as i32);
        assert_eq!(d.brightness_pct, 40);
        assert_eq!(s.target_raw(), Some(102));
    }

    #[test]
    fn an_untrusted_clock_falls_back_and_says_so() {
        let mut s = state(Prefs::default(), panel());
        s.evaluate(at(NIGHT, false), Instant::now());
        let d = s.snapshot();
        assert_eq!(d.mode, pb::DisplayMode::Day as i32);
        assert_eq!(d.basis, pb::ModeBasis::Fallback as i32);
        assert_eq!(d.sun, pb::SunStatus::ClockNotSynchronized as i32);
        assert!(describe(&d).contains("clock not synchronized"));
    }

    #[test]
    fn no_location_says_so() {
        let mut s = DisplayState::new(
            None,
            GpsInput::new(None, false),
            TrustClock::Synchronized,
            DayNight::new(Thresholds::default(), Mode::Night),
            10,
            Prefs::default(),
            panel(),
        );
        s.evaluate(at(MIDDAY, true), Instant::now());
        let d = s.snapshot();
        assert_eq!(d.mode, pb::DisplayMode::Night as i32);
        assert_eq!(d.sun, pb::SunStatus::NoLocation as i32);
    }

    #[test]
    fn changes_clamp_to_the_floor_and_report_whether_they_changed() {
        let mut s = state(Prefs::default(), panel());
        assert!(s.apply(Change {
            choice: Some(Choice::Night),
            night_pct: Some(3),
            ..Default::default()
        }));
        assert_eq!(s.prefs().choice, Choice::Night);
        assert_eq!(s.prefs().levels.night_pct, 10);
        assert!(!s.apply(Change {
            night_pct: Some(5),
            ..Default::default()
        }));
        assert!(!s.apply(Change::default()));
        assert!(
            !s.apply(Change {
                day_pct: Some(250),
                ..Default::default()
            }),
            "day is already 100"
        );
        s.evaluate(at(MIDDAY, true), Instant::now());
        let d = s.snapshot();
        assert_eq!(d.mode, pb::DisplayMode::Night as i32);
        assert_eq!(d.basis, pb::ModeBasis::Manual as i32);
        assert_eq!(d.brightness_pct, 10);
        assert_eq!(s.target_raw(), Some(26));
    }

    #[test]
    fn saved_levels_below_the_floor_are_raised() {
        let prefs = Prefs {
            choice: Choice::Auto,
            levels: Levels {
                day_pct: 5,
                night_pct: 1,
            },
        };
        let s = state(prefs, panel());
        assert_eq!(s.prefs().levels.day_pct, 10);
        assert_eq!(s.prefs().levels.night_pct, 10);
    }

    #[test]
    fn no_backlight_still_decides_the_mode() {
        let mut s = state(Prefs::default(), Err("no backlight device".into()));
        s.evaluate(at(NIGHT, true), Instant::now());
        let d = s.snapshot();
        assert_eq!(d.mode, pb::DisplayMode::Night as i32);
        assert!(!d.backlight_present);
        assert_eq!(d.backlight_problem, "no backlight device");
        assert_eq!(s.target_raw(), None);
        // A writer report can't clear "no backlight".
        s.report(Report::At(10));
        assert_eq!(s.problem(), Some("no backlight device"));
    }

    #[test]
    fn write_failures_show_until_a_ramp_finishes() {
        let mut s = state(Prefs::default(), panel());
        s.evaluate(at(MIDDAY, true), Instant::now());
        s.report(Report::Failed("can't write: permission denied".into()));
        assert_eq!(
            s.snapshot().backlight_problem,
            "can't write: permission denied"
        );
        s.report(Report::At(255));
        assert_eq!(s.snapshot().backlight_problem, "");
    }

    #[test]
    fn nothing_decided_yet_is_unspecified() {
        let s = state(Prefs::default(), panel());
        let d = s.snapshot();
        assert_eq!(d.mode, pb::DisplayMode::Unspecified as i32);
        assert_eq!(s.target_raw(), None);
    }

    #[test]
    fn choices_map_to_and_from_the_api() {
        for c in [Choice::Auto, Choice::Day, Choice::Night] {
            assert_eq!(choice_from_pb(choice_to_pb(c) as i32), Some(c));
        }
        assert_eq!(choice_from_pb(0), None);
        assert_eq!(choice_from_pb(99), None);
    }

    #[test]
    fn trust_settings_parse() {
        assert_eq!(TrustClock::parse(""), Some(TrustClock::Synchronized));
        assert_eq!(
            TrustClock::parse("synchronized"),
            Some(TrustClock::Synchronized)
        );
        assert_eq!(TrustClock::parse("always"), Some(TrustClock::Always));
        assert_eq!(TrustClock::parse("sometimes"), None);
    }

    fn io(synced: bool, now: f64, state_file: Option<PathBuf>) -> DisplayIo {
        DisplayIo {
            clock_synchronized: Arc::new(move || synced),
            now_unix: Arc::new(move || now),
            state_file,
            location_file: None,
            positions: None,
            writer: None,
            evaluate_every: Duration::from_secs(3600),
        }
    }

    async fn set(cmds: &mpsc::Sender<Command>, change: Change) -> pb::Display {
        let (reply, rx) = oneshot::channel();
        cmds.send(Command {
            change,
            source: "test".into(),
            reply,
        })
        .await
        .expect("loop running");
        rx.await.expect("reply")
    }

    #[tokio::test]
    async fn the_task_publishes_takes_changes_and_saves_them() {
        let dir = std::env::temp_dir().join(format!("f250-display-run-{}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("dir");
        let file = dir.join("display");
        let _ = std::fs::remove_file(&file);
        let (cmd_tx, cmd_rx) = mpsc::channel(4);
        let (_rep_tx, rep_rx) = mpsc::channel(4);
        let (out, mut watch_rx) = watch::channel(pb::Display::default());
        let task = tokio::spawn(run(
            state(Prefs::default(), panel()),
            io(true, NIGHT, Some(file.clone())),
            cmd_rx,
            rep_rx,
            out,
        ));
        watch_rx.changed().await.expect("first state");
        assert_eq!(watch_rx.borrow().mode, pb::DisplayMode::Night as i32);

        let d = set(
            &cmd_tx,
            Change {
                choice: Some(Choice::Day),
                day_pct: Some(70),
                ..Default::default()
            },
        )
        .await;
        assert_eq!(d.mode, pb::DisplayMode::Day as i32);
        assert_eq!(d.basis, pb::ModeBasis::Manual as i32);
        assert_eq!(d.day_brightness_pct, 70);
        let (saved, _) = load_prefs(Some(&file));
        assert_eq!(saved.choice, Choice::Day);
        assert_eq!(saved.levels.day_pct, 70);

        drop(cmd_tx);
        drop(_rep_tx);
        task.await.expect("task ends");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn the_task_falls_back_on_an_unsynchronized_clock_unless_trusted() {
        for (trust, want) in [
            (TrustClock::Synchronized, pb::ModeBasis::Fallback),
            (TrustClock::Always, pb::ModeBasis::Sun),
        ] {
            let (cmd_tx, cmd_rx) = mpsc::channel(4);
            let (rep_tx, rep_rx) = mpsc::channel(4);
            let (out, mut watch_rx) = watch::channel(pb::Display::default());
            let mut st = state(Prefs::default(), panel());
            st.trust = trust;
            let task = tokio::spawn(run(st, io(false, NIGHT, None), cmd_rx, rep_rx, out));
            watch_rx.changed().await.expect("first state");
            assert_eq!(watch_rx.borrow().basis, want as i32, "{trust:?}");
            drop(cmd_tx);
            drop(rep_tx);
            task.await.expect("task ends");
        }
    }

    /// A real (not simulated) current 3D fix in Wichita, timed `utc`.
    fn wichita(utc: f64) -> nav::Position {
        nav::Position {
            status: nav::FixStatus::Fix3d as i32,
            fix: Some(nav::Fix {
                latitude_deg: 37.687,
                longitude_deg: -97.330,
                age_ms: 0,
                utc_time_ms: Some((utc * 1000.0) as i64),
                ..Default::default()
            }),
            current: true,
            stale_after_ms: 3000,
            source: "gpsd 3.27.5: /dev/ttyACM0".into(),
            ..Default::default()
        }
    }

    /// The clock reads 2020: never believed, whatever the trust setting.
    const UNSET: f64 = 1_600_000_000.0;

    #[test]
    fn gps_position_replaces_the_configured_one_and_says_so() {
        let mut s = state(Prefs::default(), panel());
        let t = Instant::now();
        s.evaluate(at(MIDDAY, true), t);
        let d = s.snapshot();
        assert_eq!(d.location_source, pb::LocationSource::Configured as i32);
        assert_eq!(d.clock_source, pb::ClockSource::System as i32);
        let denver_elevation = d.sun_elevation_deg;

        assert_eq!(
            s.position(&wichita(MIDDAY), t),
            Some(Location::new(37.7, -97.3).expect("valid")),
            "the first fix is saved"
        );
        s.evaluate(at(MIDDAY, true), t + Duration::from_secs(90));
        let d = s.snapshot();
        assert_eq!(d.location_source, pb::LocationSource::Gps as i32);
        assert_eq!(d.location_age_s, 90);
        assert_eq!(d.basis, pb::ModeBasis::Sun as i32);
        // Worked out for Wichita, not Denver (about 33.7° against 32.7°).
        assert!(
            (d.sun_elevation_deg - denver_elevation).abs() > 0.5,
            "{d:?}"
        );
        assert!(
            describe(&d).contains("GPS position 1 min old, synchronized clock"),
            "{}",
            describe(&d)
        );
    }

    #[test]
    fn gps_time_stands_in_for_an_unsynchronized_clock() {
        let mut s = state(Prefs::default(), panel());
        let t = Instant::now();
        // The Pi after a cold start: no network, no RTC cell, the clock unset.
        s.evaluate(at(UNSET, false), t);
        let d = s.snapshot();
        assert_eq!(d.basis, pb::ModeBasis::Fallback as i32);
        assert_eq!(d.sun, pb::SunStatus::ClockNotSet as i32);
        assert_eq!(d.clock_source, pb::ClockSource::None as i32);

        // A current fix at night: the sun from GPS time, an hour on.
        s.position(&wichita(NIGHT), t);
        s.evaluate(at(UNSET, false), t + Duration::from_secs(3600));
        let d = s.snapshot();
        assert_eq!(d.basis, pb::ModeBasis::Sun as i32);
        assert_eq!(d.mode, pb::DisplayMode::Night as i32);
        assert_eq!(d.clock_source, pb::ClockSource::Gps as i32);
        assert!(describe(&d).contains("GPS time"), "{}", describe(&d));
    }

    #[test]
    fn clocks_in_order_synchronized_gps_trusted() {
        let t = Instant::now();
        let mut s = state(Prefs::default(), panel());
        s.trust = TrustClock::Always;
        assert_eq!(s.sources(at(NIGHT, false), t).1, ClockSource::Trusted);
        s.position(&wichita(MIDDAY), t);
        assert_eq!(s.sources(at(NIGHT, false), t).1, ClockSource::Gps);
        assert_eq!(s.sources(at(NIGHT, true), t).1, ClockSource::System);
        // The synchronized system clock wins: by it, it is night.
        s.evaluate(at(NIGHT, true), t);
        assert_eq!(s.snapshot().mode, pb::DisplayMode::Night as i32);
        // GPS time (midday) over a trusted but unsynchronized clock.
        s.evaluate(at(NIGHT, false), t);
        assert_eq!(s.snapshot().mode, pb::DisplayMode::Day as i32);
    }

    #[test]
    fn no_gps_and_nothing_configured_says_so() {
        let mut s = DisplayState::new(
            None,
            GpsInput::new(None, false),
            TrustClock::Synchronized,
            DayNight::new(Thresholds::default(), Mode::Day),
            10,
            Prefs::default(),
            panel(),
        );
        s.evaluate(at(MIDDAY, true), Instant::now());
        let d = s.snapshot();
        assert_eq!(d.location_source, pb::LocationSource::None as i32);
        assert_eq!(d.sun, pb::SunStatus::NoLocation as i32);
        assert!(describe(&d).contains("no GPS position, none configured"));
        // A position saved by an earlier run is enough.
        let mut s = DisplayState::new(
            None,
            GpsInput::new(Some(Location::new(37.7, -97.3).expect("valid")), false),
            TrustClock::Synchronized,
            DayNight::new(Thresholds::default(), Mode::Day),
            10,
            Prefs::default(),
            panel(),
        );
        s.evaluate(at(MIDDAY, true), Instant::now());
        let d = s.snapshot();
        assert_eq!(d.location_source, pb::LocationSource::GpsSaved as i32);
        assert_eq!(d.basis, pb::ModeBasis::Sun as i32);
    }

    #[tokio::test]
    async fn the_task_follows_positions_at_once_and_saves_them() {
        let dir = std::env::temp_dir().join(format!("f250-display-gps-{}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("dir");
        let file = dir.join("location");
        let _ = std::fs::remove_file(&file);
        let (pos_tx, pos_rx) = watch::channel(None);
        let (cmd_tx, cmd_rx) = mpsc::channel(4);
        let (rep_tx, rep_rx) = mpsc::channel(4);
        let (out, mut watch_rx) = watch::channel(pb::Display::default());
        let mut io = io(false, UNSET, None);
        io.location_file = Some(file.clone());
        io.positions = Some(pos_rx);
        let task = tokio::spawn(run(
            state(Prefs::default(), panel()),
            io,
            cmd_rx,
            rep_rx,
            out,
        ));
        watch_rx.changed().await.expect("first state");
        assert_eq!(watch_rx.borrow().basis, pb::ModeBasis::Fallback as i32);

        pos_tx.send_replace(Some((wichita(NIGHT), Instant::now())));
        // Long before the hour-long tick: the new sources decide at once.
        tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                watch_rx.changed().await.expect("state");
                if watch_rx.borrow().basis == pb::ModeBasis::Sun as i32 {
                    break;
                }
            }
        })
        .await
        .expect("follows the fix");
        let d = watch_rx.borrow().clone();
        assert_eq!(d.location_source, pb::LocationSource::Gps as i32);
        assert_eq!(d.clock_source, pb::ClockSource::Gps as i32);
        assert_eq!(d.mode, pb::DisplayMode::Night as i32);
        let deadline = Instant::now() + Duration::from_secs(5);
        while !file.exists() {
            assert!(Instant::now() < deadline, "location saved");
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        assert_eq!(
            crate::gps::load_location(&file).0,
            Some(Location::new(37.7, -97.3).expect("valid"))
        );

        drop(pos_tx);
        drop(cmd_tx);
        drop(rep_tx);
        task.await.expect("task ends");
        let _ = std::fs::remove_dir_all(&dir);
    }

    fn raw(pairs: &[(&str, &str)]) -> RawSettings {
        let mut r = RawSettings::default();
        for (k, v) in pairs {
            let v = Some((*v).to_string());
            match *k {
                "lat" => r.latitude = v,
                "lon" => r.longitude = v,
                "night" => r.night_below_deg = v,
                "hyst" => r.hysteresis_deg = v,
                "fallback" => r.fallback = v,
                "trust" => r.trust_clock = v,
                "min" => r.min_brightness_pct = v,
                _ => unreachable!(),
            }
        }
        r
    }

    #[test]
    fn settings_default_to_the_examples() {
        let (s, notes) = RawSettings::default().resolve();
        assert!(notes.is_empty());
        assert_eq!(s.location, None);
        assert_eq!(s.thresholds, Thresholds::default());
        assert_eq!(s.fallback, Mode::Day);
        assert_eq!(s.trust, TrustClock::Synchronized);
        assert_eq!(s.min_pct, 10);
        // Empty values from /etc/default/f250 are "not set".
        let (s, notes) = raw(&[("lat", ""), ("lon", " "), ("min", "")]).resolve();
        assert!(notes.is_empty(), "{notes:?}");
        assert_eq!(s.location, None);
    }

    #[test]
    fn settings_are_read() {
        let (s, notes) = raw(&[
            ("lat", "39.739"),
            ("lon", "-104.990"),
            ("night", "-6"),
            ("hyst", "0.5"),
            ("fallback", "night"),
            ("trust", "always"),
            ("min", "15"),
        ])
        .resolve();
        assert!(notes.is_empty(), "{notes:?}");
        assert_eq!(s.location, denver());
        assert_eq!(s.thresholds.night_below_deg, -6.0);
        assert_eq!(s.thresholds.hysteresis_deg, 0.5);
        assert_eq!(s.fallback, Mode::Night);
        assert_eq!(s.trust, TrustClock::Always);
        assert_eq!(s.min_pct, 15);
    }

    #[test]
    fn bad_settings_never_stop_it_and_are_reported() {
        let (s, notes) = raw(&[
            ("lat", "north"),
            ("lon", "-104.990"),
            ("night", "-40"),
            ("fallback", "dusk"),
            ("trust", "maybe"),
            ("min", "0"),
        ])
        .resolve();
        assert_eq!(s.location, None);
        assert_eq!(s.thresholds, Thresholds::default());
        assert_eq!(s.fallback, Mode::Day);
        assert_eq!(s.trust, TrustClock::Synchronized);
        assert_eq!(s.min_pct, 10);
        assert_eq!(notes.len(), 6, "{notes:?}");
        let (s, notes) = raw(&[("lat", "95"), ("lon", "0")]).resolve();
        assert_eq!(s.location, None);
        assert!(notes[0].contains("latitude"), "{notes:?}");
        let (_, notes) = raw(&[("lat", "39.7")]).resolve();
        assert!(notes[0].contains("go together"), "{notes:?}");
    }

    #[test]
    fn settings_file_round_trips_and_survives_damage() {
        let dir = std::env::temp_dir().join(format!("f250-display-{}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("dir");
        let path = dir.join("display");
        let _ = std::fs::remove_file(&path);
        assert_eq!(load_prefs(Some(&path)).0, Prefs::default());
        let p = Prefs {
            choice: Choice::Day,
            levels: Levels {
                day_pct: 90,
                night_pct: 20,
            },
        };
        save_prefs(&path, &p).expect("save");
        let (back, notes) = load_prefs(Some(&path));
        assert_eq!(back, p);
        assert!(notes.is_empty());
        std::fs::write(&path, "choice=sideways\n").expect("write");
        let (back, notes) = load_prefs(Some(&path));
        assert_eq!(back.choice, Choice::Auto);
        assert_eq!(notes.len(), 1);
        assert!(save_prefs(&dir.join("missing/display"), &p).is_err());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
