//! The OBDLink driver against a fake ELM327 over TCP that replays the real
//! captures from docs/diagnostics/VERIFICATION_LOG.md. [SIM] — no adapter or
//! truck involved.

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod common;

use std::time::Duration;

use f250_elm::{Addressing, ElmConfig, ObdCommand, ObdRequest};
use tokio::sync::mpsc;
use vehicle_gateway::transport::Outcome;
use vehicle_gateway::transport::obdlink::{DriverEvent, LinkSpec, ObdLink};

use common::{Wire, fake_adapter};

async fn wait_for(
    rx: &mut mpsc::Receiver<DriverEvent>,
    want: impl Fn(&DriverEvent) -> bool,
) -> DriverEvent {
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let ev = rx.recv().await.expect("driver alive");
            if want(&ev) {
                return ev;
            }
        }
    })
    .await
    .expect("event within 5 s")
}

async fn ready_link() -> (ObdLink, mpsc::Receiver<DriverEvent>, Wire) {
    let (addr, wire) = fake_adapter().await;
    let spec = LinkSpec::parse(&format!("tcp:{addr}")).unwrap();
    let (link, mut rx) = ObdLink::spawn(spec.connector(), ElmConfig::default(), None).unwrap();
    link.connect().await;
    wait_for(&mut rx, |e| *e == DriverEvent::Connected).await;
    let ready = wait_for(&mut rx, |e| matches!(e, DriverEvent::Ready { .. })).await;
    assert_eq!(
        ready,
        DriverEvent::Ready {
            adapter_id: Some("ELM327 v1.4b".into())
        }
    );
    (link, rx, wire)
}

#[tokio::test]
async fn two_responders_are_reported_in_arrival_order() {
    let (link, _rx, _) = ready_link().await;
    let out = link
        .request(
            ObdRequest::new(ObdCommand::mode01(0x0C)).with_addressing(Addressing::functional()),
        )
        .await;
    let Outcome::Payload { responders, .. } = out else {
        panic!("got {out:?}")
    };
    assert_eq!(responders[0].can_id, "7E9");
    assert_eq!(responders[0].payload, [0x0A, 0xC4]);
    assert_eq!(responders[1].can_id, "7E8");
    assert_eq!(responders[1].payload, [0x0A, 0xC2]);
}

#[tokio::test]
async fn trans_temp_pinned_to_the_tcm_ignores_the_pcm_refusal() {
    let (link, _rx, _) = ready_link().await;
    let req = ObdRequest::new(ObdCommand::did(0x1674))
        .with_addressing(Addressing::functional())
        .with_expected_responder(0x7E9);
    let out = link.request(req).await;
    let Outcome::Payload { responders, .. } = out else {
        panic!("got {out:?}")
    };
    assert_eq!(responders[0].can_id, "7E9");
    assert_eq!(responders[0].payload, [0x04, 0x13]); // 1043 / 8 = 130.4 °F
}

#[tokio::test]
async fn no_data_is_no_response_and_atrv_reads_volts() {
    let (link, _rx, _) = ready_link().await;
    let out = link
        .request(ObdRequest::new(ObdCommand::did(0x1310)).with_addressing(Addressing::functional()))
        .await;
    assert!(matches!(out, Outcome::NoResponse { .. }), "got {out:?}");
    assert_eq!(link.voltage().await, Some(12.6));
}

#[tokio::test]
async fn write_services_never_reach_the_wire() {
    let (link, _rx, wire) = ready_link().await;
    // Raw lines with write/control/clear services are refused before sending.
    for line in ["2E1674FF", "04", "14FFFFFF", "3101FF00", "1003"] {
        let r = link.raw(line.into()).await;
        assert!(r.refused.is_some(), "{line} should be refused");
    }
    let sent = wire.lock().unwrap().clone();
    for bad in ["2E1674FF", "04", "14FFFFFF", "3101FF00", "1003"] {
        assert!(
            !sent.iter().any(|l| l == bad),
            "{bad} reached the adapter: {sent:?}"
        );
    }
    // A read through raw is allowed and returns the adapter's lines.
    let r = link.raw("010C".into()).await;
    assert_eq!(r.refused, None);
    assert_eq!(r.lines, ["7E904410C0AC4", "7E804410C0AC2"]);
}

#[tokio::test]
async fn adapter_going_away_is_reported() {
    let (link, mut rx, _) = ready_link().await;
    link.disconnect().await;
    let out = link
        .request(
            ObdRequest::new(ObdCommand::mode01(0x0C)).with_addressing(Addressing::functional()),
        )
        .await;
    assert_eq!(out, Outcome::LinkDown);
    // Reconnect works.
    link.connect().await;
    wait_for(&mut rx, |e| matches!(e, DriverEvent::Ready { .. })).await;
}

#[tokio::test]
async fn unreachable_adapter_reports_connect_failure() {
    let spec = LinkSpec::parse("tcp:127.0.0.1:1").unwrap();
    let (link, mut rx) = ObdLink::spawn(spec.connector(), ElmConfig::default(), None).unwrap();
    link.connect().await;
    let ev = wait_for(&mut rx, |e| matches!(e, DriverEvent::ConnectFailed(_))).await;
    assert!(matches!(ev, DriverEvent::ConnectFailed(_)));
}

#[test]
fn link_spec_parsing() {
    assert_eq!(
        LinkSpec::parse("serial:/dev/cu.OBDLinkMX@38400").unwrap(),
        LinkSpec::Serial {
            path: "/dev/cu.OBDLinkMX".into(),
            baud: 38400
        }
    );
    assert_eq!(
        LinkSpec::parse("rfcomm:00:04:3E:85:EA:FC").unwrap(),
        LinkSpec::Rfcomm {
            address: "00:04:3E:85:EA:FC".into(),
            channel: 1
        }
    );
    assert!(LinkSpec::parse("bt:whatever").is_err());
}
