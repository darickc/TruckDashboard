import 'package:f250_infotainment/config/app_config.dart';
import 'package:f250_infotainment/core/clock.dart';
import 'package:f250_infotainment/model/signal.dart';
import 'package:f250_infotainment/model/signal_catalog.dart';
import 'package:f250_infotainment/telemetry/calibration.dart';
import 'package:f250_infotainment/telemetry/poll_result.dart';
import 'package:f250_infotainment/telemetry/telemetry_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

const _rules = '{"rules": []}';
const _profiles =
    '{"profiles": [{"id": "p", "name": "P", "tiles": [{"signal": "speed", "style": "digital"}]}]}';

void main() {
  late FakeMonotonicClock clock;
  late TelemetryStore store;

  setUpAll(loadTestAssets);

  setUp(() {
    clock = FakeMonotonicClock();
    store = TelemetryStore(
        catalog: signalCatalog,
        clock: clock,
        rules: const [],
        calibrations: const {'speed': Calibration(scale: 1.05)});
  });

  void respond(String id, double v) => store.apply(
      PollResult(signalId: id, at: clock.now(), outcome: PollOutcome.response, value: v));

  test('the scale is applied to every reading; the raw value is kept', () {
    respond('speed', 100);
    store.refresh();
    expect(store['speed']!.value, closeTo(105, 1e-9));
    expect(store['speed']!.lastGoodRaw, 100);
  });

  test('uncalibrated signals are untouched', () {
    respond('rpm', 700);
    store.refresh();
    expect(store['rpm']!.value, 700);
  });

  test('range checks apply to the calibrated value', () {
    respond('speed', 250); // ×1.05 = 262.5 > 255
    store.refresh();
    expect(store['speed']!.validity, Validity.outOfRange);
  });

  test('changing the calibration rescales the current reading at once', () {
    respond('speed', 100);
    store.refresh();
    store.setCalibration('speed', const Calibration(scale: 1.10));
    expect(store['speed']!.value, closeTo(110, 1e-9));
    expect(store.events.newestFirst.first.message, contains('×1.1000'));
  });

  test('computed signals cannot be calibrated directly', () {
    expect(() => store.setCalibration('boost', const Calibration(scale: 1.1)),
        throwsArgumentError);
  });

  test('offset is applied after scale', () {
    store.setCalibration('speed', const Calibration(scale: 2, offset: -1));
    respond('speed', 10);
    store.refresh();
    expect(store['speed']!.value, closeTo(19, 1e-9));
  });

  group('config', () {
    String cal(String body) => '{"signals": {$body}}';

    test('shipped calibration loads; speed starts unmeasured at ×1.0', () {
      expect(testConfig.calibrations['speed']!.scale, 1.0);
    });

    test('rejects a scale outside 0.5–2.0 (likely a typo)', () {
      expect(
          () => AppConfig.parse(_rules, _profiles, signalsById,
              calibrationJson: cal('"speed": {"scale": 10.5}')),
          throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('0.5'))));
    });

    test('rejects unknown and computed signals', () {
      expect(
          () => AppConfig.parse(_rules, _profiles, signalsById,
              calibrationJson: cal('"spd": {"scale": 1.02}')),
          throwsFormatException);
      expect(
          () => AppConfig.parse(_rules, _profiles, signalsById,
              calibrationJson: cal('"boost": {"scale": 1.02}')),
          throwsFormatException);
    });
  });
}
