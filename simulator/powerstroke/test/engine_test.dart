import 'package:powerstroke_sim/powerstroke_sim.dart';
import 'package:test/test.dart';

Scenario _scenario({List<String> faults = const [], bool loop = true}) =>
    Scenario.parse('t', '''
schema: f250.scenario.v1
name: Test
duration_s: 10
loop: $loop
seed: 3
signals:
  rpm: {unit: rpm, interval_ms: 100, keyframes: [[0, 700], [10, 1700]]}
  eot: {unit: degC, interval_ms: 1000, noise: 2, keyframes: [[0, 90]]}
faults:
${faults.map((f) => '  - $f').join('\n')}
''');

void main() {
  test('polls each signal at k × interval within (from, to]', () {
    final obs = ScenarioEngine(_scenario()).poll(0, 1000);
    expect(obs.where((o) => o.signalId == 'rpm').map((o) => o.atMs),
        [for (var k = 1; k <= 10; k++) k * 100]);
    expect(obs.where((o) => o.signalId == 'eot').map((o) => o.atMs), [1000]);
    expect(obs.map((o) => o.atMs), orderedEquals([...obs.map((o) => o.atMs)]..sort()));
  });

  test('interpolates linearly between keyframes', () {
    final obs = ScenarioEngine(_scenario()).poll(4900, 5000);
    expect(obs.singleWhere((o) => o.signalId == 'rpm').value, closeTo(1200, 1e-9));
  });

  test('output is independent of how the window is split', () {
    final whole = ScenarioEngine(_scenario()).poll(0, 3000);
    final e = ScenarioEngine(_scenario());
    final parts = [...e.poll(0, 1234), ...e.poll(1234, 2000), ...e.poll(2000, 3000)];
    expect(parts.map((o) => '${o.signalId}${o.atMs}${o.value}'),
        whole.map((o) => '${o.signalId}${o.atMs}${o.value}'));
  });

  test('noise is bounded and deterministic', () {
    final a = ScenarioEngine(_scenario()).poll(0, 10000).where((o) => o.signalId == 'eot');
    final b = ScenarioEngine(_scenario()).poll(0, 10000).where((o) => o.signalId == 'eot');
    expect(a.map((o) => o.value), b.map((o) => o.value));
    for (final o in a) {
      expect(o.value, inInclusiveRange(88, 92));
    }
    expect(a.map((o) => o.value).toSet().length, greaterThan(1));
  });

  test('min/max clamp noisy values to physical limits', () {
    final s = Scenario.parse('c', '''
schema: f250.scenario.v1
name: Clamp
duration_s: 10
signals:
  speed: {unit: km/h, interval_ms: 100, noise: 5, min: 0, keyframes: [[0, 0]]}
''');
    final values = ScenarioEngine(s).poll(0, 10000).map((o) => o.value!);
    expect(values.every((v) => v >= 0), isTrue);
    expect(values.any((v) => v > 0), isTrue);
  });

  test('loops: elapsed time wraps onto the scenario clock', () {
    final e = ScenarioEngine(_scenario());
    expect(e.scenarioSeconds(12500), closeTo(2.5, 1e-9));
    final obs = e.poll(12400, 12500).single;
    expect(obs.atMs, 12500);
    expect(obs.value, closeTo(950, 1e-9));
  });

  test('without looping the clock holds at the end', () {
    final e = ScenarioEngine(_scenario(loop: false));
    expect(e.scenarioSeconds(25000), 10);
  });

  test('no_response affects only the named signals and only in the window', () {
    final e = ScenarioEngine(_scenario(
        faults: ['{kind: no_response, signals: [eot], start_s: 2, end_s: 4}']));
    final obs = e.poll(0, 6000);
    final eot = {for (final o in obs.where((o) => o.signalId == 'eot')) o.atMs: o.kind};
    expect(eot[1000], ObservationKind.response);
    expect(eot[2000], ObservationKind.noResponse);
    expect(eot[3000], ObservationKind.noResponse);
    expect(eot[4000], ObservationKind.response);
    expect(obs.where((o) => o.signalId == 'rpm').every((o) => o.kind == ObservationKind.response),
        isTrue);
  });

  test('link_down affects every signal and reports link state', () {
    final e = ScenarioEngine(_scenario(faults: ['{kind: link_down, start_s: 1, end_s: 2}']));
    expect(e.linkUpAt(500), isTrue);
    expect(e.linkUpAt(1500), isFalse);
    final during = e.poll(1000, 1900);
    expect(during, isNotEmpty);
    expect(during.every((o) => o.kind == ObservationKind.linkDown), isTrue);
  });

  test('negative response carries the NRC; override replaces the value', () {
    final e = ScenarioEngine(_scenario(faults: [
      '{kind: negative_response, signals: [eot], nrc: 0x31, start_s: 0, end_s: 10}',
      '{kind: value_override, signals: [rpm], value: 9999, start_s: 0, end_s: 10}',
    ]));
    final obs = e.poll(0, 1000);
    final eot = obs.firstWhere((o) => o.signalId == 'eot');
    expect(eot.kind, ObservationKind.negativeResponse);
    expect(eot.nrc, 0x31);
    expect(obs.firstWhere((o) => o.signalId == 'rpm').value, 9999);
  });

  test('a long suspension skips ahead instead of replaying a backlog', () {
    final obs = ScenarioEngine(_scenario()).poll(0, 3600 * 1000);
    expect(obs.first.atMs, greaterThan(3600 * 1000 - ScenarioEngine.maxWindowMs));
  });
}
