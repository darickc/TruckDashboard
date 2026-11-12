import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/screens/home_screen.dart';
import 'package:f250_infotainment/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

void main() {
  setUpAll(loadTestAssets);

  final back = find.byKey(const ValueKey('nav-back'));
  final home = find.byKey(const ValueKey('nav-home'));

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
  }

  testWidgets('starts on Home: a button for every other screen, no Back', (tester) async {
    final h = await Harness.start(tester);
    expect(find.byKey(const ValueKey('screen-home')), findsOneWidget);
    expect(back, findsNothing);
    expect(home, findsNothing);
    expect(homeButtons.toSet(), AppScreen.values.toSet()..remove(AppScreen.home),
        reason: 'Home reaches every screen');
    for (final screen in homeButtons) {
      final button = find.byKey(ValueKey('home-${screen.name}'));
      expect(button, findsOneWidget, reason: screen.name);
      final size = tester.getSize(button);
      // Large: three across and two down, far above the 60 px minimum.
      expect(size.width, greaterThan(200), reason: screen.name);
      expect(size.height, greaterThan(150), reason: screen.name);
    }
    expect(h.services.screens.value, AppScreen.home);
  });

  testWidgets('no row of screen buttons along the bottom', (tester) async {
    final h = await Harness.start(tester);
    for (final screen in homeButtons) {
      await h.goTo(screen);
      // nav-home too: opened from Home, Back already goes there.
      for (final other in AppScreen.values) {
        expect(find.byKey(ValueKey('nav-${other.name}')), findsNothing,
            reason: '${screen.name}: no nav-${other.name} button');
      }
      expect(find.byKey(const ValueKey('nav-power')), findsNothing);
    }
  });

  testWidgets('every Home button opens its screen, and Back returns to Home', (tester) async {
    final h = await Harness.start(tester);
    for (final screen in homeButtons) {
      await tapKey(tester, 'home-${screen.name}');
      expect(find.byKey(ValueKey('screen-${screen.name}')), findsOneWidget, reason: screen.name);
      expect(h.services.screens.value, screen);
      expect(back, findsOneWidget, reason: screen.name);
      expect(home, findsNothing, reason: '${screen.name}: Back already goes Home');
      await tester.tap(back);
      await tester.pump();
      expect(find.byKey(const ValueKey('screen-home')), findsOneWidget, reason: screen.name);
      expect(back, findsNothing);
    }
  });

  testWidgets('Back is a 60 px target at the top left, under the status bar', (tester) async {
    final h = await Harness.start(tester);
    for (final screen in homeButtons) {
      await h.goTo(screen);
      final r = tester.getRect(back);
      expect(r.left, kGap, reason: screen.name);
      expect(r.top, kStatusBarHeight + kGap, reason: screen.name);
      expect(r.height, greaterThanOrEqualTo(kMinTouch), reason: screen.name);
      expect(r.width, greaterThanOrEqualTo(kMinTouch), reason: screen.name);
    }
  });

  testWidgets('a screen opened from another has Back to it and Home beside Back', (tester) async {
    final h = await Harness.start(tester);
    await tapKey(tester, 'home-settings');
    h.services.screens.open(AppScreen.diagnostics);
    await tester.pump();
    expect(find.byKey(const ValueKey('screen-diagnostics')), findsOneWidget);
    expect(back, findsOneWidget);
    expect(home, findsOneWidget);
    final b = tester.getRect(back), hm = tester.getRect(home);
    expect(hm.left, greaterThan(b.right), reason: 'Home is to the right of Back');
    expect(hm.top, b.top);
    expect(hm.height, greaterThanOrEqualTo(kMinTouch));

    // Back goes to the screen it came from, which then needs no Home.
    await tester.tap(back);
    await tester.pump();
    expect(find.byKey(const ValueKey('screen-settings')), findsOneWidget);
    expect(home, findsNothing);

    // Home goes straight Home.
    h.services.screens.open(AppScreen.gauges);
    await tester.pump();
    await tester.tap(home);
    await tester.pump();
    expect(find.byKey(const ValueKey('screen-home')), findsOneWidget);
    expect(h.services.screens.stack, [AppScreen.home]);
  });

  test('the history never cycles and always starts at Home', () {
    final s = ScreenHistory();
    expect(s.previous, isNull);
    s
      ..back()
      ..home();
    expect(s.stack, [AppScreen.home], reason: 'Back and Home on Home do nothing');
    s
      ..open(AppScreen.settings)
      ..open(AppScreen.diagnostics)
      ..open(AppScreen.gauges);
    expect(s.stack, [AppScreen.home, AppScreen.settings, AppScreen.diagnostics, AppScreen.gauges]);
    s.open(AppScreen.settings);
    expect(s.stack, [AppScreen.home, AppScreen.settings], reason: 'returns rather than stacks twice');
    s.open(AppScreen.settings);
    expect(s.stack, [AppScreen.home, AppScreen.settings], reason: 'the screen showing');
    s.open(AppScreen.home);
    expect(s.stack, [AppScreen.home]);
  });

  testWidgets('the screen title names the screen', (tester) async {
    final h = await Harness.start(tester);
    await h.goTo(AppScreen.navigation);
    expect(h.textOf('screen-title'), 'Nav');
    await h.goTo(AppScreen.diagnostics);
    expect(h.textOf('screen-title'), 'Diagnostics');
  });

  testWidgets('placeholders say they are not implemented', (tester) async {
    final h = await Harness.start(tester);
    for (final screen in [AppScreen.media, AppScreen.navigation]) {
      await h.goTo(screen);
      expect(find.textContaining('not implemented yet'), findsOneWidget, reason: screen.name);
    }
    // Cameras is implemented (camera_mode_test.dart); it still says what it
    // isn't.
    await h.goTo(AppScreen.cameras);
    expect(find.textContaining('not implemented yet'), findsNothing);
    expect(find.textContaining('Not a safety system'), findsOneWidget);
  });

  testWidgets('scenario switch from Developer resets data', (tester) async {
    final h = await Harness.start(tester);
    await h.advance(const Duration(seconds: 10));
    expect(h.store['rpm']!.successes, greaterThan(0));
    await h.goTo(AppScreen.diagnostics);
    await tester.tap(find.byKey(const ValueKey('diag-developer')));
    await tester.pump();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('scenario-link_loss')), 80,
        scrollable: find.byType(Scrollable).last);
    await tester.ensureVisible(find.byKey(const ValueKey('scenario-link_loss')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('scenario-link_loss')));
    await tester.pump();
    expect(h.services.simulation!.current!.id, 'link_loss');
    expect(h.store['rpm']!.successes, 0);
  });

  testWidgets('status bar clock shows AM/PM', (tester) async {
    final h = await Harness.start(tester);
    expect(h.textOf('status-clock'), matches(RegExp(r'^(1[0-2]|[1-9]):[0-5]\d (AM|PM)$')));
  });
}
