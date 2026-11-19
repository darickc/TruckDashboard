import 'package:f250_infotainment/cameras/camera_state.dart';
import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/core/system_info.dart';
import 'package:f250_infotainment/model/units.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/tone.dart';
import 'package:f250_infotainment/ui/widgets/system_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_cameras.dart';
import '../harness.dart';

/// Settings › System (2026-11-18): what the head unit says about itself and
/// every service's link.
void main() {
  setUpAll(loadTestAssets);

  const known = SystemFacts(
    dashboard: Fact.known('commit 81f69e1 (uncommitted changes)'),
    commit: Fact.known('0f2ffac'),
    image: Fact.known('Automotive Grade Linux 22.0.1'),
    uptime: Fact.known(Duration(hours: 3, minutes: 12)),
    cpuTemperature: Fact.known((celsius: 50.0, zone: 'cpu-thermal')),
  );

  Future<Harness> open(WidgetTester tester, {SystemFacts facts = known, DayNight theme = DayNight.night,
      String scenario = 'drive_cycle', CameraSource? cameras}) async {
    final h = await Harness.start(tester,
        theme: theme, scenario: scenario, cameras: cameras, systemInfo: FixedSystemInfo(facts));
    await h.goTo(AppScreen.settings);
    await tester.tap(find.byKey(const ValueKey('settings-system')));
    await tester.pump();
    await tester.pump();
    return h;
  }

  testWidgets('the head unit\'s facts, in the driver\'s units', (tester) async {
    final h = await open(tester);
    expect(h.textOf('system-dashboard'), 'commit 81f69e1 (uncommitted changes)');
    expect(h.textOf('system-commit'), 'commit 0f2ffac', reason: 'the image\'s, apart from the dashboard\'s');
    expect(h.textOf('system-image'), 'Automotive Grade Linux 22.0.1');
    expect(h.textOf('system-uptime'), '3 h 12 min');
    expect(h.textOf('system-temperature'), '122 °F');
    h.services.settings.units = UnitSystem.metric;
    await tester.pump();
    expect(h.textOf('system-temperature'), '50 °C');
  });

  testWidgets('what can\'t be read says why, never a value', (tester) async {
    final h = await open(tester, facts: SystemFacts.unavailable('the browser preview has none'));
    expect(h.textOf('system-commit'), 'not available: the browser preview has none');
    expect(h.textOf('system-temperature'), startsWith('not available'));
  });

  testWidgets('the data drive as camera-manager reports it, and only then', (tester) async {
    final cams = FakeCameras(const CameraStatus(link: CameraLink.down));
    final h = await open(tester, cameras: cams);
    expect(h.textOf('system-drive'), 'not reported (needs camera-manager)');
    cams.status = up(CameraView.none,
        recording: const RecordingStatus(
            cameras: [CameraRecording(camera: CameraId.front, state: RecordingState.recording)],
            driveMounted: true,
            driveFreeBytes: 412300000000,
            recordedBytes: 38400000000));
    await tester.pump();
    expect(h.textOf('system-drive'), '412.3 GB free · video 38.4 GB');
    // No camera set to record: camera-manager says nothing of the drive,
    // and the page doesn't guess (bench 2026-11-19: it said "not mounted").
    cams.status = up(CameraView.none, recording: RecordingStatus.off);
    await tester.pump();
    expect(h.textOf('system-drive'), 'not reported while recording is off');
    cams.status = up(CameraView.none,
        recording: const RecordingStatus(
            cameras: [CameraRecording(camera: CameraId.front, state: RecordingState.notRecording)]));
    await tester.pump();
    expect(h.textOf('system-drive'), 'not mounted');
  });

  testWidgets('every service, simulated ones marked, all in sight', (tester) async {
    final h = await open(tester);
    expect(tester.getRect(find.byKey(const ValueKey('system-service-map'))).bottom, lessThanOrEqualTo(480),
        reason: 'without an alert the last row shows');
    final rows = {for (final r in serviceRows(h.services)) r.id: r};
    expect(rows.keys, ['vehicle', 'cameras', 'audio', 'power', 'gps', 'routing', 'places', 'export', 'map']);
    expect(rows['vehicle']!.state, 'in-app simulator');
    expect(rows['vehicle']!.tone, HomeTone.simulated);
    expect(rows['cameras']!.state, 'simulated');
    expect(rows['power']!.state, 'simulated');
    expect(rows['routing']!.state, 'not available');
    expect(rows['map']!.state, 'no map file');
    for (final id in rows.keys) {
      expect(find.byKey(ValueKey('system-service-$id')), findsOneWidget, reason: id);
    }
  });

  testWidgets('a camera-manager that is down shows as not reachable', (tester) async {
    final h = await open(tester, cameras: FakeCameras(const CameraStatus(link: CameraLink.down)));
    expect(h.textOf('system-state-cameras'), 'not reachable');
  });

  for (final theme in DayNight.values) {
    testWidgets('lays out under an alert with the longest reasons, ${theme.name}', (tester) async {
      final h = await open(tester,
          theme: theme,
          scenario: 'link_loss',
          facts: SystemFacts.unavailable('no /sys/class/thermal/thermal_zone0/temp on this machine at all'));
      await h.advance(const Duration(seconds: 100));
      expect(find.byKey(const ValueKey('alert-banner')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
