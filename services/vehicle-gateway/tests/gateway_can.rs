//! The direct-CAN transport (ADR-0012) against an in-memory bus replaying
//! this truck's captured replies. [SIM]: no interface, adapter or truck.

#![allow(clippy::unwrap_used, clippy::expect_used)]

#[path = "common/fake_can.rs"]
mod fake_can;

use std::path::PathBuf;
use std::sync::atomic::Ordering;
use std::time::Duration;

use clap::Parser;
use f250_elm::request::{Addressing, ObdCommand, ObdRequest, ServiceAllowList};
use f250_proto::vehicle::v1 as pb;
use fake_can::{FakeBus, r};
use tokio::sync::mpsc;
use vehicle_gateway::config::Config;
use vehicle_gateway::core::Core;
use vehicle_gateway::transport::Outcome;
use vehicle_gateway::transport::can::{BusEvent, CAN_ERR_BUSOFF, CanLink, CanTiming};
use vehicle_gateway::transport::obdlink::DriverEvent;

const WINDOW: Duration = Duration::from_millis(50);

fn link(bus: &FakeBus) -> (CanLink, mpsc::Receiver<DriverEvent>) {
    CanLink::spawn(
        "vcan-test".into(),
        bus.opener(),
        ServiceAllowList::read_only_default(),
        CanTiming { window: WINDOW },
        None,
    )
}

async fn ready(events: &mut mpsc::Receiver<DriverEvent>) {
    loop {
        match tokio::time::timeout(Duration::from_secs(2), events.recv()).await {
            Ok(Some(DriverEvent::Ready { .. })) => return,
            Ok(Some(_)) => {}
            other => panic!("no Ready: {other:?}"),
        }
    }
}

fn eot() -> ObdRequest {
    ObdRequest::new(ObdCommand::did(0x1310))
}

#[tokio::test]
async fn nothing_is_opened_or_sent_before_connect() {
    let bus = FakeBus::truck();
    let (link, _ev) = link(&bus);
    assert_eq!(link.request(eot()).await, Outcome::LinkDown);
    assert_eq!(bus.opens.load(Ordering::SeqCst), 0);
    assert!(bus.sent().is_empty());
}

/// The 2026-11-03 window that the MX+ sometimes cut short: the TCM's refusal
/// arrives first. Unpinned, the gateway waits its own window and still gets
/// the PCM's value.
#[tokio::test]
async fn eot_unpinned_gets_the_pcm_value_after_the_tcm_refusal() {
    let bus = FakeBus::truck();
    let (link, mut ev) = link(&bus);
    link.connect().await;
    ready(&mut ev).await;
    match link.request(eot()).await {
        Outcome::Payload {
            responders,
            latency_ms,
        } => {
            assert_eq!(responders.len(), 1);
            assert_eq!(responders[0].can_id, "7E8");
            assert_eq!(responders[0].payload, [0x26, 0x91]);
            assert!(latency_ms >= 50, "waited the window: {latency_ms} ms");
        }
        o => panic!("{o:?}"),
    }
    let sent = bus.sent();
    assert_eq!(sent.len(), 1);
    assert_eq!(sent[0].id, 0x7DF);
    assert_eq!(sent[0].data, [0x03, 0x22, 0x13, 0x10, 0, 0, 0, 0]);
}

#[tokio::test]
async fn eot_pinned_returns_as_soon_as_the_pcm_answers() {
    let bus = FakeBus::truck();
    let (link, mut ev) = link(&bus);
    link.connect().await;
    ready(&mut ev).await;
    match link.request(eot().with_expected_responder(0x7E8)).await {
        Outcome::Payload {
            responders,
            latency_ms,
        } => {
            assert_eq!(responders[0].can_id, "7E8");
            assert!(
                latency_ms < 50,
                "no need to wait the window: {latency_ms} ms"
            );
        }
        o => panic!("{o:?}"),
    }
}

#[tokio::test]
async fn pinned_owner_silent_is_no_response() {
    let bus = FakeBus::truck();
    bus.on(
        "7DF 0322131000000000",
        vec![r(18, 0x7E9, "037F221200000000")],
    );
    let (link, mut ev) = link(&bus);
    link.connect().await;
    ready(&mut ev).await;
    let out = link.request(eot().with_expected_responder(0x7E8)).await;
    assert!(matches!(out, Outcome::NoResponse { .. }), "{out:?}");
}

#[tokio::test]
async fn both_modules_answer_rpm() {
    let bus = FakeBus::truck();
    let (link, mut ev) = link(&bus);
    link.connect().await;
    ready(&mut ev).await;
    match link
        .request(ObdRequest::new(ObdCommand::mode01(0x0C)))
        .await
    {
        Outcome::Payload { responders, .. } => {
            let ids: Vec<_> = responders.iter().map(|r| r.can_id.as_str()).collect();
            assert_eq!(ids, ["7E9", "7E8"]);
        }
        o => panic!("{o:?}"),
    }
}

#[tokio::test]
async fn physical_request_goes_out_on_its_header() {
    let bus = FakeBus::truck();
    bus.on(
        "7E1 02010C0000000000",
        vec![r(10, 0x7E9, "04410C0AC4000000")],
    );
    let (link, mut ev) = link(&bus);
    link.connect().await;
    ready(&mut ev).await;
    let req =
        ObdRequest::new(ObdCommand::mode01(0x0C)).with_addressing(Addressing::header("7E1", None));
    assert!(matches!(link.request(req).await, Outcome::Payload { .. }));
    assert_eq!(bus.sent()[0].id, 0x7E1);
}

#[tokio::test]
async fn raw_lists_every_frame_and_refuses_what_it_must() {
    let bus = FakeBus::truck();
    let (link, mut ev) = link(&bus);
    link.connect().await;
    ready(&mut ev).await;

    let out = link.raw("221310".into()).await;
    assert_eq!(out.refused, None);
    assert_eq!(out.lines[0], "TX 7DF 03 22 13 10 00 00 00 00");
    assert!(
        out.lines[1].ends_with("7E9 03 7F 22 12 00 00 00 00"),
        "{:?}",
        out.lines
    );
    assert!(
        out.lines[2].ends_with("7E8 05 62 13 10 26 91 00 00"),
        "{:?}",
        out.lines
    );

    for bad in ["ATSH7E1", "04", "7E0 2E131000", "7E8 010C", "726 221310"] {
        let out = link.raw(bad.into()).await;
        assert!(out.refused.is_some(), "{bad} must be refused");
    }
    assert_eq!(bus.sent().len(), 1, "refused lines never reach the bus");
}

#[tokio::test]
async fn bus_off_drops_the_link() {
    let bus = FakeBus::truck();
    let (link, mut ev) = link(&bus);
    link.connect().await;
    ready(&mut ev).await;
    bus.inject(Ok(BusEvent::Error {
        class: CAN_ERR_BUSOFF,
        data: vec![0; 8],
    }));
    let got = tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            if let Some(DriverEvent::Disconnected(why)) = ev.recv().await {
                return why;
            }
        }
    })
    .await
    .expect("Disconnected after bus-off");
    assert!(got.contains("bus-off"));
    assert_eq!(link.request(eot()).await, Outcome::LinkDown);
}

// ---- the whole gateway ------------------------------------------------------

fn repo(p: &str) -> String {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .join(p)
        .display()
        .to_string()
}

fn config(extra: &[&str]) -> Config {
    let mut args = vec![
        "vehicle-gateway".to_string(),
        "--transport".into(),
        "can".into(),
        "--can-if".into(),
        "vcan-test".into(),
        "--signals".into(),
        repo("shared/signals"),
        "--warnings".into(),
        repo("apps/infotainment/assets/config/warning_rules.json"),
    ];
    args.extend(extra.iter().map(|s| s.to_string()));
    Config::parse_from(args)
}

#[tokio::test]
async fn without_transmit_the_interface_is_never_opened() {
    let bus = FakeBus::truck();
    let (core, driver, mut snaps) = Core::with_can_opener(config(&[]), Some(bus.opener())).unwrap();
    let (_cmd_tx, cmd_rx) = mpsc::channel(8);
    tokio::spawn(core.run(cmd_rx, driver));
    tokio::time::sleep(Duration::from_millis(1200)).await;
    snaps.changed().await.unwrap();
    let link = snaps.borrow().link.clone().unwrap();
    assert_eq!(link.machine_state, "PASSIVE_ONLY");
    assert_eq!(link.transport, "can:vcan-test");
    assert_eq!(
        bus.opens.load(Ordering::SeqCst),
        0,
        "PASSIVE_ONLY must not open"
    );
    assert!(bus.sent().is_empty());
}

/// EOT enabled, the truck's replies, the MX+'s dropout pattern included
/// (the TCM's refusal arrives first every time): EOT and trans_temp decode
/// and stay ACTIVE, and only read-only single frames reach the bus.
#[tokio::test]
async fn polls_eot_and_trans_temp_through_the_registry() {
    let bus = FakeBus::truck();
    let (core, driver, mut snaps) = Core::with_can_opener(
        config(&["--transmit", "--enable", "eot"]),
        Some(bus.opener()),
    )
    .unwrap();
    let (_cmd_tx, cmd_rx) = mpsc::channel(8);
    tokio::spawn(core.run(cmd_rx, driver));

    let (eot, trans) = tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            snaps.changed().await.unwrap();
            let snap = snaps.borrow().clone();
            let find = |id: &str| {
                snap.samples
                    .iter()
                    .find(|s| s.signal_id == id && s.validity == pb::Validity::Valid as i32)
                    .cloned()
            };
            if let (Some(e), Some(t)) = (find("eot"), find("trans_temp")) {
                return (e, t);
            }
        }
    })
    .await
    .expect("eot and trans_temp valid within 10 s");
    // 26 91 → 9873 / 100 − 40 = 58.73 °C.
    assert!((eot.value.unwrap() - 58.73).abs() < 1e-6, "{:?}", eot.value);
    assert_eq!(eot.last_responder, "7E8");
    // 04 13 → 130.375 °F = 54.653 °C.
    assert!((trans.value.unwrap() - 54.652_777).abs() < 1e-3);
    assert_eq!(trans.last_responder, "7E9");

    // Let it poll for a while, then check what reached the bus.
    tokio::time::sleep(Duration::from_millis(1500)).await;
    let sent = bus.sent();
    assert!(sent.len() > 10, "polled: {}", sent.len());
    for f in &sent {
        assert!(
            f.id == 0x7DF || (0x7E0..=0x7E7).contains(&f.id),
            "id {:03X}",
            f.id
        );
        assert_eq!(f.data.len(), 8);
        let len = usize::from(f.data[0]);
        assert!((1..=7).contains(&len), "single frame: {:02X?}", f.data);
        assert!(
            [0x01, 0x03, 0x07, 0x09, 0x22].contains(&f.data[1]),
            "service {:02X} outside the read-only list",
            f.data[1]
        );
    }
    let snap = snaps.borrow().clone();
    let link = snap.link.clone().unwrap();
    assert_eq!(link.machine_state, "POLLING");
    assert!(link.transmit_enabled);
    let eot_state = snap.samples.iter().find(|s| s.signal_id == "eot").unwrap();
    assert_eq!(eot_state.validity, pb::Validity::Valid as i32);
}
