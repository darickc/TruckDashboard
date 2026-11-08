//! The whole gateway on the simulator, on tokio's paused clock: the real
//! registry, the `drive_cycle` scenario, the scheduler and the telemetry
//! store, with the simulator's 40–80 ms round trip. Ten virtual minutes run
//! in well under a second. [SIM] — nothing here says how the truck behaves.

#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::path::PathBuf;
use std::time::Duration;

use clap::Parser;
use f250_proto::vehicle::v1 as pb;
use tokio::sync::mpsc;
use tokio::time::Instant;
use vehicle_gateway::config::Config;
use vehicle_gateway::core::Core;

fn repo(p: &str) -> String {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .join(p)
        .display()
        .to_string()
}

fn sim_config() -> Config {
    Config::parse_from([
        "vehicle-gateway".to_string(),
        "--signals".into(),
        repo("shared/signals"),
        "--warnings".into(),
        repo("apps/infotainment/assets/config/warning_rules.json"),
        "--scenario-dir".into(),
        repo("simulator/powerstroke/scenarios"),
        "--scenario".into(),
        "drive_cycle".into(),
    ])
}

fn validity_of(snap: &pb::Snapshot, id: &str) -> pb::Validity {
    snap.samples
        .iter()
        .find(|s| s.signal_id == id)
        .map(|s| pb::Validity::try_from(s.validity).unwrap_or(pb::Validity::Unspecified))
        .unwrap_or(pb::Validity::Unspecified)
}

/// Bench log 2026-11-08: with every simulated signal enabled the poll
/// intervals ask for ~54 requests/s of a ~16/s link, EOT and ECT were each
/// read about every 3 s, and EOT − ECT read STALE in most samples because the
/// two reads were often more than its 2 s skew limit apart. The inputs of a
/// computed signal are now read back to back, and no snapshot is published
/// between them, so the delta is VALID in every snapshot once both inputs
/// have been read — without loosening the skew limit.
#[tokio::test(start_paused = true)]
async fn eot_ect_delta_stays_valid_under_the_default_enabled_set() {
    let (core, driver, mut snaps) = Core::new(sim_config()).unwrap();
    let (_cmd_tx, cmd_rx) = mpsc::channel(4);
    let run = tokio::spawn(core.run(cmd_rx, driver));

    let start = Instant::now();
    let mut first_valid: Option<Duration> = None;
    let mut snapshots = 0u32;
    let mut not_valid: Vec<(Duration, pb::Validity)> = Vec::new();
    // One full pass of the 600 s scenario.
    while start.elapsed() < Duration::from_secs(600) {
        snaps.changed().await.unwrap();
        let snap = snaps.borrow_and_update().clone();
        let at = start.elapsed();
        let v = validity_of(&snap, "eot_ect_delta");
        if first_valid.is_none() {
            if v == pb::Validity::Valid {
                first_valid = Some(at);
            }
            continue;
        }
        snapshots += 1;
        if v != pb::Validity::Valid {
            not_valid.push((at, v));
        }
        // Honesty: never VALID unless both inputs are.
        if v == pb::Validity::Valid {
            assert_eq!(validity_of(&snap, "eot"), pb::Validity::Valid, "at {at:?}");
            assert_eq!(validity_of(&snap, "ect"), pb::Validity::Valid, "at {at:?}");
        }
    }
    run.abort();

    let first = first_valid.expect("EOT − ECT was never VALID");
    assert!(first < Duration::from_secs(5), "first VALID at {first:?}");
    assert!(snapshots > 2000, "only {snapshots} snapshots");
    assert!(
        not_valid.is_empty(),
        "EOT − ECT not VALID in {} of {snapshots} snapshots; first: {:?}",
        not_valid.len(),
        &not_valid[..not_valid.len().min(5)]
    );
}

/// ADR-0019: the registry's intervals fit the simulator's budget, so nothing
/// runs on the starvation guard. Over the whole scenario every signal is
/// read at (close to) its interval, no signal flickers out of VALID once it
/// has been read, and the link never reports oversubscription. The skew and
/// staleness limits are the registry's own, unchanged.
#[tokio::test(start_paused = true)]
async fn every_signal_gets_its_interval_under_the_default_enabled_set() {
    let registry = f250_telemetry::registry::Registry::load_dir(repo("shared/signals")).unwrap();
    let (core, driver, mut snaps) = Core::new(sim_config()).unwrap();
    let (_cmd_tx, cmd_rx) = mpsc::channel(4);
    let run = tokio::spawn(core.run(cmd_rx, driver));

    let start = Instant::now();
    let secs = 600u64;
    let mut seen_valid: Vec<String> = Vec::new();
    let mut not_valid: Vec<(Duration, String, pb::Validity)> = Vec::new();
    let mut last = std::sync::Arc::new(pb::Snapshot::default());
    while start.elapsed() < Duration::from_secs(secs) {
        snaps.changed().await.unwrap();
        let snap = snaps.borrow_and_update().clone();
        let at = start.elapsed();
        assert_eq!(
            snap.link.as_ref().map(|l| l.detail.as_str()),
            Some(""),
            "oversubscribed at {at:?}"
        );
        for s in &snap.samples {
            let v = pb::Validity::try_from(s.validity).unwrap_or(pb::Validity::Unspecified);
            if seen_valid.contains(&s.signal_id) {
                if v != pb::Validity::Valid {
                    not_valid.push((at, s.signal_id.clone(), v));
                }
            } else if v == pb::Validity::Valid {
                seen_valid.push(s.signal_id.clone());
            }
        }
        last = snap;
    }
    run.abort();

    assert!(
        not_valid.is_empty(),
        "{} samples not VALID after their first reading; first: {:?}",
        not_valid.len(),
        &not_valid[..not_valid.len().min(8)]
    );
    let mut polled = 0;
    for d in registry.iter() {
        let Some(p) = &d.poll else { continue };
        polled += 1;
        let s = last
            .samples
            .iter()
            .find(|s| s.signal_id == d.id)
            .unwrap_or_else(|| panic!("{} missing from the snapshot", d.id));
        // The next request is due an interval after the previous answer, so
        // each period is the interval plus the round trip (40–80 ms here)
        // plus any wait behind the request in flight or higher priorities
        // due at the same time (up to ~160 ms seen). Living on the starvation
        // guard, as before ADR-0019, is several intervals.
        let target = (secs * 1000) as f64 / (p.interval_ms + 200) as f64;
        assert!(
            s.successes as f64 >= target,
            "{}: read {} times in {secs} s, wanted {target:.0} (every {} ms)",
            d.id,
            s.successes,
            p.interval_ms
        );
        assert_eq!(s.failures, 0, "{}", d.id);
    }
    assert_eq!(
        polled, 14,
        "the drive_cycle scenario models 14 polled signals"
    );
}
