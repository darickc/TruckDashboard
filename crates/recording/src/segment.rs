//! Segment names, and the wall time they carry only when the clock was
//! trusted (ADR-0027 decision 10).
//!
//! A segment is one file of one camera: `b00042-s000317.mkv`, or
//! `b00042-s000317-20261110T143000Z.mkv` when the clock was trusted while it
//! was recorded. The boot number and sequence always order segments by when
//! they were recorded, whatever the clock said; the wall time is only a label
//! (and the age limit's input) when it can be believed.

use std::cmp::Ordering;
use std::fmt;

/// File extension of a segment (Matroska).
pub const EXTENSION: &str = "mkv";

/// A camera's directory name: lowercase ASCII letters, 1 to 16 of them
/// (`front`, `rear`), and not `protected` (the saved clips' directory).
/// Anything else is refused, so a name can never escape its directory.
pub fn valid_camera(name: &str) -> bool {
    (1..=16).contains(&name.len())
        && name.bytes().all(|b| b.is_ascii_lowercase())
        && name != "protected"
}

/// One segment's identity.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct SegmentName {
    pub camera: String,
    /// The head unit's run that recorded it (a counter kept on the drive).
    pub boot: u32,
    /// Its place in that run, per camera, from 0.
    pub seq: u32,
    /// UTC seconds when it started, only if the clock was trusted then.
    pub wall: Option<u64>,
}

impl SegmentName {
    /// The file name, without the camera's directory.
    pub fn file_name(&self) -> String {
        match self.wall {
            Some(t) => format!(
                "b{:05}-s{:06}-{}.{EXTENSION}",
                self.boot,
                self.seq,
                format_utc(t)
            ),
            None => format!("b{:05}-s{:06}.{EXTENSION}", self.boot, self.seq),
        }
    }

    /// Parses a file name made by [`Self::file_name`]. `None` for anything
    /// else: a stray file is never taken for a recording.
    pub fn parse(camera: &str, file_name: &str) -> Option<SegmentName> {
        if !valid_camera(camera) {
            return None;
        }
        let stem = file_name.strip_suffix(&format!(".{EXTENSION}"))?;
        let rest = stem.strip_prefix('b')?;
        let (boot, rest) = rest.split_once("-s")?;
        let (seq, wall) = match rest.split_once('-') {
            Some((seq, wall)) => (seq, Some(parse_utc(wall)?)),
            None => (rest, None),
        };
        if boot.len() != 5 || seq.len() != 6 {
            return None;
        }
        Some(SegmentName {
            camera: camera.to_string(),
            boot: digits(boot)?,
            seq: digits(seq)?,
            wall,
        })
    }

    /// Recording order: by run, then sequence, then camera (front and rear
    /// segments of the same minute sit together).
    pub fn order(&self, other: &SegmentName) -> Ordering {
        (self.boot, self.seq, &self.camera).cmp(&(other.boot, other.seq, &other.camera))
    }
}

impl fmt::Display for SegmentName {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}/{}", self.camera, self.file_name())
    }
}

fn digits(s: &str) -> Option<u32> {
    if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    s.parse().ok()
}

/// `20261110T143000Z` for UTC seconds since 1970.
pub fn format_utc(t: u64) -> String {
    let days = (t / 86_400) as i64;
    let secs = t % 86_400;
    let (y, m, d) = civil_from_days(days);
    format!(
        "{y:04}{m:02}{d:02}T{:02}{:02}{:02}Z",
        secs / 3600,
        secs / 60 % 60,
        secs % 60
    )
}

/// The inverse of [`format_utc`]; `None` for anything malformed or before
/// 1970.
pub fn parse_utc(s: &str) -> Option<u64> {
    let b = s.as_bytes();
    if b.len() != 16 || b[8] != b'T' || b[15] != b'Z' {
        return None;
    }
    let num = |r: std::ops::Range<usize>| -> Option<u32> { digits(s.get(r)?) };
    let (y, mo, d) = (num(0..4)?, num(4..6)?, num(6..8)?);
    let (h, mi, se) = (num(9..11)?, num(11..13)?, num(13..15)?);
    if !(1..=12).contains(&mo) || d == 0 || d > days_in_month(y, mo) || h > 23 || mi > 59 || se > 59
    {
        return None;
    }
    let days = days_from_civil(y as i64, mo, d);
    if days < 0 {
        return None;
    }
    Some(days as u64 * 86_400 + u64::from(h) * 3600 + u64::from(mi) * 60 + u64::from(se))
}

fn is_leap(y: u32) -> bool {
    (y.is_multiple_of(4) && !y.is_multiple_of(100)) || y.is_multiple_of(400)
}

fn days_in_month(y: u32, m: u32) -> u32 {
    match m {
        2 if is_leap(y) => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    }
}

// Howard Hinnant's civil-date algorithms (public domain).
fn days_from_civil(y: i64, m: u32, d: u32) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (i64::from(m) + 9) % 12;
    let doy = (153 * mp + 2) / 5 + i64::from(d) - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if m <= 2 { y + 1 } else { y }, m, d)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn utc_round_trips_known_dates() {
        // Reference values from `date -u -d @<t> +%Y%m%dT%H%M%SZ`.
        for (t, s) in [
            (0, "19700101T000000Z"),
            (951_782_400, "20000229T000000Z"),
            (1_762_785_000, "20251110T143000Z"),
            (1_794_321_000, "20261110T143000Z"),
            (4_102_444_799, "20991231T235959Z"),
        ] {
            assert_eq!(format_utc(t), s, "{t}");
            assert_eq!(parse_utc(s), Some(t), "{s}");
        }
    }

    #[test]
    fn utc_refuses_nonsense() {
        for s in [
            "20261310T000000Z",
            "20260230T000000Z",
            "20250229T000000Z",
            "20261110T240000Z",
            "20261110 143000Z",
            "2026111T143000Z",
            "20261110T143000",
            "2026111xT143000Z",
        ] {
            assert_eq!(parse_utc(s), None, "{s}");
        }
    }

    #[test]
    fn names_round_trip_with_and_without_a_trusted_time() {
        let mut n = SegmentName {
            camera: "front".into(),
            boot: 42,
            seq: 317,
            wall: None,
        };
        assert_eq!(n.file_name(), "b00042-s000317.mkv");
        assert_eq!(SegmentName::parse("front", &n.file_name()), Some(n.clone()));
        n.wall = Some(1_794_321_000);
        assert_eq!(n.file_name(), "b00042-s000317-20261110T143000Z.mkv");
        assert_eq!(SegmentName::parse("front", &n.file_name()), Some(n.clone()));
        assert_eq!(n.to_string(), "front/b00042-s000317-20261110T143000Z.mkv");
    }

    #[test]
    fn stray_files_are_not_segments() {
        for f in [
            "b00042-s000317.mp4",
            "b42-s317.mkv",
            "b00042-s000317-.mkv",
            "b00042-s000317-garbage.mkv",
            "x00042-s000317.mkv",
            "b0004a-s000317.mkv",
            ".b00042-s000317.mkv.part",
            "notes.txt",
        ] {
            assert_eq!(SegmentName::parse("rear", f), None, "{f}");
        }
        assert_eq!(SegmentName::parse("../x", "b00042-s000317.mkv"), None);
        assert_eq!(SegmentName::parse("Rear", "b00042-s000317.mkv"), None);
        assert_eq!(SegmentName::parse("protected", "b00042-s000317.mkv"), None);
    }

    #[test]
    fn order_is_run_then_sequence_whatever_the_clock_said() {
        let a = SegmentName {
            camera: "rear".into(),
            boot: 1,
            seq: 9,
            wall: Some(2_000_000_000),
        };
        let b = SegmentName {
            camera: "front".into(),
            boot: 2,
            seq: 0,
            wall: Some(1_000_000_000),
        };
        assert_eq!(
            a.order(&b),
            Ordering::Less,
            "a later run is later, even with an older clock"
        );
        let f = SegmentName {
            camera: "front".into(),
            boot: 2,
            seq: 0,
            wall: None,
        };
        let r = SegmentName {
            camera: "rear".into(),
            boot: 2,
            seq: 0,
            wall: None,
        };
        assert_eq!(f.order(&r), Ordering::Less);
    }
}
