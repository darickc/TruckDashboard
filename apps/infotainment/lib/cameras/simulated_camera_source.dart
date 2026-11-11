import 'dart:async';

import 'package:flutter/foundation.dart';

import 'camera_settings.dart';
import 'camera_state.dart';

/// Stands in for camera-manager in the browser preview and with the in-app
/// simulator. It follows camera-manager's default switch mapping
/// (crates/camera-policy: forward, left, right and back pick a camera; press
/// closes it) and reports the feed starting, then live after [startDelay]
/// (0.62 s on the bench, bench-log 2026-11-09). There is no picture: the
/// status says simulated, and the dashboard says so on screen.
///
/// Recording (ADR-0027) is simulated too: front and rear report recording,
/// with made-up segment names and drive figures, and "save clip" saves
/// nothing. The dashboard marks all of it SIMULATED.
class SimulatedCameraSource implements CameraSource {
  SimulatedCameraSource({
    this.startDelay = const Duration(milliseconds: 620),
    Set<CameraId> missing = const {},
    RecordingStatus recording = simulatedRecording,
  })  : _missing = {...missing},
        _status = ValueNotifier(CameraStatus(
            link: CameraLink.up, view: CameraView.none, recording: recording, simulated: true));

  final Duration startDelay;
  final Set<CameraId> _missing;
  Timer? _live;

  /// When set, "save clip" is refused with this reason (tests).
  String? saveClipRefusal;

  /// Simulated figures for a 512 GB drive with the recommended settings.
  static const simulatedRecording = RecordingStatus(
    cameras: [
      CameraRecording(
          camera: CameraId.front, state: RecordingState.recording, segment: 'b00001-s000042.mkv'),
      CameraRecording(
          camera: CameraId.rear, state: RecordingState.recording, segment: 'b00001-s000042.mkv'),
    ],
    driveMounted: true,
    driveFreeBytes: 412000000000,
    recordedBytes: 38400000000,
    protectedBytes: 1200000000,
    protectedMaxBytes: 25000000000,
    clockTrusted: true,
  );

  final ValueNotifier<CameraStatus> _status;

  /// Four simulated USB ports, one camera on each, front and rear recorded.
  static final simulatedPlugged = [
    for (final (i, label) in [(1, 'SIM_front'), (2, 'SIM_left'), (3, 'SIM_right'), (4, 'SIM_rear')])
      CameraDevice(
          path: '/dev/v4l/by-path/simulated-usb-0:1.$i:1.0-video-index0', label: label),
  ];

  static CameraSettings get simulatedDefaults => CameraSettings(devices: {
        for (final (i, c) in [CameraId.front, CameraId.left, CameraId.right, CameraId.rear].indexed)
          c: simulatedPlugged[i].path,
      }, record: const {
        CameraId.front,
        CameraId.rear
      });

  CameraSettings _settings = simulatedDefaults;

  @override
  ValueListenable<CameraStatus> get status => _status;

  @override
  Future<CameraSettingsSnapshot> getSettings() async =>
      CameraSettingsSnapshot(settings: _settings, plugged: simulatedPlugged);

  /// Mirrors camera-manager's rules (refused while a camera is on screen);
  /// nothing restarts. A camera left without a device becomes unavailable.
  @override
  Future<ApplyResult> setSettings(CameraSettings? settings) async {
    if (_status.value.view?.camera != null) {
      return const ApplyResult(
          applied: false,
          detail: 'Close the camera first: applying settings restarts camera-manager.');
    }
    _settings = settings == null
        ? simulatedDefaults
        : CameraSettings(
            devices: settings.devices,
            record: settings.record.intersection(recordable.toSet()),
            source: SettingsSource.screen);
    for (final c in CameraId.values) {
      _settings.devices.containsKey(c) ? _missing.remove(c) : _missing.add(c);
    }
    return const ApplyResult(applied: true, detail: 'Saved (simulated: nothing restarts).');
  }

  @override
  void start() {}

  @override
  void stop() => _live?.cancel();

  /// Makes a camera unavailable (or available again), as a camera with no
  /// device or a dead cable would be. For tests and the preview.
  void setMissing(CameraId camera, bool missing) {
    missing ? _missing.add(camera) : _missing.remove(camera);
    final current = _status.value.view?.camera;
    if (current == camera) _show(camera);
  }

  /// Sets one recorded camera's state, as a dead camera or a missing drive
  /// would. For tests and the preview.
  void setRecording(CameraId camera, RecordingState state, {String detail = ''}) {
    final r = _status.value.recording ?? RecordingStatus.off;
    _setRecording(RecordingStatus(
      cameras: [
        for (final c in r.cameras)
          c.camera == camera
              ? CameraRecording(
                  camera: camera,
                  state: state,
                  detail: detail,
                  segment: state == RecordingState.recording ? c.segment : '')
              : c,
      ],
      driveMounted: r.driveMounted,
      driveFreeBytes: r.driveFreeBytes,
      recordedBytes: r.recordedBytes,
      protectedBytes: r.protectedBytes,
      protectedMaxBytes: r.protectedMaxBytes,
      clipSegmentsPending: r.clipSegmentsPending,
      clockTrusted: r.clockTrusted,
      problem: r.problem,
    ));
  }

  /// Replaces the whole recording state (tests).
  void setRecordingStatus(RecordingStatus r) => _setRecording(r);

  void _setRecording(RecordingStatus r) {
    final s = _status.value;
    _status.value = CameraStatus(link: s.link, view: s.view, recording: r, simulated: true);
  }

  @override
  Future<SaveClipResult> saveClip() async {
    final refusal = saveClipRefusal;
    if (refusal != null) return SaveClipResult(saved: false, detail: refusal);
    final recording = _status.value.recording?.inState(RecordingState.recording).length ?? 0;
    if (recording == 0) {
      return const SaveClipResult(saved: false, detail: 'Nothing is recording (simulated)');
    }
    return SaveClipResult(
        saved: true,
        detail: 'SIMULATED: nothing was saved; the preview has no camera-manager',
        segmentsProtected: 2 * recording,
        segmentsToCome: 2 * recording);
  }

  @override
  Future<CameraView> move(SwitchMove move) async {
    switch (move) {
      case SwitchMove.left:
        _show(CameraId.left);
      case SwitchMove.right:
        _show(CameraId.right);
      case SwitchMove.back:
        _show(CameraId.rear);
      case SwitchMove.forward:
        _show(CameraId.front);
      case SwitchMove.press:
        _live?.cancel();
        _set(CameraView.none);
    }
    return _status.value.view!;
  }

  void _show(CameraId camera) {
    _live?.cancel();
    if (_missing.contains(camera)) {
      _set(CameraView(
          camera: camera,
          reason: CameraReason.cameraSwitch,
          feed: FeedState.unavailable,
          feedDetail: 'no ${camera.name} camera (simulated)'));
      return;
    }
    _set(CameraView(camera: camera, reason: CameraReason.cameraSwitch, feed: FeedState.starting));
    _live = Timer(startDelay, () {
      _set(CameraView(camera: camera, reason: CameraReason.cameraSwitch, feed: FeedState.live));
    });
  }

  void _set(CameraView view) {
    _status.value = CameraStatus(
        link: CameraLink.up, view: view, recording: _status.value.recording, simulated: true);
  }
}
