import 'dart:io';

import 'package:powerstroke_sim/powerstroke_sim.dart';
import 'package:test/test.dart';

String _read(String id) => File('scenarios/$id.yaml').readAsStringSync();

Scenario _load(String id) => Scenario.parse(id, _read(id), resolve: _read);

const _minimal = '''
schema: f250.scenario.v1
name: Minimal
duration_s: 10
signals:
  rpm: {unit: rpm, interval_ms: 100, keyframes: [[0, 700], [10, 1700]]}
''';

void main() {
  group('shipped scenarios', () {
    final ids = Directory('scenarios')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.yaml'))
        .map((f) => f.uri.pathSegments.last.replaceAll('.yaml', ''))
        .toList()
      ..sort();

    test('the expected set is present', () {
      expect(ids, containsAll(['drive_cycle', 'eot_ect_freeze', 'link_loss']));
    });

    for (final id in ids) {
      test('$id parses and plays for a full cycle', () {
        final s = _load(id);
        final engine = ScenarioEngine(s);
        final end = (s.durationSeconds * 1000).toInt();
        var count = 0;
        for (var t = 0; t < end; t += 1000) {
          count += engine.poll(t, t + 1000).length;
        }
        expect(count, greaterThan(0));
      });
    }

    test('extends inherits tracks and appends faults', () {
      final freeze = _load('eot_ect_freeze');
      final base = _load('drive_cycle');
      expect(freeze.tracks.keys, unorderedEquals(base.tracks.keys));
      expect(freeze.durationSeconds, base.durationSeconds);
      expect(freeze.faults.single.kind, FaultKind.noResponse);
      expect(freeze.faults.single.signals, ['eot', 'ect']);
    });
  });

  group('parser rejects malformed input', () {
    void rejects(String yaml, Matcher message) => expect(
        () => Scenario.parse('bad', yaml),
        throwsA(isA<ScenarioFormatException>()
            .having((e) => e.message, 'message', message)));

    test('wrong schema', () {
      rejects(_minimal.replaceFirst('v1', 'v9'), contains('schema'));
    });
    test('non-increasing keyframes', () {
      rejects(_minimal.replaceFirst('[10, 1700]', '[0, 1700]'),
          contains('increasing'));
    });
    test('fault on an unknown signal', () {
      rejects('$_minimal\nfaults:\n  - {kind: no_response, signals: [eot], start_s: 1, end_s: 2}\n',
          contains('unknown signal'));
    });
    test('unknown fault kind', () {
      rejects('$_minimal\nfaults:\n  - {kind: explode, signals: [rpm], start_s: 1, end_s: 2}\n',
          contains('unknown'));
    });
    test('negative response without an NRC', () {
      rejects('$_minimal\nfaults:\n  - {kind: negative_response, signals: [rpm], start_s: 1, end_s: 2}\n',
          contains('nrc'));
    });
    test('extends without a resolver', () {
      rejects('${_minimal}extends: other\n', contains('resolver'));
    });
    test('extends cycle', () {
      const a = 'schema: f250.scenario.v1\nname: A\nextends: b\n';
      const b = 'schema: f250.scenario.v1\nname: B\nextends: a\n';
      expect(
          () => Scenario.parse('a', a, resolve: (id) => id == 'a' ? a : b),
          throwsA(isA<ScenarioFormatException>()));
    });
    test('invalid YAML', () {
      rejects('signals: [unclosed', contains('YAML'));
    });
  });
}
