import 'dart:async';

import 'package:flutter/foundation.dart';

import 'camera_state.dart';

/// Stands in for camera-manager in the browser preview and with the in-app
/// simulator. It follows camera-manager's default switch mapping
/// (crates/camera-policy: forward, left, right and back pick a camera; press
/// closes it) and reports the feed starting, then live after [startDelay]
/// (0.62 s on the bench, bench-log 2026-11-09). There is no picture: the
/// status says simulated, and the dashboard says so on screen.
class SimulatedCameraSource implements CameraSource {
  SimulatedCameraSource({
    this.startDelay = const Duration(milliseconds: 620),
    Set<CameraId> missing = const {},
  }) : _missing = {...missing};

  final Duration startDelay;
  final Set<CameraId> _missing;
  Timer? _live;

  final _status = ValueNotifier(const CameraStatus(
      link: CameraLink.up, view: CameraView.none, simulated: true));

  @override
  ValueListenable<CameraStatus> get status => _status;

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
    _status.value = CameraStatus(link: CameraLink.up, view: view, simulated: true);
  }
}
