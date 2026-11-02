import 'package:f250_infotainment/core/clock.dart';
import 'package:f250_infotainment/data/simulated_vehicle_data_source.dart';
import 'package:f250_infotainment/model/signal.dart';
import 'package:f250_infotainment/model/signal_catalog.dart';
import 'package:f250_infotainment/telemetry/telemetry_store.dart';
import 'package:f250_infotainment/telemetry/warnings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// Plays a scenario through the real store and calls [check] after every
/// 100 ms step.
void play(String id, Duration length, void Function(TelemetryStore, Duration) check) {
  final clock = FakeMonotonicClock();
  final store = TelemetryStore(
      catalog: signalCatalog,
      clock: clock,
      rules: testConfig.rules,
      watchedSignals: testConfig.watched);
  final src = SimulatedVehicleDataSource(store: store, scenario: testScenarios[id]!)
    ..startManual();
  for (var t = Duration.zero; t < length; t += const Duration(milliseconds: 100)) {
    clock.advance(const Duration(milliseconds: 100));
    src.step();
    check(store, clock.now());
  }
}

void main() {
  setUpAll(loadTestAssets);

  test('the fault-free drive cycle never produces an invalid reading', () {
    const bad = {Validity.outOfRange, Validity.decodeError, Validity.unsupported};
    play('drive_cycle', const Duration(minutes: 10), (store, now) {
      if (now < const Duration(seconds: 6)) return; // baro's first poll is at 5 s
      for (final s in store.ordered) {
        expect(bad, isNot(contains(s.validity)), reason: '${s.def.id} at $now');
        if (s.def.enabled) {
          expect(s.validity, Validity.valid, reason: '${s.def.id} at $now');
        }
      }
      expect(store.link, LinkState.up, reason: 'at $now');
    });
  });

  test('EOT/ECT freeze: stale + alerts during the fault, recovery after', () {
    var sawStale = false;
    play('eot_ect_freeze', const Duration(seconds: 280), (store, now) {
      final t = now.inMilliseconds / 1000;
      if (t > 130 && t < 255) {
        sawStale = true;
        expect(store['eot']!.validity, Validity.stale, reason: 'at $t s');
        expect(store['ect']!.validity, Validity.stale);
        expect(store['eot_ect_delta']!.value, isNull, reason: 'delta from frozen inputs');
        expect(store['rpm']!.validity, Validity.valid, reason: 'other PIDs keep working');
        expect(store.link, LinkState.degraded);
        expect(
            store.alerts
                .where((a) => a.kind == AlertKind.signalNotUpdating)
                .map((a) => a.signalId),
            containsAll(['eot', 'ect']));
      }
      if (t > 265) {
        expect(store['eot']!.validity, Validity.valid, reason: 'recovers without intervention');
        expect(store['eot_ect_delta']!.validity, Validity.valid);
        expect(store.link, LinkState.up);
      }
    });
    expect(sawStale, isTrue);
  });

  test('link loss: everything stale + critical alert, then recovery', () {
    play('link_loss', const Duration(seconds: 140), (store, now) {
      final t = now.inMilliseconds / 1000;
      if (t > 96 && t < 129) {
        expect(store.link, LinkState.down, reason: 'at $t s');
        expect(store.alerts.first.kind, AlertKind.linkLost);
      }
      // Each signal goes stale on its own schedule (baro is allowed 20 s).
      if (t > 112 && t < 129) {
        expect(store.ordered.where((s) => s.isValid), isEmpty, reason: 'at $t s');
      }
      if (t > 136) {
        expect(store.link, LinkState.up, reason: 'at $t s');
        expect(store.alerts.where((a) => a.kind == AlertKind.linkLost), isEmpty);
      }
    });
  });

  test('bad responses: unsupported ICP, decode-error MAP invalidates boost, implausible trans',
      () {
    play('bad_responses', const Duration(seconds: 340), (store, now) {
      final t = now.inMilliseconds / 1000;
      expect(store['icp']!.value, isNull, reason: 'ICP never shows a value');
      if (t > 2) expect(store['icp']!.validity, Validity.unsupported);
      if (t > 103 && t < 160) expect(store['boost']!.value, isNull, reason: 'at $t s');
      if (t > 301 && t < 330) {
        expect(store['trans_temp']!.value, isNull, reason: 'at $t s');
        expect(store['trans_temp']!.lastGoodValue, lessThan(150));
      }
      expect(store.warnings.levelOf('trans_temp_high'), AlertLevel.none,
          reason: 'an implausible value must not drive a warning');
    });
  });

  test('startAt begins part-way through without replaying the skipped time', () {
    final clock = FakeMonotonicClock(const Duration(seconds: 1));
    final store = TelemetryStore(
        catalog: signalCatalog, clock: clock, rules: const [], watchedSignals: const []);
    final src = SimulatedVehicleDataSource(
        store: store, scenario: testScenarios['eot_ect_freeze']!,
        startAt: const Duration(seconds: 150))
      ..startManual();
    expect(src.scenarioSeconds, closeTo(150, 1e-9));
    clock.advance(const Duration(seconds: 2));
    src.step();
    expect(store['rpm']!.successes, lessThanOrEqualTo(8), reason: 'only ~2 s of polls');
    expect(store['eot']!.successes, 0, reason: 'inside the freeze window');
  });

  test('FICM sag raises the low-voltage warning under load', () {
    var level = AlertLevel.none;
    play('ficm_sag', const Duration(seconds: 380), (store, now) {
      final l = store.warnings.levelOf('ficm_main_low');
      if (l.index > level.index) level = l;
    });
    expect(level, AlertLevel.critical);
  });
}
