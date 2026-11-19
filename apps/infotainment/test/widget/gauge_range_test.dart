import 'package:f250_infotainment/telemetry/warnings.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/widgets/range_bar.dart';
import 'package:flutter/widgets.dart' hide Threshold;
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// The range bar and peak on digital gauge tiles (ADR-0050).
void main() {
  setUpAll(loadTestAssets);

  group('rangeZones', () {
    const eot = WarningRule(
        id: 'eot',
        signalId: 'eot',
        direction: Direction.above,
        advisory: Threshold(110, 107),
        critical: Threshold(121, 118));
    const ficm = WarningRule(
        id: 'ficm',
        signalId: 'ficm_main',
        direction: Direction.below,
        advisory: Threshold(46, 47),
        critical: Threshold(45, 46));
    const battery = WarningRule(
        id: 'bat', signalId: 'battery', direction: Direction.below, advisory: Threshold(12.4, 12.8));

    test('above: advisory from its trigger to critical, critical to the end', () {
      expect(rangeZones(eot, 40, 130), [
        RangeZone(70 / 90, 81 / 90, AlertLevel.advisory),
        const RangeZone(81 / 90, 1, AlertLevel.critical),
      ]);
    });

    test('below: critical from the start, advisory up to its trigger', () {
      expect(rangeZones(ficm, 40, 52), [
        const RangeZone(0, 5 / 12, AlertLevel.critical),
        const RangeZone(5 / 12, 6 / 12, AlertLevel.advisory),
      ]);
    });

    test('advisory only', () {
      final z = rangeZones(battery, 10, 15);
      expect(z, hasLength(1));
      expect((z.single.from, z.single.level), (0, AlertLevel.advisory));
      expect(z.single.to, closeTo(0.48, 1e-9));
    });

    test('a limit off the scale is clamped, and an empty zone dropped', () {
      expect(rangeZones(eot, 40, 100), isEmpty);
      expect(rangeZones(eot, 40, 115), [RangeZone(70 / 75, 1, AlertLevel.advisory)]);
    });
  });

  RangeBar bar(WidgetTester tester, String id) => tester.widget(find.byKey(ValueKey('range-$id')));

  testWidgets('a current value: zones, a marker where it is, and this drive\'s max', (tester) async {
    final h = await Harness.start(tester);
    await h.advance(const Duration(seconds: 30));
    await h.goTo(AppScreen.gauges);
    final b = bar(tester, 'eot');
    expect(b.zones, hasLength(2));
    final eot = h.store['eot']!.value!;
    expect(b.marker, closeTo(rangeFraction(eot, 40, 130), 1e-9));
    expect(h.textOf('status-eot'), isEmpty);
    expect(h.textOf('peak-eot'), matches(RegExp(r'^max \d+ °F$')));
    final max = int.parse(RegExp(r'\d+').firstMatch(h.textOf('peak-eot')!)!.group(0)!);
    expect(max, greaterThanOrEqualTo(int.parse(h.textOf('value-eot')!)));
  });

  testWidgets('a low-side rule shows the minimum', (tester) async {
    final h = await Harness.start(tester);
    await h.advance(const Duration(seconds: 30));
    await h.goTo(AppScreen.gauges);
    expect(h.textOf('peak-ficm_main'), matches(RegExp(r'^min [\d.]+ V$')));
  });

  testWidgets('a signal with no rule has neither bar nor peak', (tester) async {
    final h = await Harness.start(tester);
    await h.advance(const Duration(seconds: 30));
    await h.goTo(AppScreen.gauges);
    expect(find.byKey(const ValueKey('range-icp')), findsNothing);
    expect(find.byKey(const ValueKey('peak-icp')), findsNothing);
  });

  testWidgets('a frozen value: no marker, and the stale status instead of the peak', (tester) async {
    final h = await Harness.start(tester, scenario: 'eot_ect_freeze');
    await h.goTo(AppScreen.gauges);
    await h.advance(const Duration(seconds: 180)); // frozen since 120 s
    expect(bar(tester, 'eot').marker, isNull);
    expect(h.textOf('status-eot'), startsWith('STALE'));
    expect(find.byKey(const ValueKey('peak-eot')), findsNothing);
    // The delta's inputs are frozen: no marker on it either.
    expect(bar(tester, 'eot_ect_delta').marker, isNull);
  });
}
