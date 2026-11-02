import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

void main() {
  setUpAll(loadTestAssets);

  testWidgets('starts on Home; every nav button opens its screen', (tester) async {
    final h = await Harness.start(tester);
    expect(find.byKey(const ValueKey('screen-home')), findsOneWidget);
    for (final tab in AppTab.values.reversed) {
      await tester.tap(find.byKey(ValueKey('nav-${tab.name}')));
      await tester.pump();
      expect(find.byKey(ValueKey('screen-${tab.name}')), findsOneWidget);
      expect(h.services.tab.value, tab);
    }
  });

  testWidgets('home shortcuts open media, navigation and cameras', (tester) async {
    await Harness.start(tester);
    for (final (key, screen) in [
      ('home-media', 'media'),
      ('home-nav', 'navigation'),
      ('home-cameras', 'cameras'),
    ]) {
      await tester.tap(find.byKey(const ValueKey('nav-home')));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
      expect(find.byKey(ValueKey('screen-$screen')), findsOneWidget);
    }
  });

  testWidgets('placeholders say they are not implemented', (tester) async {
    final h = await Harness.start(tester);
    for (final tab in [AppTab.media, AppTab.navigation, AppTab.cameras]) {
      await h.goTo(tab);
      expect(find.textContaining('not implemented yet'), findsOneWidget, reason: tab.name);
    }
    await h.goTo(AppTab.cameras);
    expect(find.textContaining('not a safety camera'), findsOneWidget);
  });

  testWidgets('scenario switch from Developer resets data', (tester) async {
    final h = await Harness.start(tester);
    await h.advance(const Duration(seconds: 10));
    expect(h.store['rpm']!.successes, greaterThan(0));
    await h.goTo(AppTab.diagnostics);
    await tester.tap(find.byKey(const ValueKey('diag-developer')));
    await tester.pump();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('scenario-link_loss')), 80,
        scrollable: find.byType(Scrollable).last);
    await tester.ensureVisible(find.byKey(const ValueKey('scenario-link_loss')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('scenario-link_loss')));
    await tester.pump();
    expect(h.services.simulation.current!.id, 'link_loss');
    expect(h.store['rpm']!.successes, 0);
  });

  testWidgets('status bar clock shows AM/PM', (tester) async {
    final h = await Harness.start(tester);
    expect(h.textOf('status-clock'), matches(RegExp(r'^(1[0-2]|[1-9]):[0-5]\d (AM|PM)$')));
  });
}
