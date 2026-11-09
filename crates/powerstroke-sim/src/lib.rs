//! Deterministic 6.0L Power Stroke scenario engine.
//!
//! A Rust port of the Dart package in `simulator/powerstroke/`. It reads the
//! same `f250.scenario.v1` YAML files (documented in
//! `simulator/powerstroke/README.md`) and turns a scenario into the stream of
//! per-request observations a diagnostic gateway would see: responses,
//! timeouts, negative responses, undecodable answers and link loss. The
//! gateway uses it as its simulated transport; the Flutter app runs the Dart
//! engine. Both produce the same observations for the same scenario and time,
//! which `tests/golden.rs` checks against files written by the Dart engine.
//!
//! Scenario values are simulated. They are not measurements from the truck.
//!
//! ```no_run
//! use powerstroke_sim::{Scenario, ScenarioEngine};
//!
//! let scenario = Scenario::load("simulator/powerstroke/scenarios", "eot_ect_freeze")?;
//! let engine = ScenarioEngine::new(scenario);
//! for obs in engine.poll(0, 1000) {
//!     println!("{} @{}ms {:?} {:?}", obs.signal_id, obs.at_ms, obs.kind, obs.value);
//! }
//! let eot = engine.observe("eot", 130_000); // request-driven
//! # Ok::<(), powerstroke_sim::ScenarioError>(())
//! ```

mod engine;
mod scenario;

pub use engine::{Observation, ObservationKind, ScenarioEngine};
pub use scenario::{
    Fault, FaultKind, Keyframe, LoaderError, SCENARIO_SCHEMA, Scenario, ScenarioError, SignalTrack,
    SimulatedDtc, load_dir,
};
