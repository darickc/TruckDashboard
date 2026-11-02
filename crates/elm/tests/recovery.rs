//! Recovery ladder and init transitions (docs/architecture/diagnostic-recovery.md,
//! docs/esp32/OBD_PROTOCOL.md "Recovery ladder"). `[SIM]`.

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod common;

use common::*;
use f250_elm::{ElmEvent, ElmResult, ElmState, RecoveryStep, ResetReason};

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

#[test]
fn timeout_provokes_prompt_then_idle() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("010C", "7E804410C1AF8\r\r>", 20),
        step("010C", "", 0),
        step("", "\r>", 20),
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
    h.pump(50);
    assert_eq!(h.elm.state(), ElmState::Idle);
    assert_eq!(
        recovery_steps(&h),
        [RecoveryStep::ProvokePrompt {
            consecutive_timeouts: 1
        }]
    );
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
}

#[test]
fn failed_recovery_escalates_to_full_reset() {
    let mut h = Harness::with_default();
    let mut extra = vec![
        step("010C", "7E804410C1AF8\r\r>", 20),
        step("010C", "", 0),
        step("", "", 0), // the recovery CR gets nothing back either
    ];
    extra.extend(boot_steps());
    h.boot(extra);
    h.submit(rpm()).unwrap();
    h.pump(100);
    h.clear_events();

    h.submit(rpm()).unwrap();
    h.pump(500 + 2000); // request timeout, then recovery timeout
    assert_eq!(h.elm.state(), ElmState::Resetting);
    h.pump(200);
    assert_eq!(h.elm.state(), ElmState::Idle);
    assert_eq!(
        recovery_steps(&h),
        [
            RecoveryStep::ProvokePrompt {
                consecutive_timeouts: 1
            },
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
        step("010C", "", 0),
        step("", "\r>", 20),
        step("010C", "", 0),
        step("", "\r>", 20),
        // A success here resets the count...
        step("010C", "7E804410C1AF8\r\r>", 20),
        // ...so two more timeouts are not yet three in a row.
        step("010C", "", 0),
        step("", "\r>", 20),
        step("010C", "", 0),
        step("", "\r>", 20),
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
    let p = |n| RecoveryStep::ProvokePrompt {
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
    let mut extra = vec![step("010C", "", 0), step("", "", 0)];
    extra.extend(boot_steps());
    extra.extend([step("010C", "", 0), step("", "", 0)]);
    extra.extend(boot_steps());
    h.boot(extra);
    for _ in 0..2 {
        h.submit(rpm()).unwrap();
        h.pump(10_000 + 2000 + 300);
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
