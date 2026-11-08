//! Chooses the next request. One request is in flight per transport at a
//! time, so the transport's real throughput is the budget. This is about
//! 10 requests/s for the MX+ on `7DF` with two responders (measured on the
//! truck); SocketCAN is to be measured.
//!
//! Rules, in order:
//! 0. Follow-ups from a group (below) go first.
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
//!
//! **Groups** are the inputs of one computed signal ([`Scheduler::group`]).
//! When a member is picked, the other members are picked right after it,
//! ahead of everything else, so the inputs are read one round trip apart
//! instead of wherever the stretch puts them. A member follows only if it is
//! due, or if it is polled at least as often as the one picked and half its
//! interval has passed, so following never makes a slow PID (baro) fast; and
//! probes never follow. See ADR-0018.

use std::collections::VecDeque;
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
    /// Signals read back to back (the inputs of one computed signal each).
    groups: Vec<Vec<String>>,
    /// Members still to read after the one just picked.
    follow: VecDeque<String>,
}

impl Scheduler {
    pub fn new(budget_rps: f64, policy: PollPolicy) -> Self {
        Scheduler {
            entries: Vec::new(),
            policy,
            budget_rps,
            probe_budget_rps: 0.5,
            last_probe_at: None,
            groups: Vec::new(),
            follow: VecDeque::new(),
        }
    }

    /// Reads these signals back to back (see the module docs). Ids that were
    /// never [`add`](Self::add)ed are ignored; a group of fewer than two does
    /// nothing.
    pub fn group(&mut self, ids: &[String]) {
        let ids: Vec<String> = ids
            .iter()
            .filter(|id| self.entry(id).is_some())
            .cloned()
            .collect();
        if ids.len() >= 2 {
            self.groups.push(ids);
        }
    }

    /// A group member picked by [`next`](Self::next) is still waiting for
    /// the others: the next pick is one of them. The caller publishes nothing
    /// in between, so no snapshot pairs a fresh input with a stale one.
    pub fn follow_up_pending(&self) -> bool {
        self.follow
            .iter()
            .any(|id| self.entry(id).is_some_and(Self::may_follow))
    }

    fn may_follow(e: &Entry) -> bool {
        e.poll.state() != PollState::Off && !e.poll.is_probe()
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
        while let Some(id) = self.follow.pop_front() {
            if self.entry(&id).is_some_and(Self::may_follow) {
                return Some(id);
            }
        }
        let pick = self.pick(now)?;
        self.queue_followers(&pick, now);
        Some(pick)
    }

    /// The other members of `leader`'s groups that should be read right
    /// after it.
    fn queue_followers(&mut self, leader: &str, now: Duration) {
        let Some(lead_interval) = self.entry(leader).map(|e| e.poll.interval()) else {
            return;
        };
        let mut follow: Vec<String> = Vec::new();
        for id in self
            .groups
            .iter()
            .filter(|g| g.iter().any(|m| m == leader))
            .flatten()
        {
            if id == leader || follow.contains(id) {
                continue;
            }
            let Some(e) = self.entry(id) else { continue };
            let interval = e.poll.interval();
            let half_way = now + interval / 2 >= e.poll.next_due();
            if Self::may_follow(e)
                && (e.poll.is_due(now) || (interval <= lead_interval && half_way))
            {
                follow.push(id.clone());
            }
        }
        self.follow.extend(follow);
    }

    fn pick(&mut self, now: Duration) -> Option<String> {
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

    /// Runs `s` against a transport that answers everything after `rtt`, for
    /// `secs`, and returns (time, id) for each read.
    fn drive(s: &mut Scheduler, rtt: Duration, secs: u64) -> Vec<(Duration, String)> {
        let mut now = ms(0);
        let mut reads = Vec::new();
        while now < Duration::from_secs(secs) {
            match s.next(now) {
                Some(id) => {
                    now += rtt;
                    s.record_success(&id, now);
                    reads.push((now, id));
                }
                None => now = s.next_due().unwrap_or(now + ms(10)).max(now + ms(1)),
            }
        }
        reads
    }

    /// The 2026-11-08 shape [SIM]: priority 0 alone asks for more than the
    /// link delivers, so EOT and ECT live on the starvation guard.
    fn oversubscribed() -> Scheduler {
        let mut s = Scheduler::new(15.0, PollPolicy::default());
        for (id, prio, every) in [
            ("rpm", 0, 100),
            ("map", 0, 100),
            ("icp", 1, 100),
            ("speed", 1, 200),
            ("ipr_duty", 2, 150),
            ("eot", 3, 500),
            ("ect", 3, 500),
            ("trans_temp", 3, 500),
            ("ficm_main", 3, 400),
            ("load", 4, 500),
            ("battery", 4, 1000),
        ] {
            s.add(id, prio, ms(every), true, ms(0));
        }
        s
    }

    /// Largest gap between the latest `a` and `b` reads, after both were read.
    fn worst_skew(reads: &[(Duration, String)], a: &str, b: &str) -> Duration {
        let (mut ta, mut tb) = (None, None);
        let mut worst = Duration::ZERO;
        for (t, id) in reads {
            if id == a {
                ta = Some(*t);
            } else if id == b {
                tb = Some(*t);
            } else {
                continue;
            }
            if let (Some(x), Some(y)) = (ta, tb) {
                worst = worst.max(x.max(y) - x.min(y));
            }
        }
        worst
    }

    #[test]
    fn ungrouped_inputs_drift_apart_under_stretch() {
        // Today's behaviour without a group, kept as the baseline.
        let mut s = oversubscribed();
        let reads = drive(&mut s, ms(65), 120);
        assert!(worst_skew(&reads, "eot", "ect") > ms(2000));
    }

    fn count(reads: &[(Duration, String)], id: &str) -> usize {
        reads.iter().filter(|(_, r)| r == id).count()
    }

    /// Every `a` read sits right next to a `b` read.
    fn always_next_to(reads: &[(Duration, String)], a: &str, b: &str) -> bool {
        let is = |i: Option<usize>| i.and_then(|i| reads.get(i)).is_some_and(|(_, r)| r == b);
        (0..reads.len())
            .filter(|&i| reads[i].1 == a)
            .all(|i| is(i.checked_sub(1)) || is(Some(i + 1)))
    }

    #[test]
    fn grouped_inputs_are_read_back_to_back_under_stretch() {
        let baseline = drive(&mut oversubscribed(), ms(65), 120);
        let mut s = oversubscribed();
        s.group(&["eot".into(), "ect".into()]);
        let reads = drive(&mut s, ms(65), 120);
        assert!(always_next_to(&reads, "eot", "ect"));
        assert!(always_next_to(&reads, "ect", "eot"));
        // Grouping reorders; it doesn't add requests.
        let (before, after) = (count(&baseline, "eot"), count(&reads, "eot"));
        assert!(after <= before + 1, "EOT read {after} times, was {before}");
        assert!(count(&reads, "ect") <= count(&baseline, "ect") + 1);
    }

    #[test]
    fn a_slower_member_is_not_pulled_early() {
        let mut s = Scheduler::new(15.0, PollPolicy::default());
        s.add("map", 0, ms(100), true, ms(0));
        s.add("baro", 5, ms(5000), true, ms(0));
        s.group(&["map".into(), "baro".into()]);
        let reads = drive(&mut s, ms(65), 60);
        // Every 5 s, not every time MAP is read.
        assert!(count(&reads, "baro") <= 60 / 5 + 1, "{reads:?}");
        // The faster member does follow the slower one.
        assert!(always_next_to(&reads, "baro", "map"));
    }

    #[test]
    fn follow_ups_go_before_everything_and_then_end() {
        let mut s = sched();
        s.add("rpm", 0, ms(100), true, ms(0));
        s.add("eot", 3, ms(500), true, ms(0));
        s.add("ect", 3, ms(500), true, ms(0));
        s.group(&["eot".into(), "ect".into()]);
        assert_eq!(s.next(ms(0)).as_deref(), Some("rpm"));
        assert!(!s.follow_up_pending());
        s.record_success("rpm", ms(0)); // rpm due again at 100 ms
        assert_eq!(s.next(ms(0)).as_deref(), Some("eot"));
        assert!(s.follow_up_pending());
        s.record_success("eot", ms(150));
        // rpm is due and priority 0, but ECT finishes the pair first.
        assert_eq!(s.next(ms(150)).as_deref(), Some("ect"));
        assert!(!s.follow_up_pending());
        s.record_success("ect", ms(200));
        assert_eq!(s.next(ms(200)).as_deref(), Some("rpm"));
    }

    #[test]
    fn probes_and_disabled_members_do_not_follow() {
        let mut s = sched();
        s.add("eot", 3, ms(500), true, ms(0));
        s.add("ect", 3, ms(500), true, ms(0));
        s.add("trans_temp", 3, ms(500), false, ms(0));
        s.group(&["eot".into(), "ect".into(), "trans_temp".into()]);
        s.record_miss("ect", Miss::Unsupported, ms(0)); // quarantined
        assert_eq!(s.state_of("ect"), Some(PollState::Quarantined));
        assert_eq!(s.next(ms(0)).as_deref(), Some("eot"));
        assert!(!s.follow_up_pending());
        s.record_success("eot", ms(50));
        assert_eq!(s.next(ms(50)), None);
        // A member disabled after it was queued is dropped, not read.
        let mut s = sched();
        s.add("eot", 3, ms(500), true, ms(0));
        s.add("ect", 3, ms(500), true, ms(0));
        s.group(&["eot".into(), "ect".into()]);
        assert_eq!(s.next(ms(0)).as_deref(), Some("eot"));
        s.set_enabled("ect", false, ms(10));
        assert!(!s.follow_up_pending());
        s.record_success("eot", ms(50));
        assert_eq!(s.next(ms(50)), None);
    }

    #[test]
    fn groups_ignore_unknown_ids() {
        let mut s = sched();
        s.add("eot", 3, ms(500), true, ms(0));
        s.group(&["eot".into(), "nope".into()]);
        assert_eq!(s.next(ms(0)).as_deref(), Some("eot"));
        assert!(!s.follow_up_pending());
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
