import 'package:flutter/foundation.dart';

import '../cameras/camera_state.dart';
import '../telemetry/source_info.dart';
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

/// "Not polling the truck" (ADR-0007 amendment, 2026-11-10): the gateway is
/// passive although polling was asked for, and says why in its link detail
/// (gateway-start's --passive-reason). Passive by choice (TRANSMIT=0) gives
/// no reason and no alert. On a drive without a laptop this is the only way
/// to notice that nothing is being read. Critical, and first: it is the
/// cause of the "Vehicle data lost" alert that comes with it, which on the
/// Pi (2026-11-10) otherwise hid it behind "+1 more".
List<BannerAlert> pollingAlerts(SourceInfo src) {
  final detail = src.detail ?? '';
  const prefix = 'not polling: ';
  if (src.simulated || src.transmitEnabled != false || !detail.startsWith(prefix)) {
    return const [];
  }
  final why = detail.substring(prefix.length);
  return [
    BannerAlert(
      level: AlertLevel.critical,
      title: 'Not polling the truck',
      detail: why.isEmpty ? 'the gateway gave no reason' : '${why[0].toUpperCase()}${why.substring(1)}',
    ),
  ];
}

/// Every active alert, critical first; within a level "not polling" first,
/// then the vehicle's (in the store's order), then the cameras'.
List<BannerAlert> bannerAlerts(AppServices s) {
  final store = s.store;
  final all = [
    ...pollingAlerts(store.source),
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
