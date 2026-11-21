//! What the 5-way switch's presses do, and the driver's setting of which wire
//! is which ([ADR-0051](../../../docs/architecture/adr/0051-five-way-switch-media-and-cameras.md)).
//!
//! - A **short** press goes to audio-manager (media and calls), a **long**
//!   one to camera-manager (a camera).
//! - While **learning** (the dashboard's Settings › Switch is asking for each
//!   direction in turn), a press is only reported: it changes neither the
//!   volume nor the camera. Learning ends by itself after
//!   [`DEFAULT_LEARNING_TIMEOUT`] without a press, so a screen that went away
//!   can't leave the switch doing nothing.
//!
//! Pure logic: the main loop owns a [`Control`], feeds it presses and the
//! dashboard's requests with a monotonic time, and saves the mapping.

use std::time::Duration;

use f250_proto::power::v1 as pb;
use tokio::sync::oneshot;

use crate::switch::{Kind, Mapping, Press, Role, Wire};

/// How long learning lasts without a press. An example value.
pub const DEFAULT_LEARNING_TIMEOUT: Duration = Duration::from_secs(60);

/// Where a press goes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Route {
    /// Learning: reported only.
    Learning,
    /// A long press: camera-manager.
    Camera,
    /// A short press: audio-manager.
    Audio,
}

/// A press on its way to a link, with what the dashboard was told.
#[derive(Debug, Clone, PartialEq)]
pub struct Sent {
    pub role: Role,
    pub press: pb::Press,
}

/// A request from the dashboard, answered by the main loop.
#[derive(Debug)]
pub enum Command {
    Learning {
        on: bool,
        source: String,
        reply: oneshot::Sender<pb::SwitchState>,
    },
    Mapping {
        mapping: Mapping,
        source: String,
        reply: oneshot::Sender<Saved>,
    },
    Reset {
        source: String,
        reply: oneshot::Sender<Saved>,
    },
}

/// The answer to a mapping change.
#[derive(Debug, Clone, PartialEq)]
pub struct Saved {
    pub saved: bool,
    pub detail: String,
    pub state: pb::SwitchState,
}

pub fn wire_to_pb(w: Wire) -> pb::Wire {
    match w {
        Wire::F13 => pb::Wire::F13,
        Wire::F14 => pb::Wire::F14,
        Wire::F15 => pb::Wire::F15,
        Wire::F16 => pb::Wire::F16,
        Wire::F17 => pb::Wire::F17,
    }
}

pub fn wire_from_pb(v: i32) -> Option<Wire> {
    match pb::Wire::try_from(v).ok()? {
        pb::Wire::F13 => Some(Wire::F13),
        pb::Wire::F14 => Some(Wire::F14),
        pb::Wire::F15 => Some(Wire::F15),
        pb::Wire::F16 => Some(Wire::F16),
        pb::Wire::F17 => Some(Wire::F17),
        pb::Wire::Unspecified => None,
    }
}

pub fn role_to_pb(r: Role) -> pb::Role {
    match r {
        Role::Up => pb::Role::Up,
        Role::Down => pb::Role::Down,
        Role::Left => pb::Role::Left,
        Role::Right => pb::Role::Right,
        Role::Press => pb::Role::Press,
    }
}

pub fn role_from_pb(v: i32) -> Option<Role> {
    match pb::Role::try_from(v).ok()? {
        pb::Role::Up => Some(Role::Up),
        pb::Role::Down => Some(Role::Down),
        pb::Role::Left => Some(Role::Left),
        pb::Role::Right => Some(Role::Right),
        pb::Role::Press => Some(Role::Press),
        pb::Role::Unspecified => None,
    }
}

/// The request's wires as a mapping; why not, in words for the screen.
pub fn mapping_from_pb(wires: &[pb::WireRole]) -> Result<Mapping, String> {
    let pairs = wires
        .iter()
        .map(|w| {
            Ok((
                wire_from_pb(w.wire).ok_or("A wire isn't one of the five.")?,
                role_from_pb(w.role).ok_or("A direction isn't one of the five.")?,
            ))
        })
        .collect::<Result<Vec<_>, &str>>()?;
    Mapping::from_pairs(&pairs)
}

#[derive(Debug, Clone)]
pub struct Control {
    mapping: Mapping,
    learning_timeout: Duration,
    long_press: Duration,
    /// Learning ends at this time unless a press comes first.
    learning_until: Option<Duration>,
    /// Why the mapping wasn't loaded or saved; `None` when all is well.
    problem: Option<String>,
    seq: u64,
}

impl Control {
    pub fn new(
        mapping: Mapping,
        problem: Option<String>,
        long_press: Duration,
        learning_timeout: Duration,
    ) -> Self {
        Self {
            mapping,
            learning_timeout,
            long_press,
            learning_until: None,
            problem,
            seq: 0,
        }
    }

    pub fn mapping(&self) -> Mapping {
        self.mapping
    }

    pub fn learning(&self) -> bool {
        self.learning_until.is_some()
    }

    /// When learning runs out if no press comes.
    pub fn learning_deadline(&self) -> Option<Duration> {
        self.learning_until
    }

    /// A press at `now`: where it goes, and what the dashboard is told.
    pub fn press(&mut self, p: Press, now: Duration) -> (Route, Sent) {
        self.seq += 1;
        let role = self.mapping.role(p.wire);
        let (route, result) = if self.learning() {
            self.learning_until = Some(now + self.learning_timeout);
            (Route::Learning, "learning: not sent".to_string())
        } else {
            match p.kind {
                Kind::Long => (Route::Camera, role.long_action().to_string()),
                Kind::Short => (Route::Audio, role.short_action().to_string()),
            }
        };
        let press = pb::Press {
            wire: wire_to_pb(p.wire) as i32,
            role: role_to_pb(role) as i32,
            kind: match p.kind {
                Kind::Short => pb::PressKind::Short,
                Kind::Long => pb::PressKind::Long,
            } as i32,
            result,
            seq: self.seq,
        };
        (route, Sent { role, press })
    }

    pub fn set_learning(&mut self, on: bool, now: Duration) {
        self.learning_until = on.then(|| now + self.learning_timeout);
    }

    /// Ends learning if it has run out at `now`; true if it just did.
    pub fn expire(&mut self, now: Duration) -> bool {
        if self.learning_until.is_some_and(|until| now >= until) {
            self.learning_until = None;
            return true;
        }
        false
    }

    /// A new mapping, and learning off. `problem` is why it wasn't saved, if
    /// it wasn't.
    pub fn set_mapping(&mut self, mapping: Mapping, problem: Option<String>) {
        self.mapping = mapping;
        self.learning_until = None;
        self.problem = problem;
    }

    /// The state for the dashboard; `present` are the wires an open input
    /// device has, `device_problem` why the switch can't be read, if so.
    pub fn state(&self, present: &[Wire], device_problem: Option<&str>) -> pb::SwitchState {
        let problem = [self.problem.as_deref(), device_problem]
            .into_iter()
            .flatten()
            .collect::<Vec<_>>()
            .join("; ");
        pb::SwitchState {
            wires: Wire::ALL
                .into_iter()
                .map(|w| pb::WireInfo {
                    wire: wire_to_pb(w) as i32,
                    pin: w.pin().to_string(),
                    role: role_to_pb(self.mapping.role(w)) as i32,
                    present: present.contains(&w),
                })
                .collect(),
            learning: self.learning(),
            learning_timeout_s: self.learning_timeout.as_secs() as u32,
            long_press_ms: self.long_press.as_millis() as u32,
            default_mapping: self.mapping == Mapping::default(),
            problem,
        }
    }
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
    use super::*;

    fn s(n: u64) -> Duration {
        Duration::from_secs(n)
    }
    fn control() -> Control {
        Control::new(Mapping::default(), None, Duration::from_millis(600), s(60))
    }
    fn press(wire: Wire, kind: Kind) -> Press {
        Press { wire, kind }
    }

    #[test]
    fn short_presses_go_to_audio_and_long_ones_to_the_cameras() {
        let mut c = control();
        let (route, sent) = c.press(press(Wire::F16, Kind::Short), s(1));
        assert_eq!(route, Route::Audio);
        assert_eq!(sent.role, Role::Up);
        assert_eq!(sent.press.result, "volume up");
        assert_eq!(sent.press.kind(), pb::PressKind::Short);
        assert_eq!(sent.press.wire(), pb::Wire::F16);
        assert_eq!(sent.press.seq, 1);
        let (route, sent) = c.press(press(Wire::F15, Kind::Long), s(2));
        assert_eq!(route, Route::Camera);
        assert_eq!(sent.role, Role::Down);
        assert_eq!(sent.press.result, "rear camera");
        assert_eq!(sent.press.seq, 2);
        let (_, sent) = c.press(press(Wire::F17, Kind::Short), s(3));
        assert_eq!(sent.press.result, "play/pause or call");
        let (_, sent) = c.press(press(Wire::F17, Kind::Long), s(3));
        assert_eq!(sent.press.result, "close camera");
    }

    #[test]
    fn while_learning_presses_are_reported_not_sent() {
        let mut c = control();
        c.set_learning(true, s(10));
        assert!(c.learning());
        assert_eq!(c.learning_deadline(), Some(s(70)));
        let (route, sent) = c.press(press(Wire::F13, Kind::Short), s(20));
        assert_eq!(route, Route::Learning);
        assert_eq!(sent.press.result, "learning: not sent");
        assert_eq!(c.learning_deadline(), Some(s(80)), "a press extends it");
        let (route, _) = c.press(press(Wire::F13, Kind::Long), s(21));
        assert_eq!(route, Route::Learning, "long presses too");
        c.set_learning(false, s(22));
        assert!(!c.learning());
        let (route, _) = c.press(press(Wire::F13, Kind::Short), s(23));
        assert_eq!(route, Route::Audio);
    }

    #[test]
    fn learning_runs_out_without_a_press() {
        let mut c = control();
        c.set_learning(true, s(0));
        assert!(!c.expire(s(59)));
        assert!(c.learning());
        assert!(c.expire(s(60)));
        assert!(!c.learning());
        assert!(!c.expire(s(61)), "once");
    }

    #[test]
    fn a_new_mapping_applies_and_ends_learning() {
        let mut c = control();
        c.set_learning(true, s(0));
        let m = Mapping::parse("F13 up\nF14 down\nF15 left\nF16 right\nF17 press").unwrap();
        c.set_mapping(m, None);
        assert!(!c.learning());
        let (_, sent) = c.press(press(Wire::F13, Kind::Short), s(1));
        assert_eq!(
            (sent.role, sent.press.result.as_str()),
            (Role::Up, "volume up")
        );
        let st = c.state(&[Wire::F13], None);
        assert!(!st.default_mapping);
        assert_eq!(st.wires.len(), 5);
        assert_eq!(st.wires[0].role(), pb::Role::Up);
        assert_eq!(st.wires[0].pin, "BCM12, pin 32");
        assert!(st.wires[0].present && !st.wires[1].present);
        c.set_mapping(Mapping::default(), Some("can't save".into()));
        let st = c.state(&[], Some("no switch device"));
        assert!(st.default_mapping);
        assert_eq!(st.problem, "can't save; no switch device");
        assert_eq!((st.long_press_ms, st.learning_timeout_s), (600, 60));
    }

    #[test]
    fn requests_become_mappings_or_say_why_not() {
        let pairs: Vec<pb::WireRole> = Wire::ALL
            .into_iter()
            .map(|w| pb::WireRole {
                wire: wire_to_pb(w) as i32,
                role: role_to_pb(Mapping::default().role(w)) as i32,
            })
            .collect();
        assert_eq!(mapping_from_pb(&pairs), Ok(Mapping::default()));
        let mut bad = pairs.clone();
        bad[0].role = 0;
        assert!(mapping_from_pb(&bad).unwrap_err().contains("direction"));
        let mut bad = pairs.clone();
        bad[0].wire = 99;
        assert!(mapping_from_pb(&bad).unwrap_err().contains("wire"));
        let mut bad = pairs;
        bad[0].role = bad[1].role;
        assert!(mapping_from_pb(&bad).unwrap_err().contains("one wire"));
    }
}
