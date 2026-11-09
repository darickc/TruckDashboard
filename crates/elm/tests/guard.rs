//! ADR-0007 service allow-list: a refused request is never written; allowed
//! ones are. `[SIM]`.

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod common;

use common::*;
use f250_elm::{
    Addressing, ConfigError, ElmClient, ElmConfig, ElmResult, ElmState, ObdCommand, ObdRequest,
    RawLineError, Request, ServiceAllowList, SubmitError,
};

/// Boot, try `req`, and assert it was refused with `err` and nothing written.
fn assert_refused(h: &mut Harness, req: Request, err: SubmitError) {
    let written = h.written.len();
    assert_eq!(h.submit(req), Err(err));
    h.pump(50);
    assert_eq!(
        h.written.len(),
        written,
        "a refused request wrote something"
    );
    assert_eq!(h.elm.state(), ElmState::Idle);
}

#[test]
fn refused_services_are_never_written() {
    let mut h = Harness::with_default();
    h.boot(vec![]);
    for service in [
        0x04, 0x10, 0x11, 0x14, 0x27, 0x2E, 0x2F, 0x31, 0x3B, 0x02, 0x19,
    ] {
        assert_refused(
            &mut h,
            ObdRequest::new(ObdCommand::Service { service }).into(),
            SubmitError::ServiceNotAllowed(service),
        );
        assert_refused(
            &mut h,
            ObdRequest::new(ObdCommand::Pid { service, pid: 0x00 }).into(),
            SubmitError::ServiceNotAllowed(service),
        );
    }
    assert_eq!(h.mismatch, "");
    assert!(h.script_done());
}

#[test]
fn refused_raw_hex_lines_are_never_written() {
    let mut h = Harness::with_default();
    h.boot(vec![]);
    let cases = [
        ("04", RawLineError::ServiceNotAllowed(0x04)),
        ("14FF00", RawLineError::ServiceNotAllowed(0x14)),
        ("2E 16 74 00", RawLineError::ServiceNotAllowed(0x2E)),
        ("1003", RawLineError::ServiceNotAllowed(0x10)),
        ("3101FF00", RawLineError::ServiceNotAllowed(0x31)),
        ("STPX H:7E0, D:1101", RawLineError::NotAtOrHex),
        ("ATI\r14FF00", RawLineError::ControlCharacter),
        ("ATCAF0", RawLineError::AtCommandRefused("ATCAF0".into())),
        (
            "AT PP 24 SV 00",
            RawLineError::AtCommandRefused("ATPP24SV00".into()),
        ),
        ("", RawLineError::Empty),
    ];
    for (line, err) in cases {
        assert_refused(&mut h, Request::Raw(line.into()), SubmitError::Raw(err));
    }
    assert!(h.script_done());
}

#[test]
fn allowed_services_are_written() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("010C", "7E804410C1AF8\r\r>", 20),
        step("03", "7E8024300\r\r>", 20),
        step("07", "7E8024700\r\r>", 20),
        step("0902", "NO DATA\r\r>", 20),
        step("221674", "7E9056216740413\r\r>", 20),
    ]);
    let reqs = [
        rpm(),
        ObdRequest::new(ObdCommand::Service { service: 0x03 }),
        ObdRequest::new(ObdCommand::Service { service: 0x07 }),
        ObdRequest::new(ObdCommand::Pid {
            service: 0x09,
            pid: 0x02,
        }),
        trans_temp1(),
    ];
    for req in reqs {
        h.submit(req).unwrap();
        h.pump(12_000);
    }
    assert_eq!(h.mismatch, "");
    assert!(h.script_done());
    let results: Vec<_> = h.obd_responses().iter().map(|r| r.result.clone()).collect();
    assert_eq!(
        results,
        [
            ElmResult::Ok,
            ElmResult::Ok,
            ElmResult::Ok,
            ElmResult::NoData,
            ElmResult::Ok
        ]
    );
    // 03 (synthetic vector, no stored DTCs): only the service byte is echoed; the count byte
    // (00) is payload.
    assert_eq!(h.obd_responses()[1].payload, [0x00]);
}

#[test]
fn allowed_raw_lines_are_written() {
    let mut h = Harness::with_default();
    h.boot(vec![
        step("ATZ", "\r\rELM327 v1.4b\r\r>", 50),
        step("221674", "7E8037F2231\r7E9056216740413\r\r>", 20),
        step("2213101", "NO DATA\r\r>", 20),
    ]);
    for line in ["ATZ", "221674", "2213101"] {
        h.raw(line).unwrap();
        h.pump(200);
        assert_eq!(h.last_raw_complete().result, ElmResult::Ok);
    }
    assert_eq!(h.mismatch, "");
    assert!(h.script_done());
}

#[test]
fn custom_allow_list_is_enforced() {
    let cfg = ElmConfig {
        allowed_services: ServiceAllowList::new([0x01]).unwrap(),
        ..test_config()
    };
    let mut h = Harness::new(cfg);
    h.boot(vec![step("010C", "7E804410C1AF8\r\r>", 20)]);
    assert_refused(
        &mut h,
        trans_temp1().into(),
        SubmitError::ServiceNotAllowed(0x22),
    );
    assert_refused(
        &mut h,
        Request::Raw("221674".into()),
        SubmitError::Raw(RawLineError::ServiceNotAllowed(0x22)),
    );
    h.submit(rpm()).unwrap();
    h.pump(100);
    assert_eq!(h.last_obd().result, ElmResult::Ok);
}

#[test]
fn guard_runs_before_the_busy_check() {
    // A forbidden request is refused as forbidden even mid-request.
    let mut h = Harness::with_default();
    h.boot(vec![step("010C", "7E804410C1AF8\r\r>", 20)]);
    h.submit(rpm()).unwrap();
    assert_eq!(
        h.submit(ObdRequest::new(ObdCommand::Service { service: 0x04 })),
        Err(SubmitError::ServiceNotAllowed(0x04))
    );
    assert_eq!(
        h.submit(rpm()),
        Err(SubmitError::NotIdle(ElmState::AwaitingResponse))
    );
}

#[test]
fn init_commands_pass_the_same_guard() {
    let cfg = ElmConfig {
        init_commands: vec!["ATE0".into(), "14FF00".into()],
        ..ElmConfig::default()
    };
    assert_eq!(
        ElmClient::new(cfg).err(),
        Some(ConfigError::InitCommand {
            command: "14FF00".into(),
            error: RawLineError::ServiceNotAllowed(0x14),
        })
    );
    let cfg = ElmConfig {
        init_commands: vec!["ATCAF0".into()],
        ..ElmConfig::default()
    };
    assert!(ElmClient::new(cfg).is_err());
    assert!(ElmClient::new(ElmConfig::default()).is_ok());
}

#[test]
fn other_request_validation() {
    let mut h = Harness::with_default();
    h.boot(vec![]);
    // Response-count digit only on a physical header.
    assert_refused(
        &mut h,
        rpm().with_expected_responses(1).into(),
        SubmitError::CountDigitOnFunctionalHeader,
    );
    assert_refused(
        &mut h,
        rpm()
            .with_addressing(Addressing::header("7E0", None))
            .with_expected_responses(10)
            .into(),
        SubmitError::InvalidResponseCount(10),
    );
    assert_refused(
        &mut h,
        rpm()
            .with_addressing(Addressing::header("7G0", None))
            .into(),
        SubmitError::InvalidHeader("7G0".into()),
    );
    assert_refused(
        &mut h,
        rpm()
            .with_addressing(Addressing::header("7E0", Some("ZZ".into())))
            .into(),
        SubmitError::InvalidFilter("ZZ".into()),
    );
    assert_refused(
        &mut h,
        ObdRequest::new(ObdCommand::Pid {
            service: 0x22,
            pid: 0x16,
        })
        .into(),
        SubmitError::PidWithReadByIdService,
    );
    assert!(h.script_done());
}

#[test]
fn submit_before_begin_is_refused() {
    let mut h = Harness::with_default();
    assert_eq!(
        h.submit(rpm()),
        Err(SubmitError::NotIdle(ElmState::Offline))
    );
    assert!(h.written.is_empty());
}
