//! The in-process GStreamer media with real pipelines: `videotestsrc`
//! encoded to MJPEG stands in for the camera, `fakesink` for the window.
//! Needs GStreamer with gst-plugins-good (`make linux-test`); built only
//! with the `gstreamer` feature. `[SIM]`: no camera, no Pi.
#![cfg(feature = "gstreamer")]

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::Duration;

use camera_manager::config::{RecordingConfig, Settings};
use camera_manager::drive::Clock;
use camera_manager::gst::GstMedia;
use camera_manager::gst::gstreamer as gst;
use camera_manager::manager::{Command, Manager, Watches};
use camera_manager::media::{Branch, CaptureSpec, Event, Media, RecordSpec};
use camera_policy::{Camera, Move};
use f250_proto::camera::v1 as pb;
use gst::prelude::*;
use tokio::sync::{mpsc, oneshot};

const SOURCE: &str = "videotestsrc is-live=true pattern=ball ! video/x-raw,width=320,height=240,framerate=30/1 ! jpegenc";
const CAPS: &str = "image/jpeg,width=320,height=240,framerate=30/1 ! jpegdec";
const SINK: &str = "fakesink sync=false";

fn temp(test: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("f250-gst-{test}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("temp dir");
    dir
}

fn record_spec(dir: &Path, segment: Duration) -> RecordSpec {
    let n = Arc::new(AtomicU32::new(0));
    let dir = dir.to_path_buf();
    RecordSpec {
        segment,
        cluster: Duration::from_secs(1),
        next_segment: Arc::new(move || {
            dir.join(format!("seg-{}.mkv", n.fetch_add(1, Ordering::SeqCst)))
        }),
    }
}

fn spec(display: bool, record: Option<RecordSpec>) -> CaptureSpec {
    CaptureSpec {
        camera: Camera::Rear,
        device: "/dev/unused".into(),
        caps: CAPS.into(),
        sink: SINK.into(),
        display,
        record,
        generation: 7,
    }
}

#[derive(Default, Debug)]
struct Seen {
    display: u32,
    record: u32,
    opened: Vec<PathBuf>,
    closed: Vec<PathBuf>,
    ended: Vec<String>,
}

/// Collects events for `d`.
async fn collect(rx: &mut mpsc::Receiver<Event>, d: Duration) -> Seen {
    let mut s = Seen::default();
    let deadline = tokio::time::Instant::now() + d;
    while let Ok(Some(e)) = tokio::time::timeout_at(deadline, rx.recv()).await {
        match e {
            Event::Frame {
                branch: Branch::Display,
                generation,
            } => {
                assert_eq!(generation, 7);
                s.display += 1;
            }
            Event::Frame {
                branch: Branch::Record,
                ..
            } => s.record += 1,
            Event::SegmentOpened { path, .. } => s.opened.push(path),
            Event::SegmentClosed { path, .. } => s.closed.push(path),
            Event::Ended { detail, .. } => s.ended.push(detail),
        }
    }
    s
}

/// Frames a Matroska file holds, read back with matroskademux.
fn frames_in(path: &Path) -> u32 {
    let p = gst::parse::launch(&format!(
        "filesrc location={} ! matroskademux ! fakesink name=out sync=false",
        path.display()
    ))
    .expect("readback pipeline")
    .downcast::<gst::Pipeline>()
    .expect("pipeline");
    let n = Arc::new(AtomicU32::new(0));
    let out = p.by_name("out").expect("out");
    let pad = out.static_pad("sink").expect("pad");
    let c = n.clone();
    pad.add_probe(gst::PadProbeType::BUFFER, move |_, _| {
        c.fetch_add(1, Ordering::SeqCst);
        gst::PadProbeReturn::Ok
    });
    p.set_state(gst::State::Playing).expect("play");
    let bus = p.bus().expect("bus");
    for msg in bus.iter_timed(gst::ClockTime::from_seconds(10)) {
        match msg.view() {
            gst::MessageView::Eos(_) => break,
            gst::MessageView::Error(e) => panic!("{} unreadable: {}", path.display(), e.error()),
            _ => {}
        }
    }
    let _ = p.set_state(gst::State::Null);
    n.load(Ordering::SeqCst)
}

#[tokio::test]
async fn records_matroska_segments_that_read_back() {
    let dir = temp("segments");
    let mut media = GstMedia::with_source(SOURCE).expect("gst");
    media
        .can_record()
        .expect("splitmuxsink and matroskamux present");
    let (tx, mut rx) = mpsc::channel(4096);
    let cap = media
        .start(
            spec(false, Some(record_spec(&dir, Duration::from_secs(1)))),
            tx,
        )
        .expect("start");
    let seen = collect(&mut rx, Duration::from_millis(2600)).await;
    assert!(seen.ended.is_empty(), "{:?}", seen.ended);
    assert_eq!(seen.display, 0, "no window asked for");
    assert!(seen.record > 40, "recording frames: {}", seen.record);
    assert!(seen.opened.len() >= 2, "segments: {:?}", seen.opened);
    assert_eq!(seen.opened[0], dir.join("seg-0.mkv"), "named by the loop");
    assert!(!seen.closed.is_empty());
    assert!(cap.stop().await, "end-of-stream finished the last segment");
    // The stop's fragment-closed for the last segment.
    let after = collect(&mut rx, Duration::from_millis(300)).await;
    let last = seen.opened.last().expect("a segment");
    assert!(
        after.closed.contains(last) || seen.closed.contains(last),
        "the last segment was finished: {after:?}"
    );
    for p in &seen.opened {
        let bytes = std::fs::read(p).expect("segment");
        assert_eq!(
            &bytes[..4],
            &[0x1A, 0x45, 0xDF, 0xA3],
            "{} is Matroska",
            p.display()
        );
        let n = frames_in(p);
        assert!(n > 10, "{} has {n} frames", p.display());
    }
    let _ = std::fs::remove_dir_all(dir);
}

#[tokio::test]
async fn the_window_comes_and_goes_while_the_recording_runs() {
    let dir = temp("display");
    let mut media = GstMedia::with_source(SOURCE).expect("gst");
    let (tx, mut rx) = mpsc::channel(4096);
    let mut cap = media
        .start(
            spec(false, Some(record_spec(&dir, Duration::from_secs(5)))),
            tx,
        )
        .expect("start");
    let before = collect(&mut rx, Duration::from_millis(500)).await;
    assert_eq!(before.display, 0);
    cap.set_display(true).expect("show");
    let shown = collect(&mut rx, Duration::from_millis(700)).await;
    assert!(shown.display > 10, "display frames: {}", shown.display);
    assert!(shown.record > 10);
    cap.set_display(false).expect("hide");
    let _ = collect(&mut rx, Duration::from_millis(100)).await; // in flight
    let hidden = collect(&mut rx, Duration::from_millis(500)).await;
    assert_eq!(hidden.display, 0, "no window after hiding");
    assert!(
        hidden.record > 5,
        "the recording went on: {}",
        hidden.record
    );
    assert!(hidden.ended.is_empty() && shown.ended.is_empty());
    assert!(cap.stop().await);
    let _ = std::fs::remove_dir_all(dir);
}

#[tokio::test]
async fn a_camera_that_isnt_recorded_only_shows() {
    let mut media = GstMedia::with_source(SOURCE).expect("gst");
    let (tx, mut rx) = mpsc::channel(4096);
    let cap = media.start(spec(true, None), tx).expect("start");
    let seen = collect(&mut rx, Duration::from_millis(700)).await;
    assert!(seen.display > 10);
    assert_eq!(seen.record, 0);
    assert!(seen.opened.is_empty());
    assert!(cap.stop().await);
}

#[tokio::test]
async fn a_missing_device_ends_with_its_error() {
    let mut media = GstMedia::new().expect("gst");
    let (tx, mut rx) = mpsc::channel(64);
    let mut s = spec(true, None);
    s.device = "/dev/f250-no-such-camera".into();
    let r = media.start(s, tx);
    let detail = match r {
        Err(e) => e,
        Ok(cap) => {
            let seen = collect(&mut rx, Duration::from_secs(3)).await;
            cap.stop().await;
            seen.ended.first().cloned().expect("an error")
        }
    };
    assert!(!detail.is_empty());
}

#[tokio::test]
async fn camera_manager_records_with_real_pipelines_and_stops_cleanly() {
    let root = temp("manager");
    let s = Settings {
        cameras: vec![(Camera::Rear, "/dev/unused".into())],
        caps: CAPS.into(),
        sink: SINK.into(),
        gst_launch: "unused".into(),
        frame_timeout: Duration::from_millis(1000),
        start_timeout: Duration::from_millis(5000),
        restart_min: Duration::from_millis(500),
        restart_max: Duration::from_millis(2000),
        policy: camera_policy::Config::default(),
        recording: Some(RecordingConfig {
            cameras: vec![Camera::Rear],
            root: root.clone(),
            mount: None,
            settings: recording::settings::Settings {
                segment_s: 10,
                ..Default::default()
            },
            clock: Clock::Untrusted,
        }),
    };
    let media = GstMedia::with_source(SOURCE).expect("gst");
    let (
        manager,
        Watches {
            mut view,
            mut recording,
        },
    ) = Manager::new(s, Box::new(media));
    let (cmds, rx) = mpsc::channel(8);
    let done = tokio::spawn(manager.run(rx));
    let rec_state = |r: &pb::Recording| r.cameras.first().map(|c| c.state);
    tokio::time::timeout(Duration::from_secs(10), async {
        while rec_state(&recording.borrow_and_update())
            != Some(pb::RecordingState::Recording as i32)
        {
            recording.changed().await.expect("loop running");
        }
    })
    .await
    .expect("recording within 10 s");
    // Show it, then close it: the recording carries on.
    let (reply, r) = oneshot::channel();
    cmds.send(Command::Move {
        mv: Move::Back,
        source: "test".into(),
        reply,
    })
    .await
    .expect("loop");
    r.await.expect("reply");
    tokio::time::timeout(Duration::from_secs(5), async {
        while view.borrow_and_update().feed != pb::FeedState::Live as i32 {
            view.changed().await.expect("loop running");
        }
    })
    .await
    .expect("live");
    let (reply, r) = oneshot::channel();
    cmds.send(Command::Move {
        mv: Move::Press,
        source: "test".into(),
        reply,
    })
    .await
    .expect("loop");
    r.await.expect("reply");
    tokio::time::sleep(Duration::from_millis(1500)).await;
    assert_eq!(
        rec_state(&recording.borrow()),
        Some(pb::RecordingState::Recording as i32),
        "{:?}",
        *recording.borrow()
    );
    cmds.send(Command::Shutdown).await.expect("loop");
    tokio::time::timeout(Duration::from_secs(8), done)
        .await
        .expect("stopped")
        .expect("no panic");
    let marker = std::fs::read_to_string(root.join(".state/clean-stop")).expect("clean stop");
    assert_eq!(marker.trim(), "1");
    let first = root.join("rear/b00001-s000000.mkv");
    assert!(frames_in(&first) > 30, "{} reads back", first.display());
    let _ = std::fs::remove_dir_all(root);
}
