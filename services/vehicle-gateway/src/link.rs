//! Per-link state machine with a bounded recovery ladder
//! (docs/architecture/diagnostic-recovery.md).
//!
//! The machine decides; the caller acts. Every event returns at most one
//! [`Action`] for the transport layer to perform. Recovery escalates
//! soft → adapter reset → reconnect, then backs off exponentially (with
//! jitter, capped) and eventually reports `FAULT`. It never reboots anything
//! and never transmits faster than normal polling.

use std::time::Duration;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecoveryStep {
    /// Bare CR / drain the socket.
    Soft,
    /// `ATZ` and the full init sequence / re-create sockets.
    Reset,
    /// Close and reopen the RFCOMM/serial link / interface down-up.
    Reconnect,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MachineState {
    /// Not started.
    Disabled,
    /// Transmit not enabled (ADR-0007): nothing is sent to the vehicle.
    PassiveOnly,
    Connecting,
    Initializing,
    Polling,
    /// Up, but a large share of active PIDs is failing.
    Degraded,
    Recovering(RecoveryStep),
    Backoff,
    /// Gave up after too many attempts. Leaves on operator retry.
    Fault,
}

impl MachineState {
    pub fn as_str(self) -> &'static str {
        match self {
            MachineState::Disabled => "DISABLED",
            MachineState::PassiveOnly => "PASSIVE_ONLY",
            MachineState::Connecting => "CONNECTING",
            MachineState::Initializing => "INITIALIZING",
            MachineState::Polling => "POLLING",
            MachineState::Degraded => "DEGRADED",
            MachineState::Recovering(RecoveryStep::Soft) => "RECOVERING_SOFT",
            MachineState::Recovering(RecoveryStep::Reset) => "RECOVERING_RESET",
            MachineState::Recovering(RecoveryStep::Reconnect) => "RECOVERING_RECONNECT",
            MachineState::Backoff => "BACKOFF",
            MachineState::Fault => "FAULT",
        }
    }

    /// Whether the scheduler may send requests.
    pub fn may_poll(self) -> bool {
        matches!(self, MachineState::Polling | MachineState::Degraded)
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Event {
    Start {
        transmit_enabled: bool,
    },
    Connected,
    ConnectFailed,
    InitOk,
    InitFailed,
    Disconnected,
    /// Periodic health summary from the scheduler.
    Health {
        active: usize,
        failing: usize,
        /// How long no PID at all has answered.
        all_silent_for: Duration,
    },
    RecoveryOk,
    RecoveryFailed,
    OperatorRetry,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Action {
    Connect,
    InitAdapter,
    Recover(RecoveryStep),
    /// Try connecting again at this time.
    RetryAt(Duration),
}

#[derive(Debug, Clone, PartialEq)]
pub struct LinkPolicy {
    /// Fraction of active PIDs failing that counts as degraded.
    pub degraded_fraction: f64,
    /// No answers at all for this long triggers recovery.
    pub dead_after: Duration,
    pub backoff_initial: Duration,
    pub backoff_max: Duration,
    /// Consecutive failed attempts before FAULT.
    pub fault_after: u32,
}

impl Default for LinkPolicy {
    fn default() -> Self {
        LinkPolicy {
            degraded_fraction: 0.5,
            dead_after: Duration::from_secs(5),
            backoff_initial: Duration::from_secs(2),
            backoff_max: Duration::from_secs(60),
            fault_after: 10,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Change {
    pub from: MachineState,
    pub to: MachineState,
    pub why: String,
}

#[derive(Debug, Clone)]
pub struct LinkMachine {
    state: MachineState,
    since: Duration,
    policy: LinkPolicy,
    attempts: u32,
    backoff: Duration,
    retry_at: Option<Duration>,
    jitter_seed: u64,
    changes: Vec<Change>,
}

impl LinkMachine {
    pub fn new(policy: LinkPolicy, jitter_seed: u64) -> Self {
        let backoff = policy.backoff_initial;
        LinkMachine {
            state: MachineState::Disabled,
            since: Duration::ZERO,
            policy,
            attempts: 0,
            backoff,
            retry_at: None,
            jitter_seed,
            changes: Vec::new(),
        }
    }

    pub fn state(&self) -> MachineState {
        self.state
    }

    pub fn since(&self) -> Duration {
        self.since
    }

    pub fn attempts(&self) -> u32 {
        self.attempts
    }

    /// State changes since the last call, for the event log.
    pub fn take_changes(&mut self) -> Vec<Change> {
        std::mem::take(&mut self.changes)
    }

    /// Call periodically; fires the backoff retry.
    pub fn tick(&mut self, now: Duration) -> Option<Action> {
        if self.state == MachineState::Backoff && self.retry_at.is_some_and(|t| now >= t) {
            self.retry_at = None;
            self.go(MachineState::Connecting, now, "backoff elapsed");
            return Some(Action::Connect);
        }
        None
    }

    pub fn handle(&mut self, ev: Event, now: Duration) -> Option<Action> {
        use MachineState as S;
        match (self.state, ev) {
            (
                _,
                Event::Start {
                    transmit_enabled: false,
                },
            ) => {
                self.go(S::PassiveOnly, now, "transmit disabled (ADR-0007)");
                None
            }
            (
                _,
                Event::Start {
                    transmit_enabled: true,
                },
            )
            | (S::Fault, Event::OperatorRetry) => {
                self.attempts = 0;
                self.backoff = self.policy.backoff_initial;
                self.go(S::Connecting, now, "start");
                Some(Action::Connect)
            }
            (S::Connecting, Event::Connected) => {
                self.go(S::Initializing, now, "connected");
                Some(Action::InitAdapter)
            }
            (S::Connecting, Event::ConnectFailed) | (S::Initializing, Event::InitFailed) => {
                self.back_off(now, "connect/init failed")
            }
            (S::Initializing, Event::InitOk) => {
                self.attempts = 0;
                self.backoff = self.policy.backoff_initial;
                self.go(S::Polling, now, "adapter initialised");
                None
            }
            (
                S::Polling | S::Degraded | S::Initializing | S::Recovering(_),
                Event::Disconnected,
            ) => self.back_off(now, "disconnected"),
            (
                S::Polling | S::Degraded,
                Event::Health {
                    active,
                    failing,
                    all_silent_for,
                },
            ) => {
                if active > 0 && all_silent_for >= self.policy.dead_after {
                    self.go(S::Recovering(RecoveryStep::Soft), now, "no answers");
                    return Some(Action::Recover(RecoveryStep::Soft));
                }
                let degraded = active > 0
                    && (failing as f64) >= self.policy.degraded_fraction * (active as f64);
                match (self.state, degraded) {
                    (S::Polling, true) => self.go(S::Degraded, now, "many PIDs failing"),
                    (S::Degraded, false) => self.go(S::Polling, now, "recovered"),
                    _ => {}
                }
                None
            }
            (S::Recovering(_), Event::RecoveryOk) => {
                self.attempts = 0;
                self.backoff = self.policy.backoff_initial;
                self.go(S::Polling, now, "recovery step worked");
                None
            }
            (S::Recovering(step), Event::RecoveryFailed) => match step {
                RecoveryStep::Soft => {
                    self.go(
                        S::Recovering(RecoveryStep::Reset),
                        now,
                        "soft recovery failed",
                    );
                    Some(Action::Recover(RecoveryStep::Reset))
                }
                RecoveryStep::Reset => {
                    self.go(S::Recovering(RecoveryStep::Reconnect), now, "reset failed");
                    Some(Action::Recover(RecoveryStep::Reconnect))
                }
                RecoveryStep::Reconnect => self.back_off(now, "reconnect failed"),
            },
            _ => None, // events that don't apply in this state are ignored
        }
    }

    fn back_off(&mut self, now: Duration, why: &str) -> Option<Action> {
        self.attempts += 1;
        if self.attempts >= self.policy.fault_after {
            self.go(
                MachineState::Fault,
                now,
                &format!("{why}; gave up after {} attempts", self.attempts),
            );
            return None;
        }
        let delay = self.backoff + self.jitter(self.backoff / 4);
        self.backoff = (self.backoff * 2).min(self.policy.backoff_max);
        let at = now + delay;
        self.retry_at = Some(at);
        self.go(
            MachineState::Backoff,
            now,
            &format!("{why}; retry in {:.1} s", delay.as_secs_f64()),
        );
        Some(Action::RetryAt(at))
    }

    /// Deterministic jitter in [0, max) (xorshift; seeded for tests).
    fn jitter(&mut self, max: Duration) -> Duration {
        let mut x = self.jitter_seed.max(1);
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.jitter_seed = x;
        let ms = max.as_millis() as u64;
        if ms == 0 {
            Duration::ZERO
        } else {
            Duration::from_millis(x % ms)
        }
    }

    fn go(&mut self, to: MachineState, now: Duration, why: &str) {
        if to != self.state {
            self.changes.push(Change {
                from: self.state,
                to,
                why: why.to_string(),
            });
            self.state = to;
            self.since = now;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use MachineState as S;

    fn secs(v: u64) -> Duration {
        Duration::from_secs(v)
    }

    fn machine() -> LinkMachine {
        LinkMachine::new(LinkPolicy::default(), 42)
    }

    fn polling() -> LinkMachine {
        let mut m = machine();
        assert_eq!(
            m.handle(
                Event::Start {
                    transmit_enabled: true
                },
                secs(0)
            ),
            Some(Action::Connect)
        );
        assert_eq!(
            m.handle(Event::Connected, secs(1)),
            Some(Action::InitAdapter)
        );
        assert_eq!(m.handle(Event::InitOk, secs(2)), None);
        assert_eq!(m.state(), S::Polling);
        m
    }

    #[test]
    fn passive_by_default_when_transmit_disabled() {
        let mut m = machine();
        assert_eq!(
            m.handle(
                Event::Start {
                    transmit_enabled: false
                },
                secs(0)
            ),
            None
        );
        assert_eq!(m.state(), S::PassiveOnly);
        assert!(!m.state().may_poll());
        // Health or recovery events can't move it into transmitting states.
        assert_eq!(m.handle(Event::Connected, secs(1)), None);
        assert_eq!(m.state(), S::PassiveOnly);
    }

    #[test]
    fn happy_path_allows_polling() {
        assert!(polling().state().may_poll());
    }

    #[test]
    fn degraded_and_back() {
        let mut m = polling();
        let h = |failing| Event::Health {
            active: 10,
            failing,
            all_silent_for: Duration::ZERO,
        };
        m.handle(h(6), secs(3));
        assert_eq!(m.state(), S::Degraded);
        assert!(m.state().may_poll());
        m.handle(h(1), secs(4));
        assert_eq!(m.state(), S::Polling);
    }

    #[test]
    fn silence_escalates_soft_reset_reconnect_then_backs_off() {
        let mut m = polling();
        let dead = Event::Health {
            active: 5,
            failing: 5,
            all_silent_for: secs(6),
        };
        assert_eq!(
            m.handle(dead, secs(10)),
            Some(Action::Recover(RecoveryStep::Soft))
        );
        assert!(!m.state().may_poll(), "no polling while recovering");
        assert_eq!(
            m.handle(Event::RecoveryFailed, secs(11)),
            Some(Action::Recover(RecoveryStep::Reset))
        );
        assert_eq!(
            m.handle(Event::RecoveryFailed, secs(12)),
            Some(Action::Recover(RecoveryStep::Reconnect))
        );
        let Some(Action::RetryAt(at)) = m.handle(Event::RecoveryFailed, secs(13)) else {
            panic!("expected backoff");
        };
        assert_eq!(m.state(), S::Backoff);
        assert!(
            at >= secs(15) && at < secs(16),
            "2 s + up to 25 % jitter, got {at:?}"
        );
        assert_eq!(m.tick(at - Duration::from_millis(1)), None);
        assert_eq!(m.tick(at), Some(Action::Connect));
        assert_eq!(m.state(), S::Connecting);
    }

    #[test]
    fn a_working_recovery_step_returns_to_polling() {
        let mut m = polling();
        m.handle(
            Event::Health {
                active: 5,
                failing: 5,
                all_silent_for: secs(9),
            },
            secs(10),
        );
        assert_eq!(m.handle(Event::RecoveryOk, secs(11)), None);
        assert_eq!(m.state(), S::Polling);
        assert_eq!(m.attempts(), 0);
    }

    #[test]
    fn backoff_doubles_is_capped_and_ends_in_fault() {
        let policy = LinkPolicy {
            fault_after: 8,
            ..LinkPolicy::default()
        };
        let mut m = LinkMachine::new(policy.clone(), 7);
        m.handle(
            Event::Start {
                transmit_enabled: true,
            },
            secs(0),
        );
        let mut now = secs(0);
        let mut delays = vec![];
        loop {
            match m.handle(Event::ConnectFailed, now) {
                Some(Action::RetryAt(at)) => {
                    delays.push(at - now);
                    now = at;
                    assert_eq!(m.tick(now), Some(Action::Connect));
                }
                None => break,
                other => panic!("unexpected {other:?}"),
            }
        }
        assert_eq!(m.state(), S::Fault);
        assert_eq!(delays.len() as u32, policy.fault_after - 1);
        for w in delays.windows(2) {
            assert!(
                w[1] >= w[0] || w[1] >= policy.backoff_max,
                "non-decreasing until the cap"
            );
        }
        assert!(
            delays
                .iter()
                .all(|d| *d <= policy.backoff_max + policy.backoff_max / 4)
        );
        // FAULT is sticky until an operator retries.
        assert_eq!(m.tick(now + secs(3600)), None);
        assert_eq!(m.handle(Event::OperatorRetry, now), Some(Action::Connect));
    }

    #[test]
    fn disconnect_while_polling_backs_off() {
        let mut m = polling();
        assert!(matches!(
            m.handle(Event::Disconnected, secs(5)),
            Some(Action::RetryAt(_))
        ));
        assert_eq!(m.state(), S::Backoff);
    }

    #[test]
    fn changes_are_reported_once() {
        let mut m = polling();
        let c = m.take_changes();
        assert_eq!(
            c.iter().map(|c| c.to).collect::<Vec<_>>(),
            vec![S::Connecting, S::Initializing, S::Polling]
        );
        assert!(m.take_changes().is_empty());
    }
}
