//! Per-PID polling health. A PID that stops answering is backed off and
//! eventually quarantined, so a dead PID costs almost no bus time, and it is
//! probed at a low rate so it recovers on its own. The sample itself ages into
//! STALE independently (that is the telemetry model's job, not this one's).

use std::time::Duration;

/// Where a PID stands. Mirrors `Sample.poll_state` in the API.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PollState {
    Active,
    /// Recent misses, still polled at its normal interval.
    Suspect,
    /// Repeated misses: polled at an exponentially growing interval.
    Backoff,
    /// Gave up on regular polling; probed every `quarantine_probe`.
    Quarantined,
    /// Disabled by configuration or an operator.
    Off,
}

impl PollState {
    pub fn as_str(self) -> &'static str {
        match self {
            PollState::Active => "ACTIVE",
            PollState::Suspect => "SUSPECT",
            PollState::Backoff => "BACKOFF",
            PollState::Quarantined => "QUARANTINED",
            PollState::Off => "OFF",
        }
    }
}

/// Why a request did not produce a usable value.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Miss {
    /// Timeout or `NO DATA`.
    NoResponse,
    /// Answer that could not be decoded.
    Invalid,
    /// Negative response saying the module does not support the request
    /// (e.g. NRC 0x31 requestOutOfRange, 0x11/0x12 not supported).
    Unsupported,
    /// Any other negative response (busy, conditions not correct, ...).
    Refused,
}

/// Negative response codes that mean "this module will never answer this".
pub fn nrc_means_unsupported(nrc: u8) -> bool {
    matches!(nrc, 0x11 | 0x12 | 0x31)
}

#[derive(Debug, Clone, PartialEq)]
pub struct PollPolicy {
    /// Consecutive misses before ACTIVE → SUSPECT is reported.
    pub suspect_after: u32,
    /// Consecutive misses before backing off.
    pub backoff_after: u32,
    /// Backoff rounds (failed probes while in BACKOFF) before quarantine.
    pub quarantine_after: u32,
    pub backoff_max: Duration,
    pub quarantine_probe: Duration,
}

impl Default for PollPolicy {
    fn default() -> Self {
        PollPolicy {
            suspect_after: 1,
            backoff_after: 3,
            quarantine_after: 5,
            backoff_max: Duration::from_secs(30),
            quarantine_probe: Duration::from_secs(60),
        }
    }
}

/// A state change worth logging.
#[derive(Debug, Clone, PartialEq)]
pub struct Transition {
    pub from: PollState,
    pub to: PollState,
    pub reason: String,
}

#[derive(Debug, Clone)]
pub struct PidPoll {
    state: PollState,
    interval: Duration,
    next_due: Duration,
    consecutive_misses: u32,
    backoff_rounds: u32,
    backoff: Duration,
}

impl PidPoll {
    pub fn new(interval: Duration, enabled: bool, now: Duration) -> Self {
        PidPoll {
            state: if enabled {
                PollState::Active
            } else {
                PollState::Off
            },
            interval,
            next_due: now,
            consecutive_misses: 0,
            backoff_rounds: 0,
            backoff: interval,
        }
    }

    pub fn state(&self) -> PollState {
        self.state
    }

    pub fn interval(&self) -> Duration {
        self.interval
    }

    pub fn next_due(&self) -> Duration {
        self.next_due
    }

    pub fn consecutive_misses(&self) -> u32 {
        self.consecutive_misses
    }

    pub fn is_due(&self, now: Duration) -> bool {
        self.state != PollState::Off && now >= self.next_due
    }

    /// Quarantined and backed-off PIDs are probes: they come out of a small
    /// separate budget so they never crowd out healthy PIDs.
    pub fn is_probe(&self) -> bool {
        matches!(self.state, PollState::Backoff | PollState::Quarantined)
    }

    /// Enables or disables polling. Re-enabling starts fresh.
    pub fn set_enabled(&mut self, enabled: bool, now: Duration) -> Option<Transition> {
        let from = self.state;
        if enabled {
            if from != PollState::Off {
                return None;
            }
            *self = PidPoll::new(self.interval, true, now);
        } else {
            self.state = PollState::Off;
        }
        (from != self.state).then(|| Transition {
            from,
            to: self.state,
            reason: if enabled { "enabled" } else { "disabled" }.into(),
        })
    }

    pub fn on_success(&mut self, now: Duration) -> Option<Transition> {
        let from = self.state;
        self.consecutive_misses = 0;
        self.backoff_rounds = 0;
        self.backoff = self.interval;
        self.next_due = now + self.interval;
        if from == PollState::Off {
            return None;
        }
        self.state = PollState::Active;
        (from != PollState::Active).then(|| Transition {
            from,
            to: PollState::Active,
            reason: "answered".into(),
        })
    }

    pub fn on_miss(
        &mut self,
        miss: Miss,
        now: Duration,
        policy: &PollPolicy,
    ) -> Option<Transition> {
        let from = self.state;
        if from == PollState::Off {
            return None;
        }
        self.consecutive_misses = self.consecutive_misses.saturating_add(1);
        let reason = format!("{miss:?} ×{}", self.consecutive_misses);

        let to = if miss == Miss::Unsupported {
            // The module said it will never answer: no point backing off.
            PollState::Quarantined
        } else {
            match from {
                PollState::Active | PollState::Suspect => {
                    if self.consecutive_misses >= policy.backoff_after {
                        PollState::Backoff
                    } else if self.consecutive_misses >= policy.suspect_after {
                        PollState::Suspect
                    } else {
                        from
                    }
                }
                PollState::Backoff => {
                    self.backoff_rounds += 1;
                    if self.backoff_rounds >= policy.quarantine_after {
                        PollState::Quarantined
                    } else {
                        PollState::Backoff
                    }
                }
                PollState::Quarantined => PollState::Quarantined,
                PollState::Off => PollState::Off,
            }
        };

        self.next_due = now
            + match to {
                PollState::Active | PollState::Suspect | PollState::Off => self.interval,
                PollState::Backoff => {
                    // Doubles each round, capped.
                    self.backoff = (self.backoff * 2).min(policy.backoff_max);
                    self.backoff
                }
                PollState::Quarantined => policy.quarantine_probe,
            };
        self.state = to;
        (from != to).then_some(Transition { from, to, reason })
    }

    /// Pushes the next request later (the scheduler stretches low priorities
    /// when the transport can't keep up).
    pub fn defer_until(&mut self, at: Duration) {
        self.next_due = self.next_due.max(at);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const S: Duration = Duration::from_secs(1);
    fn ms(v: u64) -> Duration {
        Duration::from_millis(v)
    }

    fn pid() -> PidPoll {
        PidPoll::new(S, true, Duration::ZERO)
    }

    #[test]
    fn healthy_pid_stays_active_and_reschedules_by_interval() {
        let mut p = pid();
        assert!(p.is_due(Duration::ZERO));
        assert_eq!(p.on_success(ms(100)), None);
        assert_eq!(p.state(), PollState::Active);
        assert_eq!(p.next_due(), ms(1100));
        assert!(!p.is_due(ms(1099)));
        assert!(p.is_due(ms(1100)));
    }

    #[test]
    fn misses_go_suspect_then_backoff_then_quarantine() {
        let policy = PollPolicy::default();
        let mut p = pid();
        let t = p.on_miss(Miss::NoResponse, S, &policy).expect("transition");
        assert_eq!((t.from, t.to), (PollState::Active, PollState::Suspect));
        assert_eq!(p.on_miss(Miss::NoResponse, 2 * S, &policy), None);
        let t = p
            .on_miss(Miss::NoResponse, 3 * S, &policy)
            .expect("transition");
        assert_eq!(t.to, PollState::Backoff);
        assert!(p.is_probe());
        // Backoff doubles: 2 s, 4 s, 8 s, ... capped at 30 s.
        assert_eq!(p.next_due(), 3 * S + 2 * S);
        for _ in 0..(policy.quarantine_after - 1) {
            assert_eq!(p.on_miss(Miss::NoResponse, p.next_due(), &policy), None);
        }
        let t = p
            .on_miss(Miss::NoResponse, p.next_due(), &policy)
            .expect("transition");
        assert_eq!(t.to, PollState::Quarantined);
        let at = Duration::from_secs(1000);
        p.on_miss(Miss::NoResponse, at, &policy);
        assert_eq!(p.next_due(), at + policy.quarantine_probe);
    }

    #[test]
    fn backoff_is_capped() {
        let policy = PollPolicy {
            quarantine_after: 100,
            ..PollPolicy::default()
        };
        let mut p = pid();
        let mut now = Duration::ZERO;
        for _ in 0..20 {
            p.on_miss(Miss::NoResponse, now, &policy);
            assert!(p.next_due() - now <= policy.backoff_max);
            now = p.next_due();
        }
        p.on_miss(Miss::NoResponse, now, &policy);
        assert_eq!(p.next_due() - now, policy.backoff_max, "settles at the cap");
    }

    #[test]
    fn unsupported_quarantines_immediately() {
        let mut p = pid();
        let t = p
            .on_miss(Miss::Unsupported, S, &PollPolicy::default())
            .expect("transition");
        assert_eq!(t.to, PollState::Quarantined);
    }

    #[test]
    fn a_success_from_any_state_restores_active() {
        let policy = PollPolicy::default();
        for misses in [1, 3, 10] {
            let mut p = pid();
            for i in 0..misses {
                p.on_miss(Miss::NoResponse, S * i, &policy);
            }
            let t = p.on_success(S * 100).expect("transition");
            assert_eq!(t.to, PollState::Active);
            assert_eq!(p.consecutive_misses(), 0);
            assert_eq!(p.next_due(), S * 101, "back to the normal interval");
        }
    }

    #[test]
    fn disabled_pids_are_never_due_and_ignore_results() {
        let mut p = PidPoll::new(S, false, Duration::ZERO);
        assert!(!p.is_due(S * 100));
        assert_eq!(p.on_success(S), None);
        assert_eq!(p.on_miss(Miss::NoResponse, S, &PollPolicy::default()), None);
        assert_eq!(p.state(), PollState::Off);
        let t = p.set_enabled(true, S).expect("transition");
        assert_eq!(t.to, PollState::Active);
        assert!(p.is_due(S));
    }

    #[test]
    fn unsupported_nrcs() {
        assert!(nrc_means_unsupported(0x31));
        assert!(nrc_means_unsupported(0x11));
        assert!(!nrc_means_unsupported(0x22)); // conditions not correct: transient
        assert!(!nrc_means_unsupported(0x78)); // response pending
    }
}
