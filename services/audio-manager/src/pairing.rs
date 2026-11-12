//! The pairing window (ADR-0039 decision 3): the head unit is discoverable
//! and pairable only after the driver asks, from the dashboard, and only for
//! a limited time; it closes by itself, and as soon as one phone has paired.
//! A phone asking to pair shows a six-digit code, which the driver confirms
//! on the screen.
//!
//! Pure and time-injected: the manager feeds it events and carries out the
//! [`Action`]s it returns (setting the adapter's `Discoverable` and
//! `Pairable` through the backend).

use std::time::Duration;

use tokio::time::Instant;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum State {
    /// Not discoverable; new phones are refused.
    Closed,
    /// Asked the adapter to open; not confirmed yet.
    Opening,
    /// Discoverable and pairable until `until`.
    Open,
    /// Asked the adapter to close; not confirmed yet.
    Closing,
    /// The adapter refused, or didn't answer.
    Failed,
}

/// What the manager must do to the adapter.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    /// Set `Discoverable` and `Pairable` to `on`. When opening, the adapter's
    /// own `DiscoverableTimeout`/`PairableTimeout` are set to `timeout_s`, so
    /// BlueZ closes the window by itself even if audio-manager dies.
    Adapter { on: bool, timeout_s: u32 },
}

/// The result of an event: what to do to the adapter, and a question that
/// was dropped (to be answered "no" to the phone).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Outcome {
    pub action: Option<Action>,
    pub dropped: Option<u64>,
}

impl Outcome {
    fn act(on: bool, timeout_s: u32) -> Outcome {
        Outcome {
            action: Some(Action::Adapter { on, timeout_s }),
            dropped: None,
        }
    }
}

/// A phone waiting for the driver's answer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Question {
    pub id: u64,
    pub address: String,
    pub name: String,
    /// The code the phone shows; None for a pairing with no code.
    pub passkey: Option<u32>,
    pub deadline: Instant,
}

/// The window's limits. The values in `Default` are examples
/// (configuration, CLAUDE.md rule 10).
#[derive(Debug, Clone, Copy)]
pub struct Config {
    /// The window's length when the dashboard doesn't say.
    pub default: Duration,
    /// The longest window anyone may ask for.
    pub max: Duration,
    /// The shortest.
    pub min: Duration,
    /// How long a code waits for the driver.
    pub answer: Duration,
    /// How long the adapter may take to open or close.
    pub adapter: Duration,
}

impl Default for Config {
    fn default() -> Config {
        Config {
            default: Duration::from_secs(120),
            max: Duration::from_secs(300),
            min: Duration::from_secs(10),
            answer: Duration::from_secs(30),
            adapter: Duration::from_secs(5),
        }
    }
}

#[derive(Debug)]
pub struct Window {
    cfg: Config,
    state: State,
    available: bool,
    /// The length asked for.
    length: Duration,
    /// When Open ends.
    until: Option<Instant>,
    /// When the adapter was asked (Opening, Closing).
    asked: Option<Instant>,
    detail: String,
    question: Option<Question>,
    next_id: u64,
}

fn secs(d: Duration) -> u32 {
    u32::try_from(d.as_secs()).unwrap_or(u32::MAX)
}

impl Window {
    pub fn new(cfg: Config) -> Window {
        Window {
            cfg,
            state: State::Closed,
            available: false,
            length: cfg.default,
            until: None,
            asked: None,
            detail: String::new(),
            question: None,
            next_id: 1,
        }
    }

    pub fn state(&self) -> State {
        self.state
    }

    pub fn detail(&self) -> &str {
        &self.detail
    }

    pub fn question(&self) -> Option<&Question> {
        self.question.as_ref()
    }

    /// Whole seconds until it closes by itself (rounded up); 0 unless open.
    pub fn seconds_left(&self, now: Instant) -> u32 {
        match (self.state, self.until) {
            (State::Open, Some(u)) => {
                let left = u.saturating_duration_since(now);
                let s = secs(left);
                if left.subsec_nanos() > 0 { s + 1 } else { s }
            }
            _ => 0,
        }
    }

    fn drop_question(&mut self) -> Option<u64> {
        self.question.take().map(|q| q.id)
    }

    /// The adapter is up (again). Nothing opens by itself.
    pub fn adapter_ready(&mut self) {
        self.available = true;
    }

    /// The adapter or BlueZ went away: the window is closed (a restarted
    /// BlueZ starts non-discoverable), and any question is dropped.
    pub fn adapter_lost(&mut self) -> Outcome {
        self.available = false;
        let was = self.state;
        self.state = State::Closed;
        self.until = None;
        self.asked = None;
        if was != State::Closed {
            self.detail = "Bluetooth stopped: the pairing window is closed.".into();
        }
        Outcome {
            action: None,
            dropped: self.drop_question(),
        }
    }

    /// The driver asks for a window of `seconds` (None: the default),
    /// clamped to the limits. An open window starts its countdown again.
    pub fn open(&mut self, now: Instant, seconds: Option<u32>) -> Result<Outcome, String> {
        if !self.available {
            return Err("Bluetooth is unavailable: the pairing window can't open.".into());
        }
        let want = seconds.map_or(self.cfg.default, |s| Duration::from_secs(s.into()));
        self.length = want.clamp(self.cfg.min, self.cfg.max);
        let t = secs(self.length);
        Ok(match self.state {
            State::Closed | State::Failed | State::Closing => {
                self.state = State::Opening;
                self.asked = Some(now);
                self.detail = String::new();
                Outcome::act(true, t)
            }
            // The confirmation starts the countdown with the new length.
            State::Opening => Outcome::default(),
            State::Open => {
                self.until = Some(now + self.length);
                Outcome::act(true, t)
            }
        })
    }

    /// The driver closes the window. False: it wasn't open or opening.
    pub fn close(&mut self, now: Instant) -> (bool, Outcome) {
        match self.state {
            State::Opening | State::Open => {
                let dropped = self.drop_question();
                self.begin_close(now, "Closed.");
                (
                    true,
                    Outcome {
                        dropped,
                        ..Outcome::act(false, 0)
                    },
                )
            }
            _ => (false, Outcome::default()),
        }
    }

    fn begin_close(&mut self, now: Instant, why: &str) {
        self.state = State::Closing;
        self.until = None;
        self.asked = Some(now);
        self.detail = why.into();
    }

    /// The adapter answered an [`Action`]. Answers that no longer match the
    /// state (the driver changed their mind meanwhile) are ignored.
    pub fn adapter_done(&mut self, now: Instant, on: bool, result: Result<(), String>) -> Outcome {
        match (self.state, on, result) {
            (State::Opening, true, Ok(())) => {
                self.state = State::Open;
                self.asked = None;
                self.until = Some(now + self.length);
                Outcome::default()
            }
            (State::Opening, true, Err(e)) => {
                self.state = State::Failed;
                self.asked = None;
                self.detail = format!("Bluetooth refused to open the pairing window: {e}");
                // Make sure it isn't left half open.
                Outcome::act(false, 0)
            }
            (State::Closing, false, Ok(())) => {
                self.state = State::Closed;
                self.asked = None;
                Outcome::default()
            }
            (State::Closing, false, Err(e)) => {
                self.state = State::Failed;
                self.asked = None;
                self.detail = format!(
                    "Bluetooth didn't close the pairing window ({e}); it closes by itself within {} s.",
                    secs(self.length)
                );
                Outcome::default()
            }
            _ => Outcome::default(),
        }
    }

    /// The adapter stopped being discoverable on its own (its timeout, or
    /// someone else): an open window is closed.
    pub fn discoverable_ended(&mut self) -> Outcome {
        if self.state != State::Open {
            return Outcome::default();
        }
        self.state = State::Closed;
        self.until = None;
        self.detail = "Bluetooth closed the pairing window.".into();
        Outcome {
            action: None,
            dropped: self.drop_question(),
        }
    }

    /// A phone has paired: the window closes, one phone per window.
    pub fn paired(&mut self, now: Instant, name: &str) -> Outcome {
        match self.state {
            State::Open | State::Opening => {
                let dropped = self.drop_question();
                self.begin_close(now, &format!("Paired with {name}."));
                Outcome {
                    dropped,
                    ..Outcome::act(false, 0)
                }
            }
            _ => Outcome::default(),
        }
    }

    /// Time passes: the window closes at its end; a question nobody answered
    /// is dropped; an adapter that doesn't answer is given up on.
    pub fn tick(&mut self, now: Instant) -> Outcome {
        let mut out = Outcome::default();
        if self.question.as_ref().is_some_and(|q| now >= q.deadline) {
            out.dropped = self.drop_question();
            self.detail = "No answer: the phone was refused.".into();
        }
        match self.state {
            State::Open if self.until.is_some_and(|u| now >= u) => {
                if let Some(d) = self.drop_question() {
                    out.dropped = Some(d);
                }
                let s = secs(self.length);
                self.begin_close(now, &format!("Closed by itself after {s} s."));
                out.action = Some(Action::Adapter {
                    on: false,
                    timeout_s: 0,
                });
            }
            State::Opening | State::Closing
                if self.asked.is_some_and(|a| now >= a + self.cfg.adapter) =>
            {
                let opening = self.state == State::Opening;
                self.state = State::Failed;
                self.asked = None;
                self.detail = if opening {
                    "Bluetooth didn't answer: the pairing window didn't open.".into()
                } else {
                    format!(
                        "Bluetooth didn't answer; the window closes by itself within {} s.",
                        secs(self.length)
                    )
                };
                if opening {
                    out.action = Some(Action::Adapter {
                        on: false,
                        timeout_s: 0,
                    });
                }
            }
            _ => {}
        }
        out
    }

    /// A phone asks to pair. Only while the window is open, and one at a
    /// time: Err means "refuse it now".
    pub fn ask(
        &mut self,
        now: Instant,
        address: &str,
        name: &str,
        passkey: Option<u32>,
    ) -> Result<u64, String> {
        if self.state != State::Open {
            return Err("the pairing window is closed".into());
        }
        if self.question.is_some() {
            return Err("another phone is waiting for an answer".into());
        }
        let id = self.next_id;
        self.next_id += 1;
        self.question = Some(Question {
            id,
            address: address.into(),
            name: name.into(),
            passkey: passkey.filter(|p| *p <= 999_999),
            deadline: now + self.cfg.answer,
        });
        Ok(id)
    }

    /// The driver answered question `id`. False: no such question (already
    /// answered, timed out or dropped).
    pub fn answer(&mut self, id: u64, accept: bool) -> bool {
        match &self.question {
            Some(q) if q.id == id => {
                self.detail = if accept {
                    format!("Pairing with {}…", q.name)
                } else {
                    format!("Refused {}.", q.name)
                };
                self.question = None;
                true
            }
            _ => false,
        }
    }

    /// The phone gave up (BlueZ `Agent1.Cancel`).
    pub fn cancelled(&mut self, id: u64) {
        if self.question.as_ref().is_some_and(|q| q.id == id) {
            self.question = None;
            self.detail = "The phone cancelled pairing.".into();
        }
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    fn on(t: u32) -> Option<Action> {
        Some(Action::Adapter {
            on: true,
            timeout_s: t,
        })
    }
    const OFF: Option<Action> = Some(Action::Adapter {
        on: false,
        timeout_s: 0,
    });

    fn ready() -> (Window, Instant) {
        let mut w = Window::new(Config::default());
        w.adapter_ready();
        (w, Instant::now())
    }

    fn open(w: &mut Window, t: Instant) {
        assert_eq!(w.open(t, None).unwrap().action, on(120));
        assert_eq!(w.adapter_done(t, true, Ok(())), Outcome::default());
        assert_eq!(w.state(), State::Open);
    }

    fn s(n: u64) -> Duration {
        Duration::from_secs(n)
    }

    #[test]
    fn closed_until_asked_and_refused_without_bluetooth() {
        let mut w = Window::new(Config::default());
        assert_eq!(w.state(), State::Closed);
        assert!(w.open(Instant::now(), None).is_err(), "no adapter yet");
        assert_eq!(w.state(), State::Closed);
    }

    #[test]
    fn closed_opening_open_closes_by_itself() {
        let (mut w, t) = ready();
        assert_eq!(w.open(t, None).unwrap().action, on(120));
        assert_eq!(w.state(), State::Opening);
        assert_eq!(
            w.seconds_left(t),
            0,
            "no countdown until the adapter confirms"
        );
        let t1 = t + Duration::from_millis(300);
        w.adapter_done(t1, true, Ok(()));
        assert_eq!(w.state(), State::Open);
        assert_eq!(w.seconds_left(t1), 120);
        assert_eq!(
            w.seconds_left(t1 + Duration::from_millis(500)),
            120,
            "rounded up"
        );
        assert_eq!(w.seconds_left(t1 + s(119)), 1);
        assert_eq!(w.tick(t1 + s(119)), Outcome::default());
        assert_eq!(w.tick(t1 + s(120)).action, OFF);
        assert_eq!(w.state(), State::Closing);
        assert_eq!(w.detail(), "Closed by itself after 120 s.");
        w.adapter_done(t1 + s(120), false, Ok(()));
        assert_eq!(w.state(), State::Closed);
    }

    #[test]
    fn length_is_clamped() {
        let (mut w, t) = ready();
        assert_eq!(w.open(t, Some(3600)).unwrap().action, on(300));
        let (mut w, t) = ready();
        assert_eq!(w.open(t, Some(1)).unwrap().action, on(10));
        let (mut w, t) = ready();
        assert_eq!(w.open(t, Some(60)).unwrap().action, on(60));
    }

    #[test]
    fn open_again_restarts_the_countdown() {
        let (mut w, t) = ready();
        open(&mut w, t);
        assert_eq!(w.open(t + s(100), Some(60)).unwrap().action, on(60));
        assert_eq!(w.state(), State::Open);
        assert_eq!(w.seconds_left(t + s(100)), 60);
        assert_eq!(w.tick(t + s(130)).action, None, "not closed at the old end");
    }

    #[test]
    fn open_while_opening_takes_the_new_length_without_asking_again() {
        let (mut w, t) = ready();
        w.open(t, Some(60)).unwrap();
        assert_eq!(w.open(t, Some(200)).unwrap(), Outcome::default());
        w.adapter_done(t, true, Ok(()));
        assert_eq!(w.seconds_left(t), 200);
    }

    #[test]
    fn close_from_open_and_from_opening() {
        let (mut w, t) = ready();
        open(&mut w, t);
        let (was, out) = w.close(t + s(5));
        assert!(was);
        assert_eq!(out.action, OFF);
        assert_eq!(w.state(), State::Closing);
        assert_eq!(w.seconds_left(t + s(5)), 0);
        w.adapter_done(t + s(5), false, Ok(()));
        assert_eq!(w.state(), State::Closed);

        let (mut w, t) = ready();
        w.open(t, None).unwrap();
        assert!(w.close(t).0);
        assert_eq!(w.state(), State::Closing);
        // The late "opened" answer is ignored.
        w.adapter_done(t, true, Ok(()));
        assert_eq!(w.state(), State::Closing);
    }

    #[test]
    fn close_when_closed_does_nothing() {
        let (mut w, t) = ready();
        assert_eq!(w.close(t), (false, Outcome::default()));
        assert_eq!(w.state(), State::Closed);
    }

    #[test]
    fn reopen_while_closing() {
        let (mut w, t) = ready();
        open(&mut w, t);
        w.close(t);
        assert_eq!(w.open(t, None).unwrap().action, on(120));
        assert_eq!(w.state(), State::Opening);
        // The late "closed" answer is ignored.
        w.adapter_done(t, false, Ok(()));
        assert_eq!(w.state(), State::Opening);
    }

    #[test]
    fn adapter_refuses_to_open() {
        let (mut w, t) = ready();
        w.open(t, None).unwrap();
        let out = w.adapter_done(t, true, Err("org.bluez.Error.Failed".into()));
        assert_eq!(out.action, OFF, "made sure it is closed");
        assert_eq!(w.state(), State::Failed);
        assert!(w.detail().contains("refused"));
        // Failed → Opening again.
        assert_eq!(w.open(t, None).unwrap().action, on(120));
        assert_eq!(w.state(), State::Opening);
    }

    #[test]
    fn adapter_refuses_to_close() {
        let (mut w, t) = ready();
        open(&mut w, t);
        w.close(t);
        w.adapter_done(t, false, Err("no".into()));
        assert_eq!(w.state(), State::Failed);
        assert!(w.detail().contains("closes by itself within 120 s"));
    }

    #[test]
    fn adapter_silent_while_opening_or_closing() {
        let (mut w, t) = ready();
        w.open(t, None).unwrap();
        assert_eq!(w.tick(t + s(4)), Outcome::default());
        assert_eq!(w.tick(t + s(5)).action, OFF);
        assert_eq!(w.state(), State::Failed);
        assert!(w.detail().contains("didn't open"));

        let (mut w, t) = ready();
        open(&mut w, t);
        w.close(t);
        assert_eq!(w.tick(t + s(5)).action, None);
        assert_eq!(w.state(), State::Failed);
        assert!(w.detail().contains("closes by itself"));
    }

    #[test]
    fn bluez_closes_it_first() {
        let (mut w, t) = ready();
        open(&mut w, t);
        w.ask(t, "A", "Pixel", Some(1)).unwrap();
        let out = w.discoverable_ended();
        assert_eq!(out.dropped, Some(1));
        assert_eq!(w.state(), State::Closed);
        // Only an open window is affected.
        let (mut w, _) = ready();
        assert_eq!(w.discoverable_ended(), Outcome::default());
    }

    #[test]
    fn adapter_lost_closes_from_every_state() {
        for setup in 0..4 {
            let (mut w, t) = ready();
            match setup {
                0 => {}
                1 => {
                    w.open(t, None).unwrap();
                }
                2 => open(&mut w, t),
                _ => {
                    open(&mut w, t);
                    w.close(t);
                }
            }
            w.adapter_lost();
            assert_eq!(w.state(), State::Closed, "setup {setup}");
            assert!(w.open(t, None).is_err(), "unavailable until ready again");
            w.adapter_ready();
            assert!(w.open(t, None).is_ok());
        }
    }

    #[test]
    fn a_phone_pairing_closes_the_window() {
        let (mut w, t) = ready();
        open(&mut w, t);
        let id = w.ask(t, "AA", "Pixel 8", Some(42)).unwrap();
        assert!(w.answer(id, true));
        assert_eq!(w.detail(), "Pairing with Pixel 8…");
        let out = w.paired(t + s(2), "Pixel 8");
        assert_eq!(out.action, OFF);
        assert_eq!(w.state(), State::Closing);
        assert_eq!(w.detail(), "Paired with Pixel 8.");
        // A pairing outside the window (the MX+ from bluetoothctl) changes nothing.
        let (mut w, t) = ready();
        assert_eq!(w.paired(t, "OBDLink"), Outcome::default());
        assert_eq!(w.state(), State::Closed);
    }

    #[test]
    fn questions_only_while_open_and_one_at_a_time() {
        let (mut w, t) = ready();
        assert!(w.ask(t, "A", "x", Some(1)).is_err(), "closed");
        w.open(t, None).unwrap();
        assert!(w.ask(t, "A", "x", Some(1)).is_err(), "opening");
        w.adapter_done(t, true, Ok(()));
        let id = w.ask(t, "A", "x", Some(123_456)).unwrap();
        assert_eq!(w.question().unwrap().passkey, Some(123_456));
        assert!(w.ask(t, "B", "y", Some(2)).is_err(), "one at a time");
        assert!(!w.answer(id + 1, true), "no such question");
        assert!(w.answer(id, false));
        assert_eq!(w.detail(), "Refused x.");
        assert!(!w.answer(id, true), "already answered");
        assert!(w.question().is_none());
        // A code that isn't six digits isn't shown as one.
        let id = w.ask(t, "A", "x", Some(1_000_000)).unwrap();
        assert_eq!(w.question().unwrap().passkey, None);
        w.cancelled(id);
        assert!(w.question().is_none());
        assert_eq!(w.detail(), "The phone cancelled pairing.");
    }

    #[test]
    fn unanswered_question_is_refused() {
        let (mut w, t) = ready();
        open(&mut w, t);
        let id = w.ask(t, "A", "x", Some(1)).unwrap();
        assert_eq!(w.tick(t + s(29)).dropped, None);
        assert_eq!(w.tick(t + s(30)).dropped, Some(id));
        assert_eq!(w.state(), State::Open, "the window stays open");
    }

    #[test]
    fn closing_drops_the_question() {
        let (mut w, t) = ready();
        open(&mut w, t);
        let id = w.ask(t, "A", "x", None).unwrap();
        assert_eq!(w.close(t).1.dropped, Some(id));

        let (mut w, t) = ready();
        open(&mut w, t);
        let id = w.ask(t + s(110), "A", "x", None).unwrap();
        let out = w.tick(t + s(120));
        assert_eq!(out.dropped, Some(id), "the window's end drops it");
        assert_eq!(out.action, OFF);

        let (mut w, t) = ready();
        open(&mut w, t);
        let id = w.ask(t, "A", "x", None).unwrap();
        assert_eq!(w.adapter_lost().dropped, Some(id));
    }
}
