//! Prompts through services/audio-manager (ADR-0039 decision 9, ADR-0040
//! decisions 16 and 17): `Speak` and `StopSpeaking` in `f250.audio.v1`.
//! audio-manager says the prompt (Flite), pauses the phone's music while it
//! does, and resumes it after its hold.
//!
//! The guide's loop never waits on it: [`AudioManagerSpeaker::speak`] hands
//! the text to a task that owns the connection. **Nothing is queued while
//! audio-manager is unreachable**: a prompt that can't be said now is
//! dropped (and logged), never said late (CLAUDE.md rule 4). The status
//! follows `WatchAudio`'s `prompts`, and says "not connected" otherwise.

use std::sync::{Arc, Mutex};
use std::time::Duration;

use f250_proto::audio::v1 as pb;
use hyper_util::rt::TokioIo;
use pb::audio_service_client::AudioServiceClient;
use tokio::sync::mpsc;
use tonic::transport::{Channel, Endpoint, Uri};

use crate::voice::{Speaker, SpeakerStatus};

/// Who navigation is, in audio-manager's log.
const SOURCE: &str = "navigation";

/// A call slower than this is given up: the prompt would be late.
const CALL_TIMEOUT: Duration = Duration::from_secs(2);

/// Between connection attempts.
const RETRY: Duration = Duration::from_secs(2);

#[derive(Debug)]
enum Request {
    Speak(String),
    Stop,
}

pub struct AudioManagerSpeaker {
    requests: mpsc::Sender<Request>,
    status: Arc<Mutex<SpeakerStatus>>,
}

impl AudioManagerSpeaker {
    /// Connects to audio-manager at `endpoint` (`unix:PATH` or
    /// `tcp:HOST:PORT`) in the background, and keeps reconnecting. Needs a
    /// tokio runtime.
    pub fn start(endpoint: &str) -> Self {
        let (requests, rx) = mpsc::channel(4);
        let status = Arc::new(Mutex::new(not_connected(endpoint, "connecting")));
        tokio::spawn(run(endpoint.to_string(), rx, status.clone()));
        AudioManagerSpeaker { requests, status }
    }
}

fn not_connected(endpoint: &str, why: &str) -> SpeakerStatus {
    SpeakerStatus {
        audible: false,
        detail: format!("audio-manager at {endpoint} not connected: {why}"),
    }
}

impl Speaker for AudioManagerSpeaker {
    fn speak(&mut self, text: &str) {
        if self
            .requests
            .try_send(Request::Speak(text.to_string()))
            .is_err()
        {
            eprintln!("[navigation] voice: not said (audio-manager busy or gone): {text}");
        }
    }

    fn stop(&mut self) {
        let _ = self.requests.try_send(Request::Stop);
    }

    fn status(&self) -> SpeakerStatus {
        self.status
            .lock()
            .map(|s| s.clone())
            .unwrap_or_else(|_| SpeakerStatus {
                audible: false,
                detail: "audio-manager status unavailable".to_string(),
            })
    }
}

async fn connect(endpoint: &str) -> Result<Channel, String> {
    if let Some(path) = endpoint.strip_prefix("unix:") {
        let path = path.to_string();
        Endpoint::from_static("http://localhost")
            .connect_with_connector(tower::service_fn(move |_: Uri| {
                let path = path.clone();
                async move {
                    tokio::net::UnixStream::connect(path)
                        .await
                        .map(TokioIo::new)
                }
            }))
            .await
            .map_err(|e| e.to_string())
    } else if let Some(addr) = endpoint.strip_prefix("tcp:") {
        Endpoint::from_shared(format!("http://{addr}"))
            .map_err(|e| e.to_string())?
            .connect()
            .await
            .map_err(|e| e.to_string())
    } else {
        Err("the endpoint must start with unix: or tcp:".to_string())
    }
}

fn set(status: &Mutex<SpeakerStatus>, s: SpeakerStatus) {
    if let Ok(mut g) = status.lock() {
        *g = s;
    }
}

/// Drops whatever was asked while there was no connection: never said late.
fn drop_pending(rx: &mut mpsc::Receiver<Request>) {
    while let Ok(r) = rx.try_recv() {
        if let Request::Speak(text) = r {
            eprintln!("[navigation] voice: not said (audio-manager not connected): {text}");
        }
    }
}

async fn run(endpoint: String, mut rx: mpsc::Receiver<Request>, status: Arc<Mutex<SpeakerStatus>>) {
    let mut last_problem = String::new();
    loop {
        let problem = match session(&endpoint, &mut rx, &status).await {
            Ok(()) => return, // navigation is stopping
            Err(why) => why,
        };
        set(&status, not_connected(&endpoint, &problem));
        if problem != last_problem {
            eprintln!("[navigation] voice: audio-manager at {endpoint}: {problem}");
            last_problem = problem;
        }
        // Wait to retry, dropping prompts meanwhile.
        let deadline = tokio::time::sleep(RETRY);
        tokio::pin!(deadline);
        loop {
            tokio::select! {
                _ = &mut deadline => break,
                r = rx.recv() => match r {
                    None => return,
                    Some(Request::Speak(text)) => {
                        eprintln!("[navigation] voice: not said (audio-manager not connected): {text}");
                    }
                    Some(Request::Stop) => {}
                },
            }
        }
    }
}

/// One connection: the status stream and the requests, until either fails.
/// Ok only when navigation drops the speaker.
async fn session(
    endpoint: &str,
    rx: &mut mpsc::Receiver<Request>,
    status: &Mutex<SpeakerStatus>,
) -> Result<(), String> {
    let channel = connect(endpoint).await?;
    let mut client = AudioServiceClient::new(channel);
    let mut stream = client
        .watch_audio(pb::WatchAudioRequest {})
        .await
        .map_err(|e| e.message().to_string())?
        .into_inner();
    // Anything asked while connecting is old by now.
    drop_pending(rx);
    loop {
        tokio::select! {
            msg = stream.message() => match msg {
                Ok(Some(m)) => {
                    let p = m.prompts.unwrap_or_default();
                    set(status, SpeakerStatus {
                        audible: p.available,
                        detail: if p.detail.is_empty() {
                            "audio-manager".to_string()
                        } else {
                            format!("audio-manager: {}", p.detail)
                        },
                    });
                }
                Ok(None) => return Err("audio-manager ended the stream".to_string()),
                Err(e) => return Err(e.message().to_string()),
            },
            r = rx.recv() => match r {
                None => return Ok(()),
                Some(Request::Speak(text)) => {
                    let call = client.speak(pb::SpeakRequest {
                        text: text.clone(),
                        source: SOURCE.to_string(),
                    });
                    match tokio::time::timeout(CALL_TIMEOUT, call).await {
                        Ok(Ok(r)) => {
                            let r = r.into_inner();
                            if r.accepted {
                                eprintln!("[navigation] voice: {text}");
                            } else {
                                eprintln!(
                                    "[navigation] voice: audio-manager refused ({}): {text}",
                                    r.detail
                                );
                            }
                        }
                        Ok(Err(e)) => return Err(format!("Speak: {}", e.message())),
                        Err(_) => {
                            eprintln!("[navigation] voice: not said (audio-manager slow): {text}");
                        }
                    }
                }
                Some(Request::Stop) => {
                    let call = client.stop_speaking(pb::StopSpeakingRequest {
                        source: SOURCE.to_string(),
                    });
                    if let Ok(Err(e)) = tokio::time::timeout(CALL_TIMEOUT, call).await {
                        return Err(format!("StopSpeaking: {}", e.message()));
                    }
                }
            },
        }
    }
}
