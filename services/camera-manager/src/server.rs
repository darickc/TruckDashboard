//! The `f250.camera.v1` gRPC service. Thin: moves and "save clip" go to
//! the control loop (crate::manager); the view and the recording state come
//! from its watch channels.

use std::path::PathBuf;
use std::pin::Pin;
use std::sync::Arc;

use f250_proto::camera::v1 as pb;
use pb::camera_service_server::CameraService;
use tokio::sync::{mpsc, oneshot, watch};
use tokio_stream::{Stream, StreamExt, wrappers::WatchStream};
use tonic::{Request, Response, Status};

use crate::camera_settings::{self, Saved};
use crate::manager::{Command, Watches, move_from_pb};

/// What the settings calls need (ADR-0029).
#[derive(Debug)]
pub struct SettingsCtx {
    /// The settings camera-manager is running with.
    pub current: pb::CameraSettings,
    /// Where `/dev` is, for listing the cameras plugged in.
    pub dev_root: PathBuf,
    /// The saved settings' file; `None`: settings can't be changed.
    pub file: Option<PathBuf>,
    /// Told once settings are saved: camera-manager restarts to apply them.
    pub restart: Arc<tokio::sync::Notify>,
}

#[derive(Clone)]
pub struct Api {
    cmds: mpsc::Sender<Command>,
    view: watch::Receiver<pb::View>,
    recording: watch::Receiver<pb::Recording>,
    settings: Option<Arc<SettingsCtx>>,
}

impl Api {
    pub fn new(cmds: mpsc::Sender<Command>, watches: Watches) -> Self {
        Api {
            cmds,
            view: watches.view,
            recording: watches.recording,
            settings: None,
        }
    }

    pub fn with_settings(mut self, ctx: SettingsCtx) -> Self {
        self.settings = Some(Arc::new(ctx));
        self
    }

    fn settings(&self) -> Result<&Arc<SettingsCtx>, Status> {
        self.settings
            .as_ref()
            .ok_or_else(|| Status::unimplemented("this camera-manager has no settings"))
    }
}

fn refused(detail: impl Into<String>) -> Response<pb::SetCameraSettingsResponse> {
    Response::new(pb::SetCameraSettingsResponse {
        applied: false,
        detail: detail.into(),
    })
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

    async fn get_camera_settings(
        &self,
        _: Request<pb::GetCameraSettingsRequest>,
    ) -> Result<Response<pb::GetCameraSettingsResponse>, Status> {
        let ctx = self.settings()?.clone();
        let dev = ctx.dev_root.clone();
        let devices = tokio::task::spawn_blocking(move || camera_settings::scan(&dev))
            .await
            .unwrap_or_default();
        Ok(Response::new(pb::GetCameraSettingsResponse {
            settings: Some(ctx.current.clone()),
            devices: devices
                .into_iter()
                .map(|d| pb::CameraDevice {
                    path: d.path.to_string_lossy().into_owned(),
                    label: d.label,
                })
                .collect(),
        }))
    }

    async fn set_camera_settings(
        &self,
        req: Request<pb::SetCameraSettingsRequest>,
    ) -> Result<Response<pb::SetCameraSettingsResponse>, Status> {
        let ctx = self.settings()?.clone();
        let req = req.into_inner();
        let source = source_of(&req.source);
        let Some(file) = ctx.file.clone() else {
            return Ok(refused(
                "Settings can't be changed here: camera-manager has no settings file \
                 (--settings-file). Use /etc/default/f250.",
            ));
        };
        // A rear view must never vanish because of a settings change.
        if self.view.borrow().camera != pb::Camera::Unspecified as i32 {
            return Ok(refused(
                "Close the camera first: applying settings restarts camera-manager.",
            ));
        }
        let saved = if req.use_defaults {
            None
        } else {
            match Saved::from_pb(&req.cameras, &req.record) {
                Ok(s) => Some(s),
                Err(e) => return Ok(refused(e)),
            }
        };
        let what = match &saved {
            None => "use /etc/default/f250".to_string(),
            Some(s) => s
                .format()
                .lines()
                .filter(|l| !l.starts_with('#'))
                .collect::<Vec<_>>()
                .join(" "),
        };
        let written = tokio::task::spawn_blocking(move || match &saved {
            None => camera_settings::forget(&file),
            Some(s) => camera_settings::save(&file, s),
        })
        .await
        .map_err(|_| Status::internal("settings write panicked"))?;
        if let Err(e) = written {
            eprintln!("[camera] settings from {source}: {e}");
            return Ok(refused(e));
        }
        eprintln!("[camera] settings from {source}: {what}; restarting to apply them");
        ctx.restart.notify_one();
        Ok(Response::new(pb::SetCameraSettingsResponse {
            applied: true,
            detail: "Saved. camera-manager is restarting to apply them: the cameras are off \
                     for a few seconds."
                .into(),
        }))
    }
}
