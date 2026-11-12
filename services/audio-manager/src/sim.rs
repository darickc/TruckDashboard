//! A simulated phone, for the Mac (`make sim`) and the tests: no Bluetooth,
//! labelled simulated on the screen. One paired phone plays a made-up
//! playlist; Play, Pause, Next and Previous work; while the pairing window is
//! open a second made-up phone asks to pair after a few seconds. Tests drive
//! link loss and BlueZ going away with [`SimPhone::disconnect`] and
//! [`SimPhone::set_adapter`].

use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::sync::{mpsc, oneshot, watch};
use tokio::time::Instant;

use crate::backend::Bluetooth;
use crate::model::{
    Adapter, AgentAsk, AgentRequest, Command, Phone, PlayState, Player, Snapshot, Track,
};

#[derive(Debug, Clone)]
pub struct SimConfig {
    /// A second phone asks to pair this long after the window opens; None:
    /// never.
    pub pair_after: Option<Duration>,
    /// The phone connects on its own after a link loss, this long after.
    pub reconnect_after: Option<Duration>,
}

impl Default for SimConfig {
    fn default() -> SimConfig {
        SimConfig {
            pair_after: Some(Duration::from_secs(5)),
            reconnect_after: None,
        }
    }
}

pub const FIRST: &str = "02:00:00:00:00:01";
pub const SECOND: &str = "02:00:00:00:00:02";
/// The code the second phone "shows".
pub const SIM_PASSKEY: u32 = 246_810;

#[derive(Debug)]
struct State {
    adapter_up: bool,
    discoverable: bool,
    phones: Vec<Phone>,
    playlist: Vec<Track>,
    index: usize,
    play: PlayState,
    /// Position at `at`.
    position_ms: u32,
    at: Instant,
    /// Counts window openings, so an old pairing timer does nothing.
    window_gen: u64,
}

impl State {
    fn position(&self, now: Instant) -> u32 {
        if self.play == PlayState::Playing {
            let gone = u32::try_from(now.saturating_duration_since(self.at).as_millis())
                .unwrap_or(u32::MAX);
            self.position_ms.saturating_add(gone)
        } else {
            self.position_ms
        }
    }

    fn rebase(&mut self, now: Instant) {
        self.position_ms = self.position(now);
        self.at = now;
    }

    fn snapshot(&self, now: Instant) -> Snapshot {
        if !self.adapter_up {
            return Snapshot::unavailable("simulated: Bluetooth is off");
        }
        let mut phones = self.phones.clone();
        phones.sort_by(|a, b| b.connected.cmp(&a.connected).then(a.name.cmp(&b.name)));
        let connected = phones.iter().find(|p| p.connected).cloned();
        Snapshot {
            adapter: Adapter::Ready {
                discoverable: self.discoverable,
                pairable: self.discoverable,
            },
            player: connected.as_ref().map(|p| Player {
                path: format!("/sim/{}/player0", p.address),
                address: p.address.clone(),
                name: "Simulated player".into(),
                state: self.play,
                track: self.playlist[self.index].clone(),
                position_ms: Some(self.position(now)),
                read_at: now,
            }),
            streaming: connected.is_some() && self.play == PlayState::Playing,
            phones,
        }
    }
}

fn playlist() -> Vec<Track> {
    [
        (
            "Simulated Track One",
            "The Test Tones",
            "Not a Real Album",
            185_000,
        ),
        (
            "Second Simulated Song",
            "The Test Tones",
            "Not a Real Album",
            242_000,
        ),
        ("A Third One", "Placeholder Band", "Made Up", 201_000),
    ]
    .into_iter()
    .map(|(t, a, al, d)| Track {
        title: t.into(),
        artist: a.into(),
        album: al.into(),
        duration_ms: Some(d),
    })
    .collect()
}

#[derive(Clone)]
pub struct SimPhone {
    state: Arc<Mutex<State>>,
    snap: watch::Sender<Snapshot>,
    agent: mpsc::Sender<AgentRequest>,
    cfg: SimConfig,
}

impl SimPhone {
    /// A simulated phone, connected and playing. Agent requests go to
    /// `agent`. Call [`SimPhone::run`] (or let tests step it) for the track
    /// to move on.
    pub fn new(cfg: SimConfig, agent: mpsc::Sender<AgentRequest>) -> SimPhone {
        let now = Instant::now();
        let state = State {
            adapter_up: true,
            discoverable: false,
            phones: vec![Phone {
                address: FIRST.into(),
                name: "Simulated phone".into(),
                connected: true,
                paired: true,
            }],
            playlist: playlist(),
            index: 0,
            play: PlayState::Playing,
            position_ms: 0,
            at: now,
            window_gen: 0,
        };
        let snap = watch::Sender::new(state.snapshot(now));
        SimPhone {
            state: Arc::new(Mutex::new(state)),
            snap,
            agent,
            cfg,
        }
    }

    fn with<R>(&self, f: impl FnOnce(&mut State, Instant) -> R) -> R {
        let now = Instant::now();
        let mut s = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let r = f(&mut s, now);
        self.snap.send_replace(s.snapshot(now));
        r
    }

    /// Moves to the next track when one ends. Runs until dropped.
    pub async fn run(self) {
        let mut tick = tokio::time::interval(Duration::from_millis(500));
        loop {
            tick.tick().await;
            let ended = {
                let s = self
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                let now = Instant::now();
                s.play == PlayState::Playing
                    && s.playlist[s.index]
                        .duration_ms
                        .is_some_and(|d| s.position(now) >= d)
            };
            if ended {
                self.with(|s, now| {
                    s.index = (s.index + 1) % s.playlist.len();
                    s.position_ms = 0;
                    s.at = now;
                });
            }
        }
    }

    /// The phone drops the link (out of range, turned off).
    pub fn disconnect(&self) {
        self.with(|s, _| {
            for p in &mut s.phones {
                p.connected = false;
            }
        });
        if let Some(after) = self.cfg.reconnect_after {
            let me = self.clone();
            tokio::spawn(async move {
                tokio::time::sleep(after).await;
                me.connect();
            });
        }
    }

    /// The first paired phone connects again.
    pub fn connect(&self) {
        self.with(|s, now| {
            if let Some(p) = s.phones.iter_mut().find(|p| p.paired) {
                p.connected = true;
            }
            s.rebase(now);
        });
    }

    /// Bluetooth (BlueZ, the adapter) goes away or comes back. A restarted
    /// adapter isn't discoverable.
    pub fn set_adapter(&self, up: bool) {
        self.with(|s, _| {
            s.adapter_up = up;
            s.discoverable = false;
        });
    }

    fn start_pairing_timer(&self, generation: u64) {
        let Some(after) = self.cfg.pair_after else {
            return;
        };
        let me = self.clone();
        tokio::spawn(async move {
            tokio::time::sleep(after).await;
            let still = {
                let s = me
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                s.discoverable
                    && s.window_gen == generation
                    && s.adapter_up
                    && !s.phones.iter().any(|p| p.address == SECOND)
            };
            if !still {
                return;
            }
            let (tx, rx) = oneshot::channel();
            let req = AgentRequest {
                address: SECOND.into(),
                name: "Simulated phone 2".into(),
                ask: AgentAsk::Confirm {
                    passkey: SIM_PASSKEY,
                },
                reply: tx,
            };
            if me.agent.send(req).await.is_err() {
                return;
            }
            if rx.await == Ok(true) {
                me.with(|s, now| {
                    for p in &mut s.phones {
                        p.connected = false;
                    }
                    s.phones.push(Phone {
                        address: SECOND.into(),
                        name: "Simulated phone 2".into(),
                        connected: true,
                        paired: true,
                    });
                    s.rebase(now);
                });
            }
        });
    }
}

#[tonic::async_trait]
impl Bluetooth for SimPhone {
    fn snapshot(&self) -> watch::Receiver<Snapshot> {
        self.snap.subscribe()
    }

    async fn set_pairing(&self, on: bool, _timeout_s: u32) -> Result<(), String> {
        let generation = self.with(|s, _| {
            if !s.adapter_up {
                return Err("simulated: Bluetooth is off".to_string());
            }
            s.discoverable = on;
            if on {
                s.window_gen += 1;
            }
            Ok(s.window_gen)
        })?;
        if on {
            self.start_pairing_timer(generation);
        }
        Ok(())
    }

    async fn control(&self, cmd: Command) -> Result<(), String> {
        self.with(|s, now| {
            if !s.phones.iter().any(|p| p.connected) {
                return Err("no phone is connected".to_string());
            }
            s.rebase(now);
            match cmd {
                Command::Play => s.play = PlayState::Playing,
                Command::Pause => s.play = PlayState::Paused,
                Command::Next => {
                    s.index = (s.index + 1) % s.playlist.len();
                    s.position_ms = 0;
                }
                Command::Previous => {
                    // Like most phones: back to the start, unless near it.
                    if s.position_ms < 3000 {
                        s.index = (s.index + s.playlist.len() - 1) % s.playlist.len();
                    }
                    s.position_ms = 0;
                }
            }
            Ok(())
        })
    }

    async fn trust(&self, _address: &str) -> Result<(), String> {
        Ok(())
    }
}
