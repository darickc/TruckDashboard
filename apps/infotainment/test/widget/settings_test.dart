import 'package:f250_infotainment/cameras/camera_settings.dart';
import 'package:f250_infotainment/cameras/camera_state.dart';
import 'package:f250_infotainment/cameras/simulated_camera_source.dart';
import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/model/units.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_cameras.dart';
import '../harness.dart';

Future<void> openSection(WidgetTester tester, Harness h, String section) async {
  await h.goTo(AppScreen.settings);
  await tester.tap(find.byKey(ValueKey('settings-$section')));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

String deviceText(WidgetTester tester, CameraId c) => tester
    .widget<Text>(find.descendant(
        of: find.byKey(ValueKey('cam-device-${c.name}')), matching: find.byType(Text)))
    .data!;

const port1 = '/dev/v4l/by-path/platform-x-usb-0:1.2:1.0-video-index0';
const port2 = '/dev/v4l/by-path/platform-x-usb-0:2:1.0-video-index0';

FakeCameras connectedFake({String recordingUnavailable = ''}) {
  final f = FakeCameras(const CameraStatus(link: CameraLink.up, view: CameraView.none));
  f.settings = CameraSettingsSnapshot(
    settings: CameraSettings(
        devices: const {CameraId.rear: port1},
        record: const {CameraId.rear},
        recordingUnavailable: recordingUnavailable),
    plugged: const [
      CameraDevice(path: port1, label: '046d_0825_ABC'),
      CameraDevice(path: port2),
    ],
  );
  return f;
}

void main() {
  setUpAll(loadTestAssets);

  testWidgets('the Settings screen: Display first, Units moved here and kept', (tester) async {
    final h = await Harness.start(tester);
    await h.goTo(AppScreen.settings);
    expect(find.byKey(const ValueKey('display-detail')), findsOneWidget, reason: 'Display first');
    await openSection(tester, h, 'units');
    await tap(tester, 'units-metric');
    expect(h.services.settings.units, UnitSystem.metric);
    // No longer under Diagnostics → Developer.
    await h.goTo(AppScreen.diagnostics);
    await tester.tap(find.byKey(const ValueKey('diag-developer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('units-metric')), findsNothing);
    expect(find.byKey(const ValueKey('display-detail')), findsNothing);
  });

  testWidgets('cameras: assign, record, apply, and back to /etc/default/f250 (simulated)',
      (tester) async {
    final sim = SimulatedCameraSource(startDelay: Duration.zero);
    final h = await Harness.start(tester, cameras: sim);
    await openSection(tester, h, 'cameras');
    expect(h.textOf('cam-source'), 'From /etc/default/f250.');
    expect(deviceText(tester, CameraId.rear), 'USB 1.4 · SIM_rear');
    expect(find.byKey(const ValueKey('cam-defaults')), findsNothing);
    expect(h.textOf('cam-settings-detail'), contains('Rescan'));

    // Apply does nothing until something changes.
    await tap(tester, 'cam-apply');
    expect(h.textOf('cam-source'), 'From /etc/default/f250.');

    // Rear: none.
    await tap(tester, 'cam-device-rear');
    expect(find.text('Rear camera: which USB port?'), findsOneWidget);
    await tap(tester, 'cam-pick-none');
    expect(deviceText(tester, CameraId.rear), 'None');
    expect(h.textOf('cam-settings-detail'), contains('restarts camera-manager'));

    // Left takes the front camera's port: front loses it.
    await tap(tester, 'cam-device-left');
    expect(find.text('now front; moves here'), findsOneWidget);
    await tap(tester, 'cam-pick-0');
    expect(deviceText(tester, CameraId.left), 'USB 1.1 · SIM_front');
    expect(deviceText(tester, CameraId.front), 'None');

    await tap(tester, 'cam-record-front');
    await tap(tester, 'cam-apply');
    expect(h.textOf('cam-source'), contains('Set on this screen'));
    expect(h.textOf('cam-settings-detail'), contains('Saved'));
    final applied = (await sim.getSettings()).settings;
    expect(applied.devices, {
      CameraId.left: SimulatedCameraSource.simulatedPlugged[0].path,
      CameraId.right: SimulatedCameraSource.simulatedPlugged[2].path,
    });
    expect(applied.record, {CameraId.rear}, reason: 'front off; rear kept but has no device');

    await tap(tester, 'cam-defaults');
    expect(h.textOf('cam-source'), 'From /etc/default/f250.');
    expect(deviceText(tester, CameraId.rear), 'USB 1.4 · SIM_rear');
  });

  testWidgets('cameras: undo, a camera not plugged in, recording unavailable', (tester) async {
    final fake = connectedFake(recordingUnavailable: 'Recording needs the data drive: DATA_DRIVE=1.');
    fake.settings = CameraSettingsSnapshot(
      settings: CameraSettings(
          devices: const {CameraId.rear: port1, CameraId.front: '/dev/v4l/by-path/x-usb-0:3:1.0-video-index0'},
          record: const {CameraId.rear},
          recordingUnavailable: fake.settings.settings.recordingUnavailable),
      plugged: fake.settings.plugged,
    );
    final h = await Harness.start(tester, cameras: fake);
    await openSection(tester, h, 'cameras');
    expect(deviceText(tester, CameraId.front), 'USB 3: not plugged in');
    expect(deviceText(tester, CameraId.rear), 'USB 1.2 · 046d_0825_ABC');
    expect(h.textOf('cam-recording-unavailable'), contains('DATA_DRIVE=1'));

    await tap(tester, 'cam-device-right');
    await tap(tester, 'cam-pick-1');
    expect(deviceText(tester, CameraId.right), 'USB 2');
    await tap(tester, 'cam-revert');
    expect(deviceText(tester, CameraId.right), 'None');
    expect(fake.applied, isEmpty);
  });

  testWidgets('cameras: a refusal is shown; settings are read again when camera-manager returns',
      (tester) async {
    final fake = connectedFake();
    fake.applyResult = const ApplyResult(
        applied: false, detail: 'Close the camera first: applying settings restarts camera-manager.');
    final h = await Harness.start(tester, cameras: fake);
    await openSection(tester, h, 'cameras');
    await tap(tester, 'cam-record-rear');
    await tap(tester, 'cam-apply');
    expect(h.textOf('cam-settings-detail'), contains('Close the camera first'));
    expect(fake.applied.single!.record, isEmpty);

    // camera-manager restarts: not connected, then back with new settings.
    fake.status = const CameraStatus(link: CameraLink.down, detail: 'restarting');
    await tester.pumpAndSettle();
    expect(h.textOf('cam-settings-detail'), contains('camera-manager not connected (restarting)'));
    fake.settings = CameraSettingsSnapshot(
        settings: const CameraSettings(devices: {CameraId.front: port2}, source: SettingsSource.screen),
        plugged: fake.settings.plugged);
    fake.status = const CameraStatus(link: CameraLink.up, view: CameraView.none);
    await tester.pumpAndSettle();
    expect(h.textOf('cam-source'), contains('Set on this screen'));
    expect(deviceText(tester, CameraId.front), 'USB 2');
  });

  // 800×480, both themes, every Cameras state: nothing overflows.
  for (final theme in DayNight.values) {
    for (final state in ['list', 'picker', 'not connected', 'unavailable', 'no cameras']) {
      testWidgets('camera settings lay out at 800×480: $state, ${theme.name}', (tester) async {
        final fake = connectedFake(
            recordingUnavailable: state == 'unavailable' ? 'Recording needs the data drive.' * 3 : '');
        if (state == 'no cameras') {
          fake.settings = CameraSettingsSnapshot(settings: fake.settings.settings);
        }
        if (state == 'not connected') {
          fake.status = const CameraStatus(link: CameraLink.down, detail: 'connection refused');
        }
        final h = await Harness.start(tester, theme: theme, cameras: fake);
        await openSection(tester, h, 'cameras');
        if (state == 'picker' || state == 'no cameras') await tap(tester, 'cam-device-front');
        expect(tester.takeException(), isNull);
        for (final section in ['units', 'display']) {
          await openSection(tester, h, section);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
