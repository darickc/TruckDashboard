import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/widgets/stale_hatch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

void main() {
  setUpAll(loadTestAssets);

  testWidgets('current values render plainly', (tester) async {
    final h = await Harness.start(tester, scenario: 'eot_ect_freeze');
    await h.advance(const Duration(seconds: 60));
    await h.goTo(AppScreen.gauges);
    expect(h.textOf('status-eot'), isEmpty);
    expect(h.textOf('value-eot'), matches(RegExp(r'^\d+$')));
    expect(h.textOf('value-eot_ect_delta'), matches(RegExp(r'^-?\d+$')));
    expect(find.byType(StaleHatch), findsNothing);
  });

  testWidgets('a frozen EOT shows its last value, its age and a stale warning',
      (tester) async {
    final h = await Harness.start(tester, scenario: 'eot_ect_freeze');
    await h.goTo(AppScreen.gauges);
    await h.advance(const Duration(seconds: 119));
    final lastEot = h.textOf('value-eot');
    await h.advance(const Duration(seconds: 61)); // t = 180 s, frozen since 120 s
    expect(h.textOf('value-eot'), lastEot, reason: 'last good value stays visible');
    expect(h.textOf('status-eot'), matches(RegExp(r'^STALE · \d+ (s|min)$')));
    expect(h.textOf('status-ect'), startsWith('STALE'));
    expect(find.byType(StaleHatch), findsNWidgets(2));
    // Other gauges keep working.
    expect(h.textOf('status-trans_temp'), isEmpty);
  });

  testWidgets('the EOT−ECT delta disappears rather than use a frozen input', (tester) async {
    final h = await Harness.start(tester, scenario: 'eot_ect_freeze');
    await h.advance(const Duration(seconds: 180));
    await h.goTo(AppScreen.gauges);
    expect(h.textOf('value-eot_ect_delta'), '—');
    expect(h.textOf('status-eot_ect_delta'), contains('stale'));
  });

  testWidgets('gauges and the diagnostics list agree on stale state', (tester) async {
    final h = await Harness.start(tester, scenario: 'eot_ect_freeze');
    await h.advance(const Duration(seconds: 180));
    await h.goTo(AppScreen.gauges);
    expect(h.textOf('status-eot'), startsWith('STALE'));
    await h.goTo(AppScreen.diagnostics);
    expect(find.descendant(
            of: find.byKey(const ValueKey('diag-row-eot')), matching: find.text('STALE')),
        findsOneWidget);
  });

  testWidgets('unsupported and implausible values never show a number', (tester) async {
    final h = await Harness.start(tester, scenario: 'bad_responses');
    await h.advance(const Duration(seconds: 310));
    await h.goTo(AppScreen.gauges);
    expect(h.textOf('value-icp'), '—');
    expect(h.textOf('status-icp'), 'Not supported (NRC 31)');
    expect(h.textOf('value-trans_temp'), '—');
    expect(h.textOf('status-trans_temp'), startsWith('Implausible'));
  });

  testWidgets('a missing aux sensor is listed as disabled, not as no data', (tester) async {
    final h = await Harness.start(tester);
    await h.advance(const Duration(seconds: 5));
    await h.goTo(AppScreen.diagnostics);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('diag-row-egt')), 40,
        scrollable: find.byType(Scrollable).last);
    expect(find.descendant(
            of: find.byKey(const ValueKey('diag-row-egt')), matching: find.text('DISABLED')),
        findsOneWidget);
  });
}
