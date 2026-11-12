//! audio-manager's core: follows the Bluetooth backend, runs the pairing
//! window and the pairing agent's questions, keeps the speaker settings, and
//! publishes what the dashboard shows (`f250.audio.v1.WatchAudioResponse`)
//! on each change and once a second.
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
use crate::dsp::{self, Limits, Settings};
use crate::model::{Adapter, AgentAsk, AgentRequest, Command, PlayState, Snapshot};
use crate::pairing::{self, Action, Outcome, State, Window};
use crate::prompts::{Act, PromptPause};
use crate::runner::{Dsp, DspState};
use crate::voice::{Voice, clean_prompt};

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
}

pub struct Manager {
    cfg: Config,
    bt: Arc<dyn Bluetooth>,
    dsp: Arc<dyn Dsp>,
    voice: Arc<dyn Voice>,
    inner: Mutex<Inner>,
    out: watch::Sender<pb::WatchAudioResponse>,
    /// Bumped by the main loop (systemd watchdog).
    pub heartbeat: f250_sd_notify::Heartbeat,
    /// Shutting down: watch streams end (at their next heartbeat), so the
    /// server's graceful shutdown doesn't wait on them forever.
    stopping: std::sync::atomic::AtomicBool,
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
    pub fn new(
        cfg: Config,
        bt: Arc<dyn Bluetooth>,
        dsp: Arc<dyn Dsp>,
        voice: Arc<dyn Voice>,
    ) -> Arc<Manager> {
        let (settings, problem) = load_settings(&cfg);
        if let Some(p) = problem {
            eprintln!("[audio] speaker settings: {p}");
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
            }),
            cfg,
            bt,
            dsp,
            voice,
            out: watch::Sender::new(pb::WatchAudioResponse::default()),
            heartbeat: f250_sd_notify::Heartbeat::new(),
            stopping: std::sync::atomic::AtomicBool::new(false),
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

    /// Starts shutting down: watch streams end within a second.
    pub fn stop(&self) {
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

    /// The main loop: until `agent` closes.
    pub async fn run(self: Arc<Self>, mut agent: mpsc::Receiver<AgentRequest>) {
        let mut snap = self.bt.snapshot();
        let mut dsp_state = self.dsp.state();
        self.dsp.start(self.settings()).await;
        self.on_snapshot();
        let mut tick = tokio::time::interval(Duration::from_secs(1));
        tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        loop {
            tokio::select! {
                r = snap.changed() => {
                    if r.is_err() { return; }
                    self.on_snapshot();
                }
                r = dsp_state.changed() => {
                    if r.is_err() { return; }
                    self.publish();
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
            inner.seen = true;
            // A phone gone (or another one) isn't resumed by us later.
            if s.player.is_none() {
                inner.prompts.forget();
            }
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
            let paused = self
                .bt
                .snapshot()
                .borrow()
                .player
                .as_ref()
                .is_some_and(|p| p.state == PlayState::Paused);
            if let Some(act) = inner.prompts.tick(now, paused) {
                self.send_act(act);
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
        eprintln!("[audio] prompts: {} the phone", cmd.method());
        tokio::spawn(async move {
            if let Err(e) = me.bt.control(cmd).await {
                eprintln!("[audio] prompts: {}: {e}", cmd.method());
            }
        });
    }

    // ---- spoken prompts (navigation) -----------------------------------------

    /// Says `text`, cutting off any prompt still being said. Returns at once.
    pub fn speak(self: &Arc<Self>, text: &str, source: &str) -> Result<(), String> {
        let text = clean_prompt(text);
        if text.is_empty() {
            return Err("Nothing to say.".into());
        }
        self.voice.available()?;
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
        // The driver's own choice: audio-manager won't resume it after prompts.
        self.lock().prompts.forget();
        self.bt.control(cmd).await
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
        let r = self.dsp.apply(s).await;
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

    pub fn publish(&self) {
        let s: Snapshot = self.bt.snapshot().borrow().clone();
        let now = Instant::now();
        let inner = self.lock();
        let (bluetooth, bluetooth_detail) = match &s.adapter {
            Adapter::Ready { .. } => (pb::BluetoothState::Ready, String::new()),
            Adapter::Unavailable(why) => (pb::BluetoothState::Unavailable, why.clone()),
        };
        let phone = s.connected_phone().cloned();
        let to_pb = |p: &crate::model::Phone| pb::Phone {
            address: p.address.clone(),
            name: p.name.clone(),
            connected: p.connected,
            paired: p.paired,
        };
        // Only the connected phone's player, never a gone phone's track.
        let now_playing = s
            .player
            .as_ref()
            .filter(|pl| phone.as_ref().is_some_and(|p| p.address == pl.address))
            .map(|pl| {
                let pos = pl.position_at(now);
                pb::NowPlaying {
                    title: pl.track.title.clone(),
                    artist: pl.track.artist.clone(),
                    album: pl.track.album.clone(),
                    state: play_state(pl.state).into(),
                    duration_ms: pl.track.duration_ms.unwrap_or(0),
                    has_position: pos.is_some(),
                    position_ms: pos.unwrap_or(0),
                    player_name: pl.name.clone(),
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
        let msg = pb::WatchAudioResponse {
            bluetooth: bluetooth.into(),
            bluetooth_detail,
            phone: phone.as_ref().map(to_pb),
            known: s
                .phones
                .iter()
                .filter(|p| !p.connected)
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
