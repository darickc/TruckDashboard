//! The signal registry: `shared/signals/*.yaml`, loaded and validated.
//!
//! Field meanings are in `docs/architecture/telemetry-model.md`; the
//! format is described in `shared/signals/README.md`. Loading is strict:
//! unknown fields, unparsable formulas or ids, and every rule below are
//! errors, and all problems are reported at once.
//!
//! Rules enforced by [`Registry::from_defs`] (and so by every loader):
//!
//! - ids are snake_case, not a formula function name, and unique
//! - `unit` is the canonical unit of `quantity`; `range` is finite, min < max
//! - `source` and `provenance` agree (computed ⇔ `COMPUTED`, aux ⇔
//!   `AUX_SENSOR`, diagnostic ⇔ `SAE`/`VERIFIED_ON_TRUCK`/`IMPORTED_UNVERIFIED`)
//! - `VERIFIED_ON_TRUCK` requires `evidence`
//! - an enabled `IMPORTED_UNVERIFIED` signal requires `allow_unverified: true`
//! - a diagnostic request's service byte is on the ADR-0007 read-only
//!   allow-list ([`ALLOWED_SERVICES`]), and `response.expect` is its
//!   positive-response echo
//! - the decode formula parses, its unit measures `quantity`, and
//!   `response.length` ≥ the bytes the formula needs; references name
//!   existing, non-computed signals
//! - computed signals: inputs exist, are not computed, and are exactly the
//!   signals `compute` references; `compute` uses no payload bytes
//! - calibration scale within 0.5–2.0; computed signals aren't calibrated
//! - CAN ids are `0x`-hex and fit in 29 bits

use std::collections::{BTreeSet, HashMap, HashSet};
use std::fmt;
use std::path::{Path, PathBuf};
use std::time::Duration;

use serde::Deserialize;

use crate::calibration::{Calibration, CalibrationError};
use crate::formula::{self, EvalError, Formula, ParseError};
use crate::units::{self, Quantity, Unit, UnitMismatch};

/// ADR-0007: the only diagnostic services a request may use. All are reads:
/// current data (01), stored DTCs (03), pending DTCs (07), vehicle info (09)
/// and read-data-by-identifier (22). Everything else is refused.
pub const ALLOWED_SERVICES: [u8; 5] = [0x01, 0x03, 0x07, 0x09, 0x22];

/// Whether a request may use service byte `sid` (ADR-0007).
pub fn service_allowed(sid: u8) -> bool {
    ALLOWED_SERVICES.contains(&sid)
}

/// Default `max_input_skew_ms` for computed signals.
pub const DEFAULT_MAX_INPUT_SKEW: Duration = Duration::from_millis(2000);

/// Largest 29-bit (extended) CAN identifier.
const MAX_CAN_ID: u32 = 0x1FFF_FFFF;

// ---------------------------------------------------------------------------
// Typed definitions
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Source {
    Diagnostic,
    Broadcast,
    Computed,
    Aux,
}

/// How much to trust a definition (telemetry-model.md § Provenance).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum Provenance {
    /// Published SAE J1979 formula.
    Sae,
    /// Confirmed on this truck, with a VERIFICATION_LOG.md entry.
    VerifiedOnTruck,
    /// From the Torque export or another tool; not confirmed.
    ImportedUnverified,
    /// Derived from other signals.
    Computed,
    /// Added hardware.
    AuxSensor,
    /// Decoded from passive CAN traffic.
    BroadcastDecoded,
}

impl fmt::Display for Provenance {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Provenance::Sae => "SAE",
            Provenance::VerifiedOnTruck => "VERIFIED_ON_TRUCK",
            Provenance::ImportedUnverified => "IMPORTED_UNVERIFIED",
            Provenance::Computed => "COMPUTED",
            Provenance::AuxSensor => "AUX_SENSOR",
            Provenance::BroadcastDecoded => "BROADCAST_DECODED",
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Protocol {
    Iso15765,
    Elm,
}

/// What to send, and who owns the answer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Request {
    pub protocol: Protocol,
    /// Request CAN id (e.g. 0x7DF functional).
    pub tx_id: u32,
    /// Responder that owns the value, once established on the truck.
    pub rx_id: Option<u32>,
    /// Service and DID/PID bytes.
    pub payload: Vec<u8>,
}

impl Request {
    pub fn service(&self) -> Option<u8> {
        self.payload.first().copied()
    }
}

/// What a positive answer looks like.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResponseSpec {
    /// Positive-response echo, stripped before decoding.
    pub expect: Vec<u8>,
    /// Payload bytes required after the echo; fewer is a decode error.
    pub length: usize,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Decode {
    pub formula: Formula,
    /// Unit the formula produces; converted to the canonical unit.
    pub unit: Unit,
    /// Accepted for the documented schema; only `false` is valid. Signed
    /// bytes are expressed with `signed(x)` in the formula.
    pub signed: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Range {
    pub min: f64,
    pub max: f64,
}

impl Range {
    pub fn contains(&self, v: f64) -> bool {
        v.is_finite() && v >= self.min && v <= self.max
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Poll {
    /// 0 is highest.
    pub priority: u8,
    /// A target; the scheduler may stretch it.
    pub interval_ms: u64,
    pub timeout_ms: u64,
}

/// One signal definition.
#[derive(Debug, Clone, PartialEq)]
pub struct SignalDef {
    pub id: String,
    pub name: String,
    pub short_name: String,
    pub quantity: Quantity,
    /// Canonical unit of `range` and of every value.
    pub unit: Unit,
    pub source: Source,
    pub request: Option<Request>,
    pub response: Option<ResponseSpec>,
    pub decode: Option<Decode>,
    pub range: Range,
    pub poll: Option<Poll>,
    /// `None` only for computed signals, which follow their inputs.
    pub stale_after: Option<Duration>,
    pub provenance: Provenance,
    pub evidence: Option<String>,
    pub enabled: bool,
    pub allow_unverified: bool,
    pub calibration: Option<Calibration>,
    /// Computed signals: input ids.
    pub inputs: Vec<String>,
    /// Computed signals: formula over the inputs (canonical units).
    pub compute: Option<Formula>,
    /// Computed signals: inputs must be measured this close together.
    pub max_input_skew: Option<Duration>,
    pub notes: Option<String>,
}

/// Why a response could not be decoded (→ `DECODE_ERROR`).
#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum DecodeError {
    #[error("signal has no diagnostic decode")]
    NotDiagnostic,
    #[error("response does not start with the expected echo {expected}")]
    EchoMismatch { expected: String },
    #[error("payload has {got} byte(s), {required} required")]
    TooShort { required: usize, got: usize },
    #[error(transparent)]
    Eval(#[from] EvalError),
    #[error(transparent)]
    Unit(#[from] UnitMismatch),
}

impl SignalDef {
    pub fn is_computed(&self) -> bool {
        self.source == Source::Computed
    }

    /// Computed signals' input skew limit, with the default applied.
    pub fn input_skew_limit(&self) -> Duration {
        self.max_input_skew.unwrap_or(DEFAULT_MAX_INPUT_SKEW)
    }

    /// Decodes a complete positive response (echo included) into the
    /// canonical unit, before calibration. `signal` resolves references.
    pub fn decode_response(
        &self,
        response: &[u8],
        signal: &dyn Fn(&str) -> Option<f64>,
    ) -> Result<f64, DecodeError> {
        let spec = self.response.as_ref().ok_or(DecodeError::NotDiagnostic)?;
        let payload = response
            .strip_prefix(spec.expect.as_slice())
            .ok_or_else(|| DecodeError::EchoMismatch {
                expected: format_bytes(&spec.expect),
            })?;
        self.decode_payload(payload, signal)
    }

    /// Decodes a payload (echo already stripped) into the canonical unit,
    /// before calibration.
    pub fn decode_payload(
        &self,
        payload: &[u8],
        signal: &dyn Fn(&str) -> Option<f64>,
    ) -> Result<f64, DecodeError> {
        let (Some(decode), Some(spec)) = (&self.decode, &self.response) else {
            return Err(DecodeError::NotDiagnostic);
        };
        if payload.len() < spec.length {
            return Err(DecodeError::TooShort {
                required: spec.length,
                got: payload.len(),
            });
        }
        let native = decode.formula.eval(payload, signal)?;
        Ok(units::to_canonical(self.quantity, decode.unit, native)?)
    }
}

/// `[0x22, 0x16, 0x74]` → `"22 16 74"`.
pub fn format_bytes(bytes: &[u8]) -> String {
    bytes
        .iter()
        .map(|b| format!("{b:02X}"))
        .collect::<Vec<_>>()
        .join(" ")
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// One validation failure.
#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum Problem {
    #[error("id is not snake_case or is a reserved word")]
    BadId,
    #[error("duplicate id (first defined in {first})")]
    DuplicateId { first: String },
    #[error("unit {unit} is not the canonical unit of {quantity} ({canonical})")]
    NotCanonicalUnit {
        unit: Unit,
        quantity: Quantity,
        canonical: Unit,
    },
    #[error("range must be finite with min < max")]
    BadRange,
    #[error("source {signal_source:?} does not match provenance {provenance}")]
    SourceProvenanceMismatch {
        signal_source: Source,
        provenance: Provenance,
    },
    #[error("VERIFIED_ON_TRUCK requires `evidence` (a VERIFICATION_LOG.md entry)")]
    MissingEvidence,
    #[error("enabled IMPORTED_UNVERIFIED signal requires `allow_unverified: true`")]
    UnverifiedEnabled,
    #[error("`{0}` is required for this source")]
    MissingField(&'static str),
    #[error("`{0}` is not allowed for this source")]
    UnexpectedField(&'static str),
    #[error("{field}: {value:?} is not {expected}")]
    BadHex {
        field: &'static str,
        value: String,
        expected: &'static str,
    },
    #[error("request payload is empty")]
    EmptyPayload,
    #[error("service 0x{0:02X} is not on the read-only allow-list (ADR-0007)")]
    ServiceNotAllowed(u8),
    #[error("response.expect {expect} is not the positive-response echo of {payload}")]
    EchoMismatch { expect: String, payload: String },
    #[error("{field}: {error}")]
    Formula {
        field: &'static str,
        error: ParseError,
    },
    #[error("response.length {length} is less than the {required} byte(s) the formula needs")]
    ResponseTooShort { length: usize, required: usize },
    #[error("decode.unit: {0}")]
    DecodeUnit(UnitMismatch),
    #[error("decode.signed: true is not supported; use signed(x) in the formula")]
    SignedNotSupported,
    #[error("formula references unknown signal {0:?}")]
    UnknownReference(String),
    #[error("formula references computed signal {0:?}")]
    ComputedReference(String),
    #[error("formula references the signal itself")]
    SelfReference,
    #[error("input {0:?} does not exist")]
    UnknownInput(String),
    #[error("input {0:?} is itself computed")]
    ComputedInput(String),
    #[error("inputs listed more than once")]
    DuplicateInput,
    #[error("compute must reference exactly the inputs {inputs:?}, references {references:?}")]
    ComputeInputsMismatch {
        inputs: Vec<String>,
        references: Vec<String>,
    },
    #[error("compute must not use payload bytes")]
    ComputeUsesBytes,
    #[error("calibration: {0}")]
    Calibration(CalibrationError),
    #[error("poll interval_ms and timeout_ms must be > 0")]
    BadPoll,
    #[error("stale_after_ms must be > 0")]
    BadStaleAfter,
    #[error("broadcast decoding is not defined yet (TODO); no broadcast signals can be loaded")]
    BroadcastUnsupported,
}

/// A problem, and where it was found.
#[derive(Debug, Clone, PartialEq)]
pub struct Issue {
    pub file: Option<PathBuf>,
    pub signal: Option<String>,
    pub problem: Problem,
}

impl fmt::Display for Issue {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if let Some(file) = &self.file {
            write!(f, "{}: ", file.display())?;
        }
        if let Some(signal) = &self.signal {
            write!(f, "{signal}: ")?;
        }
        write!(f, "{}", self.problem)
    }
}

#[derive(Debug, thiserror::Error)]
pub enum RegistryError {
    #[error("{path}: {source}")]
    Io {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("{path}: {source}")]
    Yaml {
        path: PathBuf,
        source: yaml_serde::Error,
    },
    #[error("invalid signal registry:\n{}", .0.iter().map(|i| format!("  {i}")).collect::<Vec<_>>().join("\n"))]
    Invalid(Vec<Issue>),
}

impl RegistryError {
    /// The validation issues, if this is a validation error.
    pub fn issues(&self) -> &[Issue] {
        match self {
            RegistryError::Invalid(issues) => issues,
            _ => &[],
        }
    }
}

// ---------------------------------------------------------------------------
// Raw (YAML) form
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawSignal {
    id: String,
    name: String,
    short_name: String,
    quantity: Quantity,
    unit: Unit,
    source: Source,
    request: Option<RawRequest>,
    response: Option<RawResponse>,
    decode: Option<RawDecode>,
    range: Range,
    poll: Option<Poll>,
    stale_after_ms: Option<u64>,
    provenance: Provenance,
    evidence: Option<String>,
    enabled: bool,
    #[serde(default)]
    allow_unverified: bool,
    calibration: Option<RawCalibration>,
    inputs: Option<Vec<String>>,
    compute: Option<String>,
    max_input_skew_ms: Option<u64>,
    notes: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawRequest {
    protocol: Protocol,
    tx_id: String,
    rx_id: Option<String>,
    payload: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawResponse {
    expect: String,
    length: usize,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawDecode {
    formula: String,
    unit: Unit,
    #[serde(default)]
    signed: bool,
}

fn default_scale() -> f64 {
    1.0
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawCalibration {
    #[serde(default = "default_scale")]
    scale: f64,
    #[serde(default)]
    offset: f64,
    note: Option<String>,
}

fn parse_can_id(field: &'static str, s: &str) -> Result<u32, Problem> {
    let bad = || Problem::BadHex {
        field,
        value: s.to_owned(),
        expected: "a 0x-prefixed hex CAN id up to 0x1FFFFFFF",
    };
    let digits = s.strip_prefix("0x").ok_or_else(bad)?;
    if digits.is_empty() || digits.len() > 8 || !digits.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(bad());
    }
    let id = u32::from_str_radix(digits, 16).map_err(|_| bad())?;
    if id > MAX_CAN_ID {
        return Err(bad());
    }
    Ok(id)
}

fn parse_bytes(field: &'static str, s: &str) -> Result<Vec<u8>, Problem> {
    let bad = || Problem::BadHex {
        field,
        value: s.to_owned(),
        expected: "space-separated two-digit hex bytes, e.g. \"22 16 74\"",
    };
    s.split_whitespace()
        .map(|b| {
            if b.len() == 2 {
                u8::from_str_radix(b, 16).map_err(|_| bad())
            } else {
                Err(bad())
            }
        })
        .collect()
}

/// Converts the YAML form, collecting every parse-level problem.
fn from_raw(raw: RawSignal) -> Result<SignalDef, Vec<Problem>> {
    let mut problems = Vec::new();

    let request = raw.request.and_then(|r| {
        let tx = parse_can_id("request.tx_id", &r.tx_id);
        let rx = r
            .rx_id
            .as_deref()
            .map(|s| parse_can_id("request.rx_id", s))
            .transpose();
        let payload = parse_bytes("request.payload", &r.payload);
        match (tx, rx, payload) {
            (Ok(tx_id), Ok(rx_id), Ok(payload)) => Some(Request {
                protocol: r.protocol,
                tx_id,
                rx_id,
                payload,
            }),
            (tx, rx, payload) => {
                problems.extend(tx.err());
                problems.extend(rx.err());
                problems.extend(payload.err());
                None
            }
        }
    });

    let response = raw
        .response
        .and_then(|r| match parse_bytes("response.expect", &r.expect) {
            Ok(expect) => Some(ResponseSpec {
                expect,
                length: r.length,
            }),
            Err(p) => {
                problems.push(p);
                None
            }
        });

    let decode = raw.decode.and_then(|d| match Formula::parse(&d.formula) {
        Ok(formula) => Some(Decode {
            formula,
            unit: d.unit,
            signed: d.signed,
        }),
        Err(error) => {
            problems.push(Problem::Formula {
                field: "decode.formula",
                error,
            });
            None
        }
    });

    let compute = raw.compute.and_then(|c| match Formula::parse(&c) {
        Ok(f) => Some(f),
        Err(error) => {
            problems.push(Problem::Formula {
                field: "compute",
                error,
            });
            None
        }
    });

    let calibration =
        raw.calibration
            .and_then(|c| match Calibration::new(c.scale, c.offset, c.note) {
                Ok(c) => Some(c),
                Err(e) => {
                    problems.push(Problem::Calibration(e));
                    None
                }
            });

    let stale_after = raw
        .stale_after_ms
        .or_else(|| raw.poll.map(|p| p.interval_ms.saturating_mul(3)))
        .map(Duration::from_millis);

    if !problems.is_empty() {
        return Err(problems);
    }
    Ok(SignalDef {
        id: raw.id,
        name: raw.name,
        short_name: raw.short_name,
        quantity: raw.quantity,
        unit: raw.unit,
        source: raw.source,
        request,
        response,
        decode,
        range: raw.range,
        poll: raw.poll,
        stale_after,
        provenance: raw.provenance,
        evidence: raw.evidence,
        enabled: raw.enabled,
        allow_unverified: raw.allow_unverified,
        calibration,
        inputs: raw.inputs.unwrap_or_default(),
        compute,
        max_input_skew: raw.max_input_skew_ms.map(Duration::from_millis),
        notes: raw.notes,
    })
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/// `unparsed` holds ids of signals that failed to parse; they exist, so
/// references to them are not reported a second time.
fn check_def(
    def: &SignalDef,
    all: &HashMap<&str, &SignalDef>,
    unparsed: &HashSet<String>,
) -> Vec<Problem> {
    let mut p = Vec::new();

    if !formula::is_snake_case_id(&def.id) || formula::RESERVED_WORDS.contains(&def.id.as_str()) {
        p.push(Problem::BadId);
    }
    let canonical = def.quantity.canonical_unit();
    if def.unit != canonical {
        p.push(Problem::NotCanonicalUnit {
            unit: def.unit,
            quantity: def.quantity,
            canonical,
        });
    }
    if !(def.range.min.is_finite() && def.range.max.is_finite() && def.range.min < def.range.max) {
        p.push(Problem::BadRange);
    }

    let provenance_ok = match def.source {
        Source::Diagnostic => matches!(
            def.provenance,
            Provenance::Sae | Provenance::VerifiedOnTruck | Provenance::ImportedUnverified
        ),
        Source::Computed => def.provenance == Provenance::Computed,
        Source::Aux => def.provenance == Provenance::AuxSensor,
        Source::Broadcast => def.provenance == Provenance::BroadcastDecoded,
    };
    if !provenance_ok {
        p.push(Problem::SourceProvenanceMismatch {
            signal_source: def.source,
            provenance: def.provenance,
        });
    }
    if def.provenance == Provenance::VerifiedOnTruck
        && def.evidence.as_deref().is_none_or(|e| e.trim().is_empty())
    {
        p.push(Problem::MissingEvidence);
    }
    if def.provenance == Provenance::ImportedUnverified && def.enabled && !def.allow_unverified {
        p.push(Problem::UnverifiedEnabled);
    }
    if let Some(poll) = def.poll
        && (poll.interval_ms == 0 || poll.timeout_ms == 0)
    {
        p.push(Problem::BadPoll);
    }
    if def.stale_after.is_some_and(|d| d.is_zero()) {
        p.push(Problem::BadStaleAfter);
    }

    // Shape by source.
    let mut require = |present: bool, field: &'static str| {
        if !present {
            p.push(Problem::MissingField(field));
        }
    };
    match def.source {
        Source::Diagnostic => {
            require(def.request.is_some(), "request");
            require(def.response.is_some(), "response");
            require(def.decode.is_some(), "decode");
            require(def.poll.is_some(), "poll");
        }
        Source::Computed => {
            require(!def.inputs.is_empty(), "inputs");
            require(def.compute.is_some(), "compute");
        }
        Source::Aux => require(def.stale_after.is_some(), "stale_after_ms"),
        Source::Broadcast => {}
    }
    let mut forbid = |present: bool, field: &'static str| {
        if present {
            p.push(Problem::UnexpectedField(field));
        }
    };
    if def.source != Source::Diagnostic {
        forbid(def.request.is_some(), "request");
        forbid(def.response.is_some(), "response");
        forbid(def.decode.is_some(), "decode");
        forbid(def.poll.is_some(), "poll");
    }
    if def.source == Source::Computed {
        forbid(def.stale_after.is_some(), "stale_after_ms");
        forbid(def.calibration.is_some(), "calibration");
    } else {
        forbid(!def.inputs.is_empty(), "inputs");
        forbid(def.compute.is_some(), "compute");
        forbid(def.max_input_skew.is_some(), "max_input_skew_ms");
    }
    if def.source == Source::Broadcast {
        p.push(Problem::BroadcastUnsupported);
    }

    if let Some(req) = &def.request {
        match req.service() {
            None => p.push(Problem::EmptyPayload),
            Some(sid) if !service_allowed(sid) => p.push(Problem::ServiceNotAllowed(sid)),
            Some(_) => {}
        }
        if let Some(resp) = &def.response {
            let echo_ok = match (req.payload.split_first(), resp.expect.split_first()) {
                (Some((sid, rest)), Some((rsid, rrest))) => {
                    sid.checked_add(0x40) == Some(*rsid) && rest == rrest
                }
                _ => false,
            };
            if !echo_ok {
                p.push(Problem::EchoMismatch {
                    expect: format_bytes(&resp.expect),
                    payload: format_bytes(&req.payload),
                });
            }
        }
    }

    if let Some(decode) = &def.decode {
        if let Err(e) = units::to_canonical(def.quantity, decode.unit, 0.0) {
            p.push(Problem::DecodeUnit(e));
        }
        if decode.signed {
            p.push(Problem::SignedNotSupported);
        }
        let required = decode.formula.bytes_required();
        if let Some(resp) = &def.response
            && resp.length < required
        {
            p.push(Problem::ResponseTooShort {
                length: resp.length,
                required,
            });
        }
        for r in decode.formula.references() {
            if r == def.id {
                p.push(Problem::SelfReference);
            } else {
                match all.get(r.as_str()) {
                    None if unparsed.contains(&r) => {}
                    None => p.push(Problem::UnknownReference(r)),
                    Some(d) if d.is_computed() => p.push(Problem::ComputedReference(r)),
                    Some(_) => {}
                }
            }
        }
    }

    if def.is_computed() {
        let unique: BTreeSet<&String> = def.inputs.iter().collect();
        if unique.len() != def.inputs.len() {
            p.push(Problem::DuplicateInput);
        }
        for input in &def.inputs {
            match all.get(input.as_str()) {
                None if unparsed.contains(input) => {}
                None => p.push(Problem::UnknownInput(input.clone())),
                Some(d) if d.is_computed() => p.push(Problem::ComputedInput(input.clone())),
                Some(_) => {}
            }
        }
        if let Some(compute) = &def.compute {
            if compute.bytes_required() > 0 {
                p.push(Problem::ComputeUsesBytes);
            }
            let refs = compute.references();
            let inputs: BTreeSet<String> = def.inputs.iter().cloned().collect();
            if refs != inputs {
                p.push(Problem::ComputeInputsMismatch {
                    inputs: def.inputs.clone(),
                    references: refs.into_iter().collect(),
                });
            }
        }
    }
    p
}

fn validate(
    defs: &[SignalDef],
    origins: &[Option<PathBuf>],
    unparsed: &HashSet<String>,
) -> Vec<Issue> {
    let mut issues = Vec::new();
    let mut by_id: HashMap<&str, &SignalDef> = HashMap::new();
    let mut first_at: HashMap<&str, usize> = HashMap::new();
    for (i, def) in defs.iter().enumerate() {
        if let Some(&first) = first_at.get(def.id.as_str()) {
            let first = origins
                .get(first)
                .and_then(|o| o.as_ref())
                .map_or_else(|| format!("entry {first}"), |p| p.display().to_string());
            issues.push(Issue {
                file: origins.get(i).cloned().flatten(),
                signal: Some(def.id.clone()),
                problem: Problem::DuplicateId { first },
            });
        } else {
            first_at.insert(&def.id, i);
            by_id.insert(&def.id, def);
        }
    }
    for (i, def) in defs.iter().enumerate() {
        for problem in check_def(def, &by_id, unparsed) {
            issues.push(Issue {
                file: origins.get(i).cloned().flatten(),
                signal: Some(def.id.clone()),
                problem,
            });
        }
    }
    issues
}

// ---------------------------------------------------------------------------
// Registry
// ---------------------------------------------------------------------------

/// A validated set of signal definitions, in load order (files sorted by
/// name, then document order).
#[derive(Debug, Clone)]
pub struct Registry {
    defs: Vec<SignalDef>,
    index: HashMap<String, usize>,
}

impl Registry {
    /// Loads every `*.yaml` file directly inside `dir` (subdirectories such as
    /// `imports/` are not read). Each file is a YAML sequence of signals.
    pub fn load_dir(dir: impl AsRef<Path>) -> Result<Registry, RegistryError> {
        let dir = dir.as_ref();
        let io = |path: &Path| {
            let path = path.to_path_buf();
            move |source| RegistryError::Io { path, source }
        };
        let mut files = Vec::new();
        for entry in std::fs::read_dir(dir).map_err(io(dir))? {
            let path = entry.map_err(io(dir))?.path();
            if path.is_file() && path.extension().is_some_and(|e| e == "yaml") {
                files.push(path);
            }
        }
        files.sort();
        let mut sources = Vec::with_capacity(files.len());
        for path in files {
            let text = std::fs::read_to_string(&path).map_err(io(&path))?;
            sources.push((path, text));
        }
        Self::from_sources(sources.iter().map(|(p, t)| (p.as_path(), t.as_str())))
    }

    /// Loads one YAML document; `name` is used in messages.
    pub fn from_yaml_str(name: &str, yaml: &str) -> Result<Registry, RegistryError> {
        Self::from_sources([(Path::new(name), yaml)])
    }

    fn from_sources<'a>(
        sources: impl IntoIterator<Item = (&'a Path, &'a str)>,
    ) -> Result<Registry, RegistryError> {
        let mut defs = Vec::new();
        let mut origins = Vec::new();
        let mut issues = Vec::new();
        let mut unparsed = HashSet::new();
        for (path, text) in sources {
            let raws: Vec<RawSignal> =
                yaml_serde::from_str(text).map_err(|source| RegistryError::Yaml {
                    path: path.to_path_buf(),
                    source,
                })?;
            for raw in raws {
                let id = raw.id.clone();
                match from_raw(raw) {
                    Ok(def) => {
                        defs.push(def);
                        origins.push(Some(path.to_path_buf()));
                    }
                    Err(problems) => {
                        issues.extend(problems.into_iter().map(|problem| Issue {
                            file: Some(path.to_path_buf()),
                            signal: Some(id.clone()),
                            problem,
                        }));
                        unparsed.insert(id);
                    }
                }
            }
        }
        issues.extend(validate(&defs, &origins, &unparsed));
        if !issues.is_empty() {
            return Err(RegistryError::Invalid(issues));
        }
        Ok(Self::indexed(defs))
    }

    /// Validates definitions built in code (or edited copies of loaded ones).
    pub fn from_defs(defs: Vec<SignalDef>) -> Result<Registry, RegistryError> {
        let issues = validate(&defs, &[], &HashSet::new());
        if !issues.is_empty() {
            return Err(RegistryError::Invalid(issues));
        }
        Ok(Self::indexed(defs))
    }

    fn indexed(defs: Vec<SignalDef>) -> Registry {
        let index = defs
            .iter()
            .enumerate()
            .map(|(i, d)| (d.id.clone(), i))
            .collect();
        Registry { defs, index }
    }

    pub fn get(&self, id: &str) -> Option<&SignalDef> {
        self.index.get(id).and_then(|&i| self.defs.get(i))
    }

    pub fn contains(&self, id: &str) -> bool {
        self.index.contains_key(id)
    }

    pub fn iter(&self) -> impl Iterator<Item = &SignalDef> {
        self.defs.iter()
    }

    pub fn ids(&self) -> impl Iterator<Item = &str> {
        self.defs.iter().map(|d| d.id.as_str())
    }

    pub fn len(&self) -> usize {
        self.defs.len()
    }

    pub fn is_empty(&self) -> bool {
        self.defs.is_empty()
    }

    /// The definitions, for building a modified copy with [`Registry::from_defs`].
    pub fn into_defs(self) -> Vec<SignalDef> {
        self.defs
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const BARO: &str = r#"
- id: baro
  name: Barometric pressure
  short_name: Baro
  quantity: pressure
  unit: kPa
  source: diagnostic
  request: {protocol: iso15765, tx_id: "0x7DF", payload: "01 33"}
  response: {expect: "41 33", length: 1}
  decode: {formula: "A", unit: kPa}
  range: {min: 50, max: 110}
  poll: {priority: 5, interval_ms: 5000, timeout_ms: 500}
  stale_after_ms: 20000
  provenance: SAE
  enabled: true
"#;

    const MAP: &str = r#"
- id: map
  name: Manifold absolute pressure
  short_name: MAP
  quantity: pressure
  unit: kPa
  source: diagnostic
  request: {protocol: iso15765, tx_id: "0x7DF", payload: "22 14 40"}
  response: {expect: "62 14 40", length: 2}
  decode: {formula: "(((A*256)+B)*0.03625)", unit: psi}
  range: {min: 0, max: 400}
  poll: {priority: 0, interval_ms: 100, timeout_ms: 500}
  provenance: IMPORTED_UNVERIFIED
  enabled: false
"#;

    const BOOST: &str = r#"
- id: boost
  name: Boost
  short_name: Boost
  quantity: pressure
  unit: kPa
  source: computed
  inputs: [map, baro]
  compute: map - baro
  max_input_skew_ms: 20000
  range: {min: -20, max: 300}
  provenance: COMPUTED
  enabled: true
"#;

    fn base() -> String {
        format!("{BARO}{MAP}{BOOST}")
    }

    fn load(yaml: &str) -> Result<Registry, RegistryError> {
        Registry::from_yaml_str("test.yaml", yaml)
    }

    fn problems(yaml: &str) -> Vec<Problem> {
        match load(yaml) {
            Ok(_) => panic!("loaded:\n{yaml}"),
            Err(RegistryError::Invalid(issues)) => issues.into_iter().map(|i| i.problem).collect(),
            Err(e) => panic!("not a validation error: {e}"),
        }
    }

    fn yaml_error(yaml: &str) -> String {
        match load(yaml) {
            Err(RegistryError::Yaml { source, .. }) => source.to_string(),
            Err(e) => panic!("not a YAML error: {e}"),
            Ok(_) => panic!("loaded:\n{yaml}"),
        }
    }

    #[test]
    fn baseline_loads() {
        let r = load(&base()).expect("baseline");
        assert_eq!(r.ids().collect::<Vec<_>>(), ["baro", "map", "boost"]);
        let map = r.get("map").expect("map");
        // Default stale_after is 3 × the poll interval.
        assert_eq!(map.stale_after, Some(Duration::from_millis(300)));
        let req = map.request.as_ref().expect("request");
        assert_eq!(req.tx_id, 0x7DF);
        assert_eq!(req.payload, [0x22, 0x14, 0x40]);
        assert_eq!(
            r.get("boost").map(|b| b.input_skew_limit()),
            Some(Duration::from_secs(20))
        );
    }

    #[test]
    fn decode_strips_the_echo_and_converts_to_canonical() {
        let r = load(&base()).expect("baseline");
        let map = r.get("map").expect("map");
        // 0x0190 = 400 × 0.03625 = 14.5 psi ≈ 99.97 kPa.
        let v = map
            .decode_response(&[0x62, 0x14, 0x40, 0x01, 0x90], &|_| None)
            .expect("decodes");
        assert!((v - 14.5 * 6.894_757_293_168).abs() < 1e-9);
        assert_eq!(
            map.decode_response(&[0x62, 0x14, 0x40, 0x01], &|_| None),
            Err(DecodeError::TooShort {
                required: 2,
                got: 1
            })
        );
        assert!(matches!(
            map.decode_response(&[0x7F, 0x22, 0x31], &|_| None),
            Err(DecodeError::EchoMismatch { .. })
        ));
    }

    #[test]
    fn unknown_fields_are_errors() {
        let e =
            yaml_error(&base().replace("  short_name: MAP", "  short_name: MAP\n  colour: red"));
        assert!(e.contains("unknown field `colour`"), "{e}");
        let e = yaml_error(&base().replace("length: 2}", "length: 2, bytes: 3}"));
        assert!(e.contains("unknown field `bytes`"), "{e}");
    }

    #[test]
    fn ids_are_unique() {
        let yaml = format!("{}{BARO}", base());
        let p = problems(&yaml);
        assert!(
            p.iter().any(|p| matches!(p, Problem::DuplicateId { .. })),
            "{p:?}"
        );
    }

    #[test]
    fn ids_are_snake_case_and_not_reserved() {
        let p = problems(&base().replace("id: boost", "id: Boost"));
        assert!(p.contains(&Problem::BadId), "{p:?}");
        let p = problems(&base().replace("id: boost", "id: min"));
        assert!(p.contains(&Problem::BadId), "{p:?}");
    }

    #[test]
    fn verified_on_truck_requires_evidence() {
        let yaml = base().replace(
            "provenance: IMPORTED_UNVERIFIED",
            "provenance: VERIFIED_ON_TRUCK",
        );
        assert_eq!(problems(&yaml), [Problem::MissingEvidence]);
        let with = yaml.replace(
            "provenance: VERIFIED_ON_TRUCK",
            "provenance: VERIFIED_ON_TRUCK\n  evidence: docs/diagnostics/VERIFICATION_LOG.md",
        );
        assert!(load(&with).is_ok());
        let blank = yaml.replace(
            "provenance: VERIFIED_ON_TRUCK",
            "provenance: VERIFIED_ON_TRUCK\n  evidence: \"  \"",
        );
        assert_eq!(problems(&blank), [Problem::MissingEvidence]);
    }

    #[test]
    fn enabled_unverified_requires_allow_unverified() {
        let yaml = base().replace(
            "provenance: IMPORTED_UNVERIFIED\n  enabled: false",
            "provenance: IMPORTED_UNVERIFIED\n  enabled: true",
        );
        assert_eq!(problems(&yaml), [Problem::UnverifiedEnabled]);
        let allowed = yaml.replace(
            "enabled: true\n\n- id: boost",
            "enabled: true\n  allow_unverified: true\n\n- id: boost",
        );
        let r = load(&allowed).expect("explicit opt-in loads");
        assert!(
            r.get("map")
                .is_some_and(|m| m.enabled && m.allow_unverified)
        );
    }

    #[test]
    fn service_must_be_on_the_read_only_allow_list() {
        for sid in 0u8..=0xFF {
            let payload = format!("{sid:02X} 14 40");
            let expect = format!("{:02X} 14 40", sid.wrapping_add(0x40));
            let yaml = base()
                .replace("payload: \"22 14 40\"", &format!("payload: \"{payload}\""))
                .replace("expect: \"62 14 40\"", &format!("expect: \"{expect}\""));
            let result = load(&yaml);
            if ALLOWED_SERVICES.contains(&sid) {
                assert!(result.is_ok(), "0x{sid:02X}: {:?}", result.err());
            } else {
                let issues = result
                    .err()
                    .map(|e| e.issues().to_vec())
                    .unwrap_or_default();
                assert!(
                    issues
                        .iter()
                        .any(|i| i.problem == Problem::ServiceNotAllowed(sid)),
                    "0x{sid:02X} not refused: {issues:?}"
                );
            }
        }
        // Write, clear-DTC, routine, security access and session control
        // are all refused.
        for sid in [0x04u8, 0x10, 0x11, 0x14, 0x27, 0x2E, 0x2F, 0x31, 0x34, 0x3B] {
            assert!(!service_allowed(sid), "0x{sid:02X}");
        }
    }

    #[test]
    fn expect_must_be_the_positive_response_echo() {
        let p = problems(&base().replace("expect: \"62 14 40\"", "expect: \"62 14 41\""));
        assert!(
            matches!(p.as_slice(), [Problem::EchoMismatch { .. }]),
            "{p:?}"
        );
        let p = problems(&base().replace("expect: \"62 14 40\"", "expect: \"22 14 40\""));
        assert!(
            matches!(p.as_slice(), [Problem::EchoMismatch { .. }]),
            "{p:?}"
        );
    }

    #[test]
    fn computed_inputs_exist_and_are_not_computed() {
        let p = problems(&base().replace(
            "inputs: [map, baro]\n  compute: map - baro",
            "inputs: [map, nope]\n  compute: map - nope",
        ));
        assert!(p.contains(&Problem::UnknownInput("nope".into())), "{p:?}");

        let chained = format!(
            "{}{}",
            base(),
            BOOST
                .replace("id: boost", "id: boost2")
                .replace("inputs: [map, baro]", "inputs: [boost, baro]")
                .replace("compute: map - baro", "compute: boost - baro")
        );
        let p = problems(&chained);
        assert!(p.contains(&Problem::ComputedInput("boost".into())), "{p:?}");
    }

    #[test]
    fn compute_must_reference_exactly_its_inputs() {
        let p = problems(&base().replace("compute: map - baro", "compute: map * 2"));
        assert!(
            p.iter()
                .any(|p| matches!(p, Problem::ComputeInputsMismatch { .. })),
            "{p:?}"
        );
        let p = problems(&base().replace("compute: map - baro", "compute: map - baro + A"));
        assert!(p.contains(&Problem::ComputeUsesBytes), "{p:?}");
        let p = problems(&base().replace("inputs: [map, baro]", "inputs: [map, baro, map]"));
        assert!(p.contains(&Problem::DuplicateInput), "{p:?}");
    }

    #[test]
    fn formulas_must_parse() {
        let p = problems(&base().replace(
            "formula: \"(((A*256)+B)*0.03625)\"",
            "formula: \"((A*256)+B\"",
        ));
        match p.as_slice() {
            [Problem::Formula { field, error }] => {
                assert_eq!(*field, "decode.formula");
                assert_eq!(error.position, 10);
            }
            other => panic!("{other:?}"),
        }
        let p = problems(&base().replace("compute: map - baro", "compute: map - eval(baro)"));
        assert!(
            matches!(
                p.as_slice(),
                [Problem::Formula {
                    field: "compute",
                    ..
                }]
            ),
            "{p:?}"
        );
    }

    #[test]
    fn response_length_covers_the_formula() {
        let p = problems(&base().replace("length: 2}", "length: 1}"));
        assert_eq!(
            p,
            [Problem::ResponseTooShort {
                length: 1,
                required: 2
            }]
        );
        // Longer than needed is fine.
        assert!(load(&base().replace("length: 2}", "length: 4}")).is_ok());
    }

    #[test]
    fn decode_references_must_exist() {
        let yaml = base().replace(
            "formula: \"(((A*256)+B)*0.03625)\"",
            "formula: \"(((A*256)+B)*0.03625) - nothing\"",
        );
        assert_eq!(
            problems(&yaml),
            [Problem::UnknownReference("nothing".into())]
        );
        let yaml = base().replace(
            "formula: \"(((A*256)+B)*0.03625)\"",
            "formula: \"(((A*256)+B)*0.03625) - boost\"",
        );
        assert_eq!(
            problems(&yaml),
            [Problem::ComputedReference("boost".into())]
        );
        let ok = base().replace(
            "formula: \"(((A*256)+B)*0.03625)\"",
            "formula: \"(((A*256)+B)*0.03625) - baro\"",
        );
        assert!(load(&ok).is_ok());
    }

    #[test]
    fn calibration_bounds() {
        let with = |scale: &str| {
            base().replace(
                "  stale_after_ms: 20000",
                &format!("  stale_after_ms: 20000\n  calibration: {{scale: {scale}, note: test}}"),
            )
        };
        let r = load(&with("1.05")).expect("in bounds");
        assert_eq!(
            r.get("baro")
                .and_then(|b| b.calibration.as_ref())
                .map(Calibration::scale),
            Some(1.05)
        );
        let p = problems(&with("10.5"));
        assert!(
            matches!(
                p.as_slice(),
                [Problem::Calibration(CalibrationError::ScaleOutOfBounds(_))]
            ),
            "{p:?}"
        );
        let p = problems(&with("0.4"));
        assert_eq!(p.len(), 1);
        // Computed signals follow their inputs; calibrate those instead.
        let p = problems(&base().replace(
            "  max_input_skew_ms: 20000",
            "  max_input_skew_ms: 20000\n  calibration: {scale: 1.1}",
        ));
        assert_eq!(p, [Problem::UnexpectedField("calibration")]);
    }

    #[test]
    fn hex_ids_and_bytes_must_parse() {
        for bad in ["7DF", "0x", "0xZZZ", "0x7DF0000000", "0x20000000"] {
            let p = problems(&base().replace(
                "tx_id: \"0x7DF\", payload: \"22",
                &format!("tx_id: \"{bad}\", payload: \"22"),
            ));
            assert!(
                matches!(
                    p.as_slice(),
                    [Problem::BadHex {
                        field: "request.tx_id",
                        ..
                    }]
                ),
                "{bad}: {p:?}"
            );
        }
        let p = problems(&base().replace(
            "tx_id: \"0x7DF\", payload: \"22",
            "tx_id: \"0x7DF\", rx_id: \"0x7EZ\", payload: \"22",
        ));
        assert!(
            matches!(
                p.as_slice(),
                [Problem::BadHex {
                    field: "request.rx_id",
                    ..
                }]
            ),
            "{p:?}"
        );
        let ok = base().replace(
            "tx_id: \"0x7DF\", payload: \"22",
            "tx_id: \"0x7DF\", rx_id: \"0x7E9\", payload: \"22",
        );
        let r = load(&ok).expect("rx_id parses");
        assert_eq!(
            r.get("map")
                .and_then(|m| m.request.as_ref())
                .and_then(|r| r.rx_id),
            Some(0x7E9)
        );
        let p = problems(&base().replace("payload: \"22 14 40\"", "payload: \"221440\""));
        assert!(
            matches!(
                p.as_slice(),
                [Problem::BadHex {
                    field: "request.payload",
                    ..
                }]
            ),
            "{p:?}"
        );
        let p = problems(&base().replace("expect: \"62 14 40\"", "expect: \"62 14 4G\""));
        assert!(
            matches!(
                p.as_slice(),
                [Problem::BadHex {
                    field: "response.expect",
                    ..
                }]
            ),
            "{p:?}"
        );
        let p = problems(&base().replace("payload: \"22 14 40\"", "payload: \"\""));
        assert!(p.contains(&Problem::EmptyPayload), "{p:?}");
    }

    #[test]
    fn units_and_ranges() {
        let p = problems(&base().replace(
            "unit: kPa\n  source: computed",
            "unit: psi\n  source: computed",
        ));
        assert!(
            matches!(p.as_slice(), [Problem::NotCanonicalUnit { .. }]),
            "{p:?}"
        );
        let p = problems(&base().replace(
            "formula: \"(((A*256)+B)*0.03625)\", unit: psi",
            "formula: \"(((A*256)+B)*0.03625)\", unit: degF",
        ));
        assert!(matches!(p.as_slice(), [Problem::DecodeUnit(_)]), "{p:?}");
        let p =
            problems(&base().replace("range: {min: -20, max: 300}", "range: {min: 300, max: -20}"));
        assert_eq!(p, [Problem::BadRange]);
        let e = yaml_error(&base().replace("unit: psi}", "unit: furlongs}"));
        assert!(e.contains("furlongs"), "{e}");
    }

    #[test]
    fn source_shape_and_provenance() {
        let p = problems(&base().replace("provenance: COMPUTED", "provenance: SAE"));
        assert!(
            matches!(p.as_slice(), [Problem::SourceProvenanceMismatch { .. }]),
            "{p:?}"
        );
        let p = problems(&base().replace(
            "  poll: {priority: 0, interval_ms: 100, timeout_ms: 500}\n",
            "",
        ));
        assert!(p.contains(&Problem::MissingField("poll")), "{p:?}");
        let p = problems(&base().replace(
            "  max_input_skew_ms: 20000",
            "  max_input_skew_ms: 20000\n  poll: {priority: 0, interval_ms: 100, timeout_ms: 500}",
        ));
        assert!(p.contains(&Problem::UnexpectedField("poll")), "{p:?}");
        let p = problems(&base().replace(
            "  stale_after_ms: 20000",
            "  stale_after_ms: 20000\n  max_input_skew_ms: 5",
        ));
        assert_eq!(p, [Problem::UnexpectedField("max_input_skew_ms")]);
        let p = problems(&base().replace(
            "{priority: 0, interval_ms: 100,",
            "{priority: 0, interval_ms: 0,",
        ));
        assert!(p.contains(&Problem::BadPoll), "{p:?}");
        let p = problems(&base().replace(
            "formula: \"(((A*256)+B)*0.03625)\", unit: psi",
            "formula: \"(((A*256)+B)*0.03625)\", unit: psi, signed: true",
        ));
        assert_eq!(p, [Problem::SignedNotSupported]);
    }

    #[test]
    fn all_problems_are_reported_together() {
        let yaml = base()
            .replace("id: boost", "id: Boost")
            .replace("payload: \"22 14 40\"", "payload: \"2E 14 40\"")
            .replace("expect: \"62 14 40\"", "expect: \"6E 14 40\"");
        let p = problems(&yaml);
        assert!(p.contains(&Problem::BadId));
        assert!(p.contains(&Problem::ServiceNotAllowed(0x2E)));
        let msg = load(&yaml).err().map(|e| e.to_string()).unwrap_or_default();
        assert!(msg.contains("test.yaml: map: service 0x2E"), "{msg}");
    }

    #[test]
    fn from_defs_revalidates_edits() {
        let mut defs = load(&base()).expect("baseline").into_defs();
        for d in &mut defs {
            if d.id == "map" {
                d.enabled = true;
            }
        }
        let e = Registry::from_defs(defs.clone()).expect_err("unverified enabled");
        assert_eq!(e.issues().len(), 1);
        for d in &mut defs {
            d.allow_unverified = true;
        }
        assert!(Registry::from_defs(defs).is_ok());
    }

    #[test]
    fn format_bytes_is_uppercase_spaced_hex() {
        assert_eq!(format_bytes(&[0x22, 0x09, 0xD0]), "22 09 D0");
        assert_eq!(format_bytes(&[]), "");
    }
}
