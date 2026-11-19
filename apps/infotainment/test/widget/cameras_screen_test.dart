import 'package:f250_infotainment/cameras/camera_state.dart';
import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_cameras.dart';
import '../harness.dart';

/// The Cameras screen's truck picker and recording card (ADR-0027,
/// ADR-0037; redesign 2026-11-18).
void main() {
  setUpAll(loadTestAssets);

  RecordingStatus recording({int recorded = 38400000000, int free = 412300000000, int clips = 1200000000}) =>
      RecordingStatus(
        cameras: const [
          CameraRecording(camera: CameraId.front, state: RecordingState.recording, segment: 'b1-s1.mkv'),
          CameraRecording(
              camera: CameraId.rear,
              state: RecordingState.notRecording,
              detail: 'no frame for 1000 ms from /dev/video-rear; camera-manager retries every 10 s'),
        ],
        driveMounted: true,
        driveFreeBytes: free,
        recordedBytes: recorded,
        protectedBytes: clips,
        protectedMaxBytes: 25000000000,
        clockTrusted: true,
      );

  Rect rectOf(WidgetTester tester, String key) => tester.getRect(find.byKey(ValueKey(key)));

  testWidgets('each camera\'s button sits where it is on the truck and sends its move', (tester) async {
    final cams = FakeCameras(up(CameraView.none, recording: recording()));
    final h = await Harness.start(tester, cameras: cams);
    await h.goTo(AppScreen.cameras);
    final truck = rectOf(tester, 'cameras-truck');
    expect(truck.height, greaterThan(kMinTouch), reason: 'the truck is drawn, not a sliver');
    expect(truck.width, greaterThan(kMinTouch));
    final front = rectOf(tester, 'cameras-open-front');
    final rear = rectOf(tester, 'cameras-open-rear');
    final left = rectOf(tester, 'cameras-open-left');
    final right = rectOf(tester, 'cameras-open-right');
    expect(front.bottom, lessThanOrEqualTo(truck.top));
    expect(rear.top, greaterThanOrEqualTo(truck.bottom));
    expect(left.right, lessThanOrEqualTo(truck.left));
    expect(right.left, greaterThanOrEqualTo(truck.right));
    for (final r in [front, rear, left, right]) {
      expect(r.width, greaterThanOrEqualTo(kMinTouch));
      expect(r.height, greaterThanOrEqualTo(kMinTouch));
    }
    for (final (key, move) in [
      ('front', SwitchMove.forward),
      ('left', SwitchMove.left),
      ('rear', SwitchMove.back),
      ('right', SwitchMove.right),
    ]) {
      await tester.tap(find.byKey(ValueKey('cameras-open-$key')));
      await tester.pump();
      expect(cams.moves.last, move, reason: key);
    }
  });

  testWidgets('storage shows as bars: video against the room left for it, clips against their cap',
      (tester) async {
    final cams = FakeCameras(up(CameraView.none, recording: recording()));
    final h = await Harness.start(tester, cameras: cams);
    await h.goTo(AppScreen.cameras);
    LinearProgressIndicator bar(String key) => tester.widget(find.byKey(ValueKey(key)));
    expect(bar('recording-drive-bar').value, closeTo(38.4 / (38.4 + 412.3), 1e-9));
    expect(bar('recording-clips-bar').value, closeTo(1.2 / 25, 1e-9));
    expect(bar('recording-clips-bar').color, Palette.night.ok);

    cams.status = up(CameraView.none, recording: recording(clips: 23000000000));
    await tester.pump();
    expect(bar('recording-clips-bar').color, Palette.night.advisory, reason: 'nearly full');
  });

  testWidgets('Save clip and To USB sit side by side; To USB opens Recordings', (tester) async {
    final cams = FakeCameras(up(CameraView.none, recording: recording()));
    final h = await Harness.start(tester, cameras: cams);
    await h.goTo(AppScreen.cameras);
    final save = rectOf(tester, 'cameras-save-clip');
    final usb = rectOf(tester, 'cameras-recordings');
    expect(save.top, usb.top);
    expect(save.right, lessThan(usb.left));
    // Never cut short (the panel's font cut it to "…mirr…", bench
    // 2026-11-19): it wraps.
    final safety = tester.widget<Text>(find.byKey(const ValueKey('cameras-safety')));
    expect(safety.maxLines, isNull);
    expect(safety.overflow, isNot(TextOverflow.ellipsis));
    expect(
        tester.renderObject<RenderParagraph>(find.byKey(const ValueKey('cameras-safety'))).didExceedMaxLines, isFalse);
    await tester.tap(find.byKey(const ValueKey('cameras-recordings')));
    await tester.pump();
    expect(h.services.screens.value, AppScreen.recordings);
  });

  testWidgets('without camera-manager: no picker, but recordings can still be copied', (tester) async {
    final cams = FakeCameras(const CameraStatus(link: CameraLink.down, detail: 'connection refused'));
    final h = await Harness.start(tester, cameras: cams);
    await h.goTo(AppScreen.cameras);
    expect(find.byKey(const ValueKey('cameras-truck')), findsNothing);
    expect(find.byKey(const ValueKey('cameras-open-front')), findsNothing);
    expect(find.byKey(const ValueKey('cameras-save-clip')), findsNothing);
    expect(find.byKey(const ValueKey('cameras-recordings')), findsOneWidget);
    expect(find.byKey(const ValueKey('cameras-safety')), findsOneWidget);
  });

  for (final theme in DayNight.values) {
    testWidgets('lays out under an alert with long recording lines, ${theme.name}', (tester) async {
      final cams = FakeCameras(up(const CameraView(reverse: ReverseStatus.unknown, blockedBySpeed: true),
          recording: RecordingStatus(
              cameras: recording().cameras,
              driveMounted: false,
              protectedMaxBytes: 25000000000,
              problem: 'Data drive full: the oldest recordings could not be deleted in time')));
      final h = await Harness.start(tester, scenario: 'link_loss', theme: theme, cameras: cams);
      await h.advance(const Duration(seconds: 100));
      await h.goTo(AppScreen.cameras);
      expect(find.byKey(const ValueKey('alert-banner')), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(rectOf(tester, 'cameras-open-rear').height, greaterThanOrEqualTo(kMinTouch));
      await tester.tap(find.byKey(const ValueKey('cameras-save-clip')));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'the result fits the button');
    });
  }
}
