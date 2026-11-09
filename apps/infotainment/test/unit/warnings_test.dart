import 'package:f250_infotainment/core/clock.dart';
import 'package:f250_infotainment/model/signal_catalog.dart';
import 'package:f250_infotainment/telemetry/poll_result.dart';
import 'package:f250_infotainment/telemetry/telemetry_store.dart';
import 'package:f250_infotainment/telemetry/warnings.dart';
import 'package:flutter_test/flutter_test.dart';

const _ectRule = WarningRule(
  id: 'ect_high',
  signalId: 'ect',
  direction: Direction.above,
  advisory: Threshold(104, 101),
  critical: Threshold(110, 107),
  minDuration: Duration(seconds: 5),
);

const _ficmRule = WarningRule(
  id: 'ficm_low',
  signalId: 'ficm_main',
  direction: Direction.below,
  advisory: Threshold(46, 47),
  gate: Gate('rpm', Direction.above, 400),
);

void main() {
  late FakeMonotonicClock clock;
  late TelemetryStore store;

  setUp(() {
    clock = FakeMonotonicClock();
    store = TelemetryStore(catalog: signalCatalog, clock: clock, rules: [_ectRule, _ficmRule]);
  });

  void set(String id, double v) => store.apply(
      PollResult(signalId: id, at: clock.now(), outcome: PollOutcome.response, value: v));

  /// Feeds [v] every 500 ms for [d], refreshing as it goes.
  void hold(String id, double v, Duration d) {
    for (var t = Duration.zero; t < d; t += const Duration(milliseconds: 500)) {
      set(id, v);
      store.refresh();
      clock.advance(const Duration(milliseconds: 500));
    }
    set(id, v);
    store.refresh();
  }

  AlertLevel level(String rule) => store.warnings.levelOf(rule);

  test('needs the minimum duration before raising', () {
    hold('ect', 105, const Duration(seconds: 4));
    expect(level('ect_high'), AlertLevel.none);
    hold('ect', 105, const Duration(seconds: 2));
    expect(level('ect_high'), AlertLevel.advisory);
  });

  test('a brief spike does not raise', () {
    hold('ect', 105, const Duration(seconds: 3));
    hold('ect', 95, const Duration(seconds: 1));
    hold('ect', 105, const Duration(seconds: 3));
    expect(level('ect_high'), AlertLevel.none);
  });

  test('hysteresis: holds between clear and trigger, drops below clear', () {
    hold('ect', 105, const Duration(seconds: 6));
    expect(level('ect_high'), AlertLevel.advisory);
    hold('ect', 102, const Duration(seconds: 2)); // below trigger, above clear
    expect(level('ect_high'), AlertLevel.advisory);
    hold('ect', 100, const Duration(seconds: 1)); // below clear
    expect(level('ect_high'), AlertLevel.none);
  });

  test('escalates to critical and steps back down through advisory', () {
    hold('ect', 111, const Duration(seconds: 6));
    expect(level('ect_high'), AlertLevel.critical);
    hold('ect', 108, const Duration(seconds: 1)); // above critical clear
    expect(level('ect_high'), AlertLevel.critical);
    hold('ect', 105, const Duration(seconds: 1)); // below critical clear, above advisory trigger
    expect(level('ect_high'), AlertLevel.advisory);
  });

  test('never fires on a stale signal, and a stale signal clears it', () {
    hold('ect', 111, const Duration(seconds: 6));
    expect(level('ect_high'), AlertLevel.critical);
    clock.advance(const Duration(seconds: 10)); // ECT stops updating
    store.refresh();
    expect(store['ect']!.isValid, isFalse);
    expect(level('ect_high'), AlertLevel.none);
  });

  test('below-direction rules with a gate', () {
    hold('ficm_main', 44, const Duration(seconds: 1));
    expect(level('ficm_low'), AlertLevel.none, reason: 'engine not running (no rpm)');
    for (var i = 0; i < 3; i++) {
      set('rpm', 700);
      set('ficm_main', 44);
      store.refresh();
      clock.advance(const Duration(milliseconds: 500));
    }
    expect(level('ficm_low'), AlertLevel.advisory);
  });

  test('threshold alerts are reported with their rule and level', () {
    hold('ect', 111, const Duration(seconds: 6));
    final a = store.alerts.firstWhere((a) => a.kind == AlertKind.threshold);
    expect(a.rule!.id, 'ect_high');
    expect(a.level, AlertLevel.critical);
  });

  group('rule parsing', () {
    test('rejects clear on the wrong side of trigger', () {
      expect(
          () => WarningRule.fromJson({
                'id': 'x',
                'signal': 'ect',
                'direction': 'above',
                'advisory': {'trigger': 100, 'clear': 105},
              }),
          throwsFormatException);
    });
    test('rejects a rule with no levels', () {
      expect(() => WarningRule.fromJson({'id': 'x', 'signal': 'ect', 'direction': 'above'}),
          throwsFormatException);
    });
  });
}
