//! navigation's prompts through audio-manager [SIM] (ADR-0040 decision 17):
//! the `AudioManagerSpeaker` against a fake `f250.audio.v1.AudioService`
//! over a unix socket. Checks the calls, the status from `WatchAudio`, and
//! that nothing is queued while audio-manager is away.
#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::path::PathBuf;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use f250_proto::audio::v1 as pb;
use navigation::audio_speaker::AudioManagerSpeaker;
use navigation::voice::Speaker;
use pb::audio_service_server::{AudioService, AudioServiceServer};
use tokio::sync::watch;
use tokio_stream::{Stream, StreamExt, wrappers::WatchStream};
use tonic::{Request, Response, Status};

#[derive(Clone)]
struct Fake {
    calls: Arc<Mutex<Vec<String>>>,
    prompts: watch::Receiver<pb::Prompts>,
}

type Watch = Pin<Box<dyn Stream<Item = Result<pb::WatchAudioResponse, Status>> + Send>>;

#[tonic::async_trait]
impl AudioService for Fake {
    type WatchAudioStream = Watch;

    async fn watch_audio(
        &self,
        _: Request<pb::WatchAudioRequest>,
    ) -> Result<Response<Watch>, Status> {
        let s = WatchStream::new(self.prompts.clone()).map(|p| {
            Ok(pb::WatchAudioResponse {
                prompts: Some(p),
                simulated: true,
                ..Default::default()
            })
        });
        Ok(Response::new(Box::pin(s)))
    }

    async fn speak(
        &self,
        req: Request<pb::SpeakRequest>,
    ) -> Result<Response<pb::SpeakResponse>, Status> {
        let r = req.into_inner();
        self.calls
            .lock()
            .unwrap()
            .push(format!("speak {}: {}", r.source, r.text));
        Ok(Response::new(pb::SpeakResponse {
            accepted: self.prompts.borrow().available,
            detail: String::new(),
        }))
    }

    async fn stop_speaking(
        &self,
        req: Request<pb::StopSpeakingRequest>,
    ) -> Result<Response<pb::StopSpeakingResponse>, Status> {
        self.calls
            .lock()
            .unwrap()
            .push(format!("stop {}", req.into_inner().source));
        Ok(Response::new(pb::StopSpeakingResponse { stopped: true }))
    }

    async fn get_cover_art(
        &self,
        _: Request<pb::GetCoverArtRequest>,
    ) -> Result<Response<pb::GetCoverArtResponse>, Status> {
        Err(Status::unimplemented("fake"))
    }

    async fn set_volume(
        &self,
        _: Request<pb::SetVolumeRequest>,
    ) -> Result<Response<pb::SetVolumeResponse>, Status> {
        Err(Status::unimplemented("fake"))
    }

    async fn control(
        &self,
        _: Request<pb::ControlRequest>,
    ) -> Result<Response<pb::ControlResponse>, Status> {
        Err(Status::unimplemented("fake"))
    }

    async fn open_pairing(
        &self,
        _: Request<pb::OpenPairingRequest>,
    ) -> Result<Response<pb::OpenPairingResponse>, Status> {
        Err(Status::unimplemented("fake"))
    }

    async fn close_pairing(
        &self,
        _: Request<pb::ClosePairingRequest>,
    ) -> Result<Response<pb::ClosePairingResponse>, Status> {
        Err(Status::unimplemented("fake"))
    }

    async fn confirm_pairing(
        &self,
        _: Request<pb::ConfirmPairingRequest>,
    ) -> Result<Response<pb::ConfirmPairingResponse>, Status> {
        Err(Status::unimplemented("fake"))
    }

    async fn connect_phone(
        &self,
        _: Request<pb::ConnectPhoneRequest>,
    ) -> Result<Response<pb::ConnectPhoneResponse>, Status> {
        Err(Status::unimplemented("fake"))
    }

    async fn disconnect_phone(
        &self,
        _: Request<pb::DisconnectPhoneRequest>,
    ) -> Result<Response<pb::DisconnectPhoneResponse>, Status> {
        Err(Status::unimplemented("fake"))
    }

    async fn forget_phone(
        &self,
        _: Request<pb::ForgetPhoneRequest>,
    ) -> Result<Response<pb::ForgetPhoneResponse>, Status> {
        Err(Status::unimplemented("fake"))
    }

    async fn get_speaker_settings(
        &self,
        _: Request<pb::GetSpeakerSettingsRequest>,
    ) -> Result<Response<pb::GetSpeakerSettingsResponse>, Status> {
        Err(Status::unimplemented("fake"))
    }

    async fn set_speaker_settings(
        &self,
        _: Request<pb::SetSpeakerSettingsRequest>,
    ) -> Result<Response<pb::SetSpeakerSettingsResponse>, Status> {
        Err(Status::unimplemented("fake"))
    }
}

fn sock(test: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("f250-navaudio-{test}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir.join("audio.sock")
}

/// Serves the fake on `path` until the task is aborted.
fn serve(path: &PathBuf, fake: Fake) -> tokio::task::JoinHandle<()> {
    let _ = std::fs::remove_file(path);
    let listener = tokio::net::UnixListener::bind(path).unwrap();
    tokio::spawn(async move {
        let _ = tonic::transport::Server::builder()
            .add_service(AudioServiceServer::new(fake))
            .serve_with_incoming(tokio_stream::wrappers::UnixListenerStream::new(listener))
            .await;
    })
}

async fn until(what: &str, mut f: impl FnMut() -> bool) {
    for _ in 0..200 {
        if f() {
            return;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    panic!("not in time: {what}");
}

#[tokio::test]
async fn speaks_and_stops_through_audio_manager() {
    let path = sock("ok");
    let (tx, prompts) = watch::channel(pb::Prompts {
        available: true,
        detail: "Flite".to_string(),
        ..Default::default()
    });
    let calls = Arc::new(Mutex::new(Vec::new()));
    let server = serve(
        &path,
        Fake {
            calls: calls.clone(),
            prompts,
        },
    );
    let mut s = AudioManagerSpeaker::start(&format!("unix:{}", path.display()));
    until("connected", || s.status().audible).await;
    assert_eq!(s.status().detail, "audio-manager: Flite");

    s.speak("Turn right onto US 36, US 281.");
    s.stop();
    until("both calls", || calls.lock().unwrap().len() == 2).await;
    assert_eq!(
        *calls.lock().unwrap(),
        [
            "speak navigation: Turn right onto US 36, US 281.",
            "stop navigation"
        ]
    );

    // audio-manager says it has no voice: not audible, and why.
    tx.send_replace(pb::Prompts {
        available: false,
        detail: "no voice configured".to_string(),
        ..Default::default()
    });
    until("not audible", || !s.status().audible).await;
    assert_eq!(s.status().detail, "audio-manager: no voice configured");
    server.abort();
}

#[tokio::test]
async fn nothing_is_queued_while_audio_manager_is_away() {
    let path = sock("away");
    let mut s = AudioManagerSpeaker::start(&format!("unix:{}", path.display()));
    tokio::time::sleep(Duration::from_millis(200)).await;
    let st = s.status();
    assert!(!st.audible);
    assert!(st.detail.contains("not connected"), "{}", st.detail);
    // Said while it is away: dropped, not said late once it comes.
    s.speak("In half a mile, turn right onto US 36.");
    tokio::time::sleep(Duration::from_millis(100)).await;
    let (tx, prompts) = watch::channel(pb::Prompts {
        available: true,
        ..Default::default()
    });
    let calls = Arc::new(Mutex::new(Vec::new()));
    let server = serve(
        &path,
        Fake {
            calls: calls.clone(),
            prompts,
        },
    );
    until("reconnected", || s.status().audible).await;
    tokio::time::sleep(Duration::from_millis(200)).await;
    assert!(
        calls.lock().unwrap().is_empty(),
        "the old prompt wasn't said late"
    );
    s.speak("Turn right onto US 36, US 281.");
    until("the new one", || calls.lock().unwrap().len() == 1).await;
    // audio-manager goes away again (its streams end as it stops): not
    // audible, and no reconnecting to a server that isn't there.
    drop(tx);
    server.abort();
    let _ = std::fs::remove_file(&path);
    until("gone", || !s.status().audible).await;
}
