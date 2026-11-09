//! What can be asked of the adapter, and the read-only guard in front of it.
//!
//! Port of the parts of `PidDefs.{h,cpp}` that `ElmClient` depends on (request
//! building, echo length, `ATSH` header handling, `expectedResponder`,
//! `expectedResponses`), plus the ADR-0007 service allow-list.
//!
//! The PID *table* (names, formulas, poll intervals) is deliberately not here:
//! it belongs to the telemetry layer. This crate only needs to know how to
//! address a request and how to recognise its answer.

use std::fmt;

use crate::parser::is_hex_string;

/// ISO 15765-4 functional request ID. Every ECU answers it; it is also the
/// ELM327 default header on CAN (restored by `ATZ`).
pub const FUNCTIONAL_HEADER: &str = "7DF";

/// SAE J1979 / ISO 14229 ReadDataByIdentifier (Ford enhanced reads).
pub const SERVICE_READ_DATA_BY_ID: u8 = 0x22;

/// Per-request timeout used by every row of the ESP32 PID table.
pub const DEFAULT_REQUEST_TIMEOUT_MS: u64 = 500;

/// Longest command line the client will write (the C++ `sendLine` buffer held
/// 30 characters plus `\r` and the terminator).
pub const MAX_COMMAND_LEN: usize = 30;

/// Longest `ATSH`/`ATCRA` argument accepted (a 29-bit header is 8 hex digits).
pub const MAX_HEADER_LEN: usize = 8;

/// True for the ISO 15765-4 functional broadcast header, which every ECU
/// answers. Response-count digits are unsafe on it (see
/// [`ObdRequest::expected_responses`]).
pub fn is_functional_header(header: &str) -> bool {
    header.eq_ignore_ascii_case(FUNCTIONAL_HEADER)
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

/// The OBD bytes of one request.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ObdCommand {
    /// A service with a one-byte PID that the positive response echoes
    /// (`01 0C` → `41 0C ...`, `09 02` → `49 02 ...`). Echo length 2.
    Pid {
        /// Service byte (must not be 0x22; use [`ObdCommand::Did`]).
        service: u8,
        /// Parameter ID.
        pid: u8,
    },
    /// Service 0x22 ReadDataByIdentifier with a two-byte DID
    /// (`22 1674` → `62 16 74 ...`). Echo length 3.
    Did {
        /// Data identifier.
        did: u16,
    },
    /// A service with no parameter (`03`, `07`). Only the response service
    /// byte is echoed. Echo length 1.
    Service {
        /// Service byte.
        service: u8,
    },
}

impl ObdCommand {
    /// SAE Mode 01 PID (`01 xx`).
    pub const fn mode01(pid: u8) -> Self {
        Self::Pid { service: 0x01, pid }
    }

    /// Read-by-DID (`22 xxxx`).
    pub const fn did(did: u16) -> Self {
        Self::Did { did }
    }

    /// The request's service byte (what the allow-list checks).
    pub const fn service(&self) -> u8 {
        match *self {
            Self::Pid { service, .. } | Self::Service { service } => service,
            Self::Did { .. } => SERVICE_READ_DATA_BY_ID,
        }
    }

    /// Bytes of positive-response echo to validate and strip before the
    /// payload: 2 for `41 xx`, 3 for `62 xx xx`, 1 for a bare service.
    pub const fn echo_len(&self) -> usize {
        match self {
            Self::Pid { .. } => 2,
            Self::Did { .. } => 3,
            Self::Service { .. } => 1,
        }
    }

    /// The request as the hex the adapter is sent (`010C`, `221674`, `03`).
    pub fn request_hex(&self) -> String {
        match *self {
            Self::Pid { service, pid } => format!("{service:02X}{pid:02X}"),
            Self::Did { did } => format!("{SERVICE_READ_DATA_BY_ID:02X}{did:04X}"),
            Self::Service { service } => format!("{service:02X}"),
        }
    }

    /// True if `payload` is a positive response to this command (service
    /// byte + 0x40 and the PID/DID echo), with at least one byte after it.
    pub fn matches_positive(&self, payload: &[u8]) -> bool {
        let echo = self.echo_len();
        if payload.len() <= echo || payload[0] != self.service().wrapping_add(0x40) {
            return false;
        }
        match *self {
            Self::Pid { pid, .. } => payload[1] == pid,
            Self::Did { did } => {
                let [hi, lo] = did.to_be_bytes();
                payload[1] == hi && payload[2] == lo
            }
            Self::Service { .. } => true,
        }
    }
}

impl fmt::Display for ObdCommand {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.request_hex())
    }
}

// ---------------------------------------------------------------------------
// Addressing
// ---------------------------------------------------------------------------

/// A request's header and (optionally) its receive filter.
///
/// `tx_header` is the `ATSH` argument, or `None` when the real header is
/// unverified: the client refuses such requests rather than guessing (C++
/// `ObdAddressing::txHeader == nullptr`). `rx_filter` is the `ATCRA`
/// argument, or `None` for "no filter" (a bare `ATCRA` clears it).
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Addressing {
    /// `ATSH` argument; `None` = unverified, request refused.
    pub tx_header: Option<String>,
    /// `ATCRA` argument; `None` = no receive filter.
    pub rx_filter: Option<String>,
}

impl Addressing {
    /// Functional broadcast (`7DF`), no filter. SAE-standard, not guessed.
    pub fn functional() -> Self {
        Self {
            tx_header: Some(FUNCTIONAL_HEADER.to_owned()),
            rx_filter: None,
        }
    }

    /// A module whose header has not been verified on the truck. Requests
    /// with this addressing are refused.
    pub const fn unverified() -> Self {
        Self {
            tx_header: None,
            rx_filter: None,
        }
    }

    /// An explicit header and optional receive filter.
    pub fn header(tx_header: impl Into<String>, rx_filter: Option<String>) -> Self {
        Self {
            tx_header: Some(tx_header.into()),
            rx_filter,
        }
    }
}

impl Default for Addressing {
    fn default() -> Self {
        Self::functional()
    }
}

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------

/// One OBD request: what to ask, how to address it, whose answer counts.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct ObdRequest {
    /// The request bytes.
    pub command: ObdCommand,
    /// Header and receive filter.
    pub addressing: Addressing,
    /// Which ECU owns this request. `None` = accept whichever answers first
    /// (the honest default while ownership is unproven). `Some(0x7E9)` drops
    /// every other sender's frames *before* ISO-TP reassembly, and a silent
    /// owner yields [`crate::ElmResult::NoResponder`].
    pub expected_responder: Option<u16>,
    /// ELM response-count digit (1..=9) appended to the request (`010C` →
    /// `010C1`) so the adapter returns as soon as N replies arrive. Refused
    /// on the functional header: asking for fewer responses than the bus will
    /// produce leaves a straggler to land in the NEXT request (`STOPPED`).
    pub expected_responses: Option<u8>,
    /// Per-request timeout, used once the first request after init has
    /// completed (the first one gets `first_data_timeout_ms`).
    pub timeout_ms: u64,
}

impl ObdRequest {
    /// A functional (`7DF`) request with the default 500 ms timeout.
    pub fn new(command: ObdCommand) -> Self {
        Self {
            command,
            addressing: Addressing::functional(),
            expected_responder: None,
            expected_responses: None,
            timeout_ms: DEFAULT_REQUEST_TIMEOUT_MS,
        }
    }

    /// Replace the addressing.
    #[must_use]
    pub fn with_addressing(mut self, addressing: Addressing) -> Self {
        self.addressing = addressing;
        self
    }

    /// Pin the request to one responder CAN ID.
    #[must_use]
    pub fn with_expected_responder(mut self, can_id: u16) -> Self {
        self.expected_responder = Some(can_id);
        self
    }

    /// Append a response-count digit (physical headers only).
    #[must_use]
    pub fn with_expected_responses(mut self, count: u8) -> Self {
        self.expected_responses = Some(count);
        self
    }

    /// Replace the per-request timeout.
    #[must_use]
    pub fn with_timeout_ms(mut self, timeout_ms: u64) -> Self {
        self.timeout_ms = timeout_ms;
        self
    }
}

// ---------------------------------------------------------------------------
// Service allow-list (ADR-0007)
// ---------------------------------------------------------------------------

/// Read-only services allowed by default (ADR-0007,
/// docs/architecture/diagnostic-recovery.md): current data, stored DTCs,
/// pending DTCs, vehicle info, read-by-identifier.
pub const DEFAULT_ALLOWED_SERVICES: [u8; 5] = [0x01, 0x03, 0x07, 0x09, 0x22];

/// Services that can never be put on the allow-list, whatever the
/// configuration says. ADR-0007: write, control, flash, routine and DTC-clear
/// services are refused in code.
///
/// The list in docs/architecture/diagnostic-recovery.md (10, 11, 14, 04, 27,
/// 2E, 2F, 31, 34–37, 3B), plus the remaining standard control/write services:
/// 08 (J1979 control of on-board system: actuator control), 28
/// CommunicationControl, 2C DynamicallyDefineDataIdentifier, 3D
/// WriteMemoryByAddress, 85 ControlDTCSetting, 87 LinkControl (ISO 14229-1).
pub const NEVER_ALLOWED_SERVICES: [u8; 19] = [
    0x04, 0x08, 0x10, 0x11, 0x14, 0x27, 0x28, 0x2C, 0x2E, 0x2F, 0x31, 0x34, 0x35, 0x36, 0x37, 0x3B,
    0x3D, 0x85, 0x87,
];

/// The set of OBD service bytes the client will transmit.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct ServiceAllowList {
    bits: [u64; 4],
}

/// Why an allow-list could not be built.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AllowListError {
    /// The service is a write/control/clear service that ADR-0007 forbids.
    Forbidden(u8),
}

impl fmt::Display for AllowListError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Forbidden(s) => write!(
                f,
                "service 0x{s:02X} is a write/control service and can never be allowed (ADR-0007)"
            ),
        }
    }
}

impl std::error::Error for AllowListError {}

impl ServiceAllowList {
    /// Build an allow-list. Fails if any service is in
    /// [`NEVER_ALLOWED_SERVICES`].
    pub fn new(services: impl IntoIterator<Item = u8>) -> Result<Self, AllowListError> {
        let mut list = Self { bits: [0; 4] };
        for s in services {
            if NEVER_ALLOWED_SERVICES.contains(&s) {
                return Err(AllowListError::Forbidden(s));
            }
            list.bits[usize::from(s >> 6)] |= 1u64 << (s & 63);
        }
        Ok(list)
    }

    /// The default read-only list: [`DEFAULT_ALLOWED_SERVICES`].
    pub const fn read_only_default() -> Self {
        let mut bits = [0u64; 4];
        let mut i = 0;
        while i < DEFAULT_ALLOWED_SERVICES.len() {
            let s = DEFAULT_ALLOWED_SERVICES[i];
            bits[(s >> 6) as usize] |= 1u64 << (s & 63);
            i += 1;
        }
        Self { bits }
    }

    /// True if `service` may be transmitted.
    pub const fn contains(&self, service: u8) -> bool {
        self.bits[(service >> 6) as usize] & (1u64 << (service & 63)) != 0
    }

    /// The allowed services, ascending.
    pub fn services(&self) -> Vec<u8> {
        (0..=u8::MAX).filter(|&s| self.contains(s)).collect()
    }
}

impl Default for ServiceAllowList {
    fn default() -> Self {
        Self::read_only_default()
    }
}

// ---------------------------------------------------------------------------
// Raw command lines
// ---------------------------------------------------------------------------

/// What a raw console line is, once it has passed the guard.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RawLineKind {
    /// An ELM `AT` command (adapter-local).
    At,
    /// A hex OBD request; the adapter will put it on the bus.
    Obd {
        /// Its service byte (first two hex digits).
        service: u8,
    },
}

/// Why a raw line was refused.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RawLineError {
    /// Empty or whitespace only.
    Empty,
    /// Longer than [`MAX_COMMAND_LEN`].
    TooLong(usize),
    /// Contains a control or non-ASCII character. A `\r` would let one line
    /// smuggle a second, unchecked command past the allow-list.
    ControlCharacter,
    /// Neither an `AT` command nor hex. This includes STN `ST...` commands:
    /// `STPX` transmits arbitrary frames, so the whole family is refused.
    NotAtOrHex,
    /// A hex request whose service byte is not on the allow-list.
    ServiceNotAllowed(u8),
    /// An `AT` command that would defeat the allow-list or change the
    /// adapter persistently: `ATCAF0` (CAN auto-formatting off makes the first
    /// typed byte the ISO-TP PCI, so the guard would read the wrong byte as
    /// the service) and `ATPP...` (programmable parameters, written to the
    /// adapter's EEPROM; PP 24 sets the CAF default).
    AtCommandRefused(String),
}

impl fmt::Display for RawLineError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Empty => f.write_str("empty command"),
            Self::TooLong(n) => write!(f, "command is {n} characters (max {MAX_COMMAND_LEN})"),
            Self::ControlCharacter => f.write_str("command contains a control character"),
            Self::NotAtOrHex => f.write_str("command is neither an AT command nor hex"),
            Self::ServiceNotAllowed(s) => {
                write!(f, "service 0x{s:02X} is not on the allow-list (ADR-0007)")
            }
            Self::AtCommandRefused(c) => write!(f, "AT command '{c}' is refused (ADR-0007)"),
        }
    }
}

impl std::error::Error for RawLineError {}

/// Check a raw line against the guard and say what it is.
///
/// Spaces are ignored (the ELM ignores them too) and case does not matter.
pub fn check_raw_line(line: &str, allow: &ServiceAllowList) -> Result<RawLineKind, RawLineError> {
    if !line.bytes().all(|b| (0x20..=0x7E).contains(&b)) {
        return Err(RawLineError::ControlCharacter);
    }
    if line.len() > MAX_COMMAND_LEN {
        return Err(RawLineError::TooLong(line.len()));
    }
    let compact: String = line
        .chars()
        .filter(|&c| c != ' ')
        .map(|c| c.to_ascii_uppercase())
        .collect();
    if compact.is_empty() {
        return Err(RawLineError::Empty);
    }
    if let Some(rest) = compact.strip_prefix("AT") {
        if rest == "CAF0" || rest.starts_with("PP") {
            return Err(RawLineError::AtCommandRefused(compact));
        }
        return Ok(RawLineKind::At);
    }
    if compact.len() < 2 || !is_hex_string(&compact) {
        return Err(RawLineError::NotAtOrHex);
    }
    let service = u8::from_str_radix(compact.get(..2).unwrap_or_default(), 16)
        .map_err(|_| RawLineError::NotAtOrHex)?;
    if !allow.contains(service) {
        return Err(RawLineError::ServiceNotAllowed(service));
    }
    Ok(RawLineKind::Obd { service })
}

/// Validate and normalise (upper-case) an `ATSH`/`ATCRA` argument.
pub(crate) fn normalise_header(h: &str) -> Option<String> {
    if h.is_empty() || h.len() > MAX_HEADER_LEN || !is_hex_string(h) {
        return None;
    }
    Some(h.to_ascii_uppercase())
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::*;

    #[test]
    fn request_hex_and_echo() {
        assert_eq!(ObdCommand::mode01(0x0C).request_hex(), "010C");
        assert_eq!(ObdCommand::did(0x1674).request_hex(), "221674");
        assert_eq!(ObdCommand::did(0x09D0).request_hex(), "2209D0");
        assert_eq!(ObdCommand::Service { service: 0x03 }.request_hex(), "03");
        assert_eq!(
            ObdCommand::Pid {
                service: 0x09,
                pid: 0x02
            }
            .request_hex(),
            "0902"
        );
        assert_eq!(ObdCommand::mode01(0x0C).echo_len(), 2);
        assert_eq!(ObdCommand::did(0x1674).echo_len(), 3);
        assert_eq!(ObdCommand::did(0x1674).service(), 0x22);
    }

    #[test]
    fn positive_echo_matching() {
        let rpm = ObdCommand::mode01(0x0C);
        assert!(rpm.matches_positive(&[0x41, 0x0C, 0x1A, 0xF8]));
        assert!(!rpm.matches_positive(&[0x41, 0x0D, 0x1A]));
        assert!(!rpm.matches_positive(&[0x41, 0x0C])); // echo only, no body
        let tt = ObdCommand::did(0x1674);
        assert!(tt.matches_positive(&[0x62, 0x16, 0x74, 0x04, 0x13]));
        assert!(!tt.matches_positive(&[0x62, 0x16, 0x75, 0x04, 0x13]));
        assert!(!tt.matches_positive(&[0x7F, 0x22, 0x31]));
        let dtc = ObdCommand::Service { service: 0x03 };
        assert!(dtc.matches_positive(&[0x43, 0x00]));
        assert!(!dtc.matches_positive(&[0x47, 0x00]));
    }

    #[test]
    fn functional_header_detection() {
        assert!(is_functional_header("7DF"));
        assert!(is_functional_header("7df"));
        assert!(!is_functional_header("7E0"));
        assert!(!is_functional_header("726"));
    }

    #[test]
    fn default_allow_list_is_the_adr_0007_set() {
        let a = ServiceAllowList::default();
        assert_eq!(a.services(), DEFAULT_ALLOWED_SERVICES);
        for s in [0x04, 0x10, 0x14, 0x27, 0x2E, 0x2F, 0x31, 0x3B] {
            assert!(!a.contains(s), "0x{s:02X} must not be allowed");
        }
    }

    #[test]
    fn allow_list_refuses_forbidden_services() {
        assert_eq!(
            ServiceAllowList::new([0x01, 0x14]),
            Err(AllowListError::Forbidden(0x14))
        );
        assert_eq!(
            ServiceAllowList::new([0x2E]),
            Err(AllowListError::Forbidden(0x2E))
        );
        let custom = ServiceAllowList::new([0x01, 0x19]).unwrap();
        assert!(custom.contains(0x19));
        assert!(!custom.contains(0x22));
    }

    #[test]
    fn raw_line_guard() {
        let a = ServiceAllowList::default();
        assert_eq!(check_raw_line("ATZ", &a), Ok(RawLineKind::At));
        assert_eq!(check_raw_line("ATSH 7E1", &a), Ok(RawLineKind::At));
        assert_eq!(check_raw_line("atdpn", &a), Ok(RawLineKind::At));
        assert_eq!(check_raw_line("ATCAF1", &a), Ok(RawLineKind::At));
        assert_eq!(
            check_raw_line("221674", &a),
            Ok(RawLineKind::Obd { service: 0x22 })
        );
        assert_eq!(
            check_raw_line("2213101", &a),
            Ok(RawLineKind::Obd { service: 0x22 })
        );
        assert_eq!(
            check_raw_line("01 0C", &a),
            Ok(RawLineKind::Obd { service: 0x01 })
        );
        assert_eq!(
            check_raw_line("04", &a),
            Err(RawLineError::ServiceNotAllowed(0x04))
        );
        assert_eq!(
            check_raw_line("2e1234AA", &a),
            Err(RawLineError::ServiceNotAllowed(0x2E))
        );
        assert_eq!(
            check_raw_line("1003", &a),
            Err(RawLineError::ServiceNotAllowed(0x10))
        );
        assert_eq!(check_raw_line("", &a), Err(RawLineError::Empty));
        assert_eq!(check_raw_line("   ", &a), Err(RawLineError::Empty));
        assert_eq!(check_raw_line("0", &a), Err(RawLineError::NotAtOrHex));
        assert_eq!(
            check_raw_line("STPX H:7E0, D:1101", &a),
            Err(RawLineError::NotAtOrHex)
        );
        assert_eq!(check_raw_line("STDI", &a), Err(RawLineError::NotAtOrHex));
        assert_eq!(
            check_raw_line("ATI\r14FF00", &a),
            Err(RawLineError::ControlCharacter)
        );
        assert!(matches!(
            check_raw_line("AT CAF 0", &a),
            Err(RawLineError::AtCommandRefused(_))
        ));
        assert!(matches!(
            check_raw_line("ATPP 24 SV 00", &a),
            Err(RawLineError::AtCommandRefused(_))
        ));
        assert!(matches!(
            check_raw_line(&"0".repeat(31), &a),
            Err(RawLineError::TooLong(31))
        ));
    }

    #[test]
    fn header_normalisation() {
        assert_eq!(normalise_header("7e0").as_deref(), Some("7E0"));
        assert_eq!(normalise_header("C410F1").as_deref(), Some("C410F1"));
        assert_eq!(normalise_header(""), None);
        assert_eq!(normalise_header("7E 0"), None);
        assert_eq!(normalise_header("123456789"), None);
    }
}
