//! Warning rules inside the telemetry model. Mirrors
//! apps/infotainment/test/unit/warnings_test.dart. The thresholds below are
//! test data, not limits for the truck.

mod common;

use std::time::Duration;

use f250_telemetry::state::StoreConfig;
use f250_telemetry::warnings::{AlertKind, AlertLevel, Direction, WarningConfig};
use f250_telemetry::{Outcome, PollResult, TelemetryStore};

const RULES: &str = r#"{
  "rules": [
    {
      "id": "ect_high", "signal": "ect", "direction": "above",
      "advisory": {"trigger": 104, "clear": 101},
      "critical": {"trigger": 110, "clear": 107},
      "min_duration_ms": 5000
    },
    {
      "id": "ficm_low", "signal": "ficm_main", "direction": "below",
      "advisory": {"trigger": 46, "clear": 47},
      "when": {"signal": "rpm", "direction": "above", "value": 400}
    }
  ]
}"#;

struct Harness {
    now: Duration,
    store: TelemetryStore,
}

const STEP: Duration = Duration::from_millis(500);

impl Harness {
    fn new() -> Self {
        let cfg = WarningConfig::from_json(RULES).unwrap_or_else(|e| panic!("{e}"));
        let registry = common::test_registry();
        cfg.check_signals(&registry)
            .unwrap_or_else(|e| panic!("{e}"));
        let store = TelemetryStore::new(
            &registry,
            StoreConfig {
                rules: cfg.rules,
                ..StoreConfig::default()
            },
            Duration::ZERO,
        );
        Self {
            now: Duration::ZERO,
            store,
        }
    }

    fn set(&mut self, id: &str, v: f64) {
        self.store
            .apply(&PollResult::new(id, self.now, Outcome::Response(v)));
    }

    /// Feeds `v` every 500 ms for `d`, refreshing as it goes.
    fn hold(&mut self, id: &str, v: f64, d: Duration) {
        let mut t = Duration::ZERO;
        while t < d {
            self.set(id, v);
            self.store.refresh(self.now);
            self.now += STEP;
            t += STEP;
        }
        self.set(id, v);
        self.store.refresh(self.now);
    }

    fn level(&self, rule: &str) -> AlertLevel {
        self.store.warnings().level_of(rule)
    }
}

fn secs(s: u64) -> Duration {
    Duration::from_secs(s)
}

#[test]
fn needs_the_minimum_duration_before_raising() {
    let mut h = Harness::new();
    h.hold("ect", 105.0, secs(4));
    assert_eq!(h.level("ect_high"), AlertLevel::None);
    h.hold("ect", 105.0, secs(2));
    assert_eq!(h.level("ect_high"), AlertLevel::Advisory);
}

#[test]
fn a_brief_spike_does_not_raise() {
    let mut h = Harness::new();
    h.hold("ect", 105.0, secs(3));
    h.hold("ect", 95.0, secs(1));
    h.hold("ect", 105.0, secs(3));
    assert_eq!(h.level("ect_high"), AlertLevel::None);
}

#[test]
fn hysteresis_holds_between_clear_and_trigger_and_drops_below_clear() {
    let mut h = Harness::new();
    h.hold("ect", 105.0, secs(6));
    assert_eq!(h.level("ect_high"), AlertLevel::Advisory);
    h.hold("ect", 102.0, secs(2)); // below trigger, above clear
    assert_eq!(h.level("ect_high"), AlertLevel::Advisory);
    h.hold("ect", 100.0, secs(1)); // below clear
    assert_eq!(h.level("ect_high"), AlertLevel::None);
}

#[test]
fn escalates_to_critical_and_steps_back_down_through_advisory() {
    let mut h = Harness::new();
    h.hold("ect", 111.0, secs(6));
    assert_eq!(h.level("ect_high"), AlertLevel::Critical);
    h.hold("ect", 108.0, secs(1)); // above critical clear
    assert_eq!(h.level("ect_high"), AlertLevel::Critical);
    h.hold("ect", 105.0, secs(1)); // below critical clear, above advisory trigger
    assert_eq!(h.level("ect_high"), AlertLevel::Advisory);
}

#[test]
fn never_fires_on_a_stale_signal_and_a_stale_signal_clears_it() {
    let mut h = Harness::new();
    h.hold("ect", 111.0, secs(6));
    assert_eq!(h.level("ect_high"), AlertLevel::Critical);
    h.now += secs(10); // ECT stops updating
    h.store.refresh(h.now);
    assert!(h.store.get("ect").is_some_and(|s| !s.is_valid()));
    assert_eq!(h.level("ect_high"), AlertLevel::None);
}

#[test]
fn never_fires_on_an_out_of_range_reading() {
    let mut h = Harness::new();
    h.hold("ect", 105.0, secs(6));
    assert_eq!(h.level("ect_high"), AlertLevel::Advisory);
    h.hold("ect", 500.0, secs(6)); // implausible: OUT_OF_RANGE, not "hotter"
    assert_eq!(h.level("ect_high"), AlertLevel::None);
}

#[test]
fn below_direction_rules_with_a_gate() {
    let mut h = Harness::new();
    h.hold("ficm_main", 44.0, secs(1));
    assert_eq!(
        h.level("ficm_low"),
        AlertLevel::None,
        "engine not running (no rpm)"
    );
    for _ in 0..3 {
        h.set("rpm", 700.0);
        h.set("ficm_main", 44.0);
        h.store.refresh(h.now);
        h.now += STEP;
    }
    assert_eq!(h.level("ficm_low"), AlertLevel::Advisory);
}

#[test]
fn a_closed_gate_clears_the_alert() {
    let mut h = Harness::new();
    h.set("rpm", 700.0);
    h.hold("ficm_main", 44.0, secs(1));
    assert_eq!(h.level("ficm_low"), AlertLevel::Advisory);
    h.set("rpm", 0.0);
    h.hold("ficm_main", 44.0, secs(1));
    assert_eq!(h.level("ficm_low"), AlertLevel::None);
}

#[test]
fn threshold_alerts_are_reported_with_their_rule_and_level() {
    let mut h = Harness::new();
    h.hold("ect", 111.0, secs(6));
    let a = h
        .store
        .alerts()
        .iter()
        .find(|a| a.kind == AlertKind::Threshold)
        .unwrap_or_else(|| panic!("no threshold alert"));
    assert_eq!(a.rule_id.as_deref(), Some("ect_high"));
    assert_eq!(a.level, AlertLevel::Critical);
    assert_eq!(a.threshold, Some(110.0));
    assert_eq!(a.direction, Some(Direction::Above));
    assert!(
        h.store
            .events()
            .newest_first()
            .any(|e| e.message == "Warning ect_high: none → critical")
    );
}

#[test]
fn alerts_rank_critical_first_then_oldest() {
    let mut h = Harness::new();
    // FICM low (advisory) is raised first, then ECT goes critical while
    // every signal keeps updating.
    for _ in 0..14 {
        h.set("rpm", 700.0);
        h.set("ficm_main", 44.0);
        h.set("ect", 111.0);
        h.store.refresh(h.now);
        h.now += STEP;
    }
    let ranked: Vec<_> = h
        .store
        .alerts()
        .iter()
        .map(|a| (a.level, a.rule_id.as_deref()))
        .collect();
    assert_eq!(
        ranked,
        [
            (AlertLevel::Critical, Some("ect_high")),
            (AlertLevel::Advisory, Some("ficm_low")),
        ]
    );
}
