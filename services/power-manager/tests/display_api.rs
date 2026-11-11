//! The real power-manager binary, end to end: a fake sysfs with a backlight,
//! the display API on a unix socket, a client that watches and changes it.
//! On a Mac there are no input devices, so the power key is in FAULT; the
//! display runs regardless (ADR-0028: nothing about it depends on the key).

use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

use f250_proto::power::v1 as pb;
use hyper_util::rt::TokioIo;
use pb::display_service_client::DisplayServiceClient;
use tonic::transport::{Channel, Endpoint, Uri};

struct Run {
    child: Child,
    root: PathBuf,
}

impl Drop for Run {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

fn brightness(root: &Path) -> String {
    std::fs::read_to_string(root.join("sys/class/backlight/10-0045/brightness"))
        .unwrap_or_default()
        .trim()
        .to_string()
}

fn start(name: &str, extra: &[&str]) -> Run {
    // Short: unix socket paths are limited to about 100 bytes.
    let root = std::env::temp_dir().join(format!("pm-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let bl = root.join("sys/class/backlight/10-0045");
    std::fs::create_dir_all(&bl).expect("fake sysfs");
    std::fs::write(bl.join("max_brightness"), "255\n").expect("max");
    std::fs::write(bl.join("brightness"), "255\n").expect("brightness");
    let sock = root.join("p.sock");
    let child = Command::new(env!("CARGO_BIN_EXE_power-manager"))
        .arg("--sysfs")
        .arg(root.join("sys"))
        .arg("--display-listen")
        .arg(format!("unix:{}", sock.display()))
        .arg("--display-state")
        .arg(root.join("display"))
        .arg("--brightness-ramp-ms=0")
        .arg("--dry-run")
        .args(extra)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("power-manager starts");
    Run { child, root }
}

async fn connect(root: &Path) -> DisplayServiceClient<Channel> {
    let sock = root.join("p.sock");
    let deadline = Instant::now() + Duration::from_secs(10);
    while !sock.exists() {
        assert!(Instant::now() < deadline, "no socket at {}", sock.display());
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    let channel = Endpoint::from_static("http://localhost")
        .connect_with_connector(tower::service_fn(move |_: Uri| {
            let sock = sock.clone();
            async move {
                tokio::net::UnixStream::connect(sock)
                    .await
                    .map(TokioIo::new)
            }
        }))
        .await
        .expect("connects");
    DisplayServiceClient::new(channel)
}

async fn first(client: &mut DisplayServiceClient<Channel>) -> pb::Display {
    let mut stream = client
        .watch_display(pb::WatchDisplayRequest {})
        .await
        .expect("watch")
        .into_inner();
    let msg = tokio::time::timeout(Duration::from_secs(5), stream.message())
        .await
        .expect("a state within 5 s")
        .expect("stream ok")
        .expect("a message");
    msg.display.expect("display set")
}

async fn until_brightness(root: &Path, want: &str) {
    let deadline = Instant::now() + Duration::from_secs(5);
    while brightness(root) != want {
        assert!(
            Instant::now() < deadline,
            "brightness {} never became {want}",
            brightness(root)
        );
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

#[tokio::test]
async fn watch_set_and_the_backlight_follows() {
    // No location: Auto falls back to day, and says why.
    let run = start("set", &[]);
    let mut client = connect(&run.root).await;
    let d = first(&mut client).await;
    assert_eq!(d.mode, pb::DisplayMode::Day as i32);
    assert_eq!(d.basis, pb::ModeBasis::Fallback as i32);
    assert_eq!(d.sun, pb::SunStatus::NoLocation as i32);
    assert!(d.backlight_present);
    assert_eq!(d.backlight, "10-0045");
    assert_eq!(d.brightness_pct, 100);
    until_brightness(&run.root, "255").await;

    let r = client
        .set_display(pb::SetDisplayRequest {
            choice: pb::DisplayChoice::Night as i32,
            night_brightness_pct: 20,
            source: "test".into(),
            ..Default::default()
        })
        .await
        .expect("set")
        .into_inner()
        .display
        .expect("display");
    assert_eq!(r.mode, pb::DisplayMode::Night as i32);
    assert_eq!(r.basis, pb::ModeBasis::Manual as i32);
    assert_eq!(r.brightness_pct, 20);
    until_brightness(&run.root, "51").await;

    // Below the floor is raised to it; the backlight never goes dark.
    client
        .set_display(pb::SetDisplayRequest {
            night_brightness_pct: 1,
            ..Default::default()
        })
        .await
        .expect("set");
    until_brightness(&run.root, "26").await;

    let saved = std::fs::read_to_string(run.root.join("display")).expect("settings kept");
    assert!(saved.contains("choice=night"), "{saved}");
    assert!(saved.contains("night_pct=10"), "{saved}");

    let bad = client
        .set_display(pb::SetDisplayRequest {
            choice: 99,
            ..Default::default()
        })
        .await;
    assert_eq!(
        bad.expect_err("refused").code(),
        tonic::Code::InvalidArgument
    );
}

#[tokio::test]
async fn follows_the_sun_on_a_trusted_clock() {
    let run = start(
        "sun",
        &[
            "--latitude=39.739",
            "--longitude=-104.990",
            "--trust-clock=always",
        ],
    );
    let mut client = connect(&run.root).await;
    let d = first(&mut client).await;
    assert_eq!(d.basis, pb::ModeBasis::Sun as i32);
    assert_eq!(d.sun, pb::SunStatus::Known as i32);
    let night = d.sun_elevation_deg < -3.0;
    assert_eq!(
        d.mode,
        if night {
            pb::DisplayMode::Night
        } else {
            pb::DisplayMode::Day
        } as i32,
        "sun at {}°",
        d.sun_elevation_deg
    );
}

#[tokio::test]
async fn bad_display_settings_never_stop_it() {
    let run = start(
        "bad",
        &[
            "--latitude=north",
            "--longitude=-104.990",
            "--min-brightness-pct=0",
            "--fallback=dusk",
            "--backlight=nope",
        ],
    );
    let mut client = connect(&run.root).await;
    let d = first(&mut client).await;
    assert_eq!(d.sun, pb::SunStatus::NoLocation as i32);
    assert_eq!(d.mode, pb::DisplayMode::Day as i32);
    assert_eq!(d.min_brightness_pct, 10);
    assert!(!d.backlight_present);
    assert!(
        d.backlight_problem.contains("nope"),
        "{}",
        d.backlight_problem
    );
}
