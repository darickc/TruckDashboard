//! audio-manager's core: follows the Bluetooth backend, runs the pairing
//! window and the pairing agent's questions, connects paired phones (the
//! driver's choice, or the last phone again by itself), keeps the speaker
//! settings and the master volume (ADR-0043), follows the connected phone's
//! calls (ADR-0045), and publishes what the dashboard shows
//! (`f250.audio.v1.WatchAudioResponse`) on each change and once a second.
//!
//! Honesty rules (CLAUDE.md rule 4): the track is published only while its
//! phone is connected; nothing is current once Bluetooth is gone.

use std::collections::{BTreeSet, HashMap};
use std::path::PathBuf;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::Duration;

use f250_proto::audio::v1 as pb;
use tokio::sync::{mpsc, oneshot, watch};
use tokio::time::Instant;

use crate::backend::Bluetooth;
use crate::call_audio::CallAudio;
use crate::calls::{self, Availability, Call, CallSnapshot, CallState};
use crate::dsp::{self, Limits, Mix, Settings};
use crate::model::{Adapter, AgentAsk, AgentRequest, Command, Picture, PlayState, Snapshot};
use crate::pairing::{self, Action, Outcome, State, Window};
use crate::phonebook::{self, BookState, Phonebook, RecentKind};
use crate::prompts::{Act, PromptPause};
use crate::ring::Ringer;
use crate::runner::{Dsp, DspState};
use crate::telephony::Telephony;
use crate::voice::{Voice, clean_prompt};
use crate::volume::{self, Change, Volume, VolumeLimits};

/// The volume is saved this long after its last change, so a knob turn
/// doesn't write the SD card at every detent (ADR-0043 decision 4).
pub const SAVE_VOLUME_AFTER: Duration = Duration::from_secs(2);

#[derive(Debug, Clone)]
pub struct Config {
    pub pairing: pairing::Config,
    /// The name phones see.
    pub name: String,
    pub limits: Limits,
    pub defaults: Settings,
    /// Where the driver's speaker settings are kept; None: only in memory.
    pub settings_file: Option<PathBuf>,
    pub simulated: bool,
    /// The music resumes this long after the last prompt (an example).
    pub prompt_hold: Duration,
    /// Where the address of the phone connected last is kept; None: only in
    /// memory.
    pub last_phone_file: Option<PathBuf>,
    pub reconnect: Reconnect,
    /// The master volume's steps and caps (examples, ADR-0043).
    pub volume: VolumeLimits,
    /// Where the level is kept; None: only in memory.
    pub volume_file: Option<PathBuf>,
    /// A call that rings without the phone's own ring tone this long is
    /// rung through the speakers (an example: the phone's in-band ring may
    /// take a moment to start).
    pub ring_after: Duration,
}

/// Reconnecting the last phone by itself: at start, when Bluetooth comes
/// back, and after the link drops, an attempt every `every` until a phone is
/// connected or `window` has passed. Examples (configuration).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Reconnect {
    pub every: Duration,
    /// Zero: never by itself.
    pub window: Duration,
}

impl Reconnect {
    pub const OFF: Reconnect = Reconnect {
        every: Duration::from_secs(20),
        window: Duration::ZERO,
    };
}

/// A connection being tried.
#[derive(Debug, Clone)]
struct Attempt {
    address: String,
    name: String,
    automatic: bool,
}

/// A Bluetooth address as BlueZ writes it (AA:BB:CC:DD:EE:FF).
pub fn is_address(a: &str) -> bool {
    a.len() == 17
        && a.split(':').count() == 6
        && a.split(':')
            .all(|p| p.len() == 2 && p.chars().all(|c| c.is_ascii_hexdigit()))
}

/// Reads the last phone's address; None (with why, when it isn't just
/// missing) when there isn't a usable one.
pub fn load_last_phone(path: Option<&std::path::Path>) -> (Option<String>, Option<String>) {
    let Some(path) = path else {
        return (None, None);
    };
    match std::fs::read_to_string(path) {
        Ok(text) => {
            let a = text.trim().to_ascii_uppercase();
            if is_address(&a) {
                (Some(a), None)
            } else {
                (
                    None,
                    Some(format!(
                        "{}: not a Bluetooth address; ignored",
                        path.display()
                    )),
                )
            }
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => (None, None),
        Err(e) => (None, Some(format!("{}: {e}", path.display()))),
    }
}

struct Inner {
    window: Window,
    replies: HashMap<u64, oneshot::Sender<bool>>,
    settings: Settings,
    discoverable: bool,
    /// Phones paired as of the last snapshot.
    paired: BTreeSet<String>,
    /// The first snapshot has been seen (pairings in it aren't new).
    seen: bool,
    prompts: PromptPause,
    /// The prompt being said, to cut it off.
    saying: Option<tokio::task::AbortHandle>,
    /// Counts prompts, so an old one's end doesn't end a newer one.
    prompt_gen: u64,
    prompt_detail: String,
    /// The phone connected most recently (its address).
    last_phone: Option<String>,
    attempt: Option<Attempt>,
    /// How the last attempt went, for the screen.
    connect_detail: String,
    /// Reconnecting by itself until then.
    auto_until: Option<Instant>,
    next_auto: Instant,
    /// As of the last snapshot.
    had_phone: bool,
    adapter_ready: bool,
    /// The connected phones, in the order they connected (the newest
    /// last): one phone at a time, the newest kept.
    order: Vec<String>,
    /// Phones asked to disconnect and not gone yet.
    disconnecting: BTreeSet<String>,
    /// Phones the driver disconnected: not reconnected by itself until they
    /// connect again (in memory: after a restart they are again).
    held: BTreeSet<String>,
    volume: Volume,
    /// A volume change not saved yet: (the level, who changed it last).
    volume_unsaved: Option<String>,
    /// Calls seen, by object path: the id the dashboard names them by, and
    /// since when each is active.
    calls: HashMap<String, CallMemo>,
    next_call_id: u64,
    /// The phone in use has a call (any state but ended).
    in_call: bool,
    mic_muted: bool,
    /// The music paused for a call, resumed after it (as for prompts).
    call_pause: PromptPause,
    /// The ring tone playing through the speakers.
    ring: Option<tokio::task::AbortHandle>,
    /// The call ringing on the phone in use, and since when.
    incoming: Option<(u64, Instant)>,
    /// The phone whose lists were asked for last (ADR-0045 phase 2).
    book_for: Option<String>,
}

#[derive(Debug, Clone, Copy)]
struct CallMemo {
    id: u64,
    state: CallState,
    active_since: Option<Instant>,
}

pub struct Manager {
    cfg: Config,
    bt: Arc<dyn Bluetooth>,
    dsp: Arc<dyn Dsp>,
    voice: Arc<dyn Voice>,
    tel: Arc<dyn Telephony>,
    ringer: Arc<dyn Ringer>,
    book: Arc<dyn Phonebook>,
    call_audio: Arc<dyn CallAudio>,
    inner: Mutex<Inner>,
    out: watch::Sender<pb::WatchAudioResponse>,
    /// Bumped by the main loop (systemd watchdog).
    pub heartbeat: f250_sd_notify::Heartbeat,
    /// Shutting down: watch streams end (at their next heartbeat), so the
    /// server's graceful shutdown doesn't wait on them forever.
    stopping: std::sync::atomic::AtomicBool,
    /// Settings and volume reach the filter-chain one at a time, each with
    /// the other's latest value.
    applying: tokio::sync::Mutex<()>,
    /// Bumped at each volume change; the volume task applies the newest.
    volume_changed: watch::Sender<u64>,
}

fn play_state(s: PlayState) -> pb::PlayState {
    match s {
        PlayState::Stopped => pb::PlayState::Stopped,
        PlayState::Playing => pb::PlayState::Playing,
        PlayState::Paused => pb::PlayState::Paused,
        PlayState::ForwardSeek => pb::PlayState::ForwardSeek,
        PlayState::ReverseSeek => pb::PlayState::ReverseSeek,
        PlayState::Error => pb::PlayState::Error,
        PlayState::Unknown => pb::PlayState::Unspecified,
    }
}

pub fn settings_pb(s: &Settings) -> pb::SpeakerSettings {
    pb::SpeakerSettings {
        fader: s.fader,
        balance: s.balance,
        sub_level_db: s.sub_level_db,
        crossover_hz: s.crossover_hz,
    }
}

pub fn settings_from_pb(s: &pb::SpeakerSettings) -> Settings {
    Settings {
        fader: s.fader,
        balance: s.balance,
        sub_level_db: s.sub_level_db,
        crossover_hz: s.crossover_hz,
    }
}

/// The saved volume level, or None (and why, when the file is damaged).
pub fn load_volume(path: Option<&std::path::Path>) -> (Option<u32>, Option<String>) {
    let Some(path) = path else {
        return (None, None);
    };
    match std::fs::read_to_string(path) {
        Ok(text) => match volume::parse_saved(&text) {
            Ok(n) => (Some(n), None),
            Err(e) => (None, Some(format!("{}: {e}", path.display()))),
        },
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => (None, None),
        Err(e) => (None, Some(format!("{}: {e}", path.display()))),
    }
}

/// Reads the settings file; the defaults (with why) when it is missing or
/// damaged.
pub fn load_settings(cfg: &Config) -> (Settings, Option<String>) {
    let Some(path) = &cfg.settings_file else {
        return (cfg.defaults, None);
    };
    match std::fs::read_to_string(path) {
        Ok(text) => match dsp::parse_settings(&text, &cfg.limits, &cfg.defaults) {
            Ok(s) => (s, None),
            Err(e) => (
                cfg.defaults,
                Some(format!("{}: {e}; using the defaults", path.display())),
            ),
        },
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => (cfg.defaults, None),
        Err(e) => (
            cfg.defaults,
            Some(format!("{}: {e}; using the defaults", path.display())),
        ),
    }
}

impl Manager {
    // One argument per backend: main picks each (real, simulated or off)
    // and the tests swap them one at a time.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        cfg: Config,
        bt: Arc<dyn Bluetooth>,
        dsp: Arc<dyn Dsp>,
        voice: Arc<dyn Voice>,
        tel: Arc<dyn Telephony>,
        ringer: Arc<dyn Ringer>,
        book: Arc<dyn Phonebook>,
        call_audio: Arc<dyn CallAudio>,
    ) -> Arc<Manager> {
        let (settings, problem) = load_settings(&cfg);
        if let Some(p) = problem {
            eprintln!("[audio] speaker settings: {p}");
        }
        let (last_phone, problem) = load_last_phone(cfg.last_phone_file.as_deref());
        if let Some(p) = problem {
            eprintln!("[audio] last phone: {p}");
        }
        let (saved, problem) = load_volume(cfg.volume_file.as_deref());
        if let Some(p) = problem {
            eprintln!("[audio] volume: {p}; starting at {}", cfg.volume.start_max);
        }
        let volume = volume::at_start(&cfg.volume, saved);
        if saved.is_some_and(|n| n > volume.level) {
            eprintln!(
                "[audio] volume: saved {}, starting at {} (the start maximum)",
                saved.unwrap_or(0),
                volume.level
            );
        }
        Arc::new(Manager {
            inner: Mutex::new(Inner {
                window: Window::new(cfg.pairing),
                replies: HashMap::new(),
                settings,
                discoverable: false,
                paired: BTreeSet::new(),
                seen: false,
                prompts: PromptPause::new(cfg.prompt_hold),
                saying: None,
                prompt_gen: 0,
                prompt_detail: String::new(),
                last_phone,
                attempt: None,
                connect_detail: String::new(),
                auto_until: None,
                next_auto: Instant::now(),
                had_phone: false,
                adapter_ready: false,
                order: Vec::new(),
                disconnecting: BTreeSet::new(),
                held: BTreeSet::new(),
                volume,
                volume_unsaved: None,
                calls: HashMap::new(),
                next_call_id: 1,
                in_call: false,
                mic_muted: false,
                call_pause: PromptPause::new(cfg.prompt_hold),
                ring: None,
                incoming: None,
                book_for: None,
            }),
            cfg,
            bt,
            dsp,
            voice,
            tel,
            ringer,
            book,
            call_audio,
            out: watch::Sender::new(pb::WatchAudioResponse::default()),
            heartbeat: f250_sd_notify::Heartbeat::new(),
            stopping: std::sync::atomic::AtomicBool::new(false),
            applying: tokio::sync::Mutex::new(()),
            volume_changed: watch::Sender::new(0),
        })
    }

    fn lock(&self) -> MutexGuard<'_, Inner> {
        self.inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    pub fn watch(&self) -> watch::Receiver<pb::WatchAudioResponse> {
        self.out.subscribe()
    }

    /// Starts shutting down: watch streams end within a second. A volume
    /// change not saved yet is saved now.
    pub fn stop(&self) {
        self.save_volume();
        self.stopping
            .store(true, std::sync::atomic::Ordering::Relaxed);
        self.publish();
    }

    pub fn stopping(&self) -> bool {
        self.stopping.load(std::sync::atomic::Ordering::Relaxed)
    }

    pub fn settings(&self) -> Settings {
        self.lock().settings
    }

    pub fn volume(&self) -> Volume {
        self.lock().volume
    }

    /// What the filter-chain should run with now.
    fn mix(&self) -> Mix {
        let inner = self.lock();
        Mix {
            settings: inner.settings,
            master: volume::gain(&self.cfg.volume, &inner.volume),
        }
    }

    /// Sends the latest settings and volume to the filter-chain, one call at
    /// a time.
    async fn apply_mix(&self) -> Result<String, String> {
        let _one = self.applying.lock().await;
        let r = self.dsp.apply(self.mix()).await;
        if let Err(e) = &r {
            eprintln!("[audio] speakers' filter-chain: {e}");
        }
        r
    }

    /// Changes the volume (the dashboard, the knob): applied by the volume
    /// task, the newest value only. Returns the new volume and a note when
    /// it isn't what was asked.
    pub fn set_volume(&self, c: Change, source: &str) -> (Volume, Option<String>) {
        let (v, note, changed, was_muted) = {
            let mut inner = self.lock();
            let was_muted = inner.volume.muted;
            let (v, note) = volume::apply(&self.cfg.volume, inner.volume, c);
            let changed = v != inner.volume;
            if changed {
                if v.level != inner.volume.level {
                    inner.volume_unsaved = Some(source.to_string());
                }
                inner.volume = v;
            }
            (v, note, changed, was_muted)
        };
        if changed {
            // Mute is logged here, the level when it's saved.
            if v.muted != was_muted {
                eprintln!(
                    "[audio] {source}: {}",
                    if v.muted { "muted" } else { "unmuted" }
                );
            }
            self.volume_changed.send_modify(|n| *n = n.wrapping_add(1));
            self.publish();
        }
        (v, note)
    }

    /// Writes the level if a change is waiting (ADR-0043 decision 4).
    pub fn save_volume(&self) {
        let (level, source) = {
            let mut inner = self.lock();
            let Some(source) = inner.volume_unsaved.take() else {
                return;
            };
            (inner.volume.level, source)
        };
        let db = volume::level_db(&self.cfg.volume, level)
            .map_or("silent".to_string(), |d| format!("{d:.0} dB"));
        eprintln!("[audio] {source}: volume {level} ({db})");
        let Some(path) = &self.cfg.volume_file else {
            return;
        };
        let tmp = path.with_extension("json.new");
        if let Err(e) = std::fs::write(&tmp, volume::saved_json(level))
            .and_then(|()| std::fs::rename(&tmp, path))
        {
            eprintln!("[audio] volume: can't save {}: {e}", path.display());
        }
    }

    /// Applies volume changes as they come, the newest only, and saves the
    /// level once the changes stop.
    async fn volume_task(self: Arc<Self>) {
        let mut changed = self.volume_changed.subscribe();
        let mut save_at: Option<Instant> = None;
        loop {
            tokio::select! {
                r = changed.changed() => {
                    if r.is_err() { return; }
                    changed.borrow_and_update();
                    let _ = self.apply_mix().await;
                    self.publish();
                    save_at = Some(Instant::now() + SAVE_VOLUME_AFTER);
                }
                () = async {
                    match save_at {
                        Some(t) => tokio::time::sleep_until(t).await,
                        None => std::future::pending().await,
                    }
                } => {
                    save_at = None;
                    self.save_volume();
                }
            }
        }
    }

    /// The main loop: until `agent` closes.
    pub async fn run(self: Arc<Self>, mut agent: mpsc::Receiver<AgentRequest>) {
        let mut snap = self.bt.snapshot();
        let mut art = self.bt.cover_art();
        let mut dsp_state = self.dsp.state();
        let mut calls = self.tel.calls();
        let mut book = self.book.book();
        self.dsp.start(self.mix()).await;
        tokio::spawn(Arc::clone(&self).volume_task());
        self.on_snapshot();
        self.follow_book();
        let mut tick = tokio::time::interval(Duration::from_secs(1));
        tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        loop {
            tokio::select! {
                r = snap.changed() => {
                    if r.is_err() { return; }
                    self.on_snapshot();
                    self.follow_book();
                }
                r = book.changed() => {
                    if r.is_err() { return; }
                    self.publish();
                }
                r = dsp_state.changed() => {
                    if r.is_err() { return; }
                    self.publish();
                }
                r = art.changed() => {
                    if r.is_err() { return; }
                    self.publish();
                }
                r = calls.changed() => {
                    if r.is_err() { return; }
                    self.on_calls();
                }
                req = agent.recv() => match req {
                    Some(req) => self.on_agent(req),
                    None => return,
                },
                _ = tick.tick() => self.on_tick(),
            }
            self.heartbeat.beat();
        }
    }

    /// Carries out an outcome: refuses a dropped question, and sets the
    /// adapter (on its own task; the answer comes back to the window).
    fn carry_out(self: &Arc<Self>, inner: &mut Inner, out: Outcome) {
        if let Some(id) = out.dropped
            && let Some(tx) = inner.replies.remove(&id)
        {
            let _ = tx.send(false);
        }
        if let Some(Action::Adapter { on, timeout_s }) = out.action {
            let me = Arc::clone(self);
            tokio::spawn(async move {
                let r = me.bt.set_pairing(on, timeout_s).await;
                if let Err(e) = &r {
                    eprintln!("[audio] pairing window: setting discoverable={on}: {e}");
                }
                {
                    let mut inner = me.lock();
                    let out = inner.window.adapter_done(Instant::now(), on, r);
                    me.carry_out(&mut inner, out);
                }
                me.publish();
            });
        }
    }

    fn on_snapshot(self: &Arc<Self>) {
        let s = self.bt.snapshot().borrow().clone();
        let now = Instant::now();
        {
            let mut inner = self.lock();
            let inner = &mut *inner;
            match &s.adapter {
                Adapter::Ready { discoverable, .. } => {
                    inner.window.adapter_ready();
                    if inner.discoverable && !discoverable {
                        let out = inner.window.discoverable_ended();
                        self.carry_out(inner, out);
                    }
                    inner.discoverable = *discoverable;
                }
                Adapter::Unavailable(_) => {
                    let out = inner.window.adapter_lost();
                    self.carry_out(inner, out);
                    inner.discoverable = false;
                    inner.prompts.forget();
                }
            }
            let paired: BTreeSet<String> = s
                .phones
                .iter()
                .filter(|p| p.paired)
                .map(|p| p.address.clone())
                .collect();
            if inner.seen {
                for p in s.phones.iter().filter(|p| p.paired) {
                    if inner.paired.contains(&p.address) {
                        continue;
                    }
                    if matches!(inner.window.state(), State::Open | State::Opening) {
                        eprintln!(
                            "[audio] paired with {} ({}) in the window",
                            p.name, p.address
                        );
                        let out = inner.window.paired(now, &p.name);
                        self.carry_out(inner, out);
                        let (me, addr) = (Arc::clone(self), p.address.clone());
                        tokio::spawn(async move {
                            if let Err(e) = me.bt.trust(&addr).await {
                                eprintln!("[audio] trusting {addr}: {e}");
                            }
                        });
                    }
                }
            }
            inner.paired = paired;
            self.follow_order(inner, &s);
            inner.seen = true;
            self.one_phone(inner, &s);
            self.follow_connection(inner, &s, now);
            // A phone gone (or another one) isn't resumed by us later.
            if s.player.is_none() {
                inner.prompts.forget();
                inner.call_pause.forget();
            }
            let t = self.tel.calls().borrow().clone();
            self.follow_calls(inner, &s, &t, now);
        }
        self.publish();
    }

    fn on_agent(self: &Arc<Self>, req: AgentRequest) {
        let now = Instant::now();
        {
            let mut inner = self.lock();
            let passkey = match req.ask {
                AgentAsk::Confirm { passkey } => Some(passkey),
                AgentAsk::Authorize => None,
            };
            match inner.window.ask(now, &req.address, &req.name, passkey) {
                Ok(id) => {
                    eprintln!(
                        "[audio] {} ({}) asks to pair: waiting for the driver",
                        req.name, req.address
                    );
                    inner.replies.insert(id, req.reply);
                }
                Err(why) => {
                    eprintln!(
                        "[audio] {} ({}) asked to pair: refused, {why}",
                        req.name, req.address
                    );
                    let _ = req.reply.send(false);
                }
            }
        }
        self.publish();
    }

    fn on_tick(self: &Arc<Self>) {
        let now = Instant::now();
        {
            let mut inner = self.lock();
            let inner = &mut *inner;
            // The phone or BlueZ gave up on a question (Agent1.Cancel).
            let gone: Vec<u64> = inner
                .replies
                .iter()
                .filter(|(_, tx)| tx.is_closed())
                .map(|(id, _)| *id)
                .collect();
            for id in gone {
                inner.replies.remove(&id);
                inner.window.cancelled(id);
            }
            let out = inner.window.tick(now);
            self.carry_out(inner, out);
            let snap = self.bt.snapshot().borrow().clone();
            self.reconnect_tick(inner, &snap, now);
            let t = self.tel.calls().borrow().clone();
            self.ring_check(inner, &snap, &t, now);
            let paused = self
                .bt
                .snapshot()
                .borrow()
                .player
                .as_ref()
                .is_some_and(|p| p.state == PlayState::Paused);
            // Nothing resumes the music during a call.
            if !inner.in_call {
                if let Some(act) = inner.prompts.tick(now, paused) {
                    self.send_act(act);
                }
                if let Some(act) = inner.call_pause.tick(now, paused) {
                    self.send_act(act);
                }
            }
        }
        self.publish();
    }

    /// Pauses or plays the phone for prompts, on its own task.
    fn send_act(self: &Arc<Self>, act: Act) {
        let me = Arc::clone(self);
        let cmd = match act {
            Act::Pause => Command::Pause,
            Act::Play => Command::Play,
        };
        eprintln!("[audio] {} the phone's music", cmd.method());
        tokio::spawn(async move {
            if let Err(e) = me.bt.control(cmd).await {
                eprintln!("[audio] {} the phone's music: {e}", cmd.method());
            }
        });
    }

    // ---- connecting phones ------------------------------------------------------

    /// Keeps the order the connected phones connected in. Phones already
    /// connected at the first snapshot: the last phone kept, else the one
    /// with the player, else the first.
    fn follow_order(&self, inner: &mut Inner, s: &Snapshot) {
        let connected: Vec<&crate::model::Phone> =
            s.phones.iter().filter(|p| p.connected).collect();
        inner
            .order
            .retain(|a| connected.iter().any(|p| &p.address == a));
        inner
            .disconnecting
            .retain(|a| connected.iter().any(|p| &p.address == a));
        let mut new: Vec<String> = connected
            .iter()
            .map(|p| p.address.clone())
            .filter(|a| !inner.order.contains(a))
            .collect();
        if !inner.seen && new.len() > 1 {
            let player = s.player.as_ref().map(|pl| pl.address.clone());
            let rank = |a: &String| {
                if inner.last_phone.as_ref() == Some(a) {
                    2
                } else if player.as_ref() == Some(a) {
                    1
                } else {
                    0
                }
            };
            new.sort_by_key(rank);
        }
        // A phone that has just connected (it wasn't before) is no longer
        // held back by the driver's Disconnect. Not on any snapshot that still
        // shows it connected: BlueZ reports it so for a moment after the
        // Disconnect is sent (bench-log 2026-11-12).
        for a in &new {
            inner.held.remove(a);
        }
        inner.order.extend(new);
    }

    /// The phone in use: the connected phone that connected last.
    fn current(inner: &Inner, s: &Snapshot) -> Option<crate::model::Phone> {
        inner
            .order
            .iter()
            .rev()
            .find_map(|a| s.phones.iter().find(|p| p.connected && &p.address == a))
            .or_else(|| s.connected_phone())
            .cloned()
    }

    /// One phone at a time (ADR-0039 decision 3a): when another phone
    /// connects (a phone paired in the window, one coming into range), the
    /// newest is kept and the others are disconnected. Not while the driver's
    /// own connection runs: it disconnects the others itself.
    fn one_phone(self: &Arc<Self>, inner: &mut Inner, s: &Snapshot) {
        if inner.attempt.as_ref().is_some_and(|a| !a.automatic) {
            return;
        }
        let Some(keep) = Self::current(inner, s) else {
            return;
        };
        let others: Vec<crate::model::Phone> = s
            .phones
            .iter()
            .filter(|p| p.connected && p.address != keep.address)
            .filter(|p| !inner.disconnecting.contains(&p.address))
            .cloned()
            .collect();
        for p in others {
            eprintln!(
                "[audio] {} ({}) is the phone in use: disconnecting {} ({}), one phone at a time",
                keep.name, keep.address, p.name, p.address
            );
            inner.disconnecting.insert(p.address.clone());
            let me = Arc::clone(self);
            tokio::spawn(async move {
                if let Err(e) = me.bt.disconnect(&p.address).await {
                    eprintln!("[audio] disconnecting {} ({}): {e}", p.name, p.address);
                    me.lock().disconnecting.remove(&p.address);
                }
            });
        }
    }

    /// Keeps the last phone up to date, and starts reconnecting by itself at
    /// start, when Bluetooth comes back, and when the link drops.
    fn follow_connection(&self, inner: &mut Inner, s: &Snapshot, now: Instant) {
        let ready = matches!(s.adapter, Adapter::Ready { .. });
        let connected = Self::current(inner, s);
        if let Some(p) = &connected {
            if inner.last_phone.as_deref() != Some(p.address.as_str()) {
                inner.last_phone = Some(p.address.clone());
                self.save_last_phone(&p.address);
            }
            if inner.auto_until.take().is_some() {
                eprintln!("[audio] {} ({}) connected", p.name, p.address);
            }
            // A phone has just connected: an older failure is stale.
            if !inner.had_phone && inner.attempt.is_none() {
                inner.connect_detail.clear();
            }
        } else if ready
            && (!inner.adapter_ready || inner.had_phone)
            && !self.cfg.reconnect.window.is_zero()
            && let Some(last) = inner.last_phone.clone()
            && !inner.held.contains(&last)
        {
            inner.auto_until = Some(now + self.cfg.reconnect.window);
            inner.next_auto = now;
            eprintln!(
                "[audio] no phone connected: trying {last} every {} s for {} s",
                self.cfg.reconnect.every.as_secs(),
                self.cfg.reconnect.window.as_secs()
            );
        }
        if !ready {
            inner.auto_until = None;
        }
        inner.had_phone = connected.is_some();
        inner.adapter_ready = ready;
    }

    fn save_last_phone(&self, address: &str) {
        let Some(path) = &self.cfg.last_phone_file else {
            return;
        };
        let tmp = path.with_extension("new");
        if let Err(e) =
            std::fs::write(&tmp, format!("{address}\n")).and_then(|()| std::fs::rename(&tmp, path))
        {
            eprintln!("[audio] last phone not saved ({}): {e}", path.display());
        }
    }

    /// Once a second: the next automatic attempt, or giving up.
    fn reconnect_tick(self: &Arc<Self>, inner: &mut Inner, s: &Snapshot, now: Instant) {
        let Some(until) = inner.auto_until else {
            return;
        };
        let last = inner.last_phone.clone().unwrap_or_default();
        let phone = s
            .phones
            .iter()
            .find(|p| p.paired && p.address == last)
            .cloned();
        let Some(phone) = phone else {
            // Not paired any more (removed on the phone or in BlueZ).
            inner.auto_until = None;
            return;
        };
        if now >= until {
            inner.auto_until = None;
            if s.connected_phone().is_none() && inner.attempt.is_none() {
                inner.connect_detail = format!(
                    "Stopped trying to reach {} after {} min. Tap it to connect.",
                    phone.name,
                    self.cfg.reconnect.window.as_secs().div_ceil(60)
                );
                eprintln!("[audio] stopped trying to reconnect {}", phone.address);
            }
            return;
        }
        let window_closed = matches!(inner.window.state(), State::Closed | State::Failed);
        if inner.attempt.is_some()
            || now < inner.next_auto
            || s.connected_phone().is_some()
            || !window_closed
        {
            return;
        }
        inner.next_auto = now + self.cfg.reconnect.every;
        self.begin_connect(inner, phone.address, phone.name, true);
    }

    /// Starts a connection on its own task; the outcome comes back to
    /// `connect_detail`.
    fn begin_connect(
        self: &Arc<Self>,
        inner: &mut Inner,
        address: String,
        name: String,
        automatic: bool,
    ) {
        inner.attempt = Some(Attempt {
            address: address.clone(),
            name: name.clone(),
            automatic,
        });
        inner.connect_detail.clear();
        eprintln!(
            "[audio] connecting {name} ({address}){}",
            if automatic { " by itself" } else { "" }
        );
        let me = Arc::clone(self);
        tokio::spawn(async move {
            let r = me.bt.connect(&address).await;
            let connected = me
                .bt
                .snapshot()
                .borrow()
                .phones
                .iter()
                .any(|p| p.connected && p.address == address);
            {
                let mut inner = me.lock();
                inner.attempt = None;
                inner.connect_detail = match (&r, connected) {
                    (_, true) | (Ok(()), _) => String::new(),
                    (Err(e), false) if automatic && inner.auto_until.is_some() => format!(
                        "Couldn't reach {name} ({e}); trying again in {} s.",
                        me.cfg.reconnect.every.as_secs()
                    ),
                    (Err(e), false) => format!("Couldn't connect to {name}: {e}."),
                };
            }
            match &r {
                Ok(()) => eprintln!("[audio] connected {name} ({address})"),
                Err(e) => eprintln!("[audio] connecting {name} ({address}): {e}"),
            }
            me.publish();
        });
    }

    /// The driver chose a paired phone. Ok: what is happening, for the
    /// screen.
    pub fn connect_phone(self: &Arc<Self>, address: &str, source: &str) -> Result<String, String> {
        let s = self.bt.snapshot().borrow().clone();
        if !matches!(s.adapter, Adapter::Ready { .. }) {
            return Err("Bluetooth is unavailable.".into());
        }
        let Some(phone) = s
            .phones
            .iter()
            .find(|p| p.paired && p.address == address)
            .cloned()
        else {
            return Err("That phone isn't paired.".into());
        };
        if phone.connected {
            return Err(format!("{} is already connected.", phone.name));
        }
        let msg = {
            let mut inner = self.lock();
            if let Some(a) = &inner.attempt {
                return Err(format!("Already connecting to {}.", a.name));
            }
            // The driver's choice replaces trying the last phone by itself.
            inner.auto_until = None;
            eprintln!(
                "[audio] {source}: connect {} ({})",
                phone.name, phone.address
            );
            self.begin_connect(&mut inner, phone.address.clone(), phone.name.clone(), false);
            format!("Connecting to {}…", phone.name)
        };
        self.publish();
        Ok(msg)
    }

    /// The driver disconnects the connected phone. Ok: what is happening.
    pub fn disconnect_phone(
        self: &Arc<Self>,
        address: &str,
        source: &str,
    ) -> Result<String, String> {
        let s = self.bt.snapshot().borrow().clone();
        if !matches!(s.adapter, Adapter::Ready { .. }) {
            return Err("Bluetooth is unavailable.".into());
        }
        let Some(phone) = s.phones.iter().find(|p| p.address == address).cloned() else {
            return Err("That phone isn't paired.".into());
        };
        if !phone.connected {
            return Err(format!("{} isn't connected.", phone.name));
        }
        {
            let mut inner = self.lock();
            inner.held.insert(phone.address.clone());
            inner.disconnecting.insert(phone.address.clone());
            inner.auto_until = None;
            inner.connect_detail.clear();
        }
        eprintln!(
            "[audio] {source}: disconnect {} ({})",
            phone.name, phone.address
        );
        let msg = format!("Disconnecting {}…", phone.name);
        let me = Arc::clone(self);
        tokio::spawn(async move {
            if let Err(e) = me.bt.disconnect(&phone.address).await {
                eprintln!(
                    "[audio] disconnecting {} ({}): {e}",
                    phone.name, phone.address
                );
                let mut inner = me.lock();
                inner.disconnecting.remove(&phone.address);
                inner.held.remove(&phone.address);
                inner.connect_detail = format!("Couldn't disconnect {}: {e}.", phone.name);
            }
            me.publish();
        });
        self.publish();
        Ok(msg)
    }

    /// The driver forgets a paired phone (BlueZ removes the pairing). Ok:
    /// what is happening.
    pub fn forget_phone(self: &Arc<Self>, address: &str, source: &str) -> Result<String, String> {
        let s = self.bt.snapshot().borrow().clone();
        if !matches!(s.adapter, Adapter::Ready { .. }) {
            return Err("Bluetooth is unavailable.".into());
        }
        let Some(phone) = s.phones.iter().find(|p| p.address == address).cloned() else {
            return Err("That phone isn't paired.".into());
        };
        {
            let mut inner = self.lock();
            if inner
                .attempt
                .as_ref()
                .is_some_and(|a| a.address == phone.address)
            {
                return Err(format!(
                    "Connecting to {}: wait for it to finish.",
                    phone.name
                ));
            }
            inner.held.remove(&phone.address);
            if inner.last_phone.as_deref() == Some(phone.address.as_str()) {
                inner.last_phone = None;
                inner.auto_until = None;
                if let Some(path) = &self.cfg.last_phone_file
                    && let Err(e) = std::fs::remove_file(path)
                    && e.kind() != std::io::ErrorKind::NotFound
                {
                    eprintln!("[audio] last phone not cleared ({}): {e}", path.display());
                }
            }
            inner.connect_detail.clear();
        }
        eprintln!(
            "[audio] {source}: forget {} ({})",
            phone.name, phone.address
        );
        let msg = format!("Deleting {}…", phone.name);
        let me = Arc::clone(self);
        tokio::spawn(async move {
            let r = me.bt.remove(&phone.address).await;
            {
                let mut inner = me.lock();
                inner.connect_detail = match &r {
                    Ok(()) => format!("Deleted {}. Pair it again to use it.", phone.name),
                    Err(e) => format!("Couldn't delete {}: {e}.", phone.name),
                };
            }
            match &r {
                Ok(()) => eprintln!("[audio] forgot {} ({})", phone.name, phone.address),
                Err(e) => eprintln!("[audio] forgetting {} ({}): {e}", phone.name, phone.address),
            }
            me.publish();
        });
        self.publish();
        Ok(msg)
    }

    // ---- spoken prompts (navigation) -----------------------------------------

    /// Says `text`, cutting off any prompt still being said. Returns at once.
    pub fn speak(self: &Arc<Self>, text: &str, source: &str) -> Result<(), String> {
        let text = clean_prompt(text);
        if text.is_empty() {
            return Err("Nothing to say.".into());
        }
        self.voice.available()?;
        if self.lock().in_call {
            eprintln!("[audio] {source}: prompt skipped during a call: {text:?}");
            return Err("A call is in progress: the prompt is skipped.".into());
        }
        let playing = self
            .bt
            .snapshot()
            .borrow()
            .player
            .as_ref()
            .is_some_and(|p| p.state == PlayState::Playing);
        let generation = {
            let mut inner = self.lock();
            if let Some(old) = inner.saying.take() {
                old.abort();
            }
            inner.prompt_gen += 1;
            if let Some(act) = inner.prompts.start(playing) {
                self.send_act(act);
            }
            inner.prompt_detail = String::new();
            inner.prompt_gen
        };
        eprintln!("[audio] {source}: saying {text:?}");
        let me = Arc::clone(self);
        let task = tokio::spawn(async move {
            let r = me.voice.say(&text).await;
            {
                let mut inner = me.lock();
                if inner.prompt_gen != generation {
                    return;
                }
                inner.saying = None;
                inner.prompts.finished(Instant::now());
                if let Err(e) = r {
                    eprintln!("[audio] prompt not said: {e}");
                    inner.prompt_detail = format!("The last prompt wasn't said: {e}");
                }
            }
            me.publish();
        });
        {
            let mut inner = self.lock();
            if inner.prompt_gen == generation && inner.prompts.speaking() {
                inner.saying = Some(task.abort_handle());
            }
        }
        self.publish();
        Ok(())
    }

    /// Stops the prompt being said. False: nothing was.
    pub fn stop_speaking(self: &Arc<Self>, source: &str) -> bool {
        let was = {
            let mut inner = self.lock();
            let was = inner.prompts.speaking();
            if let Some(t) = inner.saying.take() {
                t.abort();
            }
            if was {
                inner.prompt_gen += 1;
                inner.prompts.finished(Instant::now());
            }
            was
        };
        if was {
            eprintln!("[audio] {source}: prompt stopped");
        }
        self.publish();
        was
    }

    // ---- phone calls (ADR-0045) ---------------------------------------------

    fn on_calls(self: &Arc<Self>) {
        {
            let s = self.bt.snapshot().borrow().clone();
            let t = self.tel.calls().borrow().clone();
            let mut inner = self.lock();
            self.follow_calls(&mut inner, &s, &t, Instant::now());
        }
        self.publish();
    }

    /// The calls on the phone in use.
    fn phone_calls(inner: &Inner, s: &Snapshot, t: &CallSnapshot) -> Vec<Call> {
        let Some(phone) = Self::current(inner, s) else {
            return Vec::new();
        };
        t.calls
            .iter()
            .filter(|c| c.address == phone.address && c.state != CallState::Disconnected)
            .cloned()
            .collect()
    }

    /// Keeps the calls' ids and times, logs their changes, and pauses the
    /// music when the first call starts and resumes it after the last.
    fn follow_calls(
        self: &Arc<Self>,
        inner: &mut Inner,
        s: &Snapshot,
        t: &CallSnapshot,
        now: Instant,
    ) {
        let mine = Self::phone_calls(inner, s, t);
        inner.calls.retain(|path, _| {
            t.calls
                .iter()
                .any(|c| &c.path == path && c.state != CallState::Disconnected)
        });
        for c in &t.calls {
            if c.state == CallState::Disconnected {
                continue;
            }
            let next_id = inner.next_call_id;
            let memo = inner
                .calls
                .entry(c.path.clone())
                .or_insert_with(|| CallMemo {
                    id: next_id,
                    state: CallState::Unknown,
                    active_since: None,
                });
            if memo.id == next_id {
                inner.next_call_id += 1;
            }
            if memo.state != c.state {
                if mine.iter().any(|m| m.path == c.path) {
                    eprintln!(
                        "[audio] call {} ({}): {:?}",
                        memo.id,
                        calls::caller(c),
                        c.state
                    );
                }
                memo.state = c.state;
            }
            if c.state == CallState::Active && memo.active_since.is_none() {
                memo.active_since = Some(now);
            }
        }
        let in_call = !mine.is_empty();
        if in_call && !inner.in_call {
            // Spoken directions stop for the call (ADR-0039 decision 9's
            // rule: skipped, not queued).
            if let Some(task) = inner.saying.take() {
                task.abort();
                inner.prompt_gen += 1;
                inner.prompts.finished(now);
                eprintln!("[audio] prompt stopped for a call");
            }
            let playing = s
                .player
                .as_ref()
                .is_some_and(|p| p.state == PlayState::Playing);
            if let Some(act) = inner.call_pause.start(playing) {
                self.send_act(act);
            }
            // The microphone to the phone, the phone's voice to the speakers.
            if let Some(phone) = Self::current(inner, s) {
                self.call_audio.start(&phone.address);
            }
        } else if !in_call && inner.in_call {
            eprintln!("[audio] no call any more");
            inner.call_pause.finished(now);
            self.call_audio.stop();
            // The call is in the phone's history now.
            if let Some(phone) = Self::current(inner, s) {
                self.book.load(Some(phone.address));
            }
            if inner.mic_muted {
                // Every call starts unmuted.
                inner.mic_muted = false;
                let me = Arc::clone(self);
                tokio::spawn(async move {
                    if let Err(e) = me.tel.set_mic_muted(false).await {
                        eprintln!("[audio] call microphone: unmuting after the call: {e}");
                    }
                });
            }
        }
        inner.in_call = in_call;
        self.ring_check(inner, s, t, now);
    }

    /// Rings through the speakers while the call shown rings (incoming)
    /// and its phone sends no ring tone of its own, after `ring_after`
    /// (ADR-0045 decision 7). A waiting call isn't rung: it would sound over
    /// the call in progress.
    fn ring_check(
        self: &Arc<Self>,
        inner: &mut Inner,
        s: &Snapshot,
        t: &CallSnapshot,
        now: Instant,
    ) {
        let phone = Self::current(inner, s);
        let address = phone.as_ref().map_or("", |p| p.address.as_str());
        let mine = Self::phone_calls(inner, s, t);
        let ringing = calls::pick(&mine, address)
            .0
            .filter(|c| c.state == CallState::Incoming)
            .and_then(|c| inner.calls.get(&c.path).map(|m| m.id));
        inner.incoming = match (ringing, inner.incoming) {
            (Some(id), Some((was, since))) if id == was => Some((id, since)),
            (Some(id), _) => Some((id, now)),
            (None, _) => None,
        };
        let in_band = t.gateways.iter().any(|g| g.address == address && g.audio);
        let ring = inner
            .incoming
            .is_some_and(|(_, since)| now.saturating_duration_since(since) >= self.cfg.ring_after)
            && !in_band
            && self.ringer.available().is_ok();
        match (ring, inner.ring.is_some()) {
            (true, false) => {
                eprintln!("[audio] ringing through the speakers (the phone sends no ring tone)");
                let me = Arc::clone(self);
                let task = tokio::spawn(async move {
                    loop {
                        if let Err(e) = me.ringer.ring_once().await {
                            eprintln!("[audio] ring tone: {e}");
                            tokio::time::sleep(Duration::from_secs(3)).await;
                        }
                    }
                });
                inner.ring = Some(task.abort_handle());
            }
            (false, true) => {
                if let Some(task) = inner.ring.take() {
                    task.abort();
                }
                eprintln!(
                    "[audio] ring tone stopped{}",
                    if in_band && inner.incoming.is_some() {
                        ": the phone's own started"
                    } else {
                        ""
                    }
                );
            }
            _ => {}
        }
    }

    /// The call named `id` on the phone in use, if it is still there.
    fn call_by_id(&self, id: u64) -> Result<Call, String> {
        let s = self.bt.snapshot().borrow().clone();
        let t = self.tel.calls().borrow().clone();
        match &t.availability {
            Availability::Off(why) => return Err(format!("Calls stay on the phone: {why}.")),
            Availability::Unavailable(why) => return Err(format!("Calls unavailable: {why}.")),
            Availability::Ready => {}
        }
        let inner = self.lock();
        Self::phone_calls(&inner, &s, &t)
            .into_iter()
            .find(|c| inner.calls.get(&c.path).is_some_and(|m| m.id == id))
            .ok_or_else(|| "That call has ended.".to_string())
    }

    /// Answers an incoming call. Ok: what is happening, for the screen.
    pub async fn answer_call(&self, id: u64, source: &str) -> Result<String, String> {
        let c = self.call_by_id(id)?;
        match c.state {
            CallState::Incoming => {}
            CallState::Waiting => {
                return Err("Another call is in progress: answer this one on the phone.".into());
            }
            _ => return Err("That call isn't ringing.".into()),
        }
        eprintln!("[audio] {source}: answer call {id} ({})", calls::caller(&c));
        self.tel
            .answer(&c.path)
            .await
            .map(|()| "Answered.".to_string())
            .map_err(|e| {
                eprintln!("[audio] answering call {id}: {e}");
                format!("The phone didn't answer the call: {e}.")
            })
    }

    /// Declines a ringing call or hangs up any other.
    pub async fn hang_up(&self, id: u64, source: &str) -> Result<String, String> {
        let c = self.call_by_id(id)?;
        let what = if c.state.rings() {
            "decline"
        } else {
            "hang up"
        };
        eprintln!("[audio] {source}: {what} call {id} ({})", calls::caller(&c));
        self.tel
            .hang_up(&c.path)
            .await
            .map(|()| {
                if c.state.rings() {
                    "Declined.".to_string()
                } else {
                    "Hung up.".to_string()
                }
            })
            .map_err(|e| {
                eprintln!("[audio] {what} call {id}: {e}");
                format!("The phone didn't end the call: {e}.")
            })
    }

    /// The knob's push (ADR-0045 decision 6, the same key as play/pause,
    /// ADR-0043): answers a ringing call, hangs up the call in progress, and
    /// without a call plays or pauses. A waiting call (another one during a
    /// call) isn't touched: answering it ends or holds the first, so it is
    /// answered or declined on the screen or the phone. Ok: what it did.
    pub async fn knob_push(&self, source: &str) -> Result<String, String> {
        let shown = {
            let s = self.bt.snapshot().borrow().clone();
            let t = self.tel.calls().borrow().clone();
            let inner = self.lock();
            let mine = Self::phone_calls(&inner, &s, &t);
            let address = Self::current(&inner, &s)
                .map(|p| p.address)
                .unwrap_or_default();
            calls::pick(&mine, &address)
                .0
                .and_then(|c| Some((inner.calls.get(&c.path)?.id, c.state)))
        };
        match shown {
            None => self
                .play_pause(source)
                .await
                .map(|c| c.method().to_string()),
            Some((id, CallState::Incoming)) => self.answer_call(id, source).await,
            Some((_, CallState::Waiting)) => {
                eprintln!("[audio] {source}: push ignored: another call is waiting");
                Err(
                    "Another call is waiting: answer or decline it on the screen or the phone."
                        .into(),
                )
            }
            Some((id, _)) => self.hang_up(id, source).await,
        }
    }

    /// Mutes or unmutes the call microphone, during a call only.
    pub async fn set_mic_muted(&self, muted: bool, source: &str) -> Result<(), String> {
        if !self.lock().in_call {
            return Err("There is no call.".into());
        }
        self.tel.set_mic_muted(muted).await.map_err(|e| {
            eprintln!("[audio] call microphone: {e}");
            format!(
                "The microphone couldn't be {}: {e}.",
                if muted { "muted" } else { "unmuted" }
            )
        })?;
        let changed = {
            let mut inner = self.lock();
            let changed = inner.mic_muted != muted;
            inner.mic_muted = muted;
            changed
        };
        if changed {
            eprintln!(
                "[audio] {source}: call microphone {}",
                if muted { "muted" } else { "unmuted" }
            );
        }
        self.publish();
        Ok(())
    }

    /// Asks for the lists of the phone in use when it changes (none: they
    /// are cleared).
    fn follow_book(&self) {
        let s = self.bt.snapshot().borrow().clone();
        let mut inner = self.lock();
        let address = Self::current(&inner, &s).map(|p| p.address);
        if address != inner.book_for {
            inner.book_for.clone_from(&address);
            drop(inner);
            self.book.load(address);
        }
    }

    /// Calls `number` from the phone in use (ADR-0045 phase 2). Ok: what is
    /// happening, for the screen. Not during another call: hold and swap
    /// are the phone's.
    pub async fn dial(&self, number: &str, source: &str) -> Result<String, String> {
        let number = phonebook::dial_number(number)?;
        let s = self.bt.snapshot().borrow().clone();
        let t = self.tel.calls().borrow().clone();
        match &t.availability {
            Availability::Off(why) => return Err(format!("Calls stay on the phone: {why}.")),
            Availability::Unavailable(why) => return Err(format!("Calls unavailable: {why}.")),
            Availability::Ready => {}
        }
        let address = {
            let inner = self.lock();
            let phone = Self::current(&inner, &s).ok_or("No phone is connected.")?;
            if !Self::phone_calls(&inner, &s, &t).is_empty() {
                return Err("A call is in progress: hang it up first.".into());
            }
            phone.address
        };
        // The number itself isn't logged: it is the driver's business.
        eprintln!(
            "[audio] {source}: dial a number ({} characters)",
            number.len()
        );
        self.tel
            .dial(&address, &number)
            .await
            .map(|()| "Calling…".to_string())
            .map_err(|e| {
                eprintln!("[audio] dialling: {e}");
                format!("The phone didn't place the call: {e}.")
            })
    }

    /// The phone's lists as last read.
    pub fn phonebook(&self) -> pb::GetPhonebookResponse {
        let b = self.book.book().borrow().clone();
        pb::GetPhonebookResponse {
            version: b.version,
            contacts: b
                .contacts
                .iter()
                .map(|c| pb::Contact {
                    name: c.name.clone(),
                    numbers: c
                        .numbers
                        .iter()
                        .map(|n| pb::ContactNumber {
                            number: n.number.clone(),
                            label: n.label.clone(),
                        })
                        .collect(),
                })
                .collect(),
            recent_calls: b
                .recent
                .iter()
                .map(|r| pb::RecentCall {
                    name: r.name.clone(),
                    number: r.number.clone(),
                    kind: match r.kind {
                        RecentKind::Received => pb::RecentKind::Received,
                        RecentKind::Dialed => pb::RecentKind::Dialed,
                        RecentKind::Missed => pb::RecentKind::Missed,
                        RecentKind::Unknown => pb::RecentKind::Unspecified,
                    }
                    .into(),
                    time: r.time.clone(),
                })
                .collect(),
        }
    }

    /// Reads the phone's lists again. Ok: what is happening.
    pub fn refresh_phonebook(&self, source: &str) -> Result<String, String> {
        if let BookState::Off(why) = &self.book.book().borrow().state {
            return Err(format!("The phone's contacts aren't read here: {why}."));
        }
        let s = self.bt.snapshot().borrow().clone();
        let phone = Self::current(&self.lock(), &s).ok_or("No phone is connected.")?;
        eprintln!("[audio] {source}: read the phone's contacts again");
        self.book.load(Some(phone.address));
        Ok("Reading the phone's contacts…".into())
    }

    fn phonebook_pb(&self) -> pb::Phonebook {
        let b = self.book.book().borrow().clone();
        let (state, detail) = match &b.state {
            BookState::None => (pb::PhonebookState::None, String::new()),
            BookState::Loading => (pb::PhonebookState::Loading, String::new()),
            BookState::Ready => (pb::PhonebookState::Ready, String::new()),
            BookState::Failed(why) => (pb::PhonebookState::Failed, why.clone()),
            BookState::Off(why) => (pb::PhonebookState::Off, why.clone()),
        };
        pb::Phonebook {
            state: state.into(),
            detail,
            version: b.version,
            contacts: u32::try_from(b.contacts.len()).unwrap_or(u32::MAX),
            recent_calls: u32::try_from(b.recent.len()).unwrap_or(u32::MAX),
        }
    }

    fn calls_pb(&self, inner: &Inner, s: &Snapshot, now: Instant) -> pb::Calls {
        let t = self.tel.calls().borrow().clone();
        let phone = Self::current(inner, s);
        let (available, detail) = match (&t.availability, &phone) {
            (Availability::Off(why), _) => (false, format!("Calls stay on the phone: {why}.")),
            (Availability::Unavailable(why), _) => (false, format!("Calls unavailable: {why}.")),
            (Availability::Ready, None) => (false, "No phone is connected.".to_string()),
            (Availability::Ready, Some(p))
                if !t.gateways.iter().any(|g| g.address == p.address) =>
            {
                (
                    false,
                    format!(
                        "{} hasn't connected for calls: they stay on the phone.",
                        p.name
                    ),
                )
            }
            (Availability::Ready, Some(_)) => (true, String::new()),
        };
        let mine = Self::phone_calls(inner, s, &t);
        let (shown, others) = calls::pick(&mine, phone.as_ref().map_or("", |p| p.address.as_str()));
        let call = shown.and_then(|c| {
            let memo = inner.calls.get(&c.path)?;
            let state = match c.state {
                CallState::Incoming => pb::CallState::Incoming,
                CallState::Waiting => pb::CallState::Waiting,
                CallState::Dialing => pb::CallState::Dialing,
                CallState::Alerting => pb::CallState::Alerting,
                CallState::Active => pb::CallState::Active,
                CallState::Held => pb::CallState::Held,
                CallState::Disconnected | CallState::Unknown => pb::CallState::Unspecified,
            };
            Some(pb::Call {
                id: memo.id,
                state: state.into(),
                number: c.number.clone(),
                // The phone's name for the caller, else the contact the
                // number belongs to (many phones give none for a call out).
                name: if c.name.is_empty() {
                    phonebook::name_for(&self.book.book().borrow().contacts, &c.number)
                        .unwrap_or_default()
                } else {
                    c.name.clone()
                },
                withheld: c.withheld,
                active_s: memo.active_since.map_or(0, |at| {
                    u32::try_from(now.saturating_duration_since(at).as_secs()).unwrap_or(u32::MAX)
                }),
                multiparty: c.multiparty,
            })
        });
        pb::Calls {
            available,
            detail,
            call,
            other_calls: others,
            mic_muted: inner.mic_muted && inner.in_call,
            phone_name: phone.map(|p| p.name).unwrap_or_default(),
            local_ring: inner.ring.is_some(),
        }
    }

    // ---- requests from the dashboard ----------------------------------------

    pub async fn control(&self, cmd: Command, source: &str) -> Result<(), String> {
        let s = self.bt.snapshot().borrow().clone();
        if s.connected_phone().is_none() {
            return Err("No phone is connected.".into());
        }
        if s.player.is_none() {
            return Err("The phone doesn't offer playback control (no AVRCP player).".into());
        }
        eprintln!("[audio] {source}: {}", cmd.method());
        // The driver's own choice: audio-manager won't resume it after
        // prompts or a call.
        {
            let mut inner = self.lock();
            inner.prompts.forget();
            inner.call_pause.forget();
        }
        self.bt.control(cmd).await
    }

    /// Play/pause from the knob (one key for both, ADR-0043): pauses a
    /// playing phone, plays one that isn't.
    pub async fn play_pause(&self, source: &str) -> Result<Command, String> {
        let playing = self
            .bt
            .snapshot()
            .borrow()
            .player
            .as_ref()
            .is_some_and(|p| p.state == PlayState::Playing);
        let cmd = if playing {
            Command::Pause
        } else {
            Command::Play
        };
        self.control(cmd, source).await.map(|()| cmd)
    }

    pub fn open_pairing(
        self: &Arc<Self>,
        seconds: Option<u32>,
        source: &str,
    ) -> Result<(), String> {
        let r = {
            let mut inner = self.lock();
            let r = inner.window.open(Instant::now(), seconds);
            if let Ok(out) = &r {
                self.carry_out(&mut inner, *out);
            }
            r
        };
        match &r {
            Ok(_) => eprintln!("[audio] {source}: pairing window opened"),
            Err(e) => eprintln!("[audio] {source}: pairing window refused: {e}"),
        }
        self.publish();
        r.map(|_| ())
    }

    pub fn close_pairing(self: &Arc<Self>, source: &str) -> bool {
        let was = {
            let mut inner = self.lock();
            let (was, out) = inner.window.close(Instant::now());
            self.carry_out(&mut inner, out);
            was
        };
        if was {
            eprintln!("[audio] {source}: pairing window closed");
        }
        self.publish();
        was
    }

    pub fn confirm(&self, id: u64, accept: bool, source: &str) -> bool {
        let answered = {
            let mut inner = self.lock();
            if inner.window.answer(id, accept) {
                if let Some(tx) = inner.replies.remove(&id) {
                    let _ = tx.send(accept);
                }
                true
            } else {
                false
            }
        };
        if answered {
            eprintln!(
                "[audio] {source}: pairing question {id} {}",
                if accept { "accepted" } else { "refused" }
            );
        }
        self.publish();
        answered
    }

    pub async fn set_settings(&self, s: Settings, source: &str) -> Result<String, String> {
        self.cfg.limits.validate(&s)?;
        if let Some(path) = &self.cfg.settings_file {
            let tmp = path.with_extension("json.new");
            std::fs::write(&tmp, dsp::settings_json(&s))
                .and_then(|()| std::fs::rename(&tmp, path))
                .map_err(|e| format!("The settings can't be saved ({}): {e}", path.display()))?;
        }
        self.lock().settings = s;
        eprintln!("[audio] {source}: speaker settings {s:?}");
        let r = self.apply_mix().await;
        self.publish();
        r
    }

    pub fn limits(&self) -> Limits {
        self.cfg.limits
    }

    pub fn defaults(&self) -> Settings {
        self.cfg.defaults
    }

    // ---- what the dashboard sees ---------------------------------------------

    /// The picture named `id` (NowPlaying.cover_art_id), only while it is
    /// the connected phone's current track's.
    pub fn cover_art(&self, id: &str) -> Option<Picture> {
        let s: Snapshot = self.bt.snapshot().borrow().clone();
        let phone = Self::current(&self.lock(), &s)?;
        let player = s.player.as_ref().filter(|pl| pl.address == phone.address)?;
        let art = self.bt.cover_art().borrow().clone();
        art.for_player(player)
            .filter(|p| p.id.to_string() == id)
            .cloned()
    }

    pub fn publish(&self) {
        let s: Snapshot = self.bt.snapshot().borrow().clone();
        let now = Instant::now();
        let inner = self.lock();
        let (bluetooth, bluetooth_detail) = match &s.adapter {
            Adapter::Ready { .. } => (pb::BluetoothState::Ready, String::new()),
            Adapter::Unavailable(why) => (pb::BluetoothState::Unavailable, why.clone()),
        };
        let phone = Self::current(&inner, &s);
        let to_pb = |p: &crate::model::Phone| pb::Phone {
            address: p.address.clone(),
            name: p.name.clone(),
            connected: p.connected,
            paired: p.paired,
            last: inner.last_phone.as_deref() == Some(p.address.as_str()),
        };
        let art = self.bt.cover_art().borrow().clone();
        // Only the connected phone's player, never a gone phone's track.
        let now_playing = s
            .player
            .as_ref()
            .filter(|pl| phone.as_ref().is_some_and(|p| p.address == pl.address))
            .map(|pl| {
                let pos = pl.position_at(now);
                // Only the picture of this track (ADR-0042).
                let picture = art.for_player(pl);
                pb::NowPlaying {
                    title: pl.track.title.clone(),
                    artist: pl.track.artist.clone(),
                    album: pl.track.album.clone(),
                    state: play_state(pl.state).into(),
                    duration_ms: pl.track.duration_ms.unwrap_or(0),
                    has_position: pos.is_some(),
                    position_ms: pos.unwrap_or(0),
                    player_name: pl.name.clone(),
                    cover_art_id: picture.map(|p| p.id.to_string()).unwrap_or_default(),
                    cover_art_detail: if picture.is_some() {
                        String::new()
                    } else {
                        art.detail.clone()
                    },
                }
            });
        let w = &inner.window;
        let state = match w.state() {
            State::Closed => pb::PairingState::Closed,
            State::Opening => pb::PairingState::Opening,
            State::Open => pb::PairingState::Open,
            State::Closing => pb::PairingState::Closing,
            State::Failed => pb::PairingState::Failed,
        };
        let question = w.question().map(|q| pb::PasskeyQuestion {
            id: q.id,
            phone_name: q.name.clone(),
            address: q.address.clone(),
            passkey: q.passkey.unwrap_or(0),
            shows_passkey: q.passkey.is_some(),
            seconds_left: u32::try_from(q.deadline.saturating_duration_since(now).as_secs())
                .unwrap_or(0),
        });
        let (dsp, dsp_detail) = match &*self.dsp.state().borrow() {
            DspState::Applied => (pb::DspState::Applied, String::new()),
            DspState::Starting => (pb::DspState::Starting, String::new()),
            DspState::NotRunning(why) => (pb::DspState::NotRunning, why.clone()),
        };
        let volume = {
            let v = inner.volume;
            let (applied, detail) = match &*self.dsp.state().borrow() {
                DspState::Applied => (true, String::new()),
                DspState::Starting => (
                    false,
                    "Not applied yet: the speakers' filter-chain is starting.".to_string(),
                ),
                DspState::NotRunning(why) => (false, format!("Not applied: {why}.")),
            };
            pb::Volume {
                level: v.level,
                max: self.cfg.volume.max,
                steps: self.cfg.volume.steps,
                muted: v.muted,
                applied,
                detail,
            }
        };
        let msg = pb::WatchAudioResponse {
            bluetooth: bluetooth.into(),
            bluetooth_detail,
            phone: phone.as_ref().map(to_pb),
            // Every other paired phone, connected or not: a phone is never
            // left out of the list (one still connected is being
            // disconnected, one phone at a time).
            known: s
                .phones
                .iter()
                .filter(|p| phone.as_ref().is_none_or(|c| c.address != p.address))
                .map(to_pb)
                .collect(),
            now_playing,
            streaming: s.streaming && phone.is_some(),
            pairing: Some(pb::Pairing {
                state: state.into(),
                seconds_left: w.seconds_left(now),
                detail: w.detail().to_string(),
                question,
                name: self.cfg.name.clone(),
            }),
            dsp: dsp.into(),
            dsp_detail,
            simulated: self.cfg.simulated,
            volume: Some(volume),
            calls: Some(self.calls_pb(&inner, &s, now)),
            phonebook: Some(self.phonebook_pb()),
            connect: Some(pb::ConnectAttempt {
                address: inner
                    .attempt
                    .as_ref()
                    .map(|a| a.address.clone())
                    .unwrap_or_default(),
                name: inner
                    .attempt
                    .as_ref()
                    .map(|a| a.name.clone())
                    .unwrap_or_default(),
                automatic: inner.attempt.as_ref().is_some_and(|a| a.automatic),
                detail: inner.connect_detail.clone(),
            }),
            prompts: Some(pb::Prompts {
                available: self.voice.available().is_ok(),
                speaking: inner.prompts.speaking(),
                music_paused: inner.prompts.music_paused(),
                detail: match self.voice.available() {
                    Err(why) => why,
                    Ok(how) if inner.prompt_detail.is_empty() => how,
                    Ok(_) => inner.prompt_detail.clone(),
                },
            }),
        };
        drop(inner);
        // Every call is sent, even unchanged: it is the heartbeat.
        self.out.send_replace(msg);
    }
}
