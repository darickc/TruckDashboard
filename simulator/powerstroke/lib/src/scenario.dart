import 'package:yaml/yaml.dart';

/// Schema identifier every scenario file must declare. Bump to v2 for any
/// incompatible change; the Rust simulated transport (Phase 3) checks it too.
const scenarioSchema = 'f250.scenario.v1';

/// Thrown for any malformed scenario. Scenario files are hand-written input,
/// so every check fails loudly with the file and field at fault.
class ScenarioFormatException implements Exception {
  ScenarioFormatException(this.source, this.message);

  final String source;
  final String message;

  @override
  String toString() => 'ScenarioFormatException($source): $message';
}

/// One (time, value) point of a piecewise-linear trajectory.
class Keyframe {
  const Keyframe(this.atSeconds, this.value);

  final double atSeconds;
  final double value;
}

/// How one signal behaves when the simulated gateway polls it.
class SignalTrack {
  const SignalTrack({
    required this.id,
    required this.unit,
    required this.intervalMs,
    required this.keyframes,
    this.noise = 0,
    this.min,
    this.max,
  });

  final String id;

  /// Canonical unit of every keyframe value (e.g. `degC`, `kPa`). The app
  /// checks it against the signal catalog when the scenario loads.
  final String unit;

  /// Simulated poll interval. Each poll produces one observation.
  final int intervalMs;

  final List<Keyframe> keyframes;

  /// Peak amplitude of deterministic noise added to each sample.
  final double noise;

  /// Physical limits applied after noise (e.g. speed never below 0). Not
  /// applied to fault overrides, which exist to produce impossible values.
  final double? min;
  final double? max;
}

enum FaultKind {
  /// The module never answers (adapter timeout / NO DATA). The field symptom
  /// this project exists to diagnose.
  noResponse,

  /// The module answers with a negative response (e.g. 7F 22 31).
  negativeResponse,

  /// A response arrives but cannot be decoded (wrong length, wrong echo).
  invalidResponse,

  /// A response arrives with the value replaced (to exercise range checks).
  valueOverride,

  /// The whole diagnostic link is down; every signal is affected.
  linkDown,
}

class Fault {
  const Fault({
    required this.kind,
    required this.startSeconds,
    required this.endSeconds,
    this.signals = const [],
    this.nrc,
    this.value,
  });

  final FaultKind kind;
  final double startSeconds;
  final double endSeconds;

  /// Affected signals; empty for [FaultKind.linkDown] (which affects all).
  final List<String> signals;

  /// Negative response code for [FaultKind.negativeResponse].
  final int? nrc;

  /// Replacement value for [FaultKind.valueOverride].
  final double? value;

  bool activeAt(double seconds) =>
      seconds >= startSeconds && seconds < endSeconds;

  bool affects(String signalId) =>
      kind == FaultKind.linkDown || signals.contains(signalId);
}

/// A simulated diagnostic trouble code. Always presented as simulated.
class SimulatedDtc {
  const SimulatedDtc(this.code, this.description, this.status);

  final String code;
  final String description;
  final String status;
}

class Scenario {
  const Scenario({
    required this.id,
    required this.name,
    required this.description,
    required this.durationSeconds,
    required this.loop,
    required this.seed,
    required this.tracks,
    required this.faults,
    required this.dtcs,
  });

  /// File stem, e.g. `eot_ect_freeze`.
  final String id;
  final String name;
  final String description;
  final double durationSeconds;
  final bool loop;
  final int seed;
  final Map<String, SignalTrack> tracks;
  final List<Fault> faults;
  final List<SimulatedDtc> dtcs;

  /// Parses [yamlText]. When the file declares `extends: <id>`, [resolve] is
  /// called to fetch that scenario's text; the child inherits the parent's
  /// tracks (overridable per signal) and appends its faults.
  static Scenario parse(
    String id,
    String yamlText, {
    String Function(String id)? resolve,
    Set<String> visiting = const {},
  }) {
    final Object? doc;
    try {
      doc = loadYaml(yamlText);
    } on YamlException catch (e) {
      throw ScenarioFormatException(id, 'invalid YAML: ${e.message}');
    }
    if (doc is! YamlMap) {
      throw ScenarioFormatException(id, 'top level must be a mapping');
    }
    final r = _Reader(id, doc);
    final schema = r.string('schema');
    if (schema != scenarioSchema) {
      throw ScenarioFormatException(
          id, 'schema must be "$scenarioSchema", got "$schema"');
    }

    Scenario? parent;
    final parentId = r.optionalString('extends');
    if (parentId != null) {
      if (resolve == null) {
        throw ScenarioFormatException(
            id, 'extends "$parentId" but no resolver was given');
      }
      if (visiting.contains(parentId) || parentId == id) {
        throw ScenarioFormatException(id, 'extends cycle via "$parentId"');
      }
      parent = Scenario.parse(parentId, resolve(parentId),
          resolve: resolve, visiting: {...visiting, id});
    }

    final tracks = <String, SignalTrack>{...?parent?.tracks};
    final signals = r.optionalMap('signals');
    if (signals != null) {
      for (final entry in signals.entries) {
        final sid = entry.key.toString();
        tracks[sid] = _parseTrack(id, sid, entry.value);
      }
    }
    if (tracks.isEmpty) {
      throw ScenarioFormatException(id, 'no signals defined');
    }

    final duration = r.optionalNumber('duration_s') ?? parent?.durationSeconds;
    if (duration == null || duration <= 0) {
      throw ScenarioFormatException(id, 'duration_s must be > 0');
    }

    final faults = <Fault>[...?parent?.faults];
    for (final (i, f) in (r.optionalList('faults') ?? const []).indexed) {
      faults.add(_parseFault(id, i, f, tracks.keys.toSet()));
    }

    final dtcs = <SimulatedDtc>[...?parent?.dtcs];
    for (final (i, d) in (r.optionalList('dtcs') ?? const []).indexed) {
      if (d is! YamlMap) {
        throw ScenarioFormatException(id, 'dtcs[$i] must be a mapping');
      }
      final dr = _Reader('$id dtcs[$i]', d);
      dtcs.add(SimulatedDtc(dr.string('code'), dr.string('description'),
          dr.optionalString('status') ?? 'stored'));
    }

    return Scenario(
      id: id,
      name: r.string('name'),
      description: r.optionalString('description') ?? '',
      durationSeconds: duration,
      loop: r.optionalBool('loop') ?? parent?.loop ?? true,
      seed: r.optionalNumber('seed')?.toInt() ?? parent?.seed ?? 1,
      tracks: tracks,
      faults: faults,
      dtcs: dtcs,
    );
  }

  static SignalTrack _parseTrack(String id, String sid, Object? node) {
    if (node is! YamlMap) {
      throw ScenarioFormatException(id, 'signals.$sid must be a mapping');
    }
    final r = _Reader('$id signals.$sid', node);
    final interval = r.number('interval_ms').toInt();
    if (interval < 10) {
      throw ScenarioFormatException(id, 'signals.$sid.interval_ms must be >= 10');
    }
    final frames = <Keyframe>[];
    for (final (i, kf) in r.list('keyframes').indexed) {
      if (kf is! YamlList || kf.length != 2 || kf[0] is! num || kf[1] is! num) {
        throw ScenarioFormatException(
            id, 'signals.$sid.keyframes[$i] must be [seconds, value]');
      }
      final at = (kf[0] as num).toDouble();
      if (frames.isNotEmpty && at <= frames.last.atSeconds) {
        throw ScenarioFormatException(
            id, 'signals.$sid.keyframes must have increasing times');
      }
      frames.add(Keyframe(at, (kf[1] as num).toDouble()));
    }
    if (frames.isEmpty) {
      throw ScenarioFormatException(id, 'signals.$sid.keyframes is empty');
    }
    final noise = r.optionalNumber('noise') ?? 0;
    if (noise < 0) {
      throw ScenarioFormatException(id, 'signals.$sid.noise must be >= 0');
    }
    final min = r.optionalNumber('min');
    final max = r.optionalNumber('max');
    if (min != null && max != null && min >= max) {
      throw ScenarioFormatException(id, 'signals.$sid: min must be < max');
    }
    return SignalTrack(
      id: sid,
      unit: r.string('unit'),
      intervalMs: interval,
      keyframes: frames,
      noise: noise,
      min: min,
      max: max,
    );
  }

  static Fault _parseFault(String id, int i, Object? node, Set<String> known) {
    if (node is! YamlMap) {
      throw ScenarioFormatException(id, 'faults[$i] must be a mapping');
    }
    final r = _Reader('$id faults[$i]', node);
    final kindName = r.string('kind');
    final kind = switch (kindName) {
      'no_response' => FaultKind.noResponse,
      'negative_response' => FaultKind.negativeResponse,
      'invalid_response' => FaultKind.invalidResponse,
      'value_override' => FaultKind.valueOverride,
      'link_down' => FaultKind.linkDown,
      _ => throw ScenarioFormatException(id, 'faults[$i].kind "$kindName" unknown'),
    };
    final start = r.number('start_s');
    final end = r.number('end_s');
    if (end <= start) {
      throw ScenarioFormatException(id, 'faults[$i]: end_s must be > start_s');
    }
    final signals = [
      for (final s in r.optionalList('signals') ?? const []) s.toString()
    ];
    if (kind == FaultKind.linkDown && signals.isNotEmpty) {
      throw ScenarioFormatException(id, 'faults[$i]: link_down takes no signals');
    }
    if (kind != FaultKind.linkDown && signals.isEmpty) {
      throw ScenarioFormatException(id, 'faults[$i]: signals is required');
    }
    for (final s in signals) {
      if (!known.contains(s)) {
        throw ScenarioFormatException(id, 'faults[$i]: unknown signal "$s"');
      }
    }
    final nrc = r.optionalNumber('nrc')?.toInt();
    if (kind == FaultKind.negativeResponse && nrc == null) {
      throw ScenarioFormatException(id, 'faults[$i]: negative_response needs nrc');
    }
    final value = r.optionalNumber('value');
    if (kind == FaultKind.valueOverride && value == null) {
      throw ScenarioFormatException(id, 'faults[$i]: value_override needs value');
    }
    return Fault(
        kind: kind,
        startSeconds: start,
        endSeconds: end,
        signals: signals,
        nrc: nrc,
        value: value);
  }
}

/// Typed field access with uniform error messages.
class _Reader {
  _Reader(this.where, this.map);

  final String where;
  final YamlMap map;

  Never _fail(String field, String expected) => throw ScenarioFormatException(
      where, '"$field" must be $expected (got ${map[field]})');

  String string(String f) =>
      optionalString(f) ?? _fail(f, 'a non-empty string');

  String? optionalString(String f) {
    final v = map[f];
    if (v == null) return null;
    if (v is! String || v.isEmpty) _fail(f, 'a non-empty string');
    return v;
  }

  double number(String f) => optionalNumber(f) ?? _fail(f, 'a number');

  double? optionalNumber(String f) {
    final v = map[f];
    if (v == null) return null;
    if (v is! num) _fail(f, 'a number');
    return v.toDouble();
  }

  bool? optionalBool(String f) {
    final v = map[f];
    if (v == null) return null;
    if (v is! bool) _fail(f, 'true or false');
    return v;
  }

  YamlList list(String f) => optionalList(f) ?? _fail(f, 'a list');

  YamlList? optionalList(String f) {
    final v = map[f];
    if (v == null) return null;
    if (v is! YamlList) _fail(f, 'a list');
    return v;
  }

  YamlMap? optionalMap(String f) {
    final v = map[f];
    if (v == null) return null;
    if (v is! YamlMap) _fail(f, 'a mapping');
    return v;
  }
}
