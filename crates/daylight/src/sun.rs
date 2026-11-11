//! The sun's elevation above the horizon.
//!
//! The Astronomical Almanac's low-precision formulas (good to about 0.01° in
//! the sun's position between 1950 and 2050), with Greenwich mean sidereal
//! time for the hour angle. No refraction: at the thresholds used for
//! day/night (a few degrees below the horizon) it changes nothing that
//! matters. Day/night needs a degree, not an arc-second.

/// Where the truck is, in degrees. North and east are positive.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Location {
    latitude_deg: f64,
    longitude_deg: f64,
}

impl Location {
    /// Rejects anything that isn't a place on Earth.
    pub fn new(latitude_deg: f64, longitude_deg: f64) -> Result<Self, String> {
        if !latitude_deg.is_finite() || !(-90.0..=90.0).contains(&latitude_deg) {
            return Err(format!(
                "latitude must be -90 to 90 degrees, got {latitude_deg}"
            ));
        }
        if !longitude_deg.is_finite() || !(-180.0..=180.0).contains(&longitude_deg) {
            return Err(format!(
                "longitude must be -180 to 180 degrees (east positive), got {longitude_deg}"
            ));
        }
        Ok(Self {
            latitude_deg,
            longitude_deg,
        })
    }

    pub fn latitude_deg(&self) -> f64 {
        self.latitude_deg
    }

    pub fn longitude_deg(&self) -> f64 {
        self.longitude_deg
    }
}

/// Seconds since 1970-01-01T00:00:00Z → days since J2000.0 (2000-01-01T12:00Z).
fn days_since_j2000(unix_secs: f64) -> f64 {
    unix_secs / 86_400.0 + 2_440_587.5 - 2_451_545.0
}

/// The sun's elevation in degrees at `unix_secs` (UTC) seen from `at`:
/// positive above the horizon.
pub fn elevation_deg(unix_secs: f64, at: Location) -> f64 {
    let n = days_since_j2000(unix_secs);
    // Mean longitude and mean anomaly.
    let l = (280.460 + 0.985_647_4 * n).rem_euclid(360.0);
    let g = (357.528 + 0.985_600_3 * n).rem_euclid(360.0).to_radians();
    // Ecliptic longitude and the obliquity of the ecliptic.
    let lambda = (l + 1.915 * g.sin() + 0.020 * (2.0 * g).sin()).to_radians();
    let epsilon = (23.439 - 0.000_000_4 * n).to_radians();
    // Right ascension and declination.
    let ra = (epsilon.cos() * lambda.sin()).atan2(lambda.cos());
    let dec = (epsilon.sin() * lambda.sin()).asin();
    // Greenwich mean sidereal time → local hour angle.
    let gmst_deg = (280.460_618_37 + 360.985_647_366_29 * n).rem_euclid(360.0);
    let hour_angle = (gmst_deg + at.longitude_deg).to_radians() - ra;
    let lat = at.latitude_deg.to_radians();
    let sin_elev = lat.sin() * dec.sin() + lat.cos() * dec.cos() * hour_angle.cos();
    sin_elev.clamp(-1.0, 1.0).asin().to_degrees()
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::*;

    /// 2026-mm-ddThh:mm:00Z as Unix seconds (proleptic Gregorian; no leap
    /// seconds, as Unix time).
    fn utc(y: i64, m: i64, d: i64, hh: i64, mm: i64) -> f64 {
        // Days from civil (Howard Hinnant's algorithm).
        let y = if m <= 2 { y - 1 } else { y };
        let era = y.div_euclid(400);
        let yoe = y - era * 400;
        let mp = (m + 9) % 12;
        let doy = (153 * mp + 2) / 5 + d - 1;
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        let days = era * 146_097 + doe - 719_468;
        (days * 86_400 + hh * 3600 + mm * 60) as f64
    }

    fn at(lat: f64, lon: f64) -> Location {
        Location::new(lat, lon).unwrap()
    }

    #[test]
    fn utc_helper_matches_known_unix_times() {
        assert_eq!(utc(1970, 1, 1, 0, 0), 0.0);
        assert_eq!(utc(2026, 1, 1, 0, 0), 1_767_225_600.0);
        assert_eq!(utc(2000, 1, 1, 12, 0), 946_728_000.0);
    }

    /// Reference elevations from an independent implementation of NOAA's
    /// solar calculator (the "General Solar Position" spreadsheet's
    /// equations: Julian century, equation of time, true solar time),
    /// written separately in Python for these vectors, without refraction.
    /// Agreement within 0.1°.
    #[test]
    fn matches_noaa_reference_vectors() {
        let cases = [
            // (lat, lon, y, m, d, hh, mm, elevation)
            (39.739, -104.990, 2026, 6, 21, 19, 0, 73.69),
            (39.739, -104.990, 2026, 12, 21, 19, 0, 26.82),
            (39.739, -104.990, 2026, 11, 11, 1, 0, -14.03),
            (51.5, -0.13, 2026, 3, 20, 12, 0, 38.43),
            (0.0, 0.0, 2026, 9, 23, 12, 0, 88.09),
            (-33.87, 151.21, 2026, 1, 15, 2, 0, 77.24),
            (64.84, -147.72, 2026, 12, 21, 21, 30, 1.64),
            (35.0, 139.0, 2026, 7, 1, 9, 15, 7.82),
            (-60.0, -70.0, 2026, 4, 10, 15, 45, 20.97),
        ];
        for (lat, lon, y, m, d, hh, mm, want) in cases {
            let got = elevation_deg(utc(y, m, d, hh, mm), at(lat, lon));
            assert!(
                (got - want).abs() < 0.1,
                "{lat},{lon} {y}-{m}-{d} {hh}:{mm}Z: got {got:.2}, want {want:.2}"
            );
        }
    }

    /// Published sunrise and sunset happen at an apparent elevation of
    /// -0.833° (refraction plus the sun's radius). London's sunrise on the
    /// 2026 summer solstice is about 04:43 BST (03:43 UTC); Sydney's sunset
    /// on the winter solstice (June) about 16:54 AEST (06:54 UTC).
    #[test]
    fn crosses_sunrise_and_sunset_near_published_times() {
        let london = at(51.5074, -0.1278);
        let before = elevation_deg(utc(2026, 6, 21, 3, 39), london);
        let after = elevation_deg(utc(2026, 6, 21, 3, 47), london);
        assert!(before < -0.833 && after > -0.833, "{before} {after}");

        let sydney = at(-33.8688, 151.2093);
        let before = elevation_deg(utc(2026, 6, 21, 6, 50), sydney);
        let after = elevation_deg(utc(2026, 6, 21, 6, 58), sydney);
        assert!(before > -0.833 && after < -0.833, "{before} {after}");
    }

    #[test]
    fn noon_on_the_equator_at_an_equinox_is_overhead() {
        let e = elevation_deg(utc(2026, 3, 20, 12, 7), at(0.0, 0.0));
        assert!(e > 88.5, "{e}");
    }

    #[test]
    fn polar_night_and_midnight_sun() {
        let svalbard = at(78.22, 15.65);
        for hh in 0..24 {
            let winter = elevation_deg(utc(2026, 12, 21, hh, 0), svalbard);
            let summer = elevation_deg(utc(2026, 6, 21, hh, 0), svalbard);
            assert!(winter < 0.0, "{hh}: {winter}");
            assert!(summer > 0.0, "{hh}: {summer}");
        }
    }

    #[test]
    fn rejects_places_off_the_earth() {
        assert!(Location::new(90.1, 0.0).is_err());
        assert!(Location::new(-91.0, 0.0).is_err());
        assert!(Location::new(0.0, 180.5).is_err());
        assert!(Location::new(f64::NAN, 0.0).is_err());
        assert!(Location::new(0.0, f64::INFINITY).is_err());
        assert!(Location::new(-90.0, -180.0).is_ok());
    }
}
