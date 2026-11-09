//! Single-frame ISO 15765-2 request/response over raw CAN frames, for the
//! direct-CAN transport (ADR-0012). Pure logic: no sockets, no clock. The
//! driver in [`super::can`] feeds it frames and elapsed times.
//!
//! Scope, deliberately small:
//! - Requests are single frames (every registry request is ≤ 7 bytes).
//! - Responses are single frames. A first frame (multi-frame response, e.g.
//!   `09 02` VIN) is recorded and reported as Invalid; flow control is never
//!   sent. TODO: flow control, if a multi-frame read is ever needed.
//! - Only the OBD request IDs are transmitted: `7DF` functional and
//!   `7E0`–`7E7` physical. Only `7E8`–`7EF` answers are considered.
//! - Every request passes the ADR-0007 service allow-list here, before it can
//!   reach a socket.

use std::collections::BTreeSet;
use std::time::Duration;

use f250_elm::parser::hex_to_bytes;
use f250_elm::request::{ObdCommand, ObdRequest, ServiceAllowList};

use super::{Outcome, ResponderPayload};

/// ISO 15765-4 functional request ID.
pub const FUNCTIONAL_ID: u16 = 0x7DF;
/// Physical request IDs `7E0`–`7E7` (ECU n answers on `id + 8`).
pub const PHYSICAL_IDS: std::ops::RangeInclusive<u16> = 0x7E0..=0x7E7;
/// Diagnostic response IDs `7E8`–`7EF`.
pub const RESPONSE_IDS: std::ops::RangeInclusive<u16> = 0x7E8..=0x7EF;
/// Pad byte for unused request bytes. ISO 15765-4 frames are always 8 bytes;
/// the pad value is a choice, not a requirement we verified. 0x00 is what
/// the bench sees from candump-style tools. UNVERIFIED against what the MX+
/// sends (a listen-only capture beside the MX+ would show it).
pub const PAD: u8 = 0x00;
/// NRC 0x78: requestCorrectlyReceived-ResponsePending. The module will
/// answer later; keep waiting until the request timeout.
pub const NRC_RESPONSE_PENDING: u8 = 0x78;

/// One classic CAN data frame with an 11-bit ID.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Frame {
    pub id: u16,
    pub data: Vec<u8>,
}

impl Frame {
    /// `7E8 03 41 0C 0A` style, for the traffic log and the console.
    pub fn display(&self) -> String {
        let mut s = format!("{:03X}", self.id);
        for b in &self.data {
            s.push_str(&format!(" {b:02X}"));
        }
        s
    }
}

/// True if a CAN ID may be used to transmit a diagnostic request.
pub fn is_request_id(id: u16) -> bool {
    id == FUNCTIONAL_ID || PHYSICAL_IDS.contains(&id)
}

/// The physical request ID of the module that answers on `responder`: ECU n
/// is addressed on `7E0 + n` and answers on `7E8 + n` (ISO 15765-4 11-bit
/// OBD IDs). On this truck `7E0`→`7E8` (PCM) and `7E1`→`7E9` (TCM) are
/// verified [TRUCK] (VERIFICATION_LOG 2026-11-08); the others are not.
pub fn physical_request_id(responder: u16) -> Option<u16> {
    RESPONSE_IDS.contains(&responder).then(|| responder - 8)
}

/// Parse a request ID from an `ATSH`-style header string ("7DF", "7E1").
fn parse_request_id(header: &str) -> Result<u16, String> {
    let id = u16::from_str_radix(header.trim(), 16)
        .map_err(|_| format!("request header '{header}' is not hex"))?;
    if !is_request_id(id) {
        return Err(format!(
            "request header {id:03X} is not an OBD request ID (7DF, 7E0–7E7)"
        ));
    }
    Ok(id)
}

/// Build a single-frame request: `[len, bytes…, pad…]`, 8 bytes.
fn single_frame(id: u16, bytes: &[u8]) -> Result<Frame, String> {
    if bytes.is_empty() || bytes.len() > 7 {
        return Err(format!(
            "{} request bytes do not fit one ISO-TP single frame (1–7)",
            bytes.len()
        ));
    }
    let mut data = Vec::with_capacity(8);
    data.push(bytes.len() as u8);
    data.extend_from_slice(bytes);
    data.resize(8, PAD);
    Ok(Frame { id, data })
}

/// The request frame for one registry request, after the ADR-0007 check.
pub fn request_frame(req: &ObdRequest, allow: &ServiceAllowList) -> Result<Frame, String> {
    let service = req.command.service();
    if !allow.contains(service) {
        return Err(format!(
            "service 0x{service:02X} is not on the read-only allow-list (ADR-0007)"
        ));
    }
    let header = req
        .addressing
        .tx_header
        .as_deref()
        .ok_or("request header unverified; refused")?;
    let id = parse_request_id(header)?;
    let bytes = hex_to_bytes(&req.command.request_hex(), 7)
        .ok_or_else(|| format!("bad request bytes {}", req.command.request_hex()))?;
    single_frame(id, &bytes)
}

/// A console `raw` line: `[ID] HEX`, e.g. `010C`, `7E1 221674`, `7E0:221310`.
/// The ID defaults to `7DF`. ELM `AT` commands mean nothing here.
pub fn raw_frame(line: &str, allow: &ServiceAllowList) -> Result<Frame, String> {
    let line = line.trim();
    if line.len() >= 2 && line[..2].eq_ignore_ascii_case("AT") {
        return Err(
            "this is the direct-CAN transport, not an ELM adapter: AT commands don't apply. \
             Use '[ID] HEX', e.g. '7E1 221674' or '010C' (7DF)"
                .into(),
        );
    }
    let (id, hex) = match line.split_once([' ', ':']) {
        Some((id, rest)) => (parse_request_id(id)?, rest.trim()),
        None => (FUNCTIONAL_ID, line),
    };
    let hex: String = hex.chars().filter(|c| !c.is_whitespace()).collect();
    let bytes = hex_to_bytes(&hex, 7).ok_or_else(|| format!("'{hex}' is not 1–7 hex bytes"))?;
    let service = bytes[0];
    if !allow.contains(service) {
        return Err(format!(
            "service 0x{service:02X} is not on the read-only allow-list (ADR-0007)"
        ));
    }
    single_frame(id, &bytes)
}

/// ISO-TP protocol control information of a received frame.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Pci<'a> {
    Single(&'a [u8]),
    First,
    Other,
    Malformed,
}

pub fn pci(data: &[u8]) -> Pci<'_> {
    let Some(&b0) = data.first() else {
        return Pci::Malformed;
    };
    match b0 >> 4 {
        0 => {
            let len = usize::from(b0 & 0x0F);
            if len == 0 || len > 7 || data.len() < 1 + len {
                Pci::Malformed
            } else {
                Pci::Single(&data[1..1 + len])
            }
        }
        1 => Pci::First,
        2 | 3 => Pci::Other,
        _ => Pci::Malformed,
    }
}

/// Collects the answers to one request until it is complete.
///
/// - **Pinned** (`expected_responder`): other modules' frames are dropped
///   before parsing, exactly like the ELM client. Done as soon as the owner
///   gives a final answer, or when the window passes without one; but with
///   [`Exchange::wait_for`], not before the listed other modules have
///   answered too (or the window has passed). On the functional ID every
///   module hears the request, and a refusal names only the service, not
///   the DID: a refusal still on its way when the next request goes out is
///   read as that request's answer (2026-11-07 drive: the PCM's `7F 22 31`
///   to trans temp, ~30 ms late, taken as the PCM refusing EOT), and the
///   module may skip a request that reaches it while it is still answering.
/// - **Unpinned**: every module that answers within `window` is recorded;
///   done when the window ends. This is what removes the 2026-11-03 dropout:
///   the window is ours, not the adapter's adaptive timing.
/// - NRC 0x78 (response pending) from a module extends the wait to `timeout`.
#[derive(Debug, Clone)]
pub struct Exchange {
    command: Option<ObdCommand>,
    expected: Option<u16>,
    window: Duration,
    timeout: Duration,
    positives: Vec<(u16, Vec<u8>)>,
    negatives: Vec<(u16, u8)>,
    pending: BTreeSet<u16>,
    owner_final: bool,
    /// Other modules a pinned exchange still waits to hear from.
    others: BTreeSet<u16>,
    multi_frame: Option<u16>,
    /// Frames from responders other than the pinned one (dropped).
    pub ignored: u32,
    /// Single frames that were neither a matching positive nor a negative.
    pub unmatched: u32,
    pub malformed: u32,
}

impl Exchange {
    pub fn new(req: &ObdRequest, window: Duration) -> Self {
        Self::build(
            Some(req.command),
            req.expected_responder,
            window,
            req.timeout_ms,
        )
    }

    /// A console `raw` exchange: no command to match, no pin.
    pub fn raw(window: Duration, timeout_ms: u64) -> Self {
        Self::build(None, None, window, timeout_ms)
    }

    fn build(
        command: Option<ObdCommand>,
        expected: Option<u16>,
        window: Duration,
        timeout_ms: u64,
    ) -> Self {
        let timeout = Duration::from_millis(timeout_ms);
        Exchange {
            command,
            expected,
            window: window.min(timeout),
            timeout,
            positives: Vec::new(),
            negatives: Vec::new(),
            pending: BTreeSet::new(),
            owner_final: false,
            others: BTreeSet::new(),
            multi_frame: None,
            ignored: 0,
            unmatched: 0,
            malformed: 0,
        }
    }

    /// A pinned exchange also waits (up to the window) for these modules'
    /// final answers, so none of them is still answering when the next
    /// request goes out. The owner is never in the set. No effect unpinned.
    pub fn wait_for(mut self, modules: impl IntoIterator<Item = u16>) -> Self {
        if let Some(owner) = self.expected {
            self.others = modules
                .into_iter()
                .filter(|&id| id != owner && RESPONSE_IDS.contains(&id))
                .collect();
        }
        self
    }

    /// Feed one received frame.
    pub fn on_frame(&mut self, frame: &Frame) {
        if !RESPONSE_IDS.contains(&frame.id) {
            return;
        }
        if self.expected.is_some_and(|e| e != frame.id) {
            self.ignored += 1;
            if self.others.contains(&frame.id) && self.is_final_answer(&frame.data) {
                self.others.remove(&frame.id);
            }
            return;
        }
        let payload = match pci(&frame.data) {
            Pci::Single(p) => p,
            Pci::First => {
                self.multi_frame.get_or_insert(frame.id);
                return;
            }
            Pci::Other => return,
            Pci::Malformed => {
                self.malformed += 1;
                return;
            }
        };
        let service = self.command.map(|c| c.service());
        if payload[0] == 0x7F {
            if payload.len() < 3 || service.is_some_and(|s| payload[1] != s) {
                self.unmatched += 1;
                return;
            }
            let nrc = payload[2];
            if nrc == NRC_RESPONSE_PENDING {
                self.pending.insert(frame.id);
                return;
            }
            self.pending.remove(&frame.id);
            self.negatives.push((frame.id, nrc));
            self.mark_final(frame.id);
            return;
        }
        let body = match self.command {
            Some(c) if c.matches_positive(payload) => payload[c.echo_len()..].to_vec(),
            Some(_) => {
                self.unmatched += 1;
                return;
            }
            None => payload.to_vec(),
        };
        self.pending.remove(&frame.id);
        self.positives.push((frame.id, body));
        self.mark_final(frame.id);
    }

    fn mark_final(&mut self, id: u16) {
        if self.expected == Some(id) {
            self.owner_final = true;
        }
    }

    /// A single frame that ends a module's part in this exchange: a positive
    /// answer to this command, or a refusal of this service other than
    /// "response pending".
    fn is_final_answer(&self, data: &[u8]) -> bool {
        let Pci::Single(payload) = pci(data) else {
            return false;
        };
        let Some(c) = self.command else {
            return true;
        };
        if payload[0] == 0x7F {
            payload.len() >= 3 && payload[1] == c.service() && payload[2] != NRC_RESPONSE_PENDING
        } else {
            c.matches_positive(payload)
        }
    }

    /// Whether the exchange is complete at `at` (time since the request).
    pub fn done(&self, at: Duration) -> bool {
        if at >= self.timeout {
            return true;
        }
        if self.owner_final {
            return self.others.is_empty() || at >= self.window;
        }
        at >= self.window && self.pending.is_empty()
    }

    /// When to look again if nothing arrives.
    pub fn next_check(&self, at: Duration) -> Duration {
        if at < self.window {
            self.window
        } else {
            self.timeout
        }
    }

    /// The transport-neutral result. `at` is the exchange's duration, which
    /// is what the request cost the link (comparable to the ELM's TX→prompt).
    pub fn finish(&self, at: Duration) -> Outcome {
        let latency_ms = at.as_millis().min(u128::from(u32::MAX)) as u32;
        if !self.positives.is_empty() {
            return Outcome::Payload {
                responders: self
                    .positives
                    .iter()
                    .map(|(id, p)| ResponderPayload {
                        can_id: format!("{id:03X}"),
                        payload: p.clone(),
                    })
                    .collect(),
                latency_ms,
            };
        }
        if let Some(&(_, nrc)) = self.negatives.first() {
            return Outcome::Negative { nrc, latency_ms };
        }
        if let Some(id) = self.multi_frame {
            return Outcome::Invalid {
                detail: format!(
                    "{id:03X} sent a multi-frame response; ISO-TP flow control is not implemented"
                ),
                latency_ms,
            };
        }
        Outcome::NoResponse { latency_ms }
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;
    use f250_elm::request::Addressing;

    fn ms(n: u64) -> Duration {
        Duration::from_millis(n)
    }
    fn f(id: u16, hex: &str) -> Frame {
        Frame {
            id,
            data: hex_to_bytes(hex, 8).unwrap(),
        }
    }
    fn allow() -> ServiceAllowList {
        ServiceAllowList::read_only_default()
    }
    fn eot() -> ObdRequest {
        ObdRequest::new(ObdCommand::did(0x1310))
    }
    const W: Duration = Duration::from_millis(50);

    #[test]
    fn builds_padded_single_frames() {
        let fr = request_frame(&eot(), &allow()).unwrap();
        assert_eq!(fr, f(0x7DF, "0322131000000000"));
        let rpm = ObdRequest::new(ObdCommand::mode01(0x0C))
            .with_addressing(Addressing::header("7E0", None));
        assert_eq!(
            request_frame(&rpm, &allow()).unwrap(),
            f(0x7E0, "02010C0000000000")
        );
    }

    #[test]
    fn refuses_what_adr_0007_forbids() {
        // Clear DTCs (0x04) can't even be put on a list; a default list
        // without 0x22 refuses a DID read.
        let only01 = ServiceAllowList::new([0x01]).unwrap();
        assert!(request_frame(&eot(), &only01).is_err());
        assert!(raw_frame("04", &allow()).is_err());
        assert!(raw_frame("7E0 2E131000", &allow()).is_err());
        assert!(raw_frame("7E0 3101", &allow()).is_err());
        let unverified = eot().with_addressing(Addressing::unverified());
        assert!(request_frame(&unverified, &allow()).is_err());
        // Only OBD request IDs may transmit.
        let odd = eot().with_addressing(Addressing::header("726", None));
        assert!(request_frame(&odd, &allow()).is_err());
        assert!(raw_frame("7E8 010C", &allow()).is_err());
        assert!(raw_frame("ATSH7E1", &allow()).is_err());
        assert!(raw_frame("0102030405060708", &allow()).is_err(), "8 bytes");
    }

    #[test]
    fn raw_lines() {
        assert_eq!(
            raw_frame("010C", &allow()).unwrap(),
            f(0x7DF, "02010C0000000000")
        );
        assert_eq!(
            raw_frame("7E1 22 16 74", &allow()).unwrap(),
            f(0x7E1, "0322167400000000")
        );
        assert_eq!(
            raw_frame("7e0:221310", &allow()).unwrap(),
            f(0x7E0, "0322131000000000")
        );
    }

    /// 2026-11-03, the usual EOT window: the TCM refuses, the PCM answers.
    #[test]
    fn physical_request_id_is_the_responder_less_8() {
        assert_eq!(physical_request_id(0x7E8), Some(0x7E0));
        assert_eq!(physical_request_id(0x7E9), Some(0x7E1));
        assert_eq!(physical_request_id(0x7EF), Some(0x7E7));
        assert_eq!(physical_request_id(0x7E7), None);
        assert_eq!(physical_request_id(0x7F0), None);
    }

    #[test]
    fn unpinned_waits_the_window_and_keeps_the_positive() {
        let mut ex = Exchange::new(&eot(), W);
        ex.on_frame(&f(0x7E9, "037F221200000000"));
        assert!(
            !ex.done(ms(20)),
            "the window is ours, not the first answer's"
        );
        ex.on_frame(&f(0x7E8, "0562131026910000"));
        assert!(!ex.done(ms(25)));
        assert!(ex.done(W));
        match ex.finish(W) {
            Outcome::Payload { responders, .. } => {
                assert_eq!(responders.len(), 1);
                assert_eq!(responders[0].can_id, "7E8");
                assert_eq!(responders[0].payload, [0x26, 0x91]);
            }
            o => panic!("{o:?}"),
        }
    }

    #[test]
    fn unpinned_with_only_a_refusal_is_negative() {
        let mut ex = Exchange::new(&eot(), W);
        ex.on_frame(&f(0x7E9, "037F221200000000"));
        assert_eq!(
            ex.finish(W),
            Outcome::Negative {
                nrc: 0x12,
                latency_ms: 50
            }
        );
    }

    #[test]
    fn pinned_returns_on_the_owner_and_drops_the_rest() {
        let mut ex = Exchange::new(&eot().with_expected_responder(0x7E8), W);
        ex.on_frame(&f(0x7E9, "037F221200000000"));
        assert_eq!(ex.ignored, 1);
        assert!(!ex.done(ms(15)));
        ex.on_frame(&f(0x7E8, "0562131026910000"));
        assert!(ex.done(ms(18)), "no need to wait out the window");
        assert!(matches!(
            ex.finish(ms(18)),
            Outcome::Payload { latency_ms: 18, .. }
        ));
    }

    fn trans_temp() -> ObdRequest {
        ObdRequest::new(ObdCommand::did(0x1674)).with_expected_responder(0x7E9)
    }

    /// 2026-11-07 drive: the TCM answers trans temp in ~7 ms, the PCM's
    /// refusal follows ~30 ms after the request. Waiting for it keeps it out
    /// of the next request's exchange.
    #[test]
    fn pinned_waits_for_the_other_modules_refusal() {
        let mut ex = Exchange::new(&trans_temp(), W).wait_for([0x7E8, 0x7E9]);
        ex.on_frame(&f(0x7E9, "0562167404130000"));
        assert!(!ex.done(ms(7)), "the PCM hasn't answered yet");
        assert_eq!(ex.next_check(ms(7)), W);
        ex.on_frame(&f(0x7E8, "037F227800000000"));
        assert!(!ex.done(ms(20)), "response pending isn't an answer");
        ex.on_frame(&f(0x7E8, "037F223100000000"));
        assert!(ex.done(ms(30)), "everyone has answered");
        match ex.finish(ms(30)) {
            Outcome::Payload { responders, .. } => {
                assert_eq!(responders.len(), 1);
                assert_eq!(responders[0].can_id, "7E9");
            }
            o => panic!("{o:?}"),
        }
    }

    #[test]
    fn pinned_wait_for_others_ends_at_the_window() {
        let mut ex = Exchange::new(&trans_temp(), W).wait_for([0x7E8]);
        ex.on_frame(&f(0x7E9, "0562167404130000"));
        // An answer to some other request doesn't count as the PCM's.
        ex.on_frame(&f(0x7E8, "04410C0AC2000000"));
        ex.on_frame(&f(0x7E8, "037F010000000000"));
        assert!(!ex.done(ms(49)));
        assert!(ex.done(W), "a silent module costs one window, no more");
        assert!(matches!(ex.finish(W), Outcome::Payload { .. }));
    }

    #[test]
    fn wait_for_only_applies_to_pinned_exchanges() {
        let mut unpinned = Exchange::new(&eot(), W).wait_for([0x7E8, 0x7E9]);
        unpinned.on_frame(&f(0x7E8, "0562131026910000"));
        assert!(!unpinned.done(ms(40)), "unpinned still waits its window");
        assert!(unpinned.done(W));
        let mut pinned = Exchange::new(&eot().with_expected_responder(0x7E8), W).wait_for([0x7E8]);
        pinned.on_frame(&f(0x7E8, "0562131026910000"));
        assert!(pinned.done(ms(40)), "the owner is never waited for twice");
    }

    #[test]
    fn pinned_owner_silent_is_no_response_not_unsupported() {
        let mut ex = Exchange::new(&eot().with_expected_responder(0x7E8), W);
        ex.on_frame(&f(0x7E9, "037F221200000000"));
        assert!(ex.done(W));
        assert_eq!(ex.finish(W), Outcome::NoResponse { latency_ms: 50 });
    }

    #[test]
    fn two_responders_both_recorded_in_arrival_order() {
        let rpm = ObdRequest::new(ObdCommand::mode01(0x0C));
        let mut ex = Exchange::new(&rpm, W);
        ex.on_frame(&f(0x7E9, "04410C0AC4000000"));
        ex.on_frame(&f(0x7E8, "04410C0AC2000000"));
        match ex.finish(W) {
            Outcome::Payload { responders, .. } => {
                let ids: Vec<_> = responders.iter().map(|r| r.can_id.as_str()).collect();
                assert_eq!(ids, ["7E9", "7E8"]);
                assert_eq!(responders[1].payload, [0x0A, 0xC2]);
            }
            o => panic!("{o:?}"),
        }
    }

    #[test]
    fn response_pending_extends_to_the_timeout() {
        let mut ex = Exchange::new(&eot().with_expected_responder(0x7E8), W);
        ex.on_frame(&f(0x7E8, "037F227800000000"));
        assert!(
            !ex.done(ms(100)),
            "0x78 keeps the exchange open past the window"
        );
        assert_eq!(ex.next_check(ms(100)), ms(500));
        ex.on_frame(&f(0x7E8, "0562131026910000"));
        assert!(ex.done(ms(120)));
        let mut silent = Exchange::new(&eot(), W);
        silent.on_frame(&f(0x7E8, "037F227800000000"));
        assert!(!silent.done(ms(499)));
        assert!(silent.done(ms(500)));
        assert!(matches!(silent.finish(ms(500)), Outcome::NoResponse { .. }));
    }

    #[test]
    fn ignores_foreign_and_malformed_frames() {
        let mut ex = Exchange::new(&eot(), W);
        ex.on_frame(&f(0x4B0, "0562131026910000")); // not a diagnostic response ID
        ex.on_frame(&f(0x7E8, "0962131026910000")); // SF length 9
        ex.on_frame(&f(0x7E8, "04410C0AC2000000")); // answer to another request
        ex.on_frame(&f(0x7E8, "037F010000000000")); // NRC for another service
        assert_eq!(ex.malformed, 1);
        assert_eq!(ex.unmatched, 2);
        assert_eq!(ex.finish(W), Outcome::NoResponse { latency_ms: 50 });
    }

    #[test]
    fn multi_frame_is_reported_not_followed() {
        let vin = ObdRequest::new(ObdCommand::Pid {
            service: 0x09,
            pid: 0x02,
        });
        let mut ex = Exchange::new(&vin, W);
        ex.on_frame(&f(0x7E8, "1014490201314654"));
        assert!(matches!(ex.finish(W), Outcome::Invalid { .. }));
    }

    #[test]
    fn raw_exchange_keeps_every_single_frame() {
        let mut ex = Exchange::raw(W, 500);
        ex.on_frame(&f(0x7E9, "037F221200000000"));
        ex.on_frame(&f(0x7E8, "0562131026910000"));
        match ex.finish(W) {
            Outcome::Payload { responders, .. } => {
                assert_eq!(responders[0].payload, [0x62, 0x13, 0x10, 0x26, 0x91]);
            }
            o => panic!("{o:?}"),
        }
    }
}
