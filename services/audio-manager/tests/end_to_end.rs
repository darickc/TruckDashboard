//! audio-manager end to end [SIM]: the simulated phone, the manager and a
//! gRPC client over a unix socket. Now playing and controls, link loss (the
//! track goes with the phone), Bluetooth going away, the pairing window with
//! a passkey question accepted and refused, the speaker settings, and the
//! once-a-second heartbeat. Phone calls (ADR-0045) on the simulated phone:
//! ringing, answered, declined, a waiting call, mute, the music paused and
//! resumed, prompts skipped, and calls off without a microphone.

#![allow(clippy::unwrap_used)]

use std::sync::Arc;
use std::time::Duration;

use audio_manager::backend::Bluetooth;
use audio_manager::dsp::{Limits, Settings};
use audio_manager::manager::{Config, Manager, Reconnect};
use audio_manager::pairing;
use audio_manager::ring::SimRinger;
use audio_manager::runner::NoDsp;
use audio_manager::server::Api;
use audio_manager::sim::{self, SimConfig, SimPhone};
use audio_manager::sim_calls::{SIM_CALLER, SIM_NUMBER, SimCalls, SimCallsConfig};
use audio_manager::telephony::{NoCalls, Telephony};
use audio_manager::voice::SimVoice;
use audio_manager::volume::VolumeLimits;
use f250_proto::audio::v1 as pb;
use hyper_util::rt::TokioIo;
use pb::audio_service_client::AudioServiceClient;
use pb::audio_service_server::AudioServiceServer;
use tokio::sync::mpsc;
use tonic::transport::{Channel, Endpoint, Server, Uri};

type Client = AudioServiceClient<Channel>;

fn dir(test: &str) -> std::path::PathBuf {
    let d = std::env::temp_dir().join(format!("f250-audio-{test}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).expect("temp dir");
    d
}

async fn client(path: std::path::PathBuf) -> Client {
    for _ in 0..100 {
        if path.exists() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    let channel = Endpoint::from_static("http://localhost")
        .connect_with_connector(tower::service_fn(move |_: Uri| {
            let path = path.clone();
            async move {
                tokio::net::UnixStream::connect(path)
                    .await
                    .map(TokioIo::new)
            }
        }))
        .await
        .expect("connect");
    AudioServiceClient::new(channel)
}

struct Running {
    manager: Arc<Manager>,
    client: Client,
    sim: SimPhone,
    calls: SimCalls,
    ringer: Arc<SimRinger>,
    dir: std::path::PathBuf,
}

async fn start(test: &str, sim_cfg: SimConfig) -> Running {
    start_with(test, sim_cfg, |_, _| {}).await
}

/// `start`, with the manager's configuration changed first (reconnecting,
/// the last phone's file in the test's directory).
async fn start_with(
    test: &str,
    sim_cfg: SimConfig,
    change: impl FnOnce(&mut Config, &std::path::Path),
) -> Running {
    start_full(test, sim_cfg, change, None).await
}

/// `start_with`, with another telephony backend than the simulated calls.
async fn start_full(
    test: &str,
    sim_cfg: SimConfig,
    change: impl FnOnce(&mut Config, &std::path::Path),
    tel: Option<Arc<dyn Telephony>>,
) -> Running {
    let dir = dir(test);
    let (agent_tx, agent_rx) = mpsc::channel(8);
    let sim = SimPhone::new(sim_cfg, agent_tx);
    let bt: Arc<dyn Bluetooth> = Arc::new(sim.clone());
    let calls = SimCalls::new(SimCallsConfig::default());
    let ringer = Arc::new(SimRinger::new(Duration::from_millis(200)));
    let mut cfg = Config {
        pairing: pairing::Config::default(),
        name: "F-250".into(),
        limits: Limits::default(),
        defaults: Settings::default(),
        settings_file: Some(dir.join("speakers.json")),
        simulated: true,
        prompt_hold: Duration::from_millis(300),
        last_phone_file: None,
        reconnect: Reconnect::OFF,
        volume: VolumeLimits {
            max: 24,
            ..VolumeLimits::default()
        },
        volume_file: Some(dir.join("volume.json")),
        ring_after: Duration::from_millis(300),
    };
    change(&mut cfg, &dir);
    let manager = Manager::new(
        cfg,
        bt,
        Arc::new(NoDsp::new("simulated: no PipeWire")),
        Arc::new(SimVoice {
            per_char: Duration::from_millis(2),
            min: Duration::from_millis(300),
        }),
        tel.unwrap_or_else(|| Arc::new(calls.clone())),
        ringer.clone(),
    );
    tokio::spawn(Arc::clone(&manager).run(agent_rx));
    let api = Api::new(Arc::clone(&manager));
    let sock = dir.join("audio.sock");
    let listener = tokio::net::UnixListener::bind(&sock).expect("bind");
    let incoming = tokio_stream::wrappers::UnixListenerStream::new(listener);
    tokio::spawn(
        Server::builder()
            .add_service(AudioServiceServer::new(api))
            .serve_with_incoming(incoming),
    );
    Running {
        manager,
        client: client(sock).await,
        sim,
        calls,
        ringer,
        dir,
    }
}

async fn watch(c: &mut Client) -> tonic::Streaming<pb::WatchAudioResponse> {
    c.watch_audio(pb::WatchAudioRequest {})
        .await
        .expect("watch")
        .into_inner()
}

async fn until(
    s: &mut tonic::Streaming<pb::WatchAudioResponse>,
    what: &str,
    want: impl Fn(&pb::WatchAudioResponse) -> bool,
) -> pb::WatchAudioResponse {
    tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let m = s.message().await.expect("stream ok").expect("stream open");
            if want(&m) {
                return m;
            }
        }
    })
    .await
    .unwrap_or_else(|_| panic!("timed out waiting for: {what}"))
}

fn title(m: &pb::WatchAudioResponse) -> &str {
    m.now_playing.as_ref().map_or("", |n| n.title.as_str())
}

fn pairing(m: &pb::WatchAudioResponse) -> pb::PairingState {
    m.pairing
        .as_ref()
        .map_or(pb::PairingState::Unspecified, |p| p.state())
}

async fn control(c: &mut Client, cmd: pb::Command) -> pb::ControlResponse {
    c.control(pb::ControlRequest {
        command: cmd.into(),
        source: "test".into(),
    })
    .await
    .expect("control")
    .into_inner()
}

#[tokio::test]
async fn now_playing_and_controls() {
    let mut r = start(
        "controls",
        SimConfig {
            pair_after: None,
            ..SimConfig::default()
        },
    )
    .await;
    let mut s = watch(&mut r.client).await;
    let m = until(&mut s, "a track", |m| !title(m).is_empty()).await;
    assert!(m.simulated);
    assert_eq!(m.bluetooth(), pb::BluetoothState::Ready);
    assert_eq!(m.phone.as_ref().unwrap().name, "Simulated phone");
    let np = m.now_playing.as_ref().unwrap();
    assert_eq!(np.title, "Simulated Track One");
    assert_eq!(np.artist, "The Test Tones");
    assert_eq!(np.duration_ms, 185_000);
    assert_eq!(np.state(), pb::PlayState::Playing);
    assert!(np.has_position);
    assert!(m.streaming);
    assert_eq!(pairing(&m), pb::PairingState::Closed, "closed until asked");
    assert_eq!(m.dsp(), pb::DspState::NotRunning);

    assert!(control(&mut r.client, pb::Command::Next).await.sent);
    until(&mut s, "track two", |m| title(m) == "Second Simulated Song").await;
    assert!(control(&mut r.client, pb::Command::Pause).await.sent);
    let m = until(&mut s, "paused", |m| {
        m.now_playing
            .as_ref()
            .is_some_and(|n| n.state() == pb::PlayState::Paused)
    })
    .await;
    assert!(!m.streaming);
    assert!(control(&mut r.client, pb::Command::Previous).await.sent);
    until(&mut s, "back to one", |m| title(m) == "Simulated Track One").await;
    assert!(control(&mut r.client, pb::Command::Play).await.sent);
    until(&mut s, "playing", |m| {
        m.now_playing
            .as_ref()
            .is_some_and(|n| n.state() == pb::PlayState::Playing)
    })
    .await;
    let bad = r
        .client
        .control(pb::ControlRequest {
            command: 0,
            source: String::new(),
        })
        .await;
    assert_eq!(bad.unwrap_err().code(), tonic::Code::InvalidArgument);
}

fn art_id(m: &pb::WatchAudioResponse) -> &str {
    m.now_playing
        .as_ref()
        .map_or("", |n| n.cover_art_id.as_str())
}

async fn cover_art(c: &mut Client, id: &str) -> pb::GetCoverArtResponse {
    c.get_cover_art(pb::GetCoverArtRequest { id: id.into() })
        .await
        .expect("get cover art")
        .into_inner()
}

/// ADR-0042: each track's picture by its id; a picture is never served
/// for a track that has gone, nor for a phone that has gone.
#[tokio::test]
async fn cover_art_follows_the_track() {
    let mut r = start(
        "cover-art",
        SimConfig {
            pair_after: None,
            ..SimConfig::default()
        },
    )
    .await;
    let mut s = watch(&mut r.client).await;
    let m = until(&mut s, "track one's picture", |m| !art_id(m).is_empty()).await;
    let one = art_id(&m).to_string();
    assert_eq!(m.now_playing.as_ref().unwrap().cover_art_detail, "");
    let a = cover_art(&mut r.client, &one).await;
    assert!(a.found);
    assert_eq!(a.mime_type, "image/bmp");
    assert_eq!(
        a.image,
        sim::sim_picture(0),
        "the picture as the phone sent it"
    );

    assert!(control(&mut r.client, pb::Command::Next).await.sent);
    let m = until(&mut s, "track two's picture", |m| {
        title(m) == "Second Simulated Song" && !art_id(m).is_empty()
    })
    .await;
    let two = art_id(&m).to_string();
    assert_ne!(two, one, "another track, another id");
    assert!(cover_art(&mut r.client, &two).await.found);
    assert!(
        !cover_art(&mut r.client, &one).await.found,
        "never the last track's picture"
    );

    // The third track has none: no id, and why.
    assert!(control(&mut r.client, pb::Command::Next).await.sent);
    let m = until(&mut s, "track three", |m| title(m) == "A Third One").await;
    assert_eq!(art_id(&m), "");
    assert_eq!(
        m.now_playing.as_ref().unwrap().cover_art_detail,
        "No picture for this track"
    );
    assert!(!cover_art(&mut r.client, &two).await.found);

    // Back to one, then the phone goes: nothing is served.
    assert!(control(&mut r.client, pb::Command::Next).await.sent);
    let m = until(&mut s, "track one again", |m| {
        title(m) == "Simulated Track One" && !art_id(m).is_empty()
    })
    .await;
    let again = art_id(&m).to_string();
    assert!(cover_art(&mut r.client, &again).await.found);
    r.sim.disconnect();
    until(&mut s, "no phone", |m| m.phone.is_none()).await;
    assert!(!cover_art(&mut r.client, &again).await.found);
    assert!(!cover_art(&mut r.client, "").await.found);
}

#[tokio::test]
async fn link_loss_clears_the_track_and_it_comes_back() {
    let mut r = start(
        "link",
        SimConfig {
            pair_after: None,
            ..SimConfig::default()
        },
    )
    .await;
    let mut s = watch(&mut r.client).await;
    until(&mut s, "a track", |m| !title(m).is_empty()).await;
    r.sim.disconnect();
    let m = until(&mut s, "no phone", |m| m.phone.is_none()).await;
    assert!(
        m.now_playing.is_none(),
        "never the last track of a gone phone"
    );
    assert!(!m.streaming);
    assert_eq!(m.known.len(), 1, "still paired");
    assert_eq!(m.known[0].name, "Simulated phone");
    let c = control(&mut r.client, pb::Command::Play).await;
    assert!(!c.sent);
    assert_eq!(c.detail, "No phone is connected.");
    r.sim.connect();
    let m = until(&mut s, "back", |m| m.phone.is_some()).await;
    assert!(m.now_playing.is_some());
    assert!(m.known.is_empty());
}

#[tokio::test]
async fn bluetooth_going_away_closes_the_window_and_shows_nothing() {
    let mut r = start(
        "adapter",
        SimConfig {
            pair_after: None,
            ..SimConfig::default()
        },
    )
    .await;
    let mut s = watch(&mut r.client).await;
    let open = r
        .client
        .open_pairing(pb::OpenPairingRequest {
            seconds: 60,
            source: "test".into(),
        })
        .await
        .unwrap()
        .into_inner();
    assert!(open.accepted);
    until(&mut s, "open", |m| pairing(m) == pb::PairingState::Open).await;
    r.sim.set_adapter(false);
    let m = until(&mut s, "unavailable", |m| {
        m.bluetooth() == pb::BluetoothState::Unavailable
    })
    .await;
    assert!(m.phone.is_none() && m.now_playing.is_none() && m.known.is_empty());
    assert_eq!(pairing(&m), pb::PairingState::Closed);
    assert!(!m.bluetooth_detail.is_empty());
    let open = r
        .client
        .open_pairing(pb::OpenPairingRequest {
            seconds: 0,
            source: "test".into(),
        })
        .await
        .unwrap()
        .into_inner();
    assert!(!open.accepted);
    assert!(open.detail.contains("unavailable"));
    r.sim.set_adapter(true);
    until(&mut s, "ready", |m| {
        m.bluetooth() == pb::BluetoothState::Ready
    })
    .await;
}

#[tokio::test]
async fn pairing_window_with_a_code_accepted() {
    let mut r = start(
        "pair-yes",
        SimConfig {
            pair_after: Some(Duration::from_millis(200)),
            ..SimConfig::default()
        },
    )
    .await;
    let mut s = watch(&mut r.client).await;
    let open = r
        .client
        .open_pairing(pb::OpenPairingRequest {
            seconds: 90,
            source: "test".into(),
        })
        .await
        .unwrap()
        .into_inner();
    assert!(open.accepted, "{}", open.detail);
    let m = until(&mut s, "open", |m| pairing(m) == pb::PairingState::Open).await;
    let p = m.pairing.as_ref().unwrap();
    assert!((89..=90).contains(&p.seconds_left), "{}", p.seconds_left);
    assert_eq!(p.name, "F-250");
    let m = until(&mut s, "a question", |m| {
        m.pairing.as_ref().is_some_and(|p| p.question.is_some())
    })
    .await;
    let q = m.pairing.unwrap().question.unwrap();
    assert!(q.shows_passkey);
    assert_eq!(q.passkey, sim::SIM_PASSKEY);
    assert_eq!(q.phone_name, "Simulated phone 2");
    // A wrong id answers nothing.
    let wrong = r
        .client
        .confirm_pairing(pb::ConfirmPairingRequest {
            id: q.id + 9,
            accept: true,
            source: "test".into(),
        })
        .await
        .unwrap()
        .into_inner();
    assert!(!wrong.answered);
    let ok = r
        .client
        .confirm_pairing(pb::ConfirmPairingRequest {
            id: q.id,
            accept: true,
            source: "test".into(),
        })
        .await
        .unwrap()
        .into_inner();
    assert!(ok.answered);
    let m = until(&mut s, "paired and closed", |m| {
        m.phone.as_ref().is_some_and(|p| p.address == sim::SECOND)
            && pairing(m) == pb::PairingState::Closed
    })
    .await;
    assert_eq!(m.pairing.unwrap().detail, "Paired with Simulated phone 2.");
    assert_eq!(m.known.len(), 1, "the first phone is still paired");
}

#[tokio::test]
async fn pairing_window_with_a_code_refused_then_closed_by_hand() {
    let mut r = start(
        "pair-no",
        SimConfig {
            pair_after: Some(Duration::from_millis(200)),
            ..SimConfig::default()
        },
    )
    .await;
    let mut s = watch(&mut r.client).await;
    r.client
        .open_pairing(pb::OpenPairingRequest {
            seconds: 0,
            source: "test".into(),
        })
        .await
        .unwrap();
    let m = until(&mut s, "a question", |m| {
        m.pairing.as_ref().is_some_and(|p| p.question.is_some())
    })
    .await;
    assert!(
        (119..=120).contains(&m.pairing.as_ref().unwrap().seconds_left),
        "the default length"
    );
    let id = m.pairing.unwrap().question.unwrap().id;
    r.client
        .confirm_pairing(pb::ConfirmPairingRequest {
            id,
            accept: false,
            source: "test".into(),
        })
        .await
        .unwrap();
    let m = until(&mut s, "refused", |m| {
        m.pairing
            .as_ref()
            .is_some_and(|p| p.question.is_none() && p.detail.starts_with("Refused"))
    })
    .await;
    assert_eq!(
        pairing(&m),
        pb::PairingState::Open,
        "still open for another try"
    );
    assert_eq!(m.phone.unwrap().address, sim::FIRST);
    let closed = r
        .client
        .close_pairing(pb::ClosePairingRequest {
            source: "test".into(),
        })
        .await
        .unwrap()
        .into_inner();
    assert!(closed.closing);
    until(&mut s, "closed", |m| pairing(m) == pb::PairingState::Closed).await;
    let again = r
        .client
        .close_pairing(pb::ClosePairingRequest {
            source: "test".into(),
        })
        .await
        .unwrap()
        .into_inner();
    assert!(!again.closing);
}

#[tokio::test]
async fn speaker_settings_are_validated_saved_and_kept() {
    let mut r = start(
        "speakers",
        SimConfig {
            pair_after: None,
            ..SimConfig::default()
        },
    )
    .await;
    let got = r
        .client
        .get_speaker_settings(pb::GetSpeakerSettingsRequest {})
        .await
        .unwrap()
        .into_inner();
    let l = got.limits.unwrap();
    assert_eq!(
        (l.steps, l.crossover_min_hz, l.crossover_max_hz),
        (10, 50, 120)
    );
    assert_eq!(got.settings.unwrap().crossover_hz, 80);
    let bad = r
        .client
        .set_speaker_settings(pb::SetSpeakerSettingsRequest {
            settings: Some(pb::SpeakerSettings {
                fader: 0,
                balance: 0,
                sub_level_db: 0,
                crossover_hz: 1000,
            }),
            source: "test".into(),
        })
        .await
        .unwrap()
        .into_inner();
    assert!(!bad.applied);
    assert!(bad.detail.contains("Crossover"));
    assert_eq!(bad.settings.unwrap().crossover_hz, 80, "unchanged");
    let good = pb::SpeakerSettings {
        fader: -4,
        balance: 2,
        sub_level_db: -6,
        crossover_hz: 100,
    };
    let ok = r
        .client
        .set_speaker_settings(pb::SetSpeakerSettingsRequest {
            settings: Some(good),
            source: "test".into(),
        })
        .await
        .unwrap()
        .into_inner();
    assert!(ok.applied);
    assert!(
        ok.detail.contains("not applied"),
        "honest about no PipeWire: {}",
        ok.detail
    );
    let file = std::fs::read_to_string(r.dir.join("speakers.json")).unwrap();
    let cfg = Config {
        pairing: pairing::Config::default(),
        name: String::new(),
        limits: Limits::default(),
        defaults: Settings::default(),
        settings_file: Some(r.dir.join("speakers.json")),
        simulated: true,
        prompt_hold: Duration::from_secs(1),
        last_phone_file: None,
        reconnect: Reconnect::OFF,
        volume: VolumeLimits::default(),
        volume_file: None,
        ring_after: Duration::from_secs(1),
    };
    let (loaded, problem) = audio_manager::manager::load_settings(&cfg);
    assert!(problem.is_none(), "{file}");
    assert_eq!(
        loaded,
        Settings {
            fader: -4,
            balance: 2,
            sub_level_db: -6,
            crossover_hz: 100
        }
    );
    // A damaged file gives the defaults and says so.
    std::fs::write(r.dir.join("speakers.json"), "{oops").unwrap();
    let (loaded, problem) = audio_manager::manager::load_settings(&cfg);
    assert_eq!(loaded, Settings::default());
    assert!(problem.is_some());
}

#[tokio::test]
async fn heartbeat_once_a_second_while_nothing_changes() {
    let mut r = start(
        "heartbeat",
        SimConfig {
            pair_after: None,
            ..SimConfig::default()
        },
    )
    .await;
    let mut s = watch(&mut r.client).await;
    s.message().await.unwrap().unwrap();
    let t0 = std::time::Instant::now();
    for _ in 0..2 {
        tokio::time::timeout(Duration::from_millis(1500), s.message())
            .await
            .expect("a message within 1.5 s")
            .unwrap()
            .unwrap();
    }
    assert!(t0.elapsed() < Duration::from_secs(3));
}

#[tokio::test]
async fn watch_streams_end_when_stopping() {
    let mut r = start(
        "stop",
        SimConfig {
            pair_after: None,
            ..SimConfig::default()
        },
    )
    .await;
    let mut s = watch(&mut r.client).await;
    s.message().await.unwrap().unwrap();
    r.manager.stop();
    let end = tokio::time::timeout(Duration::from_secs(3), async {
        while s.message().await.unwrap().is_some() {}
    })
    .await;
    assert!(
        end.is_ok(),
        "the stream ended, so a graceful shutdown can finish"
    );
}

fn prompts(m: &pb::WatchAudioResponse) -> pb::Prompts {
    m.prompts.clone().unwrap_or_default()
}

fn play_state_of(m: &pb::WatchAudioResponse) -> pb::PlayState {
    m.now_playing
        .as_ref()
        .map_or(pb::PlayState::Unspecified, |n| n.state())
}

async fn speak(c: &mut Client, text: &str) -> pb::SpeakResponse {
    c.speak(pb::SpeakRequest {
        text: text.into(),
        source: "test".into(),
    })
    .await
    .unwrap()
    .into_inner()
}

#[tokio::test]
async fn a_prompt_pauses_the_music_and_resumes_it_after_the_hold() {
    let mut r = start(
        "prompt",
        SimConfig {
            pair_after: None,
            ..SimConfig::default()
        },
    )
    .await;
    let mut s = watch(&mut r.client).await;
    let m = until(&mut s, "playing", |m| {
        play_state_of(m) == pb::PlayState::Playing
    })
    .await;
    assert!(prompts(&m).available);
    assert!(
        speak(&mut r.client, "In half a mile, turn right.")
            .await
            .accepted
    );
    let m = until(&mut s, "paused for the prompt", |m| {
        prompts(m).speaking && prompts(m).music_paused && play_state_of(m) == pb::PlayState::Paused
    })
    .await;
    assert!(!m.streaming);
    until(&mut s, "said, held", |m| {
        !prompts(m).speaking && prompts(m).music_paused
    })
    .await;
    until(&mut s, "resumed", |m| {
        !prompts(m).music_paused && play_state_of(m) == pb::PlayState::Playing
    })
    .await;
}

#[tokio::test]
async fn the_drivers_pause_during_a_prompt_wins() {
    let mut r = start(
        "prompt-pause",
        SimConfig {
            pair_after: None,
            ..SimConfig::default()
        },
    )
    .await;
    let mut s = watch(&mut r.client).await;
    until(&mut s, "playing", |m| {
        play_state_of(m) == pb::PlayState::Playing
    })
    .await;
    assert!(speak(&mut r.client, "Turn left.").await.accepted);
    until(&mut s, "paused", |m| prompts(m).music_paused).await;
    assert!(control(&mut r.client, pb::Command::Pause).await.sent);
    let m = until(&mut s, "taken over", |m| !prompts(m).music_paused).await;
    assert_eq!(play_state_of(&m), pb::PlayState::Paused);
    // Well past the prompt and the hold: still paused.
    tokio::time::sleep(Duration::from_millis(1500)).await;
    let m = until(&mut s, "a later report", |_| true).await;
    assert_eq!(play_state_of(&m), pb::PlayState::Paused);
}

#[tokio::test]
async fn music_that_was_paused_stays_paused_and_prompts_can_be_stopped() {
    let mut r = start(
        "prompt-stop",
        SimConfig {
            pair_after: None,
            ..SimConfig::default()
        },
    )
    .await;
    let mut s = watch(&mut r.client).await;
    assert!(control(&mut r.client, pb::Command::Pause).await.sent);
    until(&mut s, "paused", |m| {
        play_state_of(m) == pb::PlayState::Paused
    })
    .await;
    // A long prompt, cut off by a newer one, then stopped.
    assert!(speak(&mut r.client, &"word ".repeat(400)).await.accepted);
    assert!(speak(&mut r.client, &"other ".repeat(400)).await.accepted);
    let m = until(&mut s, "speaking", |m| prompts(m).speaking).await;
    assert!(!prompts(&m).music_paused, "it wasn't playing");
    let stopped = r
        .client
        .stop_speaking(pb::StopSpeakingRequest {
            source: "test".into(),
        })
        .await
        .unwrap()
        .into_inner();
    assert!(stopped.stopped);
    let m = until(&mut s, "stopped", |m| !prompts(m).speaking).await;
    assert_eq!(play_state_of(&m), pb::PlayState::Paused);
    assert!(
        !speak(&mut r.client, " \n ").await.accepted,
        "nothing to say"
    );
}

// ---- connecting paired phones (the Phones screen; the last phone again) ----

fn quiet(start_connected: bool) -> SimConfig {
    SimConfig {
        pair_after: None,
        start_connected,
        connect_takes: Duration::from_millis(200),
        ..SimConfig::default()
    }
}

fn connected_addr(m: &pb::WatchAudioResponse) -> &str {
    m.phone
        .as_ref()
        .filter(|p| p.connected)
        .map_or("", |p| p.address.as_str())
}

fn attempt(m: &pb::WatchAudioResponse) -> pb::ConnectAttempt {
    m.connect.clone().unwrap_or_default()
}

async fn connect(c: &mut Client, address: &str) -> pb::ConnectPhoneResponse {
    c.connect_phone(pb::ConnectPhoneRequest {
        address: address.into(),
        source: "test".into(),
    })
    .await
    .expect("connect_phone")
    .into_inner()
}

#[tokio::test]
async fn a_paired_phone_is_connected_from_the_list_and_remembered() {
    let mut r = start_with("connect", quiet(false), |c, d| {
        c.last_phone_file = Some(d.join("last-phone"));
    })
    .await;
    let mut s = watch(&mut r.client).await;
    let m = until(&mut s, "the paired phone listed", |m| !m.known.is_empty()).await;
    assert_eq!(connected_addr(&m), "");
    assert_eq!(m.known[0].address, sim::FIRST);
    assert!(!m.known[0].last, "nothing connected yet: no last phone");

    let no = connect(&mut r.client, "02:00:00:00:00:09").await;
    assert!(!no.accepted);
    assert_eq!(no.detail, "That phone isn't paired.");

    let ok = connect(&mut r.client, &sim::FIRST.to_lowercase()).await;
    assert!(ok.accepted, "{}", ok.detail);
    assert_eq!(ok.detail, "Connecting to Simulated phone…");
    let again = connect(&mut r.client, sim::FIRST).await;
    assert!(!again.accepted);
    assert_eq!(again.detail, "Already connecting to Simulated phone.");
    until(&mut s, "connecting shown", |m| {
        attempt(m).address == sim::FIRST && !attempt(m).automatic
    })
    .await;
    let m = until(&mut s, "connected", |m| connected_addr(m) == sim::FIRST).await;
    assert!(m.phone.as_ref().unwrap().last);
    let m = until(&mut s, "the attempt over", |m| {
        attempt(m).address.is_empty()
    })
    .await;
    assert_eq!(attempt(&m).detail, "");
    assert_eq!(
        std::fs::read_to_string(r.dir.join("last-phone")).unwrap(),
        format!("{}\n", sim::FIRST)
    );
    let dup = connect(&mut r.client, sim::FIRST).await;
    assert!(!dup.accepted);
    assert_eq!(dup.detail, "Simulated phone is already connected.");
}

#[tokio::test]
async fn a_failed_connection_says_why() {
    let mut r = start("connect-fails", quiet(false)).await;
    r.sim.set_reachable(false);
    let mut s = watch(&mut r.client).await;
    until(&mut s, "listed", |m| !m.known.is_empty()).await;
    assert!(connect(&mut r.client, sim::FIRST).await.accepted);
    let m = until(&mut s, "the failure", |m| !attempt(m).detail.is_empty()).await;
    assert_eq!(
        attempt(&m).detail,
        "Couldn't connect to Simulated phone: simulated: the phone didn't answer (out of range)."
    );
    assert_eq!(connected_addr(&m), "");
    assert!(attempt(&m).address.is_empty());
}

#[tokio::test]
async fn the_last_phone_is_reconnected_by_itself_at_start_and_after_a_drop() {
    let mut r = start_with("reconnect", quiet(false), |c, d| {
        std::fs::write(
            d.join("last-phone"),
            format!("{}\n", sim::FIRST.to_lowercase()),
        )
        .unwrap();
        c.last_phone_file = Some(d.join("last-phone"));
        c.reconnect = Reconnect {
            every: Duration::from_secs(1),
            window: Duration::from_secs(30),
        };
    })
    .await;
    r.sim.set_reachable(false);
    let mut s = watch(&mut r.client).await;
    let m = until(&mut s, "the last phone marked", |m| {
        m.known.iter().any(|k| k.last)
    })
    .await;
    assert_eq!(m.known[0].address, sim::FIRST);
    let m = until(&mut s, "an automatic attempt failing", |m| {
        attempt(m).detail.starts_with("Couldn't reach")
    })
    .await;
    assert_eq!(
        attempt(&m).detail,
        "Couldn't reach Simulated phone (simulated: the phone didn't answer (out of range)); trying again in 1 s."
    );
    until(&mut s, "an automatic attempt shown", |m| {
        attempt(m).automatic
    })
    .await;
    r.sim.set_reachable(true);
    until(&mut s, "connected by itself", |m| {
        connected_addr(m) == sim::FIRST
    })
    .await;
    let tries = r.sim.connects().len();
    assert!(tries >= 2, "{tries}");

    // The link drops: tried again by itself.
    r.sim.disconnect();
    until(&mut s, "gone", |m| connected_addr(m).is_empty()).await;
    until(&mut s, "back by itself", |m| {
        connected_addr(m) == sim::FIRST
    })
    .await;
    assert!(r.sim.connects().len() > tries);
}

#[tokio::test]
async fn reconnecting_gives_up_after_its_window() {
    let mut r = start_with("give-up", quiet(false), |c, d| {
        std::fs::write(d.join("last-phone"), sim::FIRST).unwrap();
        c.last_phone_file = Some(d.join("last-phone"));
        c.reconnect = Reconnect {
            every: Duration::from_secs(1),
            window: Duration::from_secs(2),
        };
    })
    .await;
    r.sim.set_reachable(false);
    let mut s = watch(&mut r.client).await;
    let m = until(&mut s, "gave up", |m| {
        attempt(m).detail.starts_with("Stopped")
    })
    .await;
    assert_eq!(
        attempt(&m).detail,
        "Stopped trying to reach Simulated phone after 1 min. Tap it to connect."
    );
    let n = r.sim.connects().len();
    tokio::time::sleep(Duration::from_millis(2500)).await;
    assert_eq!(r.sim.connects().len(), n, "no more attempts");
}

#[tokio::test]
async fn no_usable_last_phone_no_attempts() {
    for (name, file) in [("no-last", None), ("bad-last", Some("not an address"))] {
        let r = start_with(name, quiet(false), |c, d| {
            if let Some(text) = file {
                std::fs::write(d.join("last-phone"), text).unwrap();
            }
            c.last_phone_file = Some(d.join("last-phone"));
            c.reconnect = Reconnect {
                every: Duration::from_secs(1),
                window: Duration::from_secs(30),
            };
        })
        .await;
        tokio::time::sleep(Duration::from_millis(2500)).await;
        assert!(r.sim.connects().is_empty(), "{name}");
        drop(r);
    }
}

// ---- one phone at a time ----------------------------------------------------

fn listed(m: &pb::WatchAudioResponse, address: &str) -> Option<pb::Phone> {
    m.phone
        .iter()
        .chain(m.known.iter())
        .find(|p| p.address == address)
        .cloned()
}

#[tokio::test]
async fn a_phone_paired_in_the_window_takes_over_and_the_old_one_is_listed() {
    let mut r = start(
        "pair-takes-over",
        SimConfig {
            pair_after: Some(Duration::from_millis(200)),
            ..SimConfig::default()
        },
    )
    .await;
    let mut s = watch(&mut r.client).await;
    until(&mut s, "the first phone", |m| {
        connected_addr(m) == sim::FIRST
    })
    .await;
    r.client
        .open_pairing(pb::OpenPairingRequest {
            seconds: 60,
            source: "test".into(),
        })
        .await
        .unwrap();
    let m = until(&mut s, "a question", |m| {
        m.pairing.as_ref().is_some_and(|p| p.question.is_some())
    })
    .await;
    let id = m.pairing.unwrap().question.unwrap().id;
    r.client
        .confirm_pairing(pb::ConfirmPairingRequest {
            id,
            accept: true,
            source: "test".into(),
        })
        .await
        .unwrap();
    let m = until(
        &mut s,
        "the new phone in use, the old one disconnected",
        |m| connected_addr(m) == sim::SECOND && listed(m, sim::FIRST).is_some_and(|p| !p.connected),
    )
    .await;
    assert!(m.phone.as_ref().unwrap().last);
    assert_eq!(r.sim.disconnects(), [sim::FIRST]);
}

#[tokio::test]
async fn a_paired_phone_connecting_by_itself_takes_over() {
    let mut r = start("connects-itself", quiet(true)).await;
    r.sim.add_paired("02:00:00:00:00:03", "Third phone");
    let mut s = watch(&mut r.client).await;
    let m = until(&mut s, "both listed", |m| {
        listed(m, "02:00:00:00:00:03").is_some()
    })
    .await;
    assert_eq!(connected_addr(&m), sim::FIRST);
    // It comes into range and connects; BlueZ keeps the first connected too.
    r.sim.connect_also("02:00:00:00:00:03");
    let m = until(&mut s, "the newest in use, the first disconnected", |m| {
        connected_addr(m) == "02:00:00:00:00:03"
            && listed(m, sim::FIRST).is_some_and(|p| !p.connected)
    })
    .await;
    assert_eq!(m.known.len(), 1, "every paired phone listed once");
    assert_eq!(r.sim.disconnects(), [sim::FIRST]);
    // And back: the driver connects the first again.
    assert!(connect(&mut r.client, sim::FIRST).await.accepted);
    until(&mut s, "the first again", |m| {
        connected_addr(m) == sim::FIRST
    })
    .await;
}

// ---- disconnect and forget (Phones' Disconnect and Delete) ----------------

async fn disconnect(c: &mut Client, address: &str) -> pb::DisconnectPhoneResponse {
    c.disconnect_phone(pb::DisconnectPhoneRequest {
        address: address.into(),
        source: "test".into(),
    })
    .await
    .expect("disconnect_phone")
    .into_inner()
}

async fn forget(c: &mut Client, address: &str) -> pb::ForgetPhoneResponse {
    c.forget_phone(pb::ForgetPhoneRequest {
        address: address.into(),
        source: "test".into(),
    })
    .await
    .expect("forget_phone")
    .into_inner()
}

fn reconnecting(c: &mut Config, d: &std::path::Path) {
    c.last_phone_file = Some(d.join("last-phone"));
    c.reconnect = Reconnect {
        every: Duration::from_secs(1),
        window: Duration::from_secs(30),
    };
}

#[tokio::test]
async fn a_phone_the_driver_disconnects_isnt_reconnected_by_itself() {
    let mut r = start_with("disconnect", quiet(true), reconnecting).await;
    let mut s = watch(&mut r.client).await;
    until(&mut s, "connected", |m| connected_addr(m) == sim::FIRST).await;
    let ok = disconnect(&mut r.client, sim::FIRST).await;
    assert!(ok.accepted, "{}", ok.detail);
    assert_eq!(ok.detail, "Disconnecting Simulated phone…");
    let m = until(&mut s, "disconnected", |m| connected_addr(m).is_empty()).await;
    assert!(
        listed(&m, sim::FIRST).is_some_and(|p| p.paired && p.last),
        "still paired, still the last"
    );
    tokio::time::sleep(Duration::from_millis(2500)).await;
    assert!(r.sim.connects().is_empty(), "not reconnected by itself");
    let no = disconnect(&mut r.client, sim::FIRST).await;
    assert!(!no.accepted);
    assert_eq!(no.detail, "Simulated phone isn't connected.");
    // Connect brings it back, and a later drop is reconnected again.
    assert!(connect(&mut r.client, sim::FIRST).await.accepted);
    until(&mut s, "connected again", |m| {
        connected_addr(m) == sim::FIRST
    })
    .await;
    r.sim.disconnect();
    until(&mut s, "dropped", |m| connected_addr(m).is_empty()).await;
    until(&mut s, "back by itself", |m| {
        connected_addr(m) == sim::FIRST
    })
    .await;
}

#[tokio::test]
async fn a_forgotten_phone_is_gone_and_no_longer_the_last() {
    let mut r = start_with("forget", quiet(true), reconnecting).await;
    r.sim.add_paired("02:00:00:00:00:03", "Third phone");
    let mut s = watch(&mut r.client).await;
    until(&mut s, "both", |m| {
        listed(m, "02:00:00:00:00:03").is_some() && connected_addr(m) == sim::FIRST
    })
    .await;
    assert!(r.dir.join("last-phone").exists());

    let no = forget(&mut r.client, "02:00:00:00:00:09").await;
    assert_eq!(
        (no.accepted, no.detail.as_str()),
        (false, "That phone isn't paired.")
    );
    let ok = forget(&mut r.client, "02:00:00:00:00:03").await;
    assert_eq!(
        (ok.accepted, ok.detail.as_str()),
        (true, "Deleting Third phone…")
    );
    let m = until(&mut s, "gone", |m| listed(m, "02:00:00:00:00:03").is_none()).await;
    assert_eq!(connected_addr(&m), sim::FIRST);
    until(&mut s, "said", |m| {
        attempt(m).detail == "Deleted Third phone. Pair it again to use it."
    })
    .await;

    // The connected one, the last phone: gone, not remembered, not tried.
    assert!(forget(&mut r.client, sim::FIRST).await.accepted);
    let m = until(&mut s, "none left", |m| {
        m.phone.is_none() && m.known.is_empty()
    })
    .await;
    assert!(m.known.iter().all(|k| !k.last));
    assert!(!r.dir.join("last-phone").exists());
    tokio::time::sleep(Duration::from_millis(2500)).await;
    assert!(r.sim.connects().is_empty());
}

async fn set_volume(
    c: &mut Client,
    change: pb::set_volume_request::Change,
) -> pb::SetVolumeResponse {
    c.set_volume(pb::SetVolumeRequest {
        change: Some(change),
        source: "test".into(),
    })
    .await
    .expect("set_volume")
    .into_inner()
}

#[tokio::test]
async fn volume_level_cap_mute_and_saving() {
    use pb::set_volume_request::Change as C;
    let mut r = start("volume", SimConfig::default()).await;
    let mut s = watch(&mut r.client).await;
    // No file yet: the start maximum (15), unmuted; the cap and the steps
    // published; not applied (no PipeWire here), and said so.
    let m = until(&mut s, "the volume", |m| m.volume.is_some()).await;
    let v = m.volume.unwrap();
    assert_eq!((v.level, v.max, v.steps, v.muted), (15, 24, 30, false));
    assert!(!v.applied);
    assert!(
        v.detail.starts_with("Not applied: simulated"),
        "{}",
        v.detail
    );

    let a = set_volume(&mut r.client, C::Steps(3)).await;
    assert_eq!(a.volume.unwrap().level, 18);
    assert!(!a.applied);
    until(&mut s, "18", |m| {
        m.volume.as_ref().is_some_and(|v| v.level == 18)
    })
    .await;

    // Above the cap: the cap, and the answer says so.
    let a = set_volume(&mut r.client, C::Level(30)).await;
    assert_eq!(a.volume.unwrap().level, 24);
    assert_eq!(a.detail, "The maximum is 24 (configuration).");

    let a = set_volume(&mut r.client, C::Mute(pb::MuteChange::Toggle.into())).await;
    let v = a.volume.unwrap();
    assert_eq!((v.level, v.muted), (24, true), "the level is kept");
    until(&mut s, "muted", |m| {
        m.volume.as_ref().is_some_and(|v| v.muted)
    })
    .await;
    let a = set_volume(&mut r.client, C::Steps(-4)).await;
    assert_eq!(
        a.volume.unwrap(),
        pb::Volume {
            level: 20,
            muted: true,
            ..v.clone()
        },
        "down stays muted"
    );
    let a = set_volume(&mut r.client, C::Steps(1)).await;
    assert!(!a.volume.unwrap().muted, "up unmutes");

    // Nothing asked: refused.
    let e = r
        .client
        .set_volume(pb::SetVolumeRequest {
            change: None,
            source: String::new(),
        })
        .await
        .unwrap_err();
    assert_eq!(e.code(), tonic::Code::InvalidArgument);

    // Saved 2 s after the last change, not at each one; at once on stop.
    let file = r.dir.join("volume.json");
    assert!(!file.exists(), "not saved at each change");
    r.manager.stop();
    assert_eq!(std::fs::read_to_string(&file).unwrap(), "{\"level\":21}");

    // A restart comes back no louder than the start maximum.
    let (saved, problem) = audio_manager::manager::load_volume(Some(&file));
    assert_eq!((saved, problem), (Some(21), None));
    let l = VolumeLimits::default();
    assert_eq!(audio_manager::volume::at_start(&l, saved).level, 15);
}

#[tokio::test]
async fn the_volume_is_saved_once_the_changes_stop() {
    use pb::set_volume_request::Change as C;
    let mut r = start("volume-save", SimConfig::default()).await;
    for _ in 0..5 {
        set_volume(&mut r.client, C::Steps(-1)).await;
    }
    let file = r.dir.join("volume.json");
    tokio::time::sleep(audio_manager::manager::SAVE_VOLUME_AFTER / 2).await;
    assert!(!file.exists(), "still turning");
    tokio::time::sleep(audio_manager::manager::SAVE_VOLUME_AFTER).await;
    assert_eq!(std::fs::read_to_string(&file).unwrap(), "{\"level\":10}");
}

#[tokio::test]
async fn the_knobs_play_pause_toggles() {
    use audio_manager::model::Command;
    let mut r = start(
        "play-pause",
        SimConfig {
            pair_after: None,
            ..SimConfig::default()
        },
    )
    .await;
    let mut s = watch(&mut r.client).await;
    let state = |m: &pb::WatchAudioResponse| m.now_playing.as_ref().map(|n| n.state());
    until(&mut s, "playing", |m| {
        state(m) == Some(pb::PlayState::Playing)
    })
    .await;
    assert_eq!(r.manager.play_pause("knob").await, Ok(Command::Pause));
    until(&mut s, "paused", |m| {
        state(m) == Some(pb::PlayState::Paused)
    })
    .await;
    assert_eq!(r.manager.play_pause("knob").await, Ok(Command::Play));
    until(&mut s, "playing again", |m| {
        state(m) == Some(pb::PlayState::Playing)
    })
    .await;

    // No phone: refused, said why.
    r.sim.disconnect();
    until(&mut s, "no phone", |m| m.phone.is_none()).await;
    assert_eq!(
        r.manager.play_pause("knob").await,
        Err("No phone is connected.".to_string())
    );
}

// ---- phone calls (ADR-0045) ---------------------------------------------------

fn calls(m: &pb::WatchAudioResponse) -> pb::Calls {
    m.calls.clone().unwrap_or_default()
}

fn call_state(m: &pb::WatchAudioResponse) -> pb::CallState {
    m.calls
        .as_ref()
        .and_then(|c| c.call.as_ref())
        .map_or(pb::CallState::Unspecified, |c| c.state())
}

async fn answer(c: &mut Client, id: u64) -> pb::AnswerCallResponse {
    c.answer_call(pb::AnswerCallRequest {
        id,
        source: "test".into(),
    })
    .await
    .unwrap()
    .into_inner()
}

async fn hang_up(c: &mut Client, id: u64) -> pb::HangUpResponse {
    c.hang_up(pb::HangUpRequest {
        id,
        source: "test".into(),
    })
    .await
    .unwrap()
    .into_inner()
}

async fn mute(c: &mut Client, muted: bool) -> pb::SetMicMutedResponse {
    c.set_mic_muted(pb::SetMicMutedRequest {
        muted,
        source: "test".into(),
    })
    .await
    .unwrap()
    .into_inner()
}

fn no_pairing() -> SimConfig {
    SimConfig {
        pair_after: None,
        ..SimConfig::default()
    }
}

#[tokio::test]
async fn a_call_rings_is_answered_muted_and_hung_up_and_the_music_resumes() {
    let mut r = start("call", no_pairing()).await;
    let mut s = watch(&mut r.client).await;
    let m = until(&mut s, "playing, calls ready", |m| {
        play_state_of(m) == pb::PlayState::Playing && calls(m).available
    })
    .await;
    assert!(calls(&m).call.is_none());
    assert_eq!(calls(&m).phone_name, "Simulated phone");
    assert!(
        !mute(&mut r.client, true).await.applied,
        "nothing to mute without a call"
    );

    r.calls.ring(SIM_NUMBER, SIM_CALLER);
    let m = until(&mut s, "ringing, music paused", |m| {
        call_state(m) == pb::CallState::Incoming && play_state_of(m) == pb::PlayState::Paused
    })
    .await;
    let call = calls(&m).call.unwrap();
    assert_eq!(
        (call.name.as_str(), call.number.as_str()),
        (SIM_CALLER, SIM_NUMBER)
    );
    assert_eq!(call.active_s, 0);
    assert_eq!(calls(&m).other_calls, 0);

    // Directions are skipped during a call, not queued.
    let said = speak(&mut r.client, "Turn right.").await;
    assert!(!said.accepted && said.detail.contains("call"), "{said:?}");

    let a = answer(&mut r.client, call.id).await;
    assert!(a.accepted, "{a:?}");
    until(&mut s, "active", |m| call_state(m) == pb::CallState::Active).await;
    let m = until(&mut s, "a second into the call", |m| {
        calls(m).call.is_some_and(|c| c.active_s >= 1)
    })
    .await;
    assert_eq!(calls(&m).call.unwrap().id, call.id, "the same call");
    assert!(
        !answer(&mut r.client, call.id).await.accepted,
        "not ringing any more"
    );

    assert!(mute(&mut r.client, true).await.applied);
    until(&mut s, "muted", |m| calls(m).mic_muted).await;
    assert_eq!(r.calls.mutes(), vec![true]);

    let h = hang_up(&mut r.client, call.id).await;
    assert_eq!((h.accepted, h.detail.as_str()), (true, "Hung up."));
    let m = until(&mut s, "no call", |m| calls(m).call.is_none()).await;
    assert!(!calls(&m).mic_muted, "the next call starts unmuted");
    until(&mut s, "music back", |m| {
        play_state_of(m) == pb::PlayState::Playing
    })
    .await;
    assert_eq!(r.calls.mutes(), vec![true, false]);
    let gone = hang_up(&mut r.client, call.id).await;
    assert!(!gone.accepted && gone.detail.contains("ended"), "{gone:?}");
}

#[tokio::test]
async fn declining_and_a_waiting_call() {
    let mut r = start("call-wait", no_pairing()).await;
    let mut s = watch(&mut r.client).await;
    until(&mut s, "ready", |m| calls(m).available).await;

    // Declined: gone, and a new call gets a new id.
    r.calls.ring(SIM_NUMBER, SIM_CALLER);
    let m = until(&mut s, "ringing", |m| {
        call_state(m) == pb::CallState::Incoming
    })
    .await;
    let first = calls(&m).call.unwrap().id;
    let h = hang_up(&mut r.client, first).await;
    assert_eq!(h.detail, "Declined.");
    until(&mut s, "declined", |m| calls(m).call.is_none()).await;

    let a = r.calls.ring("", "");
    let m = until(&mut s, "a withheld call", |m| {
        call_state(m) == pb::CallState::Incoming
    })
    .await;
    let c = calls(&m).call.unwrap();
    assert!(c.withheld && c.number.is_empty());
    assert_ne!(c.id, first);
    r.calls.answer_on_phone(&a);
    until(&mut s, "answered on the phone", |m| {
        call_state(m) == pb::CallState::Active
    })
    .await;

    // Another call during it: shown first, declined here, answered only on
    // the phone.
    r.calls.ring("+15550199", "");
    let m = until(&mut s, "waiting", |m| {
        call_state(m) == pb::CallState::Waiting
    })
    .await;
    let w = calls(&m).call.unwrap();
    assert_eq!(calls(&m).other_calls, 1);
    let refused = answer(&mut r.client, w.id).await;
    assert!(
        !refused.accepted && refused.detail.contains("on the phone"),
        "{refused:?}"
    );
    assert!(hang_up(&mut r.client, w.id).await.accepted);
    let m = until(&mut s, "back to the first", |m| {
        call_state(m) == pb::CallState::Active
    })
    .await;
    assert_eq!(calls(&m).other_calls, 0);
    assert_eq!(calls(&m).call.unwrap().id, c.id);
    r.calls.end(&a);
    until(&mut s, "ended by the far end", |m| calls(m).call.is_none()).await;
}

#[tokio::test]
async fn a_prompt_stops_for_a_call_and_calls_go_with_the_phone() {
    let mut r = start("call-phone", no_pairing()).await;
    let mut s = watch(&mut r.client).await;
    until(&mut s, "ready", |m| calls(m).available).await;
    let long = "In two miles, keep left to stay on the interstate, then take exit forty two.";
    assert!(speak(&mut r.client, long).await.accepted);
    until(&mut s, "speaking", |m| prompts(m).speaking).await;
    r.calls.ring(SIM_NUMBER, SIM_CALLER);
    let m = until(&mut s, "ringing", |m| {
        call_state(m) == pb::CallState::Incoming
    })
    .await;
    assert!(!prompts(&m).speaking, "cut off for the call");

    // The phone goes: so do its calls; it comes back with the call.
    r.sim.disconnect();
    let m = until(&mut s, "no phone", |m| m.phone.is_none()).await;
    assert!(calls(&m).call.is_none());
    assert!(!calls(&m).available);
    assert_eq!(calls(&m).detail, "No phone is connected.");
    r.sim.connect();
    until(&mut s, "ringing again", |m| {
        call_state(m) == pb::CallState::Incoming
    })
    .await;
}

#[tokio::test]
async fn without_a_microphone_calls_stay_on_the_phone() {
    let mut r = start_full(
        "call-off",
        no_pairing(),
        |_, _| {},
        Some(Arc::new(NoCalls::new("no call microphone is configured"))),
    )
    .await;
    let mut s = watch(&mut r.client).await;
    let m = until(&mut s, "a phone", |m| m.phone.is_some()).await;
    let c = calls(&m);
    assert!(!c.available && c.call.is_none());
    assert_eq!(
        c.detail,
        "Calls stay on the phone: no call microphone is configured."
    );
    let a = answer(&mut r.client, 1).await;
    assert!(!a.accepted && a.detail.starts_with("Calls stay on the phone"));
    // The simulated calls exist but aren't this manager's.
    r.calls.ring(SIM_NUMBER, SIM_CALLER);
    tokio::time::sleep(Duration::from_millis(300)).await;
    let m = until(&mut s, "a later report", |_| true).await;
    assert!(calls(&m).call.is_none());
    assert!(speak(&mut r.client, "Turn left.").await.accepted);
}

#[tokio::test]
async fn the_knobs_push_answers_and_hangs_up() {
    let mut r = start("call-knob", no_pairing()).await;
    let mut s = watch(&mut r.client).await;
    until(&mut s, "playing, calls ready", |m| {
        play_state_of(m) == pb::PlayState::Playing && calls(m).available
    })
    .await;
    r.calls.ring(SIM_NUMBER, SIM_CALLER);
    until(&mut s, "ringing", |m| {
        call_state(m) == pb::CallState::Incoming
    })
    .await;
    assert_eq!(r.manager.knob_push("test").await.unwrap(), "Answered.");
    until(&mut s, "answered", |m| {
        call_state(m) == pb::CallState::Active
    })
    .await;

    // A waiting call: the push leaves both alone.
    let w = r.calls.ring("+15550199", "");
    until(&mut s, "waiting", |m| {
        call_state(m) == pb::CallState::Waiting
    })
    .await;
    assert!(r.manager.knob_push("test").await.is_err());
    r.calls.end(&w);
    until(&mut s, "the first again", |m| {
        call_state(m) == pb::CallState::Active
    })
    .await;

    assert_eq!(r.manager.knob_push("test").await.unwrap(), "Hung up.");
    until(&mut s, "no call", |m| calls(m).call.is_none()).await;
    until(&mut s, "music back", |m| {
        play_state_of(m) == pb::PlayState::Playing
    })
    .await;
    // No call: play/pause again.
    assert_eq!(r.manager.knob_push("test").await.unwrap(), "Pause");
    until(&mut s, "paused", |m| {
        play_state_of(m) == pb::PlayState::Paused
    })
    .await;
}

#[tokio::test]
async fn a_phone_without_its_own_ring_tone_is_rung_through_the_speakers() {
    let mut r = start("call-ring", no_pairing()).await;
    let mut s = watch(&mut r.client).await;
    until(&mut s, "ready", |m| calls(m).available).await;

    // No ring tone from the phone: after ring_after, audio-manager rings
    // until the call is answered.
    r.calls.ring(SIM_NUMBER, SIM_CALLER);
    let m = until(&mut s, "ringing", |m| {
        call_state(m) == pb::CallState::Incoming
    })
    .await;
    assert!(!calls(&m).local_ring, "not before ring_after");
    let m = until(&mut s, "rung here", |m| calls(m).local_ring).await;
    let id = calls(&m).call.unwrap().id;
    tokio::time::sleep(Duration::from_millis(500)).await;
    assert!(r.ringer.rings() >= 2, "it repeats: {}", r.ringer.rings());
    assert!(answer(&mut r.client, id).await.accepted);
    until(&mut s, "answered, quiet", |m| {
        call_state(m) == pb::CallState::Active && !calls(m).local_ring
    })
    .await;
    let rung = r.ringer.rings();

    // A waiting call isn't rung over the call in progress.
    let w = r.calls.ring("+15550199", "");
    until(&mut s, "waiting", |m| {
        call_state(m) == pb::CallState::Waiting
    })
    .await;
    tokio::time::sleep(Duration::from_millis(600)).await;
    let m = until(&mut s, "a later report", |_| true).await;
    assert!(!calls(&m).local_ring);
    assert_eq!(r.ringer.rings(), rung);
    r.calls.end(&w);
    let m = until(&mut s, "the first again", |m| {
        call_state(m) == pb::CallState::Active
    })
    .await;
    assert!(
        hang_up(&mut r.client, calls(&m).call.unwrap().id)
            .await
            .accepted
    );
    until(&mut s, "no call", |m| calls(m).call.is_none()).await;

    // A phone that rings in-band: audio-manager stays quiet.
    r.calls.set_in_band(true);
    r.calls.ring(SIM_NUMBER, SIM_CALLER);
    until(&mut s, "ringing in-band", |m| {
        call_state(m) == pb::CallState::Incoming
    })
    .await;
    tokio::time::sleep(Duration::from_millis(600)).await;
    let m = until(&mut s, "a later report", |_| true).await;
    assert!(!calls(&m).local_ring);
    assert_eq!(r.ringer.rings(), rung);
}
