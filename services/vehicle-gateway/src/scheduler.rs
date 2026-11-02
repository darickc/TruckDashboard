//! Chooses the next request. One request is in flight per transport at a
//! time, so the transport's real throughput is the budget. This is about
//! 10 requests/s for the MX+ on `7DF` with two responders (measured on the
//! truck); SocketCAN is to be measured.
//!
//! Rules, in order:
//! 1. Only due PIDs are candidates.
//! 2. A PID overdue by more than [`STARVATION_INTERVALS`] intervals goes first,
//!    so low priorities stretch but never starve.
//! 3. Then lowest priority number (0 = most important), then earliest due.
//! 4. Backed-off and quarantined PIDs are probes. At most one probe per
//!    `1 / probe_budget_rps` seconds, so dead PIDs never crowd out live ones.
//!
//! When demand exceeds the budget, low priorities are the ones that slip, and
//! [`Scheduler::load`] says so. A gauge that promises 10 Hz and delivers 2 Hz
//! is a lie told to the driver.

use std::time::Duration;

use crate::poll::{Miss, PidPoll, PollPolicy, PollState, Transition};

pub const STARVATION_INTERVALS: u32 = 5;

#[derive(Debug, Clone)]
struct Entry {
    id: String,
    priority: u8,
    poll: PidPoll,
}

/// Requested vs. available throughput.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Load {
    pub demand_rps: f64,
    pub budget_rps: f64,
}

impl Load {
    /// Demand above 80 % of the budget: intervals will stretch.
    pub fn oversubscribed(&self) -> bool {
        self.demand_rps > 0.8 * self.budget_rps
    }
}

#[derive(Debug, Clone)]
pub struct Scheduler {
    entries: Vec<Entry>,
    policy: PollPolicy,
    budget_rps: f64,
    probe_budget_rps: f64,
    last_probe_at: Option<Duration>,
}

impl Scheduler {
    pub fn new(budget_rps: f64, policy: PollPolicy) -> Self {
        Scheduler {
            entries: Vec::new(),
            policy,
            budget_rps,
            probe_budget_rps: 0.5,
            last_probe_at: None,
        }
    }

    pub fn with_probe_budget(mut self, rps: f64) -> Self {
        self.probe_budget_rps = rps;
        self
    }

    /// Adds a signal. Re-adding an id replaces it.
    pub fn add(
        &mut self,
        id: &str,
        priority: u8,
        interval: Duration,
        enabled: bool,
        now: Duration,
    ) {
        self.entries.retain(|e| e.id != id);
        self.entries.push(Entry {
            id: id.to_string(),
            priority,
            poll: PidPoll::new(interval, enabled, now),
        });
    }

    pub fn ids(&self) -> impl Iterator<Item = &str> {
        self.entries.iter().map(|e| e.id.as_str())
    }

    pub fn state_of(&self, id: &str) -> Option<PollState> {
        self.entry(id).map(|e| e.poll.state())
    }

    pub fn interval_of(&self, id: &str) -> Option<Duration> {
        self.entry(id).map(|e| e.poll.interval())
    }

    pub fn set_enabled(&mut self, id: &str, enabled: bool, now: Duration) -> Option<Transition> {
        self.entry_mut(id)?.poll.set_enabled(enabled, now)
    }

    /// The next signal to request, if any is due.
    pub fn next(&mut self, now: Duration) -> Option<String> {
        let probe_ok = match self.last_probe_at {
            None => true,
            Some(t) => {
                self.probe_budget_rps > 0.0
                    && (now - t).as_secs_f64() >= 1.0 / self.probe_budget_rps
            }
        };
        let pick = self
            .entries
            .iter()
            .filter(|e| e.poll.is_due(now) && (probe_ok || !e.poll.is_probe()))
            .min_by_key(|e| {
                let overdue = now.saturating_sub(e.poll.next_due());
                let starved = overdue > e.poll.interval() * STARVATION_INTERVALS;
                (!starved, e.poll.is_probe(), e.priority, e.poll.next_due())
            })?;
        if pick.poll.is_probe() {
            self.last_probe_at = Some(now);
        }
        Some(pick.id.clone())
    }

    /// Earliest time anything becomes due (for sleeping between requests).
    pub fn next_due(&self) -> Option<Duration> {
        self.entries
            .iter()
            .filter(|e| e.poll.state() != PollState::Off)
            .map(|e| e.poll.next_due())
            .min()
    }

    pub fn record_success(&mut self, id: &str, now: Duration) -> Option<Transition> {
        self.entry_mut(id)?.poll.on_success(now)
    }

    pub fn record_miss(&mut self, id: &str, miss: Miss, now: Duration) -> Option<Transition> {
        let policy = self.policy.clone();
        self.entry_mut(id)?.poll.on_miss(miss, now, &policy)
    }

    /// Requests per second the healthy (non-probe) signals ask for.
    pub fn load(&self) -> Load {
        let demand_rps = self
            .entries
            .iter()
            .filter(|e| matches!(e.poll.state(), PollState::Active | PollState::Suspect))
            .map(|e| 1.0 / e.poll.interval().as_secs_f64())
            .sum();
        Load {
            demand_rps,
            budget_rps: self.budget_rps,
        }
    }

    fn entry(&self, id: &str) -> Option<&Entry> {
        self.entries.iter().find(|e| e.id == id)
    }

    fn entry_mut(&mut self, id: &str) -> Option<&mut Entry> {
        self.entries.iter_mut().find(|e| e.id == id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ms(v: u64) -> Duration {
        Duration::from_millis(v)
    }

    fn sched() -> Scheduler {
        Scheduler::new(10.0, PollPolicy::default())
    }

    #[test]
    fn nothing_due_nothing_picked() {
        let mut s = sched();
        s.add("rpm", 0, ms(250), true, ms(0));
        assert_eq!(s.next(ms(0)).as_deref(), Some("rpm"));
        s.record_success("rpm", ms(10));
        assert_eq!(s.next(ms(100)), None);
        assert_eq!(s.next_due(), Some(ms(260)));
    }

    #[test]
    fn lower_priority_number_wins_then_earliest_due() {
        let mut s = sched();
        s.add("baro", 5, ms(5000), true, ms(0));
        s.add("eot", 1, ms(1000), true, ms(0));
        s.add("rpm", 0, ms(250), true, ms(0));
        assert_eq!(s.next(ms(0)).as_deref(), Some("rpm"));
        s.record_success("rpm", ms(0));
        assert_eq!(s.next(ms(0)).as_deref(), Some("eot"));
        s.record_success("eot", ms(0));
        assert_eq!(s.next(ms(0)).as_deref(), Some("baro"));
    }

    #[test]
    fn low_priority_is_not_starved_forever() {
        let mut s = sched();
        s.add("rpm", 0, ms(100), true, ms(0));
        s.add("baro", 5, ms(1000), true, ms(0));
        // Simulate a transport so slow that rpm is always due.
        let mut picked_baro_at = None;
        for t in (0..20_000).step_by(150) {
            let now = ms(t);
            match s.next(now).as_deref() {
                Some("baro") => {
                    picked_baro_at = Some(now);
                    break;
                }
                Some(id) => {
                    let id = id.to_string();
                    s.record_success(&id, now - ms(100).min(now)); // keeps rpm due
                }
                None => {}
            }
        }
        let at = picked_baro_at.expect("baro eventually polled");
        assert!(
            at <= ms(1000) * (STARVATION_INTERVALS + 1),
            "picked at {at:?}"
        );
    }

    #[test]
    fn probes_are_rate_limited_and_never_beat_healthy_pids() {
        let mut s = sched().with_probe_budget(0.5); // one probe per 2 s
        s.add("rpm", 0, ms(250), true, ms(0));
        s.add("dead", 1, ms(250), true, ms(0));
        s.record_miss("dead", Miss::Unsupported, ms(0)); // quarantined: probe every 60 s
        assert_eq!(s.state_of("dead"), Some(PollState::Quarantined));
        // Before its probe time it is never picked.
        assert_eq!(s.next(ms(1000)).as_deref(), Some("rpm"));
        s.record_success("rpm", ms(1000));
        assert_eq!(s.next(ms(1100)), None);
        // At probe time it competes, but a due healthy PID goes first.
        let probe_time = ms(60_000);
        assert_eq!(s.next(probe_time).as_deref(), Some("rpm"));
        s.record_success("rpm", probe_time);
        assert_eq!(s.next(probe_time).as_deref(), Some("dead"));
        s.record_miss("dead", Miss::NoResponse, probe_time);
        // The probe budget now blocks another probe for 2 s even if due.
        s.add("dead2", 1, ms(250), true, probe_time);
        s.record_miss("dead2", Miss::Unsupported, ms(0));
        let t = probe_time + ms(1000);
        assert_eq!(
            s.next(t).as_deref(),
            Some("rpm"),
            "dead2 is due but over the probe budget"
        );
        s.record_success("rpm", t);
        assert_eq!(s.next(t), None);
        assert_eq!(s.next(probe_time + ms(2000)).as_deref(), Some("dead2"));
    }

    #[test]
    fn load_counts_only_healthy_signals() {
        let mut s = sched();
        s.add("rpm", 0, ms(250), true, ms(0)); // 4 rps
        s.add("eot", 1, ms(1000), true, ms(0)); // 1 rps
        s.add("off", 1, ms(100), false, ms(0)); // disabled
        let l = s.load();
        assert!((l.demand_rps - 5.0).abs() < 1e-9);
        assert!(!l.oversubscribed());
        s.add("map", 0, ms(250), true, ms(0));
        s.add("icp", 0, ms(250), true, ms(0));
        assert!(s.load().oversubscribed(), "13 rps asked of a 10 rps link");
        s.record_miss("icp", Miss::Unsupported, ms(0));
        assert!(
            (s.load().demand_rps - 9.0).abs() < 1e-9,
            "quarantined PIDs don't count"
        );
    }

    #[test]
    fn enable_disable_at_runtime() {
        let mut s = sched();
        s.add("eot", 1, ms(1000), false, ms(0));
        assert_eq!(s.next(ms(0)), None);
        s.set_enabled("eot", true, ms(5));
        assert_eq!(s.next(ms(5)).as_deref(), Some("eot"));
        s.set_enabled("eot", false, ms(6));
        assert_eq!(s.next(ms(100_000)), None);
        assert!(s.set_enabled("nope", true, ms(0)).is_none());
    }
}
