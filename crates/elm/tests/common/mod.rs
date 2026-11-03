//! Scripted adapter for client tests: port of
//! `firmware/esp32/test/mocks/MockTransport.h` plus the fixtures from
//! `test_elm_client/test_main.cpp`.
//!
//! A script is a list of steps `{expect, response, delay}`. Each complete
//! `\r`-terminated line the client writes must match the current step's
//! `expect`; the step's response bytes become readable `delay` ms of virtual
//! time later. A mismatch or unexpected write is recorded for the test to
//! assert on. Everything here is `[SIM]`.

#![allow(dead_code, clippy::unwrap_used, clippy::expect_used)]

use f250_elm::{
    Addressing, ElmClient, ElmConfig, ElmEvent, ElmState, ObdCommand, ObdRequest, ObdResponse,
    RawComplete, Request, RequestId, SubmitError, VoltageResponse,
};

#[derive(Debug, Clone)]
pub struct Step {
    pub expect: String,
    pub response: String,
    pub delay: u64,
}

pub fn step(expect: &str, response: &str, delay: u64) -> Step {
    Step {
        expect: expect.to_owned(),
        response: response.to_owned(),
        delay,
    }
}

/// The C++ test init list (`kInit`): note ATSP0, not the shipped ATSP6.
pub const TEST_INIT: [&str; 6] = ["ATE0", "ATL0", "ATS0", "ATH1", "ATAT1", "ATSP0"];

pub fn test_config() -> ElmConfig {
    ElmConfig {
        init_commands: TEST_INIT.iter().map(|&s| s.to_owned()).collect(),
        ..ElmConfig::default()
    }
}

/// The standard boot script: ATZ + full init, everything happy.
pub fn boot_steps() -> Vec<Step> {
    vec![
        step("ATZ", "\r\rELM327 v1.4b\r\r>", 50),
        step("ATE0", "ATE0\rOK\r\r>", 5), // echo still on for this one command
        step("ATL0", "OK\r\r>", 5),
        step("ATS0", "OK\r\r>", 5),
        step("ATH1", "OK\r\r>", 5),
        step("ATAT1", "OK\r\r>", 5),
        step("ATSP0", "OK\r\r>", 5),
    ]
}

// ---- request fixtures: rows of the C++ kPidTable that the C++ tests use ----

/// RpmSae: 01 0C, functional, 500 ms.
pub fn rpm() -> ObdRequest {
    ObdRequest::new(ObdCommand::mode01(0x0C))
}

/// Eot: 22 1310, functional.
pub fn eot() -> ObdRequest {
    ObdRequest::new(ObdCommand::did(0x1310))
}

/// Eot as shipped: 22 1310, functional, pinned to the PCM at 7E8
/// (VERIFICATION_LOG.md 2026-11-03).
pub fn eot_pinned() -> ObdRequest {
    ObdRequest::new(ObdCommand::did(0x1310)).with_expected_responder(0x7E8)
}

/// Icp: 22 1446, functional.
pub fn icp() -> ObdRequest {
    ObdRequest::new(ObdCommand::did(0x1446))
}

/// TransTemp1 as shipped: 22 1674, functional, pinned to 7E9
/// (VERIFICATION_LOG.md 2026-08-09).
pub fn trans_temp1() -> ObdRequest {
    ObdRequest::new(ObdCommand::did(0x1674)).with_expected_responder(0x7E9)
}

/// TransTemp1 with the pin removed (C++ `variantOf(TransTemp1, 0, Auto)`).
pub fn trans_temp_unpinned() -> ObdRequest {
    ObdRequest::new(ObdCommand::did(0x1674))
}

/// TransTemp2: 22 1674 on ObdModule::Tcm, whose header is unverified.
pub fn trans_temp2() -> ObdRequest {
    ObdRequest::new(ObdCommand::did(0x1674)).with_addressing(Addressing::unverified())
}

/// ObdModule::Hdr726: the literal header "726" from the Torque export.
pub fn hdr726() -> Addressing {
    Addressing::header("726", None)
}

pub struct Harness {
    pub elm: ElmClient,
    pub now: u64,
    steps: Vec<Step>,
    index: usize,
    rx: Vec<u8>,
    tx_line: String,
    pending: Option<(u64, String)>,
    injections: Vec<(u64, String)>,
    pub mismatch: String,
    pub events: Vec<ElmEvent>,
    pub written: Vec<String>,
    pub connected: bool,
}

impl Harness {
    pub fn new(cfg: ElmConfig) -> Self {
        Self {
            elm: ElmClient::new(cfg).expect("valid config"),
            now: 0,
            steps: Vec::new(),
            index: 0,
            rx: Vec::new(),
            tx_line: String::new(),
            pending: None,
            injections: Vec::new(),
            mismatch: String::new(),
            events: Vec::new(),
            written: Vec::new(),
            connected: true,
        }
    }

    pub fn with_default() -> Self {
        Self::new(test_config())
    }

    pub fn set_script(&mut self, steps: Vec<Step>) {
        self.steps = steps;
        self.index = 0;
        self.rx.clear();
        self.tx_line.clear();
        self.pending = None;
        self.injections.clear();
        self.mismatch.clear();
    }

    /// Queue bytes to appear after `in_ms`, independently of the script
    /// (stragglers, unsolicited chatter).
    pub fn inject_later(&mut self, data: &str, in_ms: u64) {
        self.injections.push((self.now + in_ms, data.to_owned()));
    }

    pub fn script_done(&self) -> bool {
        self.index >= self.steps.len() && self.pending.is_none()
    }

    fn release_due(&mut self) {
        if let Some((due, _)) = &self.pending
            && self.now >= *due
        {
            let (_, data) = self.pending.take().unwrap();
            self.rx.extend_from_slice(data.as_bytes());
        }
        let now = self.now;
        let mut i = 0;
        while i < self.injections.len() {
            if now >= self.injections[i].0 {
                let (_, data) = self.injections.remove(i);
                self.rx.extend_from_slice(data.as_bytes());
            } else {
                i += 1;
            }
        }
    }

    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            if b != b'\r' {
                self.tx_line.push(char::from(b));
                continue;
            }
            let line = std::mem::take(&mut self.tx_line);
            self.written.push(line.clone());
            if self.index >= self.steps.len() {
                self.mismatch = format!("unexpected write past end of script: '{line}'");
            } else if line != self.steps[self.index].expect {
                self.mismatch =
                    format!("expected '{}' got '{line}'", self.steps[self.index].expect);
            } else {
                let s = &self.steps[self.index];
                self.pending = Some((self.now + s.delay, s.response.clone()));
                self.index += 1;
                self.release_due(); // delay 0: release immediately
            }
        }
    }

    fn flush(&mut self) {
        while let Some(b) = self.elm.poll_transmit() {
            self.write(&b);
        }
        while let Some(ev) = self.elm.poll_event() {
            self.events.push(ev);
        }
    }

    /// Advance virtual time 1 ms at a time: deliver due bytes, tick, write.
    pub fn pump(&mut self, ms: u64) {
        for _ in 0..ms {
            self.now += 1;
            self.release_due();
            if self.connected && !self.rx.is_empty() {
                let rx = std::mem::take(&mut self.rx);
                self.elm.receive(&rx, self.now);
            }
            self.flush();
            self.elm.tick(self.now);
            self.flush();
        }
    }

    pub fn begin(&mut self) {
        self.elm.begin(self.now);
        self.flush();
    }

    pub fn submit(&mut self, req: impl Into<Request>) -> Result<RequestId, SubmitError> {
        let r = self.elm.submit(req.into(), self.now);
        self.flush();
        r
    }

    pub fn raw(&mut self, line: &str) -> Result<RequestId, SubmitError> {
        self.submit(Request::Raw(line.to_owned()))
    }

    /// Boot script + `extra`, run ATZ + init, assert Idle (C++ `boot()`).
    pub fn boot(&mut self, extra: Vec<Step>) {
        let mut steps = boot_steps();
        steps.extend(extra);
        self.set_script(steps);
        self.begin();
        self.pump(200);
        assert_eq!(self.mismatch, "");
        assert_eq!(self.elm.state(), ElmState::Idle);
    }

    pub fn obd_responses(&self) -> Vec<&ObdResponse> {
        self.events
            .iter()
            .filter_map(|e| match e {
                ElmEvent::ObdResponse(r) => Some(&**r),
                _ => None,
            })
            .collect()
    }

    pub fn last_obd(&self) -> &ObdResponse {
        self.obd_responses().last().expect("an OBD response")
    }

    pub fn obd_count(&self) -> usize {
        self.obd_responses().len()
    }

    pub fn last_voltage(&self) -> &VoltageResponse {
        self.events
            .iter()
            .rev()
            .find_map(|e| match e {
                ElmEvent::Voltage(v) => Some(v),
                _ => None,
            })
            .expect("a voltage response")
    }

    pub fn last_raw_complete(&self) -> &RawComplete {
        self.events
            .iter()
            .rev()
            .find_map(|e| match e {
                ElmEvent::RawComplete(r) => Some(r),
                _ => None,
            })
            .expect("a raw completion")
    }

    pub fn raw_lines(&self, id: RequestId) -> Vec<&str> {
        self.events
            .iter()
            .filter_map(|e| match e {
                ElmEvent::RawLine { id: i, line } if *i == id => Some(line.as_str()),
                _ => None,
            })
            .collect()
    }

    pub fn alerts(&self) -> Vec<&str> {
        self.events
            .iter()
            .filter_map(|e| match e {
                ElmEvent::AdapterAlert { line } => Some(line.as_str()),
                _ => None,
            })
            .collect()
    }

    pub fn clear_events(&mut self) {
        self.events.clear();
    }
}
