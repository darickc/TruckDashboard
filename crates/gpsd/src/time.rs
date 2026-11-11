//! gpsd's timestamps: ISO 8601 in UTC, `2026-11-11T18:00:06.000Z`.

/// Milliseconds since the Unix epoch, or `None` if `s` isn't
/// `YYYY-MM-DDTHH:MM:SS[.fraction]Z`. Leap seconds (`:60`) are refused:
/// gpsd reports them as `:59` + 1 s anyway.
pub fn parse_utc_ms(s: &str) -> Option<i64> {
    let b = s.as_bytes();
    if b.len() < 20
        || b[4] != b'-'
        || b[7] != b'-'
        || b[10] != b'T'
        || b[13] != b':'
        || b[16] != b':'
    {
        return None;
    }
    let num = |r: std::ops::Range<usize>| -> Option<i64> {
        let part = s.get(r)?;
        if !part.bytes().all(|c| c.is_ascii_digit()) {
            return None;
        }
        part.parse().ok()
    };
    let (year, month, day) = (num(0..4)?, num(5..7)?, num(8..10)?);
    let (hour, minute, second) = (num(11..13)?, num(14..16)?, num(17..19)?);
    let rest = s.get(19..)?;
    let frac_ms = match rest.strip_suffix('Z')? {
        "" => 0,
        f => {
            let digits = f.strip_prefix('.')?;
            if digits.is_empty() || !digits.bytes().all(|c| c.is_ascii_digit()) {
                return None;
            }
            // Milliseconds from the first three digits, padded.
            let mut ms = 0i64;
            for i in 0..3 {
                ms = ms * 10 + digits.as_bytes().get(i).map_or(0, |c| i64::from(c - b'0'));
            }
            ms
        }
    };
    if !(1..=12).contains(&month)
        || day < 1
        || day > days_in_month(year, month)
        || hour > 23
        || minute > 59
        || second > 59
    {
        return None;
    }
    let days = days_from_civil(year, month, day);
    Some(((days * 24 + hour) * 60 + minute) * 60_000 + second * 1000 + frac_ms)
}

fn is_leap(y: i64) -> bool {
    (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
}

fn days_in_month(y: i64, m: i64) -> i64 {
    match m {
        2 if is_leap(y) => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    }
}

/// Days since 1970-01-01 (Howard Hinnant's `days_from_civil`).
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_instants() {
        assert_eq!(parse_utc_ms("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(parse_utc_ms("1970-01-01T00:00:00.000Z"), Some(0));
        // `date -u -j -f %Y-%m-%dT%H:%M:%S 2026-11-11T18:00:06 +%s` = 1794420006
        assert_eq!(
            parse_utc_ms("2026-11-11T18:00:06.000Z"),
            Some(1_794_420_006_000)
        );
        assert_eq!(
            parse_utc_ms("2026-11-11T18:00:06.25Z"),
            Some(1_794_420_006_250)
        );
        assert_eq!(
            parse_utc_ms("2024-02-29T12:00:00.123456Z"),
            Some(1_709_208_000_123)
        );
    }

    #[test]
    fn refuses_what_isnt_a_utc_timestamp() {
        for bad in [
            "",
            "2026-11-11",
            "2026-11-11T18:00:06",       // no zone
            "2026-11-11T18:00:06+01:00", // not UTC
            "2026-13-01T00:00:00Z",
            "2026-02-29T00:00:00Z", // not a leap year
            "2026-11-11T24:00:00Z",
            "2026-11-11T18:00:60Z",
            "2026-11-11T18:00:06.Z",
            "2026-11-11T18:00:06.x0Z",
            "2026-1a-11T18:00:06Z",
            "+026-11-11T18:00:06Z",
        ] {
            assert_eq!(parse_utc_ms(bad), None, "{bad}");
        }
    }
}
