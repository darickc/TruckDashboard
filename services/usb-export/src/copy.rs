//! Copying recordings to a mounted stick (ADR-0037 decision 4): which files,
//! where they go, whether they fit, and the copy itself. Copy only: the
//! data drive is opened for reading and nothing on it is changed.
//!
//! Each file is written as `<name>.part`, flushed, then renamed to its
//! name, so a file with its real name on the stick is always complete. A
//! file already on the stick with the same size is skipped, so copying
//! again after a pulled stick or a full one finishes the job.

use std::collections::BTreeSet;
use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use recording::retention::Segment;
use recording::store::PROTECTED_DIR;

/// The folder on the stick the recordings go to.
pub const FOLDER: &str = "F250-recordings";
/// Left free on the stick after the copy, for its own bookkeeping.
pub const SPARE_BYTES: u64 = 16 << 20;
const CHUNK: usize = 1 << 20;
/// How often progress is reported while a file copies.
const PROGRESS_EVERY: Duration = Duration::from_millis(250);

/// A recording as the client names it.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct Ref {
    pub camera: String,
    pub file_name: String,
    pub protected: bool,
}

/// A recording found on the drive, to be copied.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Item {
    pub r: Ref,
    pub bytes: u64,
    /// Recording order, for copying oldest first.
    order: (u32, u32),
}

impl Item {
    /// `camera/file_name`, for the screen and the log.
    pub fn label(&self) -> String {
        if self.r.protected {
            format!("{PROTECTED_DIR}/{}/{}", self.r.camera, self.r.file_name)
        } else {
            format!("{}/{}", self.r.camera, self.r.file_name)
        }
    }

    /// Where it lives under the recordings' root.
    pub fn source(&self, root: &Path, protected: bool) -> PathBuf {
        let base = if protected {
            root.join(PROTECTED_DIR)
        } else {
            root.to_path_buf()
        };
        base.join(&self.r.camera).join(&self.r.file_name)
    }

    /// Where it goes on the stick, under the stick's mount point: the
    /// drive's own layout, inside [`FOLDER`].
    pub fn dest(&self, stick: &Path) -> PathBuf {
        self.source(&stick.join(FOLDER), self.r.protected)
    }
}

/// Finds each requested recording in a scan of the drive. Unknown ones and
/// ones still being written are refused by name; duplicates count once.
/// The result is in recording order.
pub fn resolve(
    scan: &[Segment],
    being_written: &BTreeSet<Ref>,
    refs: &[Ref],
) -> Result<Vec<Item>, String> {
    if refs.is_empty() {
        return Err("No recordings were chosen.".into());
    }
    let mut seen = BTreeSet::new();
    let mut items = Vec::new();
    for r in refs {
        if !seen.insert(r.clone()) {
            continue;
        }
        let Some(seg) = scan.iter().find(|s| {
            s.protected == r.protected
                && s.name.camera == r.camera
                && s.name.file_name() == r.file_name
        }) else {
            return Err(format!(
                "{} isn't on the data drive any more (deleted by retention, or moved by Save clip). \
                 Refresh the list.",
                r.file_name
            ));
        };
        if being_written.contains(r) {
            return Err(format!(
                "{} is still being recorded: copy it once it is finished.",
                r.file_name
            ));
        }
        items.push(Item {
            r: r.clone(),
            bytes: seg.bytes,
            order: (seg.name.boot, seg.name.seq),
        });
    }
    items.sort_by(|a, b| (a.order, &a.r.camera).cmp(&(b.order, &b.r.camera)));
    Ok(items)
}

/// Why a copy stopped.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Failure {
    /// Not enough room for what is left to copy.
    Full { need: u64, free: u64 },
    /// The stick filled up while copying.
    FilledUp,
    /// Mounted read-only, or writes refused as read-only.
    ReadOnly,
    /// A file is over the filesystem's limit (FAT: 4 GiB).
    TooBig { file: String, max: u64 },
    /// The stick went away.
    Removed,
    /// Reading the data drive failed.
    Drive(String),
    /// Anything else writing to the stick.
    Stick(String),
}

impl Failure {
    /// In words for the screen.
    pub fn message(&self) -> String {
        match self {
            Failure::Full { need, free } => format!(
                "Not enough room on the stick: the recordings need {}, {} is free.",
                size(*need),
                size(*free)
            ),
            Failure::FilledUp => "The stick is full.".into(),
            Failure::ReadOnly => {
                "The stick is read-only: check its write-protect switch, or that it isn't damaged."
                    .into()
            }
            Failure::TooBig { file, max } => format!(
                "{file} is bigger than this stick's filesystem allows ({}): use an exFAT stick.",
                size(*max)
            ),
            Failure::Removed => "The stick was removed during the copy.".into(),
            Failure::Drive(e) => format!("Reading the data drive failed: {e}"),
            Failure::Stick(e) => format!("Writing to the stick failed: {e}"),
        }
    }
}

/// `1.2 GB`, `340 MB` (decimal, as sticks are sold).
pub fn size(bytes: u64) -> String {
    let b = bytes as f64;
    if b >= 1e9 {
        format!("{:.1} GB", b / 1e9)
    } else if b >= 1e6 {
        format!("{:.0} MB", b / 1e6)
    } else {
        format!("{:.0} kB", (b / 1e3).ceil())
    }
}

/// What a write error means, given whether the stick is still there.
pub fn classify(err: &io::Error, present: bool) -> Failure {
    if !present {
        return Failure::Removed;
    }
    match err.kind() {
        io::ErrorKind::StorageFull => return Failure::FilledUp,
        io::ErrorKind::ReadOnlyFilesystem => return Failure::ReadOnly,
        _ => {}
    }
    // ENODEV, ENXIO and EIO: what a pulled stick's writes return before
    // sysfs catches up.
    match err.raw_os_error() {
        Some(5 | 6 | 19) => Failure::Removed,
        _ => Failure::Stick(err.to_string()),
    }
}

/// The plan for one stick: which items are already there.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Plan {
    pub items: Vec<Item>,
    /// Same index as `items`: already on the stick with the same size.
    pub already: Vec<bool>,
    /// Bytes still to write.
    pub to_copy: u64,
}

impl Plan {
    pub fn total_bytes(&self) -> u64 {
        self.items.iter().map(|i| i.bytes).sum()
    }
}

/// Checks the items against the stick mounted at `stick`: what's already
/// there, the file-size limit, and the room needed for the rest.
pub fn plan(
    items: Vec<Item>,
    stick: &Path,
    free_bytes: u64,
    max_file_bytes: u64,
) -> Result<Plan, Failure> {
    let mut already = Vec::with_capacity(items.len());
    let mut to_copy = 0u64;
    for item in &items {
        let there =
            fs::metadata(item.dest(stick)).is_ok_and(|m| m.is_file() && m.len() == item.bytes);
        if !there {
            if max_file_bytes > 0 && item.bytes > max_file_bytes {
                return Err(Failure::TooBig {
                    file: item.r.file_name.clone(),
                    max: max_file_bytes,
                });
            }
            to_copy += item.bytes;
        }
        already.push(there);
    }
    let need = to_copy + if to_copy > 0 { SPARE_BYTES } else { 0 };
    if need > free_bytes {
        return Err(Failure::Full {
            need,
            free: free_bytes,
        });
    }
    Ok(Plan {
        items,
        already,
        to_copy,
    })
}

/// Where a copy has got to.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Progress {
    pub files_done: u32,
    pub files_skipped: u32,
    pub files_missing: u32,
    /// Bytes of the items accounted for (copied, skipped or missing).
    pub bytes_done: u64,
    /// The item being copied.
    pub current: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Outcome {
    Done,
    Cancelled,
    Failed(Failure),
}

/// Copies the plan from the recordings' root `src` to the stick mounted at
/// `stick`, oldest first. `report` is called as it goes (at most every
/// 250 ms within a file, and after each one); `cancel` is checked between
/// chunks; `present` says whether the stick is still plugged in. Returns
/// the outcome and the final progress. A partial `.part` file is removed
/// whatever stops the copy (if the stick is still there to remove it from).
pub fn run(
    plan: &Plan,
    src: &Path,
    stick: &Path,
    cancel: &AtomicBool,
    present: &dyn Fn() -> bool,
    report: &mut dyn FnMut(&Progress),
) -> (Outcome, Progress) {
    let mut p = Progress::default();
    for (item, &already) in plan.items.iter().zip(&plan.already) {
        if cancel.load(Ordering::SeqCst) {
            return (Outcome::Cancelled, p);
        }
        p.current = item.label();
        report(&p);
        let dest = item.dest(stick);
        // Checked again here, not only in the plan: a file finished by the
        // previous attempt counts whichever way it got there.
        if already || fs::metadata(&dest).is_ok_and(|m| m.is_file() && m.len() == item.bytes) {
            p.files_done += 1;
            p.files_skipped += 1;
            p.bytes_done += item.bytes;
            continue;
        }
        let input = match open_source(item, src) {
            Ok(Some(f)) => f,
            Ok(None) => {
                p.files_done += 1;
                p.files_missing += 1;
                p.bytes_done += item.bytes;
                continue;
            }
            Err(e) => return (Outcome::Failed(Failure::Drive(e.to_string())), p),
        };
        let base = p.bytes_done;
        let copied = copy_one(input, &dest, cancel, present, &mut |n| {
            p.bytes_done = base + n;
            report(&p);
        });
        match copied {
            Ok(true) => {}
            Ok(false) => {
                p.bytes_done = base;
                return (Outcome::Cancelled, p);
            }
            Err(f) => {
                p.bytes_done = base;
                return (Outcome::Failed(f), p);
            }
        }
        p.files_done += 1;
        p.bytes_done = base + item.bytes;
    }
    p.current.clear();
    report(&p);
    (Outcome::Done, p)
}

/// The recording, wherever it is now: Save clip may have moved it between
/// `<camera>/` and `protected/<camera>/` since the list was read. `None`:
/// gone (retention deleted it).
fn open_source(item: &Item, root: &Path) -> io::Result<Option<File>> {
    for protected in [item.r.protected, !item.r.protected] {
        match File::open(item.source(root, protected)) {
            Ok(f) => return Ok(Some(f)),
            Err(e) if e.kind() == io::ErrorKind::NotFound => {}
            Err(e) => return Err(e),
        }
    }
    Ok(None)
}

/// One file: write `<dest>.part`, flush it, rename it to `dest`. Ok(false):
/// cancelled. `progress` gets the bytes copied so far.
fn copy_one(
    mut input: File,
    dest: &Path,
    cancel: &AtomicBool,
    present: &dyn Fn() -> bool,
    progress: &mut dyn FnMut(u64),
) -> Result<bool, Failure> {
    let dir = dest.parent().unwrap_or(Path::new("/"));
    let part = part_path(dest);
    let write_err = |e: io::Error| classify(&e, present());
    fs::create_dir_all(dir).map_err(write_err)?;
    let result = (|| -> Result<bool, Failure> {
        let mut out = File::create(&part).map_err(write_err)?;
        let mut buf = vec![0u8; CHUNK];
        let mut copied = 0u64;
        let mut last = Instant::now();
        loop {
            if cancel.load(Ordering::SeqCst) {
                return Ok(false);
            }
            // sysfs drops a pulled stick before its writes start failing.
            if !present() {
                return Err(Failure::Removed);
            }
            let n = match input.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => n,
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(e) => return Err(Failure::Drive(e.to_string())),
            };
            out.write_all(&buf[..n]).map_err(write_err)?;
            copied += n as u64;
            if last.elapsed() >= PROGRESS_EVERY {
                last = Instant::now();
                progress(copied);
            }
        }
        out.sync_all().map_err(write_err)?;
        drop(out);
        fs::rename(&part, dest).map_err(write_err)?;
        // The rename reaches the stick with the final sync; on exFAT and
        // FAT a directory can't be opened to sync it alone.
        progress(copied);
        Ok(true)
    })();
    if !matches!(result, Ok(true)) {
        let _ = fs::remove_file(&part);
    }
    result
}

fn part_path(dest: &Path) -> PathBuf {
    let mut s = dest.as_os_str().to_os_string();
    s.push(".part");
    PathBuf::from(s)
}

#[cfg(test)]
mod tests {
    use super::*;
    use recording::segment::SegmentName;

    fn seg(camera: &str, boot: u32, seq: u32, bytes: u64, protected: bool) -> Segment {
        Segment {
            name: SegmentName {
                camera: camera.into(),
                boot,
                seq,
                wall: None,
            },
            bytes,
            protected,
        }
    }

    fn r(camera: &str, boot: u32, seq: u32, protected: bool) -> Ref {
        Ref {
            camera: camera.into(),
            file_name: format!("b{boot:05}-s{seq:06}.mkv"),
            protected,
        }
    }

    #[test]
    fn resolve_orders_oldest_first_and_counts_duplicates_once() {
        let scan = [
            seg("rear", 2, 0, 30, false),
            seg("front", 1, 5, 10, false),
            seg("front", 2, 0, 20, true),
        ];
        let items = resolve(
            &scan,
            &BTreeSet::new(),
            &[
                r("rear", 2, 0, false),
                r("front", 2, 0, true),
                r("front", 1, 5, false),
                r("rear", 2, 0, false),
            ],
        )
        .expect("resolves");
        let labels: Vec<_> = items.iter().map(Item::label).collect();
        assert_eq!(
            labels,
            [
                "front/b00001-s000005.mkv",
                "protected/front/b00002-s000000.mkv",
                "rear/b00002-s000000.mkv"
            ]
        );
        assert_eq!(items.iter().map(|i| i.bytes).sum::<u64>(), 60);
    }

    #[test]
    fn resolve_refuses_unknown_and_unfinished_recordings_and_empty_choices() {
        let scan = [seg("front", 1, 0, 10, false), seg("front", 1, 1, 10, false)];
        assert!(resolve(&scan, &BTreeSet::new(), &[]).is_err());
        // Saved-clip flag must match: the request names the file where the
        // list saw it.
        let e = resolve(&scan, &BTreeSet::new(), &[r("front", 1, 0, true)]).expect_err("unknown");
        assert!(e.contains("isn't on the data drive"), "{e}");
        let e = resolve(
            &scan,
            &BTreeSet::new(),
            &[Ref {
                camera: "../etc".into(),
                file_name: "passwd".into(),
                protected: false,
            }],
        )
        .expect_err("never a path");
        assert!(e.contains("passwd"), "{e}");
        let writing: BTreeSet<_> = [r("front", 1, 1, false)].into();
        let e = resolve(
            &scan,
            &writing,
            &[r("front", 1, 0, false), r("front", 1, 1, false)],
        )
        .expect_err("unfinished");
        assert!(e.contains("still being recorded"), "{e}");
    }

    #[test]
    fn write_errors_are_told_apart() {
        assert_eq!(
            classify(&io::Error::from(io::ErrorKind::StorageFull), true),
            Failure::FilledUp
        );
        assert_eq!(
            classify(&io::Error::from_raw_os_error(28), true),
            Failure::FilledUp
        ); // ENOSPC
        assert_eq!(
            classify(&io::Error::from(io::ErrorKind::ReadOnlyFilesystem), true),
            Failure::ReadOnly
        );
        assert_eq!(
            classify(&io::Error::from_raw_os_error(30), true),
            Failure::ReadOnly
        ); // EROFS
        assert_eq!(
            classify(&io::Error::from_raw_os_error(5), true),
            Failure::Removed
        ); // EIO
        assert_eq!(
            classify(&io::Error::from_raw_os_error(19), true),
            Failure::Removed
        ); // ENODEV
        assert_eq!(
            classify(&io::Error::from(io::ErrorKind::StorageFull), false),
            Failure::Removed
        );
        assert!(matches!(
            classify(&io::Error::other("odd"), true),
            Failure::Stick(_)
        ));
    }

    #[test]
    fn sizes_read_like_a_sticks_label() {
        assert_eq!(size(28_100_000_000), "28.1 GB");
        assert_eq!(size(340_400_000), "340 MB");
        assert_eq!(size(1), "1 kB");
    }

    #[test]
    fn failures_say_what_to_do() {
        let m = Failure::Full {
            need: 2_000_000_000,
            free: 500_000_000,
        }
        .message();
        assert!(m.contains("2.0 GB") && m.contains("500 MB"), "{m}");
        assert!(Failure::ReadOnly.message().contains("write-protect"));
        assert!(
            Failure::TooBig {
                file: "x.mkv".into(),
                max: 4_294_967_295
            }
            .message()
            .contains("exFAT")
        );
    }
}
