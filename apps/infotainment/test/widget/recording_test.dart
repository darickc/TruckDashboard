import 'package:f250_infotainment/cameras/camera_state.dart';
import 'package:f250_infotainment/cameras/simulated_camera_source.dart';
import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/theme.dart';
import 'package:f250_infotainment/ui/widgets/save_clip_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_cameras.dart';
import '../harness.dart';

/// Front and rear recording on the dashboard (ADR-0027 decision 9): REC only
/// as camera-manager reports it, an advisory when a recorded camera isn't,
/// and "Save clip". `[SIM]`.

const frontRec = CameraRecording(
    camera: CameraId.front, state: RecordingState.recording, segment: 'b00042-s000317.mkv');
const rearRec = CameraRecording(
    camera: CameraId.rear, state: RecordingState.recording, segment: 'b00042-s000317.mkv');
const rearDown = CameraRecording(
    camera: CameraId.rear, state: RecordingState.notRecording, detail: 'no frame for 1000 ms');

RecordingStatus rec(List<CameraRecording> cams,
        {bool drive = true, bool clock = true, String problem = '', int pending = 0}) =>
    RecordingStatus(
      cameras: cams,
      driveMounted: drive,
      driveFreeBytes: 412300000000,
      recordedBytes: 38400000000,
      protectedBytes: 1200000000,
      protectedMaxBytes: 25000000000,
      clockTrusted: clock,
      problem: problem,
      clipSegmentsPending: pending,
    );

const rearLive = CameraView(camera: CameraId.rear, reason: CameraReason.cameraSwitch, feed: FeedState.live);

String? pillText(WidgetTester tester, String key) {
  final f = find.byKey(ValueKey(key));
  if (f.evaluate().isEmpty) return null;
  return tester.widget<Text>(find.descendant(of: f, matching: find.byType(Text))).data;
}

void main() {
  setUpAll(loadTestAssets);

  testWidgets('the clock stays at the right edge with and without REC', (tester) async {
    final cams = FakeCameras(up(CameraView.none, recording: rec([frontRec, rearRec])));
    await Harness.start(tester, cameras: cams);
    double clockRight() => tester.getTopRight(find.byKey(const ValueKey('status-clock'))).dx;
    final withRec = clockRight();
    expect(withRec, greaterThan(780), reason: 'the status bar has 12 px of padding');
    expect(tester.getTopRight(find.byKey(const ValueKey('rec-chip'))).dx, lessThan(withRec));
    cams.status = up(CameraView.none, recording: RecordingStatus.off);
    await tester.pump();
    expect(find.byKey(const ValueKey('rec-chip')), findsNothing);
    expect(clockRight(), withRec);
  });

  testWidgets('REC lists the cameras recording, only while camera-manager reports it',
      (tester) async {
    final cams = FakeCameras(up(CameraView.none, recording: rec([frontRec, rearRec])));
    final h = await Harness.start(tester, cameras: cams);
    expect(pillText(tester, 'rec-chip'), 'REC FRONT REAR');
    expect(find.byKey(const ValueKey('alert-banner')), findsNothing);

    // Starting isn't recording.
    cams.status = up(CameraView.none,
        recording: rec([frontRec, const CameraRecording(camera: CameraId.rear, state: RecordingState.starting)]));
    await tester.pump();
    expect(pillText(tester, 'rec-chip'), 'REC FRONT');

    cams.status = up(CameraView.none,
        recording: rec(const [CameraRecording(camera: CameraId.front, state: RecordingState.starting)]));
    await tester.pump();
    expect(pillText(tester, 'rec-chip'), 'REC STARTING');

    // Recording off, or not reported: nothing claimed, no advisory.
    for (final r in [RecordingStatus.off, null]) {
      cams.status = up(CameraView.none, recording: r);
      await tester.pump();
      expect(find.byKey(const ValueKey('rec-chip')), findsNothing, reason: '$r');
      expect(find.byKey(const ValueKey('alert-banner')), findsNothing, reason: '$r');
    }

    // The link drops: the last recording state isn't shown as current.
    cams.status = CameraStatus(link: CameraLink.down, recording: rec([frontRec, rearRec]));
    await tester.pump();
    expect(find.byKey(const ValueKey('rec-chip')), findsNothing);
    expect(find.text('CAMERAS OFFLINE'), findsOneWidget);
    await h.goTo(AppTab.cameras);
    expect(find.byKey(const ValueKey('cameras-save-clip')), findsNothing);
  });

  testWidgets('a recorded camera that isn\'t recording is an advisory on every screen',
      (tester) async {
    final cams = FakeCameras(up(CameraView.none, recording: rec([frontRec, rearDown])));
    final h = await Harness.start(tester, scenario: 'warm_idle', cameras: cams);
    await h.advance(const Duration(seconds: 5));
    expect(pillText(tester, 'rec-chip'), 'NOT RECORDING: REAR');
    for (final tab in AppTab.values) {
      await h.goTo(tab);
      expect(h.textOf('alert-title'), 'Rear camera not recording', reason: tab.name);
    }
    // In camera mode the alert takes the status bar's place.
    cams.status = up(rearLive, recording: rec([frontRec, rearDown]));
    await tester.pump();
    expect(tester.getRect(find.byKey(const ValueKey('alert-banner'))), const Rect.fromLTWH(0, 0, 800, 44));
    expect(h.textOf('alert-title'), 'Rear camera not recording');

    // A problem that isn't one camera's.
    cams.status = up(CameraView.none, recording: rec([frontRec, rearRec], problem: 'Data drive full'));
    await tester.pump();
    expect(h.textOf('alert-title'), 'Camera recording');

    cams.status = up(CameraView.none, recording: rec([frontRec, rearRec]));
    await tester.pump();
    expect(find.byKey(const ValueKey('alert-banner')), findsNothing);
  });

  testWidgets('a vehicle critical alert outranks a recording advisory', (tester) async {
    final cams = FakeCameras(up(CameraView.none, recording: rec([frontRec, rearDown])));
    final h = await Harness.start(tester, scenario: 'link_loss', cameras: cams);
    await h.advance(const Duration(seconds: 100));
    expect(h.textOf('alert-title'), 'Vehicle data lost');
    expect(find.textContaining('more'), findsOneWidget);
  });

  testWidgets('camera mode: REC dots on recording cameras, Save clip saves and says so',
      (tester) async {
    final cams = FakeCameras(up(rearLive, recording: rec([frontRec, rearRec])));
    await Harness.start(tester, cameras: cams);
    expect(find.byKey(const ValueKey('camera-rec-dot-front')), findsOneWidget);
    expect(find.byKey(const ValueKey('camera-rec-dot-rear')), findsOneWidget);
    expect(find.byKey(const ValueKey('camera-rec-dot-left')), findsNothing);
    // The column stays clear of the camera window.
    final save = tester.getRect(find.byKey(const ValueKey('camera-save-clip')));
    expect(save.right, lessThanOrEqualTo(kCameraControlsWidth));
    expect(save.height, greaterThanOrEqualTo(kMinTouch));

    await tester.tap(find.byKey(const ValueKey('camera-save-clip')));
    await tester.pump();
    expect(cams.saves, 1);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('4 segments saved, 4 to come'), findsOneWidget);
    await tester.pump(kSaveClipResultFor);
    expect(find.text('Save clip'), findsOneWidget);

    // A refusal says why.
    cams.saveResult = const SaveClipResult(saved: false, detail: 'Saved clips are full (25 GB)');
    await tester.tap(find.byKey(const ValueKey('camera-save-clip')));
    await tester.pump();
    expect(find.text('Not saved'), findsOneWidget);
    expect(find.text('Saved clips are full (25 GB)'), findsOneWidget);
    await tester.pump(kSaveClipResultFor);

    // camera-manager not answering.
    cams.saveError = StateError('gone');
    await tester.tap(find.byKey(const ValueKey('camera-save-clip')));
    await tester.pump();
    expect(find.text("camera-manager didn't answer"), findsOneWidget);
    await tester.pump(kSaveClipResultFor);

    // Rear stops: its dot goes. Recording off: no Save clip.
    cams.status = up(rearLive, recording: rec([frontRec, rearDown]));
    await tester.pump();
    expect(find.byKey(const ValueKey('camera-rec-dot-rear')), findsNothing);
    cams.status = up(rearLive, recording: RecordingStatus.off);
    await tester.pump();
    expect(find.byKey(const ValueKey('camera-save-clip')), findsNothing);
    expect(find.byKey(const ValueKey('camera-rec-dot-front')), findsNothing);
  });

  testWidgets('the Cameras tab reports recording and saves a clip', (tester) async {
    final cams = FakeCameras(up(CameraView.none, recording: rec([frontRec, rearDown], clock: false, pending: 3)));
    final h = await Harness.start(tester, cameras: cams);
    await h.goTo(AppTab.cameras);
    expect(h.textOf('recording-front'), 'Front: recording (b00042-s000317.mkv)');
    expect(h.textOf('recording-rear'), 'Rear: not recording: no frame for 1000 ms');
    expect(h.textOf('recording-drive'), 'Drive: 412.3 GB free · video 38.4 GB');
    expect(h.textOf('recording-clips'), 'Saved clips: 1.2 GB of 25.0 GB · 3 to come');
    expect(h.textOf('recording-clock'), contains('Clock not synchronized'));
    expect(find.byKey(const ValueKey('recording-simulated')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('cameras-save-clip')));
    await tester.pump();
    expect(h.textOf('cameras-save-clip-result'), '4 segments saved, 4 to come');
    await tester.pump(kSaveClipResultFor);
    expect(find.byKey(const ValueKey('cameras-save-clip-result')), findsNothing);

    cams.saveResult = const SaveClipResult(saved: false, detail: 'Nothing is recording');
    await tester.tap(find.byKey(const ValueKey('cameras-save-clip')));
    await tester.pump();
    expect(find.text('Not saved'), findsOneWidget);
    expect(h.textOf('cameras-save-clip-result'), 'Nothing is recording');
    await tester.pump(kSaveClipResultFor);

    cams.status = up(CameraView.none, recording: rec([frontRec], drive: false, problem: 'Data drive full'));
    await tester.pump();
    expect(h.textOf('recording-drive'), contains('No data drive'));
    expect(h.textOf('recording-problem'), 'Data drive full');
    expect(find.byKey(const ValueKey('recording-clock')), findsNothing);

    cams.status = up(CameraView.none, recording: RecordingStatus.off);
    await tester.pump();
    expect(h.textOf('recording-off'), 'Recording is off (RECORD_CAMERAS).');
    expect(find.byKey(const ValueKey('cameras-save-clip')), findsNothing);

    cams.status = up(CameraView.none);
    await tester.pump();
    expect(h.textOf('recording-off'), "camera-manager hasn't reported recording.");
    expect(tester.takeException(), isNull);
  });

  testWidgets('the simulated source says SIM wherever it shows recording', (tester) async {
    final sim = SimulatedCameraSource();
    final h = await Harness.start(tester, cameras: sim);
    expect(pillText(tester, 'rec-chip'), 'SIM REC FRONT REAR');
    await h.goTo(AppTab.cameras);
    expect(find.byKey(const ValueKey('recording-simulated')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cameras-save-clip')));
    await tester.pump();
    expect(find.text('SIMULATED'), findsWidgets);
    expect(h.textOf('cameras-save-clip-result'), startsWith('SIMULATED: nothing was saved'));
    await tester.pump(kSaveClipResultFor);

    sim.setRecording(CameraId.rear, RecordingState.notRecording, detail: 'no rear camera (simulated)');
    await tester.pump();
    expect(pillText(tester, 'rec-chip'), 'SIM NOT RECORDING: REAR');
  });

  for (final theme in DayNight.values) {
    testWidgets('every recording state lays out at 800×480, ${theme.name}', (tester) async {
      final long = CameraRecording(
          camera: CameraId.rear,
          state: RecordingState.notRecording,
          detail: 'the recording pipeline stopped getting frames and is being restarted with a '
              'backoff; a long detail to test the ellipsis');
      final states = [
        rec([frontRec, rearRec]),
        rec([frontRec, long], clock: false, problem: 'x' * 200, pending: 12),
        rec([long, long], drive: false),
        RecordingStatus.off,
        null,
      ];
      final cams = FakeCameras(up(CameraView.none));
      final h = await Harness.start(tester, scenario: 'link_loss', theme: theme, cameras: cams);
      for (final alert in [false, true]) {
        if (alert) await h.advance(const Duration(seconds: 100));
        for (final r in states) {
          for (final view in [CameraView.none, rearLive]) {
            cams.status = up(view, recording: r);
            await h.goTo(AppTab.cameras);
            expect(tester.takeException(), isNull, reason: '$r $view alert=$alert');
            // Every button on screen is a full touch target.
            for (final e in find.byType(InkWell).evaluate()) {
              final size = tester.getSize(find.byWidget(e.widget));
              expect(size.width, greaterThanOrEqualTo(kMinTouch), reason: '$r $view');
              expect(size.height, greaterThanOrEqualTo(kMinTouch), reason: '$r $view');
            }
          }
        }
      }
    });
  }
}
