//! Simulated transport: answers requests from a Power Stroke scenario
//! (crates/powerstroke-sim), the same scenarios the Flutter app's in-app
//! simulator plays. Nothing is transmitted anywhere.

use powerstroke_sim::{ObservationKind, ScenarioEngine};

use super::Outcome;

pub struct SimulatedTransport {
    engine: ScenarioEngine,
    /// Run-time offset: start part-way into the scenario.
    start_ms: u64,
}

impl SimulatedTransport {
    pub fn new(engine: ScenarioEngine, start_ms: u64) -> Self {
        SimulatedTransport { engine, start_ms }
    }

    pub fn scenario_id(&self) -> &str {
        self.engine.scenario().id()
    }

    pub fn scenario_name(&self) -> &str {
        self.engine.scenario().name()
    }

    /// Scenario clock for a gateway uptime.
    pub fn scenario_seconds(&self, uptime_ms: u64) -> f64 {
        self.engine.scenario_seconds(self.start_ms + uptime_ms)
    }

    pub fn link_up(&self, uptime_ms: u64) -> bool {
        self.engine.link_up_at(self.start_ms + uptime_ms)
    }

    pub fn knows(&self, signal_id: &str) -> bool {
        self.engine.scenario().track(signal_id).is_some()
    }

    /// What a request for `signal_id` at gateway uptime `uptime_ms` returns.
    /// Signals the scenario doesn't model never answer.
    pub fn request(&self, signal_id: &str, uptime_ms: u64) -> Outcome {
        let Some(obs) = self.engine.observe(signal_id, self.start_ms + uptime_ms) else {
            return Outcome::NoResponse { latency_ms: 0 };
        };
        let latency_ms = obs.latency_ms.unwrap_or(0);
        match obs.kind {
            ObservationKind::Response => match obs.value {
                Some(value) => Outcome::Value { value, latency_ms },
                None => Outcome::Invalid {
                    detail: "simulated response without a value".into(),
                    latency_ms,
                },
            },
            ObservationKind::NoResponse => Outcome::NoResponse { latency_ms },
            ObservationKind::NegativeResponse => Outcome::Negative {
                nrc: obs.nrc.and_then(|n| u8::try_from(n).ok()).unwrap_or(0x10),
                latency_ms,
            },
            ObservationKind::InvalidResponse => Outcome::Invalid {
                detail: "simulated undecodable response".into(),
                latency_ms,
            },
            ObservationKind::LinkDown => Outcome::LinkDown,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use powerstroke_sim::Scenario;

    fn transport(id: &str, start_ms: u64) -> SimulatedTransport {
        let dir = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../simulator/powerstroke/scenarios"
        );
        #[allow(clippy::unwrap_used)]
        let s = Scenario::load(dir, id).unwrap();
        SimulatedTransport::new(ScenarioEngine::new(s), start_ms)
    }

    #[test]
    fn healthy_scenario_answers_with_values() {
        let t = transport("drive_cycle", 0);
        assert!(matches!(t.request("rpm", 1000), Outcome::Value { .. }));
        assert!(matches!(
            t.request("not_a_signal", 1000),
            Outcome::NoResponse { .. }
        ));
    }

    #[test]
    fn freeze_scenario_stops_answering_eot_but_not_rpm() {
        let t = transport("eot_ect_freeze", 0);
        assert!(matches!(
            t.request("eot", 130_000),
            Outcome::NoResponse { .. }
        ));
        assert!(matches!(t.request("rpm", 130_000), Outcome::Value { .. }));
        assert!(matches!(t.request("eot", 270_000), Outcome::Value { .. }));
    }

    #[test]
    fn start_offset_shifts_the_scenario_clock() {
        let t = transport("link_loss", 89_000);
        assert!(t.link_up(0));
        assert!(!t.link_up(2_000), "link drops at 90 s of scenario time");
        assert_eq!(t.request("rpm", 2_000), Outcome::LinkDown);
        assert!((t.scenario_seconds(2_000) - 91.0).abs() < 1e-9);
    }

    #[test]
    fn negative_responses_carry_the_nrc() {
        let t = transport("bad_responses", 0);
        assert!(matches!(
            t.request("icp", 1000),
            Outcome::Negative { nrc: 0x31, .. }
        ));
    }
}
