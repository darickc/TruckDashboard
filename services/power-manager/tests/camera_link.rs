//! The camera-switch link against a fake camera-manager on a unix socket:
//! moves arrive, a missing or slow camera-manager never blocks the sender,
//! old moves are dropped, and the link finds camera-manager after it starts
//! or restarts. `[SIM]`.

use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use f250_proto::camera::v1 as pb;
use pb::camera_service_server::{CameraService, CameraServiceServer};
use power_manager::camera_link::{Link, LinkConfig, NotQueued, Outcome, SOURCE};
use power_manager::camera_switch::Direction;
use tokio::sync::{mpsc, oneshot};
use tokio::time::{Instant, timeout};
use tokio_stream::Stream;
use tonic::{Request, Response, Status};

type Seen = Arc<Mutex<Vec<(pb::SwitchMove, String)>>>;

struct Fake {
    seen: Seen,
    delay: Duration,
}

#[tonic::async_trait]
impl CameraService for Fake {
    type WatchViewStream =
        Pin<Box<dyn Stream<Item = Result<pb::WatchViewResponse, Status>> + Send>>;
    type WatchRecordingStream =
        Pin<Box<dyn Stream<Item = Result<pb::WatchRecordingResponse, Status>> + Send>>;

    // power-manager only sends moves.
    async fn watch_recording(
        &self,
        _: Request<pb::WatchRecordingRequest>,
    ) -> Result<Response<Self::WatchRecordingStream>, Status> {
        Err(Status::unimplemented("not in the fake"))
    }

    async fn save_clip(
        &self,
        _: Request<pb::SaveClipRequest>,
    ) -> Result<Response<pb::SaveClipResponse>, Status> {
        Err(Status::unimplemented("not in the fake"))
    }

    async fn get_camera_settings(
        &self,
        _: Request<pb::GetCameraSettingsRequest>,
    ) -> Result<Response<pb::GetCameraSettingsResponse>, Status> {
        Err(Status::unimplemented("not in the fake"))
    }

    async fn set_camera_settings(
        &self,
        _: Request<pb::SetCameraSettingsRequest>,
    ) -> Result<Response<pb::SetCameraSettingsResponse>, Status> {
        Err(Status::unimplemented("not in the fake"))
    }

    async fn watch_view(
        &self,
        _: Request<pb::WatchViewRequest>,
    ) -> Result<Response<Self::WatchViewStream>, Status> {
        Err(Status::unimplemented("not in this fake"))
    }

    async fn r#move(
        &self,
        req: Request<pb::MoveRequest>,
    ) -> Result<Response<pb::MoveResponse>, Status> {
        tokio::time::sleep(self.delay).await;
        let req = req.into_inner();
        let mv = pb::SwitchMove::try_from(req.r#move).unwrap_or(pb::SwitchMove::Unspecified);
        self.seen
            .lock()
            .expect("lock")
            .push((mv, req.source.clone()));
        let camera = match mv {
            pb::SwitchMove::Back => pb::Camera::Rear,
            pb::SwitchMove::Left => pb::Camera::Left,
            pb::SwitchMove::Right => pb::Camera::Right,
            _ => pb::Camera::Unspecified,
        };
        Ok(Response::new(pb::MoveResponse {
            view: Some(pb::View {
                camera: camera as i32,
                feed: pb::FeedState::Live as i32,
                ..Default::default()
            }),
        }))
    }
}

/// A fake camera-manager serving on `path` until the sender is used or
/// dropped.
struct Server {
    seen: Seen,
    stop: Option<oneshot::Sender<()>>,
    done: tokio::task::JoinHandle<()>,
}

impl Server {
    fn start(path: &Path, delay: Duration) -> Server {
        let _ = std::fs::remove_file(path);
        let listener = tokio::net::UnixListener::bind(path).expect("bind");
        let seen: Seen = Arc::default();
        let (stop, stopped) = oneshot::channel::<()>();
        let svc = CameraServiceServer::new(Fake {
            seen: seen.clone(),
            delay,
        });
        let done = tokio::spawn(async move {
            let incoming = tokio_stream::wrappers::UnixListenerStream::new(listener);
            let _ = tonic::transport::Server::builder()
                .add_service(svc)
                .serve_with_incoming_shutdown(incoming, async {
                    let _ = stopped.await;
                })
                .await;
        });
        Server {
            seen,
            stop: Some(stop),
            done,
        }
    }

    fn seen(&self) -> Vec<(pb::SwitchMove, String)> {
        self.seen.lock().expect("lock").clone()
    }

    async fn stop(mut self, path: &Path) {
        if let Some(stop) = self.stop.take() {
            let _ = stop.send(());
        }
        let _ = timeout(Duration::from_secs(5), self.done).await;
        let _ = std::fs::remove_file(path);
    }
}

/// A socket path short enough for `sun_path` (about 104 bytes on macOS).
fn socket(test: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("f250-pm-{test}-{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("temp dir");
    dir.join("camera.sock")
}

fn link(
    path: &Path,
    call_ms: u64,
    max_age_ms: u64,
) -> (Link, mpsc::UnboundedReceiver<(Direction, Outcome)>) {
    let (tx, rx) = mpsc::unbounded_channel();
    let link = Link::spawn(
        LinkConfig {
            endpoint: format!("unix:{}", path.display()),
            call_timeout: Duration::from_millis(call_ms),
            max_age: Duration::from_millis(max_age_ms),
        },
        move |d, o| {
            let _ = tx.send((d, o));
        },
    )
    .expect("link");
    (link, rx)
}

async fn next(rx: &mut mpsc::UnboundedReceiver<(Direction, Outcome)>) -> (Direction, Outcome) {
    timeout(Duration::from_secs(5), rx.recv())
        .await
        .expect("an outcome in 5 s")
        .expect("link task alive")
}

fn camera_of(outcome: &Outcome) -> Option<pb::Camera> {
    match outcome {
        Outcome::Delivered(v) => pb::Camera::try_from(v.camera).ok(),
        _ => None,
    }
}

#[tokio::test]
async fn moves_reach_camera_manager_with_the_source() {
    let path = socket("deliver");
    let server = Server::start(&path, Duration::ZERO);
    let (link, mut rx) = link(&path, 1000, 1000);

    link.send(Direction::Back).expect("queued");
    let (d, o) = next(&mut rx).await;
    assert_eq!(d, Direction::Back);
    assert_eq!(camera_of(&o), Some(pb::Camera::Rear), "{o:?}");

    link.send(Direction::Left).expect("queued");
    link.send(Direction::Press).expect("queued");
    assert_eq!(camera_of(&next(&mut rx).await.1), Some(pb::Camera::Left));
    assert_eq!(next(&mut rx).await.0, Direction::Press);

    let seen = server.seen();
    assert_eq!(
        seen.iter().map(|(m, _)| *m).collect::<Vec<_>>(),
        [
            pb::SwitchMove::Back,
            pb::SwitchMove::Left,
            pb::SwitchMove::Press
        ]
    );
    assert!(seen.iter().all(|(_, s)| s == SOURCE));
    server.stop(&path).await;
}

#[tokio::test]
async fn without_camera_manager_a_move_fails_fast_and_the_link_finds_it_later() {
    let path = socket("absent");
    let _ = std::fs::remove_file(&path);
    let (link, mut rx) = link(&path, 500, 1000);

    let started = Instant::now();
    link.send(Direction::Right).expect("queued");
    let (d, o) = next(&mut rx).await;
    assert_eq!(d, Direction::Right);
    assert!(matches!(o, Outcome::Failed(_)), "{o:?}");
    assert!(
        started.elapsed() < Duration::from_millis(1500),
        "took {:?}",
        started.elapsed()
    );

    // camera-manager starts: the next move gets through on the same link.
    let server = Server::start(&path, Duration::ZERO);
    link.send(Direction::Right).expect("queued");
    let (_, o) = next(&mut rx).await;
    assert_eq!(camera_of(&o), Some(pb::Camera::Right), "{o:?}");
    server.stop(&path).await;
}

#[tokio::test]
async fn the_link_survives_a_camera_manager_restart() {
    let path = socket("restart");
    let server = Server::start(&path, Duration::ZERO);
    let (link, mut rx) = link(&path, 500, 1000);
    link.send(Direction::Back).expect("queued");
    assert!(matches!(next(&mut rx).await.1, Outcome::Delivered(_)));
    server.stop(&path).await;

    // Down: the move fails, nothing hangs.
    link.send(Direction::Back).expect("queued");
    assert!(matches!(next(&mut rx).await.1, Outcome::Failed(_)));

    // Back on the same path: delivered again. The first call after a
    // restart may still see the old connection fail, so allow one retry by
    // the driver, as on the truck.
    let server = Server::start(&path, Duration::ZERO);
    let mut delivered = false;
    for _ in 0..2 {
        link.send(Direction::Forward).expect("queued");
        if matches!(next(&mut rx).await.1, Outcome::Delivered(_)) {
            delivered = true;
            break;
        }
    }
    assert!(delivered, "no move delivered after the restart");
    assert!(
        server
            .seen()
            .iter()
            .any(|(m, _)| *m == pb::SwitchMove::Forward)
    );
    server.stop(&path).await;
}

#[tokio::test]
async fn a_slow_camera_manager_times_out() {
    let path = socket("slow");
    let server = Server::start(&path, Duration::from_millis(800));
    let (link, mut rx) = link(&path, 150, 5000);
    let started = Instant::now();
    link.send(Direction::Left).expect("queued");
    let (_, o) = next(&mut rx).await;
    match o {
        Outcome::Failed(why) => assert!(why.contains("no answer in 150 ms"), "{why}"),
        other => panic!("expected a timeout, got {other:?}"),
    }
    assert!(
        started.elapsed() < Duration::from_millis(700),
        "took {:?}",
        started.elapsed()
    );
    server.stop(&path).await;
}

#[tokio::test]
async fn moves_that_waited_too_long_are_dropped_not_sent() {
    let path = socket("old");
    // Each call takes 300 ms; moves may wait 100 ms.
    let server = Server::start(&path, Duration::from_millis(300));
    let (link, mut rx) = link(&path, 2000, 100);
    for d in [Direction::Left, Direction::Right, Direction::Back] {
        link.send(d).expect("queued");
    }
    let (d, o) = next(&mut rx).await;
    assert_eq!(d, Direction::Left);
    assert!(matches!(o, Outcome::Delivered(_)), "{o:?}");
    for want in [Direction::Right, Direction::Back] {
        let (d, o) = next(&mut rx).await;
        assert_eq!(d, want);
        assert!(
            matches!(o, Outcome::TooOld(w) if w >= Duration::from_millis(100)),
            "{o:?}"
        );
    }
    // Only the first reached camera-manager.
    assert_eq!(
        server.seen().iter().map(|(m, _)| *m).collect::<Vec<_>>(),
        [pb::SwitchMove::Left]
    );
    server.stop(&path).await;
}

#[tokio::test]
async fn sending_never_waits_and_a_full_queue_drops_moves() {
    let path = socket("full");
    let server = Server::start(&path, Duration::from_millis(500));
    let (link, mut rx) = link(&path, 2000, 5000);

    let started = Instant::now();
    let results: Vec<Result<(), NotQueued>> =
        (0..20).map(|_| link.send(Direction::Press)).collect();
    assert!(
        started.elapsed() < Duration::from_millis(50),
        "send waited {:?}",
        started.elapsed()
    );
    let queued = results.iter().filter(|r| r.is_ok()).count();
    assert!(
        results.contains(&Err(NotQueued::QueueFull)),
        "nothing dropped: {results:?}"
    );
    assert!((1..=5).contains(&queued), "{queued} queued");

    // The first one still gets through.
    assert!(matches!(next(&mut rx).await.1, Outcome::Delivered(_)));
    server.stop(&path).await;
}
