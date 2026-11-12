import 'package:f250_infotainment/cameras/camera_state.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/banner_alerts.dart';
import 'package:f250_infotainment/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_cameras.dart';
import '../harness.dart';
import 'recording_test.dart' show frontRec, rearRec, rearDown, rec, rearLive, pillText;

/// Clearing an advisory from the banner (owner, 2026-11-11): hidden while it
/// lasts, back when it returns after kForgetClearedAfter; critical alerts
/// can't be cleared. `[SIM]`.
void main() {
  setUpAll(loadTestAssets);

  final banner = find.byKey(const ValueKey('alert-banner'));
  final clear = find.byKey(const ValueKey('alert-clear'));

  testWidgets('Clear hides "Rear camera not recording" on every screen; REC still says so',
      (tester) async {
    final cams = FakeCameras(up(CameraView.none, recording: rec([frontRec, rearDown])));
    final h = await Harness.start(tester, scenario: 'warm_idle', cameras: cams);
    await h.advance(const Duration(seconds: 5));
    expect(h.textOf('alert-title'), 'Rear camera not recording');
    final r = tester.getRect(clear);
    expect(r.height, greaterThanOrEqualTo(kMinTouch));
    expect(r.width, greaterThanOrEqualTo(kMinTouch));
    expect(r.right, lessThanOrEqualTo(800));

    await tester.tap(clear);
    await tester.pump();
    for (final screen in AppScreen.values) {
      await h.goTo(screen);
      expect(banner, findsNothing, reason: screen.name);
    }
    // Still true, and still in the status bar: only the banner is cleared.
    expect(pillText(tester, 'rec-chip'), 'NOT RECORDING: REAR');
    await h.advance(const Duration(minutes: 5));
    expect(banner, findsNothing, reason: 'hidden while it lasts');
  });

  testWidgets('a cleared advisory shows again once it has been gone 30 s and comes back',
      (tester) async {
    final cams = FakeCameras(up(CameraView.none, recording: rec([frontRec, rearDown])));
    final h = await Harness.start(tester, scenario: 'warm_idle', cameras: cams);
    await h.advance(const Duration(seconds: 5));
    await tester.tap(clear);
    await tester.pump();

    // A retry: gone for 10 s, then down again. The same problem: still hidden.
    cams.status = up(CameraView.none, recording: rec([frontRec, rearRec]));
    await h.advance(const Duration(seconds: 10));
    cams.status = up(CameraView.none, recording: rec([frontRec, rearDown]));
    await h.advance(const Duration(seconds: 2));
    expect(banner, findsNothing, reason: 'back within kForgetClearedAfter');

    // Recording for longer than kForgetClearedAfter, then down again: a new
    // problem, shown.
    cams.status = up(CameraView.none, recording: rec([frontRec, rearRec]));
    await h.advance(kForgetClearedAfter + const Duration(seconds: 2));
    cams.status = up(CameraView.none, recording: rec([frontRec, rearDown]));
    await h.advance(const Duration(seconds: 2));
    expect(h.textOf('alert-title'), 'Rear camera not recording');
  });

  testWidgets('a critical alert has no Clear, and a cleared advisory leaves "+1 more"',
      (tester) async {
    final cams = FakeCameras(up(CameraView.none, recording: rec([frontRec, rearDown])));
    final h = await Harness.start(tester, scenario: 'link_loss', cameras: cams);
    await h.advance(const Duration(seconds: 100));
    expect(h.textOf('alert-title'), 'Vehicle data lost');
    expect(clear, findsNothing, reason: 'critical');
    expect(find.text('+1 more'), findsOneWidget);
    // The refusal is in the model too, not only the missing button.
    final critical = bannerAlerts(h.services).first;
    h.services.cleared.clear(critical, h.store.clock.now());
    await tester.pump();
    expect(h.textOf('alert-title'), 'Vehicle data lost');

    // Clear the advisory (it's the one behind): "+1 more" goes.
    final advisory = bannerAlerts(h.services).firstWhere((a) => a.clearable);
    h.services.cleared.clear(advisory, h.store.clock.now());
    await tester.pump();
    expect(h.textOf('alert-title'), 'Vehicle data lost');
    expect(find.textContaining('more'), findsNothing);
  });

  testWidgets('camera mode has no Clear (44 px); a cleared advisory stays cleared there',
      (tester) async {
    final cams = FakeCameras(up(rearLive, recording: rec([frontRec, rearDown])));
    final h = await Harness.start(tester, scenario: 'warm_idle', cameras: cams);
    await h.advance(const Duration(seconds: 5));
    expect(tester.getRect(banner), const Rect.fromLTWH(0, 0, 800, 44));
    expect(clear, findsNothing);

    cams.status = up(CameraView.none, recording: rec([frontRec, rearDown]));
    await tester.pump();
    await tester.tap(clear);
    await tester.pump();
    cams.status = up(rearLive, recording: rec([frontRec, rearDown]));
    await tester.pump();
    expect(banner, findsNothing);
    expect(find.byKey(const ValueKey('status-clock')), findsOneWidget, reason: 'the status bar is back');
  });
}
