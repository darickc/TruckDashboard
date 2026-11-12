//! audio-manager's core: follows the Bluetooth backend, runs the pairing
//! window and the pairing agent's questions, connects paired phones (the
//! driver's choice, or the last phone again by itself), keeps the speaker
//! settings, and publishes what the dashboard shows
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
    /// Where the address of the phone connected last is kept; None: only in
    /// memory.
    pub last_phone_file: Option<PathBuf>,
    pub reconnect: Reconnect,
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
        let (last_phone, problem) = load_last_phone(cfg.last_phone_file.as_deref());
        if let Some(p) = problem {
            eprintln!("[audio] last phone: {p}");
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
            self.follow_order(inner, &s);
            inner.seen = true;
            self.one_phone(inner, &s);
            self.follow_connection(inner, &s, now);
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
            let snap = self.bt.snapshot().borrow().clone();
            self.reconnect_tick(inner, &snap, now);
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
            if inner.attempt.is_none() {
                inner.connect_detail.clear();
            }
        } else if ready
            && (!inner.adapter_ready || inner.had_phone)
            && !self.cfg.reconnect.window.is_zero()
            && let Some(last) = inner.last_phone.clone()
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
        let phone = Self::current(&inner, &s);
        let to_pb = |p: &crate::model::Phone| pb::Phone {
            address: p.address.clone(),
            name: p.name.clone(),
            connected: p.connected,
            paired: p.paired,
            last: inner.last_phone.as_deref() == Some(p.address.as_str()),
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
