//! The `f250.audio.v1` gRPC service: thin, over [`Manager`].

use std::pin::Pin;
use std::sync::Arc;

use f250_proto::audio::v1 as pb;
use pb::audio_service_server::AudioService;
use tokio_stream::{Stream, StreamExt, wrappers::WatchStream};
use tonic::{Request, Response, Status};

use crate::manager::{Manager, settings_from_pb, settings_pb};
use crate::model::Command;
use crate::volume::Change;

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

    async fn connect_phone(
        &self,
        req: Request<pb::ConnectPhoneRequest>,
    ) -> Result<Response<pb::ConnectPhoneResponse>, Status> {
        let req = req.into_inner();
        let address = req.address.trim().to_ascii_uppercase();
        let r = self
            .manager
            .connect_phone(&address, &source_of(&req.source));
        Ok(Response::new(match r {
            Ok(detail) => pb::ConnectPhoneResponse {
                accepted: true,
                detail,
            },
            Err(detail) => pb::ConnectPhoneResponse {
                accepted: false,
                detail,
            },
        }))
    }

    async fn disconnect_phone(
        &self,
        req: Request<pb::DisconnectPhoneRequest>,
    ) -> Result<Response<pb::DisconnectPhoneResponse>, Status> {
        let req = req.into_inner();
        let address = req.address.trim().to_ascii_uppercase();
        let (accepted, detail) = match self
            .manager
            .disconnect_phone(&address, &source_of(&req.source))
        {
            Ok(d) => (true, d),
            Err(d) => (false, d),
        };
        Ok(Response::new(pb::DisconnectPhoneResponse {
            accepted,
            detail,
        }))
    }

    async fn forget_phone(
        &self,
        req: Request<pb::ForgetPhoneRequest>,
    ) -> Result<Response<pb::ForgetPhoneResponse>, Status> {
        let req = req.into_inner();
        let address = req.address.trim().to_ascii_uppercase();
        let (accepted, detail) = match self.manager.forget_phone(&address, &source_of(&req.source))
        {
            Ok(d) => (true, d),
            Err(d) => (false, d),
        };
        Ok(Response::new(pb::ForgetPhoneResponse { accepted, detail }))
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

    async fn get_cover_art(
        &self,
        req: Request<pb::GetCoverArtRequest>,
    ) -> Result<Response<pb::GetCoverArtResponse>, Status> {
        let id = req.into_inner().id;
        Ok(Response::new(match self.manager.cover_art(&id) {
            Some(p) => pb::GetCoverArtResponse {
                found: true,
                image: p.bytes.as_ref().clone(),
                mime_type: p.mime.to_string(),
            },
            None => pb::GetCoverArtResponse::default(),
        }))
    }

    async fn set_volume(
        &self,
        req: Request<pb::SetVolumeRequest>,
    ) -> Result<Response<pb::SetVolumeResponse>, Status> {
        use pb::set_volume_request::Change as C;
        let r = req.into_inner();
        let change = match r.change {
            Some(C::Level(n)) => Change::Level(n),
            Some(C::Steps(n)) => Change::Steps(n),
            Some(C::Mute(m)) => match pb::MuteChange::try_from(m) {
                Ok(pb::MuteChange::Mute) => Change::Mute,
                Ok(pb::MuteChange::Unmute) => Change::Unmute,
                Ok(pb::MuteChange::Toggle) => Change::ToggleMute,
                _ => return Err(Status::invalid_argument("mute: MUTE, UNMUTE or TOGGLE")),
            },
            None => return Err(Status::invalid_argument("a level, steps or mute")),
        };
        let (_, note) = self.manager.set_volume(change, &source_of(&r.source));
        let volume = self.manager.watch().borrow().volume.clone();
        let applied = volume.as_ref().is_some_and(|v| v.applied);
        // Why it isn't applied is in volume.detail, on every update.
        let detail = note.unwrap_or_default();
        Ok(Response::new(pb::SetVolumeResponse {
            applied,
            detail,
            volume,
        }))
    }
}
