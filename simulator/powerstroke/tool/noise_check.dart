// Prints a fingerprint of engine output for one scenario. Run on the VM and
// compiled to JavaScript; the two outputs must be identical (web builds of
// the app must see the same simulated values as the VM and the Rust gateway).
import 'package:powerstroke_sim/powerstroke_sim.dart';

const _yaml = '''
schema: f250.scenario.v1
name: Noise check
duration_s: 600
seed: 2007
signals:
  eot: {unit: degC, interval_ms: 1000, noise: 0.3, keyframes: [[0, 92], [600, 108]]}
  rpm: {unit: rpm, interval_ms: 250, noise: 10, keyframes: [[0, 690]]}
''';

void main() {
  final engine = ScenarioEngine(Scenario.parse('noise_check', _yaml));
  final obs = engine.poll(0, 10000);
  for (final o in obs.take(12)) {
    print('${o.signalId} ${o.atMs} ${o.value!.toStringAsFixed(9)} ${o.latencyMs}');
  }
  print('count ${obs.length}');
}
