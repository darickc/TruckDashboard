import 'package:f250_infotainment/audio/audio_state.dart';
import 'package:f250_infotainment/cameras/camera_state.dart';
import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/theme.dart';
import 'package:f250_infotainment/ui/widgets/call_bar.dart';
import 'package:f250_infotainment/ui/widgets/tap_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_cameras.dart';
import '../harness.dart';
import 'media_test.dart' show FakeAudio;

/// Phone calls on the dashboard (ADR-0045 decision 5) [SIM]: the call over
/// every screen, under the alert banner, Answer and Decline, then Mute and
/// Hang up, a waiting call, refusals said, and nothing from a report that
/// isn't current.
void main() {
  setUpAll(loadTestAssets);

  Finder key(String k) => find.byKey(ValueKey(k));

  String callText(WidgetTester tester) {
    final t = tester.widget<Text>(key('call-caller'));
    return t.data ?? t.textSpan!.toPlainText();
  }

  testWidgets('ringing, answered, muted, hung up; the music pauses and resumes', (tester) async {
    final sim = SimulatedAudioSource(autoRun: false);
    final h = await Harness.start(tester, audio: sim);
    expect(key('call-bar'), findsNothing);
    expect(sim.status.value.report!.nowPlaying!.state, PlayState.playing);

    final id = sim.ring();
    await tester.pump();
    // Ringing: the sheet (owner, 2026-11-18), not the bar.
    expect(key('call-sheet'), findsOneWidget);
    expect(key('call-bar'), findsNothing);
    expect(h.textOf('call-status'), 'Incoming call');
    expect(callText(tester), 'Simulated Caller');
    expect(h.textOf('call-detail'), '+15550100 · on Simulated phone');
    expect(key('call-answer'), findsOneWidget);
    expect(key('call-hang-up'), findsOneWidget);
    expect(key('call-mute'), findsNothing, reason: 'nothing to mute before answering');
    expect(sim.status.value.report!.nowPlaying!.state, PlayState.paused);

    await tester.tap(key('call-answer'));
    await tester.pump();
    expect(sim.status.value.report!.call!.id, id);
    expect(key('call-sheet'), findsNothing, reason: 'answered: the bar');
    expect(callText(tester), 'Call  Simulated Caller');
    for (var i = 0; i < 65; i++) {
      sim.tick();
    }
    await tester.pump();
    // The time beside the caller; the details under it.
    expect(h.textOf('call-bar-timer'), '1:05');
    expect(h.textOf('call-detail'), '+15550100 · on Simulated phone');

    await tester.tap(key('call-mute'));
    await tester.pump();
    expect(sim.status.value.report!.calls!.micMuted, isTrue);
    final mute = tester.widget<TapTarget>(key('call-mute'));
    expect((mute.selected, mute.label), (true, 'Unmute the microphone'));
    await tester.tap(key('call-mute'));
    await tester.pump();
    expect(sim.status.value.report!.calls!.micMuted, isFalse);

    await tester.tap(key('call-hang-up'));
    await tester.pump();
    expect(key('call-bar'), findsNothing);
    expect(sim.status.value.report!.nowPlaying!.state, PlayState.playing, reason: 'resumed after the call');
  });

  testWidgets('declined, a waiting call, and the far end hanging up', (tester) async {
    final sim = SimulatedAudioSource(autoRun: false);
    await Harness.start(tester, audio: sim);
    sim.ring(number: '', name: '');
    await tester.pump();
    expect(callText(tester), 'Number withheld');
    expect(tester.widget<TapTarget>(key('call-hang-up')).label, 'Decline: Number withheld');
    await tester.tap(key('call-hang-up'));
    await tester.pump();
    expect(key('call-bar'), findsNothing);

    final first = sim.ring();
    await sim.answerCall(first);
    sim.ring(number: '+15550199', name: 'Second Caller');
    await tester.pump();
    expect(callText(tester), 'Another call  Second Caller');
    final detail = tester.widget<Text>(key('call-detail')).data!;
    expect(detail, contains('1 more on the phone'));
    expect(detail, contains('answer it on the phone'));
    expect(key('call-answer'), findsNothing, reason: 'a waiting call is answered on the phone');
    await tester.tap(key('call-hang-up'));
    await tester.pump();
    expect(callText(tester), 'Call  Simulated Caller');
    sim.endCall(first);
    await tester.pump();
    expect(key('call-bar'), findsNothing);
  });

  testWidgets('on every screen, below the alert banner', (tester) async {
    final sim = SimulatedAudioSource(autoRun: false);
    final h = await Harness.start(tester, scenario: 'link_loss', audio: sim);
    sim.ring();
    for (final screen in AppScreen.values) {
      await h.goTo(screen);
      // The Phone screen shows the call itself, large, and no bar.
      final phone = screen == AppScreen.phones;
      expect(key('call-sheet'), phone ? findsNothing : findsOneWidget, reason: screen.name);
      expect(key('call-view'), phone ? findsOneWidget : findsNothing, reason: screen.name);
      expect(key('call-answer'), findsOneWidget, reason: screen.name);
    }
    await h.goTo(AppScreen.home);
    await h.advance(const Duration(seconds: 100));
    expect(key('alert-banner'), findsOneWidget);
    final banner = tester.getRect(key('alert-banner'));
    final sheet = tester.getRect(key('call-sheet'));
    expect(sheet.top, greaterThanOrEqualTo(banner.bottom), reason: 'vehicle alerts stay on top');
    expect(tester.getSize(key('call-answer')).height, greaterThanOrEqualTo(kMinTouch));
    expect(tester.getSize(key('call-hang-up')).height, greaterThanOrEqualTo(kMinTouch));
  });

  testWidgets('ringing: a sheet with 80 px Decline and Answer; answered: the 68 px bar with icons', (tester) async {
    final sim = SimulatedAudioSource(autoRun: false);
    await Harness.start(tester, audio: sim);
    sim.ring();
    await tester.pump();
    final sheet = tester.getRect(key('call-sheet'));
    expect(sheet.height, CallBar.sheetHeight);
    expect(tester.widget<TapTarget>(key('call-hang-up')).fill, Palette.night.critical);
    expect(tester.widget<TapTarget>(key('call-answer')).fill, Palette.night.ok);
    expect(tester.widget<TapTarget>(key('call-hang-up')).label, 'Decline: Simulated Caller');
    for (final k in ['call-hang-up', 'call-answer']) {
      final r = tester.getRect(key(k));
      expect(r.height, greaterThanOrEqualTo(80), reason: k);
      expect(r.bottom, lessThanOrEqualTo(sheet.bottom), reason: k);
    }
    // Nothing behind it is blocked: the screen below still answers taps.
    expect(find.byKey(const ValueKey('home-settings')).hitTestable(), findsOneWidget);

    await tester.tap(key('call-answer'));
    await tester.pump();
    expect(key('call-sheet'), findsNothing);
    expect(tester.getSize(key('call-bar')).height, 68);
    expect(tester.widget<TapTarget>(key('call-hang-up')).fill, Palette.night.critical);
    final r = tester.getRect(key('call-hang-up'));
    expect(r.height, greaterThanOrEqualTo(kMinTouch));
    expect(r.top, greaterThanOrEqualTo(tester.getRect(key('call-bar')).top));
    expect(r.bottom, lessThanOrEqualTo(tester.getRect(key('call-bar')).bottom));
    expect(find.descendant(of: key('call-hang-up'), matching: find.byType(Text)), findsNothing, reason: 'an icon');
    expect(tester.getSize(key('call-mute')).width, greaterThanOrEqualTo(kMinTouch));
    expect(tester.widget<TapTarget>(key('call-mute')).fill, isNull);
  });

  testWidgets('a refusal is said on the bar; no call from a lost link', (tester) async {
    final fake = FakeAudio()
      ..value = const AudioStatus(
        link: AudioLink.up,
        report: AudioReport(
          phone: Phone(address: 'AA', name: 'Pixel 8', connected: true, paired: true),
          calls: CallsStatus(
            available: true,
            phoneName: 'Pixel 8',
            call: PhoneCall(id: 4, phase: CallPhase.active, number: '+15550100', active: Duration(seconds: 3)),
          ),
        ),
      );
    final h = await Harness.start(tester, audio: fake);
    expect(callText(tester), 'Call  +15550100');
    expect(h.textOf('call-bar-timer'), '0:03');
    expect(h.textOf('call-detail'), 'on Pixel 8');
    await tester.tap(key('call-hang-up'));
    await tester.pump();
    expect(fake.calls, contains('hang up 4'));
    expect(h.textOf('call-detail'), 'The phone didn\'t end the call: InvalidState.');
    await tester.pump(const Duration(seconds: 6));
    expect(h.textOf('call-detail'), 'on Pixel 8', reason: 'the refusal clears');

    fake.value = const AudioStatus(link: AudioLink.down, detail: 'audio-manager stopped answering');
    await tester.pump();
    expect(key('call-bar'), findsNothing);
  });

  testWidgets('the Phones screen says where calls go', (tester) async {
    final fake = FakeAudio()
      ..value = const AudioStatus(
        link: AudioLink.up,
        report: AudioReport(
          phone: Phone(address: 'AA', name: 'Pixel 8', connected: true, paired: true),
          calls: CallsStatus(detail: 'Calls stay on the phone: no call microphone is configured.'),
        ),
      );
    final h = await Harness.start(tester, audio: fake);
    h.services.phoneTab.value = PhoneTab.phones;
    await h.goTo(AppScreen.phones);
    expect(h.textOf('phones-calls'), 'Calls stay on the phone: no call microphone is configured.');
    fake.value = const AudioStatus(
      link: AudioLink.up,
      report: AudioReport(
        phone: Phone(address: 'AA', name: 'Pixel 8', connected: true, paired: true),
        calls: CallsStatus(available: true, phoneName: 'Pixel 8'),
      ),
    );
    await tester.pump();
    expect(h.textOf('phones-calls'), 'Calls on Pixel 8 come to the truck.');
    fake.value = const AudioStatus(link: AudioLink.up, report: AudioReport());
    await tester.pump();
    expect(key('phones-calls'), findsNothing, reason: 'an audio-manager without calls');
  });

  // 800×480, both themes, the longest texts: no overflow.
  const long = 'A Caller With A Very Long Name That Goes On And On';
  final states = {
    'incoming': const PhoneCall(id: 1, phase: CallPhase.incoming, name: long, number: '+15550100123456789'),
    'active': const PhoneCall(id: 1, phase: CallPhase.active, name: long, number: '+1555', active: Duration(hours: 2)),
    'waiting': const PhoneCall(id: 2, phase: CallPhase.waiting, name: long),
    'held': const PhoneCall(id: 3, phase: CallPhase.held, withheld: true),
  };
  for (final theme in DayNight.values) {
    for (final MapEntry(key: name, value: call) in states.entries) {
      testWidgets('the call bar lays out at 800×480: $name, ${theme.name}', (tester) async {
        final fake = FakeAudio()
          ..value = AudioStatus(
            link: AudioLink.up,
            report: AudioReport(
              simulated: true,
              phone: const Phone(address: 'AA', name: long, connected: true, paired: true),
              calls: CallsStatus(available: true, phoneName: long, call: call, otherCalls: 3, micMuted: true),
            ),
          );
        await Harness.start(tester, theme: theme, audio: fake);
        expect(tester.takeException(), isNull);
        if (name == 'incoming') {
          expect(key('call-sheet'), findsOneWidget);
          expect(tester.getSize(key('call-sheet')), const Size(800, CallBar.sheetHeight), reason: 'with its 8 px margins');
        } else {
          expect(key('call-bar'), findsOneWidget);
          expect(tester.getSize(key('call-bar')), const Size(800, CallBar.height));
        }
        expect(Palette.of(tester.element(key(name == 'incoming' ? 'call-sheet' : 'call-bar'))).background,
            theme == DayNight.day ? Palette.day.background : Palette.night.background);
      });
    }
  }

  // Camera mode (ADR-0045 amendment): the camera's window covers x 220–800,
  // so the call goes in the left column, and the cameras stay reachable.
  const rearLive = CameraView(camera: CameraId.rear, reason: CameraReason.cameraSwitch, feed: FeedState.live);
  const cameraWindow = Rect.fromLTWH(220, 44, 580, 436);
  final recording = RecordingStatus(
    cameras: const [
      CameraRecording(camera: CameraId.rear, state: RecordingState.recording, segment: 'b00042-s000317.mkv'),
    ],
    driveMounted: true,
    driveFreeBytes: 412300000000,
    recordedBytes: 38400000000,
    protectedBytes: 1200000000,
    protectedMaxBytes: 25000000000,
    clockTrusted: true,
  );

  testWidgets('camera mode: the call in the column, the cameras as arrows, the window untouched', (tester) async {
    final sim = SimulatedAudioSource(autoRun: false);
    final cams = FakeCameras(up(rearLive));
    await Harness.start(tester, audio: sim, cameras: cams);
    expect(key('camera-area'), findsOneWidget);
    expect(key('call-bar'), findsNothing);
    expect(find.descendant(of: key('camera-front'), matching: find.text('Front')), findsOneWidget);

    final id = sim.ring();
    await tester.pump();
    final bar = tester.getRect(key('call-bar'));
    expect(bar.right, lessThanOrEqualTo(220), reason: 'never over the camera\'s window');
    expect(bar.top, greaterThanOrEqualTo(44));
    expect(tester.getRect(key('camera-area')), cameraWindow);
    expect(callText(tester), 'Simulated Caller');
    for (final k in ['call-answer', 'call-hang-up']) {
      final r = tester.getRect(key(k));
      expect(r.height, greaterThanOrEqualTo(kMinTouch), reason: k);
      expect(r.right, lessThanOrEqualTo(220), reason: k);
    }
    // Every camera is still a button, an arrow now, and still switches.
    for (final c in ['camera-front', 'camera-left', 'camera-rear', 'camera-right', 'camera-close']) {
      expect(tester.getSize(key(c)).height, greaterThanOrEqualTo(kMinTouch), reason: c);
    }
    expect(find.descendant(of: key('camera-front'), matching: find.text('Front')), findsNothing);
    await tester.tap(key('camera-left'));
    await tester.pump();
    expect(cams.moves, [SwitchMove.left]);

    await tester.tap(key('call-answer'));
    await tester.pump();
    expect(sim.status.value.report!.call!.phase, CallPhase.active);
    expect(key('call-mute'), findsOneWidget);
    await sim.hangUp(id);
    await tester.pump();
    expect(key('call-bar'), findsNothing);
    expect(find.descendant(of: key('camera-front'), matching: find.text('Front')), findsOneWidget,
        reason: 'the column is back as it was');
  });

  for (final theme in DayNight.values) {
    testWidgets('camera mode with a call lays out at 800×480: ${theme.name}', (tester) async {
      final cams = FakeCameras(up(rearLive));
      final audio = FakeAudio();
      final h = await Harness.start(tester, scenario: 'link_loss', theme: theme, cameras: cams, audio: audio);
      for (final alert in [false, true]) {
        if (alert) await h.advance(const Duration(seconds: 100));
        for (final rec in [null, recording]) {
          cams.status = up(rearLive, recording: rec);
          for (final call in states.values) {
            audio.value = AudioStatus(
              link: AudioLink.up,
              report: AudioReport(
                simulated: true,
                phone: const Phone(address: 'AA', name: long, connected: true, paired: true),
                calls: CallsStatus(available: true, phoneName: long, call: call, otherCalls: 3, micMuted: true),
              ),
            );
            await tester.pump();
            final why = '${call.phase} rec=${rec != null} alert=$alert';
            expect(tester.takeException(), isNull, reason: why);
            expect(tester.getRect(key('camera-area')), cameraWindow, reason: why);
            expect(tester.getRect(key('camera-controls')), const Rect.fromLTWH(0, 44, 220, 436), reason: why);
            expect(tester.getRect(key('call-bar')).right, lessThanOrEqualTo(220), reason: why);
            for (final c in ['camera-front', 'camera-left', 'camera-rear', 'camera-right', 'camera-close',
              if (rec != null) 'camera-save-clip']) {
              expect(tester.getSize(key(c)).height, greaterThanOrEqualTo(kMinTouch), reason: '$why $c');
            }
          }
        }
      }
    });
  }
}
