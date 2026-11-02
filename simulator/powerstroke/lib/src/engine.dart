import 'scenario.dart';

/// What the simulated gateway saw for one poll of one signal.
enum ObservationKind {
  /// A decodable positive response carrying [Observation.value].
  response,

  /// No answer before the timeout.
  noResponse,

  /// A negative response with [Observation.nrc].
  negativeResponse,

  /// An answer that could not be decoded.
  invalidResponse,

  /// The diagnostic link itself is down; nothing was sent.
  linkDown,
}

class Observation {
  const Observation({
    required this.signalId,
    required this.atMs,
    required this.kind,
    this.value,
    this.nrc,
    this.latencyMs,
  });

  final String signalId;

  /// Milliseconds since the run started (monotonic; does not wrap on loop).
  final int atMs;
  final ObservationKind kind;

  /// Canonical-unit value for [ObservationKind.response].
  final double? value;
  final int? nrc;

  /// Simulated request→response latency for answered requests.
  final int? latencyMs;

  @override
  String toString() =>
      'Observation($signalId @${atMs}ms ${kind.name}${value == null ? '' : ' $value'})';
}

/// Deterministic scenario playback.
///
/// The same scenario and elapsed time always produce the same observations,
/// regardless of how the time range is split across calls — tests rely on it.
class ScenarioEngine {
  ScenarioEngine(this.scenario);

  final Scenario scenario;

  /// Upper bound on the window one [poll] call generates. A caller that was
  /// suspended for longer (laptop asleep) skips ahead instead of replaying
  /// minutes of backlog in one burst.
  static const maxWindowMs = 10000;

  /// Scenario clock for a run-elapsed time: wraps when looping, otherwise
  /// holds at the end.
  double scenarioSeconds(int elapsedMs) {
    final s = elapsedMs / 1000.0;
    if (scenario.loop) return s % scenario.durationSeconds;
    return s > scenario.durationSeconds ? scenario.durationSeconds : s;
  }

  bool linkUpAt(int elapsedMs) {
    final t = scenarioSeconds(elapsedMs);
    return !scenario.faults
        .any((f) => f.kind == FaultKind.linkDown && f.activeAt(t));
  }

  /// Every poll scheduled in the half-open window (fromMs, toMs], in time
  /// order. Poll k of a signal happens at k × interval.
  List<Observation> poll(int fromMs, int toMs) {
    if (toMs <= fromMs) return const [];
    if (toMs - fromMs > maxWindowMs) fromMs = toMs - maxWindowMs;
    final out = <Observation>[];
    for (final track in scenario.tracks.values) {
      final interval = track.intervalMs;
      for (var k = fromMs ~/ interval + 1; k * interval <= toMs; k++) {
        out.add(_observe(track, k, k * interval));
      }
    }
    out.sort((a, b) => a.atMs.compareTo(b.atMs));
    return out;
  }

  /// Interpolated value plus deterministic noise for poll [k].
  double valueAt(SignalTrack track, double seconds, int k) {
    final frames = track.keyframes;
    double base;
    if (seconds <= frames.first.atSeconds) {
      base = frames.first.value;
    } else if (seconds >= frames.last.atSeconds) {
      base = frames.last.value;
    } else {
      var i = 1;
      while (frames[i].atSeconds < seconds) {
        i++;
      }
      final a = frames[i - 1], b = frames[i];
      final f = (seconds - a.atSeconds) / (b.atSeconds - a.atSeconds);
      base = a.value + (b.value - a.value) * f;
    }
    var v = track.noise == 0 ? base : base + track.noise * (2 * _unit(track.id, k) - 1);
    if (track.min != null && v < track.min!) v = track.min!;
    if (track.max != null && v > track.max!) v = track.max!;
    return v;
  }

  Observation _observe(SignalTrack track, int k, int atMs) {
    final t = scenarioSeconds(atMs);
    final active = scenario.faults
        .where((f) => f.activeAt(t) && f.affects(track.id))
        .toList();
    Fault? first(FaultKind kind) {
      for (final f in active) {
        if (f.kind == kind) return f;
      }
      return null;
    }

    if (first(FaultKind.linkDown) != null) {
      return Observation(
          signalId: track.id, atMs: atMs, kind: ObservationKind.linkDown);
    }
    if (first(FaultKind.noResponse) != null) {
      return Observation(
          signalId: track.id, atMs: atMs, kind: ObservationKind.noResponse);
    }
    final latency = 40 + (_unit('${track.id}#lat', k) * 40).round();
    final negative = first(FaultKind.negativeResponse);
    if (negative != null) {
      return Observation(
          signalId: track.id,
          atMs: atMs,
          kind: ObservationKind.negativeResponse,
          nrc: negative.nrc,
          latencyMs: latency);
    }
    if (first(FaultKind.invalidResponse) != null) {
      return Observation(
          signalId: track.id,
          atMs: atMs,
          kind: ObservationKind.invalidResponse,
          latencyMs: latency);
    }
    final override = first(FaultKind.valueOverride);
    return Observation(
        signalId: track.id,
        atMs: atMs,
        kind: ObservationKind.response,
        value: override?.value ?? valueAt(track, t, k),
        latencyMs: latency);
  }

  /// Uniform [0, 1) from (seed, key, k), stable across runs and platforms.
  double _unit(String key, int k) {
    var h = 0x811c9dc5 ^ scenario.seed;
    for (final c in key.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    var x = (h ^ (k * 0x9e3779b1)) & 0xffffffff;
    x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0xffffffff;
    x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0xffffffff;
    x = x ^ (x >> 16);
    return x / 0x100000000;
  }
}
