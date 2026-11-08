//! Direct-CAN transport (ADR-0012): the gateway's own ISO-TP single-frame
//! requests on a SocketCAN interface (`can0`), instead of an ELM adapter.
//!
//! Same contract as [`super::obdlink::ObdLink`]: a handle that sends commands
//! to one driver task, which owns the socket. The driver reports
//! [`DriverEvent`]s, so the link state machine and recovery ladder are the
//! transport-neutral ones in `link.rs`.
//!
//! Safety (ADR-0007):
//! - The socket is opened only on `connect`, which the link machine only
//!   asks for when `--transmit` was given. Without it the gateway is
//!   PASSIVE_ONLY and never opens the interface.
//! - Every frame is built by [`isotp::request_frame`] / [`isotp::raw_frame`],
//!   which apply the read-only service allow-list and allow only the OBD
//!   request IDs (7DF, 7E0–7E7). Nothing else can be written.
//! - The interface's own listen-only mode is a second, independent layer:
//!   set by `tools/pi/can.sh` (root), not by the gateway.
//!
//! The bus is behind [`CanBus`] so the driver can be tested without Linux:
//! [`socket`] is the real SocketCAN implementation (Linux only).

use std::collections::BTreeSet;
use std::future::Future;
use std::io;
use std::pin::Pin;
use std::sync::Arc;
use std::time::{Duration, Instant};

use f250_elm::request::{ObdRequest, ServiceAllowList};
use tokio::sync::{mpsc, oneshot};

use super::Outcome;
use super::isotp::{self, Exchange, Frame};
use super::obdlink::{DriverEvent, RawOutcome};
use super::traffic::TrafficLog;

pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// What a bus read returns.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BusEvent {
    Data(Frame),
    /// A SocketCAN error frame (bus errors, error-passive, bus-off). `class`
    /// is the error class bits of the CAN ID; `data` the 8 detail bytes.
    Error {
        class: u32,
        data: Vec<u8>,
    },
}

/// One open CAN interface.
pub trait CanBus: Send + Sync {
    fn send<'a>(&'a mut self, frame: &'a Frame) -> BoxFuture<'a, io::Result<()>>;
    fn recv(&mut self) -> BoxFuture<'_, io::Result<BusEvent>>;
}

/// Opens (or re-opens) the bus.
pub type Opener = Arc<dyn Fn() -> BoxFuture<'static, io::Result<Box<dyn CanBus>>> + Send + Sync>;

/// SocketCAN error class: bus-off (linux/can/error.h `CAN_ERR_BUSOFF`).
pub const CAN_ERR_BUSOFF: u32 = 0x0000_0040;

/// Timing for one transport instance.
#[derive(Debug, Clone, Copy)]
pub struct CanTiming {
    /// How long to collect answers to a functional or unpinned request.
    pub window: Duration,
}

enum Cmd {
    Connect,
    Disconnect,
    Reset,
    Obd(ObdRequest, oneshot::Sender<Outcome>),
    Raw(String, oneshot::Sender<RawOutcome>),
    Check(oneshot::Sender<bool>),
}

/// Handle to the driver task.
#[derive(Clone)]
pub struct CanLink {
    cmd: mpsc::Sender<Cmd>,
    pub interface: String,
}

impl CanLink {
    /// Spawns the driver. It stays closed until [`CanLink::connect`].
    pub fn spawn(
        interface: String,
        opener: Opener,
        allow: ServiceAllowList,
        timing: CanTiming,
        traffic: Option<TrafficLog>,
    ) -> (Self, mpsc::Receiver<DriverEvent>) {
        let (cmd_tx, cmd_rx) = mpsc::channel(32);
        let (ev_tx, ev_rx) = mpsc::channel(256);
        let driver = Driver {
            interface: interface.clone(),
            opener,
            allow,
            timing,
            cmds: cmd_rx,
            events: ev_tx,
            bus: None,
            epoch: Instant::now(),
            traffic,
            last_error_note: None,
            errors_since_note: 0,
            responders: BTreeSet::new(),
        };
        tokio::spawn(driver.run());
        (
            CanLink {
                cmd: cmd_tx,
                interface,
            },
            ev_rx,
        )
    }

    pub async fn connect(&self) {
        let _ = self.cmd.send(Cmd::Connect).await;
    }

    pub async fn disconnect(&self) {
        let _ = self.cmd.send(Cmd::Disconnect).await;
    }

    /// Close and re-open the socket.
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
            refused: Some("CAN driver stopped".into()),
        };
        if self.cmd.send(Cmd::Raw(line, tx)).await.is_err() {
            return gone;
        }
        rx.await.unwrap_or(gone)
    }

    /// Soft health check: the socket is open and the interface reports up.
    /// Sends nothing on the bus.
    pub async fn check(&self) -> bool {
        let (tx, rx) = oneshot::channel();
        if self.cmd.send(Cmd::Check(tx)).await.is_err() {
            return false;
        }
        rx.await.unwrap_or(false)
    }
}

struct Driver {
    interface: String,
    opener: Opener,
    allow: ServiceAllowList,
    timing: CanTiming,
    cmds: mpsc::Receiver<Cmd>,
    events: mpsc::Sender<DriverEvent>,
    bus: Option<Box<dyn CanBus>>,
    epoch: Instant,
    traffic: Option<TrafficLog>,
    last_error_note: Option<Instant>,
    errors_since_note: u32,
    /// Diagnostic response IDs heard since the socket opened: the modules
    /// that answer functional requests. A pinned functional request waits
    /// for the others' answers too ([`Exchange::wait_for`]).
    responders: BTreeSet<u16>,
}

/// Reads the next bus event, or waits forever while closed.
async fn next_event(bus: &mut Option<Box<dyn CanBus>>) -> io::Result<BusEvent> {
    match bus {
        Some(b) => b.recv().await,
        None => std::future::pending().await,
    }
}

impl Driver {
    fn now_ms(&self) -> u64 {
        self.epoch.elapsed().as_millis() as u64
    }

    fn log(&mut self, dir: &str, line: &str) {
        let ms = self.now_ms();
        if let Some(t) = self.traffic.as_mut() {
            t.line(ms, dir, line);
        }
    }

    async fn emit(&self, ev: DriverEvent) {
        let events = self.events.clone();
        let _ = events.send(ev).await;
    }

    async fn run(mut self) {
        loop {
            tokio::select! {
                cmd = self.cmds.recv() => match cmd {
                    Some(c) => self.command(c).await,
                    None => return,
                },
                ev = next_event(&mut self.bus) => match ev {
                    // Between requests: a late answer, or another tester's
                    // traffic (filtered to 7E8–7EF by the socket). Logged only.
                    Ok(BusEvent::Data(f)) => self.on_late(&f),
                    Ok(BusEvent::Error { class, data }) => self.bus_error(class, &data).await,
                    Err(e) => self.lost(&format!("read failed: {e}")).await,
                },
            }
        }
    }

    async fn command(&mut self, c: Cmd) {
        match c {
            Cmd::Connect => self.open().await,
            Cmd::Disconnect => {
                self.bus = None;
            }
            Cmd::Reset => {
                self.bus = None;
                self.open().await;
            }
            Cmd::Obd(req, reply) => {
                let out = self.obd(req).await;
                let _ = reply.send(out);
            }
            Cmd::Raw(line, reply) => {
                let out = self.raw(&line).await;
                let _ = reply.send(out);
            }
            Cmd::Check(reply) => {
                let ok = self.bus.is_some() && interface_up(&self.interface);
                let _ = reply.send(ok);
            }
        }
    }

    async fn open(&mut self) {
        if self.bus.is_none() {
            match (self.opener)().await {
                Ok(bus) => {
                    self.bus = Some(bus);
                    self.responders.clear();
                    self.log("--", &format!("opened {}", self.interface));
                }
                Err(e) => {
                    self.emit(DriverEvent::ConnectFailed(format!(
                        "{}: {e}",
                        self.interface
                    )))
                    .await;
                    return;
                }
            }
        }
        self.emit(DriverEvent::Connected).await;
        // Nothing to initialise: no adapter, no AT commands.
        self.emit(DriverEvent::Ready {
            adapter_id: Some(format!("SocketCAN {}", self.interface)),
        })
        .await;
    }

    /// A frame that arrived outside any exchange: logged, and its sender
    /// remembered.
    fn on_late(&mut self, f: &Frame) {
        self.log("RX", &f.display());
        self.heard(f.id);
    }

    fn heard(&mut self, id: u16) {
        if isotp::RESPONSE_IDS.contains(&id) {
            self.responders.insert(id);
        }
    }

    async fn lost(&mut self, why: &str) {
        self.bus = None;
        self.log("--", &format!("lost: {why}"));
        self.emit(DriverEvent::Disconnected(why.to_string())).await;
    }

    async fn bus_error(&mut self, class: u32, data: &[u8]) {
        let hex: Vec<String> = data.iter().map(|b| format!("{b:02X}")).collect();
        self.log("ER", &format!("class {class:08X} {}", hex.join(" ")));
        self.errors_since_note += 1;
        if class & CAN_ERR_BUSOFF != 0 {
            self.lost("bus-off").await;
            return;
        }
        // One note per 10 s at most, so a noisy bus can't flood the events.
        let now = Instant::now();
        if self
            .last_error_note
            .is_none_or(|t| now.duration_since(t) >= Duration::from_secs(10))
        {
            let n = self.errors_since_note;
            self.errors_since_note = 0;
            self.last_error_note = Some(now);
            self.emit(DriverEvent::Note(format!(
                "{}: {n} CAN error frame(s), latest class {class:08X}",
                self.interface
            )))
            .await;
        }
    }

    /// Send one frame and collect answers until `ex` is done. Every received
    /// frame is logged; `seen` gets the data frames, for `raw`.
    async fn exchange(
        &mut self,
        frame: &Frame,
        ex: &mut Exchange,
        mut seen: Option<&mut Vec<(Duration, Frame)>>,
    ) -> Result<Duration, Outcome> {
        if self.bus.is_none() {
            return Err(Outcome::LinkDown);
        }
        // Whatever is already queued answers an earlier request: read it
        // now, so it can't be taken for an answer to this one.
        loop {
            let Some(bus) = self.bus.as_mut() else {
                return Err(Outcome::LinkDown);
            };
            match tokio::time::timeout(Duration::ZERO, bus.recv()).await {
                Err(_) => break,
                Ok(Ok(BusEvent::Data(f))) => self.on_late(&f),
                Ok(Ok(BusEvent::Error { class, data })) => self.bus_error(class, &data).await,
                Ok(Err(e)) => {
                    self.lost(&format!("read failed: {e}")).await;
                    return Err(Outcome::LinkDown);
                }
            }
        }
        self.log("TX", &frame.display());
        let start = Instant::now();
        let sent = match self.bus.as_mut() {
            Some(bus) => bus.send(frame).await,
            None => return Err(Outcome::LinkDown),
        };
        if let Err(e) = sent {
            self.lost(&format!("write failed: {e}")).await;
            return Err(Outcome::LinkDown);
        }
        loop {
            let at = start.elapsed();
            if ex.done(at) {
                return Ok(at);
            }
            let wait = ex.next_check(at).saturating_sub(at);
            let Some(bus) = self.bus.as_mut() else {
                return Err(Outcome::LinkDown);
            };
            match tokio::time::timeout(wait, bus.recv()).await {
                Err(_) => {} // re-check done()
                Ok(Ok(BusEvent::Data(f))) => {
                    self.log("RX", &f.display());
                    self.heard(f.id);
                    ex.on_frame(&f);
                    if let Some(s) = seen.as_deref_mut() {
                        s.push((start.elapsed(), f));
                    }
                }
                Ok(Ok(BusEvent::Error { class, data })) => {
                    self.bus_error(class, &data).await;
                    if self.bus.is_none() {
                        return Err(Outcome::LinkDown);
                    }
                }
                Ok(Err(e)) => {
                    self.lost(&format!("read failed: {e}")).await;
                    return Err(Outcome::LinkDown);
                }
            }
        }
    }

    async fn obd(&mut self, req: ObdRequest) -> Outcome {
        let frame = match isotp::request_frame(&req, &self.allow) {
            Ok(f) => f,
            Err(reason) => return Outcome::Refused { reason },
        };
        let mut ex = Exchange::new(&req, self.timing.window);
        if frame.id == isotp::FUNCTIONAL_ID {
            ex = ex.wait_for(self.responders.iter().copied());
        }
        match self.exchange(&frame, &mut ex, None).await {
            Ok(at) => ex.finish(at),
            Err(o) => o,
        }
    }

    async fn raw(&mut self, line: &str) -> RawOutcome {
        let frame = match isotp::raw_frame(line, &self.allow) {
            Ok(f) => f,
            Err(reason) => {
                return RawOutcome {
                    lines: vec![],
                    latency_ms: 0,
                    refused: Some(reason),
                };
            }
        };
        let mut ex = Exchange::raw(
            self.timing.window,
            f250_elm::request::DEFAULT_REQUEST_TIMEOUT_MS,
        );
        let mut seen = Vec::new();
        match self.exchange(&frame, &mut ex, Some(&mut seen)).await {
            Ok(at) => {
                let mut lines = vec![format!("TX {}", frame.display())];
                if seen.is_empty() {
                    lines.push(format!("(no answer in {} ms)", at.as_millis()));
                }
                for (t, f) in &seen {
                    lines.push(format!("+{:>3} ms {}", t.as_millis(), f.display()));
                }
                RawOutcome {
                    lines,
                    latency_ms: at.as_millis() as u32,
                    refused: None,
                }
            }
            Err(_) => RawOutcome {
                lines: vec![],
                latency_ms: 0,
                refused: Some(format!("{} is not open", self.interface)),
            },
        }
    }
}

/// `/sys/class/net/<if>/operstate` is "up" (or "unknown", which some CAN
/// drivers report while working). False if the interface doesn't exist.
fn interface_up(interface: &str) -> bool {
    match std::fs::read_to_string(format!("/sys/class/net/{interface}/operstate")) {
        Ok(s) => matches!(s.trim(), "up" | "unknown"),
        // Not Linux (tests on the Mac): trust the open socket.
        Err(_) => !std::path::Path::new("/sys/class/net").exists(),
    }
}

/// The real bus: a raw SocketCAN socket.
#[cfg(target_os = "linux")]
pub mod socket {
    use super::*;
    use socketcan::tokio::CanSocket;
    use socketcan::{
        CanFilter, CanFrame, EmbeddedFrame, Frame as _, Id, SocketOptions, StandardId,
    };

    struct SocketBus(CanSocket);

    impl CanBus for SocketBus {
        fn send<'a>(&'a mut self, frame: &'a Frame) -> BoxFuture<'a, io::Result<()>> {
            Box::pin(async move {
                let id = StandardId::new(frame.id)
                    .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "bad CAN id"))?;
                let f = CanFrame::new(id, &frame.data)
                    .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "bad frame"))?;
                self.0.write_frame(f).await
            })
        }

        fn recv(&mut self) -> BoxFuture<'_, io::Result<BusEvent>> {
            Box::pin(async move {
                loop {
                    match self.0.read_frame().await? {
                        CanFrame::Data(d) => {
                            if let Id::Standard(id) = d.id() {
                                return Ok(BusEvent::Data(Frame {
                                    id: id.as_raw(),
                                    data: d.data().to_vec(),
                                }));
                            }
                        }
                        CanFrame::Error(e) => {
                            return Ok(BusEvent::Error {
                                class: e.raw_id() & 0x1FFF_FFFF,
                                data: e.data().to_vec(),
                            });
                        }
                        CanFrame::Remote(_) => {}
                    }
                }
            })
        }
    }

    /// Opens `interface` with a receive filter for the diagnostic response
    /// IDs 7E8–7EF and every error class. Our own transmitted frames are not
    /// looped back to us.
    pub fn opener(interface: String) -> Opener {
        Arc::new(move || {
            let interface = interface.clone();
            Box::pin(async move {
                let sock = CanSocket::open(&interface)?;
                sock.set_filters(&[CanFilter::new(0x7E8, 0x7F8)])?;
                sock.set_error_filter_accept_all()?;
                sock.set_recv_own_msgs(false)?;
                Ok(Box::new(SocketBus(sock)) as Box<dyn CanBus>)
            })
        })
    }
}

/// Not Linux: SocketCAN doesn't exist; opening always fails, honestly.
#[cfg(not(target_os = "linux"))]
pub mod socket {
    use super::*;

    pub fn opener(interface: String) -> Opener {
        Arc::new(move || {
            let interface = interface.clone();
            Box::pin(async move {
                Err(io::Error::new(
                    io::ErrorKind::Unsupported,
                    format!("SocketCAN ({interface}) is Linux-only"),
                ))
            })
        })
    }
}
