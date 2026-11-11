//! Whether the wall clock can be believed: the system reports it
//! synchronized.
//!
//! The Pi 5 has no RTC cell yet (H20), so after a cold start its clock reads
//! the image's build time or the last shutdown's until network time arrives.
//! Two services need to know: camera-manager names recordings and applies
//! the age limit only on a trusted clock (ADR-0027 decision 10), and
//! power-manager follows the sun only on one (ADR-0028).
//!
//! The answer is the kernel's own "synchronized" flag, as `timedatectl`
//! reports it (`NTPSynchronized`), or systemd-timesyncd's flag file. On the
//! AGL image connman keeps the time and timesyncd doesn't run, so the file
//! never appears there [BENCH] 2026-11-10; `timedatectl` answers.

use std::io::Read;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

/// systemd-timesyncd's flag file.
pub const TIMESYNC_FILE: &str = "/run/systemd/timesync/synchronized";

/// How long `timedatectl` may take before the answer is "no".
pub const TIMEDATECTL_TIMEOUT: Duration = Duration::from_secs(2);

/// Whether the system reports the clock synchronized. Blocks for up to
/// [`TIMEDATECTL_TIMEOUT`]: call it off any loop that must not wait.
pub fn system_synchronized() -> bool {
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
