import 'package:f250_infotainment/cameras/camera_state.dart';
import 'package:f250_infotainment/export/export_state.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_cameras.dart';
import '../harness.dart';
import 'recording_test.dart' show frontRec, rearDown, rec;

/// Copying recordings to a USB stick from the dashboard (ADR-0037), at
/// 800×480, against the simulated usb-export. `[SIM]`.

Future<Harness> openRecordings(
  WidgetTester tester, {
  ExportSource? exports,
  String scenario = 'drive_cycle',
}) async {
  final h = await Harness.start(tester, exports: exports, scenario: scenario);
  await h.goTo(AppScreen.cameras);
  await tester.tap(find.byKey(const ValueKey('cameras-recordings')));
  await tester.pump(); // the screen
  await tester.pump(); // the list
  return h;
}

Finder key(String k) => find.byKey(ValueKey(k));

String? text(WidgetTester tester, String k) {
  final f = key(k);
  if (f.evaluate().isEmpty) return null;
  return tester.widget<Text>(f).data;
}

const front0 = 'front/b00003-s000000-20261112T045200Z.mkv';
const rear0 = 'rear/b00003-s000000-20261112T045200Z.mkv';
const front1 = 'front/b00003-s000001-20261112T045300Z.mkv';

void expectTouchTargets(WidgetTester tester) {
  for (final e in find.byType(InkWell).evaluate()) {
    final size = tester.getSize(find.byWidget(e.widget));
    expect(size.height, greaterThanOrEqualTo(kMinTouch), reason: '${e.widget.key}');
    expect(size.width, greaterThanOrEqualTo(kMinTouch), reason: '${e.widget.key}');
  }
}

void main() {
  setUpAll(loadTestAssets);

  testWidgets('opened from Cameras: recordings by run, camera and time, saved clips marked', (
    tester,
  ) async {
    await openRecordings(tester);
    expect(tester.takeException(), isNull);
    expect(key('rec-simulated'), findsOneWidget, reason: 'nothing real is copied');
    expect(text(tester, 'rec-run-2'), 'Run 2 · time unknown (clock not synchronized)');
    expect(key('rec-$front0'), findsOneWidget);
    final saved = key('rec-saved-protected/front/b00003-s000002-20261112T045400Z.mkv');
    await tester.scrollUntilVisible(
      saved,
      120,
      scrollable: find.descendant(of: key('rec-list'), matching: find.byType(Scrollable)),
    );
    expect(saved, findsOneWidget);
    expect(text(tester, 'rec-stick'), 'SIMULATED · exFAT');
    expect(text(tester, 'rec-stick-free'), '30.0 GB free of 32.0 GB');
    expect(text(tester, 'rec-chosen'), 'Nothing chosen.');
    // Back returns to Cameras.
    expect(AppScope.of(tester.element(key('rec-copy'))).screens.previous, AppScreen.cameras);
  });

  testWidgets('every button is a 60 px touch target', (tester) async {
    await openRecordings(tester);
    expectTouchTargets(tester);
  });

  testWidgets('with an alert banner above it, nothing overflows and the buttons stay on screen', (
    tester,
  ) async {
    // An advisory banner takes 62 px.
    final cams = FakeCameras(up(CameraView.none, recording: rec([frontRec, rearDown])));
    final h = await Harness.start(tester, scenario: 'warm_idle', cameras: cams);
    await h.advance(const Duration(seconds: 5));
    expect(h.textOf('alert-title'), 'Rear camera not recording');
    await h.goTo(AppScreen.recordings);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(key('alert-banner'), findsOneWidget, reason: 'alerts show on this screen too');
    expect(tester.getRect(key('rec-copy')).bottom, lessThanOrEqualTo(480));
    expectTouchTargets(tester);
  });

  testWidgets('choose, copy, watch progress, then safe to unplug', (tester) async {
    final exports = SimulatedExportSource();
    await openRecordings(tester, exports: exports);
    await tester.tap(key('rec-$front0'));
    await tester.tap(key('rec-$rear0'));
    await tester.pump();
    expect(text(tester, 'rec-chosen'), '2 chosen · 134 MB');
    expect(text(tester, 'rec-fit'), 'Fits on the stick.');
    await tester.tap(key('rec-copy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(key('rec-progress'), findsOneWidget);
    expect(text(tester, 'rec-progress-text'), '1 of 2 files · 40 MB of 134 MB');
    expect(text(tester, 'rec-copy-detail'), 'Copying: leave the stick in.');
    expect(key('rec-cancel'), findsOneWidget);
    expect(key('rec-range'), findsNothing, reason: 'the choice is fixed while copying');
    expect(text(tester, 'rec-safe'), isNull, reason: 'never safe mid-copy');
    await tester.pump(const Duration(seconds: 1));
    expect(text(tester, 'rec-copy-detail'), 'Copied 2 recordings to F250-recordings on the stick.');
    expect(text(tester, 'rec-safe'), 'Safe to unplug the stick.');
    expect(text(tester, 'rec-stick-free'), '29.9 GB free of 32.0 GB');
  });

  testWidgets('a range: tap Range, the first and the last', (tester) async {
    await openRecordings(tester);
    await tester.tap(key('rec-filter-front'));
    await tester.pump();
    expect(key('rec-$rear0'), findsNothing);
    await tester.tap(key('rec-range'));
    await tester.pump();
    expect(text(tester, 'rec-chosen'), 'Tap the first recording of the range.');
    await tester.tap(key('rec-$front0'));
    await tester.pump();
    await tester.tap(key('rec-$front1'));
    await tester.pump();
    expect(text(tester, 'rec-chosen'), '2 chosen · 48 MB');
    await tester.tap(key('rec-all'));
    await tester.pump();
    expect(
      text(tester, 'rec-chosen'),
      '7 chosen · 168 MB',
      reason: 'all front but the one being written',
    );
  });

  testWidgets('no stick: says so, and Copy says why it can\'t', (tester) async {
    await openRecordings(tester, exports: SimulatedExportSource(stick: null));
    expect(text(tester, 'rec-stick'), 'No USB stick. Plug one (exFAT) into the head unit.');
    await tester.tap(key('rec-$front0'));
    await tester.tap(key('rec-copy'));
    await tester.pump();
    expect(text(tester, 'rec-message'), 'Plug a USB stick into the head unit first.');
  });

  testWidgets('too big for the stick: shown before copying, and refused', (tester) async {
    final exports = SimulatedExportSource(
      stick: const UsbStick(
        device: 'sdz1',
        role: StickRole.export,
        label: 'SMALL',
        filesystem: 'vfat',
        freeBytes: 50000000,
        totalBytes: 64000000,
      ),
    );
    await openRecordings(tester, exports: exports);
    await tester.tap(key('rec-all'));
    await tester.pump();
    expect(text(tester, 'rec-fit'), 'Too big for the stick: 50 MB free.');
    await tester.tap(key('rec-copy'));
    await tester.pump();
    expect(
      text(tester, 'rec-message'),
      'The chosen recordings don\'t fit on the stick: choose fewer.',
    );
    expect(exports.status.value.copy!.phase, CopyPhase.idle);
  });

  for (final (stick, want) in const [
    (
      UsbStick(
        device: 'sdz1',
        role: StickRole.map,
        label: 'MAPS',
        filesystem: 'exfat',
        detail: 'A map stick: use another stick.',
      ),
      'A map stick: use another stick.',
    ),
    (
      UsbStick(
        device: 'sdz1',
        role: StickRole.export,
        label: 'LOCKED',
        filesystem: 'exfat',
        readOnly: true,
        freeBytes: 1 << 34,
        detail: 'The stick is read-only: check its write-protect switch.',
      ),
      'The stick is read-only: check its write-protect switch.',
    ),
    (
      UsbStick(
        device: 'sdz1',
        role: StickRole.unusable,
        filesystem: 'ntfs',
        detail: 'Its filesystem (ntfs) isn\'t supported.',
      ),
      'Its filesystem (ntfs) isn\'t supported.',
    ),
  ]) {
    testWidgets('a stick that can\'t take recordings says why: ${stick.label}${stick.filesystem}', (
      tester,
    ) async {
      await openRecordings(tester, exports: SimulatedExportSource(stick: stick));
      expect(text(tester, 'rec-stick-detail'), want);
      await tester.tap(key('rec-$front0'));
      await tester.tap(key('rec-copy'));
      await tester.pump();
      expect(text(tester, 'rec-message'), want, reason: 'Copy refuses with the reason');
    });
  }

  testWidgets('pulled out mid-copy: the failure is shown, and that it has been removed', (
    tester,
  ) async {
    final exports = SimulatedExportSource()..pullAfterBytes = 30000000;
    await openRecordings(tester, exports: exports);
    await tester.tap(key('rec-$rear0'));
    await tester.tap(key('rec-copy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(text(tester, 'rec-copy-detail'), startsWith('The stick was removed during the copy.'));
    expect(text(tester, 'rec-safe'), 'The stick has been removed.');
    expect(text(tester, 'rec-stick'), 'No USB stick. Plug one (exFAT) into the head unit.');
  });

  testWidgets('cancel stops the copy', (tester) async {
    final exports = SimulatedExportSource();
    await openRecordings(tester, exports: exports);
    await tester.tap(key('rec-$rear0'));
    await tester.tap(key('rec-copy'));
    await tester.pump();
    await tester.tap(key('rec-cancel'));
    await tester.pump();
    expect(text(tester, 'rec-copy-detail'), 'Cancelled: 0 of 1 recordings are on the stick.');
    expect(text(tester, 'rec-safe'), 'Safe to unplug the stick.');
    expect(key('rec-copy'), findsOneWidget);
  });

  testWidgets('usb-export unreachable: says so, never safe to unplug', (tester) async {
    await openRecordings(tester, exports: UnavailableExportSource('connection refused'));
    expect(
      text(tester, 'rec-stick'),
      'usb-export isn\'t reachable: connection refused. Recordings can\'t be copied until it is.',
    );
    expect(text(tester, 'rec-safe'), isNull);
    expect(tester.takeException(), isNull);
  });
}
