// Runs the real services/camera-manager binary, with a fake gst-launch, and
// reads it through the app's camera source: the Rust server and the Dart
// client agree on f250.camera.v1, and killing camera-manager takes the
// camera off the dashboard. Skipped unless the binary is built:
// `cargo build -p camera-manager` (make ui-test does this).
@Tags(['integration'])
library;

import 'dart:io';

import 'package:f250_infotainment/cameras/camera_state.dart';
import 'package:f250_infotainment/cameras/grpc_camera_source.dart';
import 'package:f250_infotainment/data/gateway_connection.dart';
import 'package:flutter_test/flutter_test.dart';

final _root = Directory.current.parent.parent.path; // apps/infotainment → repo
final _bin = File('$_root/target/debug/camera-manager');

/// Frames forever for `device=frames`; nothing for anything else.
const _fakeGst = r'''#!/bin/sh
dev=""
for a in "$@"; do case "$a" in device=*) dev="${a#device=}";; esac; done
mark="/GstPipeline:pipeline0/GstIdentity:f250_frames: last-message = chain   ******* (f250_frames:sink) (614400 bytes)"
case "$dev" in
  frames) while :; do echo "$mark"; sleep 0.02; done ;;
  *) exec sleep 30 ;;
esac
''';

Future<void> _until(bool Function() ok, {Duration timeout = const Duration(seconds: 10)}) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('condition not met within $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  final skip = _bin.existsSync() ? false : 'build camera-manager first: cargo build -p camera-manager';

  test('switch moves and views between the app and camera-manager; a crash clears the camera',
      () async {
    final dir = Directory.systemTemp.createTempSync('f250-camit');
    addTearDown(() => dir.deleteSync(recursive: true));
    final gst = File('${dir.path}/gst')..writeAsStringSync(_fakeGst);
    await Process.run('chmod', ['+x', gst.path]);
    final sock = '${dir.path}/c.sock';

    Future<Process> start() async {
      final p = await Process.start(_bin.path, [
        '--listen', 'unix:$sock',
        '--gst-launch', gst.path,
        '--sink', 'fakesink',
        '--camera', 'rear=frames',
        '--camera', 'left=silent',
        '--start-timeout-ms', '800',
      ]);
      p.stdout.listen((_) {});
      p.stderr.listen((_) {});
      await _until(() => File(sock).existsSync());
      return p;
    }

    var cm = await start();
    addTearDown(() => cm.kill());
    final src = GrpcCameraSource(
        endpoint: UnixEndpoint(sock), retryDelay: const Duration(milliseconds: 200))
      ..start();
    addTearDown(src.stop);

    await _until(() => src.status.value.link == CameraLink.up);
    expect(src.status.value.camera, isNull);
    // Nothing here records (no drive, no recording configured): whatever
    // camera-manager says about recording, no camera is claimed as recording.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(src.status.value.recording?.inState(RecordingState.recording) ?? const [], isEmpty);

    await src.move(SwitchMove.back);
    await _until(() => src.status.value.view?.feed == FeedState.live);
    expect(src.status.value.camera, CameraId.rear);
    expect(src.status.value.view!.reason, CameraReason.cameraSwitch);
    expect(src.status.value.view!.reverse, ReverseStatus.off);

    // A camera that never sends a frame is reported unavailable, with why.
    await src.move(SwitchMove.left);
    await _until(() => src.status.value.view?.feed == FeedState.unavailable);
    expect(src.status.value.view!.feedDetail, contains('no frame'));

    await src.move(SwitchMove.back);
    await _until(() => src.status.value.view?.feed == FeedState.live);

    // camera-manager dies: the dashboard stops claiming a camera.
    cm.kill(ProcessSignal.sigkill);
    await cm.exitCode;
    await _until(() => src.status.value.link == CameraLink.down);
    expect(src.status.value.camera, isNull);

    // It comes back (systemd restarts it): found again, no camera yet.
    cm = await start();
    await _until(() => src.status.value.link == CameraLink.up);
    expect(src.status.value.camera, isNull);
  }, skip: skip, timeout: const Timeout(Duration(seconds: 60)));
}
