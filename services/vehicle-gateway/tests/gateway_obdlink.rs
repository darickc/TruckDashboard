//! The whole gateway (registry, scheduler, ELM transport, telemetry) against
//! the fake adapter. [SIM] — no adapter or truck involved.

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod common;

use std::path::PathBuf;
use std::time::Duration;

use clap::Parser;
use f250_proto::vehicle::v1 as pb;
use tokio::sync::mpsc;
use vehicle_gateway::config::Config;
use vehicle_gateway::core::Core;

fn repo(p: &str) -> String {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .join(p)
        .display()
        .to_string()
}

fn config(adapter: &str, extra: &[&str]) -> Config {
    let mut args = vec![
        "vehicle-gateway".to_string(),
        "--transport".into(),
        "obdlink".into(),
        "--adapter".into(),
        format!("tcp:{adapter}"),
        "--signals".into(),
        repo("shared/signals"),
        "--warnings".into(),
        repo("apps/infotainment/assets/config/warning_rules.json"),
        "--voltage-every-s".into(),
        "1".into(),
    ];
    args.extend(extra.iter().map(|s| s.to_string()));
    Config::parse_from(args)
}

#[tokio::test]
async fn decodes_the_verified_trans_temp_reply_through_the_registry() {
    let (addr, wire) = common::fake_adapter().await;
    let (core, driver, mut snaps) = Core::new(config(&addr, &["--transmit"])).unwrap();
    let (_cmd_tx, cmd_rx) = mpsc::channel(8);
    tokio::spawn(core.run(cmd_rx, driver));

    let trans = tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            snaps.changed().await.unwrap();
            let snap = snaps.borrow().clone();
            if let Some(s) = snap.samples.iter().find(|s| s.signal_id == "trans_temp")
                && s.validity == pb::Validity::Valid as i32
            {
                return (s.clone(), snap.link.clone().unwrap());
            }
        }
    })
    .await
    .expect("trans_temp valid within 10 s");
    let (s, link) = trans;
    // 04 13 → 1043 / 8 = 130.375 °F = 54.653 °C (canonical).
    assert!(
        (s.value.unwrap() - 54.652_777).abs() < 1e-3,
        "{:?}",
        s.value
    );
    assert_eq!(s.last_responder, "7E9");
    assert_eq!(link.transport, "obdlink");
    assert!(link.transmit_enabled);
    assert!(!link.simulated);
    assert!(common::connections(&wire) >= 1);
    // Nothing outside the read allow-list was ever sent.
    let sent = wire.lock().unwrap().clone();
    for l in &sent {
        let svc = l.get(..2).unwrap_or("");
        assert!(
            l.starts_with("AT") || ["01", "03", "07", "09", "22"].contains(&svc),
            "unexpected line on the wire: {l}"
        );
    }
}

#[tokio::test]
async fn without_transmit_the_adapter_is_never_opened() {
    let (addr, wire) = common::fake_adapter().await;
    let (core, driver, mut snaps) = Core::new(config(&addr, &[])).unwrap();
    let (_cmd_tx, cmd_rx) = mpsc::channel(8);
    tokio::spawn(core.run(cmd_rx, driver));
    tokio::time::sleep(Duration::from_millis(1500)).await;
    snaps.changed().await.unwrap();
    let link = snaps.borrow().link.clone().unwrap();
    assert_eq!(link.machine_state, "PASSIVE_ONLY");
    assert!(!link.transmit_enabled);
    assert_eq!(
        common::connections(&wire),
        0,
        "PASSIVE_ONLY must not even connect"
    );
    assert!(wire.lock().unwrap().is_empty());
}
