//! The recordings on the data drive (ADR-0027 decisions 6–8 and 10): one
//! thread owns `crates/recording`'s store, so retention, saved clips and the
//! run counter never race each other, and the control loop never waits on
//! the drive.
//!
//! The loop sends [`Job`]s; the thread publishes a [`DriveStatus`] after
//! each. What it does:
//!
//! - **The drive.** Nothing is written unless the data drive is mounted
//!   (`--record-drive`, decision 6). The first time it is, the store opens,
//!   the run counter goes up, and if the run before stopped uncleanly its
//!   last minutes are protected (decision 8) before any retention.
//! - **Retention** on each [`Job::Pass`]: as each segment starts and once a
//!   minute (decision 7). The segments being written are never deleted,
//!   nor the newest segment of each camera in this run (one that opened
//!   after the loop's snapshot).
//! - **Save clip** (decision 8): the finished segments before the current
//!   one move at once; the current one and the ones after it move as each
//!   finishes ([`Job::Finished`]), the cap checked again each time.
//! - **The clean-stop marker**, last, at a clean shutdown.

use std::collections::HashMap;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use f250_proto::camera::v1 as pb;
use recording::protect::{self, ClipError};
use recording::retention::{self, Drive, Problem, Reason};
use recording::segment::SegmentName;
use recording::settings::Settings as RecordSettings;
use recording::store::Store;
use tokio::sync::{oneshot, watch};

const GB: f64 = 1_000_000_000.0;

/// Whether the wall clock can be believed (ADR-0027 decision 10).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Clock {
    /// Trusted while this file exists: systemd-timesyncd creates
    /// `/run/systemd/timesync/synchronized` once NTP has answered. Whether
    /// the AGL image runs timesyncd is UNVERIFIED; without it the clock is
    /// never trusted, which is the safe side. The RTC (H20) isn't fitted.
    SyncFile(PathBuf),
    /// Development and tests.
    Trusted,
    Untrusted,
}

pub const TIMESYNC_FILE: &str = "/run/systemd/timesync/synchronized";

impl Clock {
    pub fn is_trusted(&self) -> bool {
        match self {
            Clock::SyncFile(p) => p.exists(),
            Clock::Trusted => true,
            Clock::Untrusted => false,
        }
    }

    /// UTC seconds, only while the clock is trusted.
    pub fn trusted_now(&self) -> Option<u64> {
        if !self.is_trusted() {
            return None;
        }
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .ok()
            .map(|d| d.as_secs())
    }
}

#[derive(Debug, Clone)]
pub struct DriveConfig {
    /// Where recordings go: `/var/lib/f250/storage/video`.
    pub root: PathBuf,
    /// The data drive's mount point, which must be mounted before anything
    /// is written (`/var/lib/f250/storage`). `None`: not checked
    /// (development and tests only; logged at startup).
    pub mount: Option<PathBuf>,
    /// The cameras that record (directory names: `front`, `rear`).
    pub cameras: Vec<String>,
    pub settings: RecordSettings,
    pub clock: Clock,
}

/// What the thread knows, after each job.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct DriveStatus {
    /// The store is open and this run has its number: segments can be
    /// written.
    pub ready: bool,
    /// This run's number, once ready.
    pub boot: Option<u32>,
    /// Why nothing can be written, when not ready (or the drive went away).
    pub why_not: Option<String>,
    pub mounted: bool,
    pub free_bytes: u64,
    pub recorded_bytes: u64,
    pub protected_bytes: u64,
    pub protected_max_bytes: u64,
    /// Segments still to move into a saved clip as they finish.
    pub clip_pending: u32,
    /// Below the free-space minimum with nothing left to delete: recording
    /// must stop (decision 7).
    pub drive_full: bool,
    /// For the driver: the drive is full, or a saved clip or the unclean
    /// stop's minutes didn't fit.
    pub problem: Option<String>,
}

pub enum Job {
    /// Check the drive (open the store the first time it is there), then
    /// run retention. `writing`: the segments being recorded now.
    Pass { writing: Vec<SegmentName> },
    /// A segment finished: protect it if a saved clip is waiting for it.
    Finished(SegmentName),
    SaveClip {
        writing: Vec<SegmentName>,
        reply: oneshot::Sender<pb::SaveClipResponse>,
    },
    /// Write the clean-stop marker. Sent last at a clean shutdown.
    CleanStop { reply: oneshot::Sender<()> },
}

/// Starts the thread. It stops when every [`Job`] sender is gone.
pub fn spawn(
    cfg: DriveConfig,
) -> (
    tokio::sync::mpsc::Sender<Job>,
    watch::Receiver<DriveStatus>,
    std::thread::JoinHandle<()>,
) {
    let (tx, mut rx) = tokio::sync::mpsc::channel(64);
    let (status_tx, status_rx) = watch::channel(DriveStatus {
        protected_max_bytes: cfg.settings.protected_max_bytes,
        why_not: Some("checking the data drive".into()),
        ..Default::default()
    });
    let handle = std::thread::Builder::new()
        .name("camera-drive".into())
        .spawn(move || {
            let mut w = Worker::new(cfg);
            while let Some(job) = rx.blocking_recv() {
                w.job(job);
                let next = w.status.clone();
                status_tx.send_if_modified(|s| {
                    if *s == next {
                        false
                    } else {
                        *s = next;
                        true
                    }
                });
            }
        })
        .expect("spawn the drive thread");
    (tx, status_rx, handle)
}

/// A saved clip's segments still to come, for one camera.
#[derive(Debug, Clone, Copy)]
struct Pending {
    /// The first segment it takes (the one being written at the save).
    boot: u32,
    from_seq: u32,
    count: u32,
}

struct Worker {
    cfg: DriveConfig,
    store: Option<Store>,
    status: DriveStatus,
    /// Per camera: segments still to protect as they finish.
    pending: HashMap<String, Pending>,
    /// A problem that stays until it is cleared (unclean-stop minutes that
    /// didn't fit, a cut-short saved clip). The drive-full problem is
    /// worked out on each pass.
    sticky: Option<String>,
}

impl Worker {
    fn new(cfg: DriveConfig) -> Self {
        let status = DriveStatus {
            protected_max_bytes: cfg.settings.protected_max_bytes,
            ..Default::default()
        };
        Worker {
            cfg,
            store: None,
            status,
            pending: HashMap::new(),
            sticky: None,
        }
    }

    fn job(&mut self, job: Job) {
        match job {
            Job::Pass { writing } => self.pass(&writing),
            Job::Finished(name) => self.finished(&name),
            Job::SaveClip { writing, reply } => {
                let r = self.save_clip(&writing);
                let _ = reply.send(r);
            }
            Job::CleanStop { reply } => {
                if let (Some(store), Some(boot)) = (&self.store, self.status.boot) {
                    match store.mark_clean_stop(boot) {
                        Ok(()) => eprintln!("[camera] recording: run {boot} stopped cleanly"),
                        Err(e) => {
                            eprintln!("[camera] recording: clean-stop marker not written: {e}")
                        }
                    }
                }
                let _ = reply.send(());
            }
        }
        self.status.clip_pending = self.pending.values().map(|p| p.count).sum();
        self.status.problem = if self.status.drive_full {
            Some(format!(
                "The data drive is full ({:.1} GB free, {:.1} GB must stay free) and only saved clips \
                 are left: not recording",
                self.status.free_bytes as f64 / GB,
                self.cfg.settings.min_free_bytes as f64 / GB
            ))
        } else {
            self.sticky.clone()
        };
    }

    /// Opens the store the first time the drive is there.
    fn ensure_store(&mut self) -> bool {
        self.status.mounted = match &self.cfg.mount {
            None => true,
            Some(m) => is_mounted(m),
        };
        if !self.status.mounted {
            let m = self.cfg.mount.as_deref().unwrap_or(Path::new("?"));
            if self.status.ready {
                eprintln!(
                    "[camera] recording: the data drive at {} went away",
                    m.display()
                );
            }
            self.status.ready = false;
            self.status.why_not = Some(format!("no data drive mounted at {}", m.display()));
            return false;
        }
        if self.store.is_some() {
            self.status.ready = true;
            self.status.why_not = None;
            return true;
        }
        match self.open_store() {
            Ok(()) => {
                self.status.ready = true;
                self.status.why_not = None;
                true
            }
            Err(e) => {
                eprintln!("[camera] recording: {e}");
                self.status.ready = false;
                self.status.why_not = Some(e);
                false
            }
        }
    }

    fn open_store(&mut self) -> Result<(), String> {
        let root = &self.cfg.root;
        let store = Store::open(root).map_err(|e| format!("can't open {}: {e}", root.display()))?;
        for c in &self.cfg.cameras {
            store
                .camera_dir(c)
                .map_err(|e| format!("can't make {}/{c}: {e}", root.display()))?;
        }
        let run = store
            .start_run()
            .map_err(|e| format!("can't start a run in {}: {e}", root.display()))?;
        eprintln!(
            "[camera] recording: run {} on {} (clock {})",
            run.boot,
            root.display(),
            if self.cfg.clock.is_trusted() {
                "trusted"
            } else {
                "not trusted: segment names carry no time"
            }
        );
        if let Some(prev) = run.previous.filter(|p| !p.clean) {
            self.protect_unclean(&store, prev.boot);
        }
        self.status.boot = Some(run.boot);
        self.store = Some(store);
        Ok(())
    }

    /// ADR-0027 decision 8: the minutes before an unclean stop.
    fn protect_unclean(&mut self, store: &Store, previous: u32) {
        let scan = match store.scan() {
            Ok(s) => s,
            Err(e) => {
                eprintln!("[camera] recording: scan after an unclean stop failed: {e}");
                return;
            }
        };
        let plan = protect::after_unclean_stop(
            &scan.segments,
            previous,
            scan.protected_bytes(),
            &self.cfg.settings,
        );
        let mut done = 0;
        for name in &plan.protect {
            match store.protect(name) {
                Ok(()) => done += 1,
                Err(e) => eprintln!("[camera] recording: couldn't protect {name}: {e}"),
            }
        }
        eprintln!(
            "[camera] recording: run {previous} stopped uncleanly: protected its last {done} segments"
        );
        if !plan.skipped.is_empty() {
            let msg = format!(
                "{} segments from before the last unclean stop weren't saved: saved clips are full",
                plan.skipped.len()
            );
            eprintln!("[camera] recording: {msg}");
            self.sticky = Some(msg);
        }
    }

    fn pass(&mut self, writing: &[SegmentName]) {
        if !self.ensure_store() {
            return;
        }
        let Some(store) = &self.store else { return };
        let scan = match store.scan() {
            Ok(s) => s,
            Err(e) => {
                eprintln!("[camera] recording: scan failed: {e}");
                return;
            }
        };
        let free = free_bytes(store.root()).unwrap_or(0);
        let mut keep: Vec<SegmentName> = writing.to_vec();
        // The newest segment of each camera in this run: it may have opened
        // after the loop's snapshot of what is being written.
        if let Some(boot) = self.status.boot {
            let mut newest: HashMap<&str, &SegmentName> = HashMap::new();
            for g in scan
                .segments
                .iter()
                .filter(|g| !g.protected && g.name.boot == boot)
            {
                let e = newest.entry(g.name.camera.as_str()).or_insert(&g.name);
                if g.name.seq > e.seq {
                    *e = &g.name;
                }
            }
            keep.extend(newest.into_values().cloned());
        }
        let plan = retention::plan(
            &scan.segments,
            &keep,
            Drive { free_bytes: free },
            self.cfg.clock.trusted_now(),
            &self.cfg.settings,
        );
        let failed = store.apply(&plan);
        if !plan.delete.is_empty() {
            let count = |r: Reason| plan.delete.iter().filter(|(_, x)| *x == r).count();
            eprintln!(
                "[camera] recording: deleted {} segments (age {}, count {}, size {}, free space {}){}",
                plan.delete.len() - failed.len(),
                count(Reason::Age),
                count(Reason::Count),
                count(Reason::Size),
                count(Reason::FreeSpace),
                if failed.is_empty() {
                    String::new()
                } else {
                    format!("; {} failed", failed.len())
                }
            );
        }
        for (name, e) in &failed {
            eprintln!("[camera] recording: couldn't delete {name}: {e}");
        }
        let full = matches!(plan.problem, Some(Problem::DriveFull { .. }));
        if full && !self.status.drive_full {
            eprintln!(
                "[camera] recording: the drive is full with nothing left to delete: stopping"
            );
        }
        self.status.drive_full = full;
        self.status.free_bytes = plan.free_bytes_after;
        self.status.recorded_bytes = plan.recording_bytes_after;
        self.status.protected_bytes = scan.protected_bytes();
    }

    fn finished(&mut self, name: &SegmentName) {
        let Some(store) = &self.store else { return };
        // Only segments from the one being written at the save on: an
        // older one finishing late was already in the clip, or before it.
        let Some(p) = self
            .pending
            .get_mut(&name.camera)
            .filter(|p| p.count > 0 && name.boot == p.boot && name.seq >= p.from_seq)
        else {
            return;
        };
        p.count -= 1;
        let n = &mut p.count;
        let bytes = std::fs::metadata(store.path(name, false))
            .map(|m| m.len())
            .unwrap_or(0);
        if !protect::fits(self.status.protected_bytes, bytes, &self.cfg.settings) {
            *n = 0;
            let msg = format!(
                "The saved clip was cut short at {name}: saved clips are full ({:.1} of {:.1} GB)",
                self.status.protected_bytes as f64 / GB,
                self.cfg.settings.protected_max_bytes as f64 / GB
            );
            eprintln!("[camera] recording: {msg}");
            self.sticky = Some(msg);
            return;
        }
        match store.protect(name) {
            Ok(()) => {
                self.status.protected_bytes += bytes;
                self.status.recorded_bytes = self.status.recorded_bytes.saturating_sub(bytes);
                eprintln!("[camera] recording: saved {name} into the clip");
            }
            Err(e) => eprintln!("[camera] recording: couldn't save {name}: {e}"),
        }
    }

    fn save_clip(&mut self, writing: &[SegmentName]) -> pb::SaveClipResponse {
        let refuse = |detail: String| pb::SaveClipResponse {
            saved: false,
            detail,
            ..Default::default()
        };
        let Some(store) = &self.store else {
            return refuse(format!(
                "Not saved: nothing is recording ({})",
                self.status.why_not.as_deref().unwrap_or("no data drive")
            ));
        };
        let scan = match store.scan() {
            Ok(s) => s,
            Err(e) => return refuse(format!("Not saved: can't read the recordings: {e}")),
        };
        let protected = scan.protected_bytes();
        let plan = match protect::save_clip(&scan.segments, writing, protected, &self.cfg.settings)
        {
            Ok(p) => p,
            Err(ClipError::NotRecording) => {
                return refuse(
                    "Not saved: nothing is recording, so there is nothing to save".into(),
                );
            }
            Err(ClipError::CapFull {
                need_bytes,
                free_bytes,
            }) => {
                return refuse(format!(
                    "Not saved: saved clips are full. This clip needs about {:.1} GB and {:.1} GB of \
                     {:.1} GB is left. Older saved clips are never deleted for a new one",
                    need_bytes as f64 / GB,
                    free_bytes as f64 / GB,
                    self.cfg.settings.protected_max_bytes as f64 / GB
                ));
            }
        };
        let mut moved = 0u32;
        let mut moved_bytes = 0u64;
        for name in &plan.protect_now {
            let bytes = std::fs::metadata(store.path(name, false))
                .map(|m| m.len())
                .unwrap_or(0);
            match store.protect(name) {
                Ok(()) => {
                    moved += 1;
                    moved_bytes += bytes;
                }
                Err(e) => eprintln!("[camera] recording: couldn't save {name}: {e}"),
            }
        }
        let mut to_come = 0;
        for (camera, n) in &plan.protect_next {
            let Some(current) = writing.iter().find(|w| &w.camera == camera) else {
                continue;
            };
            let p = self.pending.entry(camera.clone()).or_insert(Pending {
                boot: current.boot,
                from_seq: current.seq,
                count: 0,
            });
            if p.count == 0 || p.boot != current.boot {
                *p = Pending {
                    boot: current.boot,
                    from_seq: current.seq,
                    count: *n,
                };
            } else {
                // A second press extends the clip; it never adds twice.
                let end = (p.from_seq + p.count).max(current.seq + n);
                p.count = end - p.from_seq;
            }
            to_come += p.count;
        }
        self.status.protected_bytes = protected + moved_bytes;
        eprintln!(
            "[camera] recording: clip saved: {moved} segments now, {to_come} more as they finish"
        );
        pb::SaveClipResponse {
            saved: true,
            detail: format!(
                "Clip saved: {moved} finished segments now, {to_come} more as they finish. \
                 Retention never deletes it"
            ),
            segments_protected: moved,
            segments_to_come: to_come,
        }
    }
}

/// A mount point is mounted when it sits on a different device from its
/// parent directory.
pub fn is_mounted(path: &Path) -> bool {
    let Ok(me) = std::fs::metadata(path) else {
        return false;
    };
    let parent = path.parent().unwrap_or(Path::new("/"));
    match std::fs::metadata(parent) {
        Ok(p) => me.dev() != p.dev() || me.ino() == p.ino(),
        Err(_) => false,
    }
}

fn free_bytes(path: &Path) -> Option<u64> {
    let s = rustix::fs::statvfs(path).ok()?;
    Some(s.f_bavail.saturating_mul(s.f_frsize))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_root_directory_counts_as_mounted_and_a_plain_directory_does_not() {
        assert!(is_mounted(Path::new("/")));
        let dir = std::env::temp_dir().join(format!("f250-drive-mount-{}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("dir");
        assert!(!is_mounted(&dir));
        assert!(!is_mounted(&dir.join("missing")));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn an_untrusted_clock_gives_no_time() {
        assert_eq!(Clock::Untrusted.trusted_now(), None);
        assert!(Clock::Trusted.trusted_now().is_some());
        assert_eq!(
            Clock::SyncFile("/nonexistent/f250/synchronized".into()).trusted_now(),
            None
        );
    }
}
