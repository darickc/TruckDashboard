//! The real power-manager binary following a fake navigation on a unix
//! socket (ADR-0028 amendment): a real fix replaces the configured
//! location, its time stands in for the Mac's unsynchronized clock (no
//! timedatectl here, so the system clock is never "synchronized"), the
//! position is saved to 0.1°, and a restart without navigation uses the
//! saved one. A simulated fix is never taken. `[SIM]`.

use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use f250_proto::nav::v1 as nav;
use f250_proto::power::v1 as pb;
use hyper_util::rt::TokioIo;
use nav::position_service_server::{PositionService, PositionServiceServer};
use pb::display_service_client::DisplayServiceClient;
use tokio_stream::Stream;
use tonic::transport::{Channel, Endpoint, Uri};
use tonic::{Request, Response, Status};

struct FakeNav {
    simulated: bool,
}

#[tonic::async_trait]
impl PositionService for FakeNav {
    type WatchPositionStream =
        Pin<Box<dyn Stream<Item = Result<nav::WatchPositionResponse, Status>> + Send>>;

    async fn watch_position(
        &self,
        _: Request<nav::WatchPositionRequest>,
    ) -> Result<Response<Self::WatchPositionStream>, Status> {
        let (tx, rx) = tokio::sync::mpsc::channel(4);
        let simulated = self.simulated;
        tokio::spawn(async move {
            loop {
                let utc_ms = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .map(|d| d.as_millis() as i64)
                    .unwrap_or(0);
                let p = nav::Position {
                    status: nav::FixStatus::Fix3d as i32,
                    fix: Some(nav::Fix {
                        latitude_deg: 37.687,
                        longitude_deg: -97.330,
                        age_ms: 100,
                        utc_time_ms: (!simulated).then_some(utc_ms - 100),
                        ..Default::default()
                    }),
                    current: true,
                    stale_after_ms: 3000,
                    source: if simulated {
                        "simulated"
                    } else {
                        "gpsd 3.27.5: fake"
                    }
                    .into(),
                    simulated,
                    ..Default::default()
                };
                let msg = nav::WatchPositionResponse { position: Some(p) };
                if tx.send(Ok(msg)).await.is_err() {
                    return;
                }
                tokio::time::sleep(Duration::from_millis(200)).await;
            }
        });
        Ok(Response::new(Box::pin(
            tokio_stream::wrappers::ReceiverStream::new(rx),
        )))
    }
}

fn serve_nav(sock: PathBuf, simulated: bool) {
    let _ = std::fs::remove_file(&sock);
    let listener = tokio::net::UnixListener::bind(&sock).expect("bind fake navigation");
    tokio::spawn(async move {
        tonic::transport::Server::builder()
            .add_service(PositionServiceServer::new(FakeNav { simulated }))
            .serve_with_incoming(tokio_stream::wrappers::UnixListenerStream::new(listener))
            .await
            .expect("fake navigation serves");
    });
}

struct Run {
    child: Child,
}

impl Drop for Run {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn start(root: &Path, extra: &[String]) -> Run {
    let _ = std::fs::remove_file(root.join("p.sock"));
    let child = Command::new(env!("CARGO_BIN_EXE_power-manager"))
        .arg("--display-listen")
        .arg(format!("unix:{}", root.join("p.sock").display()))
        .arg("--location-state")
        .arg(root.join("location"))
        .arg("--backlight=none")
        .arg("--dry-run")
        // Denver: GPS must replace it.
        .args(["--latitude=39.739", "--longitude=-104.990"])
        .args(extra)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("power-manager starts");
    Run { child }
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

/// The first state that satisfies `want`, within 10 s.
async fn until(
    client: &mut DisplayServiceClient<Channel>,
    want: impl Fn(&pb::Display) -> bool,
) -> pb::Display {
    let mut stream = client
        .watch_display(pb::WatchDisplayRequest {})
        .await
        .expect("watch")
        .into_inner();
    let mut last = None;
    let found = tokio::time::timeout(Duration::from_secs(10), async {
        while let Ok(Some(m)) = stream.message().await {
            let d = m.display.expect("display");
            if want(&d) {
                return Some(d);
            }
            last = Some(d);
        }
        None
    })
    .await;
    match found {
        Ok(Some(d)) => d,
        _ => panic!("never got the state wanted; last {last:?}"),
    }
}

fn dir(name: &str) -> PathBuf {
    // Short: unix socket paths are limited to about 100 bytes.
    let root = std::env::temp_dir().join(format!("pmg-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(&root).expect("dir");
    root
}

#[tokio::test]
async fn a_real_fix_gives_the_location_and_the_time_and_is_saved() {
    let root = dir("real");
    serve_nav(root.join("n.sock"), false);
    let nav_arg = format!("--navigation=unix:{}", root.join("n.sock").display());
    {
        let _run = start(&root, std::slice::from_ref(&nav_arg));
        let mut client = connect(&root).await;
        let d = until(&mut client, |d| {
            d.location_source == pb::LocationSource::Gps as i32
                && d.clock_source == pb::ClockSource::Gps as i32
        })
        .await;
        assert_eq!(d.basis, pb::ModeBasis::Sun as i32);
        assert_eq!(d.sun, pb::SunStatus::Known as i32);
        let saved = std::fs::read_to_string(root.join("location")).expect("saved");
        assert!(saved.contains("latitude=37.7\n"), "{saved}");
        assert!(saved.contains("longitude=-97.3\n"), "{saved}");
    }
    // Again with no navigation: the saved position, not the configured one,
    // and (no GPS time, no synchronized clock) the fallback.
    let _run = start(&root, &[]);
    let mut client = connect(&root).await;
    let d = until(&mut client, |d| d.basis != 0).await;
    assert_eq!(d.location_source, pb::LocationSource::GpsSaved as i32);
    assert_eq!(d.clock_source, pb::ClockSource::None as i32);
    assert_eq!(d.basis, pb::ModeBasis::Fallback as i32);
    assert_eq!(d.sun, pb::SunStatus::ClockNotSynchronized as i32);
    let _ = std::fs::remove_dir_all(&root);
}

#[tokio::test]
async fn a_simulated_fix_is_never_the_truck() {
    let root = dir("sim");
    serve_nav(root.join("n.sock"), true);
    let nav_arg = format!("--navigation=unix:{}", root.join("n.sock").display());
    {
        let _run = start(&root, &[nav_arg.clone(), "--trust-clock=always".into()]);
        let mut client = connect(&root).await;
        // Give it time to have heard the simulated fixes.
        tokio::time::sleep(Duration::from_secs(1)).await;
        let d = until(&mut client, |d| d.basis != 0).await;
        assert_eq!(d.location_source, pb::LocationSource::Configured as i32);
        assert_eq!(d.clock_source, pb::ClockSource::Trusted as i32);
        assert!(!root.join("location").exists(), "never saved");
    }
    // Development: taken, labelled, never saved, its (absent) time unused.
    let _run = start(&root, &[nav_arg, "--gps-accept-simulated".into()]);
    let mut client = connect(&root).await;
    let d = until(&mut client, |d| {
        d.location_source == pb::LocationSource::GpsSimulated as i32
    })
    .await;
    assert_eq!(d.clock_source, pb::ClockSource::None as i32);
    assert!(!root.join("location").exists(), "never saved");
    let _ = std::fs::remove_dir_all(&root);
}
