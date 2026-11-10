//! The `f250.camera.v1` gRPC service. Thin: moves go to the control loop
//! (crate::manager); the view comes from its watch channel.

use std::pin::Pin;

use f250_proto::camera::v1 as pb;
use pb::camera_service_server::CameraService;
use tokio::sync::{mpsc, oneshot, watch};
use tokio_stream::{Stream, StreamExt, wrappers::WatchStream};
use tonic::{Request, Response, Status};

use crate::manager::{Command, move_from_pb};

#[derive(Clone)]
pub struct Api {
    cmds: mpsc::Sender<Command>,
    view: watch::Receiver<pb::View>,
}

impl Api {
    pub fn new(cmds: mpsc::Sender<Command>, view: watch::Receiver<pb::View>) -> Self {
        Api { cmds, view }
    }
}

type ViewStream = Pin<Box<dyn Stream<Item = Result<pb::WatchViewResponse, Status>> + Send>>;

#[tonic::async_trait]
impl CameraService for Api {
    type WatchViewStream = ViewStream;

    async fn watch_view(
        &self,
        _: Request<pb::WatchViewRequest>,
    ) -> Result<Response<Self::WatchViewStream>, Status> {
        // WatchStream yields the current value first, then each change.
        let stream = WatchStream::new(self.view.clone())
            .map(|view| Ok(pb::WatchViewResponse { view: Some(view) }));
        Ok(Response::new(Box::pin(stream)))
    }

    async fn r#move(
        &self,
        req: Request<pb::MoveRequest>,
    ) -> Result<Response<pb::MoveResponse>, Status> {
        let req = req.into_inner();
        let mv = move_from_pb(req.r#move).ok_or_else(|| {
            Status::invalid_argument("move must be LEFT, RIGHT, BACK, FORWARD or PRESS")
        })?;
        let source = if req.source.trim().is_empty() {
            "unnamed client".to_string()
        } else {
            req.source.chars().take(64).collect()
        };
        let (reply, rx) = oneshot::channel();
        self.cmds
            .send(Command::Move { mv, source, reply })
            .await
            .map_err(|_| Status::unavailable("camera-manager loop stopped"))?;
        let view = rx
            .await
            .map_err(|_| Status::unavailable("camera-manager loop stopped"))?;
        Ok(Response::new(pb::MoveResponse { view: Some(view) }))
    }
}
