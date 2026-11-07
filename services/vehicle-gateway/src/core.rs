//! The gateway's single control loop. It alone owns the transport, so the
//! half-duplex adapter never sees two requests at once. gRPC handlers send it
//! [`Command`]s and read the snapshot it publishes.

use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use f250_elm::{Addressing, ElmConfig, ObdCommand, ObdRequest, ServiceAllowList};
use f250_proto::vehicle::v1 as pb;
use f250_sd_notify::Heartbeat;
use f250_telemetry::registry::format_bytes;
use f250_telemetry::state::{EventLog, EventSeverity, StoreConfig, TelemetryEvent};
use f250_telemetry::warnings::{AlertKind, Direction};
use f250_telemetry::{
    AlertLevel, Calibration, LinkState, Outcome as TOutcome, PollResult, Provenance, Quantity,
    Registry, SignalDef, TelemetryStore, Validity, WarningConfig,
};
use tokio::sync::{mpsc, oneshot, watch};

use crate::config::{Config, TransportKind};
use crate::link::{
    Action, Event as LinkEvent, LinkMachine, LinkPolicy, MachineState, RecoveryStep,
};
use crate::poll::{Miss, PollPolicy, nrc_means_unsupported};
use crate::scheduler::Scheduler;
use crate::transport::can::{CanLink, CanTiming, Opener};
use crate::transport::obdlink::{DriverEvent, LinkSpec, ObdLink, RawOutcome};
use crate::transport::simulated::SimulatedTransport;
use crate::transport::traffic::TrafficLog;
use crate::transport::{Outcome, ResponderPayload};

const SNAPSHOT_PERIOD: Duration = Duration::from_millis(250);
const HEALTH_PERIOD: Duration = Duration::from_secs(1);
const LINK_DOWN_PAUSE: Duration = Duration::from_millis(500);

pub type Reply<T> = oneshot::Sender<Result<T, String>>;

/// Requests from the gRPC layer.
pub enum Command {
    ListSignals(Reply<Vec<pb::SignalDefinition>>),
    ListEvents(u32, Reply<pb::ListEventsResponse>),
    SetCalibration {
        id: String,
        scale: f64,
        offset: f64,
        reply: Reply<pb::SignalDefinition>,
    },
    SetPolling {
        id: String,
        enabled: bool,
        reply: Reply<()>,
    },
    Probe {
        id: String,
        count: u32,
        reply: Reply<pb::ProbeResponse>,
    },
    Raw {
        line: String,
        reply: Reply<pb::RawResponse>,
    },
    Stats {
        reset: bool,
        reply: Reply<pb::StatsResponse>,
    },
}

enum Transport {
    Sim(Box<SimulatedTransport>),
    Obd(ObdLink),
    Can(CanLink),
}

pub struct Core {
    cfg: Config,
    registry: Registry,
    store: TelemetryStore,
    sched: Scheduler,
    link: LinkMachine,
    transport: Transport,
    epoch: Instant,
    events: EventLog,
    last_success: Option<Duration>,
    pause_until: Duration,
    latencies: HashMap<String, VecDeque<u32>>,
    stats_since: Duration,
    adapter_voltage: Option<f64>,
    last_voltage_at: Duration,
    snapshot_tx: watch::Sender<Arc<pb::Snapshot>>,
    /// Bumped by the control loop and after every adapter request, so the
    /// systemd watchdog sees whether this loop is still making progress.
    heartbeat: Heartbeat,
}

impl Core {
    /// Loads the registry and warnings, applies `--enable`, and builds the
    /// transport. Returns the core, its driver-event receiver (OBDLink and
    /// CAN) and a snapshot receiver for subscribers.
    #[allow(clippy::type_complexity)]
    pub fn new(
        cfg: Config,
    ) -> Result<
        (
            Self,
            Option<mpsc::Receiver<DriverEvent>>,
            watch::Receiver<Arc<pb::Snapshot>>,
        ),
        String,
    > {
        Self::with_can_opener(cfg, None)
    }

    /// [`Core::new`], with the CAN bus supplied by the caller instead of a
    /// SocketCAN socket (tests: an in-memory bus with scripted ECUs).
    #[allow(clippy::type_complexity)]
    pub fn with_can_opener(
        cfg: Config,
        can_opener: Option<Opener>,
    ) -> Result<
        (
            Self,
            Option<mpsc::Receiver<DriverEvent>>,
            watch::Receiver<Arc<pb::Snapshot>>,
        ),
        String,
    > {
        let registry =
            Registry::load_dir(&cfg.signals).map_err(|e| format!("signal registry: {e}"))?;
        // The simulator transmits nothing, so it polls every signal its
        // scenario models (unverified ones still show as unverified).
        let scenario = match cfg.transport {
            TransportKind::Sim => Some(
                powerstroke_sim::Scenario::load(&cfg.scenario_dir, &cfg.scenario)
                    .map_err(|e| format!("scenario: {e}"))?,
            ),
            TransportKind::Obdlink | TransportKind::Can => None,
        };
        let mut enable = cfg.enable.clone();
        let mut auto_enabled = Vec::new();
        if let Some(s) = &scenario {
            for id in s.signal_ids() {
                let id = id.to_string();
                if registry
                    .get(&id)
                    .is_some_and(|d| !d.enabled && !d.is_computed())
                    && !enable.contains(&id)
                {
                    auto_enabled.push(id.clone());
                    enable.push(id);
                }
            }
        }
        let registry = enable_signals(registry, &enable)?;
        let warnings_json = std::fs::read_to_string(&cfg.warnings)
            .map_err(|e| format!("{}: {e}", cfg.warnings.display()))?;
        let warnings =
            WarningConfig::from_json(&warnings_json).map_err(|e| format!("warning rules: {e}"))?;
        warnings
            .check_signals(&registry)
            .map_err(|e| format!("warning rules: {e}"))?;

        let epoch = Instant::now();
        let store = TelemetryStore::new(
            &registry,
            StoreConfig {
                rules: warnings.rules,
                watched_signals: warnings.comm_watch,
                ..StoreConfig::default()
            },
            Duration::ZERO,
        );
        let mut sched = Scheduler::new(cfg.budget(), PollPolicy::default());
        for d in registry.iter().filter(|d| !d.is_computed()) {
            if let Some(p) = &d.poll {
                sched.add(
                    &d.id,
                    p.priority,
                    Duration::from_millis(p.interval_ms),
                    d.enabled,
                    Duration::ZERO,
                );
            }
        }

        let (transport, driver_rx) = match cfg.transport {
            TransportKind::Sim => {
                let scenario = scenario.ok_or("scenario not loaded")?;
                let t = SimulatedTransport::new(
                    powerstroke_sim::ScenarioEngine::new(scenario),
                    cfg.sim_start_s * 1000,
                );
                (Transport::Sim(Box::new(t)), None)
            }
            TransportKind::Obdlink => {
                let spec = cfg
                    .adapter
                    .as_deref()
                    .ok_or("--adapter is required for --transport obdlink")?;
                let spec = LinkSpec::parse(spec)?;
                let traffic = match &cfg.traffic_log {
                    Some(dir) => Some(
                        TrafficLog::new(dir.clone()).map_err(|e| format!("traffic log: {e}"))?,
                    ),
                    None => None,
                };
                let elm = ElmConfig {
                    allowed_services: allow_list()?,
                    ..ElmConfig::default()
                };
                let (link, rx) = ObdLink::spawn(spec.connector(), elm, traffic)?;
                (Transport::Obd(link), Some(rx))
            }
            TransportKind::Can => {
                let traffic = match &cfg.traffic_log {
                    Some(dir) => Some(
                        TrafficLog::new(dir.clone()).map_err(|e| format!("traffic log: {e}"))?,
                    ),
                    None => None,
                };
                let opener = can_opener
                    .unwrap_or_else(|| crate::transport::can::socket::opener(cfg.can_if.clone()));
                let timing = CanTiming {
                    window: Duration::from_millis(cfg.can_window_ms),
                };
                let (link, rx) =
                    CanLink::spawn(cfg.can_if.clone(), opener, allow_list()?, timing, traffic);
                (Transport::Can(link), Some(rx))
            }
        };

        let (snapshot_tx, snapshot_rx) = watch::channel(Arc::new(pb::Snapshot::default()));
        let mut core = Core {
            cfg,
            registry,
            store,
            sched,
            link: LinkMachine::new(LinkPolicy::default(), epoch.elapsed().as_nanos() as u64 | 1),
            transport,
            epoch,
            events: EventLog::new(300),
            last_success: None,
            pause_until: Duration::ZERO,
            latencies: HashMap::new(),
            stats_since: Duration::ZERO,
            adapter_voltage: None,
            last_voltage_at: Duration::ZERO,
            snapshot_tx,
            heartbeat: Heartbeat::new(),
        };
        if !auto_enabled.is_empty() {
            core.log(
                EventSeverity::Info,
                format!(
                    "simulator: polling {} (nothing is transmitted)",
                    auto_enabled.join(", ")
                ),
            );
        }
        Ok((core, driver_rx, snapshot_rx))
    }

    fn now(&self) -> Duration {
        self.epoch.elapsed()
    }

    /// The control loop's progress counter, for the systemd watchdog
    /// (`f250_sd_notify::run_watchdog`). It stops when the loop is stuck or
    /// has ended.
    pub fn heartbeat(&self) -> Heartbeat {
        self.heartbeat.clone()
    }

    fn log(&mut self, severity: EventSeverity, message: impl Into<String>) {
        let at = self.now();
        let message = message.into();
        match severity {
            EventSeverity::Critical => eprintln!("[gateway] CRITICAL {message}"),
            EventSeverity::Advisory => eprintln!("[gateway] {message}"),
            EventSeverity::Info => {}
        }
        self.events.add(TelemetryEvent {
            at,
            severity,
            message,
        });
    }

    fn transmit_enabled(&self) -> bool {
        match self.transport {
            Transport::Sim(_) => true,
            Transport::Obd(_) | Transport::Can(_) => self.cfg.transmit,
        }
    }

    pub async fn run(
        mut self,
        mut cmds: mpsc::Receiver<Command>,
        mut driver: Option<mpsc::Receiver<DriverEvent>>,
    ) {
        let start = LinkEvent::Start {
            transmit_enabled: self.transmit_enabled(),
        };
        let action = self.link.handle(start, self.now());
        self.log_link_changes();
        if let Some(a) = action {
            self.act(a).await;
        }
        let mut next_snapshot = Duration::ZERO;
        let mut next_health = HEALTH_PERIOD;
        loop {
            self.heartbeat.beat();
            let now = self.now();
            if let Some(a) = self.link.tick(now) {
                self.log_link_changes();
                self.act(a).await;
            }
            while let Ok(c) = cmds.try_recv() {
                self.command(c).await;
            }
            if let Some(rx) = driver.as_mut() {
                while let Ok(ev) = rx.try_recv() {
                    self.driver_event(ev).await;
                }
            }
            let mut polled = false;
            if self.link.state().may_poll()
                && now >= self.pause_until
                && let Some(id) = self.sched.next(now)
            {
                self.poll(&id).await;
                polled = true;
            }
            let now = self.now();
            if now >= next_health {
                next_health = now + HEALTH_PERIOD;
                self.health(now).await;
            }
            if now >= next_snapshot {
                next_snapshot = now + SNAPSHOT_PERIOD;
                self.store.refresh(now);
                let snap = self.snapshot(now);
                let _ = self.snapshot_tx.send(Arc::new(snap));
            }
            if polled {
                continue;
            }
            // Sleep until something is due, a command arrives, or the driver reports.
            let wake = self
                .sched
                .next_due()
                .unwrap_or(now + SNAPSHOT_PERIOD)
                .max(self.pause_until)
                .min(next_snapshot)
                .min(next_health)
                .saturating_sub(now)
                .max(Duration::from_millis(5));
            tokio::select! {
                c = cmds.recv() => match c {
                    Some(c) => self.command(c).await,
                    None => return,
                },
                ev = async {
                    match driver.as_mut() {
                        Some(rx) => rx.recv().await,
                        None => std::future::pending().await,
                    }
                } => if let Some(ev) = ev { self.driver_event(ev).await },
                _ = tokio::time::sleep(wake) => {}
            }
        }
    }

    // ---- link machine -------------------------------------------------------

    fn log_link_changes(&mut self) {
        for c in self.link.take_changes() {
            let sev = match c.to {
                MachineState::Fault => EventSeverity::Critical,
                MachineState::Recovering(_) | MachineState::Backoff | MachineState::Degraded => {
                    EventSeverity::Advisory
                }
                _ => EventSeverity::Info,
            };
            self.log(
                sev,
                format!("link {} → {} ({})", c.from.as_str(), c.to.as_str(), c.why),
            );
        }
    }

    async fn link_event(&mut self, ev: LinkEvent) {
        let action = self.link.handle(ev, self.now());
        self.log_link_changes();
        if let Some(a) = action {
            Box::pin(self.act(a)).await;
        }
    }

    async fn act(&mut self, action: Action) {
        match (&self.transport, action) {
            (_, Action::RetryAt(_)) => {} // the machine's tick() fires it
            (Transport::Sim(sim), a) => {
                // The simulator has no adapter: connect/recover succeed iff the
                // scenario's link is up.
                let up = sim.link_up(self.now().as_millis() as u64);
                let ev = match a {
                    Action::Connect => {
                        if up {
                            LinkEvent::Connected
                        } else {
                            LinkEvent::ConnectFailed
                        }
                    }
                    Action::InitAdapter => LinkEvent::InitOk,
                    Action::Recover(_) => {
                        if up {
                            LinkEvent::RecoveryOk
                        } else {
                            LinkEvent::RecoveryFailed
                        }
                    }
                    Action::RetryAt(_) => return,
                };
                self.link_event(ev).await;
            }
            (Transport::Obd(link), a) => {
                let link = link.clone();
                match a {
                    Action::Connect => link.connect().await, // → DriverEvent::Connected/ConnectFailed
                    Action::InitAdapter => {} // the driver resets the adapter on connect
                    Action::Recover(RecoveryStep::Soft) => {
                        // Is the adapter itself alive? ATRV talks only to the adapter.
                        let ev = match link.voltage().await {
                            Some(v) => {
                                self.adapter_voltage = Some(f64::from(v));
                                LinkEvent::RecoveryOk
                            }
                            None => LinkEvent::RecoveryFailed,
                        };
                        Box::pin(self.link_event(ev)).await;
                    }
                    Action::Recover(RecoveryStep::Reset) => link.reset().await, // → Ready / AdapterOffline
                    Action::Recover(RecoveryStep::Reconnect) => {
                        link.disconnect().await;
                        link.connect().await;
                    }
                    Action::RetryAt(_) => {}
                }
            }
            (Transport::Can(link), a) => {
                let link = link.clone();
                match a {
                    Action::Connect => link.connect().await, // → Connected + Ready / ConnectFailed
                    Action::InitAdapter => {}                // nothing to initialise
                    Action::Recover(RecoveryStep::Soft) => {
                        // Socket open and interface up? Sends nothing.
                        let ev = if link.check().await {
                            LinkEvent::RecoveryOk
                        } else {
                            LinkEvent::RecoveryFailed
                        };
                        Box::pin(self.link_event(ev)).await;
                    }
                    Action::Recover(RecoveryStep::Reset | RecoveryStep::Reconnect) => {
                        link.reset().await; // reopen the socket → Ready / ConnectFailed
                    }
                    Action::RetryAt(_) => {}
                }
            }
        }
    }

    async fn driver_event(&mut self, ev: DriverEvent) {
        let recovering = matches!(self.link.state(), MachineState::Recovering(_));
        match ev {
            DriverEvent::Connected => {
                if !recovering {
                    self.link_event(LinkEvent::Connected).await;
                }
            }
            DriverEvent::ConnectFailed(why) => {
                self.log(
                    EventSeverity::Advisory,
                    format!("adapter connect failed: {why}"),
                );
                let e = if recovering {
                    LinkEvent::RecoveryFailed
                } else {
                    LinkEvent::ConnectFailed
                };
                self.link_event(e).await;
            }
            DriverEvent::Ready { adapter_id } => {
                self.log(
                    EventSeverity::Info,
                    format!(
                        "adapter ready: {}",
                        adapter_id.unwrap_or_else(|| "unknown".into())
                    ),
                );
                let e = if recovering {
                    LinkEvent::RecoveryOk
                } else {
                    LinkEvent::InitOk
                };
                self.link_event(e).await;
            }
            DriverEvent::Disconnected(why) => {
                self.log(
                    EventSeverity::Advisory,
                    format!("adapter disconnected: {why}"),
                );
                self.link_event(LinkEvent::Disconnected).await;
            }
            DriverEvent::AdapterOffline => {
                self.log(
                    EventSeverity::Advisory,
                    "adapter stopped answering (ELM recovery gave up)",
                );
                let e = if recovering {
                    LinkEvent::RecoveryFailed
                } else {
                    LinkEvent::Disconnected
                };
                self.link_event(e).await;
            }
            DriverEvent::AdapterAlert(line) => {
                self.log(EventSeverity::Advisory, format!("adapter says: {line}"));
            }
            DriverEvent::Note(note) => self.log(EventSeverity::Info, note),
        }
    }

    async fn health(&mut self, now: Duration) {
        let ids: Vec<String> = self.sched.ids().map(str::to_string).collect();
        let mut active = 0;
        let mut failing = 0;
        for id in &ids {
            match self.sched.state_of(id) {
                Some(crate::poll::PollState::Off) | None => {}
                Some(crate::poll::PollState::Active) => active += 1,
                Some(_) => {
                    active += 1;
                    failing += 1;
                }
            }
        }
        let silent = now.saturating_sub(
            self.last_success
                .unwrap_or(self.link.since())
                .max(self.link.since()),
        );
        self.link_event(LinkEvent::Health {
            active,
            failing,
            all_silent_for: silent,
        })
        .await;

        // Adapter supply voltage (ATRV), only while the link is healthy.
        if let Transport::Obd(link) = &self.transport
            && self.cfg.voltage_every_s > 0
            && self.link.state().may_poll()
            && now >= self.last_voltage_at + Duration::from_secs(self.cfg.voltage_every_s)
        {
            let link = link.clone();
            self.last_voltage_at = now;
            self.adapter_voltage = link.voltage().await.map(f64::from);
        }
    }

    // ---- polling ------------------------------------------------------------

    async fn request(&mut self, id: &str) -> Outcome {
        let Some(def) = self.registry.get(id) else {
            return Outcome::Refused {
                reason: format!("unknown signal {id}"),
            };
        };
        match &self.transport {
            Transport::Sim(sim) => {
                let outcome = sim.request(id, self.now().as_millis() as u64);
                // Model the adapter's round trip so throughput is realistic.
                if let Some(ms) = outcome.latency_ms() {
                    tokio::time::sleep(Duration::from_millis(u64::from(ms))).await;
                }
                outcome
            }
            Transport::Obd(link) => {
                if !self.cfg.transmit {
                    return Outcome::Refused {
                        reason: "transmit disabled (--transmit not given)".into(),
                    };
                }
                match obd_request(def) {
                    Ok(req) => link.clone().request(req).await,
                    Err(reason) => Outcome::Refused { reason },
                }
            }
            Transport::Can(link) => {
                if !self.cfg.transmit {
                    return Outcome::Refused {
                        reason: "transmit disabled (--transmit not given)".into(),
                    };
                }
                match obd_request(def) {
                    Ok(req) => link.clone().request(req).await,
                    Err(reason) => Outcome::Refused { reason },
                }
            }
        }
    }

    /// Turns a transport outcome into the telemetry outcome, decoding
    /// payloads with the registry formula.
    fn decode(&self, def: &SignalDef, outcome: &Outcome) -> TOutcome {
        let lookup = |id: &str| self.store.value(id);
        match outcome {
            Outcome::Value { value, .. } => TOutcome::Response(*value),
            Outcome::Payload { responders, .. } => match responders.first() {
                Some(r) => match def.decode_payload(&r.payload, &lookup) {
                    Ok(v) => TOutcome::Response(v),
                    Err(_) => TOutcome::InvalidResponse,
                },
                None => TOutcome::InvalidResponse,
            },
            Outcome::NoResponse { .. } => TOutcome::NoResponse,
            Outcome::Negative { nrc, .. } => TOutcome::NegativeResponse { nrc: *nrc },
            Outcome::Invalid { .. } => TOutcome::InvalidResponse,
            Outcome::LinkDown => TOutcome::LinkDown,
            Outcome::Refused { .. } => TOutcome::NoResponse,
        }
    }

    async fn poll(&mut self, id: &str) {
        let outcome = self.request(id).await;
        self.record(id, &outcome);
    }

    fn record(&mut self, id: &str, outcome: &Outcome) {
        let now = self.now();
        let Some(def) = self.registry.get(id).cloned() else {
            return;
        };
        if let Outcome::Refused { reason } = outcome {
            // Never retry something the gateway itself refuses: quarantine it.
            self.log(
                EventSeverity::Advisory,
                format!("{id}: request refused: {reason}"),
            );
            if let Some(t) = self.sched.record_miss(id, Miss::Unsupported, now) {
                self.log(
                    EventSeverity::Info,
                    format!("{id}: {} → {}", t.from.as_str(), t.to.as_str()),
                );
            }
            return;
        }
        if *outcome == Outcome::LinkDown {
            self.store.set_source_link_down(true);
            self.pause_until = now + LINK_DOWN_POLL_PAUSE;
            return;
        }
        self.store.set_source_link_down(false);
        let t_outcome = self.decode(&def, outcome);
        let responder = match outcome {
            Outcome::Payload { responders, .. } => responders
                .first()
                .and_then(|r| u32::from_str_radix(&r.can_id, 16).ok()),
            _ => None,
        };
        let mut result = PollResult::new(id, now, t_outcome);
        result.latency_ms = outcome.latency_ms();
        result.responder = responder;
        self.store.apply(&result);
        if let Some(ms) = outcome.latency_ms() {
            let ring = self.latencies.entry(id.to_string()).or_default();
            if ring.len() >= 64 {
                ring.pop_front();
            }
            ring.push_back(ms);
        }
        let transition = match t_outcome {
            TOutcome::Response(_) => {
                self.last_success = Some(now);
                self.sched.record_success(id, now)
            }
            TOutcome::NoResponse => self.sched.record_miss(id, Miss::NoResponse, now),
            TOutcome::InvalidResponse => self.sched.record_miss(id, Miss::Invalid, now),
            TOutcome::NegativeResponse { nrc } => {
                // The module answered: the link itself is alive.
                self.last_success = Some(now);
                let miss = if nrc_means_unsupported(nrc) {
                    Miss::Unsupported
                } else {
                    Miss::Refused
                };
                self.sched.record_miss(id, miss, now)
            }
            TOutcome::LinkDown => None,
        };
        if let Some(t) = transition {
            let sev = if t.to == crate::poll::PollState::Active {
                EventSeverity::Info
            } else {
                EventSeverity::Advisory
            };
            self.log(
                sev,
                format!(
                    "{id}: {} → {} ({})",
                    t.from.as_str(),
                    t.to.as_str(),
                    t.reason
                ),
            );
        }
    }

    // ---- commands -----------------------------------------------------------

    async fn command(&mut self, c: Command) {
        match c {
            Command::ListSignals(reply) => {
                let defs = self.registry.iter().map(|d| self.definition(d)).collect();
                let _ = reply.send(Ok(defs));
            }
            Command::ListEvents(limit, reply) => {
                let _ = reply.send(Ok(self.list_events(limit)));
            }
            Command::SetCalibration {
                id,
                scale,
                offset,
                reply,
            } => {
                let result = Calibration::new(scale, offset, None)
                    .map_err(|e| e.to_string())
                    .and_then(|c| {
                        self.store
                            .set_calibration(&id, c, self.now())
                            .map_err(|e| e.to_string())
                    })
                    .and_then(|()| {
                        self.registry
                            .get(&id)
                            .map(|d| self.definition(d))
                            .ok_or_else(|| format!("unknown signal {id}"))
                    });
                if result.is_ok() {
                    self.log(
                        EventSeverity::Info,
                        format!("{id}: calibration ×{scale:.4} {offset:+}"),
                    );
                }
                let _ = reply.send(result);
            }
            Command::SetPolling { id, enabled, reply } => {
                let result = match self.registry.get(&id) {
                    None => Err(format!("unknown signal {id}")),
                    Some(d) if d.is_computed() => {
                        Err(format!("{id} is computed; enable its inputs"))
                    }
                    Some(d) if enabled && !d.enabled => Err(format!(
                        "{id} is disabled in the registry ({}); restart the gateway with --enable {id} to opt in",
                        d.provenance
                    )),
                    Some(_) => {
                        let now = self.now();
                        if let Some(t) = self.sched.set_enabled(&id, enabled, now) {
                            self.log(
                                EventSeverity::Info,
                                format!("{id}: {} → {}", t.from.as_str(), t.to.as_str()),
                            );
                        }
                        Ok(())
                    }
                };
                let _ = reply.send(result);
            }
            Command::Probe { id, count, reply } => {
                let result = self.probe(&id, count.clamp(1, 20)).await;
                let _ = reply.send(result);
            }
            Command::Raw { line, reply } => {
                let result = match &self.transport {
                    Transport::Sim(_) => Ok(pb::RawResponse {
                        refused: "the simulated transport has no adapter".into(),
                        ..Default::default()
                    }),
                    Transport::Obd(_) | Transport::Can(_) if !self.cfg.transmit => {
                        Ok(pb::RawResponse {
                            refused: "transmit disabled (--transmit not given)".into(),
                            ..Default::default()
                        })
                    }
                    Transport::Obd(link) => {
                        let link = link.clone();
                        let raw = link.raw(line.clone()).await;
                        Ok(self.raw_response(&line, raw))
                    }
                    Transport::Can(link) => {
                        let link = link.clone();
                        let raw = link.raw(line.clone()).await;
                        Ok(self.raw_response(&line, raw))
                    }
                };
                let _ = reply.send(result);
            }
            Command::Stats { reset, reply } => {
                let _ = reply.send(Ok(self.stats(reset)));
            }
        }
    }

    fn raw_response(&mut self, line: &str, raw: RawOutcome) -> pb::RawResponse {
        let RawOutcome {
            lines,
            latency_ms,
            refused,
        } = raw;
        self.log(
            EventSeverity::Info,
            format!("raw {line} → {} line(s)", lines.len()),
        );
        pb::RawResponse {
            lines,
            latency_ms,
            refused: refused.unwrap_or_default(),
        }
    }

    async fn probe(&mut self, id: &str, count: u32) -> Result<pb::ProbeResponse, String> {
        let def = self
            .registry
            .get(id)
            .cloned()
            .ok_or_else(|| format!("unknown signal {id}"))?;
        if def.is_computed() {
            return Err(format!("{id} is computed; probe its inputs"));
        }
        let mut attempts = Vec::new();
        for _ in 0..count {
            // Up to 20 requests in one command: each one counts as progress,
            // so a long probe isn't mistaken for a stuck loop.
            self.heartbeat.beat();
            let outcome = self.request(id).await;
            self.record(id, &outcome);
            let lookup = |sid: &str| self.store.value(sid);
            let (name, nrc, detail) = match &outcome {
                Outcome::Payload { .. } | Outcome::Value { .. } => ("ok", 0, String::new()),
                Outcome::NoResponse { .. } => ("no_response", 0, String::new()),
                Outcome::Negative { nrc, .. } => ("negative", u32::from(*nrc), String::new()),
                Outcome::Invalid { detail, .. } => ("invalid", 0, detail.clone()),
                Outcome::LinkDown => ("link_down", 0, String::new()),
                Outcome::Refused { reason } => ("refused", 0, reason.clone()),
            };
            let responders = match &outcome {
                Outcome::Payload { responders, .. } => responders
                    .iter()
                    .map(|ResponderPayload { can_id, payload }| pb::Responder {
                        can_id: can_id.clone(),
                        payload_hex: format_bytes(payload),
                        decoded: def.decode_payload(payload, &lookup).ok(),
                    })
                    .collect(),
                Outcome::Value { value, .. } => {
                    vec![pb::Responder {
                        can_id: "SIM".into(),
                        payload_hex: String::new(),
                        decoded: Some(*value),
                    }]
                }
                _ => vec![],
            };
            attempts.push(pb::ProbeAttempt {
                outcome: name.into(),
                latency_ms: outcome.latency_ms().unwrap_or(0),
                responders,
                nrc,
                detail,
            });
        }
        Ok(pb::ProbeResponse { attempts })
    }

    fn stats(&mut self, reset: bool) -> pb::StatsResponse {
        let now = self.now();
        let window_ms = now.saturating_sub(self.stats_since).as_millis() as u64;
        let signals = self
            .registry
            .iter()
            .filter(|d| !d.is_computed())
            .map(|d| {
                let st = self.store.get(&d.id);
                let mut lat: Vec<u32> = self
                    .latencies
                    .get(&d.id)
                    .map(|r| r.iter().copied().collect())
                    .unwrap_or_default();
                lat.sort_unstable();
                let pct = |p: f64| {
                    lat.get(((lat.len() as f64 - 1.0) * p).round() as usize)
                        .copied()
                        .unwrap_or(0)
                };
                pb::SignalStats {
                    signal_id: d.id.clone(),
                    successes: st.map(|s| s.successes).unwrap_or(0),
                    failures: st.map(|s| s.failures).unwrap_or(0),
                    latency_p50_ms: pct(0.5),
                    latency_p95_ms: pct(0.95),
                    poll_state: self
                        .sched
                        .state_of(&d.id)
                        .map(|s| s.as_str())
                        .unwrap_or("-")
                        .into(),
                    interval_ms: self
                        .sched
                        .interval_of(&d.id)
                        .map(|i| i.as_millis() as u32)
                        .unwrap_or(0),
                }
            })
            .collect();
        let rps = self.store.requests_per_second(now);
        if reset {
            self.latencies.clear();
            self.stats_since = now;
        }
        pb::StatsResponse {
            requests_per_second: rps,
            signals,
            window_ms,
        }
    }

    fn list_events(&self, limit: u32) -> pb::ListEventsResponse {
        let now = self.now();
        let wall_now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0);
        let mut all: Vec<&TelemetryEvent> = self
            .events
            .newest_first()
            .chain(self.store.events().newest_first())
            .collect();
        all.sort_by_key(|e| std::cmp::Reverse(e.at));
        let limit = if limit == 0 { 100 } else { limit as usize };
        pb::ListEventsResponse {
            events: all
                .into_iter()
                .take(limit)
                .map(|e| pb::Event {
                    mono_ms: e.at.as_millis() as u64,
                    wall_ms: wall_now - now.saturating_sub(e.at).as_millis() as i64,
                    severity: match e.severity {
                        EventSeverity::Critical => pb::EventSeverity::Critical,
                        EventSeverity::Advisory => pb::EventSeverity::Advisory,
                        EventSeverity::Info => pb::EventSeverity::Info,
                    } as i32,
                    message: e.message.clone(),
                })
                .collect(),
            dropped: self.events.dropped() + self.store.events().dropped(),
        }
    }

    // ---- API views ----------------------------------------------------------

    fn definition(&self, d: &SignalDef) -> pb::SignalDefinition {
        let cal = self.store.calibration_of(&d.id);
        pb::SignalDefinition {
            id: d.id.clone(),
            name: d.name.clone(),
            short_name: d.short_name.clone(),
            quantity: quantity(d.quantity) as i32,
            unit: d.unit.to_string(),
            provenance: provenance(d.provenance) as i32,
            min: d.range.min,
            max: d.range.max,
            stale_after_ms: d.stale_after.map(|s| s.as_millis() as u32).unwrap_or(0),
            request: d
                .request
                .as_ref()
                .map(|r| format_bytes(&r.payload))
                .unwrap_or_default(),
            responder: d
                .request
                .as_ref()
                .and_then(|r| r.rx_id)
                .map(|id| format!("{id:03X}"))
                .unwrap_or_default(),
            evidence: d.evidence.clone().unwrap_or_default(),
            enabled: d.enabled,
            disabled_reason: if d.enabled {
                String::new()
            } else {
                d.notes.clone().unwrap_or_default()
            },
            inputs: d.inputs.clone(),
            calibration_scale: cal.scale(),
            calibration_offset: cal.offset(),
        }
    }

    fn snapshot(&mut self, now: Duration) -> pb::Snapshot {
        let samples = self
            .store
            .ordered()
            .map(|s| pb::Sample {
                signal_id: s.def.id.clone(),
                validity: validity(s.validity) as i32,
                value: if s.validity == Validity::Valid {
                    s.value
                } else {
                    None
                },
                last_good_value: s.last_good_value,
                last_good_raw: s.last_good_raw,
                last_good_age_ms: s.age_at(now).map(|a| a.as_millis() as u64),
                rejected_value: s.last_rejected_value,
                last_nrc: s.last_nrc.map(u32::from).unwrap_or(0),
                last_responder: s
                    .last_responder
                    .map(|r| format!("{r:03X}"))
                    .unwrap_or_default(),
                last_latency_ms: s.last_latency_ms.unwrap_or(0),
                successes: s.successes,
                failures: s.failures,
                consecutive_failures: s.consecutive_failures.min(u64::from(u32::MAX)) as u32,
                invalid_inputs: s.invalid_inputs.clone(),
                poll_state: self
                    .sched
                    .state_of(&s.def.id)
                    .map(|p| p.as_str())
                    .unwrap_or("")
                    .into(),
            })
            .collect();
        let alerts = self
            .store
            .alerts()
            .iter()
            .map(|a| pb::Alert {
                id: a.id.clone(),
                kind: match a.kind {
                    AlertKind::Threshold => pb::AlertKind::Threshold,
                    AlertKind::SignalNotUpdating => pb::AlertKind::SignalNotUpdating,
                    AlertKind::LinkLost => pb::AlertKind::LinkLost,
                } as i32,
                level: match a.level {
                    AlertLevel::Critical => pb::AlertLevel::Critical,
                    _ => pb::AlertLevel::Advisory,
                } as i32,
                since_mono_ms: a.since.as_millis() as u64,
                signal_id: a.signal_id.clone().unwrap_or_default(),
                rule_id: a.rule_id.clone().unwrap_or_default(),
                threshold: a.threshold.unwrap_or(0.0),
                above: a.direction != Some(Direction::Below),
            })
            .collect();
        let (transport, simulated, scenario, scenario_seconds) = match &self.transport {
            Transport::Sim(sim) => (
                "simulated".to_string(),
                true,
                sim.scenario_name().to_string(),
                sim.scenario_seconds(now.as_millis() as u64),
            ),
            Transport::Obd(_) => ("obdlink".to_string(), false, String::new(), 0.0),
            Transport::Can(link) => (format!("can:{}", link.interface), false, String::new(), 0.0),
        };
        let rps = self.store.requests_per_second(now);
        let load = self.sched.load();
        pb::Snapshot {
            mono_ms: now.as_millis() as u64,
            samples,
            alerts,
            link: Some(pb::LinkStatus {
                state: match self.store.link() {
                    LinkState::Connecting => pb::LinkState::Connecting,
                    LinkState::Up => pb::LinkState::Up,
                    LinkState::Degraded => pb::LinkState::Degraded,
                    LinkState::Down => pb::LinkState::Down,
                } as i32,
                since_mono_ms: self.store.link_since().as_millis() as u64,
                transport,
                simulated,
                transmit_enabled: self.transmit_enabled(),
                requests_per_second: rps,
                machine_state: self.link.state().as_str().into(),
                detail: if load.oversubscribed() {
                    format!(
                        "polling asks {:.1} req/s of a {:.1} req/s link: low priorities stretched",
                        load.demand_rps, load.budget_rps
                    )
                } else {
                    String::new()
                },
                adapter_voltage: self.adapter_voltage,
                scenario,
                scenario_seconds,
            }),
        }
    }
}

const LINK_DOWN_POLL_PAUSE: Duration = LINK_DOWN_PAUSE;

/// ADR-0007 read-service allow-list, the same set the registry enforces.
fn allow_list() -> Result<ServiceAllowList, String> {
    ServiceAllowList::new(f250_telemetry::registry::ALLOWED_SERVICES.iter().copied())
        .map_err(|e| e.to_string())
}

/// `--enable`: opt unverified signals into polling (they stay marked
/// IMPORTED_UNVERIFIED everywhere they are shown).
fn enable_signals(registry: Registry, ids: &[String]) -> Result<Registry, String> {
    if ids.is_empty() {
        return Ok(registry);
    }
    let mut defs = registry.into_defs();
    for id in ids {
        let d = defs
            .iter_mut()
            .find(|d| &d.id == id)
            .ok_or_else(|| format!("--enable: unknown signal {id}"))?;
        if d.is_computed() {
            return Err(format!("--enable: {id} is computed; enable its inputs"));
        }
        d.enabled = true;
        if d.provenance == Provenance::ImportedUnverified {
            d.allow_unverified = true;
        }
    }
    Registry::from_defs(defs).map_err(|e| format!("--enable: {e}"))
}

/// Builds the ELM request for a registry signal. Refuses anything the
/// registry can't express unambiguously.
pub fn obd_request(def: &SignalDef) -> Result<ObdRequest, String> {
    let req = def
        .request
        .as_ref()
        .ok_or_else(|| format!("{} has no request", def.id))?;
    let command = match req.payload.as_slice() {
        [0x01, pid] => ObdCommand::mode01(*pid),
        [0x22, hi, lo] => ObdCommand::did(u16::from_be_bytes([*hi, *lo])),
        other => {
            return Err(format!(
                "{}: unsupported request {}",
                def.id,
                format_bytes(other)
            ));
        }
    };
    let addressing = if req.tx_id == 0x7DF {
        Addressing::functional()
    } else {
        Addressing::header(format!("{:03X}", req.tx_id), None)
    };
    let mut r = ObdRequest::new(command).with_addressing(addressing);
    if let Some(rx) = req.rx_id {
        let rx =
            u16::try_from(rx).map_err(|_| format!("{}: responder {rx:X} is not 11-bit", def.id))?;
        r = r.with_expected_responder(rx);
    }
    if let Some(p) = &def.poll {
        r = r.with_timeout_ms(p.timeout_ms);
    }
    Ok(r)
}

fn quantity(q: Quantity) -> pb::Quantity {
    match q {
        Quantity::Temperature => pb::Quantity::Temperature,
        Quantity::TemperatureDelta => pb::Quantity::TemperatureDelta,
        Quantity::Pressure => pb::Quantity::Pressure,
        Quantity::Voltage => pb::Quantity::Voltage,
        Quantity::Speed => pb::Quantity::Speed,
        Quantity::Rotation => pb::Quantity::Rotation,
        Quantity::Percent => pb::Quantity::Percent,
    }
}

fn provenance(p: Provenance) -> pb::Provenance {
    match p {
        Provenance::Sae => pb::Provenance::Sae,
        Provenance::VerifiedOnTruck => pb::Provenance::VerifiedOnTruck,
        Provenance::ImportedUnverified => pb::Provenance::ImportedUnverified,
        Provenance::Computed => pb::Provenance::Computed,
        Provenance::AuxSensor => pb::Provenance::AuxSensor,
        #[allow(unreachable_patterns)]
        _ => pb::Provenance::BroadcastDecoded,
    }
}

fn validity(v: Validity) -> pb::Validity {
    match v {
        Validity::Valid => pb::Validity::Valid,
        Validity::Stale => pb::Validity::Stale,
        Validity::NoData => pb::Validity::NoData,
        Validity::OutOfRange => pb::Validity::OutOfRange,
        Validity::DecodeError => pb::Validity::DecodeError,
        Validity::Unsupported => pb::Validity::Unsupported,
        Validity::Disabled => pb::Validity::Disabled,
    }
}
