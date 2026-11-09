/// Writes the cross-language golden files in `test/golden/`.
///
/// For every scenario in `scenarios/`, the Dart engine is run over the first
/// [runMs] of run time in [windowMs] poll windows, and every observation is
/// written to `test/golden/<id>.json`. The Rust port
/// (`crates/powerstroke-sim/tests/golden.rs`) and `test/golden_test.dart` both
/// regenerate the observations and compare, so a drift on either side fails.
///
/// Regenerate after an intentional engine or scenario change:
///
///     cd simulator/powerstroke && fvm dart run tool/golden.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:powerstroke_sim/powerstroke_sim.dart';

const runMs = 300000;
const windowMs = 1000;
const scenariosDir = 'scenarios';
const goldenDir = 'test/golden';

/// Scenario ids (file stems) in `scenarios/`, sorted.
List<String> scenarioIds() => Directory(scenariosDir)
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.yaml'))
    .map((f) => f.uri.pathSegments.last.replaceAll('.yaml', ''))
    .toList()
  ..sort();

String _read(String id) => File('$scenariosDir/$id.yaml').readAsStringSync();

Scenario loadScenario(String id) => Scenario.parse(id, _read(id), resolve: _read);

File goldenFile(String id) => File('$goldenDir/$id.json');

/// Observations for the first [runMs], polled in [windowMs] windows, in the
/// order the engine returned them.
List<Observation> run(Scenario scenario) {
  final engine = ScenarioEngine(scenario);
  return [
    for (var t = 0; t < runMs; t += windowMs) ...engine.poll(t, t + windowMs),
  ];
}

String kindName(ObservationKind kind) => switch (kind) {
      ObservationKind.response => 'response',
      ObservationKind.noResponse => 'no_response',
      ObservationKind.negativeResponse => 'negative_response',
      ObservationKind.invalidResponse => 'invalid_response',
      ObservationKind.linkDown => 'link_down',
    };

Map<String, Object?> observationJson(Observation o) => {
      'signal': o.signalId,
      'at_ms': o.atMs,
      'kind': kindName(o.kind),
      'value': o.value,
      'nrc': o.nrc,
      'latency_ms': o.latencyMs,
    };

/// The golden file text: one observation per line to keep diffs readable.
String encodeGolden(String id, List<Observation> observations) {
  final b = StringBuffer()
    ..writeln('{')
    ..writeln(' "scenario": ${jsonEncode(id)},')
    ..writeln(' "schema": ${jsonEncode(scenarioSchema)},')
    ..writeln(' "run_ms": $runMs,')
    ..writeln(' "window_ms": $windowMs,')
    ..writeln(' "observations": [');
  for (final (i, o) in observations.indexed) {
    b.write('  ${jsonEncode(observationJson(o))}');
    b.writeln(i == observations.length - 1 ? '' : ',');
  }
  b
    ..writeln(' ]')
    ..writeln('}');
  return b.toString();
}

void main() {
  Directory(goldenDir).createSync(recursive: true);
  for (final id in scenarioIds()) {
    final observations = run(loadScenario(id));
    goldenFile(id).writeAsStringSync(encodeGolden(id, observations));
    stdout.writeln('${goldenFile(id).path}: ${observations.length} observations');
  }
}
