/// Deterministic 6.0L Power Stroke scenario simulator.
///
/// Scenario files live in `scenarios/` (format: `f250.scenario.v1`, documented
/// in `simulator/powerstroke/README.md`). The engine turns a scenario into the
/// stream of per-request observations a diagnostic gateway would see,
/// including the failure modes the head unit must survive.
library;

export 'src/engine.dart';
export 'src/scenario.dart';
