//! The camera switch: five contacts, each closing to ground on its own GPIO
//! ([ADR-0024](../../../docs/architecture/adr/0024-camera-selection-switch-and-can-reverse.md)).
//!
//! The kernel reads the pins, not this service: one `gpio-key` overlay per
//! contact (`agl/boot/config-f250.txt`) turns each into a key on its own input
//! device, with the pull-up on and the kernel's 5 ms `gpio-keys` debounce
//! ([ADR-0025](../../../docs/architecture/adr/0025-camera-switch-through-gpio-key.md)).
//! The keys are F13–F17: nothing in the dashboard or the compositor acts on
//! them, unlike arrow keys, which would move the UI's focus.
//!
//! [`Debouncer`] then decides what counts as a move. It is pure logic: every
//! input comes with a monotonic time, so the tests drive it without a clock.
//!
//! - A contact counts once it has been the **only** closed contact for the
//!   debounce time (`switch_debounce_ms`, 30 ms by default, an example).
//!   Contact bounce restarts the wait.
//! - One closure is one move, however long it is held: the contact must open
//!   before it counts again.
//! - Two contacts closed together (a diagonal on a cheap rocker) count as
//!   neither, until one opens.
//! - A contact already held when the service starts isn't seen until it opens
//!   and closes again: the kernel reports only changes.
//!
//! Which camera a move shows, and latching it, is camera-manager's policy
//! ([camera-policy.md](../../../docs/architecture/camera-policy.md)).
//! [`camera_link`](crate::camera_link) passes the moves to it.

use std::time::Duration;

/// The default debounce time. An example value: tune it on the switch that is
/// fitted (H32).
pub const DEFAULT_DEBOUNCE: Duration = Duration::from_millis(30);

/// One direction of the switch.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Direction {
    Left,
    Right,
    Back,
    Forward,
    Press,
}

impl Direction {
    pub const ALL: [Direction; 5] = [
        Direction::Left,
        Direction::Right,
        Direction::Back,
        Direction::Forward,
        Direction::Press,
    ];

    /// The key the `gpio-key` overlay gives this contact
    /// (`linux/input-event-codes.h`). Must match `agl/boot/config-f250.txt`.
    pub const fn keycode(self) -> u16 {
        match self {
            Direction::Left => 183,    // KEY_F13
            Direction::Right => 184,   // KEY_F14
            Direction::Back => 185,    // KEY_F15
            Direction::Forward => 186, // KEY_F16
            Direction::Press => 187,   // KEY_F17
        }
    }

    pub fn from_keycode(code: u16) -> Option<Self> {
        Self::ALL.into_iter().find(|d| d.keycode() == code)
    }

    /// The five key codes.
    pub fn keycodes() -> [u16; 5] {
        Self::ALL.map(Direction::keycode)
    }

    pub const fn name(self) -> &'static str {
        match self {
            Direction::Left => "left",
            Direction::Right => "right",
            Direction::Back => "back",
            Direction::Forward => "forward",
            Direction::Press => "press",
        }
    }

    const fn bit(self) -> u8 {
        1 << self as u8
    }

    fn from_single_bit(mask: u8) -> Option<Self> {
        (mask.count_ones() == 1)
            .then(|| Self::ALL.into_iter().find(|d| d.bit() == mask))
            .flatten()
    }
}

/// Turns contact changes into moves.
#[derive(Debug, Clone)]
pub struct Debouncer {
    debounce: Duration,
    /// Contacts closed now.
    closed: u8,
    /// When `closed` last changed.
    changed_at: Duration,
    /// Contacts that have counted and not opened since.
    counted: u8,
}

impl Debouncer {
    pub fn new(debounce: Duration) -> Self {
        Self {
            debounce,
            closed: 0,
            changed_at: Duration::ZERO,
            counted: 0,
        }
    }

    pub fn debounce(&self) -> Duration {
        self.debounce
    }

    /// A contact closed (`true`) or opened (`false`) at `now`.
    pub fn contact(&mut self, direction: Direction, closed: bool, now: Duration) {
        let bit = direction.bit();
        let before = self.closed;
        if closed {
            self.closed |= bit;
        } else {
            self.closed &= !bit;
            self.counted &= !bit;
        }
        if self.closed != before {
            self.changed_at = now;
        }
    }

    /// The move that counts at `now`, if one does. Call it after every
    /// contact change and when [`Self::deadline`] passes.
    pub fn poll(&mut self, now: Duration) -> Option<Direction> {
        let direction = self.waiting()?;
        if now.saturating_sub(self.changed_at) < self.debounce {
            return None;
        }
        self.counted |= direction.bit();
        Some(direction)
    }

    /// When the contact that is waiting will count if nothing changes: the
    /// time to call [`Self::poll`] next. `None` when nothing is waiting.
    pub fn deadline(&self) -> Option<Duration> {
        self.waiting().map(|_| self.changed_at + self.debounce)
    }

    /// The single closed contact that hasn't counted yet.
    fn waiting(&self) -> Option<Direction> {
        Direction::from_single_bit(self.closed).filter(|d| self.counted & d.bit() == 0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ms(n: u64) -> Duration {
        Duration::from_millis(n)
    }
    fn debouncer() -> Debouncer {
        Debouncer::new(ms(30))
    }

    #[test]
    fn keycodes_are_f13_to_f17_and_round_trip() {
        assert_eq!(Direction::keycodes(), [183, 184, 185, 186, 187]);
        for d in Direction::ALL {
            assert_eq!(Direction::from_keycode(d.keycode()), Some(d));
        }
        assert_eq!(Direction::from_keycode(116), None, "KEY_POWER");
        assert_eq!(Direction::from_keycode(105), None, "KEY_LEFT");
    }

    #[test]
    fn a_clean_press_counts_after_the_debounce() {
        let mut d = debouncer();
        d.contact(Direction::Left, true, ms(1000));
        assert_eq!(d.poll(ms(1000)), None);
        assert_eq!(d.deadline(), Some(ms(1030)));
        assert_eq!(d.poll(ms(1029)), None);
        assert_eq!(d.poll(ms(1030)), Some(Direction::Left));
        assert_eq!(d.deadline(), None);
    }

    #[test]
    fn a_held_contact_counts_once() {
        let mut d = debouncer();
        d.contact(Direction::Back, true, ms(0));
        assert_eq!(d.poll(ms(40)), Some(Direction::Back));
        assert_eq!(d.poll(ms(5000)), None);
        d.contact(Direction::Back, false, ms(6000));
        assert_eq!(d.poll(ms(6100)), None);
        // Closed again: a new move.
        d.contact(Direction::Back, true, ms(7000));
        assert_eq!(d.poll(ms(7030)), Some(Direction::Back));
    }

    #[test]
    fn a_blip_shorter_than_the_debounce_is_ignored() {
        let mut d = debouncer();
        d.contact(Direction::Right, true, ms(0));
        d.contact(Direction::Right, false, ms(10));
        assert_eq!(d.deadline(), None);
        assert_eq!(d.poll(ms(100)), None);
    }

    #[test]
    fn bounce_restarts_the_wait() {
        let mut d = debouncer();
        d.contact(Direction::Press, true, ms(0));
        d.contact(Direction::Press, false, ms(3));
        d.contact(Direction::Press, true, ms(6));
        d.contact(Direction::Press, false, ms(8));
        d.contact(Direction::Press, true, ms(12));
        assert_eq!(d.deadline(), Some(ms(42)));
        assert_eq!(d.poll(ms(41)), None);
        assert_eq!(d.poll(ms(42)), Some(Direction::Press));
    }

    #[test]
    fn two_contacts_together_count_as_neither() {
        let mut d = debouncer();
        d.contact(Direction::Left, true, ms(0));
        d.contact(Direction::Back, true, ms(5));
        assert_eq!(d.deadline(), None);
        assert_eq!(d.poll(ms(500)), None);
        // Back opens: Left alone now, counted from that moment.
        d.contact(Direction::Back, false, ms(600));
        assert_eq!(d.deadline(), Some(ms(630)));
        assert_eq!(d.poll(ms(630)), Some(Direction::Left));
    }

    #[test]
    fn a_counted_contact_does_not_count_again_after_a_diagonal() {
        let mut d = debouncer();
        d.contact(Direction::Left, true, ms(0));
        assert_eq!(d.poll(ms(30)), Some(Direction::Left));
        // Rocked into the diagonal and back, Left never opening.
        d.contact(Direction::Forward, true, ms(100));
        d.contact(Direction::Forward, false, ms(120));
        assert_eq!(d.deadline(), None);
        assert_eq!(d.poll(ms(500)), None);
    }

    #[test]
    fn rolling_from_one_direction_to_another_counts_both() {
        let mut d = debouncer();
        d.contact(Direction::Left, true, ms(0));
        assert_eq!(d.poll(ms(30)), Some(Direction::Left));
        d.contact(Direction::Back, true, ms(200));
        d.contact(Direction::Left, false, ms(210));
        assert_eq!(d.poll(ms(239)), None);
        assert_eq!(d.poll(ms(240)), Some(Direction::Back));
    }

    #[test]
    fn opening_a_contact_that_was_never_seen_closing_is_harmless() {
        // Held at start-up: the kernel reports only the release.
        let mut d = debouncer();
        d.contact(Direction::Forward, false, ms(50));
        assert_eq!(d.poll(ms(500)), None);
        assert_eq!(d.deadline(), None);
    }

    #[test]
    fn a_repeated_close_report_does_not_restart_the_wait() {
        let mut d = debouncer();
        d.contact(Direction::Left, true, ms(0));
        d.contact(Direction::Left, true, ms(20));
        assert_eq!(d.poll(ms(30)), Some(Direction::Left));
    }

    #[test]
    fn zero_debounce_counts_at_once() {
        let mut d = Debouncer::new(Duration::ZERO);
        d.contact(Direction::Right, true, ms(5));
        assert_eq!(d.poll(ms(5)), Some(Direction::Right));
    }
}
