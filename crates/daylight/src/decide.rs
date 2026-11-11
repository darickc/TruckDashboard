//! Day or night, from the driver's choice and the sun.
//!
//! - **Day / Night** chosen by hand: that mode, always.
//! - **Auto**: the sun decides, with hysteresis, but only on a location and
//!   a clock that can be believed. Otherwise the fallback mode, and the
//!   decision says why ([`Unavailable`]), so the screen never claims to
//!   follow the sun when it can't.
//!
//! The sun is worked out whatever the choice, so the screen can show it and
//! the hysteresis is already settled when the driver goes back to Auto.

use crate::sun::{Location, elevation_deg};

/// What the display shows.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Day,
    Night,
}

/// The driver's setting.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Choice {
    Auto,
    Day,
    Night,
}

impl Choice {
    pub fn name(self) -> &'static str {
        match self {
            Choice::Auto => "auto",
            Choice::Day => "day",
            Choice::Night => "night",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match s.trim().to_ascii_lowercase().as_str() {
            "auto" => Some(Choice::Auto),
            "day" => Some(Choice::Day),
            "night" => Some(Choice::Night),
            _ => None,
        }
    }
}

impl Mode {
    pub fn name(self) -> &'static str {
        match self {
            Mode::Day => "day",
            Mode::Night => "night",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match s.trim().to_ascii_lowercase().as_str() {
            "day" => Some(Mode::Day),
            "night" => Some(Mode::Night),
            _ => None,
        }
    }
}

/// Why the sun can't be worked out.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Unavailable {
    /// No latitude and longitude configured.
    NoLocation,
    /// The system doesn't report the clock synchronized, and the
    /// configuration doesn't say to trust it anyway.
    ClockNotSynchronized,
    /// The clock reads before [`EARLIEST_PLAUSIBLE_UNIX`]: never believed.
    ClockImplausible,
}

impl Unavailable {
    pub fn describe(self) -> &'static str {
        match self {
            Unavailable::NoLocation => "no location configured",
            Unavailable::ClockNotSynchronized => "clock not synchronized",
            Unavailable::ClockImplausible => "clock not set",
        }
    }
}

/// The sun, as far as it is known.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum SunState {
    Known {
        elevation_deg: f64,
        /// Day or night by the sun, with hysteresis.
        mode: Mode,
    },
    Unknown(Unavailable),
}

/// What decided the mode.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Basis {
    /// Auto, following the sun.
    Sun,
    /// The driver chose Day or Night.
    Manual,
    /// Auto, but the sun is unknown: the configured fallback.
    Fallback,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Decision {
    pub mode: Mode,
    pub basis: Basis,
    pub sun: SunState,
}

/// 2026-01-01T00:00:00Z. A clock before this has never been set (the Pi
/// without its RTC cell boots at the image's build time or the last
/// shutdown's); whatever the trust setting, the sun isn't worked out from it.
pub const EARLIEST_PLAUSIBLE_UNIX: f64 = 1_767_225_600.0;

/// When the sun makes it night. Example values (ADR-0028), not requirements.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Thresholds {
    /// Night once the sun is below this.
    pub night_below_deg: f64,
    /// Day again only once the sun is this much above `night_below_deg`.
    pub hysteresis_deg: f64,
}

impl Default for Thresholds {
    fn default() -> Self {
        Self {
            night_below_deg: -3.0,
            hysteresis_deg: 1.0,
        }
    }
}

impl Thresholds {
    pub fn validate(&self) -> Result<(), String> {
        if !self.night_below_deg.is_finite() || !(-18.0..=10.0).contains(&self.night_below_deg) {
            return Err(format!(
                "the night threshold must be -18 to 10 degrees, got {}",
                self.night_below_deg
            ));
        }
        if !self.hysteresis_deg.is_finite() || !(0.0..=5.0).contains(&self.hysteresis_deg) {
            return Err(format!(
                "the hysteresis must be 0 to 5 degrees, got {}",
                self.hysteresis_deg
            ));
        }
        Ok(())
    }
}

/// Keeps the sun's last day/night for the hysteresis.
#[derive(Debug, Clone)]
pub struct DayNight {
    thresholds: Thresholds,
    fallback: Mode,
    sun_mode: Option<Mode>,
}

impl DayNight {
    pub fn new(thresholds: Thresholds, fallback: Mode) -> Self {
        Self {
            thresholds,
            fallback,
            sun_mode: None,
        }
    }

    pub fn thresholds(&self) -> Thresholds {
        self.thresholds
    }

    pub fn fallback(&self) -> Mode {
        self.fallback
    }

    /// The mode now. `clock_trusted`: the system reports the clock
    /// synchronized, or the configuration says to trust it.
    pub fn decide(
        &mut self,
        choice: Choice,
        location: Option<Location>,
        clock_trusted: bool,
        now_unix: f64,
    ) -> Decision {
        let sun = self.sun(location, clock_trusted, now_unix);
        let (mode, basis) = match (choice, sun) {
            (Choice::Day, _) => (Mode::Day, Basis::Manual),
            (Choice::Night, _) => (Mode::Night, Basis::Manual),
            (Choice::Auto, SunState::Known { mode, .. }) => (mode, Basis::Sun),
            (Choice::Auto, SunState::Unknown(_)) => (self.fallback, Basis::Fallback),
        };
        Decision { mode, basis, sun }
    }

    fn sun(&mut self, location: Option<Location>, clock_trusted: bool, now_unix: f64) -> SunState {
        let why = match location {
            None => Some(Unavailable::NoLocation),
            Some(_) if !now_unix.is_finite() || now_unix < EARLIEST_PLAUSIBLE_UNIX => {
                Some(Unavailable::ClockImplausible)
            }
            Some(_) if !clock_trusted => Some(Unavailable::ClockNotSynchronized),
            Some(_) => None,
        };
        let (Some(at), None) = (location, why) else {
            // Start afresh when the sun comes back: the old state may be
            // hours out of date.
            self.sun_mode = None;
            return SunState::Unknown(why.unwrap_or(Unavailable::NoLocation));
        };
        let elevation_deg = elevation_deg(now_unix, at);
        let t = self.thresholds;
        let mode = match self.sun_mode {
            Some(Mode::Night) if elevation_deg <= t.night_below_deg + t.hysteresis_deg => {
                Mode::Night
            }
            Some(Mode::Night) => Mode::Day,
            _ if elevation_deg < t.night_below_deg => Mode::Night,
            _ => Mode::Day,
        };
        self.sun_mode = Some(mode);
        SunState::Known {
            elevation_deg,
            mode,
        }
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::*;

    // Denver: 2026-11-11 sunset is about 23:44 UTC (16:44 MST).
    const NOV_11_2026_NOON_UTC: f64 = 1_794_398_400.0;

    fn denver() -> Option<Location> {
        Some(Location::new(39.739, -104.990).unwrap())
    }

    fn dn() -> DayNight {
        DayNight::new(Thresholds::default(), Mode::Day)
    }

    /// The first time after `from` (stepping a minute) the sun is
    /// below/above `deg`.
    fn when(from: f64, deg: f64, falling: bool) -> f64 {
        let at = denver().unwrap();
        let mut t = from;
        loop {
            let e = elevation_deg(t, at);
            if (falling && e < deg) || (!falling && e > deg) {
                return t;
            }
            t += 60.0;
            assert!(t < from + 2.0 * 86_400.0, "never crossed {deg}");
        }
    }

    #[test]
    fn noon_reference_is_right() {
        // 2026-11-11T12:00:00Z
        assert_eq!(
            NOV_11_2026_NOON_UTC,
            EARLIEST_PLAUSIBLE_UNIX + 314.5 * 86_400.0
        );
    }

    #[test]
    fn auto_follows_the_sun_through_dusk_and_dawn() {
        let mut d = dn();
        let day = NOV_11_2026_NOON_UTC + 7.0 * 3600.0; // 19:00Z, midday in Denver
        let r = d.decide(Choice::Auto, denver(), true, day);
        assert_eq!((r.mode, r.basis), (Mode::Day, Basis::Sun));

        let dusk = when(day, -3.0, true);
        let r = d.decide(Choice::Auto, denver(), true, dusk - 120.0);
        assert_eq!(r.mode, Mode::Day);
        let r = d.decide(Choice::Auto, denver(), true, dusk);
        assert_eq!((r.mode, r.basis), (Mode::Night, Basis::Sun));

        let dawn = when(dusk + 3600.0, -2.0, false);
        // Between -3° and -2° on the way up it stays night (hysteresis).
        let r = d.decide(Choice::Auto, denver(), true, dawn - 120.0);
        assert_eq!(r.mode, Mode::Night);
        let r = d.decide(Choice::Auto, denver(), true, dawn);
        assert_eq!(r.mode, Mode::Day);
    }

    #[test]
    fn hysteresis_holds_night_in_the_band() {
        let mut d = dn();
        let at = denver().unwrap();
        let night = when(NOV_11_2026_NOON_UTC + 7.0 * 3600.0, -3.0, true);
        assert_eq!(
            d.decide(Choice::Auto, denver(), true, night).mode,
            Mode::Night
        );
        // From cold (no previous sun state) a sun at -2.5° is day; after night
        // it stays night.
        let band = when(night + 3600.0, -2.5, false);
        assert!((elevation_deg(band, at) - -2.5).abs() < 0.3);
        assert_eq!(
            d.decide(Choice::Auto, denver(), true, band).mode,
            Mode::Night
        );
        let mut cold = dn();
        assert_eq!(
            cold.decide(Choice::Auto, denver(), true, band).mode,
            Mode::Day
        );
    }

    #[test]
    fn manual_choices_win_but_the_sun_is_still_reported() {
        let mut d = dn();
        let midday = NOV_11_2026_NOON_UTC + 7.0 * 3600.0;
        let r = d.decide(Choice::Night, denver(), true, midday);
        assert_eq!((r.mode, r.basis), (Mode::Night, Basis::Manual));
        assert!(matches!(
            r.sun,
            SunState::Known {
                mode: Mode::Day,
                ..
            }
        ));
        let r = d.decide(Choice::Day, None, false, 0.0);
        assert_eq!((r.mode, r.basis), (Mode::Day, Basis::Manual));
        assert_eq!(r.sun, SunState::Unknown(Unavailable::NoLocation));
    }

    #[test]
    fn auto_falls_back_and_says_why() {
        let midnight = NOV_11_2026_NOON_UTC + 18.0 * 3600.0; // 06:00Z, 23:00 in Denver
        let cases = [
            (None, true, midnight, Unavailable::NoLocation),
            (denver(), false, midnight, Unavailable::ClockNotSynchronized),
            // A clock at the image's build time a year back, even "trusted".
            (
                denver(),
                true,
                EARLIEST_PLAUSIBLE_UNIX - 86_400.0,
                Unavailable::ClockImplausible,
            ),
            (denver(), true, f64::NAN, Unavailable::ClockImplausible),
        ];
        for fallback in [Mode::Day, Mode::Night] {
            for (loc, trusted, now, why) in cases {
                let mut d = DayNight::new(Thresholds::default(), fallback);
                let r = d.decide(Choice::Auto, loc, trusted, now);
                assert_eq!(r.mode, fallback);
                assert_eq!(r.basis, Basis::Fallback);
                assert_eq!(r.sun, SunState::Unknown(why));
            }
        }
    }

    #[test]
    fn losing_the_clock_resets_the_hysteresis() {
        let mut d = dn();
        let night = when(NOV_11_2026_NOON_UTC + 7.0 * 3600.0, -3.0, true);
        d.decide(Choice::Auto, denver(), true, night);
        d.decide(Choice::Auto, denver(), false, night);
        let band = when(night + 3600.0, -2.5, false);
        // Fresh start: -2.5° is day, as from cold.
        assert_eq!(d.decide(Choice::Auto, denver(), true, band).mode, Mode::Day);
    }

    #[test]
    fn thresholds_are_checked() {
        assert!(Thresholds::default().validate().is_ok());
        for (n, h) in [
            (-19.0, 1.0),
            (11.0, 1.0),
            (f64::NAN, 1.0),
            (-3.0, -0.1),
            (-3.0, 6.0),
        ] {
            assert!(
                Thresholds {
                    night_below_deg: n,
                    hysteresis_deg: h
                }
                .validate()
                .is_err(),
                "{n} {h}"
            );
        }
    }

    #[test]
    fn names_round_trip() {
        for c in [Choice::Auto, Choice::Day, Choice::Night] {
            assert_eq!(Choice::parse(c.name()), Some(c));
        }
        for m in [Mode::Day, Mode::Night] {
            assert_eq!(Mode::parse(m.name()), Some(m));
        }
        assert_eq!(Choice::parse(" AUTO "), Some(Choice::Auto));
        assert_eq!(Choice::parse("dusk"), None);
    }
}
