//! Recording through the control loop (ADR-0027), with a fake media in
//! place of GStreamer: it writes real segment files, named by the loop's
//! namer, into a temporary directory, and reports frames and segments as
//! the GStreamer media does. Its behaviour depends on the device name:
//!
//! - `ok`: frames on both branches, a new segment every 100 ms
//! - `stall`: five recording frames, then nothing (the capture stays up)
//! - `dies`: a few frames, then the capture ends with an error
//! - `unclean`: like `ok`, but its stop can't finish the segment
//!
//! `[SIM]`.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use camera_manager::config::{RecordingConfig, Settings};
use camera_manager::drive::Clock;
use camera_manager::manager::{Command, Manager, Watches};
use camera_manager::media::{Branch, Capture, CaptureSpec, Event, Media, StopFuture};
use camera_policy::{Camera, Move};
use f250_proto::camera::v1 as pb;
use tokio::sync::{mpsc, oneshot, watch};

const SEGMENT_EVERY: Duration = Duration::from_millis(100);
const FRAME_EVERY: Duration = Duration::from_millis(20);
const SOON: Duration = Duration::from_secs(5);

/// What the fake media did, for the tests to check.
#[derive(Default)]
struct Log {
    /// (camera, display, record) per start.
    starts: Vec<(Camera, bool, bool)>,
    /// (camera, on) per set_display.
    displays: Vec<(Camera, bool)>,
    segment_lengths: Vec<Duration>,
}

#[derive(Clone)]
struct FakeMedia {
    log: Arc<Mutex<Log>>,
    can_record: Result<(), String>,
}

impl FakeMedia {
    fn new() -> Self {
        FakeMedia {
            log: Arc::default(),
            can_record: Ok(()),
        }
    }

    fn starts(&self, camera: Camera) -> Vec<(bool, bool)> {
        self.log
            .lock()
            .expect("log")
            .starts
            .iter()
            .filter(|(c, ..)| *c == camera)
            .map(|(_, d, r)| (*d, *r))
            .collect()
    }

    fn displays(&self, camera: Camera) -> Vec<bool> {
        self.log
            .lock()
            .expect("log")
            .displays
            .iter()
            .filter(|(c, _)| *c == camera)
            .map(|(_, on)| *on)
            .collect()
    }
}

struct FakeCapture {
    camera: Camera,
    generation: u64,
    display: Arc<AtomicBool>,
    stop: Option<oneshot::Sender<oneshot::Sender<bool>>>,
    log: Arc<Mutex<Log>>,
}

impl Capture for FakeCapture {
    fn generation(&self) -> u64 {
        self.generation
    }

    fn set_display(&mut self, on: bool) -> Result<(), String> {
        self.display.store(on, Ordering::SeqCst);
        if let Ok(mut l) = self.log.lock() {
            l.displays.push((self.camera, on));
        }
        Ok(())
    }

    fn stop(mut self: Box<Self>) -> StopFuture {
        let stop = self.stop.take();
        Box::pin(async move {
            let Some(stop) = stop else { return true };
            let (tx, rx) = oneshot::channel();
            if stop.send(tx).is_err() {
                return true; // it had already ended
            }
            rx.await.unwrap_or(false)
        })
    }
}

impl Media for FakeMedia {
    fn can_record(&self) -> Result<(), String> {
        self.can_record.clone()
    }

    fn start(
        &mut self,
        spec: CaptureSpec,
        events: mpsc::Sender<Event>,
    ) -> Result<Box<dyn Capture>, String> {
        {
            let mut l = self.log.lock().expect("log");
            l.starts
                .push((spec.camera, spec.display, spec.record.is_some()));
            if let Some(r) = &spec.record {
                l.segment_lengths.push(r.segment);
            }
        }
        let display = Arc::new(AtomicBool::new(spec.display));
        let (stop_tx, mut stop_rx) = oneshot::channel::<oneshot::Sender<bool>>();
        let g = spec.generation;
        let device = spec.device.clone();
        let shown = display.clone();
        tokio::spawn(async move {
            let mut segment: Option<PathBuf> = None;
            let mut next_segment = tokio::time::Instant::now();
            let mut frames = 0u32;
            let mut tick = tokio::time::interval(FRAME_EVERY);
            loop {
                tokio::select! {
                    reply = &mut stop_rx => {
                        let clean = device != "unclean";
                        if clean && let Some(p) = segment.take() {
                            let _ = events.send(Event::SegmentClosed { generation: g, path: p }).await;
                        }
                        if let Ok(reply) = reply {
                            let _ = reply.send(clean);
                        }
                        return;
                    }
                    _ = tick.tick() => {}
                }
                frames += 1;
                if device == "dies" && frames > 4 {
                    let _ = events
                        .send(Event::Ended {
                            generation: g,
                            detail: "Could not read from resource".into(),
                        })
                        .await;
                    // Wait for the loop's stop.
                    if let Ok(reply) = stop_rx.await {
                        let _ = reply.send(false);
                    }
                    return;
                }
                let recording = device != "stall" || frames <= 5;
                if let Some(r) = spec.record.as_ref().filter(|_| recording) {
                    if tokio::time::Instant::now() >= next_segment {
                        if let Some(p) = segment.take() {
                            let _ = events
                                .send(Event::SegmentClosed {
                                    generation: g,
                                    path: p,
                                })
                                .await;
                        }
                        let p = (r.next_segment)();
                        std::fs::write(&p, b"").expect("segment file");
                        let _ = events
                            .send(Event::SegmentOpened {
                                generation: g,
                                path: p.clone(),
                            })
                            .await;
                        segment = Some(p);
                        next_segment += SEGMENT_EVERY;
                    }
                    if let Some(p) = &segment {
                        use std::io::Write;
                        let mut f = std::fs::OpenOptions::new()
                            .append(true)
                            .open(p)
                            .expect("append");
                        f.write_all(&[0u8; 100]).expect("write");
                    }
                    let _ = events.try_send(Event::Frame {
                        generation: g,
                        branch: Branch::Record,
                    });
                }
                if shown.load(Ordering::SeqCst) {
                    let _ = events.try_send(Event::Frame {
                        generation: g,
                        branch: Branch::Display,
                    });
                }
            }
        });
        Ok(Box::new(FakeCapture {
            camera: spec.camera,
            generation: g,
            display,
            stop: Some(stop_tx),
            log: self.log.clone(),
        }))
    }
}

fn temp(test: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("f250-rec-{test}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("temp dir");
    dir
}

fn settings(root: &Path, cameras: &[(Camera, &str)], record: &[Camera]) -> Settings {
    Settings {
        cameras: cameras
            .iter()
            .map(|(c, d)| (*c, (*d).to_string()))
            .collect(),
        caps: "image/jpeg,width=640,height=480 ! jpegdec".into(),
        sink: "fakesink".into(),
        gst_launch: "unused".into(),
        frame_timeout: Duration::from_millis(250),
        start_timeout: Duration::from_millis(400),
        restart_min: Duration::from_millis(200),
        restart_max: Duration::from_millis(400),
        policy: camera_policy::Config::default(),
        recording: Some(RecordingConfig {
            cameras: record.to_vec(),
            root: root.to_path_buf(),
            mount: None,
            settings: recording::settings::Settings::default(),
            clock: Clock::Untrusted,
        }),
    }
}

struct Rig {
    root: PathBuf,
    media: FakeMedia,
    cmds: mpsc::Sender<Command>,
    view: watch::Receiver<pb::View>,
    recording: watch::Receiver<pb::Recording>,
    done: tokio::task::JoinHandle<()>,
}

fn rig(root: PathBuf, s: Settings, media: FakeMedia) -> Rig {
    let (manager, Watches { view, recording }) = Manager::new(s, Box::new(media.clone()));
    let (cmds, rx) = mpsc::channel(8);
    let done = tokio::spawn(manager.run(rx));
    Rig {
        root,
        media,
        cmds,
        view,
        recording,
        done,
    }
}

fn state(r: &pb::Recording, camera: pb::Camera) -> Option<&pb::CameraRecording> {
    r.cameras.iter().find(|c| c.camera == camera as i32)
}

fn is(r: &pb::Recording, camera: pb::Camera, s: pb::RecordingState) -> bool {
    state(r, camera).is_some_and(|c| c.state == s as i32)
}

impl Rig {
    async fn mv(&self, mv: Move) -> pb::View {
        let (reply, rx) = oneshot::channel();
        self.cmds
            .send(Command::Move {
                mv,
                source: "test".into(),
                reply,
            })
            .await
            .expect("loop running");
        rx.await.expect("reply")
    }

    async fn save(&self) -> pb::SaveClipResponse {
        let (reply, rx) = oneshot::channel();
        self.cmds
            .send(Command::SaveClip {
                source: "test".into(),
                reply,
            })
            .await
            .expect("loop running");
        rx.await.expect("reply")
    }

    async fn until(&mut self, what: &str, pred: impl Fn(&pb::Recording) -> bool) -> pb::Recording {
        let deadline = tokio::time::Instant::now() + SOON;
        loop {
            {
                let v = self.recording.borrow_and_update();
                if pred(&v) {
                    return v.clone();
                }
            }
            let left = deadline.saturating_duration_since(tokio::time::Instant::now());
            if tokio::time::timeout(left, self.recording.changed())
                .await
                .is_err()
            {
                panic!(
                    "timed out waiting for {what}; last {:?}",
                    *self.recording.borrow()
                );
            }
        }
    }

    async fn until_view(&mut self, what: &str, pred: impl Fn(&pb::View) -> bool) -> pb::View {
        let deadline = tokio::time::Instant::now() + SOON;
        loop {
            {
                let v = self.view.borrow_and_update();
                if pred(&v) {
                    return v.clone();
                }
            }
            let left = deadline.saturating_duration_since(tokio::time::Instant::now());
            if tokio::time::timeout(left, self.view.changed())
                .await
                .is_err()
            {
                panic!(
                    "timed out waiting for {what}; last {:?}",
                    *self.view.borrow()
                );
            }
        }
    }

    fn files(&self, sub: &str) -> Vec<String> {
        let mut v: Vec<String> = std::fs::read_dir(self.root.join(sub))
            .map(|d| {
                d.filter_map(|e| e.ok())
                    .map(|e| e.file_name().to_string_lossy().into_owned())
                    .collect()
            })
            .unwrap_or_default();
        v.sort();
        v
    }

    async fn stop(self) -> PathBuf {
        self.cmds
            .send(Command::Shutdown)
            .await
            .expect("loop running");
        tokio::time::timeout(SOON, self.done)
            .await
            .expect("loop stopped")
            .expect("no panic");
        self.root
    }
}

fn live(v: &pb::View) -> bool {
    v.feed == pb::FeedState::Live as i32
}

const FRONT: pb::Camera = pb::Camera::Front;
const REAR: pb::Camera = pb::Camera::Rear;
const RECORDING: pb::RecordingState = pb::RecordingState::Recording;
const NOT_RECORDING: pb::RecordingState = pb::RecordingState::NotRecording;

#[tokio::test]
async fn front_and_rear_record_into_named_segments_on_their_own() {
    let root = temp("both");
    let s = settings(
        &root,
        &[(Camera::Front, "ok"), (Camera::Rear, "ok")],
        &[Camera::Front, Camera::Rear],
    );
    let mut r = rig(root, s, FakeMedia::new());
    let rec = r
        .until("both recording", |x| {
            is(x, FRONT, RECORDING) && is(x, REAR, RECORDING)
        })
        .await;
    assert!(rec.drive_mounted, "no mount check: counts as mounted");
    assert!(!rec.clock_trusted);
    let seg = &state(&rec, FRONT).expect("front").segment;
    assert!(seg.starts_with("b00001-s0000"), "{seg}");
    // Untrusted clock: no wall time in the name (decision 10).
    assert_eq!(seg.len(), "b00001-s000000.mkv".len(), "{seg}");
    tokio::time::sleep(Duration::from_millis(350)).await;
    assert!(r.files("front").len() >= 3, "{:?}", r.files("front"));
    assert!(r.files("rear").len() >= 3);
    assert_eq!(r.files("front")[0], "b00001-s000000.mkv");
    // Nothing on screen, one capture per camera, recording only.
    assert_eq!(r.media.starts(Camera::Front), vec![(false, true)]);
    assert_eq!(
        r.media.log.lock().expect("log").segment_lengths[0],
        Duration::from_secs(60),
        "RECORD_SEGMENT_S"
    );
    let root = r.stop().await;
    // A clean stop leaves the marker for this run.
    let marker = std::fs::read_to_string(root.join(".state/clean-stop")).expect("marker");
    assert_eq!(marker.trim(), "1");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn a_trusted_clock_puts_the_time_in_the_name() {
    let root = temp("clock");
    let mut s = settings(&root, &[(Camera::Rear, "ok")], &[Camera::Rear]);
    if let Some(rc) = s.recording.as_mut() {
        rc.clock = Clock::Trusted;
    }
    let mut r = rig(root, s, FakeMedia::new());
    let rec = r.until("rear recording", |x| is(x, REAR, RECORDING)).await;
    let seg = &state(&rec, REAR).expect("rear").segment;
    assert!(seg.ends_with("Z.mkv"), "{seg}");
    assert!(rec.clock_trusted);
    let root = r.stop().await;
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn showing_a_recorded_camera_adds_a_window_to_the_same_capture() {
    let root = temp("show");
    let s = settings(&root, &[(Camera::Rear, "ok")], &[Camera::Rear]);
    let mut r = rig(root, s, FakeMedia::new());
    r.until("rear recording", |x| is(x, REAR, RECORDING)).await;
    r.mv(Move::Back).await;
    r.until_view("rear live", live).await;
    r.mv(Move::Press).await;
    tokio::time::sleep(Duration::from_millis(100)).await;
    // One capture throughout; only its window came and went.
    assert_eq!(r.media.starts(Camera::Rear), vec![(false, true)]);
    assert_eq!(r.media.displays(Camera::Rear), vec![true, false]);
    let rec = r.recording.borrow().clone();
    assert!(is(&rec, REAR, RECORDING), "{rec:?}");
    let root = r.stop().await;
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn a_camera_that_isnt_recorded_runs_only_while_shown() {
    let root = temp("left");
    let s = settings(
        &root,
        &[(Camera::Rear, "ok"), (Camera::Left, "ok")],
        &[Camera::Rear],
    );
    let mut r = rig(root, s, FakeMedia::new());
    r.until("rear recording", |x| is(x, REAR, RECORDING)).await;
    assert!(r.media.starts(Camera::Left).is_empty());
    r.mv(Move::Left).await;
    r.until_view("left live", live).await;
    assert_eq!(r.media.starts(Camera::Left), vec![(true, false)]);
    assert!(!r.root.join("left").exists(), "left is never recorded");
    let root = r.stop().await;
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn without_the_data_drive_nothing_records_and_the_camera_still_shows() {
    let root = temp("nodrive");
    let not_a_mount = root.join("storage");
    std::fs::create_dir_all(&not_a_mount).expect("dir");
    let mut s = settings(&root, &[(Camera::Rear, "ok")], &[Camera::Rear]);
    if let Some(rc) = s.recording.as_mut() {
        rc.root = not_a_mount.join("video");
        rc.mount = Some(not_a_mount.clone());
    }
    let mut r = rig(root, s, FakeMedia::new());
    let rec = r
        .until("not recording", |x| is(x, REAR, NOT_RECORDING))
        .await;
    let detail = &state(&rec, REAR).expect("rear").detail;
    assert!(detail.contains("no data drive mounted"), "{detail}");
    assert!(!rec.drive_mounted);
    assert!(
        !not_a_mount.join("video").exists(),
        "nothing written without the drive"
    );
    r.mv(Move::Back).await;
    r.until_view("rear live", live).await;
    assert_eq!(r.media.starts(Camera::Rear), vec![(true, false)]);
    let saved = r.save().await;
    assert!(!saved.saved);
    assert!(
        saved.detail.contains("nothing is recording"),
        "{}",
        saved.detail
    );
    let root = r.stop().await;
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn media_that_cant_record_says_why() {
    let root = temp("cant");
    let s = settings(&root, &[(Camera::Rear, "ok")], &[Camera::Rear]);
    let mut media = FakeMedia::new();
    media.can_record = Err("built without GStreamer".into());
    let mut r = rig(root, s, media);
    let rec = r
        .until("not recording", |x| is(x, REAR, NOT_RECORDING))
        .await;
    assert_eq!(
        state(&rec, REAR).expect("rear").detail,
        "built without GStreamer"
    );
    let root = r.stop().await;
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn raw_video_isnt_recorded() {
    let root = temp("raw");
    let mut s = settings(&root, &[(Camera::Rear, "ok")], &[Camera::Rear]);
    s.caps = "video/x-raw,format=YUY2".into();
    let mut r = rig(root, s, FakeMedia::new());
    let rec = r
        .until("not recording", |x| is(x, REAR, NOT_RECORDING))
        .await;
    let d = &state(&rec, REAR).expect("rear").detail;
    assert!(d.contains("raw video isn't recorded"), "{d}");
    let root = r.stop().await;
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn a_recording_without_frames_is_reported_and_restarted() {
    let root = temp("stall");
    let s = settings(&root, &[(Camera::Rear, "stall")], &[Camera::Rear]);
    let mut r = rig(root, s, FakeMedia::new());
    r.until("recording", |x| is(x, REAR, RECORDING)).await;
    let rec = r
        .until("not recording", |x| is(x, REAR, NOT_RECORDING))
        .await;
    let d = &state(&rec, REAR).expect("rear").detail;
    assert!(d.contains("no frame for 250 ms"), "{d}");
    // Restarted after the backoff.
    r.until("recording again", |x| is(x, REAR, RECORDING)).await;
    assert!(r.media.starts(Camera::Rear).len() >= 2);
    let root = r.stop().await;
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn a_capture_that_dies_takes_the_picture_down_and_comes_back() {
    let root = temp("dies");
    let s = settings(&root, &[(Camera::Rear, "dies")], &[Camera::Rear]);
    let mut r = rig(root, s, FakeMedia::new());
    r.mv(Move::Back).await;
    let rec = r
        .until("not recording", |x| is(x, REAR, NOT_RECORDING))
        .await;
    assert!(
        state(&rec, REAR)
            .expect("rear")
            .detail
            .contains("Could not read"),
        "{rec:?}"
    );
    let v = r
        .until_view("unavailable", |v| {
            v.feed == pb::FeedState::Unavailable as i32
        })
        .await;
    assert!(
        v.feed_detail.contains("Could not read"),
        "{}",
        v.feed_detail
    );
    // Retried: the shown camera comes back recording too.
    tokio::time::sleep(Duration::from_millis(600)).await;
    assert!(
        r.media
            .starts(Camera::Rear)
            .iter()
            .filter(|(d, rec)| *d && *rec)
            .count()
            >= 2,
        "{:?}",
        r.media.starts(Camera::Rear)
    );
    let root = r.stop().await;
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn save_clip_protects_the_minutes_before_and_the_segments_after() {
    let root = temp("clip");
    let s = settings(
        &root,
        &[(Camera::Front, "ok"), (Camera::Rear, "ok")],
        &[Camera::Front, Camera::Rear],
    );
    let mut r = rig(root, s, FakeMedia::new());
    r.until("both recording", |x| {
        is(x, FRONT, RECORDING) && is(x, REAR, RECORDING)
    })
    .await;
    tokio::time::sleep(Duration::from_millis(450)).await;
    let saved = r.save().await;
    assert!(saved.saved, "{}", saved.detail);
    // 120 s before at 60 s segments: two finished segments per camera now;
    // the one being written and one more (60 s after) as they finish.
    assert_eq!(saved.segments_protected, 4, "{}", saved.detail);
    assert_eq!(saved.segments_to_come, 4);
    // Two now; the next may already have finished and joined them.
    assert!((2..=3).contains(&r.files("protected/front").len()));
    let rec = r
        .until("the clip complete", |x| {
            x.clip_segments_pending == 0 && x.protected_bytes > 0
        })
        .await;
    assert!(rec.problem.is_empty(), "{}", rec.problem);
    assert_eq!(r.files("protected/front").len(), 4);
    assert_eq!(r.files("protected/rear").len(), 4);
    // Saved clips are out of retention's reach and the recording went on.
    let front = r.files("front");
    assert!(!front.is_empty());
    for f in r.files("protected/front") {
        assert!(!front.contains(&f), "{f} in both");
    }
    let root = r.stop().await;
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn save_clip_is_refused_when_the_saved_clips_are_full() {
    let root = temp("clipfull");
    let mut s = settings(&root, &[(Camera::Rear, "ok")], &[Camera::Rear]);
    if let Some(rc) = s.recording.as_mut() {
        rc.settings.protected_max_bytes = 50;
    }
    let mut r = rig(root, s, FakeMedia::new());
    r.until("recording", |x| is(x, REAR, RECORDING)).await;
    tokio::time::sleep(Duration::from_millis(350)).await;
    let saved = r.save().await;
    assert!(!saved.saved);
    assert!(
        saved.detail.contains("saved clips are full"),
        "{}",
        saved.detail
    );
    assert!(r.files("protected/rear").is_empty());
    let root = r.stop().await;
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn retention_keeps_the_size_limit_and_never_the_segment_being_written() {
    let root = temp("retention");
    let mut s = settings(&root, &[(Camera::Rear, "ok")], &[Camera::Rear]);
    if let Some(rc) = s.recording.as_mut() {
        // About two finished segments of the fake's ~500 bytes.
        rc.settings.max_bytes = 1_200;
        rc.settings.min_free_bytes = 0;
    }
    let mut r = rig(root, s, FakeMedia::new());
    r.until("recording", |x| is(x, REAR, RECORDING)).await;
    tokio::time::sleep(Duration::from_millis(900)).await;
    let files = r.files("rear");
    assert!(
        (2..=5).contains(&files.len()),
        "old segments go, recent ones stay: {files:?}"
    );
    assert_ne!(files[0], "b00001-s000000.mkv", "the oldest went first");
    let rec = r.recording.borrow().clone();
    let writing = state(&rec, REAR).expect("rear").segment.clone();
    assert!(
        writing.is_empty() || files.contains(&writing),
        "{writing} deleted while written"
    );
    let root = r.stop().await;
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn a_full_drive_stops_recording_and_says_so() {
    let root = temp("full");
    let mut s = settings(&root, &[(Camera::Rear, "ok")], &[Camera::Rear]);
    if let Some(rc) = s.recording.as_mut() {
        rc.settings.min_free_bytes = u64::MAX / 2;
    }
    let mut r = rig(root, s, FakeMedia::new());
    let rec = r
        .until("drive full", |x| {
            !x.problem.is_empty() && is(x, REAR, NOT_RECORDING)
        })
        .await;
    assert!(rec.problem.contains("drive is full"), "{}", rec.problem);
    let root = r.stop().await;
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn after_an_unclean_stop_the_last_minutes_are_protected() {
    let root = temp("unclean");
    let s = settings(&root, &[(Camera::Rear, "unclean")], &[Camera::Rear]);
    let mut r = rig(root.clone(), s, FakeMedia::new());
    r.until("recording", |x| is(x, REAR, RECORDING)).await;
    tokio::time::sleep(Duration::from_millis(450)).await;
    let before = r.files("rear");
    let root = r.stop().await;
    assert!(
        !root.join(".state/clean-stop").exists(),
        "a segment that wasn't finished: no clean-stop marker"
    );
    // The next start protects them before anything else.
    let s = settings(&root, &[(Camera::Rear, "ok")], &[Camera::Rear]);
    let mut r = rig(root, s, FakeMedia::new());
    let rec = r
        .until("run 2 recording", |x| {
            state(x, REAR).is_some_and(|c| c.segment.starts_with("b00002-"))
        })
        .await;
    assert!(rec.protected_bytes > 0);
    let saved = r.files("protected/rear");
    // Five minutes at 60 s segments, plus the cut one: every segment of the
    // short first run.
    assert_eq!(saved, before, "{saved:?} vs {before:?}");
    let root = r.stop().await;
    let _ = std::fs::remove_dir_all(root);
}
