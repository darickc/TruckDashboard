//! Cross-language conformance: the Rust engine must reproduce the
//! observations the Dart engine wrote to `simulator/powerstroke/test/golden/`
//! (`fvm dart run tool/golden.dart`). `test/golden_test.dart` checks the same
//! files from the Dart side.
#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::fs;
use std::path::{Path, PathBuf};

use powerstroke_sim::{Observation, ScenarioEngine, load_dir};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct Golden {
    scenario: String,
    schema: String,
    run_ms: u64,
    window_ms: u64,
    observations: Vec<GoldenObservation>,
}

#[derive(Debug, Deserialize)]
struct GoldenObservation {
    signal: String,
    at_ms: u64,
    kind: String,
    value: Option<f64>,
    nrc: Option<i64>,
    latency_ms: Option<u32>,
}

fn sim_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../simulator/powerstroke")
}

/// Dart's `List.sort` is not stable (insertion sort up to 32 elements, then
/// dual-pivot quicksort), so the order of observations that share a
/// timestamp is an implementation detail. Compare in (time, signal) order.
fn canonical<T>(items: &mut [T], key: impl Fn(&T) -> (u64, String)) {
    items.sort_by_key(key);
}

#[test]
fn rust_engine_matches_dart_golden_observations() {
    let scenarios = load_dir(sim_dir().join("scenarios")).unwrap();
    assert!(!scenarios.is_empty());

    let golden_dir = sim_dir().join("test/golden");
    let mut golden_ids: Vec<String> = fs::read_dir(&golden_dir)
        .unwrap()
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().is_some_and(|e| e == "json"))
        .map(|p| p.file_stem().unwrap().to_str().unwrap().to_owned())
        .collect();
    golden_ids.sort();
    let scenario_ids: Vec<&str> = scenarios.iter().map(|s| s.id()).collect();
    assert_eq!(
        golden_ids, scenario_ids,
        "every scenario needs a golden file and vice versa; run `fvm dart run tool/golden.dart`"
    );

    for scenario in scenarios {
        let id = scenario.id().to_owned();
        let text = fs::read_to_string(golden_dir.join(format!("{id}.json"))).unwrap();
        let golden: Golden = serde_json::from_str(&text).unwrap();
        assert_eq!(golden.scenario, id);
        assert_eq!(golden.schema, powerstroke_sim::SCENARIO_SCHEMA);

        let engine = ScenarioEngine::new(scenario);
        let mut actual: Vec<Observation> = (0..golden.run_ms)
            .step_by(usize::try_from(golden.window_ms).unwrap())
            .flat_map(|t| engine.poll(t, t + golden.window_ms))
            .collect();
        let mut expected = golden.observations;
        canonical(&mut actual, |o| (o.at_ms, o.signal_id.clone()));
        canonical(&mut expected, |o| (o.at_ms, o.signal.clone()));

        assert_eq!(actual.len(), expected.len(), "{id}: observation count");
        for (i, (a, e)) in actual.iter().zip(&expected).enumerate() {
            let at = format!("{id} observation {i}: rust {a:?} vs dart {e:?}");
            assert_eq!(a.signal_id, e.signal, "{at}");
            assert_eq!(a.at_ms, e.at_ms, "{at}");
            assert_eq!(a.kind.as_str(), e.kind, "{at}");
            assert_eq!(a.nrc, e.nrc, "{at}");
            assert_eq!(a.latency_ms, e.latency_ms, "{at}");
            match (a.value, e.value) {
                (None, None) => {}
                (Some(av), Some(ev)) => assert!((av - ev).abs() <= 1e-9, "{at}"),
                _ => panic!("{at}: value presence differs"),
            }
        }
    }
}
