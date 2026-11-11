import 'package:flutter/foundation.dart';

import '../cameras/camera_state.dart';
import '../telemetry/warnings.dart';
import 'app_scope.dart';
import 'presentation.dart';

/// One alert as the banner shows it: the vehicle's alerts (TelemetryStore)
/// and camera-manager's, in one list. The telemetry model stays about
/// signals; camera alerts join here, in the UI, so they show wherever the
/// banner does: above every screen, and in camera mode in the status bar's
/// place.
@immutable
class BannerAlert {
  const BannerAlert({
    required this.level,
    required this.title,
    required this.detail,
    this.simulated = false,
  });

  final AlertLevel level;
  final String title;
  final String detail;

  /// It comes from a simulated source (marked SIM where the SIMULATED badge
  /// isn't visible).
  final bool simulated;

  @override
  String toString() => 'BannerAlert($level, "$title", "$detail", simulated: $simulated)';
}

/// Advisories for recording (ADR-0027 decision 9): every camera set to
/// record that isn't, so a dead dashcam isn't discovered after the incident
/// it missed, and the recording problem that isn't one camera's. Nothing
/// without camera-manager (the dashboard can't say) or with recording off.
List<BannerAlert> recordingAlerts(CameraStatus c) {
  final r = c.recording;
  if (r == null || r.isOff) return const [];
  return [
    for (final cam in r.inState(RecordingState.notRecording))
      BannerAlert(
        level: AlertLevel.advisory,
        title: '${cam.camera == null ? 'A camera' : cameraName(cam.camera!)} not recording',
        detail: cam.detail.isEmpty ? 'camera-manager gave no reason' : cam.detail,
        simulated: c.simulated,
      ),
    if (r.problem.isNotEmpty)
      BannerAlert(
        level: AlertLevel.advisory,
        title: 'Camera recording',
        detail: r.problem,
        simulated: c.simulated,
      ),
  ];
}

/// Every active alert, critical first; within a level the vehicle's come
/// before the cameras', in the store's order.
List<BannerAlert> bannerAlerts(AppServices s) {
  final store = s.store;
  final all = [
    for (final a in store.alerts)
      () {
        final (title, detail) = describeAlert(a, store, s.settings.units);
        return BannerAlert(
            level: a.level, title: title, detail: detail, simulated: store.source.simulated);
      }(),
    ...recordingAlerts(s.cameras.status.value),
  ];
  // List.sort isn't stable; sort indices to keep the order within a level.
  final order = List.generate(all.length, (i) => i)
    ..sort((a, b) {
      final byLevel = all[b].level.index.compareTo(all[a].level.index);
      return byLevel != 0 ? byLevel : a.compareTo(b);
    });
  return [for (final i in order) all[i]];
}
