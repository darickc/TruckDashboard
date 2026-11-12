//! Spoken directions (ADR-0040).
//!
//! [`Prompter`] is pure, like the guide: it is shown the guide's state after
//! each update and decides what, if anything, to say. It uses Valhalla's own
//! verbal instructions (`verbal_transition_alert_instruction`,
//! `verbal_pre_transition_instruction`, `verbal_post_transition_instruction`,
//! as Valhalla 3.9.1 sends them in `tests/data/`) and composes only the
//! distances, in the configured units.
//!
//! - **Approaching:** "In half a mile, turn right onto US 36." once the next
//!   maneuver is within the far distance.
//! - **At the maneuver:** Valhalla's pre-transition instruction ("Turn right
//!   onto US 36, US 281.") within the near distance.
//! - **After it,** on a long stretch: "Continue on US 36 for 12 miles."
//! - **Rerouting:** "Off the route. Finding a new one." and "New route."
//! - **Arrival:** Valhalla's arrival instruction.
//!
//! **Never from stale guidance** (CLAUDE.md rule 4): every prompt needs
//! progress the guide computed from a current fix in this very update. A
//! prompt that came due while the fix was stale is not said late with old
//! distances; the next one that is due from a current fix is. Muted, the
//! prompts are still worked out (so unmuting doesn't replay old ones) but
//! nothing is said.
//!
//! [`Speaker`] is how a prompt is heard: the log, a program that speaks its
//! argument (macOS `say`, espeak-ng), and later services/audio-manager
//! (ADR-0039), which isn't connected yet.

use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::Duration;

use f250_proto::nav::v1 as pb;

use crate::guide::{Progress, State};
use crate::valhalla::Route;

/// The units distances are spoken in.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Units {
    #[default]
    Imperial,
    Metric,
}

/// When prompts are spoken. Every distance is an example to tune on the
/// truck (CLAUDE.md rule 10), not a correct value.
#[derive(Debug, Clone)]
pub struct VoiceConfig {
    /// The approaching prompt comes this many seconds ahead at the current
    /// speed...
    pub far_s: f64,
    /// ...but never nearer than this, nor farther than this.
    pub far_min_m: f64,
    pub far_max_m: f64,
    /// The at-the-maneuver prompt, likewise.
    pub near_s: f64,
    pub near_min_m: f64,
    pub near_max_m: f64,
    /// An approaching prompt waits this long after another prompt, so they
    /// don't run together. The at-the-maneuver prompt never waits.
    pub min_gap: Duration,
    /// After a maneuver, "Continue for …" is said only within this distance
    /// past it, and only when the next maneuver is beyond the far distance.
    pub continue_within_m: f64,
    pub units: Units,
}

impl Default for VoiceConfig {
    fn default() -> Self {
        VoiceConfig {
            far_s: 30.0,
            far_min_m: 400.0,
            far_max_m: 2_500.0,
            near_s: 8.0,
            near_min_m: 50.0,
            near_max_m: 300.0,
            min_gap: Duration::from_secs(4),
            continue_within_m: 300.0,
            units: Units::Imperial,
        }
    }
}

impl VoiceConfig {
    /// (far, near) thresholds at `speed_mps`.
    pub fn thresholds(&self, speed_mps: Option<f64>) -> (f64, f64) {
        let v = speed_mps
            .filter(|v| v.is_finite() && *v > 0.0)
            .unwrap_or(0.0);
        let far = (v * self.far_s).clamp(self.far_min_m, self.far_max_m);
        let near = (v * self.near_s).clamp(self.near_min_m, self.near_max_m);
        (far, near.min(far))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PromptKind {
    /// A new route's first instruction.
    Start,
    Approaching,
    AtManeuver,
    Continue,
    OffRoute,
    NewRoute,
    Arrived,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Prompt {
    pub kind: PromptKind,
    pub text: String,
    /// The maneuver it is about, an index into the route's maneuvers.
    pub maneuver: Option<usize>,
}

/// What the prompter is shown after each guide update.
#[derive(Debug, Clone, Copy)]
pub struct Moment<'a> {
    pub state: State,
    pub route: Option<&'a Route>,
    /// Only from a current fix, as the guide computes it; None otherwise.
    pub progress: Option<Progress>,
    /// The current fix's speed.
    pub speed_mps: Option<f64>,
    /// The guide's reroute count for this destination.
    pub reroutes: u32,
    /// The guide says the truck is off the route.
    pub off_route: bool,
    pub now: Duration,
}

const SAID_FAR: u8 = 1;
const SAID_NEAR: u8 = 2;
const SAID_CONTINUE: u8 = 4;

#[derive(Debug)]
pub struct Prompter {
    cfg: VoiceConfig,
    muted: bool,
    route_id: u64,
    /// Per maneuver of the route: what has been said about it.
    said: Vec<u8>,
    started: bool,
    reroutes: u32,
    arrived: bool,
    last_at: Option<Duration>,
    last_prompt: String,
    prompts: u64,
}

impl Prompter {
    pub fn new(cfg: VoiceConfig, muted: bool) -> Self {
        Prompter {
            cfg,
            muted,
            route_id: 0,
            said: Vec::new(),
            started: false,
            reroutes: 0,
            arrived: false,
            last_at: None,
            last_prompt: String::new(),
            prompts: 0,
        }
    }

    pub fn muted(&self) -> bool {
        self.muted
    }

    pub fn set_muted(&mut self, muted: bool) {
        self.muted = muted;
    }

    pub fn last_prompt(&self) -> &str {
        &self.last_prompt
    }

    pub fn prompts(&self) -> u64 {
        self.prompts
    }

    /// What to say now, if anything. Muted, the answer is always None but
    /// the prompt still counts as made.
    pub fn update(&mut self, m: Moment<'_>) -> Option<Prompt> {
        let p = self.decide(m)?;
        self.last_at = Some(m.now);
        self.last_prompt = p.text.clone();
        self.prompts += 1;
        (!self.muted).then_some(p)
    }

    fn decide(&mut self, m: Moment<'_>) -> Option<Prompt> {
        if matches!(m.state, State::Idle | State::Unavailable) {
            // No destination: forget everything about the last one.
            self.route_id = 0;
            self.said.clear();
            self.started = false;
            self.reroutes = 0;
            self.arrived = false;
            return None;
        }
        // Off the route: the guide asked for a new route from a current fix.
        if m.reroutes > self.reroutes {
            self.reroutes = m.reroutes;
            return Some(Prompt {
                kind: PromptKind::OffRoute,
                text: "Off the route. Finding a new one.".to_string(),
                maneuver: None,
            });
        }
        let route = m.route?;
        let new_route = route.id != self.route_id;
        if new_route {
            self.route_id = route.id;
            self.said = vec![0; route.maneuvers.len()];
            self.started = false;
            self.arrived = false;
        }
        // Everything below is said only from current progress.
        let pr = m.progress?;
        if m.state == State::Arrived {
            if self.arrived {
                return None;
            }
            self.arrived = true;
            let text = route
                .maneuvers
                .last()
                .filter(|x| matches!(x.kind, 4..=6))
                .map(|x| x.verbal_pre.clone())
                .filter(|t| !t.is_empty())
                .unwrap_or_else(|| "You have arrived at your destination.".to_string());
            return Some(Prompt {
                kind: PromptKind::Arrived,
                text,
                maneuver: Some(route.maneuvers.len().saturating_sub(1)),
            });
        }
        if m.state != State::Active || m.off_route {
            return None;
        }
        let i = pr
            .maneuver_index
            .min(route.maneuvers.len().saturating_sub(1));
        let (far, near) = self.cfg.thresholds(m.speed_mps);
        let d = pr.to_maneuver_m;
        // Maneuvers already behind are done with: never said late.
        for s in self.said.iter_mut().take(i) {
            *s |= SAID_FAR | SAID_NEAR;
        }
        if !self.started {
            self.started = true;
            if self.reroutes > 0 {
                return Some(Prompt {
                    kind: PromptKind::NewRoute,
                    text: "New route.".to_string(),
                    maneuver: None,
                });
            }
            // Valhalla's start instruction: "Drive south. Then turn right
            // onto East 1st Street." Its "then" covers the next maneuver
            // when that is close.
            let start = &route.maneuvers[0];
            if i == 1 && start.verbal_multi_cue && d <= near {
                self.said[1] |= SAID_FAR | SAID_NEAR;
            }
            if !start.verbal_pre.is_empty() && pr.along_m <= self.cfg.continue_within_m {
                return Some(Prompt {
                    kind: PromptKind::Start,
                    text: start.verbal_pre.clone(),
                    maneuver: Some(0),
                });
            }
        }
        let man = &route.maneuvers[i];
        if d <= near {
            if self.said[i] & SAID_NEAR != 0 {
                return None;
            }
            self.said[i] |= SAID_FAR | SAID_NEAR;
            // Valhalla says "Then …" when the next maneuver follows close
            // behind; that one then gets no approaching prompt of its own.
            if man.verbal_multi_cue
                && let Some(s) = self.said.get_mut(i + 1)
            {
                *s |= SAID_FAR;
            }
            let text = first_non_empty(&[&man.verbal_pre, &man.instruction])?;
            return Some(Prompt {
                kind: PromptKind::AtManeuver,
                text,
                maneuver: Some(i),
            });
        }
        let gap_ok = self
            .last_at
            .is_none_or(|t| m.now.saturating_sub(t) >= self.cfg.min_gap);
        if d <= far && self.said[i] & SAID_FAR == 0 {
            if !gap_ok {
                return None; // still due next time, if still in range
            }
            self.said[i] |= SAID_FAR | SAID_CONTINUE;
            let what = first_non_empty(&[&man.verbal_alert, &man.verbal_pre, &man.instruction])?;
            return Some(Prompt {
                kind: PromptKind::Approaching,
                text: format!(
                    "In {}, {}",
                    spoken_distance(d, self.cfg.units),
                    lower_first(&what)
                ),
                maneuver: Some(i),
            });
        }
        // Just past a maneuver, with a long way to the next: how far.
        if d > far && i > 0 && self.said[i] & SAID_CONTINUE == 0 {
            let past = pr.along_m - route.maneuvers[i - 1].start_m;
            if past > self.cfg.continue_within_m {
                self.said[i] |= SAID_CONTINUE; // too late to be useful
                return None;
            }
            if !gap_ok {
                return None;
            }
            self.said[i] |= SAID_CONTINUE;
            let prev = &route.maneuvers[i - 1];
            return Some(Prompt {
                kind: PromptKind::Continue,
                text: continue_text(&prev.verbal_post, d, self.cfg.units),
                maneuver: Some(i - 1),
            });
        }
        None
    }

    pub fn to_pb(&self, speaker: &SpeakerStatus) -> pb::Voice {
        pb::Voice {
            muted: self.muted,
            audible: speaker.audible,
            detail: speaker.detail.clone(),
            last_prompt: self.last_prompt.clone(),
            prompts: self.prompts,
        }
    }
}

fn first_non_empty(options: &[&String]) -> Option<String> {
    options
        .iter()
        .find(|s| !s.trim().is_empty())
        .map(|s| s.trim().to_string())
}

/// "Turn right onto US 36." → "turn right onto US 36.", but "US 36 …"
/// stays as it is.
fn lower_first(s: &str) -> String {
    let mut chars = s.chars();
    match (chars.next(), chars.next()) {
        (Some(a), Some(b)) if a.is_uppercase() && b.is_lowercase() => {
            a.to_lowercase().chain(s.chars().skip(1)).collect()
        }
        _ => s.to_string(),
    }
}

/// Valhalla's "Continue on US 36 for 19 kilometers." with the distance from
/// here, in the configured units: "Continue on US 36 for 12 miles."
pub fn continue_text(verbal_post: &str, metres: f64, units: Units) -> String {
    let distance = spoken_distance(metres, units);
    let base = verbal_post
        .trim()
        .rsplit_once(" for ")
        .map(|(head, _)| head)
        .filter(|h| h.starts_with("Continue"))
        .unwrap_or("Continue");
    format!("{base} for {distance}.")
}

const METRES_PER_MILE: f64 = 1_609.344;
const FEET_PER_METRE: f64 = 3.280_839_895;

/// A distance as it is said: "500 feet", "a quarter mile", "half a mile",
/// "1.5 miles", "12 miles"; "300 meters", "1.5 kilometers".
pub fn spoken_distance(metres: f64, units: Units) -> String {
    let m = if metres.is_finite() {
        metres.max(0.0)
    } else {
        0.0
    };
    match units {
        Units::Imperial => {
            let miles = m / METRES_PER_MILE;
            if miles < 0.2 {
                let feet = ((m * FEET_PER_METRE) / 100.0).round().max(1.0) * 100.0;
                return format!("{} feet", feet as u64);
            }
            if miles < 0.9 {
                let quarters = (miles * 4.0).round() as u32;
                return match quarters {
                    0 | 1 => "a quarter mile".to_string(),
                    2 => "half a mile".to_string(),
                    _ => "three quarters of a mile".to_string(),
                };
            }
            plural(miles, "mile", "miles")
        }
        Units::Metric => {
            if m < 950.0 {
                let step = if m < 300.0 { 50.0 } else { 100.0 };
                let r = ((m / step).round() * step).max(step);
                return format!("{} meters", r as u64);
            }
            plural(m / 1000.0, "kilometer", "kilometers")
        }
    }
}

/// To the half under 3, whole numbers above.
fn plural(x: f64, one: &str, many: &str) -> String {
    let r = if x < 3.0 {
        (x * 2.0).round() / 2.0
    } else {
        x.round()
    };
    if (r - 1.0).abs() < 1e-9 {
        format!("1 {one}")
    } else if r.fract() == 0.0 {
        format!("{} {many}", r as u64)
    } else {
        format!("{r:.1} {many}")
    }
}

/// Whether prompts can be heard, and where they go, for the screen.
#[derive(Debug, Clone, PartialEq)]
pub struct SpeakerStatus {
    pub audible: bool,
    pub detail: String,
}

/// How a prompt is heard. Small on purpose: services/audio-manager
/// (ADR-0039) will be another implementation, which ducks the music.
pub trait Speaker: Send + 'static {
    /// Says `text` now, cutting off anything still being said: the newer
    /// prompt is the one that matters.
    fn speak(&mut self, text: &str);
    /// Stops anything being said (muted, or the route ended).
    fn stop(&mut self);
    fn status(&self) -> SpeakerStatus;
}

/// Prompts to the log only: what navigation does where there is no audio
/// path (the Pi until audio-manager exists).
#[derive(Debug, Default)]
pub struct LogSpeaker {
    pub why: String,
}

impl Speaker for LogSpeaker {
    fn speak(&mut self, text: &str) {
        eprintln!("[navigation] voice (not audible: {}): {text}", self.why);
    }
    fn stop(&mut self) {}
    fn status(&self) -> SpeakerStatus {
        SpeakerStatus {
            audible: false,
            detail: format!("the log only: {}", self.why),
        }
    }
}

/// A program that speaks its last argument and exits: macOS `say`, or
/// `espeak-ng -v en-us`. One at a time; a newer prompt kills an older one
/// still speaking.
#[derive(Debug)]
pub struct CommandSpeaker {
    pub program: PathBuf,
    pub args: Vec<String>,
    pub name: String,
    child: Option<tokio::process::Child>,
}

impl CommandSpeaker {
    /// From "say" or "espeak-ng -v en-us": the program, then its arguments.
    pub fn parse(command: &str) -> Option<Self> {
        let mut words = command.split_whitespace();
        let program = PathBuf::from(words.next()?);
        Some(CommandSpeaker {
            name: command.trim().to_string(),
            args: words.map(str::to_string).collect(),
            program,
            child: None,
        })
    }

    fn found(&self) -> bool {
        program_found(&self.program)
    }
}

/// `program` exists: a path, or a name on PATH.
pub fn program_found(program: &Path) -> bool {
    if program.components().count() > 1 {
        return program.is_file();
    }
    std::env::var_os("PATH")
        .is_some_and(|path| std::env::split_paths(&path).any(|d| d.join(program).is_file()))
}

impl Speaker for CommandSpeaker {
    fn speak(&mut self, text: &str) {
        self.stop();
        match tokio::process::Command::new(&self.program)
            .args(&self.args)
            .arg(text)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .kill_on_drop(true)
            .spawn()
        {
            Ok(child) => {
                eprintln!("[navigation] voice: {text}");
                self.child = Some(child);
            }
            Err(e) => eprintln!(
                "[navigation] voice: {} failed ({e}): {text}",
                self.program.display()
            ),
        }
    }

    fn stop(&mut self) {
        if let Some(mut c) = self.child.take() {
            // Reaped when dropped (kill_on_drop) or by tokio's orphan reaper.
            let _ = c.start_kill();
        }
    }

    fn status(&self) -> SpeakerStatus {
        if self.found() {
            SpeakerStatus {
                audible: true,
                detail: self.name.clone(),
            }
        } else {
            SpeakerStatus {
                audible: false,
                detail: format!("{} not found: the log only", self.program.display()),
            }
        }
    }
}

/// Records prompts: for tests.
#[derive(Debug, Default, Clone)]
pub struct RecordingSpeaker {
    pub said: std::sync::Arc<std::sync::Mutex<Vec<String>>>,
    pub stops: std::sync::Arc<std::sync::atomic::AtomicUsize>,
}

impl Speaker for RecordingSpeaker {
    fn speak(&mut self, text: &str) {
        if let Ok(mut s) = self.said.lock() {
            s.push(text.to_string());
        }
    }
    fn stop(&mut self) {
        self.stops
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    }
    fn status(&self) -> SpeakerStatus {
        SpeakerStatus {
            audible: true,
            detail: "recorded (test)".to_string(),
        }
    }
}

/// Spoken directions as the guide runs them: the prompter, its speaker,
/// and where the mute setting is kept.
pub struct Voice {
    pub prompter: Prompter,
    pub speaker: Box<dyn Speaker>,
    /// The mute setting survives restarts here; None keeps it in memory.
    pub settings: Option<PathBuf>,
}

impl Voice {
    /// Reads the mute setting from `settings`, if any: unmuted when there is
    /// none or it can't be read.
    pub fn new(cfg: VoiceConfig, speaker: Box<dyn Speaker>, settings: Option<PathBuf>) -> Self {
        let muted = settings.as_deref().is_some_and(read_muted);
        Voice {
            prompter: Prompter::new(cfg, muted),
            speaker,
            settings,
        }
    }

    /// Mutes or unmutes, stops anything being said when muting, and keeps
    /// the setting.
    pub fn set_muted(&mut self, muted: bool) {
        self.prompter.set_muted(muted);
        if muted {
            self.speaker.stop();
        }
        if let Some(f) = &self.settings {
            let text = format!("{{\"muted\": {muted}}}\n");
            if let Err(e) = crate::places::write_atomic(f, text.as_bytes()) {
                eprintln!(
                    "[navigation] voice: the mute setting wasn't saved to {}: {e}",
                    f.display()
                );
            }
        }
    }

    /// After a guide update: say what is due.
    pub fn update(&mut self, m: Moment<'_>) {
        if matches!(m.state, State::Idle | State::Unavailable) && self.prompter.route_id != 0 {
            self.speaker.stop();
        }
        if let Some(p) = self.prompter.update(m) {
            self.speaker.speak(&p.text);
        }
    }

    pub fn to_pb(&self) -> pb::Voice {
        self.prompter.to_pb(&self.speaker.status())
    }
}

fn read_muted(f: &Path) -> bool {
    std::fs::read(f)
        .ok()
        .and_then(|b| serde_json::from_slice::<serde_json::Value>(&b).ok())
        .and_then(|v| v.get("muted").and_then(serde_json::Value::as_bool))
        .unwrap_or(false)
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::*;
    use crate::guide::progress;
    use crate::valhalla::LatLon;

    const ROUTE: &str = include_str!("../tests/data/valhalla-3.9.1-route-auto.json");
    const DEST: LatLon = (39.8103, -98.5559);

    fn route(id: u64) -> Route {
        let mut r = crate::valhalla::parse_response(ROUTE, DEST, "auto").unwrap();
        r.id = id;
        r
    }

    const S: fn(u64) -> Duration = Duration::from_secs;

    /// A moment `along` metres along route `r`, from a current fix at
    /// `speed` m/s.
    fn at<'a>(r: &'a Route, along: f64, speed: f64, now: Duration) -> Moment<'a> {
        Moment {
            state: State::Active,
            route: Some(r),
            progress: Some(progress(r, along, 0.0)),
            speed_mps: Some(speed),
            reroutes: 0,
            off_route: false,
            now,
        }
    }

    fn stale<'a>(r: &'a Route, now: Duration) -> Moment<'a> {
        Moment {
            progress: None,
            speed_mps: None,
            ..at(r, 0.0, 0.0, now)
        }
    }

    fn said(p: &mut Prompter, m: Moment<'_>) -> Option<(PromptKind, String)> {
        p.update(m).map(|x| (x.kind, x.text))
    }

    /// Maneuver 3 (Turn right onto US 36) starts here; 2 is 671 m before.
    fn m3(r: &Route) -> f64 {
        r.maneuvers[3].start_m
    }

    #[test]
    fn reads_valhallas_verbal_instructions() {
        let r = route(1);
        let m = &r.maneuvers[3];
        assert_eq!(m.verbal_alert, "Turn right onto US 36.");
        assert_eq!(m.verbal_pre, "Turn right onto US 36, US 281.");
        assert_eq!(m.verbal_post, "Continue for 19 kilometers.");
        assert!(!m.verbal_multi_cue);
        assert!(r.maneuvers[0].verbal_multi_cue);
        assert_eq!(r.maneuvers[4].verbal_post, "", "the exit has none");
        assert_eq!(
            r.maneuvers[8].verbal_pre,
            "You have arrived at your destination."
        );
    }

    #[test]
    fn start_of_a_route() {
        let r = route(1);
        let mut p = Prompter::new(VoiceConfig::default(), false);
        // Valhalla's start includes the next turn, 13 m away: that turn's own
        // at-the-maneuver prompt isn't repeated.
        assert_eq!(
            said(&mut p, at(&r, 0.0, 5.0, S(0))),
            Some((
                PromptKind::Start,
                "Drive south. Then Turn right onto East 1st Street.".to_string()
            ))
        );
        assert_eq!(said(&mut p, at(&r, 5.0, 5.0, S(10))), None);
        assert_eq!(said(&mut p, at(&r, 0.0, 5.0, S(11))), None, "said once");
    }

    /// Maneuver 4 (Take the exit on the right) starts here, 19 km in.
    fn m4(r: &Route) -> f64 {
        r.maneuvers[4].start_m
    }

    #[test]
    fn approaching_then_at_the_maneuver() {
        let r = route(1);
        let mut p = Prompter::new(VoiceConfig::default(), false);
        // Well past the start (no start prompt: it would be late), and past
        // the turn onto US 36 (no "continue": too late too).
        // 15 m/s: far 450 m, near 120 m.
        assert_eq!(said(&mut p, at(&r, m4(&r) - 3_000.0, 15.0, S(0))), None);
        assert_eq!(
            said(&mut p, at(&r, m4(&r) - 460.0, 15.0, S(10))),
            None,
            "not yet"
        );
        assert_eq!(
            said(&mut p, at(&r, m4(&r) - 440.0, 15.0, S(11))),
            Some((
                PromptKind::Approaching,
                "In a quarter mile, take the exit on the right.".to_string()
            ))
        );
        assert_eq!(
            said(&mut p, at(&r, m4(&r) - 300.0, 15.0, S(20))),
            None,
            "once"
        );
        assert_eq!(
            said(&mut p, at(&r, m4(&r) - 110.0, 15.0, S(25))),
            Some((
                PromptKind::AtManeuver,
                "Take the exit on the right.".to_string()
            ))
        );
        assert_eq!(
            said(&mut p, at(&r, m4(&r) - 20.0, 15.0, S(30))),
            None,
            "once"
        );
    }

    #[test]
    fn continue_after_the_maneuver_on_a_long_stretch() {
        let r = route(1);
        let mut p = Prompter::new(VoiceConfig::default(), false);
        let _ = said(&mut p, at(&r, m3(&r) - 100.0, 25.0, S(0)));
        // 50 m past the turn onto US 36; the exit is 19 km on.
        let (kind, text) = said(&mut p, at(&r, m3(&r) + 50.0, 25.0, S(10))).unwrap();
        assert_eq!(kind, PromptKind::Continue);
        assert_eq!(text, "Continue for 12 miles.");
        assert_eq!(
            said(&mut p, at(&r, m3(&r) + 80.0, 25.0, S(20))),
            None,
            "once"
        );
        // Metric: Valhalla's own wording, with the distance from here.
        assert_eq!(
            continue_text(
                "Continue on US 281 for 3 kilometers.",
                2_900.0,
                Units::Metric
            ),
            "Continue on US 281 for 3 kilometers."
        );
        assert_eq!(
            continue_text("", 2_400.0, Units::Imperial),
            "Continue for 1.5 miles."
        );
    }

    #[test]
    fn a_continue_too_late_is_not_said() {
        let r = route(1);
        let mut p = Prompter::new(VoiceConfig::default(), false);
        let _ = said(&mut p, at(&r, m3(&r) - 100.0, 25.0, S(0)));
        // The next current fix is 2 km past the turn (a long outage).
        assert_eq!(said(&mut p, at(&r, m3(&r) + 2_000.0, 25.0, S(90))), None);
        assert_eq!(said(&mut p, at(&r, m3(&r) + 2_050.0, 25.0, S(92))), None);
    }

    #[test]
    fn close_maneuvers_wait_for_the_gap_or_ride_on_then() {
        let r = route(1);
        let mut p = Prompter::new(VoiceConfig::default(), false);
        // Maneuver 7 (Turn left, 50 m) follows 6 with Valhalla's "Then …".
        let m6 = r.maneuvers[6].start_m;
        let m7 = r.maneuvers[7].start_m;
        let _ = said(&mut p, at(&r, m6 - 400.0, 13.0, S(0)));
        let (k, _) = said(&mut p, at(&r, m6 - 90.0, 13.0, S(30))).unwrap();
        assert_eq!(k, PromptKind::AtManeuver);
        // Maneuver 6 has no "then" (7 is 395 m on): 7 gets its own prompts.
        assert!(!r.maneuvers[6].verbal_multi_cue);
        // 1 s later, 7 is within far range: the gap holds it back...
        assert_eq!(said(&mut p, at(&r, m6 + 10.0, 13.0, S(31))), None);
        // ...until it has passed, while still due.
        let (k, t) = said(&mut p, at(&r, m6 + 60.0, 13.0, S(35))).unwrap();
        assert_eq!(
            (k, t.as_str()),
            (PromptKind::Approaching, "In a quarter mile, turn left.")
        );
        let (k, t) = said(&mut p, at(&r, m7 - 80.0, 13.0, S(55))).unwrap();
        assert_eq!(
            (k, t.as_str()),
            (
                PromptKind::AtManeuver,
                "Turn left. Then You will arrive at your destination."
            )
        );
    }

    #[test]
    fn stale_fix_says_nothing_and_nothing_late() {
        let r = route(1);
        let mut p = Prompter::new(VoiceConfig::default(), false);
        assert_eq!(said(&mut p, at(&r, m4(&r) - 3_000.0, 15.0, S(0))), None);
        // The approach happens while the fix is stale: silence.
        for t in 1..20 {
            assert_eq!(said(&mut p, stale(&r, S(t))), None);
        }
        // Current again 60 m before the exit: the at-the-maneuver prompt,
        // not the stale "in a quarter mile".
        let (k, _) = said(&mut p, at(&r, m4(&r) - 60.0, 15.0, S(20))).unwrap();
        assert_eq!(k, PromptKind::AtManeuver);
        // Stale through the exit and beyond: it isn't announced late.
        let mut p = Prompter::new(VoiceConfig::default(), false);
        assert_eq!(said(&mut p, at(&r, m4(&r) - 3_000.0, 15.0, S(0))), None);
        assert_eq!(said(&mut p, stale(&r, S(30))), None);
        assert_eq!(said(&mut p, at(&r, m4(&r) + 1_000.0, 15.0, S(300))), None);
        // A stale moment with Arrived doesn't announce arrival either.
        let arrived = Moment {
            state: State::Arrived,
            ..stale(&r, S(200))
        };
        assert_eq!(said(&mut p, arrived), None);
    }

    #[test]
    fn rerouting() {
        let r1 = route(1);
        let mut p = Prompter::new(VoiceConfig::default(), false);
        let _ = said(&mut p, at(&r1, 5_000.0, 25.0, S(0)));
        // Off the route: no maneuver prompts while the guide says so.
        let off = Moment {
            off_route: true,
            ..at(&r1, m3(&r1) - 100.0, 25.0, S(10))
        };
        assert_eq!(said(&mut p, off), None);
        // The guide asks for a new route.
        let asking = Moment {
            state: State::Routing,
            reroutes: 1,
            off_route: true,
            ..at(&r1, m3(&r1) - 100.0, 25.0, S(15))
        };
        assert_eq!(
            said(&mut p, asking),
            Some((
                PromptKind::OffRoute,
                "Off the route. Finding a new one.".to_string()
            ))
        );
        assert_eq!(
            said(
                &mut p,
                Moment {
                    now: S(16),
                    ..asking
                }
            ),
            None,
            "once"
        );
        // The new route arrives.
        let r2 = route(2);
        let new = Moment {
            reroutes: 1,
            ..at(&r2, 2_000.0, 25.0, S(17))
        };
        assert_eq!(
            said(&mut p, new),
            Some((PromptKind::NewRoute, "New route.".to_string()))
        );
        // Then its maneuvers as usual.
        let near = Moment {
            reroutes: 1,
            ..at(&r2, r2.maneuvers[4].start_m - 150.0, 25.0, S(40))
        };
        assert_eq!(said(&mut p, near).unwrap().0, PromptKind::AtManeuver);
    }

    #[test]
    fn arrival() {
        let r = route(1);
        let mut p = Prompter::new(VoiceConfig::default(), false);
        let len = r.shape_length_m();
        let _ = said(&mut p, at(&r, len - 300.0, 10.0, S(0)));
        let arrived = Moment {
            state: State::Arrived,
            ..at(&r, len - 20.0, 10.0, S(30))
        };
        assert_eq!(
            said(&mut p, arrived),
            Some((
                PromptKind::Arrived,
                "You have arrived at your destination.".to_string()
            ))
        );
        assert_eq!(
            said(
                &mut p,
                Moment {
                    now: S(31),
                    ..arrived
                }
            ),
            None,
            "once"
        );
        // Cleared: everything is forgotten.
        let idle = Moment {
            state: State::Idle,
            route: None,
            ..stale(&r, S(40))
        };
        assert_eq!(said(&mut p, idle), None);
        assert_eq!(
            said(&mut p, at(&r, 0.0, 5.0, S(50))).unwrap().0,
            PromptKind::Start
        );
    }

    #[test]
    fn muted_says_nothing_and_doesnt_replay() {
        let r = route(1);
        let mut p = Prompter::new(VoiceConfig::default(), true);
        assert_eq!(said(&mut p, at(&r, 0.0, 5.0, S(0))), None);
        assert_eq!(p.prompts(), 1, "made, not said");
        assert!(p.last_prompt().starts_with("Drive south."));
        assert_eq!(said(&mut p, at(&r, m3(&r) - 100.0, 15.0, S(60))), None);
        p.set_muted(false);
        // The turn already "said" while muted isn't repeated...
        assert_eq!(said(&mut p, at(&r, m3(&r) - 50.0, 15.0, S(61))), None);
        // ...the next one is.
        let (k, _) = said(&mut p, at(&r, r.maneuvers[4].start_m - 100.0, 15.0, S(900))).unwrap();
        assert_eq!(k, PromptKind::AtManeuver);
    }

    #[test]
    fn thresholds_scale_with_speed_within_limits() {
        let c = VoiceConfig::default();
        assert_eq!(c.thresholds(None), (400.0, 50.0));
        assert_eq!(c.thresholds(Some(20.0)), (600.0, 160.0));
        assert_eq!(c.thresholds(Some(200.0)), (2_500.0, 300.0));
        assert_eq!(c.thresholds(Some(f64::NAN)), (400.0, 50.0));
    }

    #[test]
    fn distances_as_spoken() {
        let i = Units::Imperial;
        assert_eq!(spoken_distance(30.0, i), "100 feet");
        assert_eq!(spoken_distance(152.4, i), "500 feet");
        assert_eq!(spoken_distance(400.0, i), "a quarter mile");
        assert_eq!(spoken_distance(800.0, i), "half a mile");
        assert_eq!(spoken_distance(1_200.0, i), "three quarters of a mile");
        assert_eq!(spoken_distance(1_609.0, i), "1 mile");
        assert_eq!(spoken_distance(2_400.0, i), "1.5 miles");
        assert_eq!(spoken_distance(19_000.0, i), "12 miles");
        let m = Units::Metric;
        assert_eq!(spoken_distance(10.0, m), "50 meters");
        assert_eq!(spoken_distance(120.0, m), "100 meters");
        assert_eq!(spoken_distance(440.0, m), "400 meters");
        assert_eq!(spoken_distance(1_000.0, m), "1 kilometer");
        assert_eq!(spoken_distance(2_700.0, m), "2.5 kilometers");
        assert_eq!(spoken_distance(19_000.0, m), "19 kilometers");
        assert_eq!(spoken_distance(f64::NAN, m), "50 meters");
    }

    #[test]
    fn lower_first_keeps_abbreviations() {
        assert_eq!(lower_first("Turn right."), "turn right.");
        assert_eq!(lower_first("US 36 begins."), "US 36 begins.");
        assert_eq!(lower_first(""), "");
    }

    #[test]
    fn voice_speaks_and_stops_and_keeps_mute() {
        let dir = std::env::temp_dir().join(format!("f250-voice-{}", std::process::id()));
        let file = dir.join("voice.json");
        let _ = std::fs::remove_dir_all(&dir);
        let rec = RecordingSpeaker::default();
        let mut v = Voice::new(
            VoiceConfig::default(),
            Box::new(rec.clone()),
            Some(file.clone()),
        );
        assert!(!v.prompter.muted(), "unmuted without a setting");
        let r = route(1);
        v.update(at(&r, 0.0, 5.0, S(0)));
        assert_eq!(rec.said.lock().unwrap().len(), 1);
        v.set_muted(true);
        assert_eq!(
            rec.stops.load(std::sync::atomic::Ordering::Relaxed),
            1,
            "muting stops speech"
        );
        v.update(at(&r, m3(&r) - 100.0, 15.0, S(60)));
        assert_eq!(rec.said.lock().unwrap().len(), 1, "nothing while muted");
        assert!(v.to_pb().muted);
        // The setting survives a restart; a corrupt one reads as unmuted.
        let v2 = Voice::new(
            VoiceConfig::default(),
            Box::new(LogSpeaker::default()),
            Some(file.clone()),
        );
        assert!(v2.prompter.muted());
        std::fs::write(&file, b"{{{").unwrap();
        let v3 = Voice::new(
            VoiceConfig::default(),
            Box::new(LogSpeaker::default()),
            Some(file),
        );
        assert!(!v3.prompter.muted());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn command_speaker_status() {
        let s = CommandSpeaker::parse("espeak-ng -v en-us").unwrap();
        assert_eq!(s.program, PathBuf::from("espeak-ng"));
        assert_eq!(s.args, ["-v", "en-us"]);
        let missing = CommandSpeaker::parse("/nonexistent/speak").unwrap();
        assert!(!missing.status().audible);
        assert!(CommandSpeaker::parse("  ").is_none());
        let sh = CommandSpeaker::parse("sh").unwrap();
        assert!(sh.status().audible, "found on PATH");
        assert!(
            !LogSpeaker {
                why: "no audio".into()
            }
            .status()
            .audible
        );
    }
}
