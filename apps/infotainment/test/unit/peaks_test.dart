import 'package:f250_infotainment/core/clock.dart';
import 'package:f250_infotainment/model/signal_catalog.dart';
import 'package:f250_infotainment/telemetry/calibration.dart';
import 'package:f250_infotainment/telemetry/poll_result.dart';
import 'package:f250_infotainment/telemetry/telemetry_store.dart';
import 'package:f250_infotainment/telemetry/warnings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Each signal's highest and lowest valid value since start (the Gauges
/// tiles' "max" / "min", ADR-0050).
void main() {
  late FakeMonotonicClock clock;
  late TelemetryStore store;

  // The delta only counts on a warm engine, as in warning_rules.json.
  const deltaRule = WarningRule(
    id: 'delta',
    signalId: 'eot_ect_delta',
    direction: Direction.above,
    advisory: Threshold(8.3, 6.7),
    gate: Gate('ect', Direction.above, 82),
  );

  setUp(() {
    clock = FakeMonotonicClock();
    store = TelemetryStore(catalog: signalCatalog, clock: clock, rules: const [deltaRule]);
  });

  void respond(String id, double v) => store.apply(
      PollResult(signalId: id, at: clock.now(), outcome: PollOutcome.response, value: v));

  void tick([Duration d = const Duration(milliseconds: 250)]) {
    clock.advance(d);
    store.refresh();
  }

  test('keeps the highest and lowest valid value', () {
    for (final v in [90.0, 104.0, 97.0, 85.0, 99.0]) {
      respond('eot', v);
      tick();
    }
    expect(store['eot']!.peakHigh, 104);
    expect(store['eot']!.peakLow, 85);
  });

  test('none before any valid value', () {
    tick();
    expect(store['eot']!.peakHigh, isNull);
    expect(store['eot']!.peakLow, isNull);
  });

  test('an implausible answer never becomes a peak', () {
    respond('eot', 90);
    tick();
    respond('eot', 900); // outside the plausible range: rejected
    tick();
    expect(store['eot']!.peakHigh, 90);
  });

  test('a stale value is not sampled again, and the peak survives it', () {
    respond('eot', 100);
    tick();
    tick(const Duration(seconds: 30)); // stale now
    expect(store['eot']!.isValid, isFalse);
    expect(store['eot']!.peakHigh, 100);
  });

  test("a gated signal's peak counts only while its gate holds", () {
    // Cold engine: ECT 60 °C, delta 30 °C. Not a peak.
    respond('eot', 90);
    respond('ect', 60);
    tick();
    expect(store['eot_ect_delta']!.isValid, isTrue);
    expect(store['eot_ect_delta']!.peakHigh, isNull);
    // Warm: ECT 88 °C, delta 4 °C.
    respond('eot', 92);
    respond('ect', 88);
    tick();
    expect(store['eot_ect_delta']!.peakHigh, closeTo(4, 1e-9));
    // EOT itself has no gate: its peaks count from the start.
    expect(store['eot']!.peakLow, 90);
  });

  test('a calibration change starts the peaks over, under the new factor', () {
    respond('eot', 120);
    tick();
    respond('eot', 100);
    tick();
    store.setCalibration('eot', const Calibration(scale: 1.1, offset: 0));
    // 120 under the old factor is gone; the current 100 rescaled is the peak.
    expect(store['eot']!.peakHigh, closeTo(110, 1e-9));
    expect(store['eot']!.peakLow, closeTo(110, 1e-9));
  });

  test('a scenario change (reset) clears them', () {
    respond('eot', 100);
    tick();
    store.reset();
    expect(store['eot']!.peakHigh, isNull);
  });
}
