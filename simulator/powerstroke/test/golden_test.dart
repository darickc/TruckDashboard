// Cross-language conformance: the golden files in test/golden/ are also read
// by the Rust port (crates/powerstroke-sim/tests/golden.rs). This test
// regenerates them in memory, so a change to the Dart engine or a scenario
// that is not mirrored in Rust fails here first. After an intentional change,
// run `fvm dart run tool/golden.dart` and make the Rust tests pass again.
import 'dart:convert';

import 'package:powerstroke_sim/powerstroke_sim.dart';
import 'package:test/test.dart';

import '../tool/golden.dart' as golden;

void main() {
  final ids = golden.scenarioIds();

  test('every scenario has a golden file', () {
    for (final id in ids) {
      expect(golden.goldenFile(id).existsSync(), isTrue,
          reason: 'missing ${golden.goldenFile(id).path}; '
              'run `fvm dart run tool/golden.dart`');
    }
  });

  for (final id in ids) {
    test('$id matches its golden file', () {
      final file = golden.goldenFile(id);
      if (!file.existsSync()) fail('missing ${file.path}');
      final doc = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      expect(doc['scenario'], id);
      expect(doc['schema'], scenarioSchema);
      expect(doc['run_ms'], golden.runMs);
      expect(doc['window_ms'], golden.windowMs);

      final expected = (doc['observations'] as List).cast<Map<String, Object?>>();
      final actual = golden.run(golden.loadScenario(id)).map(golden.observationJson).toList();
      expect(actual.length, expected.length, reason: 'observation count');
      for (var i = 0; i < actual.length; i++) {
        final a = actual[i], e = expected[i];
        final where = '$id observation $i ($e)';
        expect(a['signal'], e['signal'], reason: where);
        expect(a['at_ms'], e['at_ms'], reason: where);
        expect(a['kind'], e['kind'], reason: where);
        expect(a['nrc'], e['nrc'], reason: where);
        expect(a['latency_ms'], e['latency_ms'], reason: where);
        final av = a['value'] as double?, ev = e['value'] as num?;
        if (ev == null) {
          expect(av, isNull, reason: where);
        } else {
          expect(av, closeTo(ev, 1e-9), reason: where);
        }
      }
    });
  }
}
