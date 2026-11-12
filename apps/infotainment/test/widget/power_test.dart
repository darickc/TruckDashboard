import 'package:f250_infotainment/core/power.dart';
import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/theme.dart';
import 'package:f250_infotainment/ui/widgets/power_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// Records shutdown and restart requests instead of exiting the test process.
class FakePowerControl implements PowerControl {
  int powerOffs = 0;
  int restarts = 0;

  @override
  bool get canPowerOff => true;

  @override
  void powerOff() => powerOffs++;

  @override
  void restart() => restarts++;
}

void main() {
  setUpAll(loadTestAssets);

  final power = find.byKey(const ValueKey('settings-power'));
  final restart = find.byKey(const ValueKey('settings-restart'));
  final confirm = find.byKey(const ValueKey('power-confirm'));
  final cancel = find.byKey(const ValueKey('power-cancel'));
  final question = find.byKey(const ValueKey('power-question'));

  Future<Harness> onSettings(WidgetTester tester,
      {PowerControl? control, String scenario = 'drive_cycle', DayNight theme = DayNight.night}) async {
    final h = await Harness.start(tester,
        power: control ?? FakePowerControl(), scenario: scenario, theme: theme);
    await h.goTo(AppScreen.settings);
    return h;
  }

  testWidgets('the exit codes are distinct and match the launchers', (tester) async {
    expect(powerOffExitCode, 42);
    expect(restartExitCode, 43);
  });

  testWidgets('no Power or Restart unless the launcher allows them', (tester) async {
    final h = await Harness.start(tester);
    await h.goTo(AppScreen.settings);
    expect(power, findsNothing);
    expect(restart, findsNothing);
    expect(find.byKey(const ValueKey('settings-display')), findsOneWidget);
  });

  testWidgets('Power and Restart are on Settings only, side by side, at least 60×60',
      (tester) async {
    final h = await Harness.start(tester, power: FakePowerControl());
    for (final screen in AppScreen.values) {
      await h.goTo(screen);
      final want = screen == AppScreen.settings ? findsOneWidget : findsNothing;
      expect(power, want, reason: screen.name);
      expect(restart, want, reason: screen.name);
    }
    await h.goTo(AppScreen.settings);
    final p = tester.getRect(power), r = tester.getRect(restart);
    for (final b in [p, r]) {
      expect(b.width, greaterThanOrEqualTo(kMinTouch));
      expect(b.height, greaterThanOrEqualTo(kMinTouch));
    }
    expect(r.top, p.top, reason: 'same row');
    expect(r.right, lessThan(p.left), reason: 'Restart next to Power, on its left');
    expect(tester.takeException(), isNull);
  });

  for (final (button, label, action) in [
    ('settings-power', 'shutting down', 'Shut down'),
    ('settings-restart', 'restarting', 'Restart'),
  ]) {
    testWidgets('$label takes a second, confirming tap', (tester) async {
      final fake = FakePowerControl();
      await onSettings(tester, control: fake);
      await tester.tap(find.byKey(ValueKey(button)));
      await tester.pump();
      expect(fake.powerOffs + fake.restarts, 0, reason: 'one tap only asks');
      expect(question, findsOneWidget);
      expect(find.text('$action the head unit? Data is saved first.'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-display')), findsNothing,
          reason: 'the question takes the row');
      expect(find.byKey(const ValueKey('nav-back')), findsOneWidget, reason: 'Back stays');
      expect(tester.getSize(confirm).height, greaterThanOrEqualTo(kMinTouch));
      expect(tester.getSize(cancel).height, greaterThanOrEqualTo(kMinTouch));

      await tester.tap(confirm);
      await tester.pump();
      expect(fake.powerOffs, button == 'settings-power' ? 1 : 0);
      expect(fake.restarts, button == 'settings-restart' ? 1 : 0);
      expect(find.byKey(const ValueKey('power-progress')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancel $label brings the sections back', (tester) async {
      final fake = FakePowerControl();
      await onSettings(tester, control: fake);
      await tester.tap(find.byKey(ValueKey(button)));
      await tester.pump();
      await tester.tap(cancel);
      await tester.pump();
      expect(fake.powerOffs + fake.restarts, 0);
      expect(find.byKey(const ValueKey('settings-display')), findsOneWidget);
      expect(power, findsOneWidget);
      expect(restart, findsOneWidget);
    });
  }

  testWidgets('an unanswered question goes away by itself', (tester) async {
    final fake = FakePowerControl();
    await onSettings(tester, control: fake);
    await tester.tap(power);
    await tester.pump();
    await tester.pump(kPowerConfirmTimeout - const Duration(milliseconds: 100));
    expect(confirm, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(confirm, findsNothing);
    expect(fake.powerOffs, 0);
  });

  testWidgets('the alert banner stays visible while the question is up', (tester) async {
    final h = await onSettings(tester, scenario: 'link_loss');
    await h.advance(const Duration(seconds: 100));
    expect(find.byKey(const ValueKey('alert-banner')), findsOneWidget);
    await tester.tap(restart);
    await tester.pump();
    expect(question, findsOneWidget);
    expect(find.byKey(const ValueKey('alert-banner')), findsOneWidget);
    expect(h.textOf('alert-title'), 'Vehicle data lost');
  });

  for (final theme in DayNight.values) {
    testWidgets('the question lays out at 800×480: ${theme.name}', (tester) async {
      await onSettings(tester, theme: theme);
      for (final b in [power, restart]) {
        await tester.tap(b);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.tap(cancel);
        await tester.pump();
      }
      await tester.tap(power);
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'shutting-down message');
    });
  }
}
