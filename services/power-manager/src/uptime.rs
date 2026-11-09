//! Time since the kernel booted, which the boot window is measured from.
//!
//! The supply's ON pulse comes relative to power-on, not to this service's
//! start, and a restarted service must not reopen the window. So on Linux
//! this reads `/proc/uptime` (`CLOCK_BOOTTIME`). Elsewhere (a dev Mac) it
//! falls back to the time since the process started.

use std::sync::OnceLock;
use std::time::{Duration, Instant};

/// The first field of `/proc/uptime`: seconds since boot, with a fraction.
pub fn parse_proc_uptime(text: &str) -> Option<Duration> {
    let secs: f64 = text.split_whitespace().next()?.parse().ok()?;
    (secs.is_finite() && secs >= 0.0).then(|| Duration::from_secs_f64(secs))
}

/// Time since boot: `/proc/uptime` if it can be read, else since this
/// process first asked.
pub fn since_boot() -> Duration {
    static START: OnceLock<Instant> = OnceLock::new();
    let start = *START.get_or_init(Instant::now);
    std::fs::read_to_string("/proc/uptime")
        .ok()
        .and_then(|t| parse_proc_uptime(&t))
        .unwrap_or_else(|| start.elapsed())
}

/// Whether [`since_boot`] measures from the kernel's boot.
pub fn from_kernel() -> bool {
    std::fs::read_to_string("/proc/uptime")
        .ok()
        .and_then(|t| parse_proc_uptime(&t))
        .is_some()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_proc_uptime() {
        assert_eq!(
            parse_proc_uptime("12.34 40.01\n"),
            Some(Duration::from_secs_f64(12.34))
        );
        assert_eq!(
            parse_proc_uptime("3600.00 1.00"),
            Some(Duration::from_secs(3600))
        );
    }

    #[test]
    fn rejects_bad_uptime() {
        assert_eq!(parse_proc_uptime(""), None);
        assert_eq!(parse_proc_uptime("abc 1"), None);
        assert_eq!(parse_proc_uptime("-1 1"), None);
        assert_eq!(parse_proc_uptime("inf 1"), None);
    }

    #[test]
    fn since_boot_moves_forward() {
        let a = since_boot();
        let b = since_boot();
        assert!(b >= a);
    }
}
