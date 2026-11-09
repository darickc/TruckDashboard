//! Bounded on-disk log of every adapter line, for diagnosing the EOT/ECT
//! dropout (PROJECT_PLAN 3.5.6). Rotates through a fixed number of files,
//! so it can't fill the disk.
//!
//! The rotation carries on across gateway starts: each start opens the file
//! after the last one used, so a restart never overwrites the session before
//! it. On AGL the folder is fixed (`/var/lib/f250/traffic`), and before this
//! a boot at the desk truncated the drive's log (VERIFICATION_LOG
//! 2026-11-08). The last index used is kept in the file `current`, not taken
//! from file times: the Pi has no RTC battery, and its clock starts at a
//! stale time until NTP answers.

use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::PathBuf;

/// Holds the index of the file in use, so the next start moves past it.
const CURRENT: &str = "current";

pub struct TrafficLog {
    dir: PathBuf,
    file: Option<File>,
    written: u64,
    index: u32,
    max_bytes: u64,
    max_files: u32,
}

impl TrafficLog {
    pub fn new(dir: PathBuf) -> std::io::Result<Self> {
        std::fs::create_dir_all(&dir)?;
        let mut log = TrafficLog {
            dir,
            file: None,
            written: 0,
            index: 0,
            // 10 × 5 MB: at the truck's CAN polling (~4 MB an hour,
            // 2026-11-08) a drive stays on disk for the next 9 starts.
            max_bytes: 5 << 20,
            max_files: 10,
        };
        log.index = log.last_index();
        Ok(log)
    }

    #[cfg(test)]
    fn with_limits(mut self, max_bytes: u64, max_files: u32) -> Self {
        self.max_bytes = max_bytes;
        self.max_files = max_files;
        self.index = self.last_index();
        self
    }

    /// The index the previous start was writing, or 0 if none (or garbage):
    /// rotation then starts at file 1.
    fn last_index(&self) -> u32 {
        std::fs::read_to_string(self.dir.join(CURRENT))
            .ok()
            .and_then(|s| s.trim().parse::<u32>().ok())
            .filter(|i| (1..=self.max_files).contains(i))
            .unwrap_or(0)
    }

    /// `dir` is "TX" or "RX"; `ms` is the driver's monotonic clock.
    pub fn line(&mut self, ms: u64, dir: &str, line: &str) {
        if self.file.is_none() || self.written >= self.max_bytes {
            self.rotate();
        }
        if let Some(f) = self.file.as_mut() {
            let entry = format!("{ms:>10} {dir} {line}\n");
            if f.write_all(entry.as_bytes()).is_ok() {
                self.written += entry.len() as u64;
            }
        }
    }

    fn rotate(&mut self) {
        self.index = (self.index % self.max_files) + 1;
        let path = self.dir.join(format!("adapter-traffic.{}.log", self.index));
        self.file = OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .open(path)
            .ok();
        self.written = 0;
        // Best effort, like the log itself: without it, the next start
        // begins again at file 1.
        let _ = std::fs::write(self.dir.join(CURRENT), format!("{}\n", self.index));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn temp_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("f250-traffic-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        dir
    }

    fn read(dir: &Path, i: u32) -> String {
        std::fs::read_to_string(dir.join(format!("adapter-traffic.{i}.log"))).unwrap_or_default()
    }

    #[test]
    fn rotates_through_a_fixed_set_of_files() -> std::io::Result<()> {
        let dir = temp_dir("rotate");
        let mut log = TrafficLog::new(dir.clone())?.with_limits(100, 3);
        for i in 0..100 {
            log.line(i, "TX", "010C");
        }
        let mut files: Vec<_> = std::fs::read_dir(&dir)?
            .filter_map(Result::ok)
            .filter(|e| e.file_name() != CURRENT)
            .collect();
        files.sort_by_key(|e| e.file_name());
        assert_eq!(files.len(), 3, "never more than max_files");
        for f in &files {
            assert!(f.metadata()?.len() <= 100 + 30, "each file bounded");
        }
        std::fs::remove_dir_all(&dir)?;
        Ok(())
    }

    #[test]
    fn a_restart_keeps_the_previous_sessions_file() -> std::io::Result<()> {
        let dir = temp_dir("restart");
        {
            let mut drive = TrafficLog::new(dir.clone())?.with_limits(1000, 3);
            drive.line(1, "TX", "7DF 03 22 13 10");
        }
        let mut desk = TrafficLog::new(dir.clone())?.with_limits(1000, 3);
        desk.line(1, "TX", "7DF 02 01 0C");
        assert!(
            read(&dir, 1).contains("22 13 10"),
            "the drive's log survives"
        );
        assert!(
            read(&dir, 2).contains("01 0C"),
            "the next start writes the next file"
        );
        std::fs::remove_dir_all(&dir)?;
        Ok(())
    }

    #[test]
    fn starts_wrap_around_and_overwrite_only_the_oldest() -> std::io::Result<()> {
        let dir = temp_dir("wrap");
        for start in 0..4u64 {
            let mut log = TrafficLog::new(dir.clone())?.with_limits(1000, 3);
            log.line(start, "TX", &format!("start {start}"));
        }
        assert!(
            read(&dir, 1).contains("start 3"),
            "the 4th start reuses file 1"
        );
        assert!(read(&dir, 2).contains("start 1"));
        assert!(read(&dir, 3).contains("start 2"));
        std::fs::remove_dir_all(&dir)?;
        Ok(())
    }

    #[test]
    fn a_start_that_logs_nothing_moves_nothing() -> std::io::Result<()> {
        let dir = temp_dir("idle");
        {
            let mut drive = TrafficLog::new(dir.clone())?.with_limits(1000, 3);
            drive.line(1, "TX", "drive");
        }
        drop(TrafficLog::new(dir.clone())?.with_limits(1000, 3));
        let mut next = TrafficLog::new(dir.clone())?.with_limits(1000, 3);
        next.line(1, "TX", "next");
        assert!(read(&dir, 1).contains("drive"));
        assert!(
            read(&dir, 2).contains("next"),
            "the idle start used no file"
        );
        std::fs::remove_dir_all(&dir)?;
        Ok(())
    }

    #[test]
    fn an_unreadable_index_starts_at_file_1() -> std::io::Result<()> {
        for garbage in ["", "x\n", "0\n", "99\n"] {
            let dir = temp_dir("garbage");
            std::fs::create_dir_all(&dir)?;
            std::fs::write(dir.join(CURRENT), garbage)?;
            let mut log = TrafficLog::new(dir.clone())?.with_limits(1000, 3);
            log.line(1, "TX", "first");
            assert!(read(&dir, 1).contains("first"), "index {garbage:?}");
            assert_eq!(std::fs::read_to_string(dir.join(CURRENT))?, "1\n");
            std::fs::remove_dir_all(&dir)?;
        }
        Ok(())
    }
}
