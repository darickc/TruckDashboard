//! The recordings on the data drive (ADR-0027 decisions 6, 8 and 10):
//!
//! ```text
//! <root>/<camera>/b00042-s000317-20261110T143000Z.mkv   recordings
//! <root>/protected/<camera>/...                          saved clips
//! <root>/.state/boot                                     the last run's number
//! <root>/.state/clean-stop                               written at a clean stop
//! ```
//!
//! `<root>` is `/var/lib/f250/storage/video`, on the data drive only; the
//! caller checks the drive is mounted. Files that aren't segments are
//! reported and never touched. State files are replaced atomically and
//! synced, so a power cut leaves the old value or the new one.

use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

use crate::retention::{Plan, Segment};
use crate::segment::{SegmentName, valid_camera};

pub const PROTECTED_DIR: &str = "protected";
const STATE_DIR: &str = ".state";
/// Boot numbers are five digits in file names.
pub const MAX_BOOT: u32 = 99_999;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunStart {
    /// This run's number.
    pub boot: u32,
    /// The run before, if there was one.
    pub previous: Option<Previous>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Previous {
    pub boot: u32,
    /// It left a clean-stop marker: its segments were finished.
    pub clean: bool,
}

#[derive(Debug, Default)]
pub struct Scan {
    pub segments: Vec<Segment>,
    /// Files and directories that aren't segments: reported, left alone.
    pub ignored: Vec<PathBuf>,
}

impl Scan {
    pub fn protected_bytes(&self) -> u64 {
        self.segments
            .iter()
            .filter(|g| g.protected)
            .map(|g| g.bytes)
            .sum()
    }
}

#[derive(Debug, Clone)]
pub struct Store {
    root: PathBuf,
}

impl Store {
    pub fn open(root: impl Into<PathBuf>) -> io::Result<Store> {
        let root = root.into();
        fs::create_dir_all(root.join(STATE_DIR))?;
        fs::create_dir_all(root.join(PROTECTED_DIR))?;
        Ok(Store { root })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    /// Where a camera's new segments go (created if missing).
    pub fn camera_dir(&self, camera: &str) -> io::Result<PathBuf> {
        let dir = self.root.join(checked(camera)?);
        fs::create_dir_all(&dir)?;
        Ok(dir)
    }

    pub fn path(&self, name: &SegmentName, protected: bool) -> PathBuf {
        let base = if protected {
            self.root.join(PROTECTED_DIR)
        } else {
            self.root.clone()
        };
        base.join(&name.camera).join(name.file_name())
    }

    /// Starts a run: the next boot number, saved before any segment uses
    /// it, and whether the run before stopped cleanly. The clean-stop marker
    /// is consumed, so a crash in this run leaves none behind.
    pub fn start_run(&self) -> io::Result<RunStart> {
        let state = self.root.join(STATE_DIR);
        let last = read_number(&state.join("boot"))?;
        let boot = last.map_or(1, |b| b + 1);
        if boot > MAX_BOOT {
            return Err(io::Error::other(format!(
                "boot number {boot} doesn't fit in a segment name (max {MAX_BOOT})"
            )));
        }
        let marker = state.join("clean-stop");
        let clean_boot = read_number(&marker)?;
        write_atomic(&state.join("boot"), &format!("{boot}\n"))?;
        match fs::remove_file(&marker) {
            Ok(()) => sync_dir(&state)?,
            Err(e) if e.kind() == io::ErrorKind::NotFound => {}
            Err(e) => return Err(e),
        }
        Ok(RunStart {
            boot,
            previous: last.map(|b| Previous {
                boot: b,
                clean: clean_boot == Some(b),
            }),
        })
    }

    /// Records that run `boot` finished its segments. Called last, after
    /// every pipeline has finished at shutdown.
    pub fn mark_clean_stop(&self, boot: u32) -> io::Result<()> {
        write_atomic(
            &self.root.join(STATE_DIR).join("clean-stop"),
            &format!("{boot}\n"),
        )
    }

    /// Every segment, recorded and protected.
    pub fn scan(&self) -> io::Result<Scan> {
        let mut scan = Scan::default();
        self.scan_dir(&self.root, false, &mut scan)?;
        self.scan_dir(&self.root.join(PROTECTED_DIR), true, &mut scan)?;
        Ok(scan)
    }

    fn scan_dir(&self, dir: &Path, protected: bool, scan: &mut Scan) -> io::Result<()> {
        for entry in fs::read_dir(dir)? {
            let entry = entry?;
            let name = entry.file_name();
            let name = name.to_string_lossy();
            if name == STATE_DIR || (!protected && name == PROTECTED_DIR) {
                continue;
            }
            if !entry.file_type()?.is_dir() || !valid_camera(&name) {
                scan.ignored.push(entry.path());
                continue;
            }
            for file in fs::read_dir(entry.path())? {
                let file = file?;
                let meta = file.metadata()?;
                match SegmentName::parse(&name, &file.file_name().to_string_lossy()) {
                    Some(seg) if meta.is_file() => scan.segments.push(Segment {
                        name: seg,
                        bytes: meta.len(),
                        protected,
                    }),
                    _ => scan.ignored.push(file.path()),
                }
            }
        }
        Ok(())
    }

    /// Deletes a recording (never a protected clip).
    pub fn delete(&self, name: &SegmentName) -> io::Result<()> {
        fs::remove_file(self.path(name, false))
    }

    /// Moves a finished recording into `protected/`. Same filesystem, so
    /// the move is a rename: the clip is never half-copied.
    pub fn protect(&self, name: &SegmentName) -> io::Result<()> {
        let to = self.path(name, true);
        let dir = to.parent().unwrap_or(&self.root).to_path_buf();
        fs::create_dir_all(&dir)?;
        fs::rename(self.path(name, false), &to)?;
        sync_dir(&dir)?;
        sync_dir(&self.root.join(&name.camera))
    }

    /// Carries out a retention plan. Returns the deletions that failed; a
    /// segment already gone counts as deleted.
    pub fn apply(&self, plan: &Plan) -> Vec<(SegmentName, io::Error)> {
        let mut failed = Vec::new();
        for (name, _) in &plan.delete {
            match self.delete(name) {
                Ok(()) => {}
                Err(e) if e.kind() == io::ErrorKind::NotFound => {}
                Err(e) => failed.push((name.clone(), e)),
            }
        }
        failed
    }
}

fn checked(camera: &str) -> io::Result<&str> {
    if valid_camera(camera) {
        Ok(camera)
    } else {
        Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("bad camera name {camera:?}"),
        ))
    }
}

fn read_number(path: &Path) -> io::Result<Option<u32>> {
    match fs::read_to_string(path) {
        Ok(s) => s.trim().parse().map(Some).map_err(|_| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                format!("{}: not a number: {:?}", path.display(), s.trim()),
            )
        }),
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e),
    }
}

/// Write, sync, rename over, sync the directory.
fn write_atomic(path: &Path, contents: &str) -> io::Result<()> {
    let tmp = path.with_extension("new");
    {
        let mut f = fs::File::create(&tmp)?;
        f.write_all(contents.as_bytes())?;
        f.sync_all()?;
    }
    fs::rename(&tmp, path)?;
    sync_dir(path.parent().unwrap_or(Path::new(".")))
}

fn sync_dir(dir: &Path) -> io::Result<()> {
    fs::File::open(dir)?.sync_all()
}
