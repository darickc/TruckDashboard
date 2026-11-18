//! Whether the wall clock can be believed: the system reports it
//! synchronized.
//!
//! Without an RTC cell a cold start's clock reads the image's build time or
//! the last shutdown's until network time arrives. The cell is fitted since
//! 2026-11-17; until it is shown to hold the time with the power cut (H20),
//! "synchronized" stays the default test, and [`plausible`] is the floor for
//! a service told to trust the clock anyway.
//! Two services need to know: camera-manager names recordings and applies
//! the age limit only on a trusted clock (ADR-0027 decision 10), and
//! power-manager follows the sun only on one (ADR-0028).
//!
//! The answer is the kernel's own "synchronized" flag, as `timedatectl`
//! reports it (`NTPSynchronized`), or systemd-timesyncd's flag file (both:
//! [`network_synchronized`]), or gps-clock's flag file once it has set or
//! confirmed the clock from a real GPS fix this boot ([`GPS_FILE`],
//! ADR-0049). On the AGL image connman keeps the time and timesyncd doesn't
//! run, so timesyncd's file never appears there [BENCH] 2026-11-10;
//! `timedatectl` answers.

use std::io::Read;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

/// systemd-timesyncd's flag file.
pub const TIMESYNC_FILE: &str = "/run/systemd/timesync/synchronized";

/// gps-clock's flag file (ADR-0049): it exists once gps-clock has set or
/// confirmed the system clock from a real, current GPS fix since boot
/// (`/run` is emptied at every boot, like timesyncd's file).
pub const GPS_FILE: &str = "/run/f250-gps-clock/synchronized";

/// 2026-01-01T00:00:00Z. A clock reading earlier than this is never
/// believed, whatever the settings: it is a board that lost its time (the
/// image's build date, 1970) or a GPS week rollover.
pub const EARLIEST_PLAUSIBLE_UNIX: u64 = 1_767_225_600;

/// Whether a wall-clock reading (seconds since 1970, UTC) could be the real
/// time: not before [`EARLIEST_PLAUSIBLE_UNIX`].
pub fn plausible(unix_s: u64) -> bool {
    unix_s >= EARLIEST_PLAUSIBLE_UNIX
}

/// How long `timedatectl` may take before the answer is "no".
pub const TIMEDATECTL_TIMEOUT: Duration = Duration::from_secs(2);

/// Whether the clock is synchronized: by network time, or from GPS by
/// gps-clock. Blocks for up to [`TIMEDATECTL_TIMEOUT`]: call it off any
/// loop that must not wait.
pub fn system_synchronized() -> bool {
    Path::new(GPS_FILE).exists() || network_synchronized()
}

/// Whether network time has synchronized the clock: the kernel's flag as
/// `timedatectl` reports it, or timesyncd's file. gps-clock asks this one,
/// so its own flag never counts as network time. Blocks like
/// [`system_synchronized`].
pub fn network_synchronized() -> bool {
    Path::new(TIMESYNC_FILE).exists() || timedatectl_synchronized()
}

fn timedatectl_synchronized() -> bool {
    let Ok(mut child) = Command::new("timedatectl")
        .args(["show", "--property=NTPSynchronized", "--value"])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    else {
        return false;
    };
    let deadline = Instant::now() + TIMEDATECTL_TIMEOUT;
    loop {
        match child.try_wait() {
            Ok(Some(status)) if status.success() => {
                let mut out = String::new();
                if let Some(mut so) = child.stdout.take() {
                    let _ = so.read_to_string(&mut out);
                }
                return is_yes(&out);
            }
            Ok(Some(_)) | Err(_) => return false,
            Ok(None) if Instant::now() >= deadline => {
                let _ = child.kill();
                let _ = child.wait();
                return false;
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(20)),
        }
    }
}

fn is_yes(out: &str) -> bool {
    out.trim() == "yes"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nothing_before_2026_is_plausible() {
        assert!(!plausible(0), "1970: a board with no time");
        assert!(
            !plausible(EARLIEST_PLAUSIBLE_UNIX - 1),
            "the last second of 2025"
        );
        assert!(plausible(EARLIEST_PLAUSIBLE_UNIX), "2026-01-01T00:00Z");
        assert!(plausible(1_794_955_798), "2026-11-17, the bench Pi's RTC");
    }

    #[test]
    fn reads_timedatectl_value() {
        assert!(is_yes("yes\n"));
        assert!(!is_yes("no\n"));
        assert!(!is_yes(""));
    }

    #[test]
    fn answers_without_hanging() {
        // On a Mac there is no timedatectl: the answer is "no", quickly.
        let start = Instant::now();
        let _ = system_synchronized();
        assert!(start.elapsed() <= TIMEDATECTL_TIMEOUT + Duration::from_millis(500));
    }
}
