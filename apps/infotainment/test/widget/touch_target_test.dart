import 'package:f250_infotainment/core/power.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/theme.dart';
import 'package:f250_infotainment/ui/widgets/tap_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

void main() {
  setUpAll(loadTestAssets);

  /// Every tap handler in the tree (InkWell and anything else builds on a
  /// GestureDetector) must sit on a target of at least kMinTouch.
  void expectAllTargetsLargeEnough(WidgetTester tester, String where) {
    final tappable = find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onTap != null,
        skipOffstage: true);
    expect(tappable, findsWidgets, reason: where);
    for (final e in tappable.evaluate()) {
      final size = (e.renderObject! as RenderBox).size;
      final label = e.findAncestorWidgetOfExactType<TapTarget>()?.label ?? e.widget.toString();
      expect(size.width, greaterThanOrEqualTo(kMinTouch - 0.01), reason: '$where: $label');
      expect(size.height, greaterThanOrEqualTo(kMinTouch - 0.01), reason: '$where: $label');
      expect(e.findAncestorWidgetOfExactType<TapTarget>(), isNotNull,
          reason: '$where: tap handler outside TapTarget ($label)');
    }
  }

  testWidgets('every tappable is at least 60×60 on every screen', (tester) async {
    final h = await Harness.start(tester);
    await h.advance(const Duration(seconds: 5));
    for (final screen in AppScreen.values) {
      await h.goTo(screen);
      expectAllTargetsLargeEnough(tester, screen.name);
    }
    for (final section in ['signals', 'link', 'dtcs', 'events', 'developer']) {
      await h.goTo(AppScreen.diagnostics);
      await tester.tap(find.byKey(ValueKey('diag-$section')));
      await tester.pump();
      expectAllTargetsLargeEnough(tester, 'diagnostics/$section');
    }
  });

  testWidgets('Home, Back/Home, Power, Restart and their questions are 60×60 too', (tester) async {
    final h = await Harness.start(tester, power: _AllowPowerOff());
    expectAllTargetsLargeEnough(tester, 'home');
    await h.goTo(AppScreen.settings);
    expectAllTargetsLargeEnough(tester, 'settings with power buttons');
    for (final b in ['settings-power', 'settings-restart']) {
      await tester.tap(find.byKey(ValueKey(b)));
      await tester.pump();
      expectAllTargetsLargeEnough(tester, '$b question');
      await tester.tap(find.byKey(const ValueKey('power-cancel')));
      await tester.pump();
    }
    // Back and Home both showing.
    h.services.screens.open(AppScreen.diagnostics);
    await tester.pump();
    expect(find.byKey(const ValueKey('nav-home')), findsOneWidget);
    expectAllTargetsLargeEnough(tester, 'diagnostics from settings');
  });
}

class _AllowPowerOff implements PowerControl {
  @override
  bool get canPowerOff => true;

  @override
  void powerOff() {}

  @override
  void restart() {}
}
