//! Telemetry model for the F-250 head unit.
//!
//! - [`units`]: quantities, canonical units, native→canonical and display
//!   conversion.
//! - [`formula`]: the ADR-0006 safe formula grammar and the Torque importer.
//! - [`calibration`]: per-signal `raw × scale + offset` correction.
//! - [`registry`]: `shared/signals/*.yaml`, loaded and validated.
//! - [`state`]: validity, staleness, computed signals, link health, events.
//! - [`warnings`]: threshold rules with hysteresis, durations and gates.
//!
//! Design: `docs/architecture/telemetry-model.md`. The Flutter app
//! (`apps/infotainment/lib/telemetry/`) implements the same rules in Dart.
//! No module here touches a vehicle bus or a clock: times are passed in as
//! monotonic [`std::time::Duration`]s.

pub mod calibration;
pub mod formula;
pub mod registry;
pub mod state;
pub mod units;
pub mod warnings;

pub use calibration::Calibration;
pub use formula::Formula;
pub use registry::{Provenance, Registry, SignalDef, Source};
pub use state::{LinkState, Outcome, PollResult, SignalState, TelemetryStore, Validity};
pub use units::{Quantity, Unit, UnitSystem};
pub use warnings::{AlertLevel, WarningConfig, WarningEngine, WarningRule};
