//! gps-clock's decisions (ADR-0049): when a GPS time may set the system
//! clock, with no I/O and no clock of its own. `main.rs` feeds it
//! navigation's positions and does what it says.
//!
//! The rules:
//!
//! - **Only a real, current fix's time.** Not the simulated receiver, not a
//!   last-known fix, not a fix without a 2D/3D status or a UTC time, and
//!   never a time before 2026 (a week rollover). The time is the fix's UTC
//!   plus its age when navigation sent it ([`gps_time`]).
//! - **Network time wins.** While the system reports network time
//!   (`clock_sync::network_synchronized`), gps-clock does nothing:
//!   [`Verdict::HandsOff`].
//! - **Agreement first.** [`Policy::needed`] readings in a row whose GPS
//!   time agrees with the monotonic clock within [`Policy::agree_s`], so one
//!   bad report never sets the clock. A disagreeing reading starts again.
//! - **Step only when it is off.** More than [`Policy::step_threshold_s`]
//!   between GPS and the system clock: [`Verdict::Step`]. Otherwise
//!   [`Verdict::Confirm`]: the clock (from the RTC, say) is right. Without
//!   PPS, gpsd's time is good to a fraction of a second, so the threshold
//!   is an example, not a measured figure (UNVERIFIED until a receiver is
//!   fitted, H11).
//! - **Not over and over.** After a step, no other step for
//!   [`Policy::min_step_interval`]: a clock that needs stepping again so
//!   soon means something is wrong, and gps-clock says so.

use std::time::{Duration, Instant};

use f250_proto::nav::v1 as nav;

/// The tunables. Examples, not measured (ADR-0049).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Policy {
    /// Step the clock when GPS and the system differ by more than this.
    pub step_threshold_s: f64,
    /// Readings agree when their GPS-minus-monotonic offsets are this close.
    pub agree_s: f64,
    /// Agreeing readings in a row before anything is done.
    pub needed: u32,
    /// No second step sooner than this after one.
    pub min_step_interval: Duration,
}

impl Default for Policy {
    fn default() -> Self {
        Self {
            step_threshold_s: 1.0,
            agree_s: 0.5,
            needed: 3,
            min_step_interval: Duration::from_secs(600),
        }
    }
}

/// What to do with one reading.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Verdict {
    /// Nothing yet: why.
    Wait(&'static str),
    /// Network time keeps the clock: leave it alone.
    HandsOff,
    /// The clock agrees with GPS within the threshold. `offset_s`: GPS
    /// minus system.
    Confirm { offset_s: f64 },
    /// Set the clock forward (positive) or back by `offset_s`.
    Step { offset_s: f64 },
    /// It needs a step, but one was made less than
    /// [`Policy::min_step_interval`] ago.
    TooSoon { offset_s: f64 },
}

/// UTC (seconds) at the moment navigation sent `p`, when `p` may set the
/// clock: a real, current 2D/3D fix with a UTC time from 2026 on. With
/// `accept_simulated` (development only), the simulated receiver's too.
pub fn gps_time(p: &nav::Position, accept_simulated: bool) -> Option<f64> {
    if p.simulated && !accept_simulated {
        return None;
    }
    if !p.current {
        return None;
    }
    if !matches!(
        nav::FixStatus::try_from(p.status),
        Ok(nav::FixStatus::Fix2d | nav::FixStatus::Fix3d)
    ) {
        return None;
    }
    let fix = p.fix.as_ref()?;
    let ms = fix.utc_time_ms?;
    let unix = ms as f64 / 1000.0 + fix.age_ms as f64 / 1000.0;
    (unix.is_finite() && unix >= clock_sync::EARLIEST_PLAUSIBLE_UNIX as f64).then_some(unix)
}

/// The decisions, one reading at a time.
#[derive(Debug, Clone)]
pub struct Decider {
    policy: Policy,
    /// GPS UTC minus the monotonic clock (as seconds since `origin`) of the
    /// last reading, and how many in a row have agreed.
    last: Option<f64>,
    streak: u32,
    last_step: Option<Instant>,
    origin: Instant,
}

impl Decider {
    pub fn new(policy: Policy, origin: Instant) -> Self {
        Self {
            policy,
            last: None,
            streak: 0,
            last_step: None,
            origin,
        }
    }

    /// One reading: `gps_unix` from [`gps_time`], received at `at`;
    /// `sys_unix` the system clock at that moment; `network` whether network
    /// time keeps the clock.
    pub fn reading(&mut self, gps_unix: f64, at: Instant, sys_unix: f64, network: bool) -> Verdict {
        let mono = at.saturating_duration_since(self.origin).as_secs_f64();
        let g = gps_unix - mono;
        match self.last {
            Some(prev) if (g - prev).abs() <= self.policy.agree_s => {
                self.streak = self.streak.saturating_add(1);
            }
            _ => self.streak = 1,
        }
        self.last = Some(g);
        if network {
            return Verdict::HandsOff;
        }
        if self.streak < self.policy.needed {
            return Verdict::Wait("waiting for GPS times that agree");
        }
        let offset_s = gps_unix - sys_unix;
        if offset_s.abs() <= self.policy.step_threshold_s {
            return Verdict::Confirm { offset_s };
        }
        if let Some(t) = self.last_step
            && at.saturating_duration_since(t) < self.policy.min_step_interval
        {
            return Verdict::TooSoon { offset_s };
        }
        Verdict::Step { offset_s }
    }

    /// The step was made at `at`.
    pub fn stepped(&mut self, at: Instant) {
        self.last_step = Some(at);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // 2026-11-11T18:00:00Z.
    const T: f64 = 1_794_423_600.0;

    fn pos(
        status: nav::FixStatus,
        current: bool,
        simulated: bool,
        ms: Option<i64>,
    ) -> nav::Position {
        nav::Position {
            status: status as i32,
            current,
            simulated,
            fix: Some(nav::Fix {
                latitude_deg: 39.8,
                longitude_deg: -98.6,
                utc_time_ms: ms,
                age_ms: 200,
                ..Default::default()
            }),
            ..Default::default()
        }
    }

    #[test]
    fn only_a_real_current_fix_from_2026_on_gives_a_time() {
        let ms = Some((T * 1000.0) as i64);
        let good = pos(nav::FixStatus::Fix3d, true, false, ms);
        assert_eq!(
            gps_time(&good, false),
            Some(T + 0.2),
            "the fix's time plus its age"
        );
        assert!(gps_time(&pos(nav::FixStatus::Fix2d, true, false, ms), false).is_some());
        assert_eq!(
            gps_time(&pos(nav::FixStatus::Fix3d, false, false, ms), false),
            None,
            "not current"
        );
        assert_eq!(
            gps_time(&pos(nav::FixStatus::NoFix, true, false, ms), false),
            None,
            "no fix"
        );
        assert_eq!(
            gps_time(&pos(nav::FixStatus::Fix3d, true, false, None), false),
            None,
            "no time"
        );
        assert_eq!(
            gps_time(
                &pos(nav::FixStatus::Fix3d, true, false, Some(1_560_000_000_000)),
                false
            ),
            None,
            "2019: a week rollover"
        );
        let sim = pos(nav::FixStatus::Fix3d, true, true, ms);
        assert_eq!(
            gps_time(&sim, false),
            None,
            "the simulated receiver is never the truck"
        );
        assert!(
            gps_time(&sim, true).is_some(),
            "unless asked, for development"
        );
        let mut nofix = good.clone();
        nofix.fix = None;
        assert_eq!(gps_time(&nofix, false), None);
    }

    /// Readings one second apart from `start`, GPS at `gps0` and the system
    /// `sys_off` seconds from it.
    fn feed(
        d: &mut Decider,
        start: Instant,
        n: u32,
        gps0: f64,
        sys_off: f64,
        net: bool,
    ) -> Vec<Verdict> {
        (0..n)
            .map(|i| {
                let at = start + Duration::from_secs(u64::from(i));
                let g = gps0 + f64::from(i);
                d.reading(g, at, g + sys_off, net)
            })
            .collect()
    }

    #[test]
    fn waits_for_three_agreeing_readings_then_steps_a_wrong_clock() {
        let o = Instant::now();
        let mut d = Decider::new(Policy::default(), o);
        // The clock reads the last shutdown, a day behind.
        let v = feed(&mut d, o, 3, T, -86_400.0, false);
        assert!(matches!(v[0], Verdict::Wait(_)));
        assert!(matches!(v[1], Verdict::Wait(_)));
        assert_eq!(v[2], Verdict::Step { offset_s: 86_400.0 });
    }

    #[test]
    fn a_right_clock_is_confirmed_not_stepped() {
        let o = Instant::now();
        let mut d = Decider::new(Policy::default(), o);
        let v = feed(&mut d, o, 3, T, 0.4, false);
        assert!(
            matches!(v[2], Verdict::Confirm { offset_s } if (offset_s + 0.4).abs() < 1e-3),
            "{v:?}"
        );
        // Just inside the threshold still confirms; just outside steps.
        let mut d = Decider::new(Policy::default(), o);
        let v = feed(&mut d, o, 3, T, -0.99, false);
        assert!(matches!(v[2], Verdict::Confirm { .. }), "{v:?}");
        let mut d = Decider::new(Policy::default(), o);
        let v = feed(&mut d, o, 3, T, -1.01, false);
        assert!(matches!(v[2], Verdict::Step { .. }), "{v:?}");
    }

    #[test]
    fn a_reading_that_disagrees_starts_again() {
        let o = Instant::now();
        let mut d = Decider::new(Policy::default(), o);
        feed(&mut d, o, 2, T, -60.0, false);
        // The third reading jumps 5 s against the monotonic clock.
        let at = o + Duration::from_secs(2);
        assert!(matches!(
            d.reading(T + 2.0 + 5.0, at, T + 2.0 - 60.0, false),
            Verdict::Wait(_)
        ));
        // Two more that agree with it: three in a row again.
        let at3 = o + Duration::from_secs(3);
        assert!(matches!(
            d.reading(T + 8.0, at3, T + 3.0 - 60.0, false),
            Verdict::Wait(_)
        ));
        let at4 = o + Duration::from_secs(4);
        assert!(matches!(
            d.reading(T + 9.0, at4, T + 4.0 - 60.0, false),
            Verdict::Step { .. }
        ));
    }

    #[test]
    fn network_time_is_left_alone() {
        let o = Instant::now();
        let mut d = Decider::new(Policy::default(), o);
        let v = feed(&mut d, o, 5, T, -86_400.0, true);
        assert!(v.iter().all(|x| *x == Verdict::HandsOff), "{v:?}");
        // Network time gone: the readings already agree, so it acts at once.
        let at = o + Duration::from_secs(5);
        assert_eq!(
            d.reading(T + 5.0, at, T + 5.0 - 30.0, false),
            Verdict::Step { offset_s: 30.0 }
        );
    }

    #[test]
    fn no_second_step_within_ten_minutes() {
        let o = Instant::now();
        let mut d = Decider::new(Policy::default(), o);
        assert!(matches!(
            feed(&mut d, o, 3, T, -120.0, false)[2],
            Verdict::Step { .. }
        ));
        d.stepped(o + Duration::from_secs(2));
        // Still 120 s off a second later (the step didn't take): too soon.
        let at = o + Duration::from_secs(3);
        assert_eq!(
            d.reading(T + 3.0, at, T + 3.0 - 120.0, false),
            Verdict::TooSoon { offset_s: 120.0 }
        );
        // Ten minutes after the step it may step again.
        let at = o + Duration::from_secs(602);
        let g = T + 602.0;
        assert_eq!(
            d.reading(g, at, g - 120.0, false),
            Verdict::Step { offset_s: 120.0 }
        );
    }
}
