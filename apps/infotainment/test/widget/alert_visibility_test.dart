import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

void main() {
  setUpAll(loadTestAssets);

  testWidgets('no banner while healthy', (tester) async {
    final h = await Harness.start(tester, scenario: 'warm_idle');
    await h.advance(const Duration(seconds: 20));
    expect(find.byKey(const ValueKey('alert-banner')), findsNothing);
  });

  testWidgets('link loss shows a critical banner on every screen', (tester) async {
    final h = await Harness.start(tester, scenario: 'link_loss');
    await h.advance(const Duration(seconds: 100));
    for (final screen in AppScreen.values) {
      await h.goTo(screen);
      expect(find.byKey(const ValueKey('alert-banner')), findsOneWidget, reason: screen.name);
      expect(h.textOf('alert-title'), 'Vehicle data lost', reason: screen.name);
    }
    expect(h.textOf('link-state'), 'Link down');
  });

  testWidgets('EOT/ECT freeze names the frozen signal on every screen', (tester) async {
    final h = await Harness.start(tester, scenario: 'eot_ect_freeze');
    await h.advance(const Duration(seconds: 200));
    for (final screen in AppScreen.values) {
      await h.goTo(screen);
      expect(h.textOf('alert-title'), matches(RegExp(r'^(EOT|ECT) not updating$')),
          reason: screen.name);
    }
    expect(h.textOf('link-state'), 'Degraded');
  });

  testWidgets('banner clears when the link recovers', (tester) async {
    final h = await Harness.start(tester, scenario: 'link_loss');
    await h.advance(const Duration(seconds: 100));
    expect(find.byKey(const ValueKey('alert-banner')), findsOneWidget);
    await h.advance(const Duration(seconds: 40));
    expect(find.byKey(const ValueKey('alert-banner')), findsNothing);
  });
}
