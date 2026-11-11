//! The `f250.camera.v1` gRPC service. Thin: moves and "save clip" go to
//! the control loop (crate::manager); the view and the recording state come
//! from its watch channels.

use std::pin::Pin;

use f250_proto::camera::v1 as pb;
use pb::camera_service_server::CameraService;
use tokio::sync::{mpsc, oneshot, watch};
use tokio_stream::{Stream, StreamExt, wrappers::WatchStream};
use tonic::{Request, Response, Status};

use crate::manager::{Command, Watches, move_from_pb};

#[derive(Clone)]
pub struct Api {
    cmds: mpsc::Sender<Command>,
    view: watch::Receiver<pb::View>,
    recording: watch::Receiver<pb::Recording>,
}

impl Api {
    pub fn new(cmds: mpsc::Sender<Command>, watches: Watches) -> Self {
        Api {
            cmds,
            view: watches.view,
            recording: watches.recording,
        }
    }
}

type ViewStream = Pin<Box<dyn Stream<Item = Result<pb::WatchViewResponse, Status>> + Send>>;
type RecordingStream =
    Pin<Box<dyn Stream<Item = Result<pb::WatchRecordingResponse, Status>> + Send>>;

fn source_of(s: &str) -> String {
    if s.trim().is_empty() {
        "unnamed client".to_string()
    } else {
        s.chars().take(64).collect()
    }
}

#[tonic::async_trait]
impl CameraService for Api {
    type WatchViewStream = ViewStream;
    type WatchRecordingStream = RecordingStream;

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
        let source = source_of(&req.source);
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

    async fn watch_recording(
        &self,
        _: Request<pb::WatchRecordingRequest>,
    ) -> Result<Response<Self::WatchRecordingStream>, Status> {
        let stream = WatchStream::new(self.recording.clone()).map(|recording| {
            Ok(pb::WatchRecordingResponse {
                recording: Some(recording),
            })
        });
        Ok(Response::new(Box::pin(stream)))
    }

    async fn save_clip(
        &self,
        req: Request<pb::SaveClipRequest>,
    ) -> Result<Response<pb::SaveClipResponse>, Status> {
        let source = source_of(&req.into_inner().source);
        let (reply, rx) = oneshot::channel();
        self.cmds
            .send(Command::SaveClip { source, reply })
            .await
            .map_err(|_| Status::unavailable("camera-manager loop stopped"))?;
        let r = rx
            .await
            .map_err(|_| Status::unavailable("camera-manager loop stopped"))?;
        Ok(Response::new(r))
    }
}
