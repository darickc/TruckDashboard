//! The control loop: feeds the camera policy, runs the pipeline for the
//! camera it picks, and publishes what is on screen (ADR-0026).
//!
//! - One pipeline at a time, only for the camera on screen.
//! - A camera counts as up only once its pipeline delivers frames.
//! - No frame for `frame_timeout` (or none within `start_timeout` of the
//!   start), or the process ending, makes it unavailable and **kills the
//!   pipeline**, closing its window, so no frozen frame stays on screen.
//!   It is retried after a backoff while the view still wants it.

use std::time::Duration;

use camera_policy::{Camera, Input, Move, Policy, ReverseStatus, Why};
use f250_proto::camera::v1 as pb;
use f250_sd_notify::Heartbeat;
use tokio::sync::{mpsc, oneshot, watch};
use tokio::time::Instant;

use crate::config::{Settings, camera_name};
use crate::pipeline::{self, Event, Running};

/// The loop wakes at least this often, to beat the heartbeat.
const IDLE_WAKE: Duration = Duration::from_secs(1);

pub enum Command {
    Move {
        mv: Move,
        source: String,
        reply: oneshot::Sender<pb::View>,
    },
}

enum Feed {
    /// No camera wanted.
    Off,
    Starting {
        camera: Camera,
        run: Running,
        since: Instant,
    },
    Live {
        camera: Camera,
        run: Running,
        last_frame: Instant,
    },
    Down {
        camera: Camera,
        detail: String,
        /// When to try again; `None` when retrying can't help (no device).
        retry_at: Option<Instant>,
    },
}

impl Feed {
    fn camera(&self) -> Option<Camera> {
        match self {
            Feed::Off => None,
            Feed::Starting { camera, .. }
            | Feed::Live { camera, .. }
            | Feed::Down { camera, .. } => Some(*camera),
        }
    }

    fn generation(&self) -> Option<u64> {
        match self {
            Feed::Starting { run, .. } | Feed::Live { run, .. } => Some(run.generation),
            _ => None,
        }
    }
}

pub struct Manager {
    settings: Settings,
    policy: Policy,
    feed: Feed,
    generation: u64,
    backoff: Duration,
    start: Instant,
    events_tx: mpsc::Sender<Event>,
    events_rx: Option<mpsc::Receiver<Event>>,
    view_tx: watch::Sender<pb::View>,
    heartbeat: Heartbeat,
}

impl Manager {
    pub fn new(settings: Settings) -> (Manager, watch::Receiver<pb::View>) {
        let policy = Policy::new(settings.policy.clone());
        let (events_tx, events_rx) = mpsc::channel(256);
        let (view_tx, view_rx) = watch::channel(pb::View::default());
        let backoff = settings.restart_min;
        let m = Manager {
            settings,
            policy,
            feed: Feed::Off,
            generation: 0,
            backoff,
            start: Instant::now(),
            events_tx,
            events_rx: Some(events_rx),
            view_tx,
            heartbeat: Heartbeat::new(),
        };
        let first = m.api_view();
        m.view_tx.send_replace(first);
        (m, view_rx)
    }

    pub fn heartbeat(&self) -> Heartbeat {
        self.heartbeat.clone()
    }

    /// Runs until the command channel closes, then stops any pipeline.
    pub async fn run(mut self, mut cmds: mpsc::Receiver<Command>) {
        let Some(mut events) = self.events_rx.take() else {
            return;
        };
        self.log_view();
        loop {
            self.heartbeat.beat();
            let wake = self.next_wake(Instant::now());
            tokio::select! {
                c = cmds.recv() => match c {
                    Some(c) => self.command(c).await,
                    None => break,
                },
                Some(e) = events.recv() => self.event(e).await,
                () = tokio::time::sleep_until(wake) => self.tick().await,
            }
        }
        self.stop_feed().await;
    }

    fn now_d(&self, now: Instant) -> Duration {
        now.saturating_duration_since(self.start)
    }

    fn next_wake(&self, now: Instant) -> Instant {
        let mut wake = now + IDLE_WAKE;
        let mut consider = |t: Instant| wake = wake.min(t);
        if let Some(d) = self.policy.deadline() {
            consider(self.start + d);
        }
        match &self.feed {
            Feed::Starting { since, .. } => consider(*since + self.settings.start_timeout),
            Feed::Live { last_frame, .. } => consider(*last_frame + self.settings.frame_timeout),
            Feed::Down {
                retry_at: Some(t), ..
            } => consider(*t),
            _ => {}
        }
        wake
    }

    async fn command(&mut self, c: Command) {
        match c {
            Command::Move { mv, source, reply } => {
                let now = Instant::now();
                eprintln!("[camera] switch: {} (from {source})", move_name(mv));
                self.policy.handle(Input::Switch(mv), self.now_d(now));
                self.reconcile(now).await;
                self.publish();
                let _ = reply.send(self.api_view());
            }
        }
    }

    async fn event(&mut self, e: Event) {
        let now = Instant::now();
        match e {
            Event::Frame { generation } => {
                if self.feed.generation() != Some(generation) {
                    return; // a stopped pipeline's last frame
                }
                match std::mem::replace(&mut self.feed, Feed::Off) {
                    Feed::Starting { camera, run, since } => {
                        eprintln!(
                            "[camera] {} camera live: first frame after {} ms",
                            camera_name(camera),
                            now.saturating_duration_since(since).as_millis()
                        );
                        self.backoff = self.settings.restart_min;
                        self.policy.handle(Input::CameraUp(camera), self.now_d(now));
                        self.feed = Feed::Live {
                            camera,
                            run,
                            last_frame: now,
                        };
                        self.publish();
                    }
                    Feed::Live { camera, run, .. } => {
                        self.feed = Feed::Live {
                            camera,
                            run,
                            last_frame: now,
                        };
                    }
                    other => self.feed = other,
                }
            }
            Event::Ended { generation, detail } => {
                if self.feed.generation() == Some(generation) {
                    self.fail(now, detail).await;
                    self.publish();
                }
            }
        }
    }

    async fn tick(&mut self) {
        let now = Instant::now();
        self.policy.handle(Input::Tick, self.now_d(now));
        match &self.feed {
            Feed::Starting { since, .. } if now >= *since + self.settings.start_timeout => {
                let ms = self.settings.start_timeout.as_millis();
                self.fail(now, format!("no frame within {ms} ms of starting"))
                    .await;
            }
            Feed::Live { last_frame, .. } if now >= *last_frame + self.settings.frame_timeout => {
                let ms = self.settings.frame_timeout.as_millis();
                self.fail(now, format!("no frame for {ms} ms")).await;
            }
            Feed::Down {
                camera,
                retry_at: Some(t),
                ..
            } if now >= *t && self.policy.view().camera == Some(*camera) => {
                let camera = *camera;
                self.feed = Feed::Off;
                self.start_camera(now, camera);
            }
            _ => {}
        }
        self.reconcile(now).await;
        self.publish();
    }

    /// Runs the pipeline the view wants, and only that one.
    async fn reconcile(&mut self, now: Instant) {
        let wanted = self.policy.view().camera;
        if self.feed.camera() == wanted {
            return;
        }
        self.stop_feed().await;
        self.backoff = self.settings.restart_min;
        if let Some(c) = wanted {
            self.start_camera(now, c);
        }
    }

    fn start_camera(&mut self, now: Instant, camera: Camera) {
        let name = camera_name(camera);
        let Some(device) = self.settings.device(camera).map(String::from) else {
            eprintln!("[camera] {name} camera chosen, but none is configured");
            self.feed = Feed::Down {
                camera,
                detail: format!("no {name} camera configured (--camera {name}=DEVICE)"),
                retry_at: None,
            };
            return;
        };
        self.generation += 1;
        let args = pipeline::args(&device, &self.settings.caps, &self.settings.sink);
        match Running::spawn(
            &self.settings.gst_launch,
            &args,
            self.generation,
            self.events_tx.clone(),
        ) {
            Ok(run) => {
                eprintln!("[camera] {name} camera starting ({device})");
                self.feed = Feed::Starting {
                    camera,
                    run,
                    since: now,
                };
            }
            Err(e) => {
                let detail = format!("{}: {e}", self.settings.gst_launch);
                eprintln!(
                    "[camera] {name} camera: {detail}; retry in {} ms",
                    self.backoff.as_millis()
                );
                self.feed = Feed::Down {
                    camera,
                    detail,
                    retry_at: Some(now + self.backoff),
                };
                self.backoff = (self.backoff * 2).min(self.settings.restart_max);
            }
        }
    }

    /// The running pipeline failed: stop it (closing its window) and retry
    /// later.
    async fn fail(&mut self, now: Instant, detail: String) {
        let Some(camera) = self.feed.camera() else {
            return;
        };
        self.stop_feed().await;
        eprintln!(
            "[camera] {} camera unavailable: {detail}; retry in {} ms",
            camera_name(camera),
            self.backoff.as_millis()
        );
        self.feed = Feed::Down {
            camera,
            detail,
            retry_at: Some(now + self.backoff),
        };
        self.backoff = (self.backoff * 2).min(self.settings.restart_max);
    }

    async fn stop_feed(&mut self) {
        let now = Instant::now();
        match std::mem::replace(&mut self.feed, Feed::Off) {
            Feed::Starting { camera, run, .. } | Feed::Live { camera, run, .. } => {
                run.stop().await;
                self.policy
                    .handle(Input::CameraDown(camera), self.now_d(now));
            }
            Feed::Down { camera, .. } => {
                self.policy
                    .handle(Input::CameraDown(camera), self.now_d(now));
            }
            Feed::Off => {}
        }
    }

    pub fn api_view(&self) -> pb::View {
        let v = self.policy.view();
        let mut out = pb::View {
            camera: v.camera.map_or(pb::Camera::Unspecified, pb_camera) as i32,
            reason: match v.why {
                Some(Why::Reverse) => pb::Reason::Reverse,
                Some(Why::Switch) => pb::Reason::Switch,
                None => pb::Reason::Unspecified,
            } as i32,
            reverse: match v.reverse {
                ReverseStatus::Off => pb::ReverseStatus::Off,
                ReverseStatus::Unknown => pb::ReverseStatus::Unknown,
                ReverseStatus::NotEngaged => pb::ReverseStatus::NotEngaged,
                ReverseStatus::Engaged => pb::ReverseStatus::Engaged,
            } as i32,
            blocked_by_speed: v.blocked_by_speed,
            ..Default::default()
        };
        if v.camera.is_some() && v.camera == self.feed.camera() {
            let (feed, detail) = match &self.feed {
                Feed::Starting { .. } | Feed::Off => (pb::FeedState::Starting, String::new()),
                Feed::Live { .. } => (pb::FeedState::Live, String::new()),
                Feed::Down { detail, .. } => (pb::FeedState::Unavailable, detail.clone()),
            };
            out.feed = feed as i32;
            out.feed_detail = detail;
        } else if v.camera.is_some() {
            // Wanted but not started yet: only between a policy change and
            // the reconcile that follows it.
            out.feed = pb::FeedState::Starting as i32;
        }
        out
    }

    fn publish(&mut self) {
        let next = self.api_view();
        let changed = self.view_tx.send_if_modified(|v| {
            if *v == next {
                false
            } else {
                *v = next;
                true
            }
        });
        if changed {
            self.log_view();
        }
    }

    fn log_view(&self) {
        eprintln!("[camera] view: {}", describe_view(&self.view_tx.borrow()));
    }
}

/// A view as one line, for the service's log and `camera-ctl`:
/// `rear (switch), live; reverse off`.
pub fn describe_view(v: &pb::View) -> String {
    let camera = pb::Camera::try_from(v.camera).unwrap_or(pb::Camera::Unspecified);
    let line = if camera == pb::Camera::Unspecified {
        "no camera".to_string()
    } else {
        let reason = pb::Reason::try_from(v.reason).unwrap_or(pb::Reason::Unspecified);
        let feed = pb::FeedState::try_from(v.feed).unwrap_or(pb::FeedState::Unspecified);
        let mut s = format!(
            "{} ({}), {}",
            camera
                .as_str_name()
                .trim_start_matches("CAMERA_")
                .to_lowercase(),
            reason
                .as_str_name()
                .trim_start_matches("REASON_")
                .to_lowercase(),
            feed.as_str_name()
                .trim_start_matches("FEED_STATE_")
                .to_lowercase()
        );
        if !v.feed_detail.is_empty() {
            s.push_str(": ");
            s.push_str(&v.feed_detail);
        }
        s
    };
    let reverse = pb::ReverseStatus::try_from(v.reverse).unwrap_or(pb::ReverseStatus::Unspecified);
    format!(
        "{line}; reverse {}{}",
        reverse
            .as_str_name()
            .trim_start_matches("REVERSE_STATUS_")
            .to_lowercase(),
        if v.blocked_by_speed {
            "; hidden by the speed limit"
        } else {
            ""
        }
    )
}

pub fn pb_camera(c: Camera) -> pb::Camera {
    match c {
        Camera::Left => pb::Camera::Left,
        Camera::Right => pb::Camera::Right,
        Camera::Rear => pb::Camera::Rear,
    }
}

/// A switch move from the API. `None` for an unspecified or unknown value.
pub fn move_from_pb(v: i32) -> Option<Move> {
    match pb::SwitchMove::try_from(v).ok()? {
        pb::SwitchMove::Unspecified => None,
        pb::SwitchMove::Left => Some(Move::Left),
        pb::SwitchMove::Right => Some(Move::Right),
        pb::SwitchMove::Back => Some(Move::Back),
        pb::SwitchMove::Forward => Some(Move::Forward),
        pb::SwitchMove::Press => Some(Move::Press),
    }
}

fn move_name(m: Move) -> &'static str {
    match m {
        Move::Left => "left",
        Move::Right => "right",
        Move::Back => "back",
        Move::Forward => "forward",
        Move::Press => "press",
    }
}
