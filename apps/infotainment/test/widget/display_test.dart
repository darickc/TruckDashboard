import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/display/display_state.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// A display source whose state the test sets, recording what it is asked.
class FakeDisplaySource implements DisplaySource {
  FakeDisplaySource(DisplayStatus initial) : _status = ValueNotifier(initial);

  final ValueNotifier<DisplayStatus> _status;
  final choices = <DisplayChoice>[];
  final levels = <(DayNight, int)>[];

  set value(DisplayStatus s) => _status.value = s;

  @override
  ValueListenable<DisplayStatus> get status => _status;

  @override
  void start() {}

  @override
  void stop() {}

  @override
  Future<void> setChoice(DisplayChoice choice) async => choices.add(choice);

  @override
  Future<void> setBrightness(DayNight mode, int pct) async => levels.add((mode, pct));
}

DisplayReport report({
  DayNight mode = DayNight.night,
  DisplayChoice choice = DisplayChoice.auto,
  ModeBasis basis = ModeBasis.sun,
  SunStatus sun = SunStatus.known,
  double? elevation = -8.4,
  String? backlight = '10-0045',
  String problem = '',
}) =>
    DisplayReport(
      mode: mode,
      choice: choice,
      basis: basis,
      sun: sun,
      sunElevationDeg: sun == SunStatus.known ? elevation : null,
      dayPct: 100,
      nightPct: 40,
      minPct: 10,
      backlight: backlight,
      brightnessPct: mode == DayNight.day ? 100 : 40,
      backlightProblem: problem,
    );

DisplayStatus connected(DisplayReport r) => DisplayStatus(
    link: DisplayLink.connected,
    mode: r.mode,
    choice: r.choice,
    report: r,
    dayPct: r.dayPct,
    nightPct: r.nightPct,
    minPct: r.minPct);

const lost = DisplayStatus(
    link: DisplayLink.lost,
    mode: DayNight.night,
    choice: DisplayChoice.auto,
    detail: 'connection refused');

Future<void> openDisplay(WidgetTester tester, Harness h) async {
  await h.goTo(AppScreen.settings);
  await tester.tap(find.byKey(const ValueKey('settings-display')));
  await tester.pump();
  await tester.scrollUntilVisible(find.byKey(const ValueKey('brightness-level')), 80,
      scrollable: find.byType(Scrollable).last);
  await tester.pump();
}

Color background(WidgetTester tester) {
  final ctx = tester.element(find.byKey(const ValueKey('display-detail')));
  return Palette.of(ctx).background;
}

void main() {
  setUpAll(loadTestAssets);

  testWidgets('simulated: Day and Night by hand, no Auto, and levels kept', (tester) async {
    final h = await Harness.start(tester);
    await openDisplay(tester, h);
    expect(find.byKey(const ValueKey('display-auto')), findsNothing);
    expect(h.textOf('display-detail'), contains('Simulated: no power-manager'));
    expect(background(tester), Palette.night.background);
    expect(h.textOf('brightness-level'), 'Brightness (night) 40 %');

    await tester.tap(find.byKey(const ValueKey('display-day')));
    await tester.pumpAndSettle();
    expect(h.services.display.status.value.mode, DayNight.day);
    expect(background(tester), Palette.day.background);
    expect(h.textOf('brightness-level'), 'Brightness (day) 100 %');

    await tester.tap(find.byKey(const ValueKey('brightness-up')));
    await tester.pump();
    expect(h.textOf('brightness-level'), 'Brightness (day) 100 %', reason: 'capped at 100');
    for (var i = 0; i < 12; i++) {
      await tester.tap(find.byKey(const ValueKey('brightness-down')));
      await tester.pump();
    }
    expect(h.textOf('brightness-level'), 'Brightness (day) 10 %', reason: 'never below the floor');
  });

  testWidgets('connected: Auto offered, the theme follows power-manager, changes are sent',
      (tester) async {
    final fake = FakeDisplaySource(connected(report()));
    final h = await Harness.start(tester, display: fake);
    await openDisplay(tester, h);
    expect(find.byKey(const ValueKey('display-auto')), findsOneWidget);
    expect(h.textOf('display-detail'), 'Auto: Night by the sun (sun −8.4°).');
    expect(background(tester), Palette.night.background);
    expect(find.byKey(const ValueKey('display-backlight')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('display-day')));
    await tester.tap(find.byKey(const ValueKey('brightness-down')));
    await tester.pump();
    expect(fake.choices, [DisplayChoice.day]);
    expect(fake.levels, [(DayNight.night, 30)]);

    fake.value = connected(report(mode: DayNight.day, choice: DisplayChoice.day, basis: ModeBasis.manual, elevation: 12.0));
    await tester.pumpAndSettle();
    expect(background(tester), Palette.day.background);
    expect(h.textOf('display-detail'), 'Day, chosen by hand (sun 12.0°).');
  });

  testWidgets('connected: why Auto can\'t follow the sun, and backlight trouble', (tester) async {
    final fake = FakeDisplaySource(connected(report(
        mode: DayNight.day, basis: ModeBasis.fallback, sun: SunStatus.clockNotSynchronized)));
    final h = await Harness.start(tester, display: fake);
    await openDisplay(tester, h);
    expect(h.textOf('display-detail'),
        'Auto unavailable: clock not synchronized. Showing Day.');

    fake.value = connected(report(
        mode: DayNight.day, basis: ModeBasis.fallback, sun: SunStatus.noLocation));
    await tester.pump();
    expect(h.textOf('display-detail'), contains('no location configured'));

    fake.value = connected(report(problem: "can't write brightness: permission denied"));
    await tester.pump();
    expect(h.textOf('display-backlight'),
        "Backlight 10-0045: can't write brightness: permission denied.");

    fake.value = connected(report(backlight: null, problem: 'no backlight device'));
    await tester.pump();
    expect(h.textOf('display-backlight'), 'No backlight: no backlight device.');
  });

  testWidgets('lost: the theme stays, nothing claims control, Auto is not offered',
      (tester) async {
    final fake = FakeDisplaySource(lost);
    final h = await Harness.start(tester, display: fake);
    await openDisplay(tester, h);
    expect(background(tester), Palette.night.background);
    expect(find.byKey(const ValueKey('display-auto')), findsNothing);
    expect(h.textOf('display-detail'), contains('power-manager not connected (connection refused)'));
    expect(h.textOf('display-detail'), contains('isn\'t controlled'));
    expect(h.textOf('brightness-level'), 'Brightness: not controlled');
    expect(find.byKey(const ValueKey('brightness-up')), findsNothing);
  });

  // 800×480, both themes, every display state: no overflow.
  final states = {
    'simulated': null,
    'sun': connected(report()),
    'fallback': connected(report(basis: ModeBasis.fallback, sun: SunStatus.clockNotSet)),
    'backlight problem': connected(report(problem: 'x' * 120)),
    'lost': lost,
  };
  for (final theme in DayNight.values) {
    for (final MapEntry(key: name, value: st) in states.entries) {
      testWidgets('the display settings lay out at 800×480: $name, ${theme.name}', (tester) async {
        final display = st == null
            ? SimulatedDisplaySource(mode: theme)
            : FakeDisplaySource(DisplayStatus(
                link: st.link,
                mode: theme,
                choice: st.choice,
                report: st.report,
                dayPct: st.dayPct,
                nightPct: st.nightPct,
                minPct: st.minPct,
                detail: st.detail));
        final h = await Harness.start(tester, display: display);
        await openDisplay(tester, h);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('display-detail')), findsOneWidget);
      });
    }
  }
}
