//! Passes camera-switch moves to camera-manager: its `f250.camera.v1` `Move`
//! call ([ADR-0026](../../../docs/architecture/adr/0026-camera-manager-interfaces.md)).
//!
//! The power key comes first. Nothing here can hold up the main loop:
//!
//! - [`Link::send`] never waits. Moves go into a short queue; when it is full
//!   the move is dropped and the caller logs it.
//! - One task makes the calls, each with a timeout ([`LinkConfig::call_timeout`]).
//! - A move that waited longer than [`LinkConfig::max_age`] is dropped, not
//!   sent: a camera change the driver asked for seconds ago is a surprise, not
//!   a help.
//! - A move that fails isn't retried. The driver moves the switch again.
//!
//! The connection is lazy: power-manager starts and runs without
//! camera-manager, and finds it once it is there, or again after it restarts.
//!
//! Both times are example values, not measured requirements.

use std::time::Duration;

use f250_proto::camera::v1 as pb;
use hyper_util::rt::TokioIo;
use pb::camera_service_client::CameraServiceClient;
use tokio::sync::mpsc;
use tokio::time::Instant;
use tonic::transport::{Channel, Endpoint, Uri};

use crate::camera_switch::Direction;

/// The name camera-manager logs for these moves.
pub const SOURCE: &str = "power-manager (camera switch)";

/// How many moves may wait for the call before newer ones are dropped.
const QUEUE: usize = 4;

#[derive(Debug, Clone)]
pub struct LinkConfig {
    /// `unix:PATH` or `tcp:HOST:PORT`.
    pub endpoint: String,
    /// Connecting plus the call. An example value.
    pub call_timeout: Duration,
    /// A move older than this when its turn comes is dropped. An example
    /// value.
    pub max_age: Duration,
}

/// What became of one move.
#[derive(Debug, Clone, PartialEq)]
pub enum Outcome {
    /// camera-manager took it; the view it answered with.
    Delivered(pb::View),
    /// The call failed or timed out.
    Failed(String),
    /// It waited too long behind other calls and wasn't sent.
    TooOld(Duration),
}

/// The sending side. Dropping it ends the task once the queue is empty.
#[derive(Debug, Clone)]
pub struct Link {
    tx: mpsc::Sender<(Direction, Instant)>,
}

/// Why [`Link::send`] didn't queue a move.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NotQueued {
    /// Calls are slower than the switch: the move is dropped.
    QueueFull,
    /// The task ended (it shouldn't).
    Closed,
}

impl Link {
    /// Starts the task that makes the calls. `report` is called once per move
    /// with what became of it.
    pub fn spawn<R>(cfg: LinkConfig, mut report: R) -> Result<Link, String>
    where
        R: FnMut(Direction, Outcome) + Send + 'static,
    {
        let channel = channel(&cfg)?;
        let (tx, mut rx) = mpsc::channel::<(Direction, Instant)>(QUEUE);
        tokio::spawn(async move {
            let mut client = CameraServiceClient::new(channel);
            while let Some((direction, at)) = rx.recv().await {
                let waited = at.elapsed();
                let outcome = if waited > cfg.max_age {
                    Outcome::TooOld(waited)
                } else {
                    call(&mut client, direction, cfg.call_timeout).await
                };
                report(direction, outcome);
            }
        });
        Ok(Link { tx })
    }

    /// Queues a move without waiting.
    pub fn send(&self, direction: Direction) -> Result<(), NotQueued> {
        self.tx
            .try_send((direction, Instant::now()))
            .map_err(|e| match e {
                mpsc::error::TrySendError::Full(_) => NotQueued::QueueFull,
                mpsc::error::TrySendError::Closed(_) => NotQueued::Closed,
            })
    }
}

pub fn switch_move(direction: Direction) -> pb::SwitchMove {
    match direction {
        Direction::Left => pb::SwitchMove::Left,
        Direction::Right => pb::SwitchMove::Right,
        Direction::Back => pb::SwitchMove::Back,
        Direction::Forward => pb::SwitchMove::Forward,
        Direction::Press => pb::SwitchMove::Press,
    }
}

/// A short description of a view for the log: `rear (live)`,
/// `dashboard`, `left (unavailable: no left camera configured)`.
pub fn describe_view(view: &pb::View) -> String {
    let camera = match pb::Camera::try_from(view.camera) {
        Ok(pb::Camera::Left) => "left camera",
        Ok(pb::Camera::Right) => "right camera",
        Ok(pb::Camera::Rear) => "rear camera",
        _ => return "dashboard".to_string(),
    };
    let feed = match pb::FeedState::try_from(view.feed) {
        Ok(pb::FeedState::Starting) => "starting".to_string(),
        Ok(pb::FeedState::Live) => "live".to_string(),
        Ok(pb::FeedState::Unavailable) if view.feed_detail.is_empty() => "unavailable".to_string(),
        Ok(pb::FeedState::Unavailable) => format!("unavailable: {}", view.feed_detail),
        _ => "feed unknown".to_string(),
    };
    format!("{camera} ({feed})")
}

async fn call(
    client: &mut CameraServiceClient<Channel>,
    direction: Direction,
    timeout: Duration,
) -> Outcome {
    let request = pb::MoveRequest {
        r#move: switch_move(direction) as i32,
        source: SOURCE.to_string(),
    };
    match tokio::time::timeout(timeout, client.r#move(request)).await {
        Err(_) => Outcome::Failed(format!("no answer in {} ms", timeout.as_millis())),
        Ok(Err(status)) => Outcome::Failed(status_text(&status)),
        Ok(Ok(response)) => match response.into_inner().view {
            Some(view) => Outcome::Delivered(view),
            None => Outcome::Failed("camera-manager answered without a view".to_string()),
        },
    }
}

/// A status without tonic's debug noise: the code, then the message.
fn status_text(status: &tonic::Status) -> String {
    let message = status.message();
    if message.is_empty() {
        format!("{:?}", status.code())
    } else {
        format!("{:?}: {message}", status.code())
    }
}

/// A channel that connects on first use and again after a failure.
fn channel(cfg: &LinkConfig) -> Result<Channel, String> {
    let endpoint = &cfg.endpoint;
    if let Some(path) = endpoint.strip_prefix("unix:") {
        let path = path.to_string();
        Ok(Endpoint::from_static("http://localhost")
            .connect_timeout(cfg.call_timeout)
            .connect_with_connector_lazy(tower::service_fn(move |_: Uri| {
                let path = path.clone();
                async move {
                    tokio::net::UnixStream::connect(path)
                        .await
                        .map(TokioIo::new)
                }
            })))
    } else if let Some(addr) = endpoint.strip_prefix("tcp:") {
        Ok(Endpoint::try_from(format!("http://{addr}"))
            .map_err(|e| format!("bad --camera-manager {endpoint}: {e}"))?
            .connect_timeout(cfg.call_timeout)
            .connect_lazy())
    } else {
        Err(format!(
            "--camera-manager must start with unix: or tcp:, got {endpoint}"
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_direction_maps_to_its_move() {
        let moves: Vec<pb::SwitchMove> = Direction::ALL.into_iter().map(switch_move).collect();
        assert_eq!(
            moves,
            [
                pb::SwitchMove::Left,
                pb::SwitchMove::Right,
                pb::SwitchMove::Back,
                pb::SwitchMove::Forward,
                pb::SwitchMove::Press,
            ]
        );
    }

    #[test]
    fn views_read_plainly_in_the_log() {
        let mut v = pb::View::default();
        assert_eq!(describe_view(&v), "dashboard");
        v.camera = pb::Camera::Rear as i32;
        v.feed = pb::FeedState::Live as i32;
        assert_eq!(describe_view(&v), "rear camera (live)");
        v.camera = pb::Camera::Left as i32;
        v.feed = pb::FeedState::Unavailable as i32;
        v.feed_detail = "no left camera configured".into();
        assert_eq!(
            describe_view(&v),
            "left camera (unavailable: no left camera configured)"
        );
    }

    #[tokio::test]
    async fn a_bad_endpoint_is_refused_at_start() {
        let cfg = LinkConfig {
            endpoint: "/run/f250-camera/camera.sock".into(),
            call_timeout: Duration::from_millis(100),
            max_age: Duration::from_secs(1),
        };
        let err = Link::spawn(cfg, |_, _| {}).expect_err("no scheme");
        assert!(err.contains("unix: or tcp:"), "{err}");
    }
}
