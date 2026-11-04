//! Transports: how a request for one signal reaches the vehicle (or a
//! simulation of it) and what came back. The gateway's scheduler, recovery and
//! validity logic are identical for every transport (PROJECT_PLAN 3.6).
//!
//! Only one transport exists per gateway process, so two transports can
//! never transmit at the same time (ADR-0007, Phase 4.6).

pub mod can;
pub mod isotp;
pub mod obdlink;
pub mod simulated;
pub mod traffic;

/// One answering module.
#[derive(Debug, Clone, PartialEq)]
pub struct ResponderPayload {
    /// CAN ID, e.g. "7E9".
    pub can_id: String,
    /// Payload after the positive-response echo.
    pub payload: Vec<u8>,
}

/// What came back for one request.
#[derive(Debug, Clone, PartialEq)]
pub enum Outcome {
    /// Raw payload(s) to decode with the signal's registry formula. The first
    /// responder is the one to use (after `expected_responder` filtering in
    /// the ELM client).
    Payload {
        responders: Vec<ResponderPayload>,
        latency_ms: u32,
    },
    /// Already decoded, canonical units. Only the simulator produces this: it
    /// models the vehicle at the value level, not the byte level.
    Value {
        value: f64,
        latency_ms: u32,
    },
    NoResponse {
        latency_ms: u32,
    },
    Negative {
        nrc: u8,
        latency_ms: u32,
    },
    Invalid {
        detail: String,
        latency_ms: u32,
    },
    /// The link is down; nothing was sent.
    LinkDown,
    /// The request was not sent (e.g. outside the ADR-0007 allow-list).
    Refused {
        reason: String,
    },
}

impl Outcome {
    pub fn latency_ms(&self) -> Option<u32> {
        match self {
            Outcome::Payload { latency_ms, .. }
            | Outcome::Value { latency_ms, .. }
            | Outcome::NoResponse { latency_ms }
            | Outcome::Negative { latency_ms, .. }
            | Outcome::Invalid { latency_ms, .. } => Some(*latency_ms),
            Outcome::LinkDown | Outcome::Refused { .. } => None,
        }
    }
}
