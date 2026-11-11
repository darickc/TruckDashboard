//! Camera settings from the dashboard (ADR-0029) against the real
//! `camera-manager` binary: a fake `/dev` with two cameras, the settings
//! file, and the restart in place that applies them. `[SIM]`.

use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::time::{Duration, Instant};

use f250_proto::camera::v1 as pb;
use hyper_util::rt::TokioIo;
use pb::camera_service_client::CameraServiceClient;
use tonic::transport::{Channel, Endpoint, Uri};

/// A gst-launch that never sends a frame: the camera stays "starting".
const FAKE: &str = "#!/bin/sh\nsleep 30\n";

struct Service {
    child: Child,
    dir: PathBuf,
}

impl Drop for Service {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

impl Service {
    fn sock(&self) -> PathBuf {
        self.dir.join("c.sock")
    }

    fn settings(&self) -> PathBuf {
        self.dir.join("state/settings")
    }

    fn dev(&self) -> PathBuf {
        self.dir.join("dev")
    }
}

fn start(test: &str, extra: &[&str]) -> Service {
    // Short: unix socket paths are limited to about 100 bytes.
    let dir = std::env::temp_dir().join(format!("cm-{test}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    let dev = dir.join("dev");
    std::fs::create_dir_all(dev.join("v4l/by-path")).expect("dev");
    std::fs::create_dir_all(dev.join("v4l/by-id")).expect("dev");
    for (n, port) in [("video0", "1"), ("video2", "2")] {
        std::fs::write(dev.join(n), "").expect("node");
        std::os::unix::fs::symlink(
            dev.join(n),
            dev.join(format!(
                "v4l/by-path/platform-x-usb-0:{port}:1.0-video-index0"
            )),
        )
        .expect("link");
    }
    std::os::unix::fs::symlink(
        dev.join("video0"),
        dev.join("v4l/by-id/usb-046d_0825_ABC-video-index0"),
    )
    .expect("link");
    let gst = dir.join("gst");
    std::fs::write(&gst, FAKE).expect("fake");
    std::fs::set_permissions(&gst, std::fs::Permissions::from_mode(0o755)).expect("chmod");
    let child = Command::new(env!("CARGO_BIN_EXE_camera-manager"))
        .arg("--listen")
        .arg(format!("unix:{}", dir.join("c.sock").display()))
        .args(["--media", "launch", "--gst-launch"])
        .arg(&gst)
        .args(["--sink", "fakesink", "--camera", "rear=/dev/fake0"])
        .arg("--settings-file")
        .arg(dir.join("state/settings"))
        .arg("--dev-root")
        .arg(&dev)
        .args(extra)
        .stderr(std::process::Stdio::null())
        .spawn()
        .expect("camera-manager");
    Service { child, dir }
}

async fn connect(sock: &Path) -> CameraServiceClient<Channel> {
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        if sock.exists() {
            let s = sock.to_path_buf();
            let ch = Endpoint::from_static("http://localhost")
                .connect_with_connector(tower::service_fn(move |_: Uri| {
                    let s = s.clone();
                    async move { tokio::net::UnixStream::connect(s).await.map(TokioIo::new) }
                }))
                .await;
            if let Ok(ch) = ch {
                return CameraServiceClient::new(ch);
            }
        }
        assert!(
            Instant::now() < deadline,
            "no camera-manager at {}",
            sock.display()
        );
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

async fn get(c: &mut CameraServiceClient<Channel>) -> pb::GetCameraSettingsResponse {
    c.get_camera_settings(pb::GetCameraSettingsRequest {})
        .await
        .expect("get")
        .into_inner()
}

/// Polls until camera-manager has restarted and reports `want`.
async fn until_source(sock: &Path, want: pb::SettingsSource) -> pb::GetCameraSettingsResponse {
    let deadline = Instant::now() + Duration::from_secs(15);
    loop {
        let mut c = connect(sock).await;
        if let Ok(r) = c.get_camera_settings(pb::GetCameraSettingsRequest {}).await {
            let r = r.into_inner();
            if r.settings.as_ref().map(|s| s.source) == Some(want as i32) {
                return r;
            }
        }
        assert!(Instant::now() < deadline, "never reported {want:?}");
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}

fn assign(camera: pb::Camera, device: &str) -> pb::CameraAssignment {
    pb::CameraAssignment {
        camera: camera as i32,
        device: device.to_string(),
    }
}

#[tokio::test]
async fn lists_cameras_saves_settings_and_restarts_in_place() {
    let svc = start("set", &["--recording-allowed"]);
    let pid = svc.child.id();
    let mut c = connect(&svc.sock()).await;
    let r = get(&mut c).await;
    let s = r.settings.expect("settings");
    assert_eq!(s.source, pb::SettingsSource::Defaults as i32);
    assert_eq!(s.cameras.len(), 4);
    assert_eq!(
        s.cameras[3].device, "/dev/fake0",
        "rear from the command line"
    );
    assert!(
        s.recording_unavailable.contains("GStreamer"),
        "{}",
        s.recording_unavailable
    );
    assert_eq!(r.devices.len(), 2);
    assert!(
        r.devices[0]
            .path
            .ends_with("platform-x-usb-0:1:1.0-video-index0")
    );
    assert_eq!(r.devices[0].label, "046d_0825_ABC");
    let (front, rear) = (r.devices[0].path.clone(), r.devices[1].path.clone());

    // Two cameras on one device: refused, nothing saved.
    let bad = c
        .set_camera_settings(pb::SetCameraSettingsRequest {
            cameras: vec![
                assign(pb::Camera::Front, &front),
                assign(pb::Camera::Rear, &front),
            ],
            source: "test".into(),
            ..Default::default()
        })
        .await
        .expect("answer")
        .into_inner();
    assert!(!bad.applied);
    assert!(bad.detail.contains("can't both be"), "{}", bad.detail);
    assert!(!svc.settings().exists());

    let ok = c
        .set_camera_settings(pb::SetCameraSettingsRequest {
            cameras: vec![
                assign(pb::Camera::Front, &front),
                assign(pb::Camera::Rear, &rear),
            ],
            record: vec![pb::Camera::Front as i32, pb::Camera::Rear as i32],
            source: "test".into(),
            ..Default::default()
        })
        .await
        .expect("answer")
        .into_inner();
    assert!(ok.applied, "{}", ok.detail);
    let saved = std::fs::read_to_string(svc.settings()).expect("saved");
    assert!(saved.contains(&format!("front={front}")), "{saved}");
    assert!(saved.contains("record=front,rear"), "{saved}");

    // It comes back by itself, in the same process, with the new settings.
    let r = until_source(&svc.sock(), pb::SettingsSource::Screen).await;
    let s = r.settings.expect("settings");
    assert_eq!(s.cameras[0].device, front);
    assert_eq!(s.cameras[3].device, rear);
    assert_eq!(
        s.record,
        vec![pb::Camera::Front as i32, pb::Camera::Rear as i32]
    );
    let mut svc = svc;
    assert!(
        svc.child.try_wait().expect("wait").is_none(),
        "the process ended"
    );
    assert_eq!(svc.child.id(), pid);

    // Back to /etc/default/f250.
    let mut c = connect(&svc.sock()).await;
    let back = c
        .set_camera_settings(pb::SetCameraSettingsRequest {
            use_defaults: true,
            source: "test".into(),
            ..Default::default()
        })
        .await
        .expect("answer")
        .into_inner();
    assert!(back.applied, "{}", back.detail);
    let r = until_source(&svc.sock(), pb::SettingsSource::Defaults).await;
    assert_eq!(
        r.settings.expect("settings").cameras[3].device,
        "/dev/fake0"
    );
    assert!(!svc.settings().exists());
    let _ = svc.dev();
}

#[tokio::test]
async fn refused_while_a_camera_is_on_screen() {
    let svc = start("busy", &[]);
    let mut c = connect(&svc.sock()).await;
    let v = c
        .r#move(pb::MoveRequest {
            r#move: pb::SwitchMove::Back as i32,
            source: "test".into(),
        })
        .await
        .expect("move")
        .into_inner();
    assert_eq!(v.view.expect("view").camera, pb::Camera::Rear as i32);
    let r = c
        .set_camera_settings(pb::SetCameraSettingsRequest {
            use_defaults: true,
            ..Default::default()
        })
        .await
        .expect("answer")
        .into_inner();
    assert!(!r.applied);
    assert!(r.detail.contains("Close the camera first"), "{}", r.detail);
    let s = get(&mut c).await.settings.expect("settings");
    assert!(
        s.recording_unavailable.contains("DATA_DRIVE=1"),
        "{}",
        s.recording_unavailable
    );
}
