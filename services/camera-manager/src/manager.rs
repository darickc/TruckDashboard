//! The control loop: feeds the camera policy, runs one capture per camera
//! that needs one, and publishes what is on screen (ADR-0026) and what is
//! recording (ADR-0027).
//!
//! **Display.** The camera on screen gets a display branch; a camera counts
//! as up only once that branch delivers frames. No frame for
//! `frame_timeout` (or none within `start_timeout` of the start) makes it
//! unavailable and **removes the branch**, closing its window, so no frozen
//! frame stays on screen. It is retried after a backoff while the view
//! still wants it.
//!
//! **Recording** (front and rear, `--record`). Each recorded camera keeps a
//! capture with a recording branch while the data drive is ready; the
//! display branch comes and goes on the same capture. A recording branch
//! with no frames for `frame_timeout` marks the recording failed and the
//! capture restarts after a backoff. A camera that isn't recorded runs only
//! while shown (ADR-0026 decision 2).
//!
//! The segment being written is synced to the drive every `RECORD_SYNC_S`
//! (decision 5); the drive thread ([`crate::drive`]) runs retention as each
//! segment starts and once a minute, and saves clips.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use camera_policy::{Camera, Input, Move, Policy, ReverseStatus, Why};
use f250_proto::camera::v1 as pb;
use f250_sd_notify::Heartbeat;
use recording::segment::SegmentName;
use tokio::sync::{mpsc, oneshot, watch};
use tokio::time::Instant;

use crate::config::{RecordingConfig, Settings, camera_name};
use crate::drive::{self, Clock, DriveConfig, DriveStatus, Job};
use crate::media::{self, Branch, Capture, CaptureSpec, Event, Media, RecordSpec};

/// The loop wakes at least this often, to beat the heartbeat.
const IDLE_WAKE: Duration = Duration::from_secs(1);
/// Retention runs at least this often (ADR-0027 decision 7).
const PASS_EVERY: Duration = Duration::from_secs(60);
/// How long the drive thread gets to write the clean-stop marker.
const CLEAN_STOP_WAIT: Duration = Duration::from_secs(2);

pub enum Command {
    Move {
        mv: Move,
        source: String,
        reply: oneshot::Sender<pb::View>,
    },
    SaveClip {
        source: String,
        reply: oneshot::Sender<pb::SaveClipResponse>,
    },
    /// Stop: every capture is stopped (never restarted), recordings
    /// finished, and [`Manager::run`] returns. Its view sender goes with it,
    /// which ends every `WatchView` stream, so the server's graceful shutdown
    /// can finish (bench-log 2026-11-10: without this, a stop hung until
    /// systemd's SIGKILL).
    Shutdown,
}

/// The display branch of the camera on screen.
enum Feed {
    /// No camera wanted.
    Off,
    Starting {
        camera: Camera,
        generation: u64,
        since: Instant,
    },
    Live {
        camera: Camera,
        generation: u64,
        last_frame: Instant,
    },
    Down {
        camera: Camera,
        detail: String,
        /// When to try again; `None` when retrying can't help (no device).
        retry_at: Option<Instant>,
    },
}

impl Feed {
    fn camera(&self) -> Option<Camera> {
        match self {
            Feed::Off => None,
            Feed::Starting { camera, .. }
            | Feed::Live { camera, .. }
            | Feed::Down { camera, .. } => Some(*camera),
        }
    }

    /// The capture whose display branch this is.
    fn generation(&self) -> Option<u64> {
        match self {
            Feed::Starting { generation, .. } | Feed::Live { generation, .. } => Some(*generation),
            _ => None,
        }
    }
}

/// A running capture.
struct Cap {
    camera: Camera,
    cap: Box<dyn Capture>,
    generation: u64,
    display: bool,
    record: bool,
}

/// One recorded camera.
struct Rec {
    camera: Camera,
    state: RecState,
    segment: Option<Open>,
    /// The segment that finished last, until the next one opens: "save
    /// clip" in that gap anchors on the one about to start.
    closed: Option<SegmentName>,
    backoff: Duration,
}

enum RecState {
    /// Not recording, and not trying to: no drive, no device, can't record.
    Idle(String),
    Starting {
        generation: u64,
        since: Instant,
    },
    Recording {
        generation: u64,
        last_frame: Instant,
    },
    Failed {
        detail: String,
        retry_at: Instant,
    },
}

/// The segment being written.
struct Open {
    name: SegmentName,
    path: PathBuf,
    /// Opened for syncing (ADR-0027 decision 5); `None` until it can be.
    file: Option<Arc<std::fs::File>>,
    syncing: Arc<AtomicBool>,
}

/// Names segments for the recording branches: this run's number, a
/// sequence per camera, and the wall time only while the clock is trusted
/// (ADR-0027 decision 10).
struct Namer {
    root: PathBuf,
    boot: u32,
    clock: Clock,
    seq: HashMap<String, u32>,
}

impl Namer {
    fn next(&mut self, camera: &str) -> PathBuf {
        let seq = self.seq.entry(camera.to_string()).or_default();
        let name = SegmentName {
            camera: camera.to_string(),
            boot: self.boot,
            seq: *seq,
            wall: self.clock.trusted_now(),
        };
        *seq += 1;
        self.root.join(camera).join(name.file_name())
    }
}

struct DriveLink {
    jobs: mpsc::Sender<Job>,
    status: watch::Receiver<DriveStatus>,
}

pub struct Manager {
    settings: Settings,
    media: Box<dyn Media>,
    policy: Policy,
    feed: Feed,
    /// By camera name (`Camera` isn't `Hash`).
    caps: HashMap<&'static str, Cap>,
    rec: Vec<Rec>,
    generation: u64,
    backoff: Duration,
    start: Instant,
    events_tx: mpsc::Sender<Event>,
    events_rx: Option<mpsc::Receiver<Event>>,
    view_tx: watch::Sender<pb::View>,
    recording_tx: watch::Sender<pb::Recording>,
    heartbeat: Heartbeat,
    drive: Option<DriveLink>,
    namer: Option<Arc<Mutex<Namer>>>,
    next_pass: Instant,
    next_sync: Instant,
}

/// What the server watches.
pub struct Watches {
    pub view: watch::Receiver<pb::View>,
    pub recording: watch::Receiver<pb::Recording>,
}

impl Manager {
    pub fn new(settings: Settings, media: Box<dyn Media>) -> (Manager, Watches) {
        let policy = Policy::new(settings.policy.clone());
        let (events_tx, events_rx) = mpsc::channel(512);
        let (view_tx, view_rx) = watch::channel(pb::View::default());
        let (recording_tx, recording_rx) = watch::channel(pb::Recording::default());
        let backoff = settings.restart_min;
        let now = Instant::now();
        let rec = settings
            .recording
            .as_ref()
            .map(|r| {
                r.cameras
                    .iter()
                    .map(|c| Rec {
                        camera: *c,
                        state: RecState::Idle("checking the data drive".into()),
                        segment: None,
                        closed: None,
                        backoff: settings.restart_min,
                    })
                    .collect()
            })
            .unwrap_or_default();
        let drive = settings.recording.as_ref().map(|r| {
            let (jobs, status, _thread) = drive::spawn(DriveConfig {
                root: r.root.clone(),
                mount: r.mount.clone(),
                cameras: r
                    .cameras
                    .iter()
                    .map(|c| camera_name(*c).to_string())
                    .collect(),
                settings: r.settings.clone(),
                clock: r.clock.clone(),
            });
            DriveLink { jobs, status }
        });
        let m = Manager {
            settings,
            media,
            policy,
            feed: Feed::Off,
            caps: HashMap::new(),
            rec,
            generation: 0,
            backoff,
            start: now,
            events_tx,
            events_rx: Some(events_rx),
            view_tx,
            recording_tx,
            heartbeat: Heartbeat::new(),
            drive,
            namer: None,
            next_pass: now + PASS_EVERY,
            next_sync: now,
        };
        m.view_tx.send_replace(m.api_view());
        m.recording_tx.send_replace(m.api_recording());
        (
            m,
            Watches {
                view: view_rx,
                recording: recording_rx,
            },
        )
    }

    pub fn heartbeat(&self) -> Heartbeat {
        self.heartbeat.clone()
    }

    fn rec_cfg(&self) -> Option<&RecordingConfig> {
        self.settings.recording.as_ref()
    }

    /// Runs until [`Command::Shutdown`] or the command channel closes, then
    /// stops every capture.
    pub async fn run(mut self, mut cmds: mpsc::Receiver<Command>) {
        let Some(mut events) = self.events_rx.take() else {
            return;
        };
        self.log_view();
        let mut drive_status = self.drive.as_ref().map(|d| d.status.clone());
        if self.drive.is_some() {
            self.send_pass().await;
        }
        loop {
            self.heartbeat.beat();
            let wake = self.next_wake(Instant::now());
            tokio::select! {
                c = cmds.recv() => match c {
                    Some(Command::Shutdown) | None => break,
                    Some(c) => self.command(c).await,
                },
                Some(e) = events.recv() => self.event(e).await,
                Ok(()) = async {
                    match drive_status.as_mut() {
                        Some(s) => s.changed().await,
                        None => std::future::pending().await,
                    }
                } => self.drive_changed().await,
                () = tokio::time::sleep_until(wake) => self.tick().await,
            }
        }
        self.shutdown(&mut events).await;
    }

    fn now_d(&self, now: Instant) -> Duration {
        now.saturating_duration_since(self.start)
    }

    fn next_wake(&self, now: Instant) -> Instant {
        let mut wake = now + IDLE_WAKE;
        let mut consider = |t: Instant| wake = wake.min(t);
        if let Some(d) = self.policy.deadline() {
            consider(self.start + d);
        }
        match &self.feed {
            Feed::Starting { since, .. } => consider(*since + self.settings.start_timeout),
            Feed::Live { last_frame, .. } => consider(*last_frame + self.settings.frame_timeout),
            Feed::Down {
                retry_at: Some(t), ..
            } => consider(*t),
            _ => {}
        }
        for r in &self.rec {
            match &r.state {
                RecState::Starting { since, .. } => consider(*since + self.settings.start_timeout),
                RecState::Recording { last_frame, .. } => {
                    consider(*last_frame + self.settings.frame_timeout)
                }
                RecState::Failed { retry_at, .. } => consider(*retry_at),
                RecState::Idle(_) => {}
            }
        }
        if self.drive.is_some() {
            consider(self.next_pass);
            if self.rec.iter().any(|r| r.segment.is_some()) {
                consider(self.next_sync);
            }
        }
        wake
    }

    async fn command(&mut self, c: Command) {
        match c {
            Command::Move { mv, source, reply } => {
                let now = Instant::now();
                eprintln!("[camera] switch: {} (from {source})", move_name(mv));
                self.policy.handle(Input::Switch(mv), self.now_d(now));
                self.reconcile(now).await;
                self.publish();
                let _ = reply.send(self.api_view());
            }
            Command::SaveClip { source, reply } => {
                eprintln!("[camera] save clip (from {source})");
                let Some(d) = &self.drive else {
                    let _ = reply.send(pb::SaveClipResponse {
                        saved: false,
                        detail: "Not saved: recording is off (RECORD_CAMERAS)".into(),
                        ..Default::default()
                    });
                    return;
                };
                let writing = self.writing();
                if let Err(e) = d.jobs.send(Job::SaveClip { writing, reply }).await
                    && let Job::SaveClip { reply, .. } = e.0
                {
                    let _ = reply.send(pb::SaveClipResponse {
                        saved: false,
                        detail: "Not saved: the recording store stopped".into(),
                        ..Default::default()
                    });
                }
            }
            // Handled in run().
            Command::Shutdown => {}
        }
    }

    async fn event(&mut self, e: Event) {
        let now = Instant::now();
        let generation = e.generation();
        let Some(camera) = self.camera_of(generation) else {
            return; // a stopped capture's last word
        };
        match e {
            Event::Frame {
                branch: Branch::Display,
                ..
            } => self.display_frame(now, generation),
            Event::Frame {
                branch: Branch::Record,
                ..
            } => self.record_frame(now, camera, generation),
            Event::SegmentOpened { path, .. } => self.segment_opened(camera, path).await,
            Event::SegmentClosed { path, .. } => self.segment_closed(camera, &path).await,
            Event::Ended { detail, .. } => {
                self.fail_capture(now, camera, detail).await;
                self.reconcile(now).await;
                self.publish();
            }
        }
    }

    fn camera_of(&self, generation: u64) -> Option<Camera> {
        self.caps
            .values()
            .find(|k| k.generation == generation)
            .map(|k| k.camera)
    }

    fn display_frame(&mut self, now: Instant, generation: u64) {
        if self.feed.generation() != Some(generation) {
            return; // the capture records, but its window isn't wanted
        }
        match std::mem::replace(&mut self.feed, Feed::Off) {
            Feed::Starting {
                camera,
                generation,
                since,
            } => {
                eprintln!(
                    "[camera] {} camera live: first frame after {} ms",
                    camera_name(camera),
                    now.saturating_duration_since(since).as_millis()
                );
                self.backoff = self.settings.restart_min;
                self.policy.handle(Input::CameraUp(camera), self.now_d(now));
                self.feed = Feed::Live {
                    camera,
                    generation,
                    last_frame: now,
                };
                self.publish();
            }
            Feed::Live {
                camera, generation, ..
            } => {
                self.feed = Feed::Live {
                    camera,
                    generation,
                    last_frame: now,
                };
            }
            other => self.feed = other,
        }
    }

    fn record_frame(&mut self, now: Instant, camera: Camera, generation: u64) {
        let min = self.settings.restart_min;
        let Some(r) = self.rec.iter_mut().find(|r| r.camera == camera) else {
            return;
        };
        match &r.state {
            RecState::Starting {
                generation: g,
                since,
            } if *g == generation => {
                eprintln!(
                    "[camera] {} camera recording: first frame after {} ms",
                    camera_name(camera),
                    now.saturating_duration_since(*since).as_millis()
                );
                r.backoff = min;
                r.state = RecState::Recording {
                    generation,
                    last_frame: now,
                };
                self.publish();
            }
            RecState::Recording { generation: g, .. } if *g == generation => {
                r.state = RecState::Recording {
                    generation,
                    last_frame: now,
                };
            }
            _ => {}
        }
    }

    async fn segment_opened(&mut self, camera: Camera, path: PathBuf) {
        let name = name_of(camera, &path);
        let Some(r) = self.rec.iter_mut().find(|r| r.camera == camera) else {
            return;
        };
        let Some(name) = name else {
            eprintln!(
                "[camera] {} camera: unexpected segment name {}",
                camera_name(camera),
                path.display()
            );
            return;
        };
        let file = std::fs::File::open(&path).ok().map(Arc::new);
        r.closed = None;
        r.segment = Some(Open {
            name,
            path,
            file,
            syncing: Arc::new(AtomicBool::new(false)),
        });
        self.publish();
        // Retention as each segment starts (ADR-0027 decision 7).
        self.send_pass().await;
    }

    async fn segment_closed(&mut self, camera: Camera, path: &Path) {
        let Some(name) = name_of(camera, path) else {
            return;
        };
        if let Some(r) = self.rec.iter_mut().find(|r| r.camera == camera)
            && r.segment.as_ref().is_some_and(|o| o.name == name)
        {
            // Its end (the cues) to the drive too.
            if let Some(o) = r.segment.take() {
                r.closed = Some(o.name.clone());
                sync_now(o);
            }
            self.publish();
        }
        if let Some(d) = &self.drive {
            let _ = d.jobs.send(Job::Finished(name)).await;
        }
    }

    async fn drive_changed(&mut self) {
        let status = match &self.drive {
            Some(d) => d.status.borrow().clone(),
            None => return,
        };
        if let (Some(boot), None, Some(cfg)) = (status.boot, &self.namer, self.rec_cfg()) {
            self.namer = Some(Arc::new(Mutex::new(Namer {
                root: cfg.root.clone(),
                boot,
                clock: cfg.clock.clone(),
                seq: HashMap::new(),
            })));
        }
        let now = Instant::now();
        self.reconcile(now).await;
        self.publish();
    }

    async fn tick(&mut self) {
        let now = Instant::now();
        self.policy.handle(Input::Tick, self.now_d(now));
        match &self.feed {
            Feed::Starting { since, .. } if now >= *since + self.settings.start_timeout => {
                let ms = self.settings.start_timeout.as_millis();
                self.fail_display(now, format!("no frame within {ms} ms of starting"))
                    .await;
            }
            Feed::Live { last_frame, .. } if now >= *last_frame + self.settings.frame_timeout => {
                let ms = self.settings.frame_timeout.as_millis();
                self.fail_display(now, format!("no frame for {ms} ms"))
                    .await;
            }
            Feed::Down {
                camera,
                retry_at: Some(t),
                ..
            } if now >= *t && self.policy.view().camera == Some(*camera) => {
                let camera = *camera;
                self.feed = Feed::Off;
                self.start_display(now, camera).await;
            }
            _ => {}
        }
        let stalled: Vec<(Camera, String)> = self
            .rec
            .iter()
            .filter_map(|r| match &r.state {
                RecState::Starting { since, .. } if now >= *since + self.settings.start_timeout => {
                    Some((
                        r.camera,
                        format!(
                            "no frame within {} ms of starting",
                            self.settings.start_timeout.as_millis()
                        ),
                    ))
                }
                RecState::Recording { last_frame, .. }
                    if now >= *last_frame + self.settings.frame_timeout =>
                {
                    Some((
                        r.camera,
                        format!(
                            "no frame for {} ms",
                            self.settings.frame_timeout.as_millis()
                        ),
                    ))
                }
                _ => None,
            })
            .collect();
        for (camera, detail) in stalled {
            self.fail_capture(now, camera, detail).await;
        }
        if self.drive.is_some() {
            if now >= self.next_pass {
                self.next_pass = now + PASS_EVERY;
                self.send_pass().await;
            }
            if now >= self.next_sync {
                let every = self.rec_cfg().map_or(1, |c| c.settings.sync_s.max(1));
                self.next_sync = now + Duration::from_secs(u64::from(every));
                self.sync_segments();
            }
        }
        self.reconcile(now).await;
        self.publish();
    }

    /// Forces the segments being written to the drive (ADR-0027 decision
    /// 5), off the loop's thread, one sync per camera at a time.
    fn sync_segments(&mut self) {
        for r in &mut self.rec {
            let Some(o) = r.segment.as_mut() else {
                continue;
            };
            if o.file.is_none() {
                o.file = std::fs::File::open(&o.path).ok().map(Arc::new);
            }
            let Some(file) = o.file.clone() else { continue };
            if o.syncing.swap(true, Ordering::AcqRel) {
                continue; // the last one hasn't finished
            }
            let syncing = o.syncing.clone();
            let name = o.name.clone();
            tokio::task::spawn_blocking(move || {
                if let Err(e) = file.sync_data() {
                    eprintln!("[camera] recording: sync of {name} failed: {e}");
                }
                syncing.store(false, Ordering::Release);
            });
        }
    }

    async fn send_pass(&mut self) {
        let writing = self.writing();
        if let Some(d) = &self.drive {
            let _ = d.jobs.send(Job::Pass { writing }).await;
        }
    }

    /// The segment each recording camera is writing. Between one segment
    /// finishing and the next opening, the next one (by name: it has the
    /// next sequence number).
    fn writing(&self) -> Vec<SegmentName> {
        self.rec
            .iter()
            .filter_map(|r| match (&r.segment, &r.closed, &r.state) {
                (Some(o), ..) => Some(o.name.clone()),
                (None, Some(c), RecState::Recording { .. }) => Some(SegmentName {
                    seq: c.seq + 1,
                    wall: None,
                    ..c.clone()
                }),
                _ => None,
            })
            .collect()
    }

    /// Whether `camera` should record now, or why not.
    fn record_wanted(&self, camera: Camera) -> Result<(), String> {
        let name = camera_name(camera);
        if self.settings.device(camera).is_none() {
            return Err(format!(
                "no {name} camera configured (--camera {name}=DEVICE)"
            ));
        }
        self.media.can_record()?;
        media::recordable(&self.settings.caps)?;
        let Some(d) = &self.drive else {
            return Err("recording is off".into());
        };
        let s = d.status.borrow();
        if !s.ready {
            return Err(s
                .why_not
                .clone()
                .unwrap_or_else(|| "the data drive isn't ready".into()));
        }
        if s.drive_full {
            return Err("the data drive is full with only saved clips left".into());
        }
        if self.namer.is_none() {
            return Err("waiting for the run number".into());
        }
        Ok(())
    }

    /// Brings the captures in line with what the view and the recordings
    /// want.
    async fn reconcile(&mut self, now: Instant) {
        // Display: the camera the view wants, and only that one.
        let wanted = self.policy.view().camera;
        if self.feed.camera() != wanted {
            self.stop_display(now).await;
            self.backoff = self.settings.restart_min;
            if let Some(c) = wanted {
                self.start_display(now, c).await;
            }
        }
        // Recording.
        let cameras: Vec<Camera> = self.rec.iter().map(|r| r.camera).collect();
        for camera in cameras {
            let want = self.record_wanted(camera);
            let recording = self.caps.get(camera_name(camera)).is_some_and(|k| k.record);
            match want {
                Err(why) => {
                    if recording {
                        eprintln!(
                            "[camera] {} camera: recording stops: {why}",
                            camera_name(camera)
                        );
                        self.stop_recording(now, camera).await;
                    }
                    if let Some(r) = self.rec.iter_mut().find(|r| r.camera == camera) {
                        r.state = RecState::Idle(why);
                    }
                }
                Ok(()) if !recording => {
                    let waiting = self.rec.iter().any(|r| {
                        r.camera == camera
                            && matches!(r.state, RecState::Failed { retry_at, .. } if now < retry_at)
                    });
                    if !waiting {
                        self.start_recording(now, camera).await;
                    }
                }
                Ok(()) => {}
            }
        }
    }

    fn record_spec(&self, camera: Camera) -> Option<RecordSpec> {
        let cfg = self.rec_cfg()?;
        let namer = self.namer.clone()?;
        let name = camera_name(camera);
        Some(RecordSpec {
            segment: Duration::from_secs(u64::from(cfg.settings.segment_s)),
            cluster: Duration::from_secs(1),
            next_segment: Arc::new(move || match namer.lock() {
                Ok(mut n) => n.next(name),
                // A poisoned lock: a name that is never a segment, so
                // retention leaves it alone and the file is still kept.
                Err(_) => PathBuf::from(format!("/nonexistent/{name}-unnamed.mkv")),
            }),
        })
    }

    /// Starts a capture. Returns its generation.
    fn start_capture(
        &mut self,
        camera: Camera,
        display: bool,
        record: bool,
    ) -> Result<u64, String> {
        let name = camera_name(camera);
        let device = self
            .settings
            .device(camera)
            .map(String::from)
            .ok_or_else(|| format!("no {name} camera configured (--camera {name}=DEVICE)"))?;
        let record_spec = if record {
            Some(
                self.record_spec(camera)
                    .ok_or_else(|| "recording isn't ready".to_string())?,
            )
        } else {
            None
        };
        self.generation += 1;
        let generation = self.generation;
        let spec = CaptureSpec {
            camera,
            device: device.clone(),
            caps: self.settings.caps.clone(),
            sink: self.settings.sink.clone(),
            display,
            record: record_spec,
            generation,
        };
        let cap = self.media.start(spec, self.events_tx.clone())?;
        eprintln!(
            "[camera] {name} camera starting ({device}){}{}",
            if display { ", shown" } else { "" },
            if record { ", recording" } else { "" }
        );
        self.caps.insert(
            camera_name(camera),
            Cap {
                camera,
                cap,
                generation,
                display,
                record,
            },
        );
        Ok(generation)
    }

    async fn start_display(&mut self, now: Instant, camera: Camera) {
        let name = camera_name(camera);
        // A recording capture: add its display branch.
        if let Some(k) = self.caps.get_mut(camera_name(camera))
            && k.record
        {
            match k.cap.set_display(true) {
                Ok(()) => {
                    k.display = true;
                    self.feed = Feed::Starting {
                        camera,
                        generation: k.generation,
                        since: now,
                    };
                }
                Err(detail) => self.display_down(now, camera, detail),
            }
            return;
        }
        if self.settings.device(camera).is_none() {
            eprintln!("[camera] {name} camera chosen, but none is configured");
            self.feed = Feed::Down {
                camera,
                detail: format!("no {name} camera configured (--camera {name}=DEVICE)"),
                retry_at: None,
            };
            return;
        }
        // A display-only capture left from before: replace it.
        if let Some(k) = self.caps.remove(camera_name(camera)) {
            k.cap.stop().await;
        }
        // A recorded camera whose recording is down: try both now.
        let record =
            self.rec.iter().any(|r| r.camera == camera) && self.record_wanted(camera).is_ok();
        match self.start_capture(camera, true, record) {
            Ok(generation) => {
                self.feed = Feed::Starting {
                    camera,
                    generation,
                    since: now,
                };
                if record {
                    self.set_rec(
                        camera,
                        RecState::Starting {
                            generation,
                            since: now,
                        },
                    );
                }
            }
            Err(detail) => {
                self.display_down(now, camera, detail.clone());
                if record {
                    self.rec_failed(now, camera, detail);
                }
            }
        }
    }

    fn display_down(&mut self, now: Instant, camera: Camera, detail: String) {
        eprintln!(
            "[camera] {} camera: {detail}; retry in {} ms",
            camera_name(camera),
            self.backoff.as_millis()
        );
        self.feed = Feed::Down {
            camera,
            detail,
            retry_at: Some(now + self.backoff),
        };
        self.backoff = (self.backoff * 2).min(self.settings.restart_max);
    }

    /// Takes the camera off screen: removes the display branch of a
    /// recording capture, stops any other.
    async fn stop_display(&mut self, now: Instant) {
        let camera = match std::mem::replace(&mut self.feed, Feed::Off) {
            Feed::Starting { camera, .. } | Feed::Live { camera, .. } => {
                self.hide(camera).await;
                camera
            }
            Feed::Down { camera, .. } => camera,
            Feed::Off => return,
        };
        self.policy
            .handle(Input::CameraDown(camera), self.now_d(now));
    }

    async fn hide(&mut self, camera: Camera) {
        let Some(k) = self.caps.get_mut(camera_name(camera)) else {
            return;
        };
        if k.record {
            match k.cap.set_display(false) {
                Ok(()) => {
                    k.display = false;
                    return;
                }
                Err(e) => eprintln!(
                    "[camera] {} camera: the window wouldn't close ({e}): stopping the capture",
                    camera_name(camera)
                ),
            }
        }
        if let Some(k) = self.caps.remove(camera_name(camera)) {
            k.cap.stop().await;
            if k.record {
                self.rec_lost(camera);
            }
        }
    }

    /// The display branch failed: take it off screen and retry later.
    async fn fail_display(&mut self, now: Instant, detail: String) {
        let Some(camera) = self.feed.camera() else {
            return;
        };
        self.stop_display(now).await;
        self.display_down(now, camera, detail);
    }

    async fn start_recording(&mut self, now: Instant, camera: Camera) {
        // A display-only capture holds the camera: replace it with one that
        // does both, so the picture stays.
        let shown = matches!(self.feed, Feed::Starting { camera: c, .. } | Feed::Live { camera: c, .. } if c == camera);
        if let Some(k) = self.caps.remove(camera_name(camera)) {
            k.cap.stop().await;
        }
        match self.start_capture(camera, shown, true) {
            Ok(generation) => {
                self.set_rec(
                    camera,
                    RecState::Starting {
                        generation,
                        since: now,
                    },
                );
                if shown {
                    self.feed = Feed::Starting {
                        camera,
                        generation,
                        since: now,
                    };
                }
            }
            Err(detail) => {
                self.rec_failed(now, camera, detail.clone());
                if shown {
                    self.policy
                        .handle(Input::CameraDown(camera), self.now_d(now));
                    self.display_down(now, camera, detail);
                }
            }
        }
    }

    /// Recording must stop (no drive, drive full): finish the segment and
    /// keep the picture if it is shown.
    async fn stop_recording(&mut self, now: Instant, camera: Camera) {
        let Some(k) = self.caps.remove(camera_name(camera)) else {
            return;
        };
        let shown = k.display;
        k.cap.stop().await;
        self.rec_lost(camera);
        if shown {
            self.policy
                .handle(Input::CameraDown(camera), self.now_d(now));
            self.feed = Feed::Off;
            // reconcile() starts it again, display only.
        }
    }

    /// A capture failed (it ended, or its recording stopped getting frames):
    /// stop what is left of it; both branches retry after their backoffs.
    async fn fail_capture(&mut self, now: Instant, camera: Camera, detail: String) {
        let Some(k) = self.caps.remove(camera_name(camera)) else {
            return;
        };
        let shown = matches!(self.feed, Feed::Starting { camera: c, .. } | Feed::Live { camera: c, .. } if c == camera);
        k.cap.stop().await;
        if k.record {
            self.rec_failed(now, camera, detail.clone());
        }
        if shown {
            self.policy
                .handle(Input::CameraDown(camera), self.now_d(now));
            self.display_down(now, camera, detail);
        }
    }

    fn set_rec(&mut self, camera: Camera, state: RecState) {
        if let Some(r) = self.rec.iter_mut().find(|r| r.camera == camera) {
            r.state = state;
        }
    }

    /// The recording capture is gone; the segment it was writing is cut
    /// where it stopped.
    fn rec_lost(&mut self, camera: Camera) {
        if let Some(r) = self.rec.iter_mut().find(|r| r.camera == camera) {
            r.closed = None;
            if let Some(o) = r.segment.take() {
                sync_now(o);
            }
            r.state = RecState::Idle("stopped".into());
        }
    }

    fn rec_failed(&mut self, now: Instant, camera: Camera, detail: String) {
        let max = self.settings.restart_max;
        let Some(r) = self.rec.iter_mut().find(|r| r.camera == camera) else {
            return;
        };
        r.closed = None;
        if let Some(o) = r.segment.take() {
            sync_now(o);
        }
        eprintln!(
            "[camera] {} camera not recording: {detail}; retry in {} ms",
            camera_name(camera),
            r.backoff.as_millis()
        );
        r.state = RecState::Failed {
            detail,
            retry_at: now + r.backoff,
        };
        r.backoff = (r.backoff * 2).min(max);
    }

    /// Stops every capture (recordings get their end-of-stream), saves the
    /// segments a clip was waiting for, and marks a clean stop if every
    /// recording finished.
    async fn shutdown(&mut self, events: &mut mpsc::Receiver<Event>) {
        let now = Instant::now();
        self.stop_display(now).await;
        let caps: Vec<Cap> = self.caps.drain().map(|(_, k)| k).collect();
        let recorded = caps.iter().any(|k| k.record);
        let stops: Vec<_> = caps
            .into_iter()
            .map(|k| tokio::spawn(k.cap.stop()))
            .collect();
        let mut clean = true;
        for s in stops {
            clean &= s.await.unwrap_or(false);
        }
        // The segments the stops finished.
        while let Ok(e) = events.try_recv() {
            if let Event::SegmentClosed { path, .. } = e
                && let Some(camera) = self
                    .rec
                    .iter()
                    .find(|r| r.segment.as_ref().is_some_and(|o| o.path == path))
                    .map(|r| r.camera)
                && let Some(name) = name_of(camera, &path)
                && let Some(d) = &self.drive
            {
                let _ = d.jobs.send(Job::Finished(name)).await;
            }
        }
        for r in &mut self.rec {
            if let Some(o) = r.segment.take() {
                sync_now(o);
            }
            r.state = RecState::Idle("camera-manager stopped".into());
        }
        if let Some(d) = self.drive.take() {
            if clean {
                let (reply, rx) = oneshot::channel();
                if d.jobs.send(Job::CleanStop { reply }).await.is_ok() {
                    let _ = tokio::time::timeout(CLEAN_STOP_WAIT, rx).await;
                }
            } else if recorded {
                eprintln!(
                    "[camera] recording: a segment wasn't finished: no clean-stop marker, so the next \
                     start protects the last minutes"
                );
            }
        }
        // Nothing more is published: the watch senders go with the loop,
        // which ends every stream.
    }

    pub fn api_view(&self) -> pb::View {
        let v = self.policy.view();
        let mut out = pb::View {
            camera: v.camera.map_or(pb::Camera::Unspecified, pb_camera) as i32,
            reason: match v.why {
                Some(Why::Reverse) => pb::Reason::Reverse,
                Some(Why::Switch) => pb::Reason::Switch,
                None => pb::Reason::Unspecified,
            } as i32,
            reverse: match v.reverse {
                ReverseStatus::Off => pb::ReverseStatus::Off,
                ReverseStatus::Unknown => pb::ReverseStatus::Unknown,
                ReverseStatus::NotEngaged => pb::ReverseStatus::NotEngaged,
                ReverseStatus::Engaged => pb::ReverseStatus::Engaged,
            } as i32,
            blocked_by_speed: v.blocked_by_speed,
            ..Default::default()
        };
        if v.camera.is_some() && v.camera == self.feed.camera() {
            let (feed, detail) = match &self.feed {
                Feed::Starting { .. } | Feed::Off => (pb::FeedState::Starting, String::new()),
                Feed::Live { .. } => (pb::FeedState::Live, String::new()),
                Feed::Down { detail, .. } => (pb::FeedState::Unavailable, detail.clone()),
            };
            out.feed = feed as i32;
            out.feed_detail = detail;
        } else if v.camera.is_some() {
            // Wanted but not started yet: only between a policy change and
            // the reconcile that follows it.
            out.feed = pb::FeedState::Starting as i32;
        }
        out
    }

    pub fn api_recording(&self) -> pb::Recording {
        let Some(d) = &self.drive else {
            return pb::Recording::default();
        };
        let s = d.status.borrow();
        let checking = !s.ready && s.why_not.as_deref() == Some("checking the data drive");
        pb::Recording {
            cameras: self
                .rec
                .iter()
                .map(|r| {
                    let (state, detail) = match &r.state {
                        RecState::Idle(why) if checking => {
                            (pb::RecordingState::Starting, why.clone())
                        }
                        RecState::Idle(why) => (pb::RecordingState::NotRecording, why.clone()),
                        RecState::Starting { .. } => (pb::RecordingState::Starting, String::new()),
                        RecState::Recording { .. } => {
                            (pb::RecordingState::Recording, String::new())
                        }
                        RecState::Failed { detail, .. } => {
                            (pb::RecordingState::NotRecording, detail.clone())
                        }
                    };
                    pb::CameraRecording {
                        camera: pb_camera(r.camera) as i32,
                        state: state as i32,
                        detail,
                        segment: match (&r.state, &r.segment) {
                            (RecState::Recording { .. }, Some(o)) => o.name.file_name(),
                            _ => String::new(),
                        },
                    }
                })
                .collect(),
            drive_mounted: s.mounted,
            drive_free_bytes: s.free_bytes,
            recorded_bytes: s.recorded_bytes,
            protected_bytes: s.protected_bytes,
            protected_max_bytes: s.protected_max_bytes,
            clip_segments_pending: s.clip_pending,
            clock_trusted: self.rec_cfg().is_some_and(|c| c.clock.is_trusted()),
            problem: s.problem.clone().unwrap_or_default(),
        }
    }

    fn publish(&mut self) {
        let next = self.api_view();
        let changed = self.view_tx.send_if_modified(|v| {
            if *v == next {
                false
            } else {
                *v = next;
                true
            }
        });
        if changed {
            self.log_view();
        }
        let next = self.api_recording();
        let before = recording_states(&self.recording_tx.borrow());
        self.recording_tx.send_if_modified(|v| {
            if *v == next {
                false
            } else {
                *v = next;
                true
            }
        });
        // The log gets state changes, not each segment or byte.
        let now = recording_states(&self.recording_tx.borrow());
        if now != before {
            eprintln!("[camera] recording: {now}");
        }
    }

    fn log_view(&self) {
        eprintln!("[camera] view: {}", describe_view(&self.view_tx.borrow()));
    }
}

/// Syncs a finished or cut segment once more, off the loop's thread.
fn sync_now(o: Open) {
    let file = o
        .file
        .or_else(|| std::fs::File::open(&o.path).ok().map(Arc::new));
    if let Some(file) = file {
        tokio::task::spawn_blocking(move || {
            let _ = file.sync_data();
        });
    }
}

/// A segment's name from its path: `<root>/<camera>/<file>`.
fn name_of(camera: Camera, path: &Path) -> Option<SegmentName> {
    SegmentName::parse(camera_name(camera), path.file_name()?.to_str()?)
}

/// A view as one line, for the service's log and `camera-ctl`:
/// `rear (switch), live; reverse off`.
pub fn describe_view(v: &pb::View) -> String {
    let camera = pb::Camera::try_from(v.camera).unwrap_or(pb::Camera::Unspecified);
    let line = if camera == pb::Camera::Unspecified {
        "no camera".to_string()
    } else {
        let reason = pb::Reason::try_from(v.reason).unwrap_or(pb::Reason::Unspecified);
        let feed = pb::FeedState::try_from(v.feed).unwrap_or(pb::FeedState::Unspecified);
        let mut s = format!(
            "{} ({}), {}",
            camera
                .as_str_name()
                .trim_start_matches("CAMERA_")
                .to_lowercase(),
            reason
                .as_str_name()
                .trim_start_matches("REASON_")
                .to_lowercase(),
            feed.as_str_name()
                .trim_start_matches("FEED_STATE_")
                .to_lowercase()
        );
        if !v.feed_detail.is_empty() {
            s.push_str(": ");
            s.push_str(&v.feed_detail);
        }
        s
    };
    let reverse = pb::ReverseStatus::try_from(v.reverse).unwrap_or(pb::ReverseStatus::Unspecified);
    format!(
        "{line}; reverse {}{}",
        reverse
            .as_str_name()
            .trim_start_matches("REVERSE_STATUS_")
            .to_lowercase(),
        if v.blocked_by_speed {
            "; hidden by the speed limit"
        } else {
            ""
        }
    )
}

/// Recording as one line: `front recording (b00003-s000012.mkv), rear not
/// recording: no frame for 1000 ms; 412.3 GB free`.
pub fn describe_recording(r: &pb::Recording) -> String {
    if r.cameras.is_empty() {
        return "off".into();
    }
    let mut parts: Vec<String> = r
        .cameras
        .iter()
        .map(|c| {
            let camera = pb::Camera::try_from(c.camera)
                .unwrap_or(pb::Camera::Unspecified)
                .as_str_name()
                .trim_start_matches("CAMERA_")
                .to_lowercase();
            let state = pb::RecordingState::try_from(c.state)
                .unwrap_or(pb::RecordingState::Unspecified)
                .as_str_name()
                .trim_start_matches("RECORDING_STATE_")
                .to_lowercase()
                .replace('_', " ");
            let mut s = format!("{camera} {state}");
            if !c.segment.is_empty() {
                s.push_str(&format!(" ({})", c.segment));
            }
            if !c.detail.is_empty() {
                s.push_str(&format!(": {}", c.detail));
            }
            s
        })
        .collect();
    if r.drive_mounted {
        parts.push(format!(
            "{:.1} GB free, saved clips {:.1} of {:.1} GB",
            r.drive_free_bytes as f64 / 1e9,
            r.protected_bytes as f64 / 1e9,
            r.protected_max_bytes as f64 / 1e9
        ));
    }
    if r.clip_segments_pending > 0 {
        parts.push(format!("{} segments to save", r.clip_segments_pending));
    }
    if !r.problem.is_empty() {
        parts.push(r.problem.clone());
    }
    parts.join("; ")
}

/// Recording's states and problems, without segment names or sizes.
fn recording_states(r: &pb::Recording) -> String {
    let mut brief = r.clone();
    for c in &mut brief.cameras {
        c.segment.clear();
    }
    brief.drive_mounted = false; // describe_recording leaves the sizes out
    brief.clip_segments_pending = 0;
    describe_recording(&brief)
}

pub fn pb_camera(c: Camera) -> pb::Camera {
    match c {
        Camera::Left => pb::Camera::Left,
        Camera::Right => pb::Camera::Right,
        Camera::Rear => pb::Camera::Rear,
        Camera::Front => pb::Camera::Front,
    }
}

/// A switch move from the API. `None` for an unspecified or unknown value.
pub fn move_from_pb(v: i32) -> Option<Move> {
    match pb::SwitchMove::try_from(v).ok()? {
        pb::SwitchMove::Unspecified => None,
        pb::SwitchMove::Left => Some(Move::Left),
        pb::SwitchMove::Right => Some(Move::Right),
        pb::SwitchMove::Back => Some(Move::Back),
        pb::SwitchMove::Forward => Some(Move::Forward),
        pb::SwitchMove::Press => Some(Move::Press),
    }
}

fn move_name(m: Move) -> &'static str {
    match m {
        Move::Left => "left",
        Move::Right => "right",
        Move::Back => "back",
        Move::Forward => "forward",
        Move::Press => "press",
    }
}
