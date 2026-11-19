import 'package:f250_infotainment/audio/audio_state.dart';
import 'package:f250_infotainment/cameras/camera_state.dart';
import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/display/display_state.dart';
import 'package:f250_infotainment/nav/position_state.dart';
import 'package:f250_infotainment/nav/route_state.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/screens/home_screen.dart';
import 'package:f250_infotainment/ui/widgets/badges.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// Home's live lines (ADR-0034 amendment, 2026-11-18): each button says what
/// the screen it opens would show, and never a value that isn't current.
String? gaugesBadge(WidgetTester tester) {
  final f = find.byKey(const ValueKey('home-badge-gauges'));
  return f.evaluate().isEmpty ? null : (tester.widget(f) as Pill).text;
}

void main() {
  setUpAll(loadTestAssets);

  group('Gauges', () {
    testWidgets('normal: the badge says so and the first two tiles read current values',
        (tester) async {
      final h = await Harness.start(tester);
      await h.advance(const Duration(seconds: 30));
      expect(gaugesBadge(tester), 'NORMAL');
      expect(h.textOf('home-line-gauges'), matches(RegExp(r'^EOT \d+ °F · ECT \d+ °F$')));
    });

    testWidgets('before any data: connecting, values as dashes', (tester) async {
      final h = await Harness.start(tester);
      expect(gaugesBadge(tester), 'CONNECTING');
      expect(h.textOf('home-line-gauges'), 'EOT — · ECT —');
    });

    testWidgets('a frozen EOT/ECT: the alert, and dashes instead of the stale readings',
        (tester) async {
      final h = await Harness.start(tester, scenario: 'eot_ect_freeze');
      await h.advance(const Duration(seconds: 180)); // frozen since 120 s
      expect(gaugesBadge(tester), anyOf('ADVISORY', 'CRITICAL'));
      expect(h.textOf('home-line-gauges'), contains('not updating'));
      expect(h.textOf('home-line2-gauges'), 'EOT — · ECT —');
    });

    testWidgets('follows the selected gauge profile', (tester) async {
      final h = await Harness.start(tester);
      h.services.settings.profileId = 'towing';
      await h.advance(const Duration(seconds: 30));
      expect(h.textOf('home-line-gauges'), matches(RegExp(r'^Trans \d+ °F · EOT \d+ °F$')));
    });
  });

  testWidgets('every button has a line, and still opens its screen', (tester) async {
    final h = await Harness.start(tester);
    await h.advance(const Duration(seconds: 5));
    for (final screen in homeButtons) {
      expect(find.byKey(ValueKey('home-line-${screen.name}')), findsOneWidget, reason: screen.name);
    }
    await tester.tap(find.byKey(const ValueKey('home-cameras')));
    await tester.pump();
    expect(h.services.screens.value, AppScreen.cameras);
  });

  group('Media', () {
    const phone = Phone(address: 'a', name: 'Pixel', connected: true, paired: true);
    test('playing track', () {
      final s = mediaStatus(const AudioStatus(
          link: AudioLink.up,
          report: AudioReport(
              phone: phone,
              nowPlaying: NowPlaying(title: 'Song', artist: 'Band', state: PlayState.playing))));
      expect((s.badge, s.line, s.line2), ('PLAYING', 'Song', 'Band'));
    });
    test('paused', () {
      final s = mediaStatus(const AudioStatus(
          link: AudioLink.up,
          report: AudioReport(phone: phone, nowPlaying: NowPlaying(title: 'Song', state: PlayState.paused))));
      expect(s.badge, 'PAUSED');
    });
    test('nothing playing, no phone, offline, connecting', () {
      expect(mediaStatus(const AudioStatus(link: AudioLink.up, report: AudioReport(phone: phone))).line,
          'Nothing playing');
      expect(mediaStatus(const AudioStatus(link: AudioLink.up, report: AudioReport())).line, 'No phone connected');
      expect(mediaStatus(const AudioStatus(link: AudioLink.down)).badge, 'OFFLINE');
      expect(mediaStatus(const AudioStatus(link: AudioLink.connecting)).line, 'Connecting…');
    });
  });

  group('Phone', () {
    const phone = Phone(address: 'a', name: 'Pixel', connected: true, paired: true);
    test('connected', () {
      final s = phoneStatus(const AudioStatus(link: AudioLink.up, report: AudioReport(phone: phone)));
      expect((s.badge, s.line), ('CONNECTED', 'Pixel'));
    });
    test('no phone, connecting one', () {
      final s = phoneStatus(const AudioStatus(
          link: AudioLink.up, report: AudioReport(connect: ConnectStatus(address: 'b', name: 'Old'))));
      expect((s.badge, s.line, s.line2), (null, 'No phone connected', 'Connecting Old…'));
    });
    test('Bluetooth not ready, offline', () {
      expect(
          phoneStatus(const AudioStatus(
                  link: AudioLink.up, report: AudioReport(bluetoothReady: false, bluetoothDetail: 'no adapter')))
              .line,
          'no adapter');
      expect(phoneStatus(const AudioStatus(link: AudioLink.down)).badge, 'OFFLINE');
    });
  });

  group('Cameras', () {
    RecordingStatus rec(List<(CameraId, RecordingState)> cams) => RecordingStatus(
        cameras: [for (final (c, s) in cams) CameraRecording(camera: c, state: s)]);
    test('recording', () {
      final s = camerasStatus(CameraStatus(
          link: CameraLink.up,
          recording: rec([(CameraId.front, RecordingState.recording), (CameraId.rear, RecordingState.recording)])));
      expect((s.badge, s.badgeTone, s.line), ('REC', HomeTone.critical, 'Recording front, rear'));
    });
    test('simulated recording is marked SIM', () {
      final s = camerasStatus(CameraStatus(
          link: CameraLink.up, simulated: true, recording: rec([(CameraId.front, RecordingState.recording)])));
      expect((s.badge, s.badgeTone), ('SIM REC', HomeTone.simulated));
    });
    test('a camera set to record that is not', () {
      final s = camerasStatus(CameraStatus(
          link: CameraLink.up,
          recording: rec([(CameraId.front, RecordingState.recording), (CameraId.rear, RecordingState.notRecording)])));
      expect((s.badge, s.line, s.lineTone), ('NOT REC', 'Not recording: rear', HomeTone.advisory));
    });
    test('offline, connecting', () {
      expect(camerasStatus(const CameraStatus(link: CameraLink.down)).badge, 'OFFLINE');
      expect(camerasStatus(const CameraStatus(link: CameraLink.connecting)).badge, isNull);
    });
  });

  group('Nav', () {
    const fix = PositionState(
        link: PositionLink.connected,
        report: PositionReport(
            status: FixStatus.fix3d, receivedAt: Duration.zero, current: true, staleAfter: Duration(seconds: 3)));
    RouteView route(RouteState state, {String to = ''}) => RouteView(
        link: RouteLink.connected,
        guidance: Guidance(state: state, receivedAt: Duration.zero, destinationName: to));
    test('active route names the destination, and no distances', () {
      final s = navStatus(route(RouteState.active, to: 'Home'), fix);
      expect((s.badge, s.line, s.line2), ('ROUTE', 'To Home', ''));
    });
    test('routing, arrived, failed', () {
      expect(navStatus(route(RouteState.routing), fix).line, 'Finding a route…');
      expect(navStatus(route(RouteState.arrived, to: 'Shop'), fix).badge, 'ARRIVED');
      expect(navStatus(route(RouteState.failed), fix).badge, 'NO ROUTE');
    });
    test('no route: the GPS state', () {
      const idle = RouteView(link: RouteLink.connected);
      expect(navStatus(idle, fix).badge, 'GPS FIX');
      expect(
          navStatus(
                  idle,
                  const PositionState(
                      link: PositionLink.connected,
                      report: PositionReport(
                          status: FixStatus.fix3d,
                          receivedAt: Duration.zero,
                          current: false,
                          staleAfter: Duration(seconds: 3))))
              .badge,
          'GPS STALE');
      expect(
          navStatus(
                  idle,
                  const PositionState(
                      link: PositionLink.connected,
                      report: PositionReport(
                          status: FixStatus.noFix,
                          receivedAt: Duration.zero,
                          current: true,
                          staleAfter: Duration(seconds: 3))))
              .badge,
          'NO FIX');
      expect(navStatus(idle, const PositionState(link: PositionLink.lost)).badge, 'NO GPS');
    });
  });

  test('Settings: the theme and its brightness', () {
    expect(
        settingsStatus(const DisplayStatus(
                link: DisplayLink.simulated, mode: DayNight.night, choice: DisplayChoice.night, nightPct: 40))
            .line,
        'Night · 40 %');
    expect(
        settingsStatus(const DisplayStatus(link: DisplayLink.simulated, mode: DayNight.day, choice: DisplayChoice.auto))
            .line,
        'Auto: Day');
  });
}
