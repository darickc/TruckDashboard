//! The 5-way switch: five wires, each a contact closing to ground on its own
//! GPIO ([ADR-0024](../../../docs/architecture/adr/0024-camera-selection-switch-and-can-reverse.md),
//! [ADR-0051](../../../docs/architecture/adr/0051-five-way-switch-media-and-cameras.md)).
//!
//! The kernel reads the pins, not this service: one `gpio-key` overlay per
//! wire (`agl/boot/config-f250.txt`) turns each into a key on its own input
//! device, with the pull-up on and the kernel's 5 ms `gpio-keys` debounce
//! ([ADR-0025](../../../docs/architecture/adr/0025-camera-switch-through-gpio-key.md)).
//! The keys are F13–F17: nothing in the dashboard or the compositor acts on
//! them, unlike arrow keys, which would move the UI's focus.
//!
//! Three things live here, all pure logic:
//!
//! - [`Wire`]: the physical contact, named by its key. Which GPIO it is on is
//!   boot configuration; which direction it is depends on how the switch is
//!   mounted, so it isn't assumed.
//! - [`Role`] and [`Mapping`]: which wire is Up, Down, Left, Right or Press,
//!   the driver's setting (learned on the dashboard's Settings › Switch).
//! - [`Classifier`]: contact changes in, short and long presses out. Every
//!   input comes with a monotonic time, so the tests drive it without a
//!   clock.
//!   - A press starts once its contact has been the **only** closed contact
//!     for the debounce time (`switch_debounce_ms`, 30 ms by default, an
//!     example). Bounce restarts the wait.
//!   - Held for the long-press time (`switch_long_press_ms`, 600 ms from the
//!     contact closing, an example), it is a **long** press, reported at
//!     once; its release then does nothing.
//!   - Released sooner, it is a **short** press, reported once the contact
//!     has stayed open for the debounce time. Closing again inside that time
//!     is bounce: the same press goes on.
//!   - A second contact closing during a press (a diagonal on a cheap rocker,
//!     or rolling the thumb from one direction to another) cancels it: no
//!     short and no long. That contact must open before it can start a new
//!     press. The other one starts its own once it is alone.
//!   - A contact already held when the service starts isn't seen until it
//!     opens and closes again: the kernel reports only changes.
//!
//! What a press does (a short press to audio-manager, a long one to
//! camera-manager) is [`switch_control`](crate::switch_control)'s business.

use std::time::Duration;

/// The default debounce time. An example value: tune it on the switch that is
/// fitted (H32).
pub const DEFAULT_DEBOUNCE: Duration = Duration::from_millis(30);
/// The default long-press time. An example value.
pub const DEFAULT_LONG_PRESS: Duration = Duration::from_millis(600);

/// One of the switch's five wires, named by the key its `gpio-key` overlay
/// gives it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Wire {
    F13,
    F14,
    F15,
    F16,
    F17,
}

impl Wire {
    pub const ALL: [Wire; 5] = [Wire::F13, Wire::F14, Wire::F15, Wire::F16, Wire::F17];

    /// The key the `gpio-key` overlay gives this wire
    /// (`linux/input-event-codes.h`). Must match `agl/boot/config-f250.txt`
    /// (`make agl-test` checks).
    pub const fn keycode(self) -> u16 {
        match self {
            Wire::F13 => 183,
            Wire::F14 => 184,
            Wire::F15 => 185,
            Wire::F16 => 186,
            Wire::F17 => 187,
        }
    }

    /// The GPIO the overlay puts this key on, for the screen. Must match
    /// `agl/boot/config-f250.txt` (`make agl-test` checks).
    pub const fn pin(self) -> &'static str {
        match self {
            Wire::F13 => "BCM12, pin 32",
            Wire::F14 => "BCM13, pin 33",
            Wire::F15 => "BCM16, pin 36",
            Wire::F16 => "BCM6, pin 31",
            Wire::F17 => "BCM17, pin 11",
        }
    }

    pub fn from_keycode(code: u16) -> Option<Self> {
        Self::ALL.into_iter().find(|w| w.keycode() == code)
    }

    /// The five key codes.
    pub fn keycodes() -> [u16; 5] {
        Self::ALL.map(Wire::keycode)
    }

    pub const fn name(self) -> &'static str {
        match self {
            Wire::F13 => "F13",
            Wire::F14 => "F14",
            Wire::F15 => "F15",
            Wire::F16 => "F16",
            Wire::F17 => "F17",
        }
    }

    fn from_name(s: &str) -> Option<Self> {
        Self::ALL
            .into_iter()
            .find(|w| w.name().eq_ignore_ascii_case(s))
    }

    const fn index(self) -> usize {
        self as usize
    }

    const fn bit(self) -> u8 {
        1 << self as u8
    }

    fn from_single_bit(mask: u8) -> Option<Self> {
        (mask.count_ones() == 1)
            .then(|| Self::ALL.into_iter().find(|w| w.bit() == mask))
            .flatten()
    }
}

/// What a wire does (ADR-0051).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Role {
    Up,
    Down,
    Left,
    Right,
    Press,
}

impl Role {
    pub const ALL: [Role; 5] = [Role::Up, Role::Down, Role::Left, Role::Right, Role::Press];

    pub const fn name(self) -> &'static str {
        match self {
            Role::Up => "up",
            Role::Down => "down",
            Role::Left => "left",
            Role::Right => "right",
            Role::Press => "press",
        }
    }

    fn from_name(s: &str) -> Option<Self> {
        Self::ALL
            .into_iter()
            .find(|r| r.name().eq_ignore_ascii_case(s))
    }

    /// What a short press does, for the log and the screen.
    pub const fn short_action(self) -> &'static str {
        match self {
            Role::Up => "volume up",
            Role::Down => "volume down",
            Role::Left => "previous track",
            Role::Right => "next track",
            Role::Press => "play/pause or call",
        }
    }

    /// What a long press does.
    pub const fn long_action(self) -> &'static str {
        match self {
            Role::Up => "front camera",
            Role::Down => "rear camera",
            Role::Left => "left camera",
            Role::Right => "right camera",
            Role::Press => "close camera",
        }
    }
}

/// Which wire is which role: every wire a different role.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Mapping([Role; 5]);

impl Default for Mapping {
    /// The wiring doc's (docs/wiring/power-and-inputs.md#5-way-switch), and
    /// the bench module's labels: BCM6 up, BCM16 down, BCM12 left, BCM13
    /// right, BCM17 press.
    fn default() -> Self {
        Mapping([Role::Left, Role::Right, Role::Down, Role::Up, Role::Press])
    }
}

impl Mapping {
    pub fn role(&self, wire: Wire) -> Role {
        self.0[wire.index()]
    }

    /// From five (wire, role) pairs: each wire once, each role once.
    pub fn from_pairs(pairs: &[(Wire, Role)]) -> Result<Mapping, String> {
        let mut roles: [Option<Role>; 5] = [None; 5];
        for &(wire, role) in pairs {
            if roles[wire.index()].replace(role).is_some() {
                return Err(format!("Wire {} is given twice.", wire.name()));
            }
        }
        let mut out = [Role::Press; 5];
        for wire in Wire::ALL {
            out[wire.index()] = roles[wire.index()]
                .ok_or_else(|| format!("Wire {} has no direction.", wire.name()))?;
        }
        for role in Role::ALL {
            let n = out.iter().filter(|&&r| r == role).count();
            if n != 1 {
                return Err(format!(
                    "Every direction must be on one wire: {} is on {n}.",
                    role.name()
                ));
            }
        }
        Ok(Mapping(out))
    }

    /// The settings file: one `WIRE role` line per wire.
    pub fn format(&self) -> String {
        let mut s =
            String::from("# The 5-way switch: which wire is which (power-manager, ADR-0051).\n");
        for wire in Wire::ALL {
            s.push_str(&format!("{} {}\n", wire.name(), self.role(wire).name()));
        }
        s
    }

    /// Reads [`Self::format`]'s text; an error says what was wrong.
    pub fn parse(text: &str) -> Result<Mapping, String> {
        let mut pairs = Vec::new();
        for line in text.lines().map(str::trim) {
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let mut parts = line.split_whitespace();
            let (Some(w), Some(r), None) = (parts.next(), parts.next(), parts.next()) else {
                return Err(format!("not `WIRE ROLE`: {line:?}"));
            };
            let wire = Wire::from_name(w).ok_or_else(|| format!("no wire {w:?}"))?;
            let role = Role::from_name(r).ok_or_else(|| format!("no direction {r:?}"))?;
            pairs.push((wire, role));
        }
        Mapping::from_pairs(&pairs)
    }
}

/// Reads the mapping file: the default if it is missing, and the default
/// with a note if it can't be read or is wrong.
pub fn load_mapping(path: Option<&std::path::Path>) -> (Mapping, Option<String>) {
    let Some(path) = path else {
        return (Mapping::default(), None);
    };
    match std::fs::read_to_string(path) {
        Ok(text) => match Mapping::parse(&text) {
            Ok(m) => (m, None),
            Err(e) => (
                Mapping::default(),
                Some(format!("{}: {e}: the default directions", path.display())),
            ),
        },
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => (Mapping::default(), None),
        Err(e) => (
            Mapping::default(),
            Some(format!("{}: {e}: the default directions", path.display())),
        ),
    }
}

/// Writes the mapping file whole (a temporary file, synced, then renamed),
/// so a power cut leaves the old file or the new one.
pub fn save_mapping(path: &std::path::Path, mapping: &Mapping) -> Result<(), String> {
    use std::io::Write;
    let tmp = path.with_extension("new");
    let write = || -> std::io::Result<()> {
        let mut f = std::fs::File::create(&tmp)?;
        f.write_all(mapping.format().as_bytes())?;
        f.sync_all()?;
        std::fs::rename(&tmp, path)
    };
    write().map_err(|e| format!("can't save {}: {e}", path.display()))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Short,
    Long,
}

/// A press of one wire.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Press {
    pub wire: Wire,
    pub kind: Kind,
}

/// The press in progress.
#[derive(Debug, Clone, Copy)]
struct Active {
    wire: Wire,
    /// When its contact closed.
    closed_at: Duration,
    /// When it opened, while that may still be bounce.
    opened_at: Option<Duration>,
    /// The long press has been reported.
    long_sent: bool,
}

/// Turns contact changes into short and long presses.
#[derive(Debug, Clone)]
pub struct Classifier {
    debounce: Duration,
    long_press: Duration,
    /// Contacts closed now.
    closed: u8,
    /// When `closed` last changed.
    changed_at: Duration,
    /// Contacts whose press was cancelled: they must open before they start
    /// another.
    spent: u8,
    active: Option<Active>,
}

impl Classifier {
    pub fn new(debounce: Duration, long_press: Duration) -> Self {
        Self {
            debounce,
            long_press,
            closed: 0,
            changed_at: Duration::ZERO,
            spent: 0,
            active: None,
        }
    }

    pub fn debounce(&self) -> Duration {
        self.debounce
    }

    pub fn long_press(&self) -> Duration {
        self.long_press
    }

    /// A contact closed (`true`) or opened (`false`) at `now`.
    pub fn contact(&mut self, wire: Wire, closed: bool, now: Duration) {
        // A press that had counted, but wasn't polled before its release.
        if !closed
            && self.active.is_none()
            && self.waiting() == Some(wire)
            && now.saturating_sub(self.changed_at) >= self.debounce
        {
            self.active = Some(Active {
                wire,
                closed_at: self.changed_at,
                opened_at: None,
                long_sent: false,
            });
        }
        let bit = wire.bit();
        let before = self.closed;
        if closed {
            self.closed |= bit;
        } else {
            self.closed &= !bit;
            self.spent &= !bit;
        }
        if self.closed == before {
            return;
        }
        self.changed_at = now;
        let Some(mut a) = self.active else {
            return;
        };
        if a.wire == wire {
            if closed {
                // Bounce on the release: the same press goes on.
                a.opened_at = None;
                self.active = Some(a);
            } else if a.long_sent {
                self.active = None;
            } else {
                a.opened_at = Some(now);
                self.active = Some(a);
            }
        } else if closed && a.opened_at.is_none() {
            // Another contact while this one is held: neither counts.
            self.active = None;
            self.spent |= a.wire.bit();
        }
    }

    /// The press that counts at `now`, if one does. Call it after every
    /// contact change and when [`Self::deadline`] passes, until it gives
    /// `None`.
    pub fn poll(&mut self, now: Duration) -> Option<Press> {
        if let Some(mut a) = self.active {
            match a.opened_at {
                Some(at) => {
                    if now.saturating_sub(at) >= self.debounce {
                        self.active = None;
                        return Some(Press {
                            wire: a.wire,
                            kind: Kind::Short,
                        });
                    }
                }
                None => {
                    if !a.long_sent && now.saturating_sub(a.closed_at) >= self.long_press {
                        a.long_sent = true;
                        self.active = Some(a);
                        return Some(Press {
                            wire: a.wire,
                            kind: Kind::Long,
                        });
                    }
                    return None;
                }
            }
        }
        if self.active.is_some() {
            return None;
        }
        let wire = self.waiting()?;
        if now.saturating_sub(self.changed_at) < self.debounce {
            return None;
        }
        self.active = Some(Active {
            wire,
            closed_at: self.changed_at,
            opened_at: None,
            long_sent: false,
        });
        // A long-press time no longer than the debounce counts at once.
        self.poll(now)
    }

    /// When to call [`Self::poll`] next if nothing changes; `None` when
    /// nothing is pending.
    pub fn deadline(&self) -> Option<Duration> {
        let mut due: Option<Duration> = None;
        let mut at = |t: Duration| due = Some(due.map_or(t, |d| d.min(t)));
        match self.active {
            Some(Active {
                opened_at: Some(o), ..
            }) => {
                at(o + self.debounce);
                // A new contact waits for this release to count first.
                if self.waiting().is_some() {
                    at((self.changed_at + self.debounce).max(o + self.debounce));
                }
            }
            Some(Active {
                long_sent: false,
                closed_at,
                ..
            }) => at(closed_at + self.long_press),
            Some(_) => {}
            None => {
                if self.waiting().is_some() {
                    at(self.changed_at + self.debounce);
                }
            }
        }
        due
    }

    /// The single closed contact that may start a press.
    fn waiting(&self) -> Option<Wire> {
        Wire::from_single_bit(self.closed).filter(|w| self.spent & w.bit() == 0)
    }
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
    use super::*;

    fn ms(n: u64) -> Duration {
        Duration::from_millis(n)
    }
    fn classifier() -> Classifier {
        Classifier::new(ms(30), ms(600))
    }
    fn short(wire: Wire) -> Option<Press> {
        Some(Press {
            wire,
            kind: Kind::Short,
        })
    }
    fn long(wire: Wire) -> Option<Press> {
        Some(Press {
            wire,
            kind: Kind::Long,
        })
    }

    #[test]
    fn keycodes_are_f13_to_f17_and_round_trip() {
        assert_eq!(Wire::keycodes(), [183, 184, 185, 186, 187]);
        for w in Wire::ALL {
            assert_eq!(Wire::from_keycode(w.keycode()), Some(w));
            assert_eq!(Wire::from_name(w.name()), Some(w));
        }
        assert_eq!(Wire::from_keycode(116), None, "KEY_POWER");
        assert_eq!(Wire::from_keycode(105), None, "KEY_LEFT");
    }

    #[test]
    fn the_default_mapping_is_the_wiring_docs() {
        let m = Mapping::default();
        assert_eq!(m.role(Wire::F16), Role::Up, "BCM6");
        assert_eq!(m.role(Wire::F15), Role::Down, "BCM16");
        assert_eq!(m.role(Wire::F13), Role::Left, "BCM12");
        assert_eq!(m.role(Wire::F14), Role::Right, "BCM13");
        assert_eq!(m.role(Wire::F17), Role::Press, "BCM17");
    }

    #[test]
    fn a_mapping_round_trips_through_its_file() {
        let m = Mapping::from_pairs(&[
            (Wire::F13, Role::Up),
            (Wire::F14, Role::Down),
            (Wire::F15, Role::Right),
            (Wire::F16, Role::Left),
            (Wire::F17, Role::Press),
        ])
        .unwrap();
        let text = m.format();
        assert!(text.contains("F13 up\n"), "{text}");
        assert_eq!(Mapping::parse(&text), Ok(m));
        assert_eq!(
            Mapping::parse("f17 PRESS\nF16 up\nF15 down\nF14 right\nF13 left\n"),
            Ok(Mapping::default()),
            "case and order don't matter"
        );
    }

    #[test]
    fn a_mapping_must_give_every_wire_a_different_role() {
        let mut pairs: Vec<(Wire, Role)> = Wire::ALL.into_iter().zip(Role::ALL).collect();
        assert!(Mapping::from_pairs(&pairs).is_ok());
        pairs[1].1 = Role::Up;
        let e = Mapping::from_pairs(&pairs).unwrap_err();
        assert!(e.contains("up is on 2"), "{e}");
        let e = Mapping::from_pairs(&pairs[..4]).unwrap_err();
        assert!(e.contains("F17 has no direction"), "{e}");
        let twice = [(Wire::F13, Role::Up), (Wire::F13, Role::Down)];
        assert!(Mapping::from_pairs(&twice).unwrap_err().contains("twice"));
        assert!(
            Mapping::parse("F13 sideways")
                .unwrap_err()
                .contains("sideways")
        );
        assert!(Mapping::parse("F13").is_err());
        assert!(Mapping::parse("F99 up").is_err());
    }

    #[test]
    fn a_bad_or_missing_file_gives_the_default() {
        let dir = std::env::temp_dir().join(format!("f250-switch-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("switch");
        assert_eq!(load_mapping(Some(&path)), (Mapping::default(), None));
        std::fs::write(&path, "F13 up\n").unwrap();
        let (m, note) = load_mapping(Some(&path));
        assert_eq!(m, Mapping::default());
        assert!(note.unwrap().contains("the default directions"));
        let custom = Mapping::parse("F13 up\nF14 down\nF15 left\nF16 right\nF17 press").unwrap();
        save_mapping(&path, &custom).unwrap();
        assert_eq!(load_mapping(Some(&path)), (custom, None));
        assert!(!path.with_extension("new").exists());
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_clean_short_press_counts_after_the_release() {
        let mut c = classifier();
        c.contact(Wire::F13, true, ms(1000));
        assert_eq!(c.poll(ms(1000)), None);
        assert_eq!(c.deadline(), Some(ms(1030)));
        assert_eq!(c.poll(ms(1030)), None, "pressed, not yet released");
        assert_eq!(c.deadline(), Some(ms(1600)), "the long-press time");
        c.contact(Wire::F13, false, ms(1200));
        assert_eq!(c.deadline(), Some(ms(1230)));
        assert_eq!(c.poll(ms(1229)), None);
        assert_eq!(c.poll(ms(1230)), short(Wire::F13));
        assert_eq!(c.deadline(), None);
        assert_eq!(c.poll(ms(5000)), None);
    }

    #[test]
    fn a_held_press_is_long_at_once_and_its_release_does_nothing() {
        let mut c = classifier();
        c.contact(Wire::F15, true, ms(0));
        assert_eq!(c.poll(ms(30)), None);
        assert_eq!(c.poll(ms(599)), None);
        assert_eq!(c.poll(ms(600)), long(Wire::F15));
        assert_eq!(c.deadline(), None);
        assert_eq!(c.poll(ms(5000)), None, "held on: once");
        c.contact(Wire::F15, false, ms(6000));
        assert_eq!(c.deadline(), None);
        assert_eq!(c.poll(ms(6100)), None);
        // Pressed again: a new press, even unpolled until after the release.
        c.contact(Wire::F15, true, ms(7000));
        c.contact(Wire::F15, false, ms(7100));
        assert_eq!(c.poll(ms(7130)), short(Wire::F15));
    }

    #[test]
    fn a_blip_shorter_than_the_debounce_is_ignored() {
        let mut c = classifier();
        c.contact(Wire::F14, true, ms(0));
        c.contact(Wire::F14, false, ms(10));
        assert_eq!(c.deadline(), None);
        assert_eq!(c.poll(ms(100)), None);
    }

    #[test]
    fn bounce_on_closing_restarts_the_wait() {
        let mut c = classifier();
        c.contact(Wire::F17, true, ms(0));
        c.contact(Wire::F17, false, ms(3));
        c.contact(Wire::F17, true, ms(6));
        c.contact(Wire::F17, false, ms(8));
        c.contact(Wire::F17, true, ms(12));
        assert_eq!(c.deadline(), Some(ms(42)));
        assert_eq!(c.poll(ms(41)), None);
        assert_eq!(c.poll(ms(42)), None, "started");
        assert_eq!(c.deadline(), Some(ms(612)), "long from the last close");
    }

    #[test]
    fn bounce_on_release_is_the_same_press() {
        let mut c = classifier();
        c.contact(Wire::F17, true, ms(0));
        assert_eq!(c.poll(ms(30)), None);
        c.contact(Wire::F17, false, ms(200));
        c.contact(Wire::F17, true, ms(205));
        c.contact(Wire::F17, false, ms(210));
        assert_eq!(c.poll(ms(239)), None);
        assert_eq!(c.poll(ms(240)), short(Wire::F17));
        assert_eq!(c.poll(ms(500)), None, "once");
    }

    #[test]
    fn a_bounce_that_stays_closed_carries_on_to_a_long_press() {
        let mut c = classifier();
        c.contact(Wire::F16, true, ms(0));
        assert_eq!(c.poll(ms(30)), None);
        c.contact(Wire::F16, false, ms(300));
        c.contact(Wire::F16, true, ms(305));
        assert_eq!(c.poll(ms(400)), None);
        assert_eq!(c.poll(ms(600)), long(Wire::F16));
    }

    #[test]
    fn two_contacts_together_count_as_neither() {
        let mut c = classifier();
        c.contact(Wire::F13, true, ms(0));
        c.contact(Wire::F15, true, ms(5));
        assert_eq!(c.deadline(), None);
        assert_eq!(c.poll(ms(500)), None);
        // F15 opens: F13 alone now, counted from that moment.
        c.contact(Wire::F15, false, ms(600));
        assert_eq!(c.deadline(), Some(ms(630)));
        assert_eq!(c.poll(ms(630)), None);
        c.contact(Wire::F13, false, ms(700));
        assert_eq!(c.poll(ms(730)), short(Wire::F13));
    }

    #[test]
    fn a_diagonal_during_a_press_cancels_it() {
        let mut c = classifier();
        c.contact(Wire::F13, true, ms(0));
        assert_eq!(c.poll(ms(30)), None);
        c.contact(Wire::F16, true, ms(100));
        c.contact(Wire::F16, false, ms(120));
        // F13 alone again, but its press was cancelled: it must open first.
        assert_eq!(c.deadline(), None);
        assert_eq!(c.poll(ms(2000)), None, "no long press");
        c.contact(Wire::F13, false, ms(2100));
        assert_eq!(c.poll(ms(2200)), None, "no short press");
        c.contact(Wire::F13, true, ms(3000));
        c.contact(Wire::F13, false, ms(3100));
        assert_eq!(c.poll(ms(3130)), short(Wire::F13));
    }

    #[test]
    fn a_diagonal_after_a_long_press_adds_nothing() {
        let mut c = classifier();
        c.contact(Wire::F13, true, ms(0));
        assert_eq!(c.poll(ms(600)), long(Wire::F13));
        c.contact(Wire::F16, true, ms(700));
        c.contact(Wire::F16, false, ms(720));
        assert_eq!(c.poll(ms(3000)), None);
        c.contact(Wire::F13, false, ms(3100));
        assert_eq!(c.poll(ms(3200)), None);
    }

    #[test]
    fn rolling_from_one_direction_to_another_counts_the_second() {
        let mut c = classifier();
        c.contact(Wire::F13, true, ms(0));
        assert_eq!(c.poll(ms(30)), None);
        c.contact(Wire::F15, true, ms(200));
        c.contact(Wire::F13, false, ms(210));
        assert_eq!(c.poll(ms(239)), None);
        assert_eq!(c.poll(ms(240)), None, "F15 started; F13 cancelled");
        c.contact(Wire::F15, false, ms(400));
        assert_eq!(c.poll(ms(430)), short(Wire::F15));
        assert_eq!(c.poll(ms(1000)), None);
    }

    #[test]
    fn a_release_then_a_new_contact_counts_both_in_order() {
        let mut c = classifier();
        c.contact(Wire::F13, true, ms(0));
        assert_eq!(c.poll(ms(30)), None);
        c.contact(Wire::F13, false, ms(100));
        c.contact(Wire::F14, true, ms(110));
        assert_eq!(c.deadline(), Some(ms(130)));
        assert_eq!(c.poll(ms(140)), short(Wire::F13));
        assert_eq!(c.poll(ms(140)), None, "F14 started");
        c.contact(Wire::F14, false, ms(300));
        assert_eq!(c.poll(ms(330)), short(Wire::F14));
    }

    #[test]
    fn opening_a_contact_that_was_never_seen_closing_is_harmless() {
        // Held at start-up: the kernel reports only the release.
        let mut c = classifier();
        c.contact(Wire::F16, false, ms(50));
        assert_eq!(c.poll(ms(500)), None);
        assert_eq!(c.deadline(), None);
    }

    #[test]
    fn a_repeated_close_report_does_not_restart_the_wait() {
        let mut c = classifier();
        c.contact(Wire::F13, true, ms(0));
        c.contact(Wire::F13, true, ms(20));
        assert_eq!(c.poll(ms(30)), None);
        assert_eq!(c.poll(ms(600)), long(Wire::F13));
    }

    #[test]
    fn zero_debounce_counts_at_once() {
        let mut c = Classifier::new(Duration::ZERO, ms(600));
        c.contact(Wire::F14, true, ms(5));
        assert_eq!(c.poll(ms(5)), None);
        c.contact(Wire::F14, false, ms(50));
        assert_eq!(c.poll(ms(50)), short(Wire::F14));
    }
}
