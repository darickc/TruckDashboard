//! Recording settings (ADR-0027 decision 7). Every value is a
//! recommendation for a drive size, not a measured requirement: the owner
//! sets them for the drive that is fitted (H31).

use std::collections::HashMap;

const GB: u64 = 1_000_000_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Settings {
    /// `RECORD_MAX_AGE_DAYS`: delete segments older than this; 0 = no age
    /// limit.
    pub max_age_days: u32,
    /// `RECORD_MAX_GB`: unprotected video of every camera together.
    pub max_bytes: u64,
    /// `RECORD_MIN_FREE_GB`: always this much free on the drive.
    pub min_free_bytes: u64,
    /// `RECORD_PROTECTED_MAX_GB`: saved clips together.
    pub protected_max_bytes: u64,
    /// `RECORD_MAX_SEGMENTS`: per camera; 0 = off.
    pub max_segments: u32,
    /// `RECORD_SEGMENT_S`.
    pub segment_s: u32,
    /// `RECORD_SYNC_S`.
    pub sync_s: u32,
    /// `RECORD_UNCLEAN_PROTECT_MIN`: 0 = off.
    pub unclean_protect_min: u32,
    /// `RECORD_CLIP_BEFORE_S` / `RECORD_CLIP_AFTER_S`: what "save clip"
    /// keeps around the current segment.
    pub clip_before_s: u32,
    pub clip_after_s: u32,
}

impl Settings {
    /// Recommended for a 512 GB data drive (ADR-0027, 2026-11-10).
    pub fn recommended_512gb() -> Self {
        Settings {
            max_age_days: 14,
            max_bytes: 250 * GB,
            min_free_bytes: 50 * GB,
            protected_max_bytes: 25 * GB,
            max_segments: 0,
            segment_s: 60,
            sync_s: 1,
            unclean_protect_min: 5,
            clip_before_s: 120,
            clip_after_s: 60,
        }
    }

    /// Recommended for a 1 TB data drive (ADR-0027, 2026-11-10).
    pub fn recommended_1tb() -> Self {
        Settings {
            max_bytes: 550 * GB,
            min_free_bytes: 100 * GB,
            protected_max_bytes: 50 * GB,
            ..Self::recommended_512gb()
        }
    }

    /// Settings from `/etc/default/f250`-style keys. Keys that are absent or
    /// empty keep the 512 GB recommendation; a malformed or out-of-range
    /// value is an error naming the key, never silently replaced.
    pub fn from_vars(vars: &HashMap<String, String>) -> Result<Settings, String> {
        let mut s = Settings::recommended_512gb();
        let get = |key: &str| vars.get(key).map(|v| v.trim()).filter(|v| !v.is_empty());
        let num = |key: &str, max: u64| -> Result<Option<u64>, String> {
            match get(key) {
                None => Ok(None),
                Some(v) => match v.parse::<u64>() {
                    Ok(n) if n <= max => Ok(Some(n)),
                    _ => Err(format!(
                        "{key}={v}: expected a whole number from 0 to {max}"
                    )),
                },
            }
        };
        if let Some(n) = num("RECORD_MAX_AGE_DAYS", 3650)? {
            s.max_age_days = n as u32;
        }
        if let Some(n) = num("RECORD_MAX_GB", 100_000)? {
            s.max_bytes = n * GB;
        }
        if let Some(n) = num("RECORD_MIN_FREE_GB", 100_000)? {
            s.min_free_bytes = n * GB;
        }
        if let Some(n) = num("RECORD_PROTECTED_MAX_GB", 100_000)? {
            s.protected_max_bytes = n * GB;
        }
        if let Some(n) = num("RECORD_MAX_SEGMENTS", 10_000_000)? {
            s.max_segments = n as u32;
        }
        if let Some(n) = num("RECORD_SEGMENT_S", 3600)? {
            s.segment_s = n as u32;
        }
        if let Some(n) = num("RECORD_SYNC_S", 60)? {
            s.sync_s = n as u32;
        }
        if let Some(n) = num("RECORD_UNCLEAN_PROTECT_MIN", 120)? {
            s.unclean_protect_min = n as u32;
        }
        if let Some(n) = num("RECORD_CLIP_BEFORE_S", 3600)? {
            s.clip_before_s = n as u32;
        }
        if let Some(n) = num("RECORD_CLIP_AFTER_S", 3600)? {
            s.clip_after_s = n as u32;
        }
        s.check()?;
        Ok(s)
    }

    /// Values that can't work together.
    pub fn check(&self) -> Result<(), String> {
        if self.segment_s < 10 {
            return Err(format!(
                "RECORD_SEGMENT_S={}: at least 10 s",
                self.segment_s
            ));
        }
        if self.sync_s == 0 || self.sync_s > self.segment_s {
            return Err(format!(
                "RECORD_SYNC_S={}: from 1 s to the segment length ({} s)",
                self.sync_s, self.segment_s
            ));
        }
        if self.max_bytes == 0 {
            return Err("RECORD_MAX_GB=0: recording would delete everything it writes".into());
        }
        Ok(())
    }

    /// How many segments a span of seconds covers, rounded up.
    pub fn segments_for(&self, seconds: u32) -> u32 {
        seconds.div_ceil(self.segment_s)
    }
}

impl Default for Settings {
    fn default() -> Self {
        Self::recommended_512gb()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn vars(pairs: &[(&str, &str)]) -> HashMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    #[test]
    fn recommendations_match_the_adr() {
        let s = Settings::recommended_512gb();
        assert_eq!(
            (
                s.max_age_days,
                s.max_bytes / GB,
                s.min_free_bytes / GB,
                s.protected_max_bytes / GB
            ),
            (14, 250, 50, 25)
        );
        assert_eq!((s.segment_s, s.sync_s, s.unclean_protect_min), (60, 1, 5));
        assert_eq!(
            (s.clip_before_s, s.clip_after_s, s.max_segments),
            (120, 60, 0)
        );
        let t = Settings::recommended_1tb();
        assert_eq!(
            (
                t.max_bytes / GB,
                t.min_free_bytes / GB,
                t.protected_max_bytes / GB,
                t.max_age_days
            ),
            (550, 100, 50, 14)
        );
        assert!(s.check().is_ok() && t.check().is_ok());
    }

    #[test]
    fn settings_come_from_the_defaults_file() {
        let s = Settings::from_vars(&vars(&[
            ("RECORD_MAX_AGE_DAYS", "30"),
            ("RECORD_MAX_GB", "400"),
            ("RECORD_MIN_FREE_GB", " 40 "),
            ("RECORD_SEGMENT_S", ""),
            ("RECORD_UNCLEAN_PROTECT_MIN", "0"),
        ]))
        .expect("valid");
        assert_eq!(s.max_age_days, 30);
        assert_eq!(s.max_bytes, 400 * GB);
        assert_eq!(s.min_free_bytes, 40 * GB);
        assert_eq!(s.segment_s, 60, "empty keeps the recommendation");
        assert_eq!(s.unclean_protect_min, 0, "0 turns it off");
    }

    #[test]
    fn bad_values_are_errors_that_name_the_key() {
        for (k, v) in [
            ("RECORD_MAX_GB", "lots"),
            ("RECORD_MAX_GB", "-5"),
            ("RECORD_MAX_GB", "0"),
            ("RECORD_SEGMENT_S", "5"),
            ("RECORD_SYNC_S", "0"),
            ("RECORD_SYNC_S", "61"),
            ("RECORD_MAX_AGE_DAYS", "99999"),
        ] {
            let e = Settings::from_vars(&vars(&[(k, v)])).expect_err(&format!("{k}={v}"));
            assert!(e.starts_with(k), "{e}");
        }
    }

    #[test]
    fn spans_round_up_to_whole_segments() {
        let s = Settings::default();
        assert_eq!(s.segments_for(120), 2);
        assert_eq!(s.segments_for(121), 3);
        assert_eq!(s.segments_for(0), 0);
        assert_eq!(s.segments_for(5 * 60), 5);
    }
}
