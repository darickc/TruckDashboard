//! The `f250.power.v1` `SwitchService` (ADR-0051), served next to the display
//! API. Thin: requests go to the main loop, which owns the
//! [`Control`](crate::switch_control::Control); the state comes from its
//! watch channel and presses from its broadcast.

use std::pin::Pin;

use f250_proto::power::v1 as pb;
use pb::switch_service_server::SwitchService;
use tokio::sync::{broadcast, mpsc, oneshot, watch};
use tokio_stream::wrappers::{BroadcastStream, WatchStream};
use tokio_stream::{Stream, StreamExt};
use tonic::{Request, Response, Status};

use crate::switch_control::{Command, Saved, mapping_from_pb};

#[derive(Clone)]
pub struct Api {
    cmds: mpsc::Sender<Command>,
    state: watch::Receiver<pb::SwitchState>,
    presses: broadcast::Sender<pb::Press>,
}

impl Api {
    pub fn new(
        cmds: mpsc::Sender<Command>,
        state: watch::Receiver<pb::SwitchState>,
        presses: broadcast::Sender<pb::Press>,
    ) -> Self {
        Api {
            cmds,
            state,
            presses,
        }
    }

    async fn ask<T>(&self, make: impl FnOnce(oneshot::Sender<T>) -> Command) -> Result<T, Status> {
        let stopped = || Status::unavailable("power-manager's switch loop stopped");
        let (reply, rx) = oneshot::channel();
        self.cmds.send(make(reply)).await.map_err(|_| stopped())?;
        rx.await.map_err(|_| stopped())
    }
}

fn source_of(s: &str) -> String {
    if s.trim().is_empty() {
        "unnamed client".to_string()
    } else {
        s.chars().filter(|c| !c.is_control()).take(64).collect()
    }
}

type SwitchStream = Pin<Box<dyn Stream<Item = Result<pb::WatchSwitchResponse, Status>> + Send>>;

#[tonic::async_trait]
impl SwitchService for Api {
    type WatchSwitchStream = SwitchStream;

    async fn watch_switch(
        &self,
        _: Request<pb::WatchSwitchRequest>,
    ) -> Result<Response<Self::WatchSwitchStream>, Status> {
        use pb::watch_switch_response::Event;
        // Subscribed before the state is read, so no press falls between.
        let presses = BroadcastStream::new(self.presses.subscribe())
            // A client too slow for the presses misses some; the state
            // still comes.
            .filter_map(|p| p.ok())
            .map(Event::Press);
        let states = WatchStream::new(self.state.clone()).map(Event::State);
        let stream = states
            .merge(presses)
            .map(|event| Ok(pb::WatchSwitchResponse { event: Some(event) }));
        Ok(Response::new(Box::pin(stream)))
    }

    async fn set_learning(
        &self,
        req: Request<pb::SetLearningRequest>,
    ) -> Result<Response<pb::SetLearningResponse>, Status> {
        let req = req.into_inner();
        let source = source_of(&req.source);
        let state = self
            .ask(|reply| Command::Learning {
                on: req.on,
                source,
                reply,
            })
            .await?;
        Ok(Response::new(pb::SetLearningResponse {
            state: Some(state),
        }))
    }

    async fn set_mapping(
        &self,
        req: Request<pb::SetMappingRequest>,
    ) -> Result<Response<pb::SetMappingResponse>, Status> {
        let req = req.into_inner();
        let source = source_of(&req.source);
        let mapping = match mapping_from_pb(&req.wires) {
            Ok(m) => m,
            Err(detail) => {
                return Ok(Response::new(pb::SetMappingResponse {
                    saved: false,
                    detail,
                    state: Some(self.state.borrow().clone()),
                }));
            }
        };
        let Saved {
            saved,
            detail,
            state,
        } = self
            .ask(|reply| Command::Mapping {
                mapping,
                source,
                reply,
            })
            .await?;
        Ok(Response::new(pb::SetMappingResponse {
            saved,
            detail,
            state: Some(state),
        }))
    }

    async fn reset_mapping(
        &self,
        req: Request<pb::ResetMappingRequest>,
    ) -> Result<Response<pb::ResetMappingResponse>, Status> {
        let source = source_of(&req.into_inner().source);
        let Saved {
            saved,
            detail,
            state,
        } = self.ask(|reply| Command::Reset { source, reply }).await?;
        Ok(Response::new(pb::ResetMappingResponse {
            saved,
            detail,
            state: Some(state),
        }))
    }
}
