//! Runs the speakers' filter-chain (ADR-0039 decision 6): audio-manager
//! writes the configuration from the settings and runs `pipewire -c <file>`
//! as its child, a PipeWire client holding only the filter-chain, and
//! restarts it with a backoff if it stops. Fader, balance, sub level, the
//! volume (ADR-0043) and the crossover change live with `pw-cli set-param`; only a failed live
//! change restarts the child.
//!
//! After every start the runner writes a key into WirePlumber's `filters`
//! metadata (`pw-metadata`), which makes its policy instance rescan the
//! graph. Without it, a filter-chain that comes back while the chain is
//! linked is left out: AGL's equalizer stays linked straight to the DAC and
//! the doors get full range (bench-log 2026-11-12).

use std::path::PathBuf;
use std::process::Stdio;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::process::{Child, Command};
use tokio::sync::{mpsc, watch};

use crate::dsp::{self, Limits, Mix, Target};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DspState {
    /// Running with the settings.
    Applied,
    Starting,
    /// Not running; why.
    NotRunning(String),
}

#[tonic::async_trait]
pub trait Dsp: Send + Sync {
    fn state(&self) -> watch::Receiver<DspState>;
    /// Starts the filter-chain with `m` (once, at start).
    async fn start(&self, m: Mix);
    /// Applies new settings or a new volume. Ok: what happened, for the
    /// screen.
    async fn apply(&self, m: Mix) -> Result<String, String>;
}

/// No PipeWire (the Mac, the tests, `--no-dsp`): settings are kept, not
/// applied, and the screen says so.
pub struct NoDsp {
    state: watch::Sender<DspState>,
    why: String,
}

impl NoDsp {
    pub fn new(why: impl Into<String>) -> NoDsp {
        let why = why.into();
        NoDsp {
            state: watch::Sender::new(DspState::NotRunning(why.clone())),
            why,
        }
    }
}

#[tonic::async_trait]
impl Dsp for NoDsp {
    fn state(&self) -> watch::Receiver<DspState> {
        self.state.subscribe()
    }
    async fn start(&self, _: Mix) {}
    async fn apply(&self, _: Mix) -> Result<String, String> {
        Ok(format!("Saved, not applied: {}.", self.why))
    }
}

#[derive(Debug, Clone)]
pub struct PipewireConfig {
    /// `pipewire`, run as `pipewire -c <conf>`.
    pub pipewire: PathBuf,
    /// `pw-cli`, for live changes.
    pub pw_cli: PathBuf,
    /// `pw-metadata`, to make WirePlumber relink the chain after a start.
    pub pw_metadata: PathBuf,
    /// Where the generated configuration is written (the runtime directory).
    pub conf: PathBuf,
    pub limits: Limits,
    pub target: Target,
    /// Running this long counts as started.
    pub settle: Duration,
    pub max_backoff: Duration,
}

enum Msg {
    Restart,
}

pub struct PipewireDsp {
    cfg: PipewireConfig,
    state: watch::Sender<DspState>,
    /// What the child should run with (the latest applied).
    wanted: Arc<Mutex<Option<Mix>>>,
    /// What the running child runs with (started with, or changed live).
    running: Arc<Mutex<Option<Mix>>>,
    tx: mpsc::Sender<Msg>,
    rx: Mutex<Option<mpsc::Receiver<Msg>>>,
    /// How many times the filter-chain has started: the metadata value, so
    /// every write is a change.
    starts: AtomicU64,
}

/// The `filters` metadata key the runner writes (on subject 0, the core:
/// WirePlumber's filter scripts only read keys on filter nodes' ids, so it
/// changes nothing but triggers the rescan).
pub const RELINK_KEY: &str = "f250.speakers.started";

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
}

impl PipewireDsp {
    pub fn new(cfg: PipewireConfig) -> Arc<PipewireDsp> {
        let (tx, rx) = mpsc::channel(8);
        Arc::new(PipewireDsp {
            cfg,
            state: watch::Sender::new(DspState::Starting),
            wanted: Arc::default(),
            running: Arc::default(),
            tx,
            rx: Mutex::new(Some(rx)),
            starts: AtomicU64::new(0),
        })
    }

    fn spawn_child(cfg: &PipewireConfig, m: &Mix) -> Result<Child, String> {
        let text = dsp::render(&cfg.limits, &m.settings, m.master, &cfg.target);
        if let Some(dir) = cfg.conf.parent() {
            std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        }
        let tmp = cfg.conf.with_extension("conf.new");
        std::fs::write(&tmp, text).map_err(|e| format!("{}: {e}", tmp.display()))?;
        std::fs::rename(&tmp, &cfg.conf).map_err(|e| format!("{}: {e}", cfg.conf.display()))?;
        Command::new(&cfg.pipewire)
            .arg("-c")
            .arg(&cfg.conf)
            .stdin(Stdio::null())
            .kill_on_drop(true)
            .spawn()
            .map_err(|e| format!("{} can't start: {e}", cfg.pipewire.display()))
    }

    /// The supervisor: keeps one child running with the wanted settings.
    async fn supervise(self: Arc<Self>, mut rx: mpsc::Receiver<Msg>) {
        let mut backoff = Duration::from_secs(1);
        loop {
            let Some(m) = *lock(&self.wanted) else {
                // Not started yet.
                if rx.recv().await.is_none() {
                    return;
                }
                continue;
            };
            self.state.send_replace(DspState::Starting);
            let mut child = match Self::spawn_child(&self.cfg, &m) {
                Ok(c) => c,
                Err(e) => {
                    eprintln!("[audio] speakers' filter-chain: {e}");
                    self.state.send_replace(DspState::NotRunning(e));
                    *lock(&self.running) = None;
                    tokio::select! {
                        _ = tokio::time::sleep(backoff) => {}
                        m = rx.recv() => if m.is_none() { return },
                    }
                    backoff = (backoff * 2).min(self.cfg.max_backoff);
                    continue;
                }
            };
            *lock(&self.running) = Some(m);
            let mut settled = false;
            let settle = tokio::time::sleep(self.cfg.settle);
            tokio::pin!(settle);
            let restart = loop {
                tokio::select! {
                    () = &mut settle, if !settled => {
                        settled = true;
                        backoff = Duration::from_secs(1);
                        eprintln!("[audio] speakers' filter-chain running ({}, crossover {} Hz)",
                            self.cfg.conf.display(), m.settings.crossover_hz);
                        self.relink().await;
                        self.state.send_replace(DspState::Applied);
                    }
                    st = child.wait() => {
                        let why = match st {
                            Ok(st) => format!("{} stopped ({st})", self.cfg.pipewire.display()),
                            Err(e) => format!("{}: {e}", self.cfg.pipewire.display()),
                        };
                        eprintln!("[audio] speakers' filter-chain: {why}; restarting in {} s", backoff.as_secs());
                        self.state.send_replace(DspState::NotRunning(why));
                        break false;
                    }
                    m = rx.recv() => {
                        match m {
                            Some(Msg::Restart) => break true,
                            None => { let _ = child.kill().await; return; }
                        }
                    }
                }
            };
            *lock(&self.running) = None;
            if restart {
                let _ = child.kill().await;
                continue;
            }
            tokio::select! {
                _ = tokio::time::sleep(backoff) => {}
                m = rx.recv() => if m.is_none() { return },
            }
            backoff = (backoff * 2).min(self.cfg.max_backoff);
        }
    }

    /// Makes WirePlumber's policy instance rescan, so the chain is linked
    /// through the filter that just started. A failure is logged: the chain
    /// may then bypass the filter until the next stream starts.
    async fn relink(&self) {
        let n = self.starts.fetch_add(1, Ordering::Relaxed) + 1;
        let out = tokio::time::timeout(
            Duration::from_secs(3),
            Command::new(&self.cfg.pw_metadata)
                .args(["-n", "filters", "0", RELINK_KEY, &n.to_string()])
                .stdin(Stdio::null())
                .output(),
        )
        .await;
        let why = match out {
            Err(_) => "no answer in 3 s".to_string(),
            Ok(Err(e)) => format!("{}: {e}", self.cfg.pw_metadata.display()),
            Ok(Ok(o)) if !o.status.success() => {
                format!("{} {}", o.status, String::from_utf8_lossy(&o.stderr).trim())
            }
            Ok(Ok(_)) => return,
        };
        eprintln!(
            "[audio] speakers' filter-chain: couldn't ask WirePlumber to relink it ({why}); \
             the speakers may bypass it until the next stream starts"
        );
    }

    async fn set_live(&self, m: &Mix) -> Result<(), String> {
        let json = dsp::props_json(&self.cfg.limits, &m.settings, m.master);
        let out = tokio::time::timeout(
            Duration::from_secs(3),
            Command::new(&self.cfg.pw_cli)
                .args(["set-param", dsp::NODE_NAME, "Props", &json])
                .stdin(Stdio::null())
                .output(),
        )
        .await
        .map_err(|_| "pw-cli didn't answer in 3 s".to_string())?
        .map_err(|e| format!("{}: {e}", self.cfg.pw_cli.display()))?;
        let err = String::from_utf8_lossy(&out.stderr);
        if !out.status.success() || err.contains("rror") {
            return Err(format!("pw-cli: {} {}", out.status, err.trim()));
        }
        Ok(())
    }
}

#[tonic::async_trait]
impl Dsp for Arc<PipewireDsp> {
    fn state(&self) -> watch::Receiver<DspState> {
        self.state.subscribe()
    }

    async fn start(&self, m: Mix) {
        *lock(&self.wanted) = Some(m);
        let rx = lock(&self.rx).take();
        match rx {
            // The supervisor starts the child with `wanted` at once.
            Some(rx) => {
                tokio::spawn(Arc::clone(self).supervise(rx));
            }
            None => {
                let _ = self.tx.send(Msg::Restart).await;
            }
        }
    }

    async fn apply(&self, m: Mix) -> Result<String, String> {
        *lock(&self.wanted) = Some(m);
        let running = *lock(&self.running);
        let live = running.is_some() && *self.state.borrow() == DspState::Applied;
        if live {
            match self.set_live(&m).await {
                Ok(()) => {
                    *lock(&self.running) = Some(m);
                    return Ok("Applied.".into());
                }
                Err(e) => {
                    eprintln!("[audio] live change failed ({e}); restarting the filter-chain")
                }
            }
        }
        self.tx
            .send(Msg::Restart)
            .await
            .map_err(|_| "the filter-chain's supervisor has stopped".to_string())?;
        Ok("Applied by restarting the speakers' filter.".into())
    }
}
