//! Ports of `simulator/powerstroke/test/engine_test.dart`, plus tests of the
//! request-driven `observe` API the gateway uses.
#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::path::Path;

use powerstroke_sim::{ObservationKind, Scenario, ScenarioEngine, load_dir};

fn scenario_with(faults: &[&str], looping: bool) -> Scenario {
    let faults: Vec<String> = faults.iter().map(|f| format!("  - {f}")).collect();
    let yaml = format!(
        "\
schema: f250.scenario.v1
name: Test
duration_s: 10
loop: {looping}
seed: 3
signals:
  rpm: {{unit: rpm, interval_ms: 100, keyframes: [[0, 700], [10, 1700]]}}
  eot: {{unit: degC, interval_ms: 1000, noise: 2, keyframes: [[0, 90]]}}
faults:
{}
",
        faults.join("\n")
    );
    Scenario::parse("t", &yaml).unwrap()
}

fn engine(faults: &[&str]) -> ScenarioEngine {
    ScenarioEngine::new(scenario_with(faults, true))
}

#[test]
fn polls_each_signal_at_k_times_interval_within_from_to() {
    let obs = engine(&[]).poll(0, 1000);
    let rpm: Vec<u64> = obs
        .iter()
        .filter(|o| o.signal_id == "rpm")
        .map(|o| o.at_ms)
        .collect();
    assert_eq!(rpm, (1..=10).map(|k| k * 100).collect::<Vec<_>>());
    let eot: Vec<u64> = obs
        .iter()
        .filter(|o| o.signal_id == "eot")
        .map(|o| o.at_ms)
        .collect();
    assert_eq!(eot, [1000]);
    assert!(obs.windows(2).all(|w| w[0].at_ms <= w[1].at_ms));
}

#[test]
fn interpolates_linearly_between_keyframes() {
    let obs = engine(&[]).poll(4900, 5000);
    let [rpm] = obs
        .iter()
        .filter(|o| o.signal_id == "rpm")
        .collect::<Vec<_>>()[..]
    else {
        panic!("{obs:?}")
    };
    assert!((rpm.value.unwrap() - 1200.0).abs() < 1e-9);
}

#[test]
fn output_is_independent_of_how_the_window_is_split() {
    let whole = engine(&[]).poll(0, 3000);
    let e = engine(&[]);
    let parts: Vec<_> = [(0, 1234), (1234, 2000), (2000, 3000)]
        .iter()
        .flat_map(|&(a, b)| e.poll(a, b))
        .collect();
    assert_eq!(parts, whole);
}

#[test]
fn noise_is_bounded_and_deterministic() {
    let eot = |e: ScenarioEngine| -> Vec<f64> {
        e.poll(0, 10_000)
            .into_iter()
            .filter(|o| o.signal_id == "eot")
            .map(|o| o.value.unwrap())
            .collect()
    };
    let a = eot(engine(&[]));
    let b = eot(engine(&[]));
    assert_eq!(a, b);
    assert!(a.iter().all(|v| (88.0..=92.0).contains(v)), "{a:?}");
    let mut distinct = a.clone();
    distinct.sort_by(f64::total_cmp);
    distinct.dedup();
    assert!(distinct.len() > 1);
}

#[test]
fn min_max_clamp_noisy_values_to_physical_limits() {
    let s = Scenario::parse(
        "c",
        "\
schema: f250.scenario.v1
name: Clamp
duration_s: 10
signals:
  speed: {unit: km/h, interval_ms: 100, noise: 5, min: 0, keyframes: [[0, 0]]}
",
    )
    .unwrap();
    let values: Vec<f64> = ScenarioEngine::new(s)
        .poll(0, 10_000)
        .iter()
        .map(|o| o.value.unwrap())
        .collect();
    assert!(values.iter().all(|v| *v >= 0.0));
    assert!(values.iter().any(|v| *v > 0.0));
}

#[test]
fn loops_elapsed_time_wraps_onto_the_scenario_clock() {
    let e = engine(&[]);
    assert!((e.scenario_seconds(12_500) - 2.5).abs() < 1e-9);
    let obs = e.poll(12_400, 12_500);
    let [o] = &obs[..] else { panic!("{obs:?}") };
    assert_eq!(o.at_ms, 12_500);
    assert!((o.value.unwrap() - 950.0).abs() < 1e-9);
}

#[test]
fn without_looping_the_clock_holds_at_the_end() {
    let e = ScenarioEngine::new(scenario_with(&[], false));
    assert_eq!(e.scenario_seconds(25_000), 10.0);
}

#[test]
fn no_response_affects_only_the_named_signals_and_only_in_the_window() {
    let e = engine(&["{kind: no_response, signals: [eot], start_s: 2, end_s: 4}"]);
    let obs = e.poll(0, 6000);
    let eot = |at: u64| {
        obs.iter()
            .find(|o| o.signal_id == "eot" && o.at_ms == at)
            .unwrap()
            .kind
    };
    assert_eq!(eot(1000), ObservationKind::Response);
    assert_eq!(eot(2000), ObservationKind::NoResponse);
    assert_eq!(eot(3000), ObservationKind::NoResponse);
    assert_eq!(eot(4000), ObservationKind::Response);
    assert!(
        obs.iter()
            .filter(|o| o.signal_id == "rpm")
            .all(|o| o.kind == ObservationKind::Response)
    );
}

#[test]
fn link_down_affects_every_signal_and_reports_link_state() {
    let e = engine(&["{kind: link_down, start_s: 1, end_s: 2}"]);
    assert!(e.link_up_at(500));
    assert!(!e.link_up_at(1500));
    let during = e.poll(1000, 1900);
    assert!(!during.is_empty());
    assert!(during.iter().all(|o| o.kind == ObservationKind::LinkDown));
}

#[test]
fn negative_response_carries_the_nrc_override_replaces_the_value() {
    let e = engine(&[
        "{kind: negative_response, signals: [eot], nrc: 0x31, start_s: 0, end_s: 10}",
        "{kind: value_override, signals: [rpm], value: 9999, start_s: 0, end_s: 10}",
    ]);
    let obs = e.poll(0, 1000);
    let eot = obs.iter().find(|o| o.signal_id == "eot").unwrap();
    assert_eq!(eot.kind, ObservationKind::NegativeResponse);
    assert_eq!(eot.nrc, Some(0x31));
    assert_eq!(
        obs.iter().find(|o| o.signal_id == "rpm").unwrap().value,
        Some(9999.0)
    );
}

#[test]
fn a_long_suspension_skips_ahead_instead_of_replaying_a_backlog() {
    let obs = engine(&[]).poll(0, 3600 * 1000);
    assert!(obs[0].at_ms > 3600 * 1000 - ScenarioEngine::MAX_WINDOW_MS);
}

// --- Rust-only --------------------------------------------------------------

#[test]
fn fault_precedence_link_down_then_no_response_then_negative_then_invalid_then_override() {
    let all = [
        "{kind: value_override, signals: [eot], value: 1, start_s: 0, end_s: 10}",
        "{kind: invalid_response, signals: [eot], start_s: 0, end_s: 8}",
        "{kind: negative_response, signals: [eot], nrc: 0x22, start_s: 0, end_s: 6}",
        "{kind: no_response, signals: [eot], start_s: 0, end_s: 4}",
        "{kind: link_down, start_s: 0, end_s: 2}",
    ];
    let e = engine(&all);
    let kind_at = |s: u64| e.observe("eot", s * 1000).unwrap();
    assert_eq!(kind_at(1).kind, ObservationKind::LinkDown);
    assert_eq!(kind_at(3).kind, ObservationKind::NoResponse);
    assert_eq!(kind_at(5).kind, ObservationKind::NegativeResponse);
    assert_eq!(kind_at(5).nrc, Some(0x22));
    assert_eq!(kind_at(7).kind, ObservationKind::InvalidResponse);
    assert_eq!(kind_at(9).value, Some(1.0));
    // Latency only for answered requests.
    assert_eq!(kind_at(1).latency_ms, None);
    assert_eq!(kind_at(3).latency_ms, None);
    for s in [5, 7, 9] {
        assert!((40..=80).contains(&kind_at(s).latency_ms.unwrap()));
    }
}

#[test]
fn equal_timestamps_keep_track_order() {
    let obs = engine(&[]).poll(0, 10_000);
    let at_1000: Vec<&str> = obs
        .iter()
        .filter(|o| o.at_ms == 1000)
        .map(|o| o.signal_id.as_str())
        .collect();
    assert_eq!(at_1000, ["rpm", "eot"]);
}

#[test]
fn empty_or_reversed_window_yields_nothing() {
    assert!(engine(&[]).poll(1000, 1000).is_empty());
    assert!(engine(&[]).poll(2000, 1000).is_empty());
}

#[test]
fn observe_on_a_scheduled_poll_time_equals_the_scheduled_observation() {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../simulator/powerstroke/scenarios");
    for scenario in load_dir(dir).unwrap() {
        let id = scenario.id().to_owned();
        let e = ScenarioEngine::new(scenario);
        let mut checked = 0;
        // Two full drive cycles, so loop wrap and every fault window are hit.
        for t in (0..1_200_000).step_by(1000) {
            for o in e.poll(t, t + 1000) {
                assert_eq!(e.observe(&o.signal_id, o.at_ms).as_ref(), Some(&o), "{id}");
                checked += 1;
            }
        }
        assert!(checked > 20_000, "{id}: {checked}");
    }
}

#[test]
fn observe_between_polls_uses_the_floor_k_and_the_request_time() {
    let e = engine(&[]);
    let o = e.observe("eot", 2500).unwrap();
    assert_eq!(o.at_ms, 2500);
    // Same noise index as the poll at 2000 ms; same (flat) keyframe value.
    let scheduled = e.observe("eot", 2000).unwrap();
    assert_eq!(o.value, scheduled.value);
    assert_eq!(o.latency_ms, scheduled.latency_ms);
    // rpm interpolates at the request time, not the poll time.
    let rpm = e.observe("rpm", 2550).unwrap();
    assert!((rpm.value.unwrap() - 955.0).abs() < 1e-9);
}

#[test]
fn observe_unknown_signal_is_none() {
    assert_eq!(engine(&[]).observe("boost", 1000), None);
}
