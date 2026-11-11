import 'package:f250_infotainment/cameras/camera_settings.dart';
import 'package:f250_infotainment/cameras/camera_state.dart';
import 'package:flutter/foundation.dart';

/// A camera-manager whose status the test sets directly; records moves and
/// answers "save clip" with [saveResult] (or throws [saveError]).
class FakeCameras implements CameraSource {
  FakeCameras(CameraStatus initial) : _status = ValueNotifier(initial);

  final ValueNotifier<CameraStatus> _status;
  final moves = <SwitchMove>[];
  int saves = 0;
  SaveClipResult saveResult =
      const SaveClipResult(saved: true, segmentsProtected: 4, segmentsToCome: 4);
  Object? saveError;

  set status(CameraStatus s) => _status.value = s;

  @override
  ValueListenable<CameraStatus> get status => _status;
  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<CameraView> move(SwitchMove move) async {
    moves.add(move);
    return _status.value.view ?? CameraView.none;
  }

  CameraSettingsSnapshot settings = const CameraSettingsSnapshot(settings: CameraSettings());
  final applied = <CameraSettings?>[];
  ApplyResult applyResult = const ApplyResult(applied: true, detail: 'Saved.');

  @override
  Future<CameraSettingsSnapshot> getSettings() async => settings;

  @override
  Future<ApplyResult> setSettings(CameraSettings? s) async {
    applied.add(s);
    return applyResult;
  }

  @override
  Future<SaveClipResult> saveClip() async {
    saves++;
    final e = saveError;
    if (e != null) throw e;
    return saveResult;
  }
}

CameraStatus up(CameraView view, {RecordingStatus? recording}) =>
    CameraStatus(link: CameraLink.up, view: view, recording: recording);
