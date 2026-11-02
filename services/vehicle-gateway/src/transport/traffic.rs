//! Bounded on-disk log of every adapter line, for diagnosing the EOT/ECT
//! dropout (PROJECT_PLAN 3.5.6). Rotates through a fixed number of files,
//! so it can't fill the disk.

use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::PathBuf;

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
        Ok(TrafficLog {
            dir,
            file: None,
            written: 0,
            index: 0,
            max_bytes: 10 << 20,
            max_files: 5,
        })
    }

    #[cfg(test)]
    fn with_limits(mut self, max_bytes: u64, max_files: u32) -> Self {
        self.max_bytes = max_bytes;
        self.max_files = max_files;
        self
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
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rotates_through_a_fixed_set_of_files() -> std::io::Result<()> {
        let dir = std::env::temp_dir().join(format!("f250-traffic-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let mut log = TrafficLog::new(dir.clone())?.with_limits(100, 3);
        for i in 0..100 {
            log.line(i, "TX", "010C");
        }
        let mut files: Vec<_> = std::fs::read_dir(&dir)?.filter_map(Result::ok).collect();
        files.sort_by_key(|e| e.file_name());
        assert_eq!(files.len(), 3, "never more than max_files");
        for f in &files {
            assert!(f.metadata()?.len() <= 100 + 30, "each file bounded");
        }
        std::fs::remove_dir_all(&dir)?;
        Ok(())
    }
}
