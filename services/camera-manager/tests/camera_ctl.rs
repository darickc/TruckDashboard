//! `camera-ctl` against the real `camera-manager` binary, with a fake
//! `gst-launch` that sends frames. `[SIM]`.

use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Output};
use std::time::{Duration, Instant};

const FAKE: &str = r#"#!/bin/sh
case "$*" in *device=probe*) exit 0 ;; esac
mark="/GstPipeline:pipeline0/GstIdentity:f250_frames: last-message = chain   ******* (f250_frames:sink) (614400 bytes)"
while :; do echo "$mark"; sleep 0.02; done
"#;

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

fn start(test: &str) -> (Service, String) {
    let dir = std::env::temp_dir().join(format!("f250-ctl-{test}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("temp dir");
    let gst = dir.join("gst");
    std::fs::write(&gst, FAKE).expect("fake");
    std::fs::set_permissions(&gst, std::fs::Permissions::from_mode(0o755)).expect("chmod");
    // A parallel test forking at the moment the script was written can leave
    // it busy for an instant (ETXTBSY on Linux): wait until it runs.
    for _ in 0..200 {
        match Command::new(&gst).arg("device=probe").output() {
            Err(e) if e.raw_os_error() == Some(26) => std::thread::sleep(Duration::from_millis(10)),
            _ => break,
        }
    }
    let sock = dir.join("c.sock");
    let child = Command::new(env!("CARGO_BIN_EXE_camera-manager"))
        .arg("--listen")
        .arg(format!("unix:{}", sock.display()))
        .arg("--gst-launch")
        .arg(&gst)
        .args(["--camera", "rear=/dev/fake0", "--sink", "fakesink"])
        .stderr(std::process::Stdio::null())
        .spawn()
        .expect("camera-manager");
    wait_for(&sock);
    let endpoint = format!("unix:{}", sock.display());
    (Service { child, dir }, endpoint)
}

fn wait_for(sock: &Path) {
    let deadline = Instant::now() + Duration::from_secs(10);
    while !sock.exists() {
        assert!(
            Instant::now() < deadline,
            "camera-manager never bound {}",
            sock.display()
        );
        std::thread::sleep(Duration::from_millis(20));
    }
}

fn ctl(endpoint: &str, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_camera-ctl"))
        .arg("--to")
        .arg(endpoint)
        .args(args)
        .output()
        .expect("camera-ctl")
}

fn stdout(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).trim().to_string()
}

#[test]
fn moves_and_views_by_hand() {
    let (_svc, to) = start("moves");

    let o = ctl(&to, &["view"]);
    assert!(o.status.success(), "{o:?}");
    assert_eq!(stdout(&o), "no camera; reverse off");

    let o = ctl(&to, &["move", "back"]);
    assert!(o.status.success(), "{o:?}");
    assert!(stdout(&o).starts_with("rear (switch), "), "{}", stdout(&o));

    // Frames arrive within a second or so: the view goes live.
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        let v = stdout(&ctl(&to, &["view"]));
        if v == "rear (switch), live; reverse off" {
            break;
        }
        assert!(Instant::now() < deadline, "never live: {v}");
        std::thread::sleep(Duration::from_millis(50));
    }

    // Forward is the front camera, which this run has no device for.
    let o = ctl(&to, &["move", "forward"]);
    assert!(stdout(&o).starts_with("front (switch), "), "{}", stdout(&o));
    let v = stdout(&ctl(&to, &["view"]));
    assert!(v.contains("no front camera configured"), "{v}");

    let o = ctl(&to, &["move", "press"]);
    assert_eq!(stdout(&o), "no camera; reverse off");
}

#[test]
fn errors_are_plain_and_fail() {
    let o = ctl("unix:/nonexistent/f250-camera.sock", &["view"]);
    assert!(!o.status.success());
    let err = String::from_utf8_lossy(&o.stderr);
    assert!(
        err.starts_with("camera-ctl: no connection to unix:/nonexistent/f250-camera.sock"),
        "{err}"
    );

    let o = ctl("/no/scheme.sock", &["view"]);
    assert!(!o.status.success());
    assert!(String::from_utf8_lossy(&o.stderr).contains("unix: or tcp:"));

    let o = ctl("unix:/x", &["move", "up"]);
    assert!(!o.status.success(), "clap refuses an unknown direction");
}
