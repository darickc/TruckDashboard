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
    Adapter, AgentAsk, AgentRequest, Command, CoverArt, Phone, Picture, PlayState, Player,
    Snapshot, Track,
};

#[derive(Debug, Clone)]
pub struct SimConfig {
    /// A second phone asks to pair this long after the window opens; None:
    /// never.
    pub pair_after: Option<Duration>,
    /// The phone connects on its own after a link loss, this long after.
    pub reconnect_after: Option<Duration>,
    /// The first phone is connected at start (else paired, not connected).
    pub start_connected: bool,
    /// How long a connection asked for (`connect`) takes.
    pub connect_takes: Duration,
}

impl Default for SimConfig {
    fn default() -> SimConfig {
        SimConfig {
            pair_after: Some(Duration::from_secs(5)),
            reconnect_after: None,
            start_connected: true,
            connect_takes: Duration::from_secs(1),
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
    /// The phones answer a connection (in range, Bluetooth on).
    reachable: bool,
    /// Connections asked for, by address (tests).
    connects: Vec<String>,
    disconnects: Vec<String>,
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
                obex_port: Some(SIM_OBEX_PSM),
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

/// The simulated player's cover art "port" (not a real PSM: nothing
/// connects to it).
pub const SIM_OBEX_PSM: u16 = 0x1005;

/// The simulated phone's cover art for `snap`: a made-up picture for every
/// track with an image handle; "No picture for this track" for one without.
fn sim_art(snap: &Snapshot, pictures: &[Option<Arc<Vec<u8>>>], playlist: &[Track]) -> CoverArt {
    let Some(p) = &snap.player else {
        return CoverArt::default();
    };
    let Some(handle) = &p.track.image_handle else {
        return CoverArt::none(crate::cover_art::NO_PICTURE);
    };
    let Some(i) = playlist
        .iter()
        .position(|t| t.image_handle.as_ref() == Some(handle))
    else {
        return CoverArt::none(crate::cover_art::NO_PICTURE);
    };
    match &pictures[i] {
        Some(bytes) => CoverArt {
            picture: Some(Picture {
                address: p.address.clone(),
                handle: handle.clone(),
                id: (i as u64) + 1,
                bytes: Arc::clone(bytes),
                mime: "image/bmp",
            }),
            detail: String::new(),
        },
        None => CoverArt::none(crate::cover_art::NO_PICTURE),
    }
}

/// A made-up picture for a simulated track: a 200×200 BMP (no image
/// library needed): a record on a gradient in the track's colours, so each
/// track's picture looks different.
pub fn sim_picture(seed: usize) -> Vec<u8> {
    const W: u32 = 200;
    const PALETTE: [([u8; 3], [u8; 3]); 3] = [
        ([0x1d, 0x4e, 0x89], [0x5d, 0xad, 0xe2]),
        ([0x8e, 0x2c, 0x1f], [0xf0, 0x9a, 0x3e]),
        ([0x1e, 0x6b, 0x3a], [0xb8, 0xd8, 0x5a]),
    ];
    let (a, b) = PALETTE[seed % PALETTE.len()];
    let row = W * 3; // 600 bytes: already a multiple of 4
    let size = 54 + row * W;
    let mut out = Vec::with_capacity(size as usize);
    out.extend_from_slice(b"BM");
    out.extend_from_slice(&size.to_le_bytes());
    out.extend_from_slice(&0u32.to_le_bytes());
    out.extend_from_slice(&54u32.to_le_bytes());
    out.extend_from_slice(&40u32.to_le_bytes());
    out.extend_from_slice(&W.to_le_bytes()); // width
    out.extend_from_slice(&W.to_le_bytes()); // height (bottom-up)
    out.extend_from_slice(&1u16.to_le_bytes());
    out.extend_from_slice(&24u16.to_le_bytes());
    out.extend_from_slice(&0u32.to_le_bytes()); // no compression
    out.extend_from_slice(&(row * W).to_le_bytes());
    out.extend_from_slice(&2835u32.to_le_bytes());
    out.extend_from_slice(&2835u32.to_le_bytes());
    out.extend_from_slice(&0u32.to_le_bytes());
    out.extend_from_slice(&0u32.to_le_bytes());
    let mix = |x: u8, y: u8, t: u32| -> u8 {
        let v = (u32::from(x) * (2 * W - t) + u32::from(y) * t) / (2 * W);
        u8::try_from(v).unwrap_or(u8::MAX)
    };
    let c = i64::from(W / 2);
    for y in 0..W {
        for x in 0..W {
            let t = x + y;
            let mut px = [mix(a[0], b[0], t), mix(a[1], b[1], t), mix(a[2], b[2], t)];
            let dx = i64::from(x) - c;
            let dy = i64::from(y) - c;
            let d2 = dx * dx + dy * dy;
            if (14 * 14..70 * 70).contains(&d2) {
                // The record: dark, with faint grooves.
                let g = if (d2 / 150) % 3 == 0 { 0x30 } else { 0x18 };
                px = [g, g, g];
            } else if (3 * 3..14 * 14).contains(&d2) {
                px = [b[0], b[1], b[2]];
            }
            // BMP is blue, green, red.
            out.extend_from_slice(&[px[2], px[1], px[0]]);
        }
    }
    out
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
    .enumerate()
    .map(|(i, (t, a, al, d))| Track {
        title: t.into(),
        artist: a.into(),
        album: al.into(),
        duration_ms: Some(d),
        // The third track has no picture, like a track a phone has none for.
        image_handle: (i < 2).then(|| format!("{}", 1_000_001 + i)),
    })
    .collect()
}

#[derive(Clone)]
pub struct SimPhone {
    state: Arc<Mutex<State>>,
    snap: watch::Sender<Snapshot>,
    art: Arc<watch::Sender<CoverArt>>,
    /// Each track's picture (None: the track has none).
    pictures: Arc<Vec<Option<Arc<Vec<u8>>>>>,
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
                connected: cfg.start_connected,
                paired: true,
            }],
            playlist: playlist(),
            index: 0,
            play: PlayState::Playing,
            position_ms: 0,
            at: now,
            window_gen: 0,
            reachable: true,
            connects: Vec::new(),
            disconnects: Vec::new(),
        };
        let pictures: Vec<Option<Arc<Vec<u8>>>> = state
            .playlist
            .iter()
            .enumerate()
            .map(|(i, t)| t.image_handle.as_ref().map(|_| Arc::new(sim_picture(i))))
            .collect();
        let first = state.snapshot(now);
        let art = Arc::new(watch::Sender::new(sim_art(
            &first,
            &pictures,
            &state.playlist,
        )));
        let snap = watch::Sender::new(first);
        SimPhone {
            state: Arc::new(Mutex::new(state)),
            snap,
            art,
            pictures: Arc::new(pictures),
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
        let snap = s.snapshot(now);
        let art = sim_art(&snap, &self.pictures, &s.playlist);
        self.snap.send_replace(snap);
        self.art.send_if_modified(|a| {
            let changed = *a != art;
            if changed {
                *a = art;
            }
            changed
        });
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

    /// A paired phone connects by itself, as a phone does when it comes
    /// into range: other connected phones stay connected (BlueZ allows it).
    pub fn connect_also(&self, address: &str) {
        self.with(|s, now| {
            for p in s
                .phones
                .iter_mut()
                .filter(|p| p.address == address && p.paired)
            {
                p.connected = true;
            }
            s.rebase(now);
        });
    }

    /// Adds a phone paired earlier (not connected).
    pub fn add_paired(&self, address: &str, name: &str) {
        self.with(|s, _| {
            s.phones.push(Phone {
                address: address.into(),
                name: name.into(),
                connected: false,
                paired: true,
            });
        });
    }

    /// The disconnections asked for so far, by address.
    pub fn disconnects(&self) -> Vec<String> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .disconnects
            .clone()
    }

    /// The phones answer a connection or not (out of range).
    pub fn set_reachable(&self, yes: bool) {
        self.with(|s, _| s.reachable = yes);
    }

    /// The connections asked for so far, by address.
    pub fn connects(&self) -> Vec<String> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .connects
            .clone()
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
                // As BlueZ does: the new phone connects and the old one stays
                // connected too (audio-manager keeps one).
                me.with(|s, now| {
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

    fn cover_art(&self) -> watch::Receiver<CoverArt> {
        self.art.subscribe()
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

    async fn connect(&self, address: &str) -> Result<(), String> {
        self.with(|s, _| {
            s.connects.push(address.to_string());
            if !s.adapter_up {
                return Err("simulated: Bluetooth is off".to_string());
            }
            if !s.phones.iter().any(|p| p.paired && p.address == address) {
                return Err("not a paired phone".to_string());
            }
            Ok(())
        })?;
        tokio::time::sleep(self.cfg.connect_takes).await;
        self.with(|s, now| {
            if !s.reachable {
                return Err("simulated: the phone didn't answer (out of range)".to_string());
            }
            for p in &mut s.phones {
                p.connected = p.address == address;
            }
            s.rebase(now);
            Ok(())
        })
    }

    async fn remove(&self, address: &str) -> Result<(), String> {
        self.with(|s, _| {
            let before = s.phones.len();
            s.phones.retain(|p| p.address != address);
            if s.phones.len() == before {
                Err("not a known phone".to_string())
            } else {
                Ok(())
            }
        })
    }

    async fn disconnect(&self, address: &str) -> Result<(), String> {
        // As BlueZ: the phone is still reported connected for a moment.
        self.with(|s, _| s.disconnects.push(address.to_string()));
        tokio::time::sleep(self.cfg.connect_takes).await;
        self.with(|s, _| {
            for p in s.phones.iter_mut().filter(|p| p.address == address) {
                p.connected = false;
            }
            Ok(())
        })
    }
}
