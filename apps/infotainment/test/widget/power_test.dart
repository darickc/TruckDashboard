import 'package:f250_infotainment/core/power.dart';
import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/shell/nav_bar.dart';
import 'package:f250_infotainment/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// Records shutdown requests instead of exiting the test process.
class FakePowerControl implements PowerControl {
  int requests = 0;

  @override
  bool get canPowerOff => true;

  @override
  void powerOff() => requests++;
}

void main() {
  setUpAll(loadTestAssets);

  final power = find.byKey(const ValueKey('nav-power'));
  final confirm = find.byKey(const ValueKey('shutdown-confirm'));
  final cancel = find.byKey(const ValueKey('shutdown-cancel'));

  testWidgets('no power button unless the launcher allows a shutdown', (tester) async {
    await Harness.start(tester);
    expect(power, findsNothing);
  });

  testWidgets('power button is on every screen and at least 60×60', (tester) async {
    final h = await Harness.start(tester, power: FakePowerControl());
    for (final tab in AppTab.values) {
      await h.goTo(tab);
      expect(power, findsOneWidget, reason: tab.name);
      final size = tester.getSize(power);
      expect(size.width, greaterThanOrEqualTo(kMinTouch), reason: tab.name);
      expect(size.height, greaterThanOrEqualTo(kMinTouch), reason: tab.name);
      expect(tester.takeException(), isNull, reason: tab.name);
    }
  });

  testWidgets('shutting down takes a second, confirming tap', (tester) async {
    final fake = FakePowerControl();
    await Harness.start(tester, power: fake);
    await tester.tap(power);
    await tester.pump();
    expect(fake.requests, 0, reason: 'one tap only asks');
    expect(find.byKey(const ValueKey('shutdown-question')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-home')), findsNothing, reason: 'the question replaces the tabs');
    expect(tester.getSize(confirm).height, greaterThanOrEqualTo(kMinTouch));
    expect(tester.getSize(cancel).height, greaterThanOrEqualTo(kMinTouch));

    await tester.tap(confirm);
    await tester.pump();
    expect(fake.requests, 1);
    expect(find.byKey(const ValueKey('shutdown-progress')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel brings the tabs back without shutting down', (tester) async {
    final fake = FakePowerControl();
    await Harness.start(tester, power: fake);
    await tester.tap(power);
    await tester.pump();
    await tester.tap(cancel);
    await tester.pump();
    expect(fake.requests, 0);
    expect(find.byKey(const ValueKey('nav-home')), findsOneWidget);
    expect(power, findsOneWidget);
  });

  testWidgets('an unanswered question goes away by itself', (tester) async {
    final fake = FakePowerControl();
    await Harness.start(tester, power: fake);
    await tester.tap(power);
    await tester.pump();
    await tester.pump(kShutdownConfirmTimeout - const Duration(milliseconds: 100));
    expect(confirm, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(confirm, findsNothing);
    expect(fake.requests, 0);
  });

  testWidgets('the alert banner stays visible while the question is up', (tester) async {
    final h = await Harness.start(tester, scenario: 'link_loss', power: FakePowerControl());
    await h.advance(const Duration(seconds: 100));
    expect(find.byKey(const ValueKey('alert-banner')), findsOneWidget);
    await tester.tap(power);
    await tester.pump();
    expect(find.byKey(const ValueKey('shutdown-question')), findsOneWidget);
    expect(find.byKey(const ValueKey('alert-banner')), findsOneWidget);
    expect(h.textOf('alert-title'), 'Vehicle data lost');
  });

  for (final theme in DayNight.values) {
    testWidgets('the question lays out at 800×480: ${theme.name}', (tester) async {
      await Harness.start(tester, theme: theme, power: FakePowerControl());
      await tester.tap(power);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(confirm);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'shutting-down message');
    });
  }
}
