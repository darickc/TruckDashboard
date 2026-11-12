//! audio-manager end to end [SIM]: the simulated phone, the manager and a
//! gRPC client over a unix socket. Now playing and controls, link loss (the
//! track goes with the phone), Bluetooth going away, the pairing window with
//! a passkey question accepted and refused, the speaker settings, and the
//! once-a-second heartbeat.

#![allow(clippy::unwrap_used)]

use std::sync::Arc;
use std::time::Duration;

use audio_manager::backend::Bluetooth;
use audio_manager::dsp::{Limits, Settings};
use audio_manager::manager::{Config, Manager};
use audio_manager::pairing;
use audio_manager::runner::NoDsp;
use audio_manager::server::Api;
use audio_manager::sim::{self, SimConfig, SimPhone};
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
    dir: std::path::PathBuf,
}

async fn start(test: &str, sim_cfg: SimConfig) -> Running {
    let dir = dir(test);
    let (agent_tx, agent_rx) = mpsc::channel(8);
    let sim = SimPhone::new(sim_cfg, agent_tx);
    let bt: Arc<dyn Bluetooth> = Arc::new(sim.clone());
    let manager = Manager::new(
        Config {
            pairing: pairing::Config::default(),
            name: "F-250".into(),
            limits: Limits::default(),
            defaults: Settings::default(),
            settings_file: Some(dir.join("speakers.json")),
            simulated: true,
        },
        bt,
        Arc::new(NoDsp::new("simulated: no PipeWire")),
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
