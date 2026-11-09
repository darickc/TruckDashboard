//! Test vectors taken verbatim from docs/diagnostics/VERIFICATION_LOG.md
//! (captured on the truck, 2026-08-09 and 2026-11-03). The tests themselves
//! are `[SIM]`: the captured bytes are replayed through the scripted adapter.

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod common;

use common::*;
use f250_elm::{ElmResult, ErrorCause, NegativeResponse};

/// "7E8 and 7E9 both answer 010C, and they agree": the four representative
/// request/response pairs from the serial log.
#[test]
fn two_responder_010c_captures() {
    // (7E9 line, 7E8 line, 7E9 bytes, 7E8 bytes, bytes identical?)
    let pairs = [
        (
            "7E904410C0AC4",
            "7E804410C0AC2",
            [0x0A, 0xC4],
            [0x0A, 0xC2],
            false,
        ),
        (
            "7E904410C0AB8",
            "7E804410C0ABA",
            [0x0A, 0xB8],
            [0x0A, 0xBA],
            false,
        ),
        (
            "7E904410C0AC8",
            "7E804410C0AC3",
            [0x0A, 0xC8],
            [0x0A, 0xC3],
            false,
        ),
        (
            "7E904410C0AD0",
            "7E804410C0AD0",
            [0x0A, 0xD0],
            [0x0A, 0xD0],
            true,
        ),
    ];
    let mut h = Harness::with_default();
    let responses: Vec<String> = pairs
        .iter()
        .map(|(a, b, ..)| format!("{a}\r{b}\r\r>"))
        .collect();
    h.boot(responses.iter().map(|r| step("010C", r, 20)).collect());

    for (i, (_, _, p7e9, p7e8, identical)) in pairs.iter().enumerate() {
        h.submit(rpm()).unwrap();
        h.pump(if i == 0 { 12_000 } else { 200 });
        let r = h.last_obd();
        assert_eq!(r.result, ElmResult::Ok, "pair {i}");
        // 7E9 consistently answers first, so first-wins reports 7E9.
        assert_eq!(r.responder_id, Some(0x7E9));
        assert_eq!(r.payload, p7e9);
        assert_eq!(r.responder_count, 2);
        assert_eq!(r.responders[0].can_id, Some(0x7E9));
        assert_eq!(r.responders[0].payload, p7e9);
        assert_eq!(r.responders[1].can_id, Some(0x7E8));
        assert_eq!(r.responders[1].payload, p7e8);
        assert_eq!(r.responders_differ, !identical);
    }
    assert_eq!(h.mismatch, "");
    assert!(h.script_done());
}

/// `raw 221674`: the PCM rejects the DID (NRC 0x31 requestOutOfRange), the TCM
/// answers 62 16 74 04 13 (0x0413 = 1043, /8 = 130.4 F). Unpinned, the client
/// must report the positive answer AND record the negative one.
#[test]
fn trans_temp_capture_unpinned_reports_both() {
    let mut h = Harness::with_default();
    h.boot(vec![step(
        "221674",
        "7E8037F2231\r7E9056216740413\r\r>",
        20,
    )]);

    h.submit(trans_temp_unpinned()).unwrap();
    h.pump(12_000);

    let r = h.last_obd();
    assert_eq!(r.result, ElmResult::Ok);
    assert_eq!(r.responder_id, Some(0x7E9));
    assert_eq!(r.payload, [0x04, 0x13]);
    assert_eq!(r.responder_count, 1); // a negative answer is not a responder
    assert_eq!(
        r.negative_responses,
        [NegativeResponse {
            can_id: Some(0x7E8),
            service: Some(0x22),
            nrc: Some(0x31),
        }]
    );
    assert_eq!(h.mismatch, "");
}

/// Same capture with the shipped pin (expectedResponder = 0x7E9): the PCM's
/// negative response is dropped before reassembly, never parsed or recorded.
#[test]
fn trans_temp_capture_pinned_to_tcm() {
    let mut h = Harness::with_default();
    h.boot(vec![step(
        "221674",
        "7E8037F2231\r7E9056216740413\r\r>",
        20,
    )]);

    h.submit(trans_temp1()).unwrap();
    h.pump(12_000);

    let r = h.last_obd();
    assert_eq!(r.result, ElmResult::Ok);
    assert_eq!(r.responder_id, Some(0x7E9));
    assert_eq!(r.payload, [0x04, 0x13]);
    assert!(r.negative_responses.is_empty());
    assert_eq!(r.ignored_responder_frames, 1);
}

/// From the `ATSH 7E1` session: only the PCM's negative answer came back. With
/// no pin that is an error carrying the NRC; pinned to the TCM it is
/// NoResponder (the TCM was silent, not the bus).
#[test]
fn trans_temp_capture_pcm_negative_only() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("221674", "7E8037F2231\r\r>", 20),
        step("221674", "7E8037F2231\r\r>", 20),
    ]);

    h.submit(trans_temp_unpinned()).unwrap();
    h.pump(12_000);
    let neg = NegativeResponse {
        can_id: Some(0x7E8),
        service: Some(0x22),
        nrc: Some(0x31),
    };
    assert_eq!(
        h.last_obd().result,
        ElmResult::Error(ErrorCause::NegativeResponse(neg))
    );

    h.submit(trans_temp1()).unwrap();
    h.pump(200);
    assert_eq!(h.last_obd().result, ElmResult::NoResponder);
    assert_eq!(h.mismatch, "");
}

/// EOT on the 2026-11-03 drive (adapter traffic log). The usual window: the
/// TCM refuses (`7F 22 12`), the PCM answers `26 91` = 58.73 °C. Pinned to
/// 7E8, the TCM's frame is dropped and the PCM's value is reported.
#[test]
fn eot_capture_pinned_to_pcm() {
    let mut h = Harness::with_default();
    h.boot(vec![step(
        "221310",
        "7E9037F2212\r7E8056213102691\r\r>",
        20,
    )]);

    h.submit(eot_pinned()).unwrap();
    h.pump(12_000);

    let r = h.last_obd();
    assert_eq!(r.result, ElmResult::Ok);
    assert_eq!(r.responder_id, Some(0x7E8));
    assert_eq!(r.payload, [0x26, 0x91]);
    assert!(r.negative_responses.is_empty());
    assert_eq!(r.ignored_responder_frames, 1);
}

/// The other 7 of 738 windows on that drive: adaptive timing closed the window
/// after the TCM's refusal, before the PCM answered. Unpinned, that reads as
/// NRC 0x12, which the gateway treats as "unsupported" and quarantines for
/// 60 s (the dropouts seen on the dashboard). Pinned, it is NoResponder: one
/// ordinary miss.
#[test]
fn eot_capture_tcm_negative_only() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("221310", "7E9037F2212\r\r>", 20),
        step("221310", "7E9037F2212\r\r>", 20),
    ]);

    h.submit(eot()).unwrap();
    h.pump(12_000);
    let neg = NegativeResponse {
        can_id: Some(0x7E9),
        service: Some(0x22),
        nrc: Some(0x12),
    };
    assert_eq!(
        h.last_obd().result,
        ElmResult::Error(ErrorCause::NegativeResponse(neg))
    );

    h.submit(eot_pinned()).unwrap();
    h.pump(200);
    assert_eq!(h.last_obd().result, ElmResult::NoResponder);
    assert_eq!(h.mismatch, "");
}

/// `raw ATDPN` → `A6`. The reply is hex-shaped, so it must come back verbatim
/// as a raw line, never be parsed as data.
#[test]
fn protocol_a6_raw_capture() {
    let mut h = Harness::with_default();
    h.boot(vec![step("ATDPN", "A6\r\r>", 20)]);

    let id = h.raw("ATDPN").unwrap();
    assert!(h.elm.raw_in_flight());
    h.pump(100);
    assert_eq!(h.raw_lines(id), ["A6"]);
    let done = h.last_raw_complete();
    assert_eq!(done.id, id);
    assert_eq!(done.result, ElmResult::Ok);
    assert_eq!(done.latency_ms, 20);
    assert_eq!(h.obd_count(), 0);
    assert!(!h.elm.raw_in_flight());
}

/// The fix recorded in VERIFICATION_LOG.md / TRUCK_SESSION.md: after
/// `raw ATSH 7E1` the cached addressing is UNKNOWN, not "7DF" and not "7E1".
/// A raw follow-up goes out verbatim on whatever the adapter has; the next
/// table request re-establishes both header and filter explicitly.
#[test]
fn raw_atsh_marks_addressing_unknown() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("ATSH 7E1", "OK\r\r>", 5),
        // Raw requests never get prep commands.
        step("010C", "7E804410C0ABC\r7E904410C0ABC\r\r>", 20),
        // A table request after raw: ATSH AND ATCRA, because both are unknown.
        step("ATSH7DF", "OK\r\r>", 5),
        step("ATCRA", "OK\r\r>", 5),
        step("010C", "7E804410C0ABC\r\r>", 20),
    ]);
    assert_eq!(h.elm.cached_header(), Some("7DF"));

    let id = h.raw("ATSH 7E1").unwrap();
    h.pump(50);
    assert_eq!(h.raw_lines(id), ["OK"]);
    assert_eq!(h.elm.cached_header(), None);

    let id = h.raw("010C").unwrap();
    h.pump(50);
    assert_eq!(h.raw_lines(id), ["7E804410C0ABC", "7E904410C0ABC"]);
    assert_eq!(h.obd_count(), 0); // raw replies are not parsed as responses

    h.submit(rpm()).unwrap();
    h.pump(12_000);
    assert_eq!(h.last_obd().result, ElmResult::Ok);
    assert_eq!(h.elm.cached_header(), Some("7DF"));
    assert_eq!(h.mismatch, "");
    assert!(h.script_done());
}
