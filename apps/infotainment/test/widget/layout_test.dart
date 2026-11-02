import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/model/units.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// Every screen, in each data situation and both themes, must lay out at
/// 800×480 with no overflow. Overflow is reported as an exception, which
/// fails the test.
void main() {
  setUpAll(loadTestAssets);

  const situations = {
    'healthy': ('drive_cycle', Duration(seconds: 20)),
    'eot/ect frozen': ('eot_ect_freeze', Duration(seconds: 200)),
    'link lost': ('link_loss', Duration(seconds: 100)),
    'bad responses': ('bad_responses', Duration(seconds: 120)),
    'just started': ('drive_cycle', Duration(milliseconds: 300)),
  };

  for (final theme in DayNight.values) {
    for (final MapEntry(key: name, value: (scenario, at)) in situations.entries) {
      testWidgets('all screens lay out: $name, ${theme.name}', (tester) async {
        final h = await Harness.start(tester, scenario: scenario, theme: theme);
        await h.advance(at);
        for (final tab in AppTab.values) {
          await h.goTo(tab);
          expect(tester.takeException(), isNull, reason: '${tab.name}: $name');
          expect(find.byKey(ValueKey('screen-${tab.name}')), findsOneWidget);
        }
        // Diagnostics sub-sections too.
        await h.goTo(AppTab.diagnostics);
        for (final section in ['signals', 'link', 'dtcs', 'events', 'developer']) {
          await tester.tap(find.byKey(ValueKey('diag-$section')));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: 'diagnostics/$section: $name');
        }
        // Both gauge profiles.
        await h.goTo(AppTab.gauges);
        for (final p in ['engine', 'towing']) {
          await tester.tap(find.byKey(ValueKey('profile-$p')));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: 'gauges/$p: $name');
        }
      });
    }
  }

  testWidgets('metric units lay out too', (tester) async {
    final h = await Harness.start(tester);
    h.services.settings.units = UnitSystem.metric;
    await h.advance(const Duration(seconds: 20));
    for (final tab in AppTab.values) {
      await h.goTo(tab);
      expect(tester.takeException(), isNull);
    }
  });
}
