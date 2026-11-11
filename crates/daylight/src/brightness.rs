//! Backlight levels: the driver's percentage per mode, mapped onto the
//! device's `max_brightness`, never below a floor, and ramped.

use std::time::Duration;

use crate::decide::Mode;

/// The driver's brightness for each mode, in percent.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Levels {
    pub day_pct: u8,
    pub night_pct: u8,
}

impl Default for Levels {
    /// Example values (ADR-0028).
    fn default() -> Self {
        Self {
            day_pct: 100,
            night_pct: 40,
        }
    }
}

impl Levels {
    pub fn for_mode(&self, mode: Mode) -> u8 {
        match mode {
            Mode::Day => self.day_pct,
            Mode::Night => self.night_pct,
        }
    }

    /// Both levels clamped to `[floor, 100]`.
    pub fn clamped(self, floor_pct: u8) -> Self {
        Self {
            day_pct: clamp_pct(u32::from(self.day_pct), floor_pct),
            night_pct: clamp_pct(u32::from(self.night_pct), floor_pct),
        }
    }
}

/// A percentage clamped to `[floor, 100]` (the floor itself at most 100).
pub fn clamp_pct(pct: u32, floor_pct: u8) -> u8 {
    let floor = u32::from(floor_pct.min(100));
    // In range by construction.
    u8::try_from(pct.clamp(floor, 100)).unwrap_or(100)
}

/// The device value for a percentage: rounded, and at least 1 so a low
/// percentage on a coarse device never turns the backlight off.
pub fn raw_for(pct: u8, max: u32) -> u32 {
    if max == 0 {
        return 0;
    }
    let raw = (u64::from(pct.min(100)) * u64::from(max) + 50) / 100;
    u32::try_from(raw).unwrap_or(max).clamp(1, max)
}

/// A device value as a percentage of `max`, rounded.
pub fn pct_of(raw: u32, max: u32) -> u8 {
    if max == 0 {
        return 0;
    }
    let pct = (u64::from(raw.min(max)) * 100 + u64::from(max) / 2) / u64::from(max);
    u8::try_from(pct).unwrap_or(100)
}

/// A straight-line change from one device value to another.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Ramp {
    from: u32,
    to: u32,
    duration: Duration,
}

impl Ramp {
    pub fn new(from: u32, to: u32, duration: Duration) -> Self {
        Self { from, to, duration }
    }

    pub fn target(&self) -> u32 {
        self.to
    }

    /// The value `elapsed` into the ramp; the target once it is over.
    pub fn at(&self, elapsed: Duration) -> u32 {
        if self.done(elapsed) {
            return self.to;
        }
        let f = elapsed.as_secs_f64() / self.duration.as_secs_f64();
        let v = f64::from(self.from) + (f64::from(self.to) - f64::from(self.from)) * f;
        // Between from and to, so it fits.
        v.round().clamp(0.0, f64::from(u32::MAX)) as u32
    }

    pub fn done(&self, elapsed: Duration) -> bool {
        self.duration.is_zero() || elapsed >= self.duration || self.from == self.to
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::*;

    #[test]
    fn percent_to_device_value() {
        assert_eq!(raw_for(100, 255), 255);
        assert_eq!(raw_for(40, 255), 102);
        assert_eq!(raw_for(10, 255), 26);
        assert_eq!(raw_for(0, 255), 1, "never off");
        assert_eq!(raw_for(1, 10), 1);
        assert_eq!(raw_for(200, 255), 255);
        assert_eq!(raw_for(50, 0), 0);
        assert_eq!(raw_for(50, u32::MAX), 2_147_483_648);
    }

    #[test]
    fn device_value_to_percent() {
        assert_eq!(pct_of(255, 255), 100);
        assert_eq!(pct_of(102, 255), 40);
        assert_eq!(pct_of(1, 255), 0);
        assert_eq!(pct_of(300, 255), 100);
        assert_eq!(pct_of(5, 0), 0);
        for pct in 0..=100u8 {
            assert_eq!(pct_of(raw_for(pct.max(1), 255), 255), pct.max(1), "{pct}");
        }
    }

    #[test]
    fn clamps_to_the_floor() {
        assert_eq!(clamp_pct(5, 10), 10);
        assert_eq!(clamp_pct(0, 10), 10);
        assert_eq!(clamp_pct(55, 10), 55);
        assert_eq!(clamp_pct(150, 10), 100);
        assert_eq!(clamp_pct(1000, 200), 100);
        let l = Levels {
            day_pct: 3,
            night_pct: 120,
        }
        .clamped(10);
        assert_eq!((l.day_pct, l.night_pct), (10, 100));
    }

    #[test]
    fn levels_per_mode() {
        let l = Levels::default();
        assert_eq!(l.for_mode(Mode::Day), 100);
        assert_eq!(l.for_mode(Mode::Night), 40);
    }

    #[test]
    fn ramps_in_a_straight_line_both_ways() {
        let s = Duration::from_secs(1);
        let up = Ramp::new(100, 200, s);
        assert_eq!(up.at(Duration::ZERO), 100);
        assert_eq!(up.at(Duration::from_millis(250)), 125);
        assert_eq!(up.at(Duration::from_millis(500)), 150);
        assert_eq!(up.at(s), 200);
        assert_eq!(up.at(Duration::from_secs(5)), 200);
        assert!(!up.done(Duration::from_millis(999)));
        assert!(up.done(s));
        let down = Ramp::new(255, 26, s);
        assert_eq!(down.at(Duration::from_millis(500)), 141);
        assert_eq!(down.target(), 26);
    }

    #[test]
    fn a_zero_or_empty_ramp_is_done_at_once() {
        let r = Ramp::new(10, 200, Duration::ZERO);
        assert!(r.done(Duration::ZERO));
        assert_eq!(r.at(Duration::ZERO), 200);
        let same = Ramp::new(50, 50, Duration::from_secs(1));
        assert!(same.done(Duration::ZERO));
    }
}
