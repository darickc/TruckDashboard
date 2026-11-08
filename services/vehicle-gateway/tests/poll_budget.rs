//! The registry's poll intervals against each transport's throughput budget
//! (ADR-0019). `Scheduler::load` is the same figure the gateway reports in
//! `LinkStatus.detail` when it is over 80 % of the budget. [SIM] — this
//! checks the configuration; the budgets themselves were measured on the
//! truck (docs/diagnostics/VERIFICATION_LOG.md).

#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::path::PathBuf;

use clap::Parser;
use f250_telemetry::registry::Registry;
use vehicle_gateway::config::Config;
use vehicle_gateway::core::Core;
use vehicle_gateway::scheduler::Load;

fn repo(p: &str) -> String {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .join(p)
        .display()
        .to_string()
}

fn config(transport: &[&str], extra: &[&str]) -> Config {
    let mut args = vec![
        "vehicle-gateway".to_string(),
        "--signals".into(),
        repo("shared/signals"),
        "--warnings".into(),
        repo("apps/infotainment/assets/config/warning_rules.json"),
        "--scenario-dir".into(),
        repo("simulator/powerstroke/scenarios"),
    ];
    args.extend(transport.iter().map(|s| s.to_string()));
    args.extend(extra.iter().map(|s| s.to_string()));
    Config::parse_from(args)
}

/// No `--transmit`: neither the adapter nor the interface is ever opened.
const SIM: &[&str] = &["--transport", "sim", "--scenario", "drive_cycle"];
const MXPLUS: &[&str] = &["--transport", "obdlink", "--adapter", "tcp:127.0.0.1:9"];
const CAN: &[&str] = &["--transport", "can", "--can-if", "vcan-test"];

fn load(transport: &[&str], extra: &[&str]) -> Load {
    let (core, _driver, _snaps) = Core::new(config(transport, extra)).unwrap();
    core.load()
}

fn registry() -> Registry {
    Registry::load_dir(repo("shared/signals")).unwrap()
}

/// Requests/s if every polled signal in the registry is enabled.
fn every_signal_rps() -> f64 {
    registry()
        .iter()
        .filter_map(|d| d.poll.as_ref())
        .map(|p| 1000.0 / p.interval_ms as f64)
        .sum()
}

/// Every unverified signal the registry has, for `--enable`.
fn every_disabled_signal() -> String {
    registry()
        .iter()
        .filter(|d| !d.enabled && !d.is_computed() && d.poll.is_some())
        .map(|d| d.id.clone())
        .collect::<Vec<_>>()
        .join(",")
}

fn assert_fits(what: &str, l: Load) {
    assert!(
        !l.oversubscribed(),
        "{what}: asks {:.2} req/s of a {:.1} req/s budget ({:.0} %, limit 80 %)",
        l.demand_rps,
        l.budget_rps,
        100.0 * l.demand_rps / l.budget_rps
    );
}

/// Bench log 2026-11-08: the ESP32-era intervals asked ~54 req/s of a
/// ~16 req/s simulator, so most signals ran on the starvation guard.
#[tokio::test]
async fn the_default_sim_set_fits_the_simulator_budget() {
    let l = load(SIM, &[]);
    assert_eq!(l.budget_rps, 15.0);
    // The simulator polls every signal the registry has (so this can't pass
    // by leaving signals out).
    assert!(
        (l.demand_rps - every_signal_rps()).abs() < 1e-9,
        "sim polls {:.2} req/s, the whole registry asks {:.2}",
        l.demand_rps,
        every_signal_rps()
    );
    assert_fits("simulator, drive_cycle", l);
}

#[tokio::test]
async fn the_truck_default_sets_fit_their_budgets() {
    // What the truck has run since 2026-11-03: the enabled signals plus EOT.
    let l = load(MXPLUS, &["--enable", "eot"]);
    assert_eq!(l.budget_rps, 10.0);
    assert_fits("MX+, --enable eot", l);
    assert_fits("MX+, registry default", load(MXPLUS, &[]));

    let l = load(CAN, &["--enable", "eot"]);
    assert_eq!(l.budget_rps, 16.0);
    assert_fits("CAN, --enable eot", l);
    // The CAN adapter carries every signal the registry has.
    let all = every_disabled_signal();
    let l = load(CAN, &["--enable", &all]);
    assert!((l.demand_rps - every_signal_rps()).abs() < 1e-9);
    assert_fits("CAN, every signal", l);
}

/// The MX+ does not: enabling every unverified signal on it is reported as
/// oversubscribed, and the low priorities stretch (ADR-0019). Kept as a test
/// so a retune that changes this also changes the docs.
#[tokio::test]
async fn every_signal_oversubscribes_the_mx_plus() {
    let all = every_disabled_signal();
    let l = load(MXPLUS, &["--enable", &all]);
    assert!(l.oversubscribed(), "{l:?}");
    assert!(l.demand_rps < l.budget_rps * 1.25, "{l:?}");
}

/// ADR-0020: priority 0 (RPM, MAP) spends the room left under 80 %, and the
/// plan, spare reads included, never goes over it. [SIM]
#[tokio::test]
async fn spare_reads_stay_within_80_percent() {
    let within = |what: &str, l: Load| {
        assert!(
            l.planned_rps() <= 0.8 * l.budget_rps + 1e-9,
            "{what}: plans {:.2} req/s of {:.1} ({l:?})",
            l.planned_rps(),
            l.budget_rps
        );
    };
    // The truck's set over CAN: RPM is the only priority 0 enabled, and it is
    // capped by the 250 ms snapshot period: 2/s registry + 2/s spare.
    let l = load(CAN, &["--enable", "eot"]);
    within("CAN, --enable eot", l);
    assert!((l.spare_rps - 2.0).abs() < 1e-6, "{l:?}");
    // On the MX+ the same set leaves 1.47/s, all of it to RPM.
    let l = load(MXPLUS, &["--enable", "eot"]);
    within("MX+, --enable eot", l);
    assert!((l.spare_rps - (8.0 - l.demand_rps)).abs() < 1e-3, "{l:?}");
    // The simulator's full set is near 80 % already: a little room.
    let l = load(SIM, &[]);
    within("simulator", l);
    assert!(l.spare_rps > 0.0 && l.spare_rps < 0.3, "{l:?}");
    // Oversubscribed: nothing spare.
    let l = load(MXPLUS, &["--enable", &every_disabled_signal()]);
    assert_eq!(l.spare_rps, 0.0, "{l:?}");
}
