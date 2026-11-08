//! Chooses the next request. One request is in flight per transport at a
//! time, so the transport's real throughput is the budget. This is about
//! 10 requests/s for the MX+ on `7DF` with two responders and about 16/s for
//! the USB CAN adapter (both measured on the truck). The registry's intervals
//! are budgeted so the default enabled set asks for under 80 % of it
//! (ADR-0019).
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
//!
//! **Spare budget** (ADR-0020). The registry's intervals are sized for the
//! largest default set on the slowest link, so a smaller set leaves the link
//! idle. That room goes to priority 0 (RPM, MAP): while nothing else is due,
//! a healthy (`Active`) priority-0 signal may be read early, once its *spare
//! interval* has passed since its last request. The spare intervals are set
//! so that
//!
//! - the healthy signals' demand, plus the probe budget if anything is being
//!   probed, plus the extra early reads stay within 80 % of the budget (the
//!   same line as [`Load::oversubscribed`]); with nothing to spare there are
//!   no early reads;
//! - no signal is read more often than once per [`Scheduler::with_spare_floor`]
//!   (the core's snapshot period: a faster read would never be published).
//!
//! An early read only ever replaces idle time: it is never picked over a due
//! signal, a follow-up or an allowed probe, so it can delay one of those by
//! at most the round trip already in flight. It does not touch the registry
//! interval, so the signal's regular schedule, staleness and the group rules
//! are unchanged; it only makes the value fresher. Group members follow an
//! early read only if they are due themselves (regularly or early), so
//! following never adds requests outside the 80 %.

use std::collections::VecDeque;
use std::time::Duration;

use crate::poll::{Miss, PidPoll, PollPolicy, PollState, Transition};

pub const STARVATION_INTERVALS: u32 = 5;

/// Share of the budget the scheduler plans to use, spare reads included.
/// [`Load::oversubscribed`] is the same line.
pub const BUDGET_SHARE: f64 = 0.8;

/// The priority whose signals get the spare budget (ADR-0020).
pub const SPARE_PRIORITY: u8 = 0;

/// Default for [`Scheduler::with_spare_floor`]: the core's snapshot period.
pub const DEFAULT_SPARE_FLOOR: Duration = Duration::from_millis(250);

#[derive(Debug, Clone)]
struct Entry {
    id: String,
    priority: u8,
    poll: PidPoll,
    /// When this signal was last handed out by [`Scheduler::next`].
    last_request: Option<Duration>,
}

/// Requested vs. available throughput.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Load {
    /// What the healthy signals' registry intervals ask for.
    pub demand_rps: f64,
    pub budget_rps: f64,
    /// Early priority-0 reads planned on top of `demand_rps` from the spare
    /// budget (ADR-0020). Zero when oversubscribed. `demand_rps + spare_rps`
    /// (plus the probe budget, while anything is probed) never exceeds 80 %
    /// of `budget_rps`.
    pub spare_rps: f64,
}

impl Load {
    /// Demand above 80 % of the budget: intervals will stretch.
    pub fn oversubscribed(&self) -> bool {
        self.demand_rps > BUDGET_SHARE * self.budget_rps
    }

    /// Everything planned: registry demand plus spare reads.
    pub fn planned_rps(&self) -> f64 {
        self.demand_rps + self.spare_rps
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
    /// Shortest spare interval (ADR-0020).
    spare_floor: Duration,
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
            spare_floor: DEFAULT_SPARE_FLOOR,
        }
    }

    /// No spare read comes sooner than `floor` after the signal's last
    /// request. The core passes its snapshot period. `Duration::MAX` turns
    /// spare reads off.
    pub fn with_spare_floor(mut self, floor: Duration) -> Self {
        self.spare_floor = floor;
        self
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
            last_request: None,
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

    /// How often `id` is read while the link has room: shorter than
    /// [`interval_of`](Self::interval_of) for a healthy priority-0 signal
    /// when there is spare budget, `None` otherwise (ADR-0020).
    pub fn spare_interval_of(&self, id: &str) -> Option<Duration> {
        self.spare_plan()
            .into_iter()
            .find(|(i, _)| self.entries[*i].id == id)
            .map(|(_, d)| d)
    }

    pub fn set_enabled(&mut self, id: &str, enabled: bool, now: Duration) -> Option<Transition> {
        self.entry_mut(id)?.poll.set_enabled(enabled, now)
    }

    /// The next signal to request, if any is due.
    pub fn next(&mut self, now: Duration) -> Option<String> {
        while let Some(id) = self.follow.pop_front() {
            if self.entry(&id).is_some_and(Self::may_follow) {
                self.requested(&id, now);
                return Some(id);
            }
        }
        let spare = self.spare_plan();
        let (pick, early) = match self.pick(now) {
            Some(id) => (id, false),
            None => (self.pick_spare(&spare, now)?, true),
        };
        self.queue_followers(&pick, now, early.then_some(spare.as_slice()));
        self.requested(&pick, now);
        Some(pick)
    }

    fn requested(&mut self, id: &str, now: Duration) {
        if let Some(e) = self.entry_mut(id) {
            e.last_request = Some(now);
        }
    }

    /// Spare interval per healthy priority-0 entry, as (index, interval).
    ///
    /// The room is 80 % of the budget minus the healthy demand, minus the
    /// probe budget while anything is probed. It is shared equally
    /// (water-filling: a signal capped by the floor leaves its share to the
    /// others), and each signal's rate becomes its registry rate plus its
    /// share. Empty when there is no room.
    fn spare_plan(&self) -> Vec<(usize, Duration)> {
        let floor = self.spare_floor.as_secs_f64();
        if floor <= 0.0 || self.spare_floor == Duration::MAX {
            return Vec::new();
        }
        let load = self.registry_demand();
        let probing = self.entries.iter().any(|e| e.poll.is_probe());
        let mut room = BUDGET_SHARE * self.budget_rps
            - load
            - if probing { self.probe_budget_rps } else { 0.0 };
        if room <= 1e-9 {
            return Vec::new();
        }
        // (index, registry rate, most it may gain before the floor)
        let mut cands: Vec<(usize, f64, f64)> = self
            .entries
            .iter()
            .enumerate()
            .filter(|(_, e)| e.priority == SPARE_PRIORITY && e.poll.state() == PollState::Active)
            .map(|(i, e)| {
                let rate = 1.0 / e.poll.interval().as_secs_f64();
                (i, rate, 1.0 / floor - rate)
            })
            .filter(|(_, _, gap)| *gap > 1e-9)
            .collect();
        cands.sort_by(|a, b| a.2.total_cmp(&b.2));
        let n = cands.len();
        let mut plan = Vec::with_capacity(n);
        for (k, (i, rate, gap)) in cands.into_iter().enumerate() {
            let gain = (room / (n - k) as f64).min(gap);
            room -= gain;
            if gain > 1e-9 {
                // Round the interval up to whole microseconds so the plan
                // never asks for more than its share.
                let us = (1e6 / (rate + gain)).ceil() as u64;
                plan.push((i, Duration::from_micros(us)));
            }
        }
        plan
    }

    /// When `e` may next be read early under a spare interval `spare`.
    fn spare_due(e: &Entry, spare: Duration) -> Option<Duration> {
        e.last_request.map(|t| t + spare)
    }

    /// The healthy priority-0 signal whose spare read is due soonest.
    fn pick_spare(&self, plan: &[(usize, Duration)], now: Duration) -> Option<String> {
        plan.iter()
            .filter_map(|&(i, d)| {
                let e = &self.entries[i];
                Self::spare_due(e, d).filter(|t| *t <= now).map(|t| (t, e))
            })
            .min_by_key(|(t, _)| *t)
            .map(|(_, e)| e.id.clone())
    }

    /// The other members of `leader`'s groups that should be read right
    /// after it. After an early (spare) read, `spare` is the plan, and only
    /// members that are due, regularly or early, follow.
    fn queue_followers(
        &mut self,
        leader: &str,
        now: Duration,
        spare: Option<&[(usize, Duration)]>,
    ) {
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
            let ok = match spare {
                None => e.poll.is_due(now) || (interval <= lead_interval && half_way),
                Some(plan) => {
                    e.poll.is_due(now)
                        || plan.iter().any(|&(i, d)| {
                            self.entries[i].id == *id
                                && Self::spare_due(e, d).is_some_and(|t| t <= now)
                        })
                }
            };
            if Self::may_follow(e) && ok {
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

    /// Earliest time anything becomes due, early reads included (for
    /// sleeping between requests).
    pub fn next_due(&self) -> Option<Duration> {
        let regular = self
            .entries
            .iter()
            .filter(|e| e.poll.state() != PollState::Off)
            .map(|e| e.poll.next_due());
        let spare = self
            .spare_plan()
            .into_iter()
            .filter_map(|(i, d)| Self::spare_due(&self.entries[i], d));
        regular.chain(spare).min()
    }

    pub fn record_success(&mut self, id: &str, now: Duration) -> Option<Transition> {
        self.entry_mut(id)?.poll.on_success(now)
    }

    pub fn record_miss(&mut self, id: &str, miss: Miss, now: Duration) -> Option<Transition> {
        let policy = self.policy.clone();
        self.entry_mut(id)?.poll.on_miss(miss, now, &policy)
    }

    /// Requests per second the healthy (non-probe) signals ask for, and the
    /// spare reads planned on top.
    pub fn load(&self) -> Load {
        let spare_rps = self
            .spare_plan()
            .into_iter()
            .map(|(i, d)| {
                1.0 / d.as_secs_f64() - 1.0 / self.entries[i].poll.interval().as_secs_f64()
            })
            .sum();
        Load {
            demand_rps: self.registry_demand(),
            budget_rps: self.budget_rps,
            spare_rps,
        }
    }

    fn registry_demand(&self) -> f64 {
        self.entries
            .iter()
            .filter(|e| matches!(e.poll.state(), PollState::Active | PollState::Suspect))
            .map(|e| 1.0 / e.poll.interval().as_secs_f64())
            .sum()
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

    // ---- Spare budget (ADR-0020) ----

    /// The truck's set over the USB CAN adapter [SIM]: registry defaults plus
    /// `--enable eot` (ADR-0019's intervals), budget 16/s, groups as the core
    /// builds them (EOT − ECT; boost's MAP is disabled by default).
    fn truck_can() -> Scheduler {
        let mut s = Scheduler::new(16.0, PollPolicy::default());
        for (id, prio, every) in [
            ("rpm", 0, 500),
            ("speed", 1, 1000),
            ("load", 4, 1000),
            ("ect", 3, 1500),
            ("eot", 3, 1500),
            ("trans_temp", 3, 1500),
            ("iat", 5, 3000),
            ("baro", 5, 5000),
        ] {
            s.add(id, prio, ms(every), true, ms(0));
        }
        s.group(&["eot".into(), "ect".into()]);
        s
    }

    /// One request per 62.5 ms: the CAN adapter's measured 16/s.
    const CAN_RTT: Duration = Duration::from_micros(62_500);

    fn rate(reads: &[(Duration, String)], id: &str, secs: u64) -> f64 {
        count(reads, id) as f64 / secs as f64
    }

    #[test]
    fn spare_budget_speeds_up_rpm_on_the_truck_can_set() {
        let secs = 300;
        let baseline = drive(
            &mut truck_can().with_spare_floor(Duration::MAX),
            CAN_RTT,
            secs,
        );
        let mut s = truck_can();
        let l = s.load();
        assert!((l.demand_rps - 6.5333).abs() < 1e-3, "{l:?}");
        assert!(l.planned_rps() <= 0.8 * 16.0 + 1e-9, "{l:?}");
        // Capped by the 250 ms floor: 2/s registry + 2/s spare.
        assert_eq!(s.spare_interval_of("rpm"), Some(ms(250)));
        assert!((l.spare_rps - 2.0).abs() < 1e-6, "{l:?}");
        let reads = drive(&mut s, CAN_RTT, secs);

        // ADR-0019 predicted ~1.8 Hz without spare reads.
        let before = rate(&baseline, "rpm", secs);
        let after = rate(&reads, "rpm", secs);
        assert!((1.6..2.0).contains(&before), "baseline rpm {before:.2} Hz");
        // 3.45 Hz [SIM]: the 250 ms floor, minus waits behind other reads.
        assert!(after >= 3.0, "rpm {after:.2} Hz, baseline {before:.2}");
        // The link's real use stays within 80 %.
        let total = reads.len() as f64 / secs as f64;
        assert!(total <= 0.8 * 16.0, "{total:.2} req/s");
        // Every other signal still gets its interval (the yardstick of
        // tests/gateway_sim.rs: interval + 200 ms) and loses at most 2 % of
        // its reads to the early RPM reads (IAT, priority 5: 95 → 94).
        for (id, every) in [
            ("speed", 1000),
            ("load", 1000),
            ("ect", 1500),
            ("eot", 1500),
            ("trans_temp", 1500),
            ("iat", 3000),
            ("baro", 5000),
        ] {
            let (n, was) = (count(&reads, id) as f64, count(&baseline, id) as f64);
            let target = secs as f64 * 1000.0 / (every as f64 + 200.0);
            assert!(
                n >= target && n >= 0.98 * was,
                "{id}: {n} reads in {secs} s (baseline {was}), wanted {target:.0}"
            );
        }
        // EOT and ECT are still read back to back (ADR-0018).
        assert!(always_next_to(&reads, "eot", "ect"));
        assert!(always_next_to(&reads, "ect", "eot"));
        let skew = worst_skew(&reads, "eot", "ect");
        assert!(skew <= worst_skew(&baseline, "eot", "ect") + CAN_RTT);
        assert!(skew < ms(2000), "{skew:?} against max_input_skew_ms 2000");
    }

    #[test]
    fn spare_reads_never_go_before_a_due_signal() {
        let mut s = Scheduler::new(16.0, PollPolicy::default());
        s.add("rpm", 0, ms(500), true, ms(0));
        s.add("eot", 3, ms(1500), true, ms(0));
        assert_eq!(s.spare_interval_of("rpm"), Some(ms(250)));
        assert_eq!(s.next(ms(0)).as_deref(), Some("rpm"));
        s.record_success("rpm", ms(50));
        assert_eq!(s.next(ms(50)).as_deref(), Some("eot"));
        s.record_success("eot", ms(100));
        // Nothing due, spare read not yet due: sleep until it is.
        assert_eq!(s.next(ms(100)), None);
        assert_eq!(s.next_due(), Some(ms(250)));
        assert_eq!(s.next(ms(250)).as_deref(), Some("rpm"), "early read");
        s.record_success("rpm", ms(300)); // regular next due 800
        // EOT falls due at 1600 together with RPM's spare read: EOT first.
        assert_eq!(s.next(ms(500)).as_deref(), Some("rpm"));
        s.record_success("rpm", ms(550));
        assert_eq!(s.next(ms(750)).as_deref(), Some("rpm"));
        s.record_success("rpm", ms(1500));
        assert_eq!(s.next(ms(1600)).as_deref(), Some("eot"));
    }

    #[test]
    fn no_spare_reads_without_room() {
        // Oversubscribed: nothing to spare, and the old behaviour holds.
        let s = oversubscribed();
        assert_eq!(s.load().spare_rps, 0.0);
        assert_eq!(s.spare_interval_of("rpm"), None);
        // Exactly at 80 %: nothing to spare either.
        let mut s = Scheduler::new(5.0, PollPolicy::default());
        s.add("rpm", 0, ms(500), true, ms(0));
        s.add("speed", 1, ms(500), true, ms(0));
        assert_eq!(s.load().spare_rps, 0.0);
        assert_eq!(s.spare_interval_of("rpm"), None);
        // Only priority 0 is sped up.
        assert_eq!(s.spare_interval_of("speed"), None);
    }

    #[test]
    fn spare_is_shared_and_never_exceeds_80_percent() {
        // Plenty of room: both capped by the floor.
        let mut s = Scheduler::new(16.0, PollPolicy::default());
        s.add("rpm", 0, ms(500), true, ms(0));
        s.add("map", 0, ms(500), true, ms(0));
        assert_eq!(s.spare_interval_of("rpm"), Some(ms(250)));
        assert_eq!(s.spare_interval_of("map"), Some(ms(250)));
        // Little room (all 14 simulator signals: 11.73 of 15): shared equally.
        let mut s = Scheduler::new(15.0, PollPolicy::default());
        for (id, prio, every) in [
            ("rpm", 0, 500),
            ("map", 0, 500),
            ("speed", 1, 1000),
            ("icp", 1, 1000),
            ("ipr_duty", 2, 1000),
            ("load", 4, 1000),
            ("eot", 3, 1500),
            ("ect", 3, 1500),
            ("trans_temp", 3, 1500),
            ("ficm_main", 3, 1500),
            ("battery", 4, 3000),
            ("iat", 5, 3000),
            ("baro", 5, 5000),
            ("fuel_level", 6, 5000),
        ] {
            s.add(id, prio, ms(every), true, ms(0));
        }
        let l = s.load();
        assert!(!l.oversubscribed());
        assert!(l.spare_rps > 0.0 && l.planned_rps() <= 12.0 + 1e-9, "{l:?}");
        let (a, b) = (s.spare_interval_of("rpm"), s.spare_interval_of("map"));
        assert_eq!(a, b);
        assert!(a.is_some_and(|d| d < ms(500) && d > ms(450)), "{a:?}");
        // Driven at the simulator's ~65 ms round trip, real use stays under
        // 80 % of 15/s too.
        let reads = drive(&mut s, ms(65), 300);
        assert!(reads.len() as f64 / 300.0 <= 12.0);
    }

    #[test]
    fn probing_and_unhealthy_signals_shrink_the_spare() {
        let mut s = Scheduler::new(10.0, PollPolicy::default()).with_probe_budget(0.5);
        s.add("rpm", 0, ms(500), true, ms(0));
        s.add("map", 0, ms(500), true, ms(0));
        s.add("x", 1, ms(250), true, ms(0)); // 4/s
        s.add("y", 1, ms(250), true, ms(0)); // 4/s: 12/s healthy, over 8
        assert_eq!(s.load().spare_rps, 0.0);
        // y quarantined: x and the priority 0s still ask 8/s, 80 % of 10.
        s.record_miss("y", Miss::Unsupported, ms(0));
        assert_eq!(s.load().spare_rps, 0.0);
        // x quarantined too: demand 4/s, room 8 − 4 − 0.5 (probes) = 3.5/s,
        // shared by RPM and MAP but capped at +2/s each by the floor.
        s.record_miss("x", Miss::Unsupported, ms(0));
        let l = s.load();
        assert!((l.spare_rps - 3.5).abs() < 1e-3, "{l:?}");
        assert!(l.planned_rps() + 0.5 <= 8.0 + 1e-9);
        // A priority-0 signal with a recent miss is not sped up.
        s.record_miss("map", Miss::NoResponse, ms(0));
        assert_eq!(s.state_of("map"), Some(PollState::Suspect));
        assert_eq!(s.spare_interval_of("map"), None);
        assert_eq!(s.spare_interval_of("rpm"), Some(ms(250)));
    }

    #[test]
    fn spare_reads_keep_groups_and_do_not_drag_members_along() {
        let secs = 120;
        let mut s = Scheduler::new(16.0, PollPolicy::default());
        s.add("map", 0, ms(500), true, ms(0));
        s.add("baro", 5, ms(5000), true, ms(0));
        s.add("icp", 1, ms(500), true, ms(0));
        s.group(&["map".into(), "baro".into()]);
        s.group(&["map".into(), "icp".into()]);
        let reads = drive(&mut s, CAN_RTT, secs);
        assert!(rate(&reads, "map", secs) >= 3.5);
        // Baro still every 5 s, and MAP is read next to it.
        assert!(count(&reads, "baro") as u64 <= secs / 5 + 1);
        assert!(always_next_to(&reads, "baro", "map"));
        // ICP (same registry interval as MAP) is not pulled along by MAP's
        // early reads: about every 500 ms + a round trip, not every 250 ms.
        let icp = rate(&reads, "icp", secs);
        assert!(icp <= 2.0 + 1e-9, "icp {icp:.2} Hz");
        assert!(icp >= 1.0 / 0.65, "icp {icp:.2} Hz");
    }

    #[test]
    fn spare_floor_max_turns_spare_reads_off() {
        let mut s = truck_can().with_spare_floor(Duration::MAX);
        assert_eq!(s.load().spare_rps, 0.0);
        assert_eq!(s.spare_interval_of("rpm"), None);
        assert_eq!(s.next(ms(0)).as_deref(), Some("rpm"));
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
