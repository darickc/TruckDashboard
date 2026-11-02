//! OBDLink MX+ (ELM327/STN) transport: an async driver that owns the
//! sans-IO [`f250_elm::ElmClient`] and one byte stream to the adapter.
//!
//! Streams:
//! - **serial**: a serial device, e.g. the MX+ as a macOS Bluetooth serial
//!   port (`/dev/cu.*`) or the ESP32 as a USB bridge.
//! - **tcp**: `host:port`, for adapters or emulators that speak ELM over TCP.
//! - **rfcomm** (Linux, `--features rfcomm`): BlueZ RFCOMM straight to the
//!   MX+ (Phase 3.5). The adapter must already be paired (`bluetoothctl`).
//!
//! The gateway's link machine (crate::link) decides when to connect, reset
//! or reconnect; the ELM client's own ladder (bare CR → ATZ → offline)
//! handles adapter-level timeouts underneath. Everything the ELM client
//! refuses (ADR-0007 allow-list, unverified headers) is refused here too:
//! nothing reaches the stream without passing it.

use std::io;
use std::pin::Pin;
use std::sync::Arc;
use std::time::{Duration, Instant};

use f250_elm::{
    ElmClient, ElmConfig, ElmEvent, ElmResult, ElmState, ErrorCause, ObdRequest, Request, RequestId,
};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::sync::{mpsc, oneshot};

use super::{Outcome, ResponderPayload};

/// A bidirectional byte stream to the adapter.
pub trait ByteStream: AsyncRead + AsyncWrite + Unpin + Send {}
impl<T: AsyncRead + AsyncWrite + Unpin + Send> ByteStream for T {}

pub type BoxStream = Box<dyn ByteStream>;
type ConnectFuture = Pin<Box<dyn std::future::Future<Output = io::Result<BoxStream>> + Send>>;

/// Opens a fresh stream to the adapter (called on every connect/reconnect).
pub type Connector = Arc<dyn Fn() -> ConnectFuture + Send + Sync>;

/// Where the adapter is.
#[derive(Debug, Clone, PartialEq)]
pub enum LinkSpec {
    Serial {
        path: String,
        baud: u32,
    },
    Tcp {
        addr: String,
    },
    /// Bluetooth address (e.g. "00:04:3E:85:EA:FC") and RFCOMM channel.
    Rfcomm {
        address: String,
        channel: u8,
    },
}

impl LinkSpec {
    /// `serial:/dev/cu.OBDLinkMX[@115200]`, `tcp:host:port`,
    /// `rfcomm:00:04:3E:85:EA:FC[/1]`.
    pub fn parse(s: &str) -> Result<Self, String> {
        if let Some(rest) = s.strip_prefix("serial:") {
            let (path, baud) = match rest.rsplit_once('@') {
                Some((p, b)) => (p, b.parse().map_err(|_| format!("bad baud rate in {s}"))?),
                None => (rest, 115_200),
            };
            return Ok(LinkSpec::Serial {
                path: path.to_string(),
                baud,
            });
        }
        if let Some(addr) = s.strip_prefix("tcp:") {
            return Ok(LinkSpec::Tcp {
                addr: addr.to_string(),
            });
        }
        if let Some(rest) = s.strip_prefix("rfcomm:") {
            let (address, channel) = match rest.split_once('/') {
                Some((a, c)) => (
                    a,
                    c.parse()
                        .map_err(|_| format!("bad RFCOMM channel in {s}"))?,
                ),
                None => (rest, 1),
            };
            return Ok(LinkSpec::Rfcomm {
                address: address.to_string(),
                channel,
            });
        }
        Err(format!("adapter must be serial:, tcp: or rfcomm:, got {s}"))
    }

    pub fn connector(&self) -> Connector {
        let spec = self.clone();
        Arc::new(move || {
            let spec = spec.clone();
            Box::pin(async move { open(&spec).await })
        })
    }
}

async fn open(spec: &LinkSpec) -> io::Result<BoxStream> {
    match spec {
        LinkSpec::Tcp { addr } => Ok(Box::new(tokio::net::TcpStream::connect(addr).await?)),
        LinkSpec::Serial { path, baud } => {
            use tokio_serial::SerialPortBuilderExt;
            let port = tokio_serial::new(path, *baud)
                .open_native_async()
                .map_err(io::Error::other)?;
            Ok(Box::new(port))
        }
        LinkSpec::Rfcomm { address, channel } => rfcomm::open(address, *channel).await,
    }
}

#[cfg(all(target_os = "linux", feature = "rfcomm"))]
mod rfcomm {
    use super::{BoxStream, io};

    pub async fn open(address: &str, channel: u8) -> io::Result<BoxStream> {
        let addr: bluer::Address = address
            .parse()
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, format!("{e}")))?;
        let stream =
            bluer::rfcomm::Stream::connect(bluer::rfcomm::SocketAddr::new(addr, channel)).await?;
        Ok(Box::new(stream))
    }
}

#[cfg(not(all(target_os = "linux", feature = "rfcomm")))]
mod rfcomm {
    use super::{BoxStream, io};

    pub async fn open(_address: &str, _channel: u8) -> io::Result<BoxStream> {
        Err(io::Error::new(
            io::ErrorKind::Unsupported,
            "RFCOMM needs Linux and the `rfcomm` feature; on macOS pair the MX+ and use serial:/dev/cu.*",
        ))
    }
}

/// What the driver reports to the gateway core.
#[derive(Debug, Clone, PartialEq)]
pub enum DriverEvent {
    Connected,
    ConnectFailed(String),
    Disconnected(String),
    /// Reset and init done (`ATZ` banner).
    Ready {
        adapter_id: Option<String>,
    },
    /// The ELM client's own ladder gave up (state Offline): reconnect.
    AdapterOffline,
    /// STN chatter (`LV RESET`, `ACT ALERT`, `SLEEPING`, ...).
    AdapterAlert(String),
    /// Anything worth a log line: init failures, recovery steps, stray lines.
    Note(String),
}

/// Raw console result.
#[derive(Debug, Clone, PartialEq)]
pub struct RawOutcome {
    pub lines: Vec<String>,
    pub latency_ms: u32,
    pub refused: Option<String>,
}

enum Cmd {
    Connect,
    Disconnect,
    Reset,
    Obd(ObdRequest, oneshot::Sender<Outcome>),
    Raw(String, oneshot::Sender<RawOutcome>),
    Voltage(oneshot::Sender<Option<f32>>),
}

/// Handle to the driver task.
#[derive(Clone)]
pub struct ObdLink {
    cmd: mpsc::Sender<Cmd>,
}

impl ObdLink {
    /// Spawns the driver. It stays disconnected until [`ObdLink::connect`].
    pub fn spawn(
        connector: Connector,
        config: ElmConfig,
    ) -> Result<(Self, mpsc::Receiver<DriverEvent>), String> {
        let elm = ElmClient::new(config).map_err(|e| format!("{e}"))?;
        let (cmd_tx, cmd_rx) = mpsc::channel(32);
        let (ev_tx, ev_rx) = mpsc::channel(256);
        tokio::spawn(Driver::new(elm, connector, cmd_rx, ev_tx).run());
        Ok((ObdLink { cmd: cmd_tx }, ev_rx))
    }

    pub async fn connect(&self) {
        let _ = self.cmd.send(Cmd::Connect).await;
    }

    pub async fn disconnect(&self) {
        let _ = self.cmd.send(Cmd::Disconnect).await;
    }

    /// `ATZ` and the full init sequence.
    pub async fn reset(&self) {
        let _ = self.cmd.send(Cmd::Reset).await;
    }

    pub async fn request(&self, req: ObdRequest) -> Outcome {
        let (tx, rx) = oneshot::channel();
        if self.cmd.send(Cmd::Obd(req, tx)).await.is_err() {
            return Outcome::LinkDown;
        }
        rx.await.unwrap_or(Outcome::LinkDown)
    }

    pub async fn raw(&self, line: String) -> RawOutcome {
        let (tx, rx) = oneshot::channel();
        let gone = RawOutcome {
            lines: vec![],
            latency_ms: 0,
            refused: Some("adapter driver stopped".into()),
        };
        if self.cmd.send(Cmd::Raw(line, tx)).await.is_err() {
            return gone;
        }
        rx.await.unwrap_or(gone)
    }

    /// `ATRV`: the adapter's supply voltage (DLC pin 16), if it answered.
    pub async fn voltage(&self) -> Option<f32> {
        let (tx, rx) = oneshot::channel();
        self.cmd.send(Cmd::Voltage(tx)).await.ok()?;
        rx.await.ok().flatten()
    }
}

enum Pending {
    Obd(oneshot::Sender<Outcome>),
    Raw(oneshot::Sender<RawOutcome>, Vec<String>),
    Voltage(oneshot::Sender<Option<f32>>),
}

struct Driver {
    elm: ElmClient,
    connector: Connector,
    cmds: mpsc::Receiver<Cmd>,
    events: mpsc::Sender<DriverEvent>,
    stream: Option<BoxStream>,
    epoch: Instant,
    /// The one request in flight (the ELM is half-duplex).
    pending: Option<(RequestId, Pending)>,
}

impl Driver {
    fn new(
        elm: ElmClient,
        connector: Connector,
        cmds: mpsc::Receiver<Cmd>,
        events: mpsc::Sender<DriverEvent>,
    ) -> Self {
        Driver {
            elm,
            connector,
            cmds,
            events,
            stream: None,
            epoch: Instant::now(),
            pending: None,
        }
    }

    fn now(&self) -> u64 {
        self.epoch.elapsed().as_millis() as u64
    }

    async fn run(mut self) {
        let mut buf = [0u8; 512];
        loop {
            let deadline = self
                .elm
                .next_deadline()
                .map(|d| d.saturating_sub(self.now()));
            let sleep = tokio::time::sleep(Duration::from_millis(deadline.unwrap_or(1000)));
            tokio::select! {
                cmd = self.cmds.recv() => match cmd {
                    None => return, // every handle dropped
                    Some(c) => self.command(c).await,
                },
                read = async {
                    match self.stream.as_mut() {
                        Some(s) => s.read(&mut buf).await,
                        None => std::future::pending().await,
                    }
                } => match read {
                    Ok(0) => self.lost("adapter closed the connection").await,
                    Ok(n) => { let now = self.now(); self.elm.receive(&buf[..n], now); }
                    Err(e) => self.lost(&format!("read failed: {e}")).await,
                },
                _ = sleep => {}
            }
            let now = self.now();
            self.elm.tick(now);
            self.flush().await;
            self.drain_events().await;
        }
    }

    async fn command(&mut self, c: Cmd) {
        let now = self.now();
        match c {
            Cmd::Connect => {
                self.stream = None;
                match (self.connector)().await {
                    Ok(s) => {
                        self.stream = Some(s);
                        {
                            let _ = self.events.send(DriverEvent::Connected).await;
                        };
                        self.elm.begin(self.now());
                    }
                    Err(e) => {
                        let _ = self
                            .events
                            .send(DriverEvent::ConnectFailed(e.to_string()))
                            .await;
                    }
                }
            }
            Cmd::Disconnect => {
                self.stream = None;
                self.elm.transport_lost(now);
                self.fail_pending(Outcome::LinkDown);
            }
            Cmd::Reset => {
                if self.stream.is_some() {
                    self.elm.begin(now);
                }
            }
            Cmd::Obd(req, reply) => {
                if let Some(o) = self.busy_or_down() {
                    let _ = reply.send(o);
                    return;
                }
                match self.elm.submit(Request::Obd(req), now) {
                    Ok(id) => self.pending = Some((id, Pending::Obd(reply))),
                    Err(e) => {
                        let _ = reply.send(Outcome::Refused {
                            reason: e.to_string(),
                        });
                    }
                }
            }
            Cmd::Raw(line, reply) => {
                if let Some(o) = self.busy_or_down() {
                    let _ = reply.send(RawOutcome {
                        lines: vec![],
                        latency_ms: 0,
                        refused: Some(format!("{o:?}")),
                    });
                    return;
                }
                match self.elm.submit(Request::Raw(line), now) {
                    Ok(id) => self.pending = Some((id, Pending::Raw(reply, Vec::new()))),
                    Err(e) => {
                        let _ = reply.send(RawOutcome {
                            lines: vec![],
                            latency_ms: 0,
                            refused: Some(e.to_string()),
                        });
                    }
                }
            }
            Cmd::Voltage(reply) => {
                if self.busy_or_down().is_some() {
                    let _ = reply.send(None);
                    return;
                }
                match self.elm.submit(Request::ReadVoltage, now) {
                    Ok(id) => self.pending = Some((id, Pending::Voltage(reply))),
                    Err(_) => {
                        let _ = reply.send(None);
                    }
                }
            }
        }
    }

    /// Requests are refused while not connected/ready or while one is in
    /// flight (callers serialise through the scheduler, so this is a guard).
    fn busy_or_down(&self) -> Option<Outcome> {
        if self.stream.is_none() || self.elm.state() == ElmState::Offline {
            return Some(Outcome::LinkDown);
        }
        if self.pending.is_some() || self.elm.state() != ElmState::Idle {
            return Some(Outcome::Refused {
                reason: format!("adapter busy ({:?})", self.elm.state()),
            });
        }
        None
    }

    async fn flush(&mut self) {
        while let Some(bytes) = self.elm.poll_transmit() {
            let Some(s) = self.stream.as_mut() else {
                return;
            };
            if let Err(e) = s.write_all(&bytes).await {
                self.lost(&format!("write failed: {e}")).await;
                return;
            }
        }
    }

    async fn lost(&mut self, why: &str) {
        self.stream = None;
        let now = self.now();
        self.elm.transport_lost(now);
        self.fail_pending(Outcome::LinkDown);
        {
            let _ = self
                .events
                .send(DriverEvent::Disconnected(why.to_string()))
                .await;
        };
    }

    fn fail_pending(&mut self, outcome: Outcome) {
        match self.pending.take() {
            Some((_, Pending::Obd(tx))) => {
                let _ = tx.send(outcome);
            }
            Some((_, Pending::Raw(tx, lines))) => {
                let _ = tx.send(RawOutcome {
                    lines,
                    latency_ms: 0,
                    refused: Some("link lost".into()),
                });
            }
            Some((_, Pending::Voltage(tx))) => {
                let _ = tx.send(None);
            }
            None => {}
        }
    }

    async fn drain_events(&mut self) {
        while let Some(ev) = self.elm.poll_event() {
            match ev {
                ElmEvent::Ready { adapter_id } => {
                    let _ = self.events.send(DriverEvent::Ready { adapter_id }).await;
                }
                ElmEvent::StateChanged {
                    to: ElmState::Offline,
                    ..
                } => {
                    self.fail_pending(Outcome::LinkDown);
                    {
                        let _ = self.events.send(DriverEvent::AdapterOffline).await;
                    };
                }
                ElmEvent::StateChanged { .. } => {}
                ElmEvent::AdapterAlert { line } => {
                    let _ = self.events.send(DriverEvent::AdapterAlert(line)).await;
                }
                ElmEvent::InitCommandFailed { command } => {
                    let _ = self
                        .events
                        .send(DriverEvent::Note(format!(
                            "init command {command} rejected; skipped"
                        )))
                        .await;
                }
                ElmEvent::Recovery(step) => {
                    let _ = self
                        .events
                        .send(DriverEvent::Note(format!("adapter recovery: {step:?}")))
                        .await;
                }
                ElmEvent::ObdResponse(rsp) => {
                    if let Some((id, Pending::Obd(tx))) = self.pending.take() {
                        if id == rsp.id {
                            let _ = tx.send(outcome_of(&rsp));
                        } else {
                            self.pending = Some((id, Pending::Obd(tx)));
                        }
                    }
                }
                ElmEvent::Voltage(v) => {
                    if let Some((id, Pending::Voltage(tx))) = self.pending.take() {
                        if id == v.id {
                            let _ = tx.send(v.volts.filter(|_| v.result == ElmResult::Ok));
                        } else {
                            self.pending = Some((id, Pending::Voltage(tx)));
                        }
                    }
                }
                ElmEvent::RawLine { id, line } => {
                    if let Some((pid, Pending::Raw(_, lines))) = self.pending.as_mut()
                        && *pid == id
                    {
                        lines.push(line);
                    }
                }
                ElmEvent::RawComplete(done) => {
                    if let Some((id, Pending::Raw(tx, lines))) = self.pending.take() {
                        let _ = tx.send(RawOutcome {
                            lines,
                            latency_ms: done.latency_ms.min(u64::from(u32::MAX)) as u32,
                            refused: None,
                        });
                        debug_assert_eq!(id, done.id);
                    }
                }
                other => {
                    let _ = self
                        .events
                        .send(DriverEvent::Note(format!("{other:?}")))
                        .await;
                }
            }
        }
    }
}

/// Maps an ELM response onto the transport-neutral outcome.
pub fn outcome_of(rsp: &f250_elm::ObdResponse) -> Outcome {
    let latency_ms = rsp.latency_ms.min(u64::from(u32::MAX)) as u32;
    match &rsp.result {
        ElmResult::Ok => {
            let mut responders: Vec<ResponderPayload> = Vec::new();
            // The chosen payload first (after expected-responder filtering).
            responders.push(ResponderPayload {
                can_id: rsp
                    .responder_id
                    .map(|id| format!("{id:03X}"))
                    .unwrap_or_default(),
                payload: rsp.payload.clone(),
            });
            for r in rsp.responders.iter().skip(1) {
                responders.push(ResponderPayload {
                    can_id: r.can_id.map(|id| format!("{id:03X}")).unwrap_or_default(),
                    payload: r.payload.clone(),
                });
            }
            Outcome::Payload {
                responders,
                latency_ms,
            }
        }
        ElmResult::NoData | ElmResult::NoResponder | ElmResult::Timeout => {
            Outcome::NoResponse { latency_ms }
        }
        ElmResult::Stopped => Outcome::Invalid {
            detail: "adapter STOPPED".into(),
            latency_ms,
        },
        ElmResult::Error(ErrorCause::NegativeResponse(n)) => Outcome::Negative {
            nrc: n.nrc.unwrap_or(0x10),
            latency_ms,
        },
        ElmResult::Error(ErrorCause::AddressingRejected { command, line }) => Outcome::Refused {
            reason: format!("adapter rejected {command}: {line}"),
        },
        ElmResult::Error(cause) => Outcome::Invalid {
            detail: format!("{cause:?}"),
            latency_ms,
        },
    }
}
