//! The sans-IO ELM327/STN request/response state machine.
//!
//! Port of `firmware/esp32/lib/ObdCore/src/ElmClient.{h,cpp}`. See the crate
//! documentation for the driving loop.

use std::collections::VecDeque;
use std::fmt;

use crate::parser::{
    AccEvent, IsoTpReassembler, LineAccumulator, LineClass, classify_line, parse_data_line,
    parse_voltage, strip_spaces,
};
use crate::request::{
    Addressing, FUNCTIONAL_HEADER, ObdCommand, ObdRequest, RawLineError, SERVICE_READ_DATA_BY_ID,
    ServiceAllowList, check_raw_line, is_functional_header, normalise_header,
};

/// The ELM `read voltage` command.
pub const READ_VOLTAGE_COMMAND: &str = "ATRV";

/// The init sequence in `firmware/esp32/include/Config.h` (`kElmInitCommands`).
/// `ATSP6` is pinned because this truck auto-detected protocol `A6`
/// (VERIFICATION_LOG.md, 2026-08-09); change it if the adapter moves vehicles.
pub const DEFAULT_INIT_COMMANDS: [&str; 6] = ["ATE0", "ATL0", "ATS0", "ATH1", "ATAT1", "ATSP6"];

// ---------------------------------------------------------------------------
// State, ids, configuration
// ---------------------------------------------------------------------------

/// Where the client is in the adapter lifecycle.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ElmState {
    /// Not started, or unrecoverable: the owner must reconnect the transport
    /// and call [`ElmClient::begin`].
    Offline,
    /// `ATZ` sent, waiting for the prompt (the adapter may be waking up).
    Resetting,
    /// Stepping through the init command list.
    Initializing,
    /// Prompt seen, nothing in flight: [`ElmClient::submit`] is allowed.
    Idle,
    /// A request is in flight.
    AwaitingResponse,
    /// A request timed out: waiting for its late prompt, then for the answer
    /// to an `ATI` probe. Nothing new is sent until one of them arrives.
    Recovering,
}

impl ElmState {
    /// Short upper-case name (matches the C++ `elmStateName`).
    pub const fn name(self) -> &'static str {
        match self {
            Self::Offline => "OFFLINE",
            Self::Resetting => "RESETTING",
            Self::Initializing => "INITIALIZING",
            Self::Idle => "IDLE",
            Self::AwaitingResponse => "AWAITING",
            Self::Recovering => "RECOVERING",
        }
    }
}

impl fmt::Display for ElmState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.name())
    }
}

/// Identifies one submitted request in its completion event.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct RequestId(pub u64);

/// Something to ask the adapter.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Request {
    /// An OBD request; completes with [`ElmEvent::ObdResponse`].
    Obd(ObdRequest),
    /// A verbatim console line (`raw ATDPN`, `raw 221674`). Every reply line
    /// is surfaced unparsed as [`ElmEvent::RawLine`]; completes with
    /// [`ElmEvent::RawComplete`]. AT commands are allowed; hex lines must
    /// pass the service allow-list. Afterwards the cached header and filter
    /// are marked unknown, because the line may have changed them.
    Raw(String),
    /// `ATRV`, the adapter's input voltage; completes with
    /// [`ElmEvent::Voltage`].
    ReadVoltage,
}

impl From<ObdRequest> for Request {
    fn from(r: ObdRequest) -> Self {
        Self::Obd(r)
    }
}

/// Client configuration (C++ `ElmConfig`). Defaults match the firmware.
#[derive(Debug, Clone, PartialEq)]
pub struct ElmConfig {
    /// Sent in order after `ATZ`. A command answered with `?` is retried
    /// once, then skipped ([`ElmEvent::InitCommandFailed`]).
    pub init_commands: Vec<String>,
    /// `ATZ` can be slow while the STN wakes.
    pub reset_timeout_ms: u64,
    /// Per init command; also per `ATSH`/`ATCRA` prep command and `ATRV`.
    pub init_timeout_ms: u64,
    /// The first request after init may trigger protocol `SEARCHING...`;
    /// a `SEARCHING` line also re-arms this deadline.
    pub first_data_timeout_ms: u64,
    /// After a request timeout, how long to wait for that request's own late
    /// prompt before probing the adapter with `ATI`.
    pub late_reply_timeout_ms: u64,
    /// Wait for the answer to the recovery `ATI` probe; also the idle deadline.
    pub recovery_timeout_ms: u64,
    /// Raw console commands (`ATZ` needs headroom).
    pub raw_timeout_ms: u64,
    /// Consecutive request timeouts before a full `ATZ` re-init.
    pub max_consecutive_timeouts: u8,
    /// Failed resets before going [`ElmState::Offline`].
    pub max_reset_attempts: u8,
    /// How many responders' answers are kept verbatim (the count stays honest
    /// beyond this). This truck produces two.
    pub max_recorded_responders: usize,
    /// OBD services that may be transmitted (ADR-0007).
    pub allowed_services: ServiceAllowList,
}

impl Default for ElmConfig {
    fn default() -> Self {
        Self {
            init_commands: DEFAULT_INIT_COMMANDS
                .iter()
                .map(|&s| s.to_owned())
                .collect(),
            reset_timeout_ms: 6000,
            init_timeout_ms: 2000,
            first_data_timeout_ms: 10_000,
            late_reply_timeout_ms: 1000,
            recovery_timeout_ms: 2000,
            raw_timeout_ms: 3000,
            max_consecutive_timeouts: 3,
            max_reset_attempts: 2,
            max_recorded_responders: 3,
            allowed_services: ServiceAllowList::read_only_default(),
        }
    }
}

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

/// What one ECU said, echo already stripped.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResponderAnswer {
    /// Sender CAN ID; `None` for a headerless (`ATH0`) line.
    pub can_id: Option<u16>,
    /// Payload after the positive-response echo.
    pub payload: Vec<u8>,
}

/// A `7F <service> <NRC>` negative response.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NegativeResponse {
    /// Sender CAN ID; `None` for a headerless line.
    pub can_id: Option<u16>,
    /// The rejected service byte (absent if the frame was truncated).
    pub service: Option<u8>,
    /// Negative response code, e.g. 0x31 requestOutOfRange.
    pub nrc: Option<u8>,
}

/// Which adapter status line ended a request in error.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AdapterErrorKind {
    /// `CAN ERROR`.
    CanError,
    /// `BUFFER FULL`.
    BufferFull,
    /// `UNABLE TO CONNECT`.
    UnableToConnect,
    /// `?` or another `...ERROR` line.
    Rejected,
}

/// Detail for [`ElmResult::Error`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ErrorCause {
    /// An ECU answered `7F <service> <NRC>` and nobody answered positively.
    NegativeResponse(NegativeResponse),
    /// The adapter reported a fault while the request was in flight.
    Adapter {
        /// Which fault.
        kind: AdapterErrorKind,
        /// The line as received.
        line: String,
    },
    /// An `ATSH`/`ATCRA` prep command was rejected; the request was never
    /// sent.
    AddressingRejected {
        /// The prep command.
        command: String,
        /// The adapter's reply.
        line: String,
    },
    /// The prompt came back with nothing usable (for `ATRV`: no parseable
    /// voltage).
    EmptyResponse,
}

/// Outcome of one request (C++ `ElmResult`, with error detail added).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ElmResult {
    /// Positive response; payload delivered with the echo stripped.
    Ok,
    /// `NO DATA`: no ECU answered.
    NoData,
    /// An ECU answered, but not the pinned `expected_responder`. Distinct from
    /// `NoData` so a bad pin is diagnosable instead of looking like a dead PID.
    NoResponder,
    /// No prompt within the deadline (also used when the transport is lost
    /// or [`ElmClient::begin`] is called with a request in flight).
    Timeout,
    /// The adapter aborted the request (`STOPPED`).
    Stopped,
    /// `?`, `CAN ERROR`, a negative response, a rejected `ATSH`, etc.
    Error(ErrorCause),
}

impl ElmResult {
    /// Short upper-case name (matches the C++ `elmResultName`).
    pub const fn name(&self) -> &'static str {
        match self {
            Self::Ok => "OK",
            Self::NoData => "NO_DATA",
            Self::NoResponder => "NO_RESPONDER",
            Self::Timeout => "TIMEOUT",
            Self::Stopped => "STOPPED",
            Self::Error(_) => "ERROR",
        }
    }

    /// True for [`ElmResult::Ok`].
    pub const fn is_ok(&self) -> bool {
        matches!(self, Self::Ok)
    }
}

impl fmt::Display for ElmResult {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.name())
    }
}

/// Outcome of one OBD request, including who answered and what each said.
///
/// A functional (`7DF`) request is a broadcast: on this truck 7E8 and 7E9 both
/// answer `010C`, in varying order. Every answer is reported, because that is
/// what makes an on-truck reading evidence rather than an anecdote. There is
/// deliberately no verdict on whether responders "agree": that needs decoded
/// values over several samples, which is the telemetry layer's job.
#[derive(Debug, Clone, PartialEq)]
pub struct ObdResponse {
    /// The id [`ElmClient::submit`] returned.
    pub id: RequestId,
    /// The request as sent (header normalised to upper case).
    pub request: ObdRequest,
    /// The outcome.
    pub result: ElmResult,
    /// The first matching responder's payload, echo stripped. Empty unless
    /// `result` is `Ok`.
    pub payload: Vec<u8>,
    /// CAN ID that supplied `payload` (`None` if headerless or not `Ok`).
    pub responder_id: Option<u16>,
    /// ECUs whose answer matched service + PID, including any beyond
    /// `max_recorded_responders`.
    pub responder_count: u32,
    /// The first `max_recorded_responders` answers, in arrival order.
    pub responders: Vec<ResponderAnswer>,
    /// A fact about the bytes (some recorded answer differs from the first),
    /// not a verdict.
    pub responders_differ: bool,
    /// Negative responses, in arrival order (up to `max_recorded_responders`).
    pub negative_responses: Vec<NegativeResponse>,
    /// Frames dropped because they came from someone other than
    /// `expected_responder`.
    pub ignored_responder_frames: u32,
    /// Complete payloads that were neither a negative response nor a positive
    /// response to this request (e.g. a straggler from a previous request).
    pub unmatched_payloads: u32,
    /// Submit → final prompt (or → timeout), including any `ATSH`/`ATCRA`.
    pub latency_ms: u64,
    /// Request line written → prompt, excluding prep (the C++ `latencyMs`).
    /// `None` if the request line was never written (a prep command failed).
    pub wire_latency_ms: Option<u64>,
}

/// Outcome of an `ATRV` request.
#[derive(Debug, Clone, PartialEq)]
pub struct VoltageResponse {
    /// The id [`ElmClient::submit`] returned.
    pub id: RequestId,
    /// The outcome.
    pub result: ElmResult,
    /// Adapter input voltage in volts; `Some` exactly when `result` is `Ok`.
    pub volts: Option<f32>,
    /// Submit → prompt (or → timeout).
    pub latency_ms: u64,
}

/// Completion of a raw console command.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RawComplete {
    /// The id [`ElmClient::submit`] returned.
    pub id: RequestId,
    /// The line as sent.
    pub command: String,
    /// `Ok` when the prompt came back, `Timeout` otherwise. The reply lines
    /// themselves were delivered as [`ElmEvent::RawLine`].
    pub result: ElmResult,
    /// Submit → prompt (or → timeout).
    pub latency_ms: u64,
}

/// Why the client escalated to an adapter reset.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResetReason {
    /// No prompt after `ATZ`.
    ResetTimeout,
    /// An init command timed out.
    InitTimeout,
    /// No late prompt, and no answer to the recovery `ATI` probe.
    RecoveryFailed,
    /// `max_consecutive_timeouts` request timeouts in a row.
    ConsecutiveTimeouts,
}

/// A step on the recovery ladder (docs/architecture/diagnostic-recovery.md).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecoveryStep {
    /// Step 1: a request timed out. Nothing is sent; the client waits up to
    /// `late_reply_timeout_ms` for that request's own late prompt.
    ///
    /// Not a bare CR: an ELM327 answers a bare CR by repeating the last
    /// command, and the timed-out request's late prompt was then taken for
    /// the CR's answer, so every later reply was paired with the wrong request
    /// (docs/hardware/bench-log.md, 2026-11-02).
    AwaitLateReply {
        /// Timeouts in a row so far.
        consecutive_timeouts: u8,
    },
    /// Step 1b: no late prompt came. `ATI` was sent; only its identification
    /// line followed by a prompt counts as the adapter answering.
    ProbeAdapter,
    /// Step 2: full `ATZ` re-init.
    AdapterReset {
        /// 1-based attempt number.
        attempt: u8,
        /// `max_reset_attempts`.
        max: u8,
        /// What triggered it.
        reason: ResetReason,
    },
    /// Out of resets: the client is now [`ElmState::Offline`]. The owner
    /// should drop and re-establish the transport (step 3), then call
    /// [`ElmClient::begin`].
    GaveUp {
        /// What triggered the last escalation.
        reason: ResetReason,
    },
}

/// Something the caller should know about. Drain with
/// [`ElmClient::poll_event`].
#[derive(Debug, Clone, PartialEq)]
pub enum ElmEvent {
    /// The state changed.
    StateChanged {
        /// Old state.
        from: ElmState,
        /// New state.
        to: ElmState,
    },
    /// Reset and init finished; the adapter is ready (C++ "OBDLink connected").
    Ready {
        /// The banner seen after `ATZ` (e.g. `ELM327 v1.4b`).
        adapter_id: Option<String>,
    },
    /// An init command was rejected twice and skipped.
    InitCommandFailed {
        /// The command.
        command: String,
    },
    /// The recovery ladder moved.
    Recovery(RecoveryStep),
    /// An OBD request completed.
    ObdResponse(Box<ObdResponse>),
    /// An `ATRV` request completed.
    Voltage(VoltageResponse),
    /// One reply line to a raw command, unparsed.
    RawLine {
        /// The raw request.
        id: RequestId,
        /// The line.
        line: String,
    },
    /// A raw command completed.
    RawComplete(RawComplete),
    /// Unsolicited STN chatter (`LV RESET`, `ACT ALERT`, `LP ALERT`,
    /// `SLEEPING`, `WAKE...`). Never treated as a response.
    AdapterAlert {
        /// The line.
        line: String,
    },
    /// A line that belonged to nothing: received while idle or recovering, or
    /// unrecognised during a request. Typical cause: a straggler answer to an
    /// earlier request.
    StrayLine {
        /// State when it arrived.
        state: ElmState,
        /// The line.
        line: String,
    },
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Why [`ElmClient::submit`] refused a request. Nothing was written.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SubmitError {
    /// Only one request may be in flight, and only once init is done.
    NotIdle(ElmState),
    /// The service byte is not on the allow-list (ADR-0007).
    ServiceNotAllowed(u8),
    /// The addressing has no verified header; refused rather than guessed.
    UnverifiedHeader,
    /// The header is not 1..=8 hex digits.
    InvalidHeader(String),
    /// The receive filter is not 1..=8 hex digits.
    InvalidFilter(String),
    /// A response-count digit was asked for on the functional header.
    CountDigitOnFunctionalHeader,
    /// Response count outside 1..=9.
    InvalidResponseCount(u8),
    /// `ObdCommand::Pid` with service 0x22; use `ObdCommand::Did`.
    PidWithReadByIdService,
    /// A raw line failed the guard.
    Raw(RawLineError),
}

impl fmt::Display for SubmitError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotIdle(s) => write!(f, "adapter is {s}, not IDLE"),
            Self::ServiceNotAllowed(s) => {
                write!(f, "service 0x{s:02X} is not on the allow-list (ADR-0007)")
            }
            Self::UnverifiedHeader => {
                f.write_str("module header is unverified; request refused rather than guessed")
            }
            Self::InvalidHeader(h) => write!(f, "invalid header '{h}'"),
            Self::InvalidFilter(h) => write!(f, "invalid receive filter '{h}'"),
            Self::CountDigitOnFunctionalHeader => {
                f.write_str("response-count digit is unsafe on the functional header")
            }
            Self::InvalidResponseCount(n) => write!(f, "response count {n} is not 1..=9"),
            Self::PidWithReadByIdService => {
                f.write_str("service 0x22 takes a two-byte DID; use ObdCommand::Did")
            }
            Self::Raw(e) => write!(f, "raw command refused: {e}"),
        }
    }
}

impl std::error::Error for SubmitError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Raw(e) => Some(e),
            _ => None,
        }
    }
}

/// Why [`ElmClient::new`] rejected a configuration.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConfigError {
    /// An init command failed the same guard as raw lines.
    InitCommand {
        /// The command.
        command: String,
        /// Why.
        error: RawLineError,
    },
}

impl fmt::Display for ConfigError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InitCommand { command, error } => {
                write!(f, "init command '{command}' refused: {error}")
            }
        }
    }
}

impl std::error::Error for ConfigError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::InitCommand { error, .. } => Some(error),
        }
    }
}

// ---------------------------------------------------------------------------
// Internal state
// ---------------------------------------------------------------------------

/// Cached adapter addressing. `Unknown` after a raw command: the honest state
/// is "we don't know", so the next request re-establishes it explicitly.
#[derive(Debug, Clone, PartialEq, Eq)]
enum Cached<T> {
    Known(T),
    Unknown,
}

#[derive(Debug, Clone)]
enum Kind {
    Obd(ObdRequest),
    Raw(String),
    Voltage,
}

#[derive(Debug, Default, Clone)]
struct Collect {
    first: Option<(Option<u16>, Vec<u8>)>,
    responder_count: u32,
    responders: Vec<ResponderAnswer>,
    negatives: Vec<NegativeResponse>,
    ignored_frames: u32,
    unmatched_payloads: u32,
    no_data: bool,
    stopped: bool,
    error: Option<ErrorCause>,
    volts: Option<f32>,
}

#[derive(Debug, Clone)]
struct InFlight {
    id: RequestId,
    kind: Kind,
    submitted_ms: u64,
    request_sent_ms: Option<u64>,
    c: Collect,
}

fn adapter_error(cls: LineClass, line: &str) -> Option<ErrorCause> {
    let kind = match cls {
        LineClass::CanError => AdapterErrorKind::CanError,
        LineClass::BufferFull => AdapterErrorKind::BufferFull,
        LineClass::UnableToConnect => AdapterErrorKind::UnableToConnect,
        LineClass::Error => AdapterErrorKind::Rejected,
        _ => return None,
    };
    Some(ErrorCause::Adapter {
        kind,
        line: line.to_owned(),
    })
}

// ---------------------------------------------------------------------------
// The client
// ---------------------------------------------------------------------------

/// Sent when a timed-out request's prompt never arrives. Unlike a bare CR it
/// does not repeat the last command, and its answer can be told apart from a
/// straggler.
const PROBE_COMMAND: &str = "ATI";

/// Where [`ElmState::Recovering`] is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum RecoveryPhase {
    /// Waiting for the timed-out request's own prompt. Nothing sent.
    AwaitingLateReply,
    /// `ATI` sent; a prompt before its answer is a straggler's.
    Probing,
    /// The `ATI` answer arrived; its prompt ends recovery.
    ProbeAnswered,
}

/// Sans-IO ELM327/STN client. See the crate documentation for the driving
/// loop.
#[derive(Debug, Clone)]
pub struct ElmClient {
    cfg: ElmConfig,
    state: ElmState,
    deadline_ms: u64,
    acc: LineAccumulator,
    assembler: IsoTpReassembler,
    tx: VecDeque<Vec<u8>>,
    events: VecDeque<ElmEvent>,

    init_index: usize,
    init_retries: u8,
    init_cmd_failed: bool,
    reset_attempts: u8,

    // Addressing prep queue: ATSH (and optionally ATCRA) must be acknowledged
    // before the request goes out.
    prep: Vec<String>,
    prep_index: usize,
    prep_start_ms: u64,

    // Only valid while the adapter has not been reset or driven by a raw
    // command; every such path resets or invalidates it.
    header: Cached<String>,
    filter: Cached<Option<String>>,

    current: Option<InFlight>,
    first_data_done: bool,
    prep_overhead_ms: u64,
    prep_command_count: u64,
    consecutive_timeouts: u8,
    recovery: RecoveryPhase,
    last_sent: String,
    adapter_id: Option<String>,
    next_id: u64,
}

impl ElmClient {
    /// Create a client in [`ElmState::Offline`]. Init commands must pass the
    /// raw-line guard (AT commands, or hex on the allow-list).
    pub fn new(cfg: ElmConfig) -> Result<Self, ConfigError> {
        for cmd in &cfg.init_commands {
            check_raw_line(cmd, &cfg.allowed_services).map_err(|error| {
                ConfigError::InitCommand {
                    command: cmd.clone(),
                    error,
                }
            })?;
        }
        Ok(Self {
            cfg,
            state: ElmState::Offline,
            deadline_ms: 0,
            acc: LineAccumulator::new(),
            assembler: IsoTpReassembler::new(),
            tx: VecDeque::new(),
            events: VecDeque::new(),
            init_index: 0,
            init_retries: 0,
            init_cmd_failed: false,
            reset_attempts: 0,
            prep: Vec::new(),
            prep_index: 0,
            prep_start_ms: 0,
            header: Cached::Known(FUNCTIONAL_HEADER.to_owned()),
            filter: Cached::Known(None),
            current: None,
            first_data_done: false,
            prep_overhead_ms: 0,
            prep_command_count: 0,
            consecutive_timeouts: 0,
            recovery: RecoveryPhase::AwaitingLateReply,
            last_sent: String::new(),
            adapter_id: None,
            next_id: 1,
        })
    }

    // ----- inputs ---------------------------------------------------------

    /// Start (or restart) adapter reset + init. Call once the transport is up.
    /// Discards unsent output; a request still in flight completes with
    /// [`ElmResult::Timeout`].
    pub fn begin(&mut self, now_ms: u64) {
        self.tx.clear();
        self.acc.clear();
        self.assembler.reset();
        if self.current.is_some() {
            self.finish(ElmResult::Timeout, now_ms);
        }
        self.prep.clear();
        self.prep_index = 0;
        self.consecutive_timeouts = 0;
        self.reset_attempts = 0;
        self.first_data_done = false;
        self.adapter_id = None;
        self.start_reset(now_ms);
    }

    /// The owner detected transport loss: abandon everything, go Offline. A
    /// request in flight completes with [`ElmResult::Timeout`].
    pub fn transport_lost(&mut self, now_ms: u64) {
        self.tx.clear();
        self.acc.clear();
        self.set_state(ElmState::Offline);
        if self.current.is_some() {
            self.finish(ElmResult::Timeout, now_ms);
        }
    }

    /// Feed bytes received from the adapter. Ignored while Offline.
    pub fn receive(&mut self, bytes: &[u8], now_ms: u64) {
        for &b in bytes {
            if self.state == ElmState::Offline {
                return;
            }
            match self.acc.feed(b) {
                AccEvent::Line => {
                    let line = self.acc.line().to_owned();
                    self.handle_line(&line, now_ms);
                }
                AccEvent::Prompt => self.handle_prompt(now_ms),
                AccEvent::None => {}
            }
        }
    }

    /// Check deadlines. Call after [`receive`](Self::receive), and whenever
    /// [`next_deadline`](Self::next_deadline) passes.
    pub fn tick(&mut self, now_ms: u64) {
        if self.state != ElmState::Offline && now_ms >= self.deadline_ms {
            self.handle_timeout(now_ms);
        }
    }

    /// Submit a request. Only valid in [`ElmState::Idle`]. The request is
    /// validated first (allow-list, header, count digit); a refused request
    /// writes nothing.
    pub fn submit(&mut self, request: Request, now_ms: u64) -> Result<RequestId, SubmitError> {
        let kind = match request {
            Request::Obd(r) => Kind::Obd(self.validate_obd(r)?),
            Request::Raw(line) => {
                check_raw_line(&line, &self.cfg.allowed_services).map_err(SubmitError::Raw)?;
                Kind::Raw(line)
            }
            Request::ReadVoltage => Kind::Voltage,
        };
        if self.state != ElmState::Idle {
            return Err(SubmitError::NotIdle(self.state));
        }

        let id = RequestId(self.next_id);
        self.next_id += 1;
        self.assembler.reset();
        self.prep.clear();
        self.prep_index = 0;

        // Queue whatever addressing commands the adapter still needs. ATSH
        // first: on 11-bit CAN it also sets the expected receive address, and
        // an ATCRA must override that rather than be overridden by it.
        if let Kind::Obd(req) = &kind {
            let header = req.addressing.tx_header.clone().unwrap_or_default();
            let filter = req.addressing.rx_filter.clone();
            if self.header != Cached::Known(header.clone()) {
                self.prep.push(format!("ATSH{header}"));
            }
            if self.filter != Cached::Known(filter.clone()) {
                // A bare "ATCRA" clears the filter.
                self.prep
                    .push(format!("ATCRA{}", filter.unwrap_or_default()));
            }
        }

        let line = match &kind {
            Kind::Raw(line) => Some((line.clone(), self.cfg.raw_timeout_ms)),
            Kind::Voltage => Some((READ_VOLTAGE_COMMAND.to_owned(), self.cfg.init_timeout_ms)),
            Kind::Obd(_) => None,
        };
        self.current = Some(InFlight {
            id,
            kind,
            submitted_ms: now_ms,
            request_sent_ms: None,
            c: Collect::default(),
        });
        self.set_state(ElmState::AwaitingResponse);

        match line {
            Some((line, timeout)) => {
                self.send_line(&line);
                if let Some(cur) = self.current.as_mut() {
                    cur.request_sent_ms = Some(now_ms);
                }
                self.deadline_ms = now_ms + timeout;
            }
            None if self.prep.is_empty() => self.send_request(now_ms),
            None => {
                self.prep_start_ms = now_ms;
                self.send_next_prep(now_ms);
            }
        }
        Ok(id)
    }

    // ----- outputs --------------------------------------------------------

    /// Next chunk of bytes to write to the adapter (one command line,
    /// `\r`-terminated), oldest first.
    pub fn poll_transmit(&mut self) -> Option<Vec<u8>> {
        self.tx.pop_front()
    }

    /// Next event, oldest first.
    pub fn poll_event(&mut self) -> Option<ElmEvent> {
        self.events.pop_front()
    }

    /// When [`tick`](Self::tick) next has work to do; `None` while Offline.
    pub fn next_deadline(&self) -> Option<u64> {
        (self.state != ElmState::Offline).then_some(self.deadline_ms)
    }

    // ----- queries --------------------------------------------------------

    /// Current state.
    pub fn state(&self) -> ElmState {
        self.state
    }

    /// True in Idle or AwaitingResponse (the link is up and initialised).
    pub fn is_ready(&self) -> bool {
        matches!(self.state, ElmState::Idle | ElmState::AwaitingResponse)
    }

    /// True while a raw command is still collecting reply lines.
    pub fn raw_in_flight(&self) -> bool {
        matches!(
            self.current,
            Some(InFlight {
                kind: Kind::Raw(_),
                ..
            })
        )
    }

    /// The request in flight, if any.
    pub fn in_flight(&self) -> Option<RequestId> {
        self.current.as_ref().map(|c| c.id)
    }

    /// The banner seen after the last [`begin`](Self::begin)'s `ATZ`.
    pub fn adapter_id(&self) -> Option<&str> {
        self.adapter_id.as_deref()
    }

    /// The header the adapter is believed to be on; `None` when unknown
    /// (after a raw command).
    pub fn cached_header(&self) -> Option<&str> {
        match &self.header {
            Cached::Known(h) => Some(h),
            Cached::Unknown => None,
        }
    }

    /// The configuration.
    pub fn config(&self) -> &ElmConfig {
        &self.cfg
    }

    /// Milliseconds spent on `ATSH`/`ATCRA` prep since the last
    /// [`reset_stats`](Self::reset_stats). Prep is bus time no request's
    /// `wire_latency_ms` accounts for.
    pub fn prep_overhead_ms(&self) -> u64 {
        self.prep_overhead_ms
    }

    /// `ATSH`/`ATCRA` commands sent since the last
    /// [`reset_stats`](Self::reset_stats).
    pub fn prep_command_count(&self) -> u64 {
        self.prep_command_count
    }

    /// Zero the prep statistics.
    pub fn reset_stats(&mut self) {
        self.prep_overhead_ms = 0;
        self.prep_command_count = 0;
    }

    // ----- internals ------------------------------------------------------

    fn validate_obd(&self, mut r: ObdRequest) -> Result<ObdRequest, SubmitError> {
        let service = r.command.service();
        if !self.cfg.allowed_services.contains(service) {
            return Err(SubmitError::ServiceNotAllowed(service));
        }
        if matches!(r.command, ObdCommand::Pid { service, .. } if service == SERVICE_READ_DATA_BY_ID)
        {
            return Err(SubmitError::PidWithReadByIdService);
        }
        let Some(h) = r.addressing.tx_header.as_deref() else {
            return Err(SubmitError::UnverifiedHeader);
        };
        let header = normalise_header(h).ok_or_else(|| SubmitError::InvalidHeader(h.to_owned()))?;
        let filter = match r.addressing.rx_filter.as_deref() {
            None | Some("") => None,
            Some(f) => {
                Some(normalise_header(f).ok_or_else(|| SubmitError::InvalidFilter(f.to_owned()))?)
            }
        };
        if let Some(n) = r.expected_responses {
            if !(1..=9).contains(&n) {
                return Err(SubmitError::InvalidResponseCount(n));
            }
            if is_functional_header(&header) {
                return Err(SubmitError::CountDigitOnFunctionalHeader);
            }
        }
        r.addressing = Addressing {
            tx_header: Some(header),
            rx_filter: filter,
        };
        Ok(r)
    }

    fn emit(&mut self, ev: ElmEvent) {
        self.events.push_back(ev);
    }

    fn set_state(&mut self, to: ElmState) {
        let from = self.state;
        if from != to {
            self.state = to;
            self.emit(ElmEvent::StateChanged { from, to });
        }
    }

    fn send_line(&mut self, cmd: &str) {
        let mut bytes = Vec::with_capacity(cmd.len() + 1);
        bytes.extend_from_slice(cmd.as_bytes());
        bytes.push(b'\r');
        self.tx.push_back(bytes);
        cmd.clone_into(&mut self.last_sent);
    }

    /// ATZ restores the adapter's default functional header (7DF) and drops
    /// any receive filter. This MUST run on every reset path: the recovery
    /// ladder reaches `start_reset` without going through `begin`, and a stale
    /// cache would skip the next ATSH and send on the wrong header.
    fn reset_addressing_to_defaults(&mut self) {
        self.header = Cached::Known(FUNCTIONAL_HEADER.to_owned());
        self.filter = Cached::Known(None);
    }

    /// After a raw command the addressing MAY have changed (`raw ATSH 7E0`
    /// leaves it on 7E0, not 7DF). Unknown forces the next request to
    /// re-establish header and filter explicitly.
    fn mark_addressing_unknown(&mut self) {
        self.header = Cached::Unknown;
        self.filter = Cached::Unknown;
    }

    fn start_reset(&mut self, now_ms: u64) {
        self.reset_addressing_to_defaults();
        self.prep.clear();
        self.prep_index = 0;
        self.set_state(ElmState::Resetting);
        self.send_line("ATZ");
        self.deadline_ms = now_ms + self.cfg.reset_timeout_ms;
    }

    fn send_init_command(&mut self, now_ms: u64) {
        let Some(cmd) = self.cfg.init_commands.get(self.init_index).cloned() else {
            return;
        };
        // An init list that sets a header or filter leaves the cache wrong.
        let upper = cmd.replace(' ', "").to_ascii_uppercase();
        if upper.starts_with("ATSH") {
            self.header = Cached::Unknown;
        } else if upper.starts_with("ATCRA") {
            self.filter = Cached::Unknown;
        }
        self.send_line(&cmd);
        self.deadline_ms = now_ms + self.cfg.init_timeout_ms;
    }

    fn send_next_prep(&mut self, now_ms: u64) {
        let Some(cmd) = self.prep.get(self.prep_index).cloned() else {
            return;
        };
        self.send_line(&cmd);
        self.prep_command_count += 1;
        self.deadline_ms = now_ms + self.cfg.init_timeout_ms;
    }

    fn send_request(&mut self, now_ms: u64) {
        let first_data_done = self.first_data_done;
        let first_timeout = self.cfg.first_data_timeout_ms;
        let Some(cur) = self.current.as_mut() else {
            return;
        };
        let Kind::Obd(req) = &cur.kind else {
            return;
        };
        let mut cmd = req.command.request_hex();
        // Optional response-count digit: the adapter returns as soon as N
        // replies arrive. Validated at submit: 1..=9, physical header only.
        if let Some(n) = req.expected_responses {
            cmd.push(char::from(b'0' + n));
        }
        // The very first request can trigger SEARCHING: long deadline.
        let timeout = if first_data_done {
            req.timeout_ms
        } else {
            first_timeout
        };
        // Anything heard during prep was not an answer to this request.
        cur.c = Collect::default();
        cur.request_sent_ms = Some(now_ms);
        self.assembler.reset();
        self.send_line(&cmd);
        self.deadline_ms = now_ms + timeout;
    }

    fn handle_line(&mut self, line: &str, now_ms: u64) {
        // Echo suppression: before ATE0 takes effect the adapter repeats every
        // command. A line identical to what we last sent is never data.
        if !self.last_sent.is_empty() && line == self.last_sent {
            return;
        }
        let cls = classify_line(line);
        if cls == LineClass::Ignorable {
            self.emit(ElmEvent::AdapterAlert {
                line: line.to_owned(),
            });
        }
        match self.state {
            ElmState::AwaitingResponse => self.handle_request_line(line, cls, now_ms),
            ElmState::Resetting => {
                // First meaningful line after ATZ is the banner ("ELM327 v1.4b").
                if cls == LineClass::Unknown && self.adapter_id.is_none() {
                    self.adapter_id = Some(line.to_owned());
                }
            }
            ElmState::Initializing => {
                if cls == LineClass::Error {
                    self.init_cmd_failed = true;
                }
            }
            ElmState::Recovering
                if self.recovery == RecoveryPhase::Probing && self.is_probe_answer(line) =>
            {
                self.recovery = RecoveryPhase::ProbeAnswered;
            }
            ElmState::Idle | ElmState::Recovering => {
                if cls != LineClass::Ignorable {
                    let state = self.state;
                    self.emit(ElmEvent::StrayLine {
                        state,
                        line: line.to_owned(),
                    });
                }
            }
            ElmState::Offline => {}
        }
    }

    fn handle_request_line(&mut self, line: &str, cls: LineClass, now_ms: u64) {
        let in_prep = self.prep_index < self.prep.len();
        let prep_cmd = self.prep.get(self.prep_index).cloned();
        let Some(cur) = self.current.as_mut() else {
            return;
        };
        let mut stray = false;
        match &cur.kind {
            // Raw passthrough: the operator asked for exactly what the adapter
            // said, so no classification and no interpretation.
            Kind::Raw(_) => {
                let id = cur.id;
                self.emit(ElmEvent::RawLine {
                    id,
                    line: line.to_owned(),
                });
                return;
            }
            Kind::Obd(_) if in_prep => match cls {
                LineClass::Ok | LineClass::Ignorable => {}
                LineClass::Error
                | LineClass::CanError
                | LineClass::BufferFull
                | LineClass::UnableToConnect => {
                    if cur.c.error.is_none() {
                        cur.c.error = Some(ErrorCause::AddressingRejected {
                            command: prep_cmd.unwrap_or_default(),
                            line: line.to_owned(),
                        });
                    }
                }
                _ => stray = true,
            },
            Kind::Voltage => {
                if let Some(v) = parse_voltage(line) {
                    cur.c.volts.get_or_insert(v);
                } else if cls == LineClass::Stopped {
                    cur.c.stopped = true;
                } else if let Some(e) = adapter_error(cls, line) {
                    cur.c.error.get_or_insert(e);
                } else if cls != LineClass::Ignorable {
                    stray = true;
                }
            }
            Kind::Obd(_) => match cls {
                LineClass::HexData => {
                    if !self.handle_data_line(line) {
                        stray = true;
                    }
                }
                LineClass::NoData => cur.c.no_data = true,
                LineClass::Stopped => cur.c.stopped = true,
                LineClass::Searching => {
                    // Protocol auto-detect in progress: give it the long deadline.
                    self.deadline_ms = now_ms + self.cfg.first_data_timeout_ms;
                }
                LineClass::Ok | LineClass::Ignorable => {}
                LineClass::CanError
                | LineClass::BufferFull
                | LineClass::UnableToConnect
                | LineClass::Error => {
                    if let Some(e) = adapter_error(cls, line) {
                        cur.c.error.get_or_insert(e);
                    }
                }
                LineClass::Unknown => stray = true,
            },
        }
        if stray {
            self.emit(ElmEvent::StrayLine {
                state: ElmState::AwaitingResponse,
                line: line.to_owned(),
            });
        }
    }

    /// Returns false if the line was malformed.
    fn handle_data_line(&mut self, line: &str) -> bool {
        let Some(frame) = parse_data_line(&strip_spaces(line)) else {
            return false;
        };
        let max = self.cfg.max_recorded_responders;
        let Some(cur) = self.current.as_mut() else {
            return true;
        };
        let Kind::Obd(req) = &cur.kind else {
            return true;
        };

        // Drop other ECUs' frames BEFORE reassembly, so a pinned request
        // never sees (or counts, or logs) another module's answer.
        if let (Some(expected), Some(id)) = (req.expected_responder, frame.can_id)
            && id != expected
        {
            cur.c.ignored_frames += 1;
            return true;
        }

        let Some(msg) = self.assembler.feed(&frame) else {
            return true; // multi-frame in progress, or frame ignored
        };
        let p = msg.data.as_slice();
        let Some(&first) = p.first() else {
            return true;
        };

        // Negative response: 7F <service> <NRC>.
        if first == 0x7F {
            let neg = NegativeResponse {
                can_id: msg.source,
                service: p.get(1).copied(),
                nrc: p.get(2).copied(),
            };
            cur.c.error.get_or_insert(ErrorCause::NegativeResponse(neg));
            if cur.c.negatives.len() < max {
                cur.c.negatives.push(neg);
            }
            return true;
        }

        // Validate the positive-response echo, then strip it.
        if !req.command.matches_positive(p) {
            cur.c.unmatched_payloads += 1;
            return true;
        }
        let body = p[req.command.echo_len()..].to_vec();
        cur.c.responder_count += 1;

        // Record what this ECU said, verbatim and in arrival order. Recording
        // rather than adjudicating is the point: only decoded values across
        // several samples can say whether two answers mean the same thing.
        if cur.c.responders.len() < max {
            cur.c.responders.push(ResponderAnswer {
                can_id: msg.source,
                payload: body.clone(),
            });
        }
        // The FIRST matching answer is the reported one.
        if cur.c.first.is_none() {
            cur.c.first = Some((msg.source, body));
        }
        true
    }

    fn handle_prompt(&mut self, now_ms: u64) {
        match self.state {
            ElmState::Resetting => {
                self.init_index = 0;
                self.init_retries = 0;
                self.init_cmd_failed = false;
                if self.cfg.init_commands.is_empty() {
                    self.init_complete();
                } else {
                    self.set_state(ElmState::Initializing);
                    self.send_init_command(now_ms);
                }
            }
            ElmState::Initializing => {
                if self.init_cmd_failed && self.init_retries < 1 {
                    self.init_retries += 1;
                    self.init_cmd_failed = false;
                    self.send_init_command(now_ms); // retry the same command once
                    return;
                }
                if self.init_cmd_failed {
                    // Keeps failing: continue, but loudly. Some settings may
                    // simply be unsupported; the request path surfaces damage.
                    let command = self
                        .cfg
                        .init_commands
                        .get(self.init_index)
                        .cloned()
                        .unwrap_or_default();
                    self.emit(ElmEvent::InitCommandFailed { command });
                }
                self.init_index += 1;
                self.init_retries = 0;
                self.init_cmd_failed = false;
                if self.init_index >= self.cfg.init_commands.len() {
                    self.init_complete();
                } else {
                    self.send_init_command(now_ms);
                }
            }
            ElmState::AwaitingResponse => self.request_prompt(now_ms),
            ElmState::Recovering => match self.recovery {
                RecoveryPhase::AwaitingLateReply | RecoveryPhase::ProbeAnswered => {
                    self.set_state(ElmState::Idle);
                }
                // A straggler's prompt: the ATI answer has not come yet.
                RecoveryPhase::Probing => {}
            },
            ElmState::Idle | ElmState::Offline => {}
        }
    }

    /// `ATI` answers with the same identification as the `ATZ` banner.
    fn is_probe_answer(&self, line: &str) -> bool {
        line.starts_with("ELM327") || self.adapter_id.as_deref() == Some(line)
    }

    fn init_complete(&mut self) {
        self.reset_attempts = 0;
        self.set_state(ElmState::Idle);
        let adapter_id = self.adapter_id.clone();
        self.emit(ElmEvent::Ready { adapter_id });
    }

    fn request_prompt(&mut self, now_ms: u64) {
        let in_prep = self.prep_index < self.prep.len();
        let Some(cur) = self.current.as_mut() else {
            self.set_state(ElmState::Idle);
            return;
        };
        let result = match &cur.kind {
            Kind::Raw(_) => ElmResult::Ok,
            Kind::Voltage => {
                if cur.c.volts.is_some() {
                    ElmResult::Ok
                } else if cur.c.stopped {
                    ElmResult::Stopped
                } else {
                    ElmResult::Error(cur.c.error.take().unwrap_or(ErrorCause::EmptyResponse))
                }
            }
            Kind::Obd(_) if in_prep => {
                if let Some(err) = cur.c.error.take() {
                    self.complete(ElmResult::Error(err), now_ms);
                    return;
                }
                // Prep command accepted: commit its effect to the cache.
                let acked = self.prep.get(self.prep_index).cloned().unwrap_or_default();
                if let Some(h) = acked.strip_prefix("ATSH") {
                    self.header = Cached::Known(h.to_owned());
                } else if let Some(f) = acked.strip_prefix("ATCRA") {
                    self.filter = Cached::Known((!f.is_empty()).then(|| f.to_owned()));
                }
                self.prep_index += 1;
                if self.prep_index < self.prep.len() {
                    self.send_next_prep(now_ms);
                } else {
                    self.prep_overhead_ms += now_ms.saturating_sub(self.prep_start_ms);
                    self.send_request(now_ms);
                }
                return;
            }
            Kind::Obd(_) => {
                if cur.c.first.is_some() {
                    ElmResult::Ok
                } else if cur.c.stopped {
                    ElmResult::Stopped
                } else if cur.c.ignored_frames > 0 {
                    // Somebody answered, just not the module this is pinned to.
                    ElmResult::NoResponder
                } else if cur.c.no_data {
                    ElmResult::NoData
                } else {
                    ElmResult::Error(cur.c.error.take().unwrap_or(ErrorCause::EmptyResponse))
                }
            }
        };
        self.complete(result, now_ms);
    }

    /// Finish the request and return to Idle with a benign idle deadline.
    fn complete(&mut self, result: ElmResult, now_ms: u64) {
        self.set_state(ElmState::Idle);
        self.deadline_ms = now_ms + self.cfg.recovery_timeout_ms;
        self.finish(result, now_ms);
    }

    /// Emit the completion event. Does not change state.
    fn finish(&mut self, result: ElmResult, now_ms: u64) {
        let Some(cur) = self.current.take() else {
            return;
        };
        self.prep.clear();
        self.prep_index = 0;
        if matches!(cur.kind, Kind::Raw(_)) {
            // A raw command may have been ATZ/ATSH/ATCRA/ATSP.
            self.mark_addressing_unknown();
        }
        if result.is_ok() {
            self.consecutive_timeouts = 0;
            self.first_data_done = true;
        }
        let latency_ms = now_ms.saturating_sub(cur.submitted_ms);
        let ev = match cur.kind {
            Kind::Raw(command) => ElmEvent::RawComplete(RawComplete {
                id: cur.id,
                command,
                result,
                latency_ms,
            }),
            Kind::Voltage => ElmEvent::Voltage(VoltageResponse {
                id: cur.id,
                volts: if result.is_ok() { cur.c.volts } else { None },
                result,
                latency_ms,
            }),
            Kind::Obd(request) => {
                let c = cur.c;
                let (responder_id, payload) = if result.is_ok() {
                    c.first.unwrap_or_default()
                } else {
                    (None, Vec::new())
                };
                let responders_differ = c
                    .responders
                    .split_first()
                    .is_some_and(|(a, rest)| rest.iter().any(|r| r.payload != a.payload));
                ElmEvent::ObdResponse(Box::new(ObdResponse {
                    id: cur.id,
                    request,
                    result,
                    payload,
                    responder_id,
                    responder_count: c.responder_count,
                    responders: c.responders,
                    responders_differ,
                    negative_responses: c.negatives,
                    ignored_responder_frames: c.ignored_frames,
                    unmatched_payloads: c.unmatched_payloads,
                    latency_ms,
                    wire_latency_ms: cur.request_sent_ms.map(|t| now_ms.saturating_sub(t)),
                }))
            }
        };
        self.emit(ev);
    }

    fn handle_timeout(&mut self, now_ms: u64) {
        match self.state {
            ElmState::Resetting => self.escalate_or_reset(now_ms, ResetReason::ResetTimeout),
            ElmState::Initializing => self.escalate_or_reset(now_ms, ResetReason::InitTimeout),
            ElmState::AwaitingResponse => {
                self.consecutive_timeouts = self.consecutive_timeouts.saturating_add(1);
                self.finish(ElmResult::Timeout, now_ms);
                if self.consecutive_timeouts >= self.cfg.max_consecutive_timeouts {
                    // Repeated timeouts on a previously healthy link usually
                    // mean the STN slept or the bus dropped: full re-init.
                    self.consecutive_timeouts = 0;
                    self.escalate_or_reset(now_ms, ResetReason::ConsecutiveTimeouts);
                } else {
                    // A slow reply usually still ends in its own prompt: wait
                    // for it, sending nothing (see RecoveryStep::AwaitLateReply).
                    self.set_state(ElmState::Recovering);
                    self.recovery = RecoveryPhase::AwaitingLateReply;
                    let consecutive_timeouts = self.consecutive_timeouts;
                    self.emit(ElmEvent::Recovery(RecoveryStep::AwaitLateReply {
                        consecutive_timeouts,
                    }));
                    self.deadline_ms = now_ms + self.cfg.late_reply_timeout_ms;
                }
            }
            ElmState::Recovering => match self.recovery {
                RecoveryPhase::AwaitingLateReply => {
                    // The request (or its answer) was lost: ask the adapter
                    // something whose answer can be recognised.
                    self.recovery = RecoveryPhase::Probing;
                    self.emit(ElmEvent::Recovery(RecoveryStep::ProbeAdapter));
                    self.send_line(PROBE_COMMAND);
                    self.deadline_ms = now_ms + self.cfg.recovery_timeout_ms;
                }
                RecoveryPhase::Probing | RecoveryPhase::ProbeAnswered => {
                    self.escalate_or_reset(now_ms, ResetReason::RecoveryFailed);
                }
            },
            ElmState::Idle => {
                // Idle deadline is benign: refresh it.
                self.deadline_ms = now_ms + self.cfg.recovery_timeout_ms;
            }
            ElmState::Offline => {}
        }
    }

    fn escalate_or_reset(&mut self, now_ms: u64, reason: ResetReason) {
        if self.reset_attempts < self.cfg.max_reset_attempts {
            self.reset_attempts += 1;
            let (attempt, max) = (self.reset_attempts, self.cfg.max_reset_attempts);
            self.emit(ElmEvent::Recovery(RecoveryStep::AdapterReset {
                attempt,
                max,
                reason,
            }));
            self.start_reset(now_ms);
        } else {
            // Unresponsive: the owner drops and re-establishes the transport.
            self.emit(ElmEvent::Recovery(RecoveryStep::GaveUp { reason }));
            self.set_state(ElmState::Offline);
        }
    }
}
