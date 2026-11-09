import 'dart:async';

import 'package:powerstroke_sim/powerstroke_sim.dart';

import '../core/clock.dart';
import '../telemetry/poll_result.dart';
import '../telemetry/telemetry_store.dart';
import 'vehicle_data_source.dart';

/// Plays a simulator scenario into a TelemetryStore, the way the gateway
/// will deliver real responses. Time comes from the store's monotonic clock,
/// so tests drive it with a fake clock and call [step] directly.
class SimulatedVehicleDataSource implements VehicleDataSource {
  SimulatedVehicleDataSource({
    required this.store,
    required this.scenario,
    this.tickInterval = const Duration(milliseconds: 100),
    this.startAt = Duration.zero,
  }) : _engine = ScenarioEngine(scenario);

  final TelemetryStore store;
  final Scenario scenario;
  final Duration tickInterval;

  /// Begin part-way into the scenario (development: jump straight to a fault
  /// window instead of waiting for it).
  final Duration startAt;
  final ScenarioEngine _engine;

  Timer? _timer;
  Duration? _startedAt;
  int _lastMs = 0;

  MonotonicClock get _clock => store.clock;

  /// Milliseconds since this source started (the scenario clock).
  int get elapsedMs =>
      _startedAt == null ? 0 : (_clock.now() - _startedAt!).inMilliseconds;

  double get scenarioSeconds => _engine.scenarioSeconds(elapsedMs);

  @override
  String get label => 'SIMULATED';

  @override
  bool get isSimulated => true;

  @override
  void start() {
    startManual();
    _timer ??= Timer.periodic(tickInterval, (_) => step());
  }

  /// Starts the scenario clock without a timer (tests).
  void startManual() {
    if (_startedAt != null) return;
    _startedAt = _clock.now() - startAt;
    _lastMs = startAt.inMilliseconds;
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Delivers every poll due since the last step, then refreshes the store.
  void step() {
    final start = _startedAt;
    if (start == null) return;
    final now = elapsedMs;
    for (final o in _engine.poll(_lastMs, now)) {
      store.apply(PollResult(
        signalId: o.signalId,
        at: start + Duration(milliseconds: o.atMs),
        outcome: switch (o.kind) {
          ObservationKind.response => PollOutcome.response,
          ObservationKind.noResponse => PollOutcome.noResponse,
          ObservationKind.negativeResponse => PollOutcome.negativeResponse,
          ObservationKind.invalidResponse => PollOutcome.invalidResponse,
          ObservationKind.linkDown => PollOutcome.linkDown,
        },
        value: o.value,
        nrc: o.nrc,
        latencyMs: o.latencyMs,
        responder: store[o.signalId]?.def.responder,
      ));
    }
    _lastMs = now;
    store.setSourceLinkDown(!_engine.linkUpAt(now));
    store.refresh();
  }
}
