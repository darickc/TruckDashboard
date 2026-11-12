import 'package:f250_infotainment/cameras/camera_state.dart';
import 'package:f250_infotainment/cameras/simulated_camera_source.dart';
import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/theme.dart';
import 'package:f250_infotainment/ui/widgets/tap_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_cameras.dart';
import '../harness.dart';

const rearLive = CameraView(
    camera: CameraId.rear, reason: CameraReason.cameraSwitch, feed: FeedState.live);

/// The camera area must cover where the compositor puts camera-manager's
/// window (agl/flutter/config.toml: x 220, y 44, 580×435, one row short of
/// the bottom; make agl-test checks that file against the same constants).
const cameraWindow = Rect.fromLTWH(220, 44, 580, 436);

/// The status bar, or the alert bar in its place: always above the window.
const topBar = Rect.fromLTWH(0, 0, 800, 44);

bool selected(WidgetTester tester, String key) =>
    tester.widget<TapTarget>(find.byKey(ValueKey(key))).selected;

void main() {
  setUpAll(loadTestAssets);

  Rect rectOf(WidgetTester tester, String key) => tester.getRect(find.byKey(ValueKey(key)));

  void expectCameraMode(WidgetTester tester, String why) {
    expect(rectOf(tester, 'camera-area'), cameraWindow, reason: why);
    expect(rectOf(tester, 'camera-controls'), const Rect.fromLTWH(0, 44, 220, 436), reason: why);
    expect(find.byKey(const ValueKey('camera-strip')), findsNothing, reason: '$why: no strip');
    expect(find.byKey(const ValueKey('nav-back')), findsNothing, reason: '$why: screen replaced');
    expect(tester.takeException(), isNull, reason: why);
  }

  testWidgets('a camera from the Cameras screen: starting, then live (simulated, no picture)',
      (tester) async {
    final h = await Harness.start(tester);
    await h.goTo(AppScreen.cameras);
    expect(find.text('SIMULATED: NO PICTURE'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cameras-open-rear')));
    await tester.pump();
    expectCameraMode(tester, 'starting');
    expect(h.textOf('camera-area-title'), 'Starting rear camera…');
    expect(find.text('REAR CAMERA'), findsOneWidget, reason: 'status bar chip');
    expect(selected(tester, 'camera-rear'), isTrue);

    await tester.pump(const Duration(milliseconds: 700));
    expectCameraMode(tester, 'live');
    expect(h.textOf('camera-area-title'), 'SIMULATED: no camera picture');
  });

  testWidgets('camera mode comes up on any screen, as the switch would bring it', (tester) async {
    final h = await Harness.start(tester);
    await h.goTo(AppScreen.gauges);
    await h.services.cameras.move(SwitchMove.left);
    await tester.pump();
    expectCameraMode(tester, 'from gauges');
    expect(find.text('LEFT CAMERA'), findsOneWidget);
    expect(selected(tester, 'camera-left'), isTrue);

    // Close goes back to the screen the driver was on.
    await tester.tap(find.byKey(const ValueKey('camera-close')));
    await tester.pump();
    expect(find.byKey(const ValueKey('camera-area')), findsNothing);
    expect(find.byKey(const ValueKey('screen-gauges')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-back')), findsOneWidget);
  });

  testWidgets('camera buttons are switch moves, and the current camera is marked', (tester) async {
    final cams = FakeCameras(up(rearLive));
    await Harness.start(tester, cameras: cams);
    for (final (key, move) in [
      ('camera-front', SwitchMove.forward),
      ('camera-left', SwitchMove.left),
      ('camera-rear', SwitchMove.back),
      ('camera-right', SwitchMove.right),
      ('camera-close', SwitchMove.press),
    ]) {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
      expect(cams.moves.last, move, reason: key);
    }
    final rear = tester.widget<TapTarget>(find.byKey(const ValueKey('camera-rear')));
    final left = tester.widget<TapTarget>(find.byKey(const ValueKey('camera-left')));
    expect(rear.selected, isTrue);
    expect(left.selected, isFalse);
  });

  testWidgets('an alert takes the status bar, above the camera; the area never moves',
      (tester) async {
    final h = await Harness.start(tester, scenario: 'link_loss', cameras: FakeCameras(up(rearLive)));
    await h.advance(const Duration(seconds: 5));
    expect(find.byKey(const ValueKey('alert-banner')), findsNothing);
    expectCameraMode(tester, 'no alert');

    await h.advance(const Duration(seconds: 95));
    expect(find.byKey(const ValueKey('alert-banner')), findsOneWidget);
    expect(h.textOf('alert-title'), 'Vehicle data lost');
    expect(rectOf(tester, 'alert-banner'), topBar);
    expect(rectOf(tester, 'alert-banner').overlaps(cameraWindow), isFalse);
    expectCameraMode(tester, 'with alert');
    // The camera stays marked by its button; the simulated data by SIM.
    expect(selected(tester, 'camera-rear'), isTrue);
    expect(find.text('SIM'), findsOneWidget);
  });

  testWidgets('an unavailable camera says why and to use the mirrors', (tester) async {
    final cams = SimulatedCameraSource(missing: {CameraId.left});
    final h = await Harness.start(tester, cameras: cams);
    await cams.move(SwitchMove.left);
    await tester.pump();
    expectCameraMode(tester, 'unavailable');
    expect(h.textOf('camera-area-title'), 'Left camera unavailable');
    expect(h.textOf('camera-area-detail'), 'no left camera (simulated). Use the mirrors.');
    // It isn't starting: no timer brings it live.
    await tester.pump(const Duration(seconds: 2));
    expect(h.textOf('camera-area-title'), 'Left camera unavailable');
  });

  testWidgets('a live real camera: the dashboard draws only what shows if the window is missing',
      (tester) async {
    final h = await Harness.start(tester, cameras: FakeCameras(up(rearLive)));
    expectCameraMode(tester, 'real live');
    expect(h.textOf('camera-area-title'), 'Rear camera is live');
    expect(h.textOf('camera-area-detail'), contains("If you can read this, it isn't showing"));
    final area = tester.widget<Container>(find.byKey(const ValueKey('camera-area')));
    expect(area.color, Colors.black);
  });

  testWidgets('the front camera opens from the Cameras screen and its button', (tester) async {
    final h = await Harness.start(tester);
    await h.goTo(AppScreen.cameras);
    await tester.tap(find.byKey(const ValueKey('cameras-open-front')));
    await tester.pump();
    expectCameraMode(tester, 'front');
    expect(find.text('FRONT CAMERA'), findsOneWidget);
    final front = tester.widget<TapTarget>(find.byKey(const ValueKey('camera-front')));
    expect(front.selected, isTrue);
    await tester.tap(find.byKey(const ValueKey('camera-rear')));
    await tester.pump();
    expect(find.text('REAR CAMERA'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); // the simulated start
  });

  testWidgets('reverse is marked as reverse', (tester) async {
    await Harness.start(tester,
        cameras: FakeCameras(up(const CameraView(
            camera: CameraId.rear,
            reason: CameraReason.reverse,
            feed: FeedState.live,
            reverse: ReverseStatus.engaged))));
    expect(find.text('REVERSE'), findsOneWidget);
    expect(selected(tester, 'camera-rear'), isTrue);
  });

  testWidgets('without camera-manager the dashboard claims no camera', (tester) async {
    final cams = FakeCameras(up(rearLive));
    final h = await Harness.start(tester, cameras: cams);
    expectCameraMode(tester, 'connected');

    // The stream drops while a camera was up: the last view isn't shown as
    // current. camera-manager's window goes with camera-manager.
    cams.status = const CameraStatus(link: CameraLink.down, view: rearLive, detail: 'connection refused');
    await tester.pump();
    expect(find.byKey(const ValueKey('camera-area')), findsNothing);
    expect(find.text('CAMERAS OFFLINE'), findsOneWidget);
    await h.goTo(AppScreen.cameras);
    expect(find.textContaining("camera-manager isn't reachable: connection refused"), findsOneWidget);
    expect(find.byKey(const ValueKey('cameras-open-rear')), findsNothing);

    cams.status = const CameraStatus(link: CameraLink.connecting);
    await tester.pump();
    expect(find.text('CAMERAS OFFLINE'), findsNothing);
    expect(find.text('Connecting to camera-manager…'), findsOneWidget);
  });

  testWidgets('the Cameras screen reports reverse and the speed limit', (tester) async {
    final cams = FakeCameras(up(const CameraView(reverse: ReverseStatus.unknown, blockedBySpeed: true)));
    final h = await Harness.start(tester, cameras: cams);
    await h.goTo(AppScreen.cameras);
    expect(find.textContaining('Reverse signal unknown'), findsOneWidget);
    expect(find.textContaining('Hidden above the speed limit'), findsOneWidget);
    expect(find.text('CONNECTED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final theme in DayNight.values) {
    testWidgets('camera mode lays out in every state, with and without an alert, ${theme.name}',
        (tester) async {
      final cams = FakeCameras(up(rearLive));
      final h = await Harness.start(tester, scenario: 'link_loss', theme: theme, cameras: cams);
      for (final alert in [false, true]) {
        if (alert) await h.advance(const Duration(seconds: 100));
        for (final camera in CameraId.values) {
          for (final feed in FeedState.values) {
            for (final reason in CameraReason.values) {
              cams.status = up(CameraView(
                  camera: camera,
                  reason: reason,
                  feed: feed,
                  feedDetail: feed == FeedState.unavailable
                      ? 'no frame within 5000 ms of starting; a long detail from the pipeline that '
                          'goes on and on to test the ellipsis on the 800 px screen'
                      : ''));
              await tester.pump();
              expectCameraMode(tester, '$camera $feed $reason alert=$alert');
            }
          }
        }
      }
    });
  }

  testWidgets('camera buttons are at least 60×60', (tester) async {
    await Harness.start(tester, cameras: FakeCameras(up(rearLive)));
    for (final key in ['camera-front', 'camera-left', 'camera-rear', 'camera-right', 'camera-close']) {
      final size = tester.getSize(find.byKey(ValueKey(key)));
      expect(size.width, greaterThanOrEqualTo(kMinTouch), reason: key);
      expect(size.height, greaterThanOrEqualTo(kMinTouch), reason: key);
    }
  });
}
