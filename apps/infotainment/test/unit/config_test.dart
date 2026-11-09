import 'package:f250_infotainment/config/app_config.dart';
import 'package:f250_infotainment/model/signal_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

const _rules = '{"rules": [], "comm_watch": []}';
const _profiles = '{"profiles": [{"id": "p", "name": "P", "tiles": [{"signal": "eot", "style": "digital"}]}]}';

void main() {
  setUpAll(loadTestAssets);

  test('shipped config loads and references only known signals', () {
    expect(testConfig.rules, isNotEmpty);
    expect(testConfig.profiles.map((p) => p.id), containsAll(['engine', 'towing']));
    expect(testConfig.watched, containsAll(['eot', 'ect']));
  });

  test('shipped scenarios load and match the catalog', () {
    expect(testScenarios.keys, containsAll(['drive_cycle', 'eot_ect_freeze', 'link_loss']));
  });

  test('unknown signal in a profile fails fast', () {
    expect(
        () => AppConfig.parse(_rules, _profiles.replaceFirst('eot', 'oil_temp'), signalsById),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('unknown signal'))));
  });

  test('unknown signal in a rule fails fast', () {
    const rules =
        '{"rules": [{"id": "r", "signal": "nope", "direction": "above", "advisory": {"trigger": 1, "clear": 0}}]}';
    expect(() => AppConfig.parse(rules, _profiles, signalsById), throwsFormatException);
  });

  test('too many tiles fails fast', () {
    final tiles = List.filled(9, '{"signal": "eot", "style": "digital"}').join(',');
    expect(
        () => AppConfig.parse(
            _rules, '{"profiles": [{"id": "p", "name": "P", "tiles": [$tiles]}]}', signalsById),
        throwsFormatException);
  });
}
