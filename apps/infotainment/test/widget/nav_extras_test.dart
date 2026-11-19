import 'package:f250_infotainment/audio/audio_state.dart';
import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/model/signal_catalog.dart';
import 'package:f250_infotainment/model/units.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// The Nav screen's speed and media strip (redesign 2026-11-18), beside its
/// bottom buttons.
void main() {
  setUpAll(loadTestAssets);

  Rect rect(WidgetTester tester, String key) => tester.getRect(find.byKey(ValueKey(key)));

  testWidgets('the speed in the driver\'s units', (tester) async {
    final h = await Harness.start(tester);
    await h.advance(const Duration(seconds: 30));
    await h.goTo(AppScreen.navigation);
    final kmh = h.store['speed']!.value!;
    expect(h.textOf('nav-speed'), formatValue(signalsById['speed']!, kmh, UnitSystem.imperial));
    h.services.settings.units = UnitSystem.metric;
    await tester.pump();
    expect(h.textOf('nav-speed'), formatValue(signalsById['speed']!, kmh, UnitSystem.metric));
  });

  testWidgets('the link goes: the speed isn\'t current, and says nothing else', (tester) async {
    final h = await Harness.start(tester, scenario: 'link_loss');
    await h.advance(const Duration(seconds: 100)); // link down since 90 s
    await h.goTo(AppScreen.navigation);
    expect(h.textOf('nav-speed'), '—');
  });

  testWidgets('the strip: the track, Play/Pause and Next, and a tap opens Media', (tester) async {
    final audio = SimulatedAudioSource(autoRun: false);
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.navigation);
    expect(h.textOf('nav-player-title'), 'Simulated Track One');
    expect(rect(tester, 'nav-player-play-pause').height, greaterThanOrEqualTo(kMinTouch));

    await tester.tap(find.byKey(const ValueKey('nav-player-play-pause')));
    await tester.pump();
    expect(audio.status.value.report!.nowPlaying!.state, PlayState.paused);
    await tester.tap(find.byKey(const ValueKey('nav-player-next')));
    await tester.pump();
    expect(h.textOf('nav-player-title'), isNot('Simulated Track One'));

    await tester.tap(find.byKey(const ValueKey('nav-player-open')));
    await tester.pump();
    expect(h.services.screens.value, AppScreen.media);
  });

  testWidgets('no phone, no strip; the speed stays', (tester) async {
    final audio = SimulatedAudioSource(autoRun: false);
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.navigation);
    await audio.disconnectPhone(audio.status.value.report!.phone!.address);
    await tester.pump();
    expect(find.byKey(const ValueKey('nav-player')), findsNothing);
    expect(find.byKey(const ValueKey('nav-speed')), findsOneWidget);
  });

  testWidgets('beside the buttons, on their row: the truck at the centre stays in sight', (tester) async {
    final h = await Harness.start(tester);
    await h.goTo(AppScreen.navigation);
    final places = rect(tester, 'nav-places-open');
    expect(rect(tester, 'nav-player').left, greaterThan(places.right));
    expect(rect(tester, 'nav-player').center.dy, closeTo(places.center.dy, 6));
    final marker = rect(tester, 'nav-marker-current');
    expect(rect(tester, 'nav-player').top, greaterThan(marker.bottom));
    expect(tester.takeException(), isNull);
  });

  for (final theme in DayNight.values) {
    testWidgets('lays out under an alert, ${theme.name}', (tester) async {
      final h = await Harness.start(tester, scenario: 'link_loss', theme: theme);
      await h.advance(const Duration(seconds: 100));
      await h.goTo(AppScreen.navigation);
      expect(find.byKey(const ValueKey('alert-banner')), findsOneWidget);
      expect(tester.takeException(), isNull);
      // The truck sits at the map's centre while following (48 px marker).
      final centre = tester.getRect(find.byType(FlutterMap)).center;
      expect(rect(tester, 'nav-player').top, greaterThan(centre.dy + 24));
    });
  }
}
