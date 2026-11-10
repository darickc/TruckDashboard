//! The control loop end to end with real child processes: a fake
//! `gst-launch` (a shell script) stands in for GStreamer. Its behaviour
//! depends on the device name it is given:
//!
//! - `frames`: prints a frame line every 20 ms, forever
//! - `silent`: prints nothing
//! - `stall`: five frames, then nothing
//! - `dies`: one frame, an error on stderr, exit 1
//!
//! Every run writes its pid to `<dir>/pid-<device>` so the tests can check
//! the process is gone. `[SIM]`.

use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::time::Duration;

use camera_manager::config::Settings;
use camera_manager::manager::{Command, Manager};
use camera_manager::server::Api;
use camera_policy::{Camera, Move};
use f250_proto::camera::v1 as pb;
use pb::camera_service_server::CameraService;
use tokio::sync::{mpsc, oneshot, watch};
use tokio_stream::StreamExt;

const FAKE: &str = r#"#!/bin/sh
dev=""
for a in "$@"; do case "$a" in device=*) dev="${a#device=}";; esac; done
echo $$ > "$(dirname "$0")/pid-$dev"
mark="/GstPipeline:pipeline0/GstIdentity:f250_frames: last-message = chain   ******* (f250_frames:sink) (614400 bytes)"
echo "Setting pipeline to PLAYING ..."
case "$dev" in
  frames) while :; do echo "$mark"; sleep 0.02; done ;;
  silent) exec sleep 30 ;;
  stall) i=0; while [ $i -lt 5 ]; do echo "$mark"; sleep 0.02; i=$((i+1)); done; exec sleep 30 ;;
  dies) echo "$mark"; sleep 0.05; echo "ERROR: from element /GstPipeline:pipeline0/GstV4l2Src:v4l2src0: Could not read from resource." >&2; exit 1 ;;
  *) echo "ERROR: unknown fake device $dev" >&2; exit 1 ;;
esac
"#;

struct Rig {
    dir: PathBuf,
    cmds: mpsc::Sender<Command>,
    view: watch::Receiver<pb::View>,
    done: tokio::task::JoinHandle<()>,
}

fn fake_dir(test: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("f250-camera-{test}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("temp dir");
    let script = dir.join("gst-launch");
    std::fs::write(&script, FAKE).expect("write fake");
    std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).expect("chmod");
    dir
}

fn settings(dir: &Path, cameras: &[(Camera, &str)]) -> Settings {
    Settings {
        cameras: cameras
            .iter()
            .map(|(c, d)| (*c, (*d).to_string()))
            .collect(),
        caps: "image/jpeg ! jpegdec".into(),
        sink: "fakesink".into(),
        gst_launch: dir.join("gst-launch").display().to_string(),
        frame_timeout: Duration::from_millis(250),
        start_timeout: Duration::from_millis(400),
        restart_min: Duration::from_millis(200),
        restart_max: Duration::from_millis(400),
        policy: camera_policy::Config::default(),
    }
}

fn rig(test: &str, cameras: &[(Camera, &str)]) -> Rig {
    let dir = fake_dir(test);
    rig_with(dir.clone(), settings(&dir, cameras))
}

fn rig_with(dir: PathBuf, s: Settings) -> Rig {
    let (manager, view) = Manager::new(s);
    let (cmds, rx) = mpsc::channel(8);
    let done = tokio::spawn(manager.run(rx));
    Rig {
        dir,
        cmds,
        view,
        done,
    }
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

    /// Waits until the view matches, or fails after `within`.
    async fn until(
        &mut self,
        within: Duration,
        what: &str,
        pred: impl Fn(&pb::View) -> bool,
    ) -> pb::View {
        let deadline = tokio::time::Instant::now() + within;
        loop {
            {
                let v = self.view.borrow_and_update();
                if pred(&v) {
                    return v.clone();
                }
            }
            let left = deadline.saturating_duration_since(tokio::time::Instant::now());
            match tokio::time::timeout(left, self.view.changed()).await {
                Ok(Ok(())) => {}
                _ => panic!(
                    "timed out waiting for {what}; last view {:?}",
                    *self.view.borrow()
                ),
            }
        }
    }

    fn pid(&self, device: &str) -> Option<String> {
        std::fs::read_to_string(self.dir.join(format!("pid-{device}")))
            .ok()
            .map(|s| s.trim().to_string())
    }

    async fn finish(self) {
        drop(self.cmds);
        tokio::time::timeout(Duration::from_secs(5), self.done)
            .await
            .expect("loop stopped")
            .expect("no panic");
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

fn alive(pid: &str) -> bool {
    std::process::Command::new("kill")
        .args(["-0", pid])
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn cam(v: &pb::View) -> pb::Camera {
    pb::Camera::try_from(v.camera).unwrap_or(pb::Camera::Unspecified)
}

fn feed(v: &pb::View) -> pb::FeedState {
    pb::FeedState::try_from(v.feed).unwrap_or(pb::FeedState::Unspecified)
}

const SOON: Duration = Duration::from_secs(3);

#[tokio::test]
async fn starts_with_no_camera_and_reverse_off() {
    let r = rig("idle", &[(Camera::Rear, "frames")]);
    let v = r.view.borrow().clone();
    assert_eq!(cam(&v), pb::Camera::Unspecified);
    assert_eq!(feed(&v), pb::FeedState::Unspecified);
    assert_eq!(v.reverse, pb::ReverseStatus::Off as i32);
    assert!(
        r.pid("frames").is_none(),
        "no pipeline before a camera is chosen"
    );
    r.finish().await;
}

#[tokio::test]
async fn back_starts_the_rear_camera_and_goes_live_on_frames() {
    let mut r = rig("live", &[(Camera::Rear, "frames")]);
    let v = r.mv(Move::Back).await;
    assert_eq!(cam(&v), pb::Camera::Rear);
    assert_eq!(v.reason, pb::Reason::Switch as i32);
    assert_eq!(feed(&v), pb::FeedState::Starting);
    let v = r
        .until(SOON, "live", |v| feed(v) == pb::FeedState::Live)
        .await;
    assert_eq!(cam(&v), pb::Camera::Rear);
    assert!(v.feed_detail.is_empty());
    r.finish().await;
}

#[tokio::test]
async fn press_closes_the_camera_and_kills_its_pipeline() {
    let mut r = rig("close", &[(Camera::Rear, "frames")]);
    r.mv(Move::Back).await;
    r.until(SOON, "live", |v| feed(v) == pb::FeedState::Live)
        .await;
    let pid = r.pid("frames").expect("pipeline started");
    assert!(alive(&pid));
    let v = r.mv(Move::Press).await;
    assert_eq!(cam(&v), pb::Camera::Unspecified);
    // The reply comes after the pipeline was stopped and reaped.
    assert!(!alive(&pid), "pipeline {pid} still running after Press");
    r.finish().await;
}

#[tokio::test]
async fn forward_shows_the_front_camera() {
    let mut r = rig("front", &[(Camera::Front, "frames")]);
    let v = r.mv(Move::Forward).await;
    assert_eq!(cam(&v), pb::Camera::Front);
    r.until(SOON, "front live", |v| {
        cam(v) == pb::Camera::Front && feed(v) == pb::FeedState::Live
    })
    .await;
    assert!(r.pid("frames").is_some());
    r.finish().await;
}

#[tokio::test]
async fn switching_cameras_replaces_the_pipeline() {
    let mut r = rig("swap", &[(Camera::Rear, "frames"), (Camera::Left, "stall")]);
    r.mv(Move::Back).await;
    r.until(SOON, "rear live", |v| feed(v) == pb::FeedState::Live)
        .await;
    let rear = r.pid("frames").expect("rear started");
    let v = r.mv(Move::Left).await;
    assert_eq!(cam(&v), pb::Camera::Left);
    assert!(!alive(&rear), "rear pipeline still running");
    r.until(SOON, "left live", |v| {
        cam(v) == pb::Camera::Left && feed(v) == pb::FeedState::Live
    })
    .await;
    r.finish().await;
}

#[tokio::test]
async fn an_unconfigured_camera_is_unavailable_without_a_pipeline() {
    let r = rig("unconfigured", &[(Camera::Rear, "frames")]);
    let v = r.mv(Move::Right).await;
    assert_eq!(cam(&v), pb::Camera::Right);
    assert_eq!(feed(&v), pb::FeedState::Unavailable);
    assert!(
        v.feed_detail.contains("no right camera configured"),
        "{}",
        v.feed_detail
    );
    r.finish().await;
}

#[tokio::test]
async fn no_first_frame_times_out_kills_and_retries() {
    let mut r = rig("silent", &[(Camera::Rear, "silent")]);
    r.mv(Move::Back).await;
    let v = r
        .until(SOON, "start timeout", |v| {
            feed(v) == pb::FeedState::Unavailable
        })
        .await;
    assert!(
        v.feed_detail.contains("no frame within 400 ms"),
        "{}",
        v.feed_detail
    );
    let first = r.pid("silent").expect("started");
    assert!(!alive(&first), "a timed-out pipeline must be killed");
    // Retried after the backoff: starting again, as a new process.
    r.until(SOON, "retry", |v| feed(v) == pb::FeedState::Starting)
        .await;
    tokio::time::sleep(Duration::from_millis(50)).await;
    let second = r.pid("silent").expect("restarted");
    assert_ne!(first, second);
    r.finish().await;
}

#[tokio::test]
async fn frames_stopping_makes_the_camera_unavailable_never_frozen() {
    let mut r = rig("stall", &[(Camera::Rear, "stall")]);
    r.mv(Move::Back).await;
    r.until(SOON, "live", |v| feed(v) == pb::FeedState::Live)
        .await;
    let pid = r.pid("stall").expect("started");
    let v = r
        .until(SOON, "frame timeout", |v| {
            feed(v) == pb::FeedState::Unavailable
        })
        .await;
    assert!(
        v.feed_detail.contains("no frame for 250 ms"),
        "{}",
        v.feed_detail
    );
    assert_eq!(
        cam(&v),
        pb::Camera::Rear,
        "the view keeps the camera; the dashboard shows the panel"
    );
    assert!(
        !alive(&pid),
        "the stalled pipeline (and its window) must be gone"
    );
    r.finish().await;
}

#[tokio::test]
async fn a_pipeline_error_is_reported_with_its_message() {
    let mut r = rig("dies", &[(Camera::Rear, "dies")]);
    r.mv(Move::Back).await;
    let v = r
        .until(SOON, "error", |v| feed(v) == pb::FeedState::Unavailable)
        .await;
    assert!(
        v.feed_detail.contains("Could not read from resource"),
        "{}",
        v.feed_detail
    );
    r.finish().await;
}

#[tokio::test]
async fn a_missing_gst_launch_is_unavailable_with_the_reason() {
    let dir = fake_dir("missing");
    let mut s = settings(&dir, &[(Camera::Rear, "frames")]);
    s.gst_launch = dir.join("no-such-program").display().to_string();
    let r = rig_with(dir, s);
    let v = r.mv(Move::Back).await;
    assert_eq!(feed(&v), pb::FeedState::Unavailable);
    assert!(
        v.feed_detail.contains("no-such-program"),
        "{}",
        v.feed_detail
    );
    r.finish().await;
}

#[tokio::test]
async fn stopping_the_loop_kills_the_running_pipeline() {
    let mut r = rig("shutdown", &[(Camera::Rear, "frames")]);
    r.mv(Move::Back).await;
    r.until(SOON, "live", |v| feed(v) == pb::FeedState::Live)
        .await;
    let pid = r.pid("frames").expect("started");
    let dir = r.dir.clone();
    drop(r.cmds);
    tokio::time::timeout(Duration::from_secs(5), r.done)
        .await
        .expect("loop stopped")
        .expect("no panic");
    assert!(!alive(&pid), "pipeline survived the loop");
    let _ = std::fs::remove_dir_all(dir);
}

#[tokio::test]
async fn the_api_streams_views_and_takes_moves() {
    let r = rig("api", &[(Camera::Rear, "frames")]);
    let api = Api::new(r.cmds.clone(), r.view.clone());
    let mut stream = api
        .watch_view(tonic::Request::new(pb::WatchViewRequest {}))
        .await
        .expect("stream")
        .into_inner();
    let first = stream
        .next()
        .await
        .expect("item")
        .expect("ok")
        .view
        .expect("view");
    assert_eq!(cam(&first), pb::Camera::Unspecified);

    let resp = api
        .r#move(tonic::Request::new(pb::MoveRequest {
            r#move: pb::SwitchMove::Back as i32,
            source: "power-manager".into(),
        }))
        .await
        .expect("move")
        .into_inner();
    assert_eq!(cam(resp.view.as_ref().expect("view")), pb::Camera::Rear);

    let live = tokio::time::timeout(SOON, async {
        while let Some(Ok(item)) = stream.next().await {
            let v = item.view.expect("view");
            if feed(&v) == pb::FeedState::Live {
                return v;
            }
        }
        panic!("stream ended");
    })
    .await
    .expect("live within 3 s");
    assert_eq!(cam(&live), pb::Camera::Rear);

    let bad = api
        .r#move(tonic::Request::new(pb::MoveRequest {
            r#move: pb::SwitchMove::Unspecified as i32,
            source: String::new(),
        }))
        .await
        .expect_err("unspecified move rejected");
    assert_eq!(bad.code(), tonic::Code::InvalidArgument);
    drop(api);
    drop(stream);
    r.finish().await;
}
