//! Recovery ladder and init transitions (docs/architecture/diagnostic-recovery.md,
//! docs/esp32/OBD_PROTOCOL.md "Recovery ladder"). `[SIM]`.

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod common;

use common::*;
use f250_elm::{ElmEvent, ElmResult, ElmState, ObdCommand, ObdRequest, RecoveryStep, ResetReason};

fn recovery_steps(h: &Harness) -> Vec<RecoveryStep> {
    h.events
        .iter()
        .filter_map(|e| match e {
            ElmEvent::Recovery(s) => Some(*s),
            _ => None,
        })
        .collect()
}

fn states(h: &Harness) -> Vec<ElmState> {
    h.events
        .iter()
        .filter_map(|e| match e {
            ElmEvent::StateChanged { to, .. } => Some(*to),
            _ => None,
        })
        .collect()
}

fn stray_lines(h: &Harness) -> Vec<&str> {
    h.events
        .iter()
        .filter_map(|e| match e {
            ElmEvent::StrayLine { line, .. } => Some(line.as_str()),
            _ => None,
        })
        .collect()
}

fn speed() -> ObdRequest {
    ObdRequest::new(ObdCommand::mode01(0x0D))
}

#[test]
fn timeout_waits_for_the_late_prompt_then_idle() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("010C", "7E804410C1AF8\r\r>", 20),
        step("010C", "7E804410C1AF8\r\r>", 550), // answered, but late
    ]);
    h.submit(rpm()).unwrap();
    h.pump(100);
    h.clear_events();

    h.submit(rpm()).unwrap();
    h.pump(499);
    assert_eq!(h.elm.state(), ElmState::AwaitingResponse);
    h.pump(1); // exactly at the 500 ms deadline
    assert_eq!(h.elm.state(), ElmState::Recovering);
    assert_eq!(h.last_obd().result, ElmResult::Timeout);
    assert_eq!(h.last_obd().latency_ms, 500);
    h.pump(50); // the late answer and its prompt
    assert_eq!(h.elm.state(), ElmState::Idle);
    assert_eq!(
        recovery_steps(&h),
        [RecoveryStep::AwaitLateReply {
            consecutive_timeouts: 1
        }]
    );
    assert_eq!(stray_lines(&h), ["7E804410C1AF8"]);
    // Awaiting -> Recovering directly (no transient Idle), then Idle.
    assert_eq!(
        states(&h),
        [
            ElmState::AwaitingResponse,
            ElmState::Recovering,
            ElmState::Idle
        ]
    );
    assert_eq!(h.mismatch, "");
    assert!(h.script_done());
}

/// Regression for the first MX+ session on the truck (bench-log 2026-11-02,
/// adapter-traffic lines at 18294–20855 ms). A reply slowed past the 500 ms
/// timeout; the client sent a bare CR, which an ELM327 answers by repeating
/// the last command. The timed-out request's late prompt was taken as the
/// answer to the CR, the repeat's answer was paired with the next request,
/// and every reply after that was one request behind until `STOPPED`.
#[test]
fn a_slow_reply_does_not_put_later_replies_out_of_step() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("010D", "7E803410D00\r7E903410D00\r\r>", 30), // healthy so far
        // 18294 TX 010D; the prompt came back 631 ms later.
        step("010D", "7E803410D00\r7E903410D00\r\r>", 631),
        // The next request: its own answer, 30 ms later, value 0x2A.
        step("010D", "7E803410D2A\r7E903410D2A\r\r>", 30),
    ]);
    h.submit(speed()).unwrap();
    h.pump(100);
    h.clear_events();

    h.submit(speed()).unwrap();
    h.pump(499);
    let written = h.written.len();
    h.pump(1);
    assert_eq!(h.last_obd().result, ElmResult::Timeout);

    h.pump(130); // up to 1 ms before the late prompt
    assert_eq!(h.elm.state(), ElmState::Recovering);
    assert_eq!(h.written.len(), written, "nothing is sent while waiting");
    h.pump(1);
    assert_eq!(h.elm.state(), ElmState::Idle);
    assert_eq!(stray_lines(&h), ["7E803410D00", "7E903410D00"]);

    h.submit(speed()).unwrap();
    h.pump(100);
    let r = h.last_obd();
    assert_eq!(r.result, ElmResult::Ok);
    assert_eq!(r.latency_ms, 30, "the answer is this request's own");
    assert_eq!(r.payload, [0x2A]);
    assert_eq!(r.responder_id, Some(0x7E8));
    assert_eq!(h.elm.state(), ElmState::Idle);
    assert_eq!(h.mismatch, "");
    assert!(h.script_done());
}

#[test]
fn silent_adapter_is_probed_with_ati_and_a_stale_prompt_is_not_enough() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("010C", "7E804410C1AF8\r\r>", 20),
        step("010C", "", 0), // the request was lost: no late prompt either
        // A prompt from before the probe, then the probe's own answer.
        step("ATI", "\r>ELM327 v1.4b\r\r>", 20),
    ]);
    h.submit(rpm()).unwrap();
    h.pump(100);
    h.clear_events();

    h.submit(rpm()).unwrap();
    h.pump(500 + 999);
    assert_eq!(h.elm.state(), ElmState::Recovering);
    assert!(!h.written.contains(&"ATI".to_owned()));
    h.pump(1); // late_reply_timeout_ms: probe
    assert_eq!(h.written.last().map(String::as_str), Some("ATI"));
    h.pump(50);
    assert_eq!(h.elm.state(), ElmState::Idle);
    assert_eq!(
        recovery_steps(&h),
        [
            RecoveryStep::AwaitLateReply {
                consecutive_timeouts: 1
            },
            RecoveryStep::ProbeAdapter,
        ]
    );
    assert!(stray_lines(&h).is_empty(), "the ATI answer is not a stray");
    assert_eq!(h.mismatch, "");
    assert!(h.script_done());
}

#[test]
fn failed_recovery_escalates_to_full_reset() {
    let mut h = Harness::with_default();
    let mut extra = vec![
        step("010C", "7E804410C1AF8\r\r>", 20),
        step("010C", "", 0),
        step("ATI", "\r>", 20), // a prompt, but no identification: not alive
    ];
    extra.extend(boot_steps());
    h.boot(extra);
    h.submit(rpm()).unwrap();
    h.pump(100);
    h.clear_events();

    h.submit(rpm()).unwrap();
    h.pump(500 + 1000 + 2000); // request timeout, late-reply wait, probe timeout
    assert_eq!(h.elm.state(), ElmState::Resetting);
    h.pump(200);
    assert_eq!(h.elm.state(), ElmState::Idle);
    assert_eq!(
        recovery_steps(&h),
        [
            RecoveryStep::AwaitLateReply {
                consecutive_timeouts: 1
            },
            RecoveryStep::ProbeAdapter,
            RecoveryStep::AdapterReset {
                attempt: 1,
                max: 2,
                reason: ResetReason::RecoveryFailed
            },
        ]
    );
    assert!(h.events.iter().any(|e| matches!(e, ElmEvent::Ready { .. })));
    assert_eq!(h.mismatch, "");
    assert!(h.script_done());
}

#[test]
fn consecutive_timeouts_escalate_and_success_resets_the_count() {
    let mut h = Harness::with_default();
    let mut extra = vec![
        step("010C", "7E804410C1AF8\r\r>", 20),
        step("010C", "7E804410C1AF8\r\r>", 550), // late: a timeout
        step("010C", "7E804410C1AF8\r\r>", 550),
        // A success here resets the count...
        step("010C", "7E804410C1AF8\r\r>", 20),
        // ...so two more timeouts are not yet three in a row.
        step("010C", "7E804410C1AF8\r\r>", 550),
        step("010C", "7E804410C1AF8\r\r>", 550),
        step("010C", "", 0), // third in a row: full reset
    ];
    extra.extend(boot_steps());
    h.boot(extra);

    h.submit(rpm()).unwrap();
    h.pump(100);
    h.clear_events();
    let run = |h: &mut Harness| {
        h.submit(rpm()).unwrap();
        h.pump(600);
        h.pump(100);
    };
    for _ in 0..6 {
        run(&mut h);
    }
    h.pump(300);
    assert_eq!(h.elm.state(), ElmState::Idle);
    let p = |n| RecoveryStep::AwaitLateReply {
        consecutive_timeouts: n,
    };
    assert_eq!(
        recovery_steps(&h),
        [
            p(1),
            p(2),
            p(1),
            p(2),
            RecoveryStep::AdapterReset {
                attempt: 1,
                max: 2,
                reason: ResetReason::ConsecutiveTimeouts
            },
        ]
    );
    assert_eq!(h.mismatch, "");
    assert!(h.script_done());
}

#[test]
fn failed_resets_go_offline_and_begin_restarts() {
    let mut h = Harness::with_default();
    h.set_script(vec![
        step("ATZ", "", 0),
        step("ATZ", "", 0),
        step("ATZ", "", 0),
    ]);
    h.begin();
    assert_eq!(h.elm.state(), ElmState::Resetting);
    assert_eq!(h.elm.next_deadline(), Some(6000));

    h.pump(6000 * 3);
    assert_eq!(h.elm.state(), ElmState::Offline);
    assert_eq!(h.elm.next_deadline(), None);
    let r = |attempt| RecoveryStep::AdapterReset {
        attempt,
        max: 2,
        reason: ResetReason::ResetTimeout,
    };
    assert_eq!(
        recovery_steps(&h),
        [
            r(1),
            r(2),
            RecoveryStep::GaveUp {
                reason: ResetReason::ResetTimeout
            }
        ]
    );
    assert!(h.script_done());

    // Offline is terminal until the owner reconnects and calls begin().
    h.pump(10_000);
    assert!(h.script_done());
    h.boot(vec![]);
}

#[test]
fn init_command_timeout_resets() {
    let mut h = Harness::with_default();
    let mut steps = vec![
        step("ATZ", "\r\rELM327 v1.4b\r\r>", 50),
        step("ATE0", "", 0), // never answered
    ];
    steps.extend(boot_steps());
    h.set_script(steps);
    h.begin();
    h.pump(50 + 2000);
    assert_eq!(h.elm.state(), ElmState::Resetting);
    h.pump(300);
    assert_eq!(h.elm.state(), ElmState::Idle);
    assert_eq!(
        recovery_steps(&h),
        [RecoveryStep::AdapterReset {
            attempt: 1,
            max: 2,
            reason: ResetReason::InitTimeout
        }]
    );
    assert_eq!(h.mismatch, "");
}

#[test]
fn rejected_init_command_is_retried_once_then_skipped() {
    let mut h = Harness::with_default();
    h.set_script(vec![
        step("ATZ", "\r\rELM327 v1.4b\r\r>", 50),
        step("ATE0", "OK\r\r>", 5),
        step("ATL0", "OK\r\r>", 5),
        step("ATS0", "OK\r\r>", 5),
        step("ATH1", "OK\r\r>", 5),
        step("ATAT1", "?\r\r>", 5),  // rejected...
        step("ATAT1", "?\r\r>", 5),  // ...and rejected on the retry: skipped
        step("ATSP0", "?\r\r>", 5),  // rejected...
        step("ATSP0", "OK\r\r>", 5), // ...but the retry works
    ]);
    h.begin();
    h.pump(200);
    assert_eq!(h.mismatch, "");
    assert!(h.script_done());
    assert_eq!(h.elm.state(), ElmState::Idle);
    let failed: Vec<_> = h
        .events
        .iter()
        .filter_map(|e| match e {
            ElmEvent::InitCommandFailed { command } => Some(command.as_str()),
            _ => None,
        })
        .collect();
    assert_eq!(failed, ["ATAT1"]);
    assert!(h.events.contains(&ElmEvent::Ready {
        adapter_id: Some("ELM327 v1.4b".into())
    }));
}

#[test]
fn idle_deadline_is_benign() {
    let mut h = Harness::with_default();
    h.boot(vec![]);
    let written = h.written.len();
    h.clear_events();
    h.pump(60_000);
    assert_eq!(h.elm.state(), ElmState::Idle);
    assert_eq!(h.written.len(), written);
    assert!(h.events.is_empty());
}

#[test]
fn reset_attempts_are_restored_after_a_successful_init() {
    // Two separate escalations, each recovered, never reach Offline: the
    // attempt counter resets when init completes.
    let mut h = Harness::with_default();
    let mut extra = vec![step("010C", "", 0), step("ATI", "", 0)];
    extra.extend(boot_steps());
    extra.extend([step("010C", "", 0), step("ATI", "", 0)]);
    extra.extend(boot_steps());
    h.boot(extra);
    for _ in 0..2 {
        h.submit(rpm()).unwrap();
        h.pump(10_000 + 1000 + 2000 + 300);
        assert_eq!(h.elm.state(), ElmState::Idle);
    }
    let resets: Vec<_> = recovery_steps(&h)
        .into_iter()
        .filter_map(|s| match s {
            RecoveryStep::AdapterReset { attempt, .. } => Some(attempt),
            _ => None,
        })
        .collect();
    assert_eq!(resets, [1, 1]);
    assert_eq!(h.mismatch, "");
}
