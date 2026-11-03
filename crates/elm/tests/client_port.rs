//! Port of every test in `firmware/esp32/test/test_elm_client/test_main.cpp`.
//! Each test names its C++ original. `[SIM]`: scripted adapter, virtual clock.

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod common;

use common::*;
use f250_elm::{Addressing, ElmResult, ElmState, ErrorCause, NegativeResponse, SubmitError};

// C++: test_init_sequence_reaches_idle
#[test]
fn init_sequence_reaches_idle() {
    let mut h = Harness::with_default();
    h.boot(vec![]);
    assert_eq!(h.elm.adapter_id(), Some("ELM327 v1.4b"));
    assert!(h.script_done());
}

// C++: test_rpm_request_happy_path
#[test]
fn rpm_request_happy_path() {
    let mut h = Harness::with_default();
    // First data request: the adapter searches for the protocol first.
    h.boot(vec![step("010C", "SEARCHING...\r7E804410C1AF8\r\r>", 300)]);

    h.submit(rpm()).unwrap();
    assert_eq!(h.elm.state(), ElmState::AwaitingResponse);
    assert_eq!(
        h.submit(rpm()),
        Err(SubmitError::NotIdle(ElmState::AwaitingResponse))
    );

    h.pump(400);
    assert_eq!(h.mismatch, "");
    assert_eq!(h.obd_count(), 1);
    let r = h.last_obd();
    assert_eq!(r.result, ElmResult::Ok);
    // Echo-stripped: A=0x1A B=0xF8 -> 1726 rpm.
    assert_eq!(r.payload, [0x1A, 0xF8]);
    assert_eq!(h.elm.state(), ElmState::Idle);
}

// C++: test_no_data_and_stopped
#[test]
fn no_data_and_stopped() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("010C", "7E804410C1AF8\r\r>", 20), // first request OK
        step("010C", "NO DATA\r\r>", 20),
        step("010C", "STOPPED\r\r>", 20),
    ]);

    h.submit(rpm()).unwrap();
    h.pump(100);
    assert_eq!(h.last_obd().result, ElmResult::Ok);

    h.submit(rpm()).unwrap();
    h.pump(100);
    assert_eq!(h.last_obd().result, ElmResult::NoData);
    assert_eq!(h.elm.state(), ElmState::Idle); // NO DATA is not fatal

    h.submit(rpm()).unwrap();
    h.pump(100);
    assert_eq!(h.last_obd().result, ElmResult::Stopped);
    assert_eq!(h.elm.state(), ElmState::Idle);
    assert_eq!(h.mismatch, "");
}

// C++: test_negative_response_is_error
#[test]
fn negative_response_is_error() {
    let mut h = Harness::with_default();
    // 7F 22 31 = negative response, requestOutOfRange.
    h.boot(vec![step("221310", "7E8037F2231\r\r>", 20)]);

    h.submit(eot()).unwrap();
    h.pump(12_000); // inside the first-request SEARCHING window
    let r = h.last_obd();
    let neg = NegativeResponse {
        can_id: Some(0x7E8),
        service: Some(0x22),
        nrc: Some(0x31),
    };
    assert_eq!(
        r.result,
        ElmResult::Error(ErrorCause::NegativeResponse(neg))
    );
    assert_eq!(r.negative_responses, [neg]);
    assert_eq!(r.responder_count, 0);
    assert_eq!(h.mismatch, "");
}

// C++: test_timeout_then_recovery. Diverges from the C++, which sends a bare
// CR here (bench-log 2026-11-02): the Rust client waits for a late prompt,
// then probes with ATI.
#[test]
fn timeout_then_recovery() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("010C", "7E804410C1AF8\r\r>", 20), // first request OK
        step("010C", "", 0),                    // adapter goes silent
        step("ATI", "ELM327 v1.4b\r\r>", 20),   // the probe gets an answer
    ]);

    h.submit(rpm()).unwrap();
    h.pump(100);
    assert_eq!(h.last_obd().result, ElmResult::Ok);

    h.submit(rpm()).unwrap();
    h.pump(600); // past the 500 ms per-request timeout
    assert_eq!(h.last_obd().result, ElmResult::Timeout);
    h.pump(1000 + 100); // no late prompt; the probe answer arrives
    assert_eq!(h.elm.state(), ElmState::Idle);
    assert_eq!(h.mismatch, "");
}

// C++: test_transport_loss_and_reinit
#[test]
fn transport_loss_and_reinit() {
    let mut h = Harness::with_default();
    h.boot(vec![]);

    // Link drops mid-flight.
    h.submit(rpm()).unwrap();
    h.connected = false;
    h.elm.transport_lost(h.now);
    h.pump(1);
    assert_eq!(h.elm.state(), ElmState::Offline);
    assert_eq!(h.last_obd().result, ElmResult::Timeout); // in-flight request aborted

    // Owner reconnects and re-inits; a fresh boot script runs cleanly.
    h.connected = true;
    h.boot(vec![]);
}

// C++: test_unverified_header_refused
#[test]
fn unverified_header_refused() {
    let mut h = Harness::with_default();
    h.boot(vec![]);
    // TransTemp2 uses ObdModule::Tcm, whose header is unverified.
    assert_eq!(h.submit(trans_temp2()), Err(SubmitError::UnverifiedHeader));
    assert_eq!(h.elm.state(), ElmState::Idle); // still usable
    assert!(h.script_done()); // nothing was written
}

// ---------------------------------------------------------------------------
// Responder identity
// ---------------------------------------------------------------------------

// C++: test_responder_id_and_count_reported
#[test]
fn responder_id_and_count_reported() {
    let mut h = Harness::with_default();
    // 7E9 answers first, exactly as the truck log shows.
    h.boot(vec![step("010C", "7E904410C0AE0\r7E804410C0AE0\r\r>", 20)]);

    h.submit(rpm()).unwrap();
    h.pump(12_000);

    let r = h.last_obd();
    assert_eq!(r.result, ElmResult::Ok);
    assert_eq!(r.responder_id, Some(0x7E9)); // first to answer is reported
    assert_eq!(r.responder_count, 2);
    // Both answers recorded, in arrival order, with their CAN IDs.
    assert_eq!(r.responders.len(), 2);
    assert_eq!(r.responders[0].can_id, Some(0x7E9));
    assert_eq!(r.responders[1].can_id, Some(0x7E8));
    assert_eq!(r.responders[0].payload, [0x0A, 0xE0]);
    assert!(!r.responders_differ); // identical bytes
    assert_eq!(h.mismatch, "");
}

// C++: test_more_responders_than_slots_are_counted_not_recorded
#[test]
fn more_responders_than_slots_are_counted_not_recorded() {
    let mut h = Harness::with_default();
    // Four ECUs answer. Recording is bounded, but the COUNT must stay honest.
    h.boot(vec![step(
        "010C",
        "7E804410C1AF8\r7E904410C1AF8\r7EA04410C1AF8\r7EB04410C1AF8\r\r>",
        20,
    )]);

    h.submit(rpm()).unwrap();
    h.pump(12_000);

    let r = h.last_obd();
    assert_eq!(r.result, ElmResult::Ok);
    assert_eq!(r.responder_count, 4);
    assert_eq!(r.responders.len(), h.elm.config().max_recorded_responders);
    assert_eq!(r.responders.len(), 3);
    assert_eq!(r.responders[0].can_id, Some(0x7E8));
    assert_eq!(r.responders[2].can_id, Some(0x7EA));
}

// C++: test_identical_responders_do_not_differ
#[test]
fn identical_responders_do_not_differ() {
    let mut h = Harness::with_default();
    h.boot(vec![step("010C", "7E804410C1AF8\r7E904410C1AF8\r\r>", 20)]);

    h.submit(rpm()).unwrap();
    h.pump(12_000);
    let r = h.last_obd();
    assert_eq!(r.result, ElmResult::Ok);
    assert_eq!(r.responder_count, 2);
    assert!(!r.responders_differ);
}

// C++: test_differing_responders_are_recorded_not_judged
#[test]
fn differing_responders_are_recorded_not_judged() {
    let mut h = Harness::with_default();
    // Two modules answer 22 1674 with different bytes; both are handed up.
    h.boot(vec![step(
        "221674",
        "7E8056216740A2C\r7E9056216740000\r\r>",
        20,
    )]);

    // Explicitly unpinned: this is about BEFORE ownership is established.
    h.submit(trans_temp_unpinned()).unwrap();
    h.pump(12_000);

    let r = h.last_obd();
    assert_eq!(r.result, ElmResult::Ok);
    assert_eq!(r.responder_id, Some(0x7E8));
    assert_eq!(r.responder_count, 2);
    assert!(r.responders_differ);
    assert_eq!(r.responders.len(), 2);
    assert_eq!(r.responders[0].can_id, Some(0x7E8));
    assert_eq!(r.responders[0].payload, [0x0A, 0x2C]);
    assert_eq!(r.responders[1].can_id, Some(0x7E9));
    assert_eq!(r.responders[1].payload, [0x00, 0x00]);
    assert_eq!(h.mismatch, "");
}

// C++: test_rpm_sampling_jitter_is_not_treated_as_disagreement
#[test]
fn rpm_sampling_jitter_is_not_treated_as_disagreement() {
    // 7E9=0AC4 is 689.00 rpm, 7E8=0AC2 is 688.50 rpm. The BYTES differ, which
    // is all the client can honestly say.
    let mut h = Harness::with_default();
    h.boot(vec![step("010C", "7E904410C0AC4\r7E804410C0AC2\r\r>", 20)]);

    h.submit(rpm()).unwrap();
    h.pump(12_000);

    let r = h.last_obd();
    assert_eq!(r.result, ElmResult::Ok);
    assert!(r.responders_differ); // a fact about the bytes...
    assert_eq!(r.responders.len(), 2); // ...and both are kept
    assert_eq!(r.responders[0].payload[1], 0xC4);
    assert_eq!(r.responders[1].payload[1], 0xC2);
}

// C++: test_expected_responder_preferred_when_it_answers_second
#[test]
fn expected_responder_preferred_when_it_answers_second() {
    let mut h = Harness::with_default();
    h.boot(vec![step(
        "221674",
        "7E9056216740000\r7E8056216740A2C\r\r>",
        20,
    )]);

    // Pinned to 7E8: 7E9's earlier answer must be dropped, not raced.
    h.submit(trans_temp_unpinned().with_expected_responder(0x7E8))
        .unwrap();
    h.pump(12_000);

    let r = h.last_obd();
    assert_eq!(r.result, ElmResult::Ok);
    assert_eq!(r.responder_id, Some(0x7E8));
    assert_eq!(r.responder_count, 1); // 7E9 never counted
    assert_eq!(r.responders.len(), 1); // nor recorded
    assert_eq!(r.responders[0].can_id, Some(0x7E8));
    assert!(!r.responders_differ);
    assert_eq!(r.payload, [0x0A, 0x2C]);
    assert_eq!(r.ignored_responder_frames, 1);
}

// C++: test_expected_responder_absent_yields_no_responder
#[test]
fn expected_responder_absent_yields_no_responder() {
    let mut h = Harness::with_default();
    h.boot(vec![step("221674", "7E9056216740000\r\r>", 20)]);

    h.submit(trans_temp_unpinned().with_expected_responder(0x7E8))
        .unwrap();
    h.pump(12_000);

    // Somebody answered, just not the pinned module: not a dead PID.
    let r = h.last_obd();
    assert_eq!(r.result, ElmResult::NoResponder);
    assert!(r.payload.is_empty());
}

// C++: test_pinned_multiframe_survives_interleaving
#[test]
fn pinned_multiframe_survives_interleaving() {
    let mut h = Harness::with_default();
    // Total payload 9 bytes: 62 16 74 (echo) + AA BB CC DD EE FF.
    h.boot(vec![step(
        "221674",
        concat!(
            "7E81009621674AABBCC\r", // 7E8 first frame (PCI 10 09)
            "7E91009621674110022\r", // 7E9 first frame: must be ignored
            "7E921334455\r",         // 7E9 consecutive: must be ignored
            "7E821DDEEFF\r",         // 7E8 consecutive: completes it
            "\r>"
        ),
        20,
    )]);

    h.submit(trans_temp_unpinned().with_expected_responder(0x7E8))
        .unwrap();
    h.pump(12_000);

    let r = h.last_obd();
    assert_eq!(r.result, ElmResult::Ok);
    assert_eq!(r.responder_id, Some(0x7E8));
    assert_eq!(r.payload, [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]); // 9 - 3 echo
    assert_eq!(r.ignored_responder_frames, 2);
}

// ---------------------------------------------------------------------------
// Latency
// ---------------------------------------------------------------------------

// C++: test_latency_is_measured
#[test]
fn latency_is_measured() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("010C", "7E804410C1AF8\r\r>", 20), // first request clears SEARCHING
        step("010C", "7E804410C1AF8\r\r>", 90), // ~the 96 ms measured on the truck
    ]);

    h.submit(rpm()).unwrap();
    h.pump(200);
    assert_eq!(h.last_obd().result, ElmResult::Ok);

    h.submit(rpm()).unwrap();
    h.pump(200);
    let r = h.last_obd();
    assert_eq!(r.result, ElmResult::Ok);
    let wire = r.wire_latency_ms.unwrap();
    assert!(wire.abs_diff(90) <= 3, "wire latency {wire}");
    assert_eq!(r.latency_ms, wire); // no prep: submit == request written
}

// ---------------------------------------------------------------------------
// Addressing: ATSH / ATCRA sequencing and cache invalidation
// ---------------------------------------------------------------------------

// C++: test_atsh_sent_on_header_change_and_not_resent
#[test]
fn atsh_sent_on_header_change_and_not_resent() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("ATSH726", "OK\r\r>", 5),
        step("221674", "7E8056216740A2C\r\r>", 20),
        // Same header again: no ATSH, straight to the request.
        step("221674", "7E8056216740A2C\r\r>", 20),
        // Back to a functional request: ATSH restores 7DF.
        step("ATSH7DF", "OK\r\r>", 5),
        step("010C", "7E804410C1AF8\r\r>", 20),
    ]);

    let on726 = trans_temp_unpinned().with_addressing(hdr726());
    h.submit(on726.clone()).unwrap();
    h.pump(12_000);
    assert_eq!(h.last_obd().result, ElmResult::Ok);

    h.submit(on726).unwrap();
    h.pump(200);
    assert_eq!(h.last_obd().result, ElmResult::Ok);

    h.submit(rpm()).unwrap();
    h.pump(200);
    assert_eq!(h.last_obd().result, ElmResult::Ok);

    // The mock asserts on every write: an unexpected/missing ATSH shows here.
    assert_eq!(h.mismatch, "");
    assert!(h.script_done());
}

// C++: test_atcra_follows_atsh_and_is_cleared_on_return
#[test]
fn atcra_follows_atsh_and_is_cleared_on_return() {
    let mut h = Harness::with_default();
    // The "try ATSH 7E0 + ATCRA 7E8 for the PCM" experiment, as explicit
    // addressing on the request (the C++ runtime override).
    h.boot(vec![
        step("ATSH7E0", "OK\r\r>", 5),  // header first...
        step("ATCRA7E8", "OK\r\r>", 5), // ...then the receive filter
        step("221446", "7E8056214461234\r\r>", 20),
        // Back to functional: restore 7DF AND clear the filter (bare ATCRA).
        step("ATSH7DF", "OK\r\r>", 5),
        step("ATCRA", "OK\r\r>", 5),
        step("010C", "7E804410C1AF8\r\r>", 20),
    ]);

    let icp_on_pcm = icp().with_addressing(Addressing::header("7E0", Some("7E8".into())));
    h.submit(icp_on_pcm).unwrap();
    h.pump(12_000);
    assert_eq!(h.last_obd().result, ElmResult::Ok);

    h.submit(rpm()).unwrap();
    h.pump(200);
    assert_eq!(h.last_obd().result, ElmResult::Ok);
    assert_eq!(h.mismatch, "");
    assert!(h.script_done());
}

// C++: test_header_cache_invalidated_by_atz_recovery
#[test]
fn header_cache_invalidated_by_atz_recovery() {
    // Regression: the recovery ladder reaches ATZ WITHOUT going through
    // begin(). If the cached header survived that ATZ, the next request would
    // skip its ATSH and go out on 7DF while the code believed it was on 726.
    let mut h = Harness::with_default();
    let mut extra = vec![
        step("ATSH726", "OK\r\r>", 5),
        step("221674", "7E8056216740A2C\r\r>", 20), // now cached on "726"
        // Three silent requests drive the timeout ladder into a full ATZ.
        step("221674", "", 0),
        step("ATI", "ELM327 v1.4b\r\r>", 20),
        step("221674", "", 0),
        step("ATI", "ELM327 v1.4b\r\r>", 20),
        step("221674", "", 0),
    ];
    extra.extend(boot_steps());
    // THE ASSERTION: ATZ reverted the adapter to 7DF, so ATSH must come back.
    extra.push(step("ATSH726", "OK\r\r>", 5));
    extra.push(step("221674", "7E8056216740A2C\r\r>", 20));
    h.boot(extra);

    let on726 = trans_temp_unpinned().with_addressing(hdr726());
    h.submit(on726.clone()).unwrap();
    h.pump(12_000);
    assert_eq!(h.last_obd().result, ElmResult::Ok);

    for _ in 0..3 {
        h.submit(on726.clone()).unwrap();
        h.pump(700); // past the 500 ms per-request timeout
        assert_eq!(h.last_obd().result, ElmResult::Timeout);
        h.pump(1000 + 200); // probe answer / ATZ banner
    }
    h.pump(500); // finish re-init
    assert_eq!(h.elm.state(), ElmState::Idle);

    h.submit(on726).unwrap();
    h.pump(12_000);
    assert_eq!(h.last_obd().result, ElmResult::Ok);
    assert_eq!(h.mismatch, "");
    assert!(h.script_done());
}

// C++: test_rejected_addressing_command_fails_the_request
#[test]
fn rejected_addressing_command_fails_the_request() {
    let mut h = Harness::with_default();
    h.boot(vec![step("ATSH726", "?\r\r>", 5)]); // adapter rejects the header

    h.submit(trans_temp_unpinned().with_addressing(hdr726()))
        .unwrap();
    h.pump(200);

    let r = h.last_obd();
    assert_eq!(
        r.result,
        ElmResult::Error(ErrorCause::AddressingRejected {
            command: "ATSH726".into(),
            line: "?".into(),
        })
    );
    assert_eq!(r.wire_latency_ms, None); // the request line never went out
    assert_eq!(h.elm.state(), ElmState::Idle); // still usable
    assert_eq!(h.mismatch, "");
}

// ---------------------------------------------------------------------------
// Response-count digit
// ---------------------------------------------------------------------------

// C++: test_response_count_digit_appended
#[test]
fn response_count_digit_appended() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("ATSH7E0", "OK\r\r>", 5),
        // 3-byte Mode 22 request + count digit: odd length, so the ELM reads
        // the trailing digit as a response count rather than as data.
        step("2213101", "7E8056213101234\r\r>", 20),
    ]);

    let eot_on_pcm = eot()
        .with_addressing(Addressing::header("7E0", None))
        .with_expected_responses(1);
    h.submit(eot_on_pcm).unwrap();
    h.pump(12_000);

    assert_eq!(h.last_obd().result, ElmResult::Ok);
    assert_eq!(h.mismatch, "");
}
