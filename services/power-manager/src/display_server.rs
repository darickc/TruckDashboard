//! The `f250.power.v1` `DisplayService` (ADR-0028 decision 7). Thin: changes
//! go to the display task ([`crate::display::run`]); the state comes from its
//! watch channel.

use std::pin::Pin;

use f250_proto::power::v1 as pb;
use pb::display_service_server::DisplayService;
use tokio::sync::{mpsc, oneshot, watch};
use tokio_stream::{Stream, StreamExt, wrappers::WatchStream};
use tonic::{Request, Response, Status};

use crate::display::{Change, Command, choice_from_pb};

#[derive(Clone)]
pub struct Api {
    cmds: mpsc::Sender<Command>,
    display: watch::Receiver<pb::Display>,
}

impl Api {
    pub fn new(cmds: mpsc::Sender<Command>, display: watch::Receiver<pb::Display>) -> Self {
        Api { cmds, display }
    }
}

type DisplayStream = Pin<Box<dyn Stream<Item = Result<pb::WatchDisplayResponse, Status>> + Send>>;

fn source_of(s: &str) -> String {
    if s.trim().is_empty() {
        "unnamed client".to_string()
    } else {
        s.chars().take(64).collect()
    }
}

/// The request as a [`Change`]; an unknown choice is an error, zero is
/// "unchanged".
pub fn change_of(req: &pb::SetDisplayRequest) -> Result<Change, Status> {
    let choice = match req.choice {
        0 => None,
        v => Some(choice_from_pb(v).ok_or_else(|| {
            Status::invalid_argument("choice must be AUTO, DAY or NIGHT (or unset)")
        })?),
    };
    let pct = |v: u32| (v != 0).then_some(v);
    Ok(Change {
        choice,
        day_pct: pct(req.day_brightness_pct),
        night_pct: pct(req.night_brightness_pct),
    })
}

#[tonic::async_trait]
impl DisplayService for Api {
    type WatchDisplayStream = DisplayStream;

    async fn watch_display(
        &self,
        _: Request<pb::WatchDisplayRequest>,
    ) -> Result<Response<Self::WatchDisplayStream>, Status> {
        // The current value first, then each change. The channel starts
        // empty (no mode) until the task's first decision; that value is
        // skipped, so a client never takes "undecided" for a state.
        let stream = WatchStream::new(self.display.clone())
            .filter(|d| d.mode != pb::DisplayMode::Unspecified as i32)
            .map(|display| {
                Ok(pb::WatchDisplayResponse {
                    display: Some(display),
                })
            });
        Ok(Response::new(Box::pin(stream)))
    }

    async fn set_display(
        &self,
        req: Request<pb::SetDisplayRequest>,
    ) -> Result<Response<pb::SetDisplayResponse>, Status> {
        let req = req.into_inner();
        let change = change_of(&req)?;
        let (reply, rx) = oneshot::channel();
        self.cmds
            .send(Command {
                change,
                source: source_of(&req.source),
                reply,
            })
            .await
            .map_err(|_| Status::unavailable("power-manager's display task stopped"))?;
        let display = rx
            .await
            .map_err(|_| Status::unavailable("power-manager's display task stopped"))?;
        Ok(Response::new(pb::SetDisplayResponse {
            display: Some(display),
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use daylight::Choice;

    #[test]
    fn requests_become_changes() {
        let c = change_of(&pb::SetDisplayRequest {
            choice: pb::DisplayChoice::Night as i32,
            day_brightness_pct: 0,
            night_brightness_pct: 30,
            source: String::new(),
        })
        .expect("valid");
        assert_eq!(c.choice, Some(Choice::Night));
        assert_eq!(c.day_pct, None);
        assert_eq!(c.night_pct, Some(30));
        assert_eq!(
            change_of(&pb::SetDisplayRequest::default()).expect("valid"),
            Change::default()
        );
        assert!(
            change_of(&pb::SetDisplayRequest {
                choice: 42,
                ..Default::default()
            })
            .is_err()
        );
    }

    #[test]
    fn sources_are_named_and_bounded() {
        assert_eq!(source_of("  "), "unnamed client");
        assert_eq!(source_of(&"x".repeat(100)).len(), 64);
    }
}
