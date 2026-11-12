//! The `f250.audio.v1` gRPC service: thin, over [`Manager`].

use std::pin::Pin;
use std::sync::Arc;

use f250_proto::audio::v1 as pb;
use pb::audio_service_server::AudioService;
use tokio_stream::{Stream, StreamExt, wrappers::WatchStream};
use tonic::{Request, Response, Status};

use crate::manager::{Manager, settings_from_pb, settings_pb};
use crate::model::Command;

#[derive(Clone)]
pub struct Api {
    manager: Arc<Manager>,
}

impl Api {
    pub fn new(manager: Arc<Manager>) -> Api {
        Api { manager }
    }
}

fn source_of(s: &str) -> String {
    if s.trim().is_empty() {
        "unnamed client".to_string()
    } else {
        s.chars().filter(|c| !c.is_control()).take(64).collect()
    }
}

type AudioStream = Pin<Box<dyn Stream<Item = Result<pb::WatchAudioResponse, Status>> + Send>>;

#[tonic::async_trait]
impl AudioService for Api {
    type WatchAudioStream = AudioStream;

    async fn watch_audio(
        &self,
        _: Request<pb::WatchAudioRequest>,
    ) -> Result<Response<Self::WatchAudioStream>, Status> {
        // The current value first, then each publish (at least once a second).
        let m = Arc::clone(&self.manager);
        let stream = WatchStream::new(self.manager.watch())
            .take_while(move |_| !m.stopping())
            .map(Ok);
        Ok(Response::new(Box::pin(stream)))
    }

    async fn control(
        &self,
        req: Request<pb::ControlRequest>,
    ) -> Result<Response<pb::ControlResponse>, Status> {
        let req = req.into_inner();
        let cmd = match pb::Command::try_from(req.command) {
            Ok(pb::Command::Play) => Command::Play,
            Ok(pb::Command::Pause) => Command::Pause,
            Ok(pb::Command::Next) => Command::Next,
            Ok(pb::Command::Previous) => Command::Previous,
            _ => {
                return Err(Status::invalid_argument(
                    "command must be play, pause, next or previous",
                ));
            }
        };
        let r = self.manager.control(cmd, &source_of(&req.source)).await;
        Ok(Response::new(match r {
            Ok(()) => pb::ControlResponse {
                sent: true,
                detail: String::new(),
            },
            Err(detail) => pb::ControlResponse {
                sent: false,
                detail,
            },
        }))
    }

    async fn open_pairing(
        &self,
        req: Request<pb::OpenPairingRequest>,
    ) -> Result<Response<pb::OpenPairingResponse>, Status> {
        let req = req.into_inner();
        let secs = (req.seconds > 0).then_some(req.seconds);
        let r = self.manager.open_pairing(secs, &source_of(&req.source));
        Ok(Response::new(match r {
            Ok(()) => pb::OpenPairingResponse {
                accepted: true,
                detail: String::new(),
            },
            Err(detail) => pb::OpenPairingResponse {
                accepted: false,
                detail,
            },
        }))
    }

    async fn close_pairing(
        &self,
        req: Request<pb::ClosePairingRequest>,
    ) -> Result<Response<pb::ClosePairingResponse>, Status> {
        let closing = self
            .manager
            .close_pairing(&source_of(&req.into_inner().source));
        Ok(Response::new(pb::ClosePairingResponse { closing }))
    }

    async fn confirm_pairing(
        &self,
        req: Request<pb::ConfirmPairingRequest>,
    ) -> Result<Response<pb::ConfirmPairingResponse>, Status> {
        let req = req.into_inner();
        let answered = self
            .manager
            .confirm(req.id, req.accept, &source_of(&req.source));
        Ok(Response::new(pb::ConfirmPairingResponse {
            answered,
            detail: if answered {
                String::new()
            } else {
                "That question has already gone (answered, timed out or cancelled).".into()
            },
        }))
    }

    async fn get_speaker_settings(
        &self,
        _: Request<pb::GetSpeakerSettingsRequest>,
    ) -> Result<Response<pb::GetSpeakerSettingsResponse>, Status> {
        let l = self.manager.limits();
        Ok(Response::new(pb::GetSpeakerSettingsResponse {
            settings: Some(settings_pb(&self.manager.settings())),
            defaults: Some(settings_pb(&self.manager.defaults())),
            limits: Some(pb::SpeakerLimits {
                steps: l.steps,
                step_db: l.step_db,
                sub_min_db: l.sub_min_db,
                sub_max_db: l.sub_max_db,
                crossover_min_hz: l.crossover_min_hz,
                crossover_max_hz: l.crossover_max_hz,
                crossover_step_hz: l.crossover_step_hz,
            }),
        }))
    }

    async fn set_speaker_settings(
        &self,
        req: Request<pb::SetSpeakerSettingsRequest>,
    ) -> Result<Response<pb::SetSpeakerSettingsResponse>, Status> {
        let req = req.into_inner();
        let Some(s) = req.settings.as_ref() else {
            return Err(Status::invalid_argument("settings are required"));
        };
        let r = self
            .manager
            .set_settings(settings_from_pb(s), &source_of(&req.source))
            .await;
        let now = settings_pb(&self.manager.settings());
        Ok(Response::new(match r {
            Ok(detail) => pb::SetSpeakerSettingsResponse {
                applied: true,
                detail,
                settings: Some(now),
            },
            Err(detail) => pb::SetSpeakerSettingsResponse {
                applied: false,
                detail,
                settings: Some(now),
            },
        }))
    }

    async fn speak(
        &self,
        req: Request<pb::SpeakRequest>,
    ) -> Result<Response<pb::SpeakResponse>, Status> {
        let req = req.into_inner();
        Ok(Response::new(
            match self.manager.speak(&req.text, &source_of(&req.source)) {
                Ok(()) => pb::SpeakResponse {
                    accepted: true,
                    detail: String::new(),
                },
                Err(detail) => pb::SpeakResponse {
                    accepted: false,
                    detail,
                },
            },
        ))
    }

    async fn stop_speaking(
        &self,
        req: Request<pb::StopSpeakingRequest>,
    ) -> Result<Response<pb::StopSpeakingResponse>, Status> {
        let stopped = self
            .manager
            .stop_speaking(&source_of(&req.into_inner().source));
        Ok(Response::new(pb::StopSpeakingResponse { stopped }))
    }
}
