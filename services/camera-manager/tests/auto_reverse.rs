//! Automatic reverse end to end (ADR-0046) `[SIM]`: a fake vehicle-gateway
//! serves `WatchReverse` on a unix socket from a script the test changes;
//! the real control loop and `reverse_link::follow` show the rear camera
//! through a fake `gst-launch`.
#![allow(clippy::unwrap_used)]

use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::time::Duration;

use camera_manager::config::Settings;
use camera_manager::manager::{Command, Manager};
use camera_manager::pipeline::LaunchMedia;
use camera_manager::reverse_link;
use camera_policy::Camera;
use f250_proto::camera::v1 as pb;
use f250_proto::vehicle::v1 as vpb;
use tokio::sync::{mpsc, watch};
use tokio_stream::Stream;
use tonic::{Request, Response, Status};
use vpb::vehicle_service_server::{VehicleService, VehicleServiceServer};

const FAKE: &str = r#"#!/bin/sh
dev=""
for a in "$@"; do case "$a" in device=*) dev="${a#device=}";; esac; done
mark="/GstPipeline:pipeline0/GstIdentity:f250_frames: last-message = chain   ******* (f250_frames:sink) (614400 bytes)"
echo "Setting pipeline to PLAYING ..."
case "$dev" in
  frames) while :; do echo "$mark"; sleep 0.02; done ;;
  probe) exit 0 ;;
  *) echo "ERROR: unknown fake device $dev" >&2; exit 1 ;;
esac
"#;

/// What the fake gateway says; `None` ends every stream.
type Script = watch::Receiver<Option<vpb::ReverseState>>;

#[derive(Clone)]
struct FakeGateway(Script);

type Boxed<T> = Pin<Box<dyn Stream<Item = Result<T, Status>> + Send>>;

#[tonic::async_trait]
impl VehicleService for FakeGateway {
    async fn list_signals(
        &self,
        _: Request<vpb::ListSignalsRequest>,
    ) -> Result<Response<vpb::ListSignalsResponse>, Status> {
        Err(Status::unimplemented("fake"))
    }

    type StreamSnapshotsStream = Boxed<vpb::StreamSnapshotsResponse>;

    async fn stream_snapshots(
        &self,
        _: Request<vpb::StreamSnapshotsRequest>,
    ) -> Result<Response<Self::StreamSnapshotsStream>, Status> {
        Err(Status::unimplemented("fake"))
    }

    async fn list_events(
        &self,
        _: Request<vpb::ListEventsRequest>,
    ) -> Result<Response<vpb::ListEventsResponse>, Status> {
        Err(Status::unimplemented("fake"))
    }

    async fn set_calibration(
        &self,
        _: Request<vpb::SetCalibrationRequest>,
    ) -> Result<Response<vpb::SetCalibrationResponse>, Status> {
        Err(Status::unimplemented("fake"))
    }

    type WatchReverseStream = Boxed<vpb::WatchReverseResponse>;

    async fn watch_reverse(
        &self,
        _: Request<vpb::WatchReverseRequest>,
    ) -> Result<Response<Self::WatchReverseStream>, Status> {
        let mut script = self.0.clone();
        let (tx, rx) = mpsc::channel(4);
        tokio::spawn(async move {
            loop {
                let Some(state) = *script.borrow_and_update() else {
                    return; // the stream ends
                };
                let m = vpb::WatchReverseResponse {
                    state: state as i32,
                    detail: format!("fake: {state:?}"),
                    ..Default::default()
                };
                if tx.send(Ok(m)).await.is_err() {
                    return;
                }
                let _ = tokio::time::timeout(Duration::from_millis(100), script.changed()).await;
            }
        });
        Ok(Response::new(Box::pin(
            tokio_stream::wrappers::ReceiverStream::new(rx),
        )))
    }
}

fn dir(test: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("f250-autorev-{test}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let script = dir.join("gst-launch");
    std::fs::write(&script, FAKE).unwrap();
    std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
    // See tests/manager.rs: a parallel fork can hold the script busy briefly.
    for _ in 0..200 {
        match std::process::Command::new(&script)
            .arg("device=probe")
            .status()
        {
            Err(e) if e.raw_os_error() == Some(26) => std::thread::sleep(Duration::from_millis(10)),
            _ => break,
        }
    }
    dir
}

fn settings(dir: &Path) -> Settings {
    Settings {
        cameras: vec![(Camera::Rear, "frames".into())],
        caps: "image/jpeg ! jpegdec".into(),
        sink: "fakesink".into(),
        gst_launch: dir.join("gst-launch").display().to_string(),
        frame_timeout: Duration::from_millis(250),
        start_timeout: Duration::from_millis(400),
        restart_min: Duration::from_millis(200),
        restart_max: Duration::from_millis(400),
        policy: camera_policy::Config {
            auto_reverse: true,
            rev_hold: Duration::from_millis(400),
            ..camera_policy::Config::default()
        },
        recording: None,
    }
}

async fn serve(dir: &Path, script: Script) -> String {
    let sock = dir.join("vehicle.sock");
    let listener = tokio::net::UnixListener::bind(&sock).unwrap();
    tokio::spawn(
        tonic::transport::Server::builder()
            .add_service(VehicleServiceServer::new(FakeGateway(script)))
            .serve_with_incoming(tokio_stream::wrappers::UnixListenerStream::new(listener)),
    );
    format!("unix:{}", sock.display())
}

async fn until(
    view: &mut watch::Receiver<pb::View>,
    what: &str,
    ok: impl Fn(&pb::View) -> bool,
) -> pb::View {
    tokio::time::timeout(Duration::from_secs(4), async {
        loop {
            let v = view.borrow_and_update().clone();
            if ok(&v) {
                return v;
            }
            let _ = view.changed().await;
        }
    })
    .await
    .unwrap_or_else(|_| panic!("never {what}: {:?}", view.borrow()))
}

fn shows_rear_for_reverse(v: &pb::View) -> bool {
    v.camera == pb::Camera::Rear as i32
        && v.reason == pb::Reason::Reverse as i32
        && v.feed == pb::FeedState::Live as i32
}

#[tokio::test]
async fn reverse_shows_the_rear_camera_and_hands_it_back() {
    let d = dir("cycle");
    let (script_tx, script) = watch::channel(Some(vpb::ReverseState::NotEngaged));
    let gateway = serve(&d, script).await;
    let media = LaunchMedia {
        program: settings(&d).gst_launch,
        why_not_recording: "launch media".into(),
    };
    let (manager, w) = Manager::new(settings(&d), Box::new(media));
    let mut view = w.view;
    let (cmds, rx) = mpsc::channel(8);
    let done = tokio::spawn(manager.run(rx));
    tokio::spawn(reverse_link::follow(gateway, cmds.clone()));

    let v = until(&mut view, "not engaged", |v| {
        v.reverse == pb::ReverseStatus::NotEngaged as i32
    })
    .await;
    assert_eq!(v.camera, pb::Camera::Unspecified as i32);

    script_tx.send_replace(Some(vpb::ReverseState::Engaged));
    until(
        &mut view,
        "the rear camera live for reverse",
        shows_rear_for_reverse,
    )
    .await;

    // Out of reverse: the rear view holds, then goes.
    script_tx.send_replace(Some(vpb::ReverseState::NotEngaged));
    let v = until(&mut view, "no camera", |v| {
        v.camera == pb::Camera::Unspecified as i32
    })
    .await;
    assert_eq!(v.reverse, pb::ReverseStatus::NotEngaged as i32);

    cmds.send(Command::Shutdown).await.unwrap();
    let _ = tokio::time::timeout(Duration::from_secs(5), done).await;
    let _ = std::fs::remove_dir_all(&d);
}

#[tokio::test]
async fn losing_the_gateway_mid_reverse_keeps_the_rear_view_and_says_unknown() {
    let d = dir("lost");
    let (script_tx, script) = watch::channel(Some(vpb::ReverseState::Engaged));
    let gateway = serve(&d, script).await;
    let media = LaunchMedia {
        program: settings(&d).gst_launch,
        why_not_recording: "launch media".into(),
    };
    let (manager, w) = Manager::new(settings(&d), Box::new(media));
    let mut view = w.view;
    let (cmds, rx) = mpsc::channel(8);
    let done = tokio::spawn(manager.run(rx));
    tokio::spawn(reverse_link::follow(gateway, cmds.clone()));
    until(
        &mut view,
        "the rear camera live for reverse",
        shows_rear_for_reverse,
    )
    .await;

    // The gateway's stream ends: unknown, and the rear view stays (the last
    // thing known is reverse; camera-policy, owner 2026-11-09).
    script_tx.send_replace(None);
    let v = until(&mut view, "unknown", |v| {
        v.reverse == pb::ReverseStatus::Unknown as i32
    })
    .await;
    assert_eq!(v.camera, pb::Camera::Rear as i32);

    cmds.send(Command::Shutdown).await.unwrap();
    let _ = tokio::time::timeout(Duration::from_secs(5), done).await;
    let _ = std::fs::remove_dir_all(&d);
}

#[tokio::test]
async fn no_gateway_at_all_is_unknown_and_shows_nothing() {
    let d = dir("none");
    let media = LaunchMedia {
        program: settings(&d).gst_launch,
        why_not_recording: "launch media".into(),
    };
    let (manager, w) = Manager::new(settings(&d), Box::new(media));
    let mut view = w.view;
    let (cmds, rx) = mpsc::channel(8);
    let done = tokio::spawn(manager.run(rx));
    let missing = format!("unix:{}", d.join("no-such.sock").display());
    tokio::spawn(reverse_link::follow(missing, cmds.clone()));
    let v = until(&mut view, "unknown", |v| {
        v.reverse == pb::ReverseStatus::Unknown as i32
    })
    .await;
    assert_eq!(v.camera, pb::Camera::Unspecified as i32);

    cmds.send(Command::Shutdown).await.unwrap();
    let _ = tokio::time::timeout(Duration::from_secs(5), done).await;
    let _ = std::fs::remove_dir_all(&d);
}
