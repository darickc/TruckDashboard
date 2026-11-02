//! ATRV, adapter status lines, unsolicited chatter, echo filtering, latency
//! and other request-lifecycle behaviour. `[SIM]`.

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod common;

use common::*;
use f250_elm::{
    AdapterErrorKind, Addressing, ElmConfig, ElmEvent, ElmResult, ElmState, ErrorCause, ObdCommand,
    ObdRequest, Request,
};

fn stray_lines(h: &Harness) -> Vec<&str> {
    h.events
        .iter()
        .filter_map(|e| match e {
            ElmEvent::StrayLine { line, .. } => Some(line.as_str()),
            _ => None,
        })
        .collect()
}

// ---------------------------------------------------------------------------
// ATRV
// ---------------------------------------------------------------------------

#[test]
fn atrv_returns_parsed_voltage() {
    let mut h = Harness::with_default();
    h.boot(vec![step("ATRV", "12.4V\r\r>", 15)]);
    let id = h.submit(Request::ReadVoltage).unwrap();
    h.pump(50);
    let v = h.last_voltage();
    assert_eq!(v.id, id);
    assert_eq!(v.result, ElmResult::Ok);
    assert_eq!(v.volts, Some(12.4));
    assert_eq!(v.latency_ms, 15);
    assert_eq!(h.elm.state(), ElmState::Idle);
    assert_eq!(h.mismatch, "");
}

#[test]
fn atrv_echo_before_ate0_is_filtered() {
    let cfg = ElmConfig {
        init_commands: vec![],
        ..ElmConfig::default()
    };
    let mut h = Harness::new(cfg);
    h.set_script(vec![
        step("ATZ", "ATZ\r\rELM327 v1.4b\r\r>", 50),
        step("ATRV", "ATRV\r13.9V\r\r>", 10),
    ]);
    h.begin();
    h.pump(100);
    assert_eq!(h.elm.state(), ElmState::Idle);
    assert_eq!(h.elm.adapter_id(), Some("ELM327 v1.4b"));
    h.submit(Request::ReadVoltage).unwrap();
    h.pump(50);
    assert_eq!(h.last_voltage().volts, Some(13.9));
    assert!(stray_lines(&h).is_empty());
}

#[test]
fn atrv_errors() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("ATRV", "?\r\r>", 5),
        step("ATRV", "BANANA\r\r>", 5),
        step("ATRV", "", 0),
        step("", "\r>", 5),
    ]);
    h.submit(Request::ReadVoltage).unwrap();
    h.pump(50);
    assert_eq!(
        h.last_voltage().result,
        ElmResult::Error(ErrorCause::Adapter {
            kind: AdapterErrorKind::Rejected,
            line: "?".into()
        })
    );
    assert_eq!(h.last_voltage().volts, None);

    h.submit(Request::ReadVoltage).unwrap();
    h.pump(50);
    assert_eq!(
        h.last_voltage().result,
        ElmResult::Error(ErrorCause::EmptyResponse)
    );
    assert_eq!(stray_lines(&h), ["BANANA"]);

    h.submit(Request::ReadVoltage).unwrap();
    h.pump(2000); // init_timeout_ms
    assert_eq!(h.last_voltage().result, ElmResult::Timeout);
    h.pump(50);
    assert_eq!(h.elm.state(), ElmState::Idle);
    assert_eq!(h.mismatch, "");
}

#[test]
fn atrv_does_not_disturb_addressing() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("ATSH726", "OK\r\r>", 5),
        step("221674", "7E8056216740A2C\r\r>", 20),
        step("ATRV", "12.4V\r\r>", 5),
        step("221674", "7E8056216740A2C\r\r>", 20), // no ATSH needed
    ]);
    let on726 = trans_temp_unpinned().with_addressing(hdr726());
    h.submit(on726.clone()).unwrap();
    h.pump(12_000);
    h.submit(Request::ReadVoltage).unwrap();
    h.pump(50);
    h.submit(on726).unwrap();
    h.pump(200);
    assert_eq!(h.last_obd().result, ElmResult::Ok);
    assert_eq!(h.mismatch, "");
    assert!(h.script_done());
}

// ---------------------------------------------------------------------------
// Adapter status lines and chatter
// ---------------------------------------------------------------------------

#[test]
fn adapter_error_lines_end_in_error() {
    let cases = [
        ("CAN ERROR", AdapterErrorKind::CanError),
        ("BUFFER FULL", AdapterErrorKind::BufferFull),
        ("UNABLE TO CONNECT", AdapterErrorKind::UnableToConnect),
        ("?", AdapterErrorKind::Rejected),
        ("FB ERROR", AdapterErrorKind::Rejected),
    ];
    let mut h = Harness::with_default();
    h.boot(
        cases
            .iter()
            .map(|(line, _)| step("010C", &format!("{line}\r\r>"), 10))
            .collect(),
    );
    for (line, kind) in cases {
        h.submit(rpm()).unwrap();
        h.pump(12_000);
        assert_eq!(
            h.last_obd().result,
            ElmResult::Error(ErrorCause::Adapter {
                kind,
                line: line.into()
            })
        );
        assert_eq!(h.elm.state(), ElmState::Idle);
    }
    assert_eq!(h.mismatch, "");
}

#[test]
fn stn_chatter_mid_request_is_surfaced_not_parsed() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("010C", "LV RESET\r7E804410C1AF8\rACT ALERT\r\r>", 20),
        step("010C", "SLEEPING\r\r>", 20),
    ]);
    h.submit(rpm()).unwrap();
    h.pump(12_000);
    let r = h.last_obd();
    assert_eq!(r.result, ElmResult::Ok);
    assert_eq!(r.payload, [0x1A, 0xF8]);
    assert_eq!(r.responder_count, 1);
    assert_eq!(h.alerts(), ["LV RESET", "ACT ALERT"]);

    // Chatter alone is never a response.
    h.submit(rpm()).unwrap();
    h.pump(200);
    assert_eq!(
        h.last_obd().result,
        ElmResult::Error(ErrorCause::EmptyResponse)
    );
    assert_eq!(h.alerts(), ["LV RESET", "ACT ALERT", "SLEEPING"]);
    assert!(stray_lines(&h).is_empty());
}

#[test]
fn stn_chatter_while_idle_is_an_alert() {
    let mut h = Harness::with_default();
    h.boot(vec![]);
    h.inject_later("LP ALERT\r", 10);
    h.inject_later("WAKE\r", 20);
    h.pump(50);
    assert_eq!(h.alerts(), ["LP ALERT", "WAKE"]);
    assert!(stray_lines(&h).is_empty());
    assert_eq!(h.elm.state(), ElmState::Idle);
}

#[test]
fn chatter_during_raw_is_passed_through_and_alerted() {
    let mut h = Harness::with_default();
    h.boot(vec![step("ATI", "LV RESET\rELM327 v1.4b\r\r>", 10)]);
    let id = h.raw("ATI").unwrap();
    h.pump(50);
    assert_eq!(h.raw_lines(id), ["LV RESET", "ELM327 v1.4b"]);
    assert_eq!(h.alerts(), ["LV RESET"]);
}

#[test]
fn echo_is_filtered_during_a_request() {
    let mut h = Harness::with_default();
    h.boot(vec![step("010C", "010C\r7E804410C1AF8\r\r>", 20)]);
    h.submit(rpm()).unwrap();
    h.pump(12_000);
    assert_eq!(h.last_obd().result, ElmResult::Ok);
    assert!(stray_lines(&h).is_empty());
}

#[test]
fn searching_extends_the_deadline() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("010C", "7E804410C1AF8\r\r>", 20), // first request done
        step("010C", "SEARCHING...\r", 100),
    ]);
    h.submit(rpm()).unwrap();
    h.pump(100);
    h.submit(rpm()).unwrap();
    // Without SEARCHING the 500 ms per-request timeout would fire first.
    h.inject_later("7E804410C1AF8\r\r>", 3000);
    h.pump(3100);
    assert_eq!(h.last_obd().result, ElmResult::Ok);
    assert_eq!(h.last_obd().wire_latency_ms, Some(3000));
    assert_eq!(h.obd_count(), 2);
}

#[test]
fn first_request_gets_the_long_deadline() {
    let mut h = Harness::with_default();
    h.boot(vec![step("010C", "7E804410C1AF8\r\r>", 4000)]);
    h.submit(rpm()).unwrap();
    h.pump(4100);
    assert_eq!(h.last_obd().result, ElmResult::Ok);
}

// ---------------------------------------------------------------------------
// Frames
// ---------------------------------------------------------------------------

#[test]
fn headerless_and_spaced_lines() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("010C", "410C1AF8\r\r>", 20),           // ATH0 style
        step("010C", "7E8 04 41 0C 1A F8\r\r>", 20), // ATS0 not in effect
    ]);
    h.submit(rpm()).unwrap();
    h.pump(12_000);
    let r = h.last_obd();
    assert_eq!(r.result, ElmResult::Ok);
    assert_eq!(r.payload, [0x1A, 0xF8]);
    assert_eq!(r.responder_id, None);
    assert_eq!(r.responders[0].can_id, None);

    h.submit(rpm()).unwrap();
    h.pump(200);
    let r = h.last_obd();
    assert_eq!(r.result, ElmResult::Ok);
    assert_eq!(r.responder_id, Some(0x7E8));
}

#[test]
fn unpinned_multiframe_survives_another_ecus_single_frame() {
    // Grouped by CAN ID: 7E9's negative single frame between 7E8's first and
    // consecutive frames must not abandon 7E8's message.
    let mut h = Harness::with_default();
    h.boot(vec![step(
        "221674",
        "7E81009621674AABBCC\r7E9037F2231\r7E821DDEEFF\r\r>",
        20,
    )]);
    h.submit(trans_temp_unpinned()).unwrap();
    h.pump(12_000);
    let r = h.last_obd();
    assert_eq!(r.result, ElmResult::Ok);
    assert_eq!(r.payload, [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]);
    assert_eq!(r.negative_responses.len(), 1);
    assert_eq!(r.negative_responses[0].can_id, Some(0x7E9));
}

#[test]
fn straggler_is_not_mistaken_for_the_answer() {
    // A late 41 0C landing during a 01 0D request (the count-digit hazard).
    let mut h = Harness::with_default();
    h.boot(vec![
        step("010C", "7E804410C1AF8\r\r>", 20),
        step("010D", "7E804410C1AF8\r7E803410D37\r\r>", 20),
    ]);
    h.submit(rpm()).unwrap();
    h.pump(12_000);
    h.submit(ObdRequest::new(ObdCommand::mode01(0x0D))).unwrap();
    h.pump(200);
    let r = h.last_obd();
    assert_eq!(r.result, ElmResult::Ok);
    assert_eq!(r.payload, [0x37]);
    assert_eq!(r.unmatched_payloads, 1);
    assert_eq!(r.responder_count, 1);

    // A straggler while idle is a stray line.
    h.inject_later("7E804410C1AF8\r", 5);
    h.pump(10);
    assert_eq!(stray_lines(&h), ["7E804410C1AF8"]);
}

// ---------------------------------------------------------------------------
// Latency and prep statistics
// ---------------------------------------------------------------------------

#[test]
fn latency_includes_prep_and_wire_latency_does_not() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("ATSH7E0", "OK\r\r>", 30),
        step("221310", "7E8056213101234\r\r>", 60),
    ]);
    h.elm.reset_stats();
    h.submit(eot().with_addressing(Addressing::header("7E0", None)))
        .unwrap();
    h.pump(12_000);
    let r = h.last_obd();
    assert_eq!(r.result, ElmResult::Ok);
    assert_eq!(r.latency_ms, 90);
    assert_eq!(r.wire_latency_ms, Some(60));
    assert_eq!(h.elm.prep_overhead_ms(), 30);
    assert_eq!(h.elm.prep_command_count(), 1);
    h.elm.reset_stats();
    assert_eq!(h.elm.prep_overhead_ms(), 0);
    assert_eq!(h.elm.prep_command_count(), 0);
}

// ---------------------------------------------------------------------------
// Lifecycle edges
// ---------------------------------------------------------------------------

#[test]
fn request_ids_match_completions() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("010C", "7E804410C1AF8\r\r>", 20),
        step("ATRV", "12.4V\r\r>", 5),
        step("ATDPN", "A6\r\r>", 5),
    ]);
    let a = h.submit(rpm()).unwrap();
    assert_eq!(h.elm.in_flight(), Some(a));
    h.pump(12_000);
    let b = h.submit(Request::ReadVoltage).unwrap();
    h.pump(50);
    let c = h.raw("ATDPN").unwrap();
    h.pump(50);
    assert!(a < b && b < c);
    assert_eq!(h.last_obd().id, a);
    assert_eq!(h.last_voltage().id, b);
    assert_eq!(h.last_raw_complete().id, c);
    assert_eq!(h.elm.in_flight(), None);
}

#[test]
fn transport_lost_during_raw_marks_addressing_unknown() {
    let mut h = Harness::with_default();
    h.boot(vec![step("ATSH 7E1", "", 0)]);
    h.raw("ATSH 7E1").unwrap();
    h.elm.transport_lost(h.now);
    h.pump(1);
    assert_eq!(h.elm.state(), ElmState::Offline);
    assert_eq!(h.last_raw_complete().result, ElmResult::Timeout);
    // begin() puts the cache back to the ATZ default.
    h.boot(vec![]);
    assert_eq!(h.elm.cached_header(), Some("7DF"));
}

#[test]
fn begin_with_a_request_in_flight_times_it_out() {
    let mut h = Harness::with_default();
    h.boot(vec![step("010C", "", 0)]);
    h.submit(rpm()).unwrap();
    h.boot(vec![]); // owner restarts without waiting
    assert_eq!(h.last_obd().result, ElmResult::Timeout);
}

#[test]
fn bytes_received_while_offline_are_ignored() {
    let mut h = Harness::with_default();
    h.elm.receive(b"7E804410C1AF8\r>", 0);
    h.elm.tick(1_000_000);
    assert_eq!(h.elm.state(), ElmState::Offline);
    assert_eq!(h.elm.poll_event(), None);
    assert_eq!(h.elm.poll_transmit(), None);
}

#[test]
fn stopped_beats_no_data_and_no_responder() {
    let mut h = Harness::with_default();
    h.boot(vec![step("221674", "7E8037F2231\rSTOPPED\r\r>", 20)]);
    h.submit(trans_temp1()).unwrap();
    h.pump(12_000);
    assert_eq!(h.last_obd().result, ElmResult::Stopped);
}
