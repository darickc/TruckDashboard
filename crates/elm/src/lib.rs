//! Sans-IO ELM327/STN (OBDLink MX+) client.
//!
//! A port of the tested ESP32 `ElmParser`/`ElmClient`
//! (`firmware/esp32/lib/ObdCore/src/`). The crate owns the adapter's
//! request/response lifecycle and does no I/O of its own: no threads, no
//! sockets, no clock. Time is passed in as a monotonic `u64` millisecond value.
//!
//! # What it does
//!
//! * `ATZ` reset, then a configurable init sequence (data, not code). An init
//!   command answered with `?` is retried once, then skipped.
//! * One request in flight at a time, completed by the `>` prompt.
//! * A long deadline for the first request after init (protocol
//!   `SEARCHING...`) and the per-request timeout afterwards.
//! * Recovery ladder: a timeout sends a bare CR to provoke a prompt;
//!   `max_consecutive_timeouts` timeouts, a failed recovery or a failed
//!   init/reset trigger a full `ATZ` re-init; after `max_reset_attempts`
//!   failed resets the client goes [`ElmState::Offline`] and the owner
//!   reconnects the transport and calls [`ElmClient::begin`].
//! * Echo filtering until `ATE0` takes effect, `ATH1` header parsing (11-bit
//!   IDs) and headerless lines, ISO-TP reassembly grouped by CAN ID,
//!   positive-response echo validation and stripping (`41 xx`, `62 xx xx`),
//!   `7F <svc> <NRC>` negative responses.
//! * Every responder recorded in arrival order with its CAN ID, and an honest
//!   count beyond the stored maximum. `expected_responder` filtering happens
//!   before ISO-TP reassembly; a silent owner yields
//!   [`ElmResult::NoResponder`].
//! * `ATSH`/`ATCRA` header caching: sent only when the adapter's addressing
//!   differs; reset to `7DF` on every `ATZ`; marked unknown after any raw
//!   command (the fix recorded in docs/diagnostics/VERIFICATION_LOG.md).
//! * Unsolicited STN chatter (`LV RESET`, `ACT ALERT`, `SLEEPING`, `WAKE`...)
//!   is surfaced as [`ElmEvent::AdapterAlert`], never as a response.
//!
//! New in this port:
//!
//! 1. **Service allow-list (ADR-0007).** Every OBD request, including raw hex
//!    lines, must have its service byte on [`ServiceAllowList`] (default
//!    `01 03 07 09 22`) or [`ElmClient::submit`] refuses it and writes nothing.
//!    Write/control/clear services ([`NEVER_ALLOWED_SERVICES`]) cannot be
//!    added. Raw `AT` commands are allowed, except `ATCAF0` and `ATPP...`,
//!    which would let a hex line bypass the guard or change the adapter
//!    persistently; STN `ST...` commands are refused (`STPX` sends arbitrary
//!    frames).
//! 2. **`ATRV`** ([`Request::ReadVoltage`]): the adapter's input voltage,
//!    parsed (`12.4V` → `12.4`) into [`VoltageResponse::volts`].
//! 3. **Latency** on every completion: submit → prompt (`latency_ms`), and
//!    for OBD requests also request-line → prompt (`wire_latency_ms`, the C++
//!    figure, which excludes `ATSH` prep).
//!
//! # Driving loop
//!
//! The caller owns the transport and the clock:
//!
//! ```text
//! elm.begin(now)                                   // after the link comes up
//! loop {
//!     wait until bytes arrive or elm.next_deadline() passes
//!     elm.receive(&bytes_read, now)                // 1. feed input
//!     elm.tick(now)                                // 2. check deadlines
//!     while let Some(b) = elm.poll_transmit() {    // 3. write output
//!         transport.write_all(&b)
//!     }
//!     while let Some(ev) = elm.poll_event() {      // 4. handle events
//!         // ObdResponse / Voltage / RawComplete: results
//!         // StateChanged { to: Offline, .. }: reconnect, then elm.begin(now)
//!     }
//!     if elm.state() == ElmState::Idle { elm.submit(next_request, now) }
//! }
//! ```
//!
//! If the transport drops, call [`ElmClient::transport_lost`].
//!
//! A complete exchange, with the adapter's bytes typed in by hand:
//!
//! ```
//! use f250_elm::{ElmClient, ElmConfig, ElmEvent, ElmResult, ObdCommand, ObdRequest};
//!
//! # fn main() -> Result<(), Box<dyn std::error::Error>> {
//! let config = ElmConfig { init_commands: vec!["ATE0".into()], ..ElmConfig::default() };
//! let mut elm = ElmClient::new(config)?;
//!
//! elm.begin(0);
//! assert_eq!(elm.poll_transmit().as_deref(), Some(&b"ATZ\r"[..]));
//! elm.receive(b"\r\rELM327 v1.4b\r\r>", 50);
//! assert_eq!(elm.poll_transmit().as_deref(), Some(&b"ATE0\r"[..]));
//! elm.receive(b"ATE0\rOK\r\r>", 60); // the echo is filtered
//! assert!(elm.is_ready());
//!
//! let id = elm.submit(ObdRequest::new(ObdCommand::mode01(0x0C)).into(), 100)?;
//! assert_eq!(elm.poll_transmit().as_deref(), Some(&b"010C\r"[..]));
//! elm.receive(b"7E904410C0AC4\r7E804410C0AC2\r\r>", 196);
//! elm.tick(196);
//!
//! let rsp = std::iter::from_fn(|| elm.poll_event())
//!     .find_map(|ev| match ev {
//!         ElmEvent::ObdResponse(r) => Some(r),
//!         _ => None,
//!     })
//!     .ok_or("no response")?;
//! assert_eq!(rsp.id, id);
//! assert_eq!(rsp.result, ElmResult::Ok);
//! assert_eq!(rsp.payload, [0x0A, 0xC4]); // echo 41 0C stripped; 7E9 answered first
//! assert_eq!(rsp.responder_id, Some(0x7E9));
//! assert_eq!(rsp.responder_count, 2);
//! assert!(rsp.responders_differ); // a fact about bytes, not a verdict
//! assert_eq!(rsp.latency_ms, 96);
//! # Ok(())
//! # }
//! ```
//!
//! # Not here
//!
//! The PID table, formulas and scheduling belong to the telemetry layer and
//! the vehicle gateway. 29-bit CAN headers are not parsed (this truck's
//! diagnostic responses are 11-bit). Nothing in this crate has been run
//! against the truck; its tests are `[SIM]`, built from captures in
//! docs/diagnostics/VERIFICATION_LOG.md.

#![warn(missing_docs)]

mod client;
pub mod parser;
pub mod request;

pub use client::{
    AdapterErrorKind, ConfigError, DEFAULT_INIT_COMMANDS, ElmClient, ElmConfig, ElmEvent,
    ElmResult, ElmState, ErrorCause, NegativeResponse, ObdResponse, READ_VOLTAGE_COMMAND,
    RawComplete, RecoveryStep, Request, RequestId, ResetReason, ResponderAnswer, SubmitError,
    VoltageResponse,
};
pub use request::{
    Addressing, AllowListError, DEFAULT_ALLOWED_SERVICES, NEVER_ALLOWED_SERVICES, ObdCommand,
    ObdRequest, RawLineError, RawLineKind, ServiceAllowList,
};
