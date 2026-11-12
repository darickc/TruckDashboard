//! The service's state: the sticks plugged in, what each one is, and the
//! copy (ADR-0037). Blocking code on purpose: the copy runs on a thread of
//! its own and the poll on a blocking task, so a slow stick never holds up
//! the API. Every change is published on a watch channel, which the
//! gRPC stream follows.

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, SystemTime};

use f250_proto::export::v1 as pb;
use recording::store::Store;
use tokio::sync::watch;

use crate::copy::{self, FOLDER, Failure, Item, Outcome, Ref};
use crate::stickfs::StickFs;
use crate::sticks::{self, Found};

#[derive(Debug, Clone)]
pub struct Config {
    /// camera-manager's recordings: `/var/lib/f250/storage/video`.
    pub video_root: PathBuf,
    /// The data drive's mount point; `None`: not checked (development).
    pub drive: Option<PathBuf>,
    /// The map import's lock (`/run/f250-maps/import.lock`): while it
    /// exists a stick is being imported, and no stick is mounted writable.
    pub map_lock: PathBuf,
    /// A camera's newest recording changed this recently is still being
    /// written.
    pub writing_window: Duration,
}

/// Finds the sticks plugged in now (sticks::scan on the Pi).
pub type Discover = Box<dyn Fn() -> Vec<Found> + Send + Sync>;

pub struct Exporter {
    cfg: Config,
    fs: Arc<dyn StickFs>,
    discover: Discover,
    state: Mutex<State>,
    tx: watch::Sender<pb::WatchExportResponse>,
}

struct State {
    sticks: BTreeMap<String, (Found, pb::Stick)>,
    copy: pb::Copy,
    next_id: u64,
    cancel: Arc<AtomicBool>,
    /// The stick a copy has (or is about to have) mounted writable.
    busy: Option<String>,
}

impl State {
    fn snapshot(&self) -> pb::WatchExportResponse {
        pb::WatchExportResponse {
            sticks: self.sticks.values().map(|(_, s)| s.clone()).collect(),
            copy: Some(self.copy.clone()),
        }
    }
}

fn idle() -> pb::Copy {
    pb::Copy {
        state: pb::CopyState::Idle as i32,
        safe_to_unplug: true,
        folder: FOLDER.into(),
        ..Default::default()
    }
}

impl Exporter {
    pub fn new(cfg: Config, fs: Arc<dyn StickFs>, discover: Discover) -> Arc<Exporter> {
        let state = State {
            sticks: BTreeMap::new(),
            copy: idle(),
            next_id: 1,
            cancel: Arc::new(AtomicBool::new(false)),
            busy: None,
        };
        let (tx, _) = watch::channel(state.snapshot());
        Arc::new(Exporter {
            cfg,
            fs,
            discover,
            state: Mutex::new(state),
            tx,
        })
    }

    pub fn watch(&self) -> watch::Receiver<pb::WatchExportResponse> {
        self.tx.subscribe()
    }

    pub fn status(&self) -> pb::WatchExportResponse {
        self.lock().snapshot()
    }

    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn publish(&self, st: &State) {
        self.tx.send_replace(st.snapshot());
    }

    fn update(&self, f: impl FnOnce(&mut State)) {
        let mut st = self.lock();
        f(&mut st);
        self.publish(&st);
    }

    /// Looks for sticks once: new ones are checked (mounted read-only for a
    /// moment), gone ones dropped. Blocks while it checks.
    pub fn poll(&self) {
        let found = (self.discover)();
        let mut new = Vec::new();
        {
            let mut st = self.lock();
            let before = st.sticks.len();
            let now: BTreeSet<&str> = found.iter().map(|f| f.device.as_str()).collect();
            st.sticks.retain(|d, _| now.contains(d.as_str()));
            let mut changed = st.sticks.len() != before;
            for f in &found {
                match st.sticks.get_mut(&f.device) {
                    // The write-protect switch can change without a replug.
                    Some((old, s)) if old.read_only != f.read_only => {
                        s.read_only = f.read_only;
                        old.read_only = f.read_only;
                        changed = true;
                    }
                    Some(_) => {}
                    None => {
                        eprintln!(
                            "[export] stick {} plugged in: {} {} {:?}",
                            f.device, f.filesystem, f.model, f.label
                        );
                        st.sticks.insert(f.device.clone(), (f.clone(), checking(f)));
                        new.push(f.clone());
                        changed = true;
                    }
                }
            }
            if changed {
                self.publish(&st);
            }
        }
        for f in new {
            let stick = self.inspect(&f);
            eprintln!("[export] stick {}: {}", f.device, describe(&stick));
            self.update(|st| {
                if let Some((_, s)) = st.sticks.get_mut(&f.device) {
                    *s = stick;
                }
            });
        }
    }

    /// What a stick is: mounted read-only for a moment to look for map data
    /// and read its free space.
    fn inspect(&self, f: &Found) -> pb::Stick {
        let mut s = checking(f);
        let unusable = |mut s: pb::Stick, why: String| {
            s.role = pb::StickRole::Unusable as i32;
            s.detail = why;
            s
        };
        if f.filesystem.is_empty() {
            return unusable(
                s,
                "No filesystem the head unit can read: format the stick as exFAT on a computer."
                    .into(),
            );
        }
        if !sticks::supported(&f.filesystem) {
            return unusable(
                s,
                format!(
                    "Its filesystem ({}) isn't supported: format the stick as exFAT on a computer.",
                    f.filesystem
                ),
            );
        }
        let at = match self.fs.mount(&f.device, &f.filesystem, false) {
            Ok(at) => at,
            Err(e) => return unusable(s, format!("It couldn't be mounted: {e}")),
        };
        let map = ["map.pmtiles", "routing.tar"]
            .iter()
            .any(|n| at.join("f250").join(n).is_file());
        let space = self.fs.space(&at);
        self.unmount(&f.device, &at);
        if map {
            s.role = pb::StickRole::Map as i32;
            s.detail = "A map stick (it has f250/map.pmtiles or f250/routing.tar): recordings \
                        aren't copied to it. Use another stick."
                .into();
            return s;
        }
        match space {
            Ok(sp) => {
                s.role = pb::StickRole::Export as i32;
                s.free_bytes = sp.free_bytes;
                s.total_bytes = sp.total_bytes;
                s.max_file_bytes = sticks::max_file_bytes(&f.filesystem);
                if f.read_only {
                    s.detail = Failure::ReadOnly.message();
                }
                s
            }
            Err(e) => unusable(s, format!("Its free space couldn't be read: {e}")),
        }
    }

    fn unmount(&self, device: &str, at: &Path) -> bool {
        match self.fs.unmount(at, false) {
            Ok(()) => true,
            Err(e) => {
                eprintln!("[export] unmounting {device}: {e}; detaching it");
                self.fs.unmount(at, true).is_ok()
            }
        }
    }

    /// The recordings on the drive, oldest first.
    pub fn list(&self) -> pb::ListRecordingsResponse {
        let mut out = pb::ListRecordingsResponse {
            drive_mounted: true,
            ..Default::default()
        };
        if let Some(drive) = &self.cfg.drive
            && !is_mounted(drive)
        {
            out.drive_mounted = false;
            out.problem = format!(
                "The data drive isn't mounted at {}: there are no recordings to copy.",
                drive.display()
            );
            return out;
        }
        let mut scan = match Store::existing(&self.cfg.video_root).scan() {
            Ok(s) => s,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                out.problem = "Nothing has been recorded on the data drive yet.".into();
                return out;
            }
            Err(e) => {
                out.problem = format!("The recordings couldn't be read: {e}");
                return out;
            }
        };
        scan.segments
            .sort_by(|a, b| a.name.order(&b.name).then(a.protected.cmp(&b.protected)));
        let writing = self.being_written(&scan.segments);
        out.recordings = scan
            .segments
            .iter()
            .map(|s| {
                let r = ref_of(s);
                pb::Recording {
                    being_written: writing.contains(&r),
                    camera: r.camera,
                    file_name: r.file_name,
                    protected: r.protected,
                    bytes: s.bytes,
                    boot: s.name.boot,
                    seq: s.name.seq,
                    wall_time: s.name.wall.unwrap_or(0),
                }
            })
            .collect();
        out
    }

    /// Each camera's newest recording, if it changed in the last few
    /// seconds: camera-manager is probably still writing it. Saved clips
    /// are only moved there once finished (ADR-0027 decision 8).
    fn being_written(&self, segments: &[recording::retention::Segment]) -> BTreeSet<Ref> {
        let mut newest: BTreeMap<&str, &recording::retention::Segment> = BTreeMap::new();
        for s in segments.iter().filter(|s| !s.protected) {
            let e = newest.entry(s.name.camera.as_str()).or_insert(s);
            if s.name.order(&e.name).is_gt() {
                *e = s;
            }
        }
        let now = SystemTime::now();
        newest
            .values()
            .filter(|s| {
                let path = self
                    .cfg
                    .video_root
                    .join(&s.name.camera)
                    .join(s.name.file_name());
                std::fs::metadata(path)
                    .and_then(|m| m.modified())
                    .is_ok_and(|t| {
                        now.duration_since(t).unwrap_or_default() < self.cfg.writing_window
                    })
            })
            .map(|s| ref_of(s))
            .collect()
    }

    /// Starts copying `refs` to `device` on a thread of its own.
    pub fn start(
        self: &Arc<Self>,
        device: &str,
        refs: &[Ref],
        source: &str,
    ) -> pb::StartCopyResponse {
        let refuse = |detail: String| {
            eprintln!("[export] copy for {source} refused: {detail}");
            pb::StartCopyResponse {
                started: false,
                detail,
                id: 0,
            }
        };
        let (found, max_file) = {
            let st = self.lock();
            if st.busy.is_some() {
                return refuse("A copy is already running.".into());
            }
            let Some((found, stick)) = st.sticks.get(device) else {
                return refuse("That stick isn't plugged in any more.".into());
            };
            match pb::StickRole::try_from(stick.role) {
                Ok(pb::StickRole::Export) => {}
                Ok(pb::StickRole::Checking) => {
                    return refuse(
                        "The stick is still being checked: try again in a moment.".into(),
                    );
                }
                _ => return refuse(stick.detail.clone()),
            }
            if found.read_only {
                return refuse(Failure::ReadOnly.message());
            }
            (found.clone(), stick.max_file_bytes)
        };
        if self.cfg.map_lock.exists() {
            return refuse("A map stick is being imported: wait until it has finished.".into());
        }
        let scan = match Store::existing(&self.cfg.video_root).scan() {
            Ok(s) => s,
            Err(e) => return refuse(format!("The recordings couldn't be read: {e}")),
        };
        let writing = self.being_written(&scan.segments);
        let items = match copy::resolve(&scan.segments, &writing, refs) {
            Ok(i) => i,
            Err(e) => return refuse(e),
        };
        let id = {
            let mut st = self.lock();
            if st.busy.is_some() {
                return refuse("A copy is already running.".into());
            }
            st.busy = Some(found.device.clone());
            st.cancel = Arc::new(AtomicBool::new(false));
            let id = st.next_id;
            st.next_id += 1;
            st.copy = pb::Copy {
                state: pb::CopyState::Preparing as i32,
                device: found.device.clone(),
                files_total: items.len() as u32,
                bytes_total: items.iter().map(|i| i.bytes).sum(),
                detail: "Getting the stick ready: leave it in.".into(),
                folder: FOLDER.into(),
                id,
                ..Default::default()
            };
            self.publish(&st);
            id
        };
        eprintln!(
            "[export] copy {id} for {source}: {} recordings ({}) to {}",
            items.len(),
            copy::size(items.iter().map(|i| i.bytes).sum()),
            found.device
        );
        let me = Arc::clone(self);
        let cancel = Arc::clone(&self.lock().cancel);
        std::thread::spawn(move || me.job(&found, max_file, items, &cancel));
        pb::StartCopyResponse {
            started: true,
            detail: String::new(),
            id,
        }
    }

    pub fn cancel(&self) -> bool {
        let st = self.lock();
        if st.busy.is_none() {
            return false;
        }
        eprintln!("[export] copy {} cancelled", st.copy.id);
        st.cancel.store(true, Ordering::SeqCst);
        true
    }

    fn job(&self, stick: &Found, max_file: u64, items: Vec<Item>, cancel: &AtomicBool) {
        let device = stick.device.as_str();
        let total = items.len() as u32;
        let present = || self.fs.present(device);
        let at = match self.fs.mount(device, &stick.filesystem, true) {
            Ok(at) => at,
            Err(e) => {
                let f = if present() {
                    Failure::Stick(format!("it couldn't be mounted: {e}"))
                } else {
                    Failure::Removed
                };
                return self.finish(
                    Outcome::Failed(f),
                    &copy::Progress::default(),
                    total,
                    true,
                    None,
                );
            }
        };
        let prepared = (|| {
            let space = self
                .fs
                .space(&at)
                .map_err(|e| copy::classify(&e, present()))?;
            if space.read_only {
                return Err(Failure::ReadOnly);
            }
            std::fs::create_dir_all(at.join(FOLDER)).map_err(|e| copy::classify(&e, present()))?;
            copy::plan(items, &at, space.free_bytes, max_file)
        })();
        let (outcome, progress) = match prepared {
            Err(f) => (Outcome::Failed(f), copy::Progress::default()),
            Ok(plan) => {
                self.update(|st| {
                    st.copy.state = pb::CopyState::Copying as i32;
                    st.copy.detail = "Copying: leave the stick in.".into();
                });
                copy::run(
                    &plan,
                    &self.cfg.video_root,
                    &at,
                    cancel,
                    &present,
                    &mut |p| {
                        self.update(|st| {
                            st.copy.files_done = p.files_done;
                            st.copy.files_skipped = p.files_skipped;
                            st.copy.files_missing = p.files_missing;
                            st.copy.bytes_done = p.bytes_done;
                            st.copy.current = p.current.clone();
                        });
                    },
                )
            }
        };
        self.update(|st| {
            st.copy.state = pb::CopyState::Finishing as i32;
            st.copy.current.clear();
            st.copy.detail = "Writing the last of it to the stick: leave it in.".into();
        });
        // Flush and unmount whatever happened: what was copied is complete
        // on the stick, and the stick can come out.
        let mut outcome = outcome;
        let synced = match self.fs.sync(&at) {
            Ok(()) => true,
            Err(e) => {
                eprintln!("[export] syncing {device}: {e}");
                if outcome == Outcome::Done {
                    outcome = Outcome::Failed(copy::classify(&e, present()));
                }
                false
            }
        };
        let free = self.fs.space(&at).ok().map(|s| s.free_bytes);
        let unmounted = self.unmount(device, &at);
        let gone = !present();
        // Pulled out: nothing more can be written, and nothing waits on it.
        let safe = gone || (synced && unmounted);
        self.finish(outcome, &progress, total, safe, free);
    }

    fn finish(
        &self,
        outcome: Outcome,
        p: &copy::Progress,
        total: u32,
        safe: bool,
        free: Option<u64>,
    ) {
        let copied = p.files_done - p.files_skipped - p.files_missing;
        let (state, mut detail) = match &outcome {
            Outcome::Done => {
                let mut d = format!(
                    "Copied {copied} recording{} to {FOLDER} on the stick.",
                    if copied == 1 { "" } else { "s" }
                );
                if p.files_skipped > 0 {
                    d.push_str(&format!(" {} were already there.", p.files_skipped));
                }
                if p.files_missing > 0 {
                    d.push_str(&format!(
                        " {} had been deleted from the data drive before they were copied.",
                        p.files_missing
                    ));
                }
                (pb::CopyState::Done, d)
            }
            Outcome::Cancelled => (
                pb::CopyState::Cancelled,
                format!(
                    "Cancelled: {} of {total} recordings are on the stick.",
                    p.files_done - p.files_missing
                ),
            ),
            Outcome::Failed(Failure::Removed) => (
                pb::CopyState::Failed,
                format!(
                    "{} {} of {total} recordings were finished before. Plug it in and copy again: \
                     the finished ones are skipped.",
                    Failure::Removed.message(),
                    p.files_done - p.files_missing
                ),
            ),
            Outcome::Failed(f) => (
                pb::CopyState::Failed,
                format!(
                    "{} {} of {total} recordings are on the stick.",
                    f.message(),
                    p.files_done - p.files_missing
                ),
            ),
        };
        if !safe {
            detail
                .push_str(" The stick couldn't be unmounted: wait a minute before pulling it out.");
        }
        eprintln!("[export] copy finished ({state:?}): {detail}");
        self.update(|st| {
            st.copy.state = state as i32;
            st.copy.detail = detail;
            st.copy.safe_to_unplug = safe;
            st.copy.current.clear();
            st.copy.files_done = p.files_done;
            st.copy.files_skipped = p.files_skipped;
            st.copy.files_missing = p.files_missing;
            st.copy.bytes_done = p.bytes_done;
            if let (Some(free), Some((_, s))) = (free, st.sticks.get_mut(&st.copy.device)) {
                s.free_bytes = free;
            }
            st.busy = None;
        });
    }
}

fn ref_of(s: &recording::retention::Segment) -> Ref {
    Ref {
        camera: s.name.camera.clone(),
        file_name: s.name.file_name(),
        protected: s.protected,
    }
}

fn checking(f: &Found) -> pb::Stick {
    pb::Stick {
        device: f.device.clone(),
        label: f.label.clone(),
        model: f.model.clone(),
        filesystem: f.filesystem.clone(),
        role: pb::StickRole::Checking as i32,
        total_bytes: f.size_bytes,
        read_only: f.read_only,
        ..Default::default()
    }
}

fn describe(s: &pb::Stick) -> String {
    match pb::StickRole::try_from(s.role) {
        Ok(pb::StickRole::Export) => format!(
            "export stick, {} free of {}{}",
            copy::size(s.free_bytes),
            copy::size(s.total_bytes),
            if s.read_only { ", read-only" } else { "" }
        ),
        Ok(pb::StickRole::Map) => "map stick: left to the map import".into(),
        _ => format!("unusable: {}", s.detail),
    }
}

/// `path` is a mount point (its device differs from its parent's).
pub fn is_mounted(path: &Path) -> bool {
    use std::os::unix::fs::MetadataExt;
    let Ok(me) = std::fs::metadata(path) else {
        return false;
    };
    let parent = path.parent().unwrap_or(Path::new("/"));
    std::fs::metadata(parent).is_ok_and(|p| me.dev() != p.dev() || me.ino() == p.ino())
}
