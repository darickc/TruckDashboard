//! The service end to end [SIM]: a fake gpsd on TCP replays gpsd 3.27.5's
//! own output (crates/gpsd/tests/data), and a gRPC client over a unix
//! socket watches the position go from nothing to a 3D fix, and to stale
//! and "gpsd unavailable" when the fake gpsd hangs up.

use std::time::Duration;

use f250_proto::nav::v1 as pb;
use hyper_util::rt::TokioIo;
use navigation::publisher::{self, PublisherConfig};
use navigation::server::{self, Api};
use navigation::sim::{self, SimConfig};
use navigation::source::{self, GpsdConfig};
use pb::position_service_client::PositionServiceClient;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpListener;
use tokio::sync::{mpsc, watch};
use tonic::transport::{Endpoint, Uri};

const CAPTURE: &str = include_str!("../../../crates/gpsd/tests/data/gpsd-3.27.5-nmea-udp.jsonl");

fn socket(test: &str) -> String {
    let dir = std::env::temp_dir().join(format!("f250-nav-{test}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("temp dir");
    dir.join("nav.sock").display().to_string()
}

async fn client(path: &str) -> PositionServiceClient<tonic::transport::Channel> {
    let path = path.to_string();
    for _ in 0..100 {
        if std::path::Path::new(&path).exists() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    let channel = Endpoint::from_static("http://localhost")
        .connect_with_connector(tower::service_fn(move |_: Uri| {
            let path = path.clone();
            async move {
                tokio::net::UnixStream::connect(path)
                    .await
                    .map(TokioIo::new)
            }
        }))
        .await
        .expect("connect");
    PositionServiceClient::new(channel)
}

fn start(
    test: &str,
    simulated: bool,
    stale_after: Duration,
) -> (String, mpsc::Sender<navigation::source::Event>) {
    let path = socket(test);
    let (tx, rx) = mpsc::channel(64);
    let (out, position) = watch::channel(pb::Position::default());
    let cfg = PublisherConfig {
        stale_after,
        simulated,
        tick: Duration::from_millis(100),
    };
    tokio::spawn(publisher::run(cfg, rx, out, None));
    let listen = format!("unix:{path}");
    tokio::spawn(async move { server::serve(&listen, Api::new(position)).await });
    (path, tx)
}

/// Waits for the first position that `want` accepts.
async fn until(
    stream: &mut tonic::Streaming<pb::WatchPositionResponse>,
    want: impl Fn(&pb::Position) -> bool,
) -> pb::Position {
    tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let r = stream
                .message()
                .await
                .expect("stream ok")
                .expect("stream open");
            let p = r.position.expect("position");
            if want(&p) {
                return p;
            }
        }
    })
    .await
    .expect("in time")
}

#[tokio::test]
async fn gpsd_replay_to_a_fix_then_unavailable() {
    // A fake gpsd: wait for ?WATCH, send the capture quickly, hang up.
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
    let addr = listener.local_addr().expect("addr").to_string();
    let (hang_up_tx, hang_up_rx) = tokio::sync::oneshot::channel::<()>();
    tokio::spawn(async move {
        let (sock, _) = listener.accept().await.expect("accept");
        let (read, mut write) = sock.into_split();
        let mut lines = BufReader::new(read).lines();
        let first = lines.next_line().await.expect("read").expect("a line");
        assert_eq!(format!("{first}\n"), gpsd::WATCH);
        // Up to the last 3D TPV, so the position is current at the end.
        let lines: Vec<&str> = CAPTURE.lines().collect();
        let last_3d = lines
            .iter()
            .rposition(|l| l.contains("\"TPV\"") && l.contains("\"mode\":3"))
            .expect("a 3D TPV");
        for line in &lines[..=last_3d] {
            write.write_all(line.as_bytes()).await.expect("write");
            write.write_all(b"\n").await.expect("write");
        }
        let _ = hang_up_rx.await;
        // Dropping the socket hangs up; nothing listens any more.
    });

    let (path, tx) = start("gpsd", false, Duration::from_secs(3));
    let mut cfg = GpsdConfig::new(&addr);
    cfg.retry_after = Duration::from_millis(200);
    tokio::spawn(source::run_gpsd(cfg, tx));

    let mut client = client(&path).await;
    let mut stream = client
        .watch_position(pb::WatchPositionRequest {})
        .await
        .expect("watch")
        .into_inner();

    let p = until(&mut stream, |p| p.current).await;
    assert_eq!(p.status, pb::FixStatus::Fix3d as i32);
    assert!(!p.simulated);
    assert_eq!(p.source, "gpsd 3.27.5: udp://127.0.0.1:5948");
    assert!(p.satellites_used.is_some());
    let f = p.fix.expect("fix");
    assert!((f.latitude_deg - 39.83).abs() < 0.01);
    assert!(p.detail.is_empty());

    hang_up_tx.send(()).expect("hang up");
    let p = until(&mut stream, |p| {
        p.status == pb::FixStatus::Unavailable as i32
    })
    .await;
    assert!(!p.current, "never current without gpsd");
    assert!(p.fix.is_some(), "the last fix is kept");
    assert!(p.detail.starts_with("gpsd unavailable"), "{}", p.detail);
}

#[tokio::test]
async fn nobody_listening_is_unavailable() {
    // A port with nothing on it.
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
    let addr = listener.local_addr().expect("addr").to_string();
    drop(listener);
    let (path, tx) = start("refused", false, Duration::from_secs(3));
    tokio::spawn(source::run_gpsd(GpsdConfig::new(&addr), tx));
    let mut client = client(&path).await;
    let mut stream = client
        .watch_position(pb::WatchPositionRequest {})
        .await
        .expect("watch")
        .into_inner();
    let p = until(&mut stream, |p| p.detail.contains(&addr)).await;
    assert_eq!(p.status, pb::FixStatus::Unavailable as i32);
    assert!(p.fix.is_none());
}

#[tokio::test]
async fn simulated_receiver_with_an_outage() {
    let (path, tx) = start("sim", true, Duration::from_millis(300));
    let cfg = SimConfig {
        period: Duration::from_millis(50),
        outage_every: Some(Duration::from_millis(500)),
        outage_for: Duration::from_millis(400),
        ..SimConfig::default()
    };
    tokio::spawn(sim::run(cfg, tx));
    let mut client = client(&path).await;
    let mut stream = client
        .watch_position(pb::WatchPositionRequest {})
        .await
        .expect("watch")
        .into_inner();
    let p = until(&mut stream, |p| p.current).await;
    assert!(p.simulated);
    assert_eq!(p.source, "simulated");
    let p = until(&mut stream, |p| p.status == pb::FixStatus::NoFix as i32).await;
    assert!(!p.current);
    assert!(p.fix.is_some());
    until(&mut stream, |p| p.current).await;
}
