//! The telemetry model's validity, computed-signal, link, calibration and
//! event-log rules. Mirrors apps/infotainment/test/unit/telemetry_store_test.dart
//! and calibration_test.dart, against the real registry (Ford rows enabled
//! explicitly with allow_unverified, as the Flutter tests run the catalog).

mod common;

use std::time::Duration;

use f250_telemetry::state::{EventLog, StoreConfig, StoreError};
use f250_telemetry::warnings::{AlertKind, AlertLevel};
use f250_telemetry::{
    Calibration, LinkState, Outcome, PollResult, SignalState, TelemetryStore, Validity,
};

const MS: Duration = Duration::from_millis(1);

/// A store plus a fake monotonic clock.
struct Harness {
    now: Duration,
    store: TelemetryStore,
}

impl Harness {
    fn with(config: StoreConfig) -> Self {
        let now = Duration::ZERO;
        Self {
            now,
            store: TelemetryStore::new(&common::test_registry(), config, now),
        }
    }

    fn new() -> Self {
        Self::with(StoreConfig {
            watched_signals: vec!["eot".into()],
            ..StoreConfig::default()
        })
    }

    fn respond(&mut self, id: &str, v: f64) {
        self.store
            .apply(&PollResult::new(id, self.now, Outcome::Response(v)));
    }

    fn fail(&mut self, id: &str, outcome: Outcome) {
        self.store.apply(&PollResult::new(id, self.now, outcome));
    }

    fn advance(&mut self, d: Duration) {
        self.now += d;
    }

    fn refresh(&mut self) {
        self.store.refresh(self.now);
    }

    fn tick(&mut self, d: Duration) {
        self.advance(d);
        self.refresh();
    }

    fn s(&self, id: &str) -> &SignalState {
        self.store
            .get(id)
            .unwrap_or_else(|| panic!("no signal {id}"))
    }

    fn stale_after(&self, id: &str) -> Duration {
        self.s(id)
            .def
            .stale_after
            .unwrap_or_else(|| panic!("{id} has no stale_after"))
    }
}

mod validity {
    use super::*;

    #[test]
    fn starts_as_no_data_and_disabled_signals_are_disabled() {
        let mut h = Harness::new();
        h.refresh();
        assert_eq!(h.s("eot").validity, Validity::NoData);
        assert_eq!(h.s("egt").validity, Validity::Disabled);
    }

    #[test]
    fn a_response_is_valid_until_stale_after_passes_without_another() {
        let mut h = Harness::new();
        h.respond("eot", 90.0);
        h.refresh();
        assert_eq!(h.s("eot").validity, Validity::Valid);
        assert_eq!(h.s("eot").value, Some(90.0));
        let limit = h.stale_after("eot");
        h.tick(limit);
        assert_eq!(h.s("eot").validity, Validity::Valid, "exactly at the limit");
        h.tick(MS);
        assert_eq!(h.s("eot").validity, Validity::Stale);
    }

    #[test]
    fn a_stale_signal_exposes_no_current_value_only_last_good_and_age() {
        let mut h = Harness::new();
        h.respond("eot", 90.0);
        h.tick(Duration::from_secs(10));
        let s = h.s("eot");
        assert_eq!(s.value, None);
        assert_eq!(s.last_good_value, Some(90.0));
        assert_eq!(s.age_at(h.now), Some(Duration::from_secs(10)));
    }

    #[test]
    fn timeouts_do_not_change_the_value_it_only_ages() {
        let mut h = Harness::new();
        h.respond("eot", 90.0);
        h.advance(Duration::from_secs(1));
        h.fail("eot", Outcome::NoResponse);
        h.refresh();
        assert_eq!(h.s("eot").validity, Validity::Valid);
        assert_eq!(h.s("eot").value, Some(90.0));
        assert_eq!(h.s("eot").consecutive_failures, 1);
    }

    #[test]
    fn goes_stale_even_if_the_data_source_stops_entirely() {
        let mut h = Harness::new();
        h.respond("eot", 90.0);
        h.refresh();
        for _ in 0..50 {
            h.tick(100 * MS);
        }
        assert_eq!(h.s("eot").validity, Validity::Stale);
    }

    #[test]
    fn negative_response_before_any_data_is_unsupported_with_the_nrc() {
        let mut h = Harness::new();
        h.fail("icp", Outcome::NegativeResponse { nrc: 0x31 });
        h.refresh();
        assert_eq!(h.s("icp").validity, Validity::Unsupported);
        assert_eq!(h.s("icp").last_nrc, Some(0x31));
    }

    #[test]
    fn negative_response_after_good_data_only_ages_the_value() {
        let mut h = Harness::new();
        h.respond("icp", 4000.0);
        h.advance(MS);
        h.fail("icp", Outcome::NegativeResponse { nrc: 0x31 });
        h.refresh();
        assert_eq!(h.s("icp").validity, Validity::Valid);
        h.tick(h.stale_after("icp"));
        assert_eq!(h.s("icp").validity, Validity::Stale);
    }

    #[test]
    fn undecodable_response_before_any_data_is_decode_error() {
        let mut h = Harness::new();
        h.fail("map", Outcome::InvalidResponse);
        h.refresh();
        assert_eq!(h.s("map").validity, Validity::DecodeError);
    }

    #[test]
    fn an_implausible_value_is_never_shown_and_never_becomes_last_good() {
        let mut h = Harness::new();
        h.respond("trans_temp", 55.0);
        h.advance(Duration::from_secs(1));
        h.respond("trans_temp", 400.0);
        h.refresh();
        let s = h.s("trans_temp");
        assert_eq!(s.validity, Validity::OutOfRange);
        assert_eq!(s.value, None);
        assert_eq!(s.last_good_value, Some(55.0));
        assert_eq!(s.last_rejected_value, Some(400.0));
        h.advance(Duration::from_secs(1));
        h.respond("trans_temp", 56.0);
        h.refresh();
        let s = h.s("trans_temp");
        assert_eq!(s.validity, Validity::Valid);
        assert_eq!(s.value, Some(56.0));
    }

    #[test]
    fn latest_implausible_answer_is_out_of_range_regardless_of_age() {
        let mut h = Harness::new();
        h.respond("trans_temp", 55.0);
        h.advance(MS);
        h.respond("trans_temp", f64::NAN);
        h.tick(Duration::from_secs(60));
        assert_eq!(h.s("trans_temp").validity, Validity::OutOfRange);
        // A later timeout makes the latest outcome a non-answer; the reading
        // then reports its age.
        h.fail("trans_temp", Outcome::NoResponse);
        h.refresh();
        assert_eq!(h.s("trans_temp").validity, Validity::Stale);
    }

    #[test]
    fn disabled_signals_ignore_results() {
        let mut h = Harness::new();
        assert!(
            !h.store
                .apply(&PollResult::new("egt", h.now, Outcome::Response(500.0)))
        );
        assert!(
            !h.store
                .apply(&PollResult::new("boost", h.now, Outcome::Response(5.0)))
        );
        assert!(
            !h.store
                .apply(&PollResult::new("nope", h.now, Outcome::Response(5.0)))
        );
        h.refresh();
        assert_eq!(h.s("egt").validity, Validity::Disabled);
        assert_eq!(h.s("egt").last_good_value, None);
    }

    #[test]
    fn the_seed_registry_keeps_ford_rows_disabled() {
        let reg = common::seed_registry();
        let mut store = TelemetryStore::new(&reg, StoreConfig::default(), Duration::ZERO);
        store.apply(&PollResult::new(
            "eot",
            Duration::ZERO,
            Outcome::Response(90.0),
        ));
        store.apply(&PollResult::new(
            "ect",
            Duration::ZERO,
            Outcome::Response(80.0),
        ));
        store.refresh(Duration::ZERO);
        assert_eq!(
            store.get("eot").map(|s| s.validity),
            Some(Validity::Disabled)
        );
        assert_eq!(store.get("ect").map(|s| s.validity), Some(Validity::Valid));
        // A computed signal with a disabled input shows DISABLED, no value.
        let d = store
            .get("eot_ect_delta")
            .unwrap_or_else(|| panic!("delta"));
        assert_eq!(d.validity, Validity::Disabled);
        assert_eq!(d.value, None);
    }

    #[test]
    fn responder_and_latency_are_recorded() {
        let mut h = Harness::new();
        let mut r = PollResult::new("trans_temp", h.now, Outcome::Response(54.6));
        r.responder = Some(0x7E9);
        r.latency_ms = Some(42);
        h.store.apply(&r);
        h.fail("trans_temp", Outcome::NoResponse);
        let s = h.s("trans_temp");
        assert_eq!(s.last_responder, Some(0x7E9));
        assert_eq!(s.last_latency_ms, Some(42));
        assert_eq!((s.successes, s.failures), (1, 1));
    }
}

mod computed {
    use super::*;

    #[test]
    fn eot_ect_delta_is_computed_when_both_inputs_are_current() {
        let mut h = Harness::new();
        h.respond("eot", 100.0);
        h.respond("ect", 90.0);
        h.refresh();
        let d = h.s("eot_ect_delta");
        assert_eq!(d.validity, Validity::Valid);
        assert!(d.value.is_some_and(|v| (v - 10.0).abs() < 1e-9));
    }

    #[test]
    fn hidden_not_even_last_good_when_an_input_is_stale() {
        let mut h = Harness::new();
        h.respond("eot", 100.0);
        h.respond("ect", 90.0);
        h.refresh();
        for _ in 0..10 {
            h.advance(500 * MS);
            h.respond("ect", 90.0); // ECT keeps updating; EOT has frozen
        }
        h.refresh();
        assert_eq!(h.s("eot").validity, Validity::Stale);
        let d = h.s("eot_ect_delta");
        assert_eq!(d.validity, Validity::Stale);
        assert_eq!(d.value, None);
        assert_eq!(d.invalid_inputs, ["eot"]);
    }

    #[test]
    fn inputs_measured_too_far_apart_make_the_result_stale() {
        let mut h = Harness::new();
        h.respond("ect", 90.0);
        h.advance(Duration::from_secs(3)); // > max skew (2 s), < stale_after (4 s)
        h.respond("eot", 100.0);
        h.refresh();
        assert!(h.s("eot").is_valid());
        assert!(h.s("ect").is_valid());
        assert_eq!(h.s("eot_ect_delta").validity, Validity::Stale);
    }

    #[test]
    fn boost_is_map_minus_baro() {
        let mut h = Harness::new();
        h.respond("map", 185.0);
        h.respond("baro", 85.0);
        h.refresh();
        assert!(h.s("boost").value.is_some_and(|v| (v - 100.0).abs() < 1e-9));
    }

    #[test]
    fn a_result_outside_its_own_range_is_out_of_range() {
        let mut h = Harness::new();
        h.respond("eot", 140.0);
        h.respond("ect", 40.0); // delta 100 > 80
        h.refresh();
        let d = h.s("eot_ect_delta");
        assert_eq!(d.validity, Validity::OutOfRange);
        assert_eq!(d.value, None);
    }

    #[test]
    fn worst_input_validity_is_reported() {
        let mut h = Harness::new();
        h.respond("ect", 90.0);
        h.fail("eot", Outcome::NegativeResponse { nrc: 0x31 });
        h.refresh();
        assert_eq!(h.s("eot_ect_delta").validity, Validity::Unsupported);
    }

    #[test]
    fn last_good_time_is_the_older_input() {
        let mut h = Harness::new();
        h.respond("ect", 90.0);
        h.advance(Duration::from_secs(1));
        h.respond("eot", 100.0);
        h.refresh();
        assert_eq!(h.s("eot_ect_delta").last_good_at, Some(Duration::ZERO));
    }
}

mod link {
    use super::*;

    #[test]
    fn connecting_then_up_then_down_after_silence() {
        let mut h = Harness::new();
        h.refresh();
        assert_eq!(h.store.link(), LinkState::Connecting);
        h.respond("eot", 90.0);
        h.refresh();
        assert_eq!(h.store.link(), LinkState::Up);
        h.tick(h.store.link_lost_after() + MS);
        assert_eq!(h.store.link(), LinkState::Down);
        let first = &h.store.alerts()[0];
        assert_eq!(first.kind, AlertKind::LinkLost);
        assert_eq!(first.level, AlertLevel::Critical);
    }

    #[test]
    fn negative_responses_still_prove_the_link_is_alive() {
        let mut h = Harness::new();
        h.respond("eot", 90.0);
        h.refresh();
        for _ in 0..10 {
            h.advance(Duration::from_secs(1));
            h.fail("icp", Outcome::NegativeResponse { nrc: 0x31 });
        }
        h.refresh();
        assert_ne!(h.store.link(), LinkState::Down);
    }

    #[test]
    fn a_watched_signal_going_stale_degrades_the_link_and_raises_an_advisory() {
        let mut h = Harness::new();
        h.respond("eot", 90.0);
        h.refresh();
        for _ in 0..10 {
            h.advance(500 * MS);
            h.respond("rpm", 700.0);
        }
        h.refresh();
        assert_eq!(h.store.link(), LinkState::Degraded);
        let alerts = h.store.alerts();
        assert_eq!(alerts.len(), 1);
        assert_eq!(alerts[0].kind, AlertKind::SignalNotUpdating);
        assert_eq!(alerts[0].signal_id.as_deref(), Some("eot"));
        assert_eq!(alerts[0].level, AlertLevel::Advisory);
    }

    #[test]
    fn a_disabled_watched_signal_does_not_degrade_the_link() {
        // EOT is disabled in the shipped registry (unverified, not opted in).
        let registry = f250_telemetry::Registry::load_dir(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../shared/signals"
        ))
        .expect("registry");
        let mut store = TelemetryStore::new(
            &registry,
            StoreConfig {
                watched_signals: vec!["eot".into()],
                ..StoreConfig::default()
            },
            Duration::ZERO,
        );
        store.apply(&PollResult::new(
            "rpm",
            Duration::ZERO,
            Outcome::Response(700.0),
        ));
        store.refresh(Duration::ZERO);
        assert_eq!(store.link(), LinkState::Up);
        assert!(
            store.alerts().is_empty(),
            "no 'EOT not updating' for a PID never polled"
        );
    }

    #[test]
    fn source_reported_link_loss_wins_immediately() {
        let mut h = Harness::new();
        h.respond("eot", 90.0);
        h.store.set_source_link_down(true);
        h.refresh();
        assert_eq!(h.store.link(), LinkState::Down);
    }

    #[test]
    fn never_answered_connecting_during_the_grace_period_then_down() {
        let mut h = Harness::new();
        h.tick(Duration::from_secs(1));
        assert_eq!(h.store.link(), LinkState::Connecting);
        h.tick(h.store.link_lost_after());
        assert_eq!(h.store.link(), LinkState::Down);
    }

    #[test]
    fn link_down_outcomes_do_not_count_as_answers() {
        let mut h = Harness::new();
        h.respond("eot", 90.0);
        h.refresh();
        for _ in 0..5 {
            h.advance(Duration::from_secs(1));
            h.fail("eot", Outcome::LinkDown);
            h.fail("ect", Outcome::NoResponse);
        }
        h.refresh();
        assert_eq!(h.store.link(), LinkState::Down);
    }

    #[test]
    fn requests_per_second_counts_the_last_ten_seconds() {
        let mut h = Harness::new();
        for _ in 0..20 {
            h.respond("rpm", 700.0);
            h.advance(500 * MS);
        }
        h.fail("rpm", Outcome::LinkDown); // not a request
        assert!((h.store.requests_per_second(h.now) - 2.0).abs() < 0.11);
        h.advance(Duration::from_secs(30));
        assert_eq!(h.store.requests_per_second(h.now), 0.0);
    }
}

mod calibration {
    use super::*;

    fn speed_harness(scale: f64) -> Harness {
        let mut h = Harness::with(StoreConfig::default());
        let c = Calibration::new(scale, 0.0, None).unwrap_or_else(|e| panic!("{e}"));
        h.store
            .set_calibration("speed", c, h.now)
            .unwrap_or_else(|e| panic!("{e}"));
        h
    }

    #[test]
    fn the_seed_speed_calibration_is_identity() {
        let h = Harness::new();
        let c = h.store.calibration_of("speed");
        assert!(c.is_identity());
        assert!(c.note().is_some_and(|n| n.contains("CALIBRATION.md")));
    }

    #[test]
    fn the_scale_is_applied_to_every_reading_and_the_raw_value_is_kept() {
        let mut h = speed_harness(1.05);
        h.respond("speed", 100.0);
        h.refresh();
        assert!(h.s("speed").value.is_some_and(|v| (v - 105.0).abs() < 1e-9));
        assert_eq!(h.s("speed").last_good_raw, Some(100.0));
    }

    #[test]
    fn uncalibrated_signals_are_untouched() {
        let mut h = speed_harness(1.05);
        h.respond("rpm", 700.0);
        h.refresh();
        assert_eq!(h.s("rpm").value, Some(700.0));
    }

    #[test]
    fn range_checks_apply_to_the_calibrated_value() {
        let mut h = speed_harness(1.05);
        h.respond("speed", 250.0); // ×1.05 = 262.5 > 255
        h.refresh();
        assert_eq!(h.s("speed").validity, Validity::OutOfRange);
    }

    #[test]
    fn changing_the_calibration_rescales_the_current_reading_at_once() {
        let mut h = speed_harness(1.05);
        h.respond("speed", 100.0);
        h.refresh();
        let c = Calibration::new(1.10, 0.0, None).unwrap_or_else(|e| panic!("{e}"));
        h.store
            .set_calibration("speed", c, h.now)
            .unwrap_or_else(|e| panic!("{e}"));
        assert!(h.s("speed").value.is_some_and(|v| (v - 110.0).abs() < 1e-9));
        let newest = h
            .store
            .events()
            .newest_first()
            .next()
            .map(|e| e.message.clone());
        assert!(newest.is_some_and(|m| m.contains("×1.1000")));
    }

    #[test]
    fn computed_and_unknown_signals_cannot_be_calibrated() {
        let mut h = Harness::new();
        let c = Calibration::new(1.1, 0.0, None).unwrap_or_else(|e| panic!("{e}"));
        assert_eq!(
            h.store.set_calibration("boost", c.clone(), h.now),
            Err(StoreError::ComputedNotCalibrated("boost".into()))
        );
        assert_eq!(
            h.store.set_calibration("spd", c, h.now),
            Err(StoreError::UnknownSignal("spd".into()))
        );
    }

    #[test]
    fn offset_is_applied_after_scale() {
        let mut h = Harness::new();
        let c = Calibration::new(2.0, -1.0, None).unwrap_or_else(|e| panic!("{e}"));
        h.store
            .set_calibration("speed", c, h.now)
            .unwrap_or_else(|e| panic!("{e}"));
        h.respond("speed", 10.0);
        h.refresh();
        assert!(h.s("speed").value.is_some_and(|v| (v - 19.0).abs() < 1e-9));
    }

    #[test]
    fn calibration_feeds_computed_signals() {
        // Calibration happens before computed signals: boost uses the
        // calibrated MAP.
        let mut h = Harness::new();
        let c = Calibration::new(1.0, 10.0, None).unwrap_or_else(|e| panic!("{e}"));
        h.store
            .set_calibration("map", c, h.now)
            .unwrap_or_else(|e| panic!("{e}"));
        h.respond("map", 185.0);
        h.respond("baro", 85.0);
        h.refresh();
        assert!(h.s("boost").value.is_some_and(|v| (v - 110.0).abs() < 1e-9));
    }
}

#[test]
fn reset_clears_every_reading_counter_alert_and_event() {
    let mut h = Harness::new();
    h.respond("eot", 90.0);
    h.tick(Duration::from_secs(10));
    assert!(!h.store.events().is_empty());
    h.store.reset(h.now);
    assert_eq!(h.s("eot").last_good_value, None);
    assert_eq!(h.s("eot").successes, 0);
    assert!(h.store.alerts().is_empty());
    assert_eq!(h.store.events().len(), 0);
    assert_eq!(h.store.link(), LinkState::Connecting);
}

#[test]
fn event_log_is_bounded() {
    let mut h = Harness::new();
    for _ in 0..400 {
        h.respond("eot", 90.0);
        h.refresh(); // → valid
        h.tick(Duration::from_secs(5)); // → stale
    }
    assert_eq!(h.store.events().len(), EventLog::DEFAULT_CAPACITY);
    assert!(h.store.events().dropped() > 0);
}

#[test]
fn validity_transitions_are_logged_except_startup() {
    let mut h = Harness::new();
    h.respond("eot", 90.0);
    h.refresh();
    assert!(
        !h.store
            .events()
            .newest_first()
            .any(|e| e.message.starts_with("EOT:")),
        "NO_DATA → VALID is start-up noise"
    );
    h.tick(Duration::from_secs(5));
    assert!(
        h.store
            .events()
            .newest_first()
            .any(|e| e.message == "EOT: VALID → STALE")
    );
}

#[test]
fn time_going_backwards_does_not_panic() {
    let mut h = Harness::new();
    h.advance(Duration::from_secs(10));
    h.respond("eot", 90.0);
    h.store.refresh(Duration::from_secs(1));
    assert_eq!(h.s("eot").validity, Validity::Valid);
    assert_eq!(h.s("eot").age_at(Duration::ZERO), Some(Duration::ZERO));
}
