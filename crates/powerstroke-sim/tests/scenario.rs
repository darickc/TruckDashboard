//! Ports of `simulator/powerstroke/test/scenario_test.dart`, plus Rust-only
//! checks of the API around them.
#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::fs;
use std::path::{Path, PathBuf};

use powerstroke_sim::{FaultKind, Scenario, ScenarioEngine, ScenarioError, load_dir};

fn scenarios_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../simulator/powerstroke/scenarios")
}

fn read(id: &str) -> Result<String, std::io::Error> {
    fs::read_to_string(scenarios_dir().join(format!("{id}.yaml")))
}

fn load(id: &str) -> Scenario {
    Scenario::parse_with(id, &read(id).unwrap(), read).unwrap()
}

const MINIMAL: &str = "\
schema: f250.scenario.v1
name: Minimal
duration_s: 10
signals:
  rpm: {unit: rpm, interval_ms: 100, keyframes: [[0, 700], [10, 1700]]}
";

#[track_caller]
fn rejects(yaml: &str, needle: &str) {
    match Scenario::parse("bad", yaml) {
        Err(e @ ScenarioError::Format { .. }) => {
            assert_eq!(e.scenario(), Some("bad"));
            let ScenarioError::Format { message, .. } = &e else {
                unreachable!()
            };
            assert!(message.contains(needle), "{message:?} lacks {needle:?}");
        }
        other => panic!("expected a format error containing {needle:?}, got {other:?}"),
    }
}

fn with_fault(fault: &str) -> String {
    format!("{MINIMAL}\nfaults:\n  - {fault}\n")
}

// --- group: shipped scenarios -------------------------------------------

#[test]
fn shipped_the_expected_set_is_present() {
    let ids: Vec<String> = load_dir(scenarios_dir())
        .unwrap()
        .iter()
        .map(|s| s.id().to_owned())
        .collect();
    for id in ["drive_cycle", "eot_ect_freeze", "link_loss"] {
        assert!(ids.iter().any(|i| i == id), "{id} missing from {ids:?}");
    }
}

#[test]
fn shipped_each_parses_and_plays_for_a_full_cycle() {
    for s in load_dir(scenarios_dir()).unwrap() {
        let id = s.id().to_owned();
        let end = (s.duration_seconds() * 1000.0) as u64;
        let engine = ScenarioEngine::new(s);
        let count: usize = (0..end)
            .step_by(1000)
            .map(|t| engine.poll(t, t + 1000).len())
            .sum();
        assert!(count > 0, "{id} produced no observations");
    }
}

#[test]
fn shipped_extends_inherits_tracks_and_appends_faults() {
    let freeze = load("eot_ect_freeze");
    let base = load("drive_cycle");
    let mut a: Vec<&str> = freeze.signal_ids().collect();
    let mut b: Vec<&str> = base.signal_ids().collect();
    a.sort_unstable();
    b.sort_unstable();
    assert_eq!(a, b);
    assert_eq!(freeze.duration_seconds(), base.duration_seconds());
    let [fault] = freeze.faults() else {
        panic!("expected one fault, got {:?}", freeze.faults())
    };
    assert_eq!(fault.kind, FaultKind::NoResponse);
    assert_eq!(fault.signals, ["eot", "ect"]);
}

// --- group: parser rejects malformed input --------------------------------

#[test]
fn rejects_wrong_schema() {
    rejects(&MINIMAL.replacen("v1", "v9", 1), "schema");
}

#[test]
fn rejects_non_increasing_keyframes() {
    rejects(
        &MINIMAL.replacen("[10, 1700]", "[0, 1700]", 1),
        "increasing",
    );
}

#[test]
fn rejects_fault_on_an_unknown_signal() {
    rejects(
        &with_fault("{kind: no_response, signals: [eot], start_s: 1, end_s: 2}"),
        "unknown signal",
    );
}

#[test]
fn rejects_unknown_fault_kind() {
    rejects(
        &with_fault("{kind: explode, signals: [rpm], start_s: 1, end_s: 2}"),
        "unknown",
    );
}

#[test]
fn rejects_negative_response_without_an_nrc() {
    rejects(
        &with_fault("{kind: negative_response, signals: [rpm], start_s: 1, end_s: 2}"),
        "nrc",
    );
}

#[test]
fn rejects_extends_without_a_resolver() {
    rejects(&format!("{MINIMAL}extends: other\n"), "resolver");
}

#[test]
fn rejects_extends_cycle() {
    const A: &str = "schema: f250.scenario.v1\nname: A\nextends: b\n";
    const B: &str = "schema: f250.scenario.v1\nname: B\nextends: a\n";
    let err = Scenario::parse_with("a", A, |id| {
        Ok::<_, std::io::Error>(if id == "a" { A } else { B }.to_owned())
    })
    .unwrap_err();
    assert!(matches!(err, ScenarioError::Format { .. }), "{err:?}");
    assert!(err.to_string().contains("cycle"), "{err}");
}

#[test]
fn rejects_invalid_yaml() {
    rejects("signals: [unclosed", "YAML");
}

// --- Rust-only checks -----------------------------------------------------

#[test]
fn rejects_the_remaining_dart_checks() {
    rejects("- just a list\n", "top level must be a mapping");
    rejects("name: X\n", "schema");
    rejects(
        "schema: f250.scenario.v1\nname: X\nduration_s: 10\n",
        "no signals",
    );
    rejects(
        &MINIMAL.replacen("duration_s: 10", "duration_s: 0", 1),
        "duration_s",
    );
    rejects(&MINIMAL.replacen("name: Minimal\n", "", 1), "name");
    rejects(
        &MINIMAL.replacen("interval_ms: 100", "interval_ms: 9.9", 1),
        "interval_ms",
    );
    rejects(&MINIMAL.replacen("unit: rpm, ", "", 1), "unit");
    rejects(
        &MINIMAL.replacen("[[0, 700], [10, 1700]]", "[]", 1),
        "empty",
    );
    rejects(
        &MINIMAL.replacen("[0, 700]", "[0, '700']", 1),
        "[seconds, value]",
    );
    rejects(
        &MINIMAL.replacen("[0, 700]", "[0, 700, 1]", 1),
        "[seconds, value]",
    );
    rejects(
        &MINIMAL.replacen("unit: rpm", "unit: rpm, noise: -1", 1),
        "noise",
    );
    rejects(
        &MINIMAL.replacen("unit: rpm", "unit: rpm, min: 5, max: 5", 1),
        "min",
    );
    rejects(
        &MINIMAL.replacen("signals:", "loop: yes\nsignals:", 1),
        "loop",
    );
    rejects(
        &with_fault("{kind: no_response, signals: [rpm], start_s: 2, end_s: 2}"),
        "end_s",
    );
    rejects(
        &with_fault("{kind: link_down, signals: [rpm], start_s: 1, end_s: 2}"),
        "link_down",
    );
    rejects(
        &with_fault("{kind: no_response, start_s: 1, end_s: 2}"),
        "signals",
    );
    rejects(
        &with_fault("{kind: value_override, signals: [rpm], start_s: 1, end_s: 2}"),
        "value",
    );
    rejects(&with_fault("just a string"), "faults[0]");
    rejects(
        &format!("{MINIMAL}dtcs:\n  - {{code: P0128}}\n"),
        "description",
    );
}

#[test]
fn parses_hex_nrc_and_quoted_percent_units() {
    let yaml = format!(
        "{}\nfaults:\n  - {{kind: negative_response, signals: [load], nrc: 0x31, start_s: 0, end_s: 1}}\n",
        MINIMAL.replace(
            "signals:\n",
            "signals:\n  load: {unit: '%', interval_ms: 500, keyframes: [[0, 18]]}\n"
        )
    );
    let s = Scenario::parse("hex", &yaml).unwrap();
    assert_eq!(s.track("load").unwrap().unit(), "%");
    assert_eq!(s.faults()[0].nrc, Some(0x31));

    let bad = load("bad_responses");
    assert_eq!(bad.faults()[0].nrc, Some(0x31));
    assert_eq!(bad.track("load").unwrap().unit(), "%");
}

#[test]
fn defaults_match_dart() {
    let s = Scenario::parse("m", MINIMAL).unwrap();
    assert!(s.looping());
    assert_eq!(s.seed(), 1);
    assert_eq!(s.description(), "");
    assert!(s.faults().is_empty());
    assert!(s.dtcs().is_empty());
    let t = s.track("rpm").unwrap();
    assert_eq!(t.noise(), 0.0);
    assert_eq!((t.min(), t.max()), (None, None));
}

#[test]
fn child_override_keeps_parent_track_position_and_inherits_settings() {
    let ficm = load("ficm_sag");
    let base = load("drive_cycle");
    let ids: Vec<&str> = ficm.signal_ids().collect();
    assert_eq!(ids, base.signal_ids().collect::<Vec<_>>());
    assert_eq!(ficm.track("ficm_main").unwrap().keyframes().len(), 6);
    assert_eq!(ficm.seed(), 2007);
    assert!(ficm.looping());
    assert_eq!(ficm.name(), "FICM voltage sag");

    let idle = load("warm_idle");
    assert_eq!(idle.duration_seconds(), 120.0);
    assert_eq!(idle.track("baro").unwrap().interval_ms(), 5000);
}

#[test]
fn dtcs_are_inherited_with_default_status() {
    let bad = load("bad_responses");
    assert_eq!(bad.dtcs().len(), 1);
    assert_eq!(bad.dtcs()[0].code, "P0128");
    assert_eq!(bad.dtcs()[0].status, "stored");
}

#[test]
fn loader_failure_names_scenario_and_parent() {
    let err = Scenario::parse_with("child", "schema: f250.scenario.v1\nextends: gone\n", |_| {
        Err::<String, _>("not found")
    })
    .unwrap_err();
    match &err {
        ScenarioError::Resolve {
            scenario, parent, ..
        } => {
            assert_eq!((scenario.as_str(), parent.as_str()), ("child", "gone"));
        }
        other => panic!("{other:?}"),
    }
}

#[test]
fn parent_errors_carry_the_parent_id() {
    let err = Scenario::parse_with("child", "schema: f250.scenario.v1\nextends: p\n", |_| {
        Ok::<_, std::io::Error>("schema: f250.scenario.v1\nname: P\n".to_owned())
    })
    .unwrap_err();
    assert_eq!(err.scenario(), Some("p"), "{err}");
}

#[test]
fn load_dir_reports_missing_directory() {
    let err = load_dir(scenarios_dir().join("does-not-exist")).unwrap_err();
    assert!(matches!(err, ScenarioError::Io { .. }), "{err:?}");
}
