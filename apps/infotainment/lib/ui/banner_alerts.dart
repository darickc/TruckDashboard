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

  /// Which alert this is for clearing: its level and title, not its detail,
  /// which can change while the problem lasts (a retry's countdown).
  String get id => '${level.name}|$title';

  /// Advisories can be cleared from the banner (owner, 2026-11-11). Critical
  /// alerts can't: one cleared while driving could hide the warning that
  /// mattered (engine, "Vehicle data lost", "Not polling the truck").
  bool get clearable => level != AlertLevel.critical;

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

/// How long "Not polling the truck" must last before it shows (owner,
/// 2026-11-10). At a normal start the gateway is passive for a few seconds
/// while the CAN adapter listens (CAN_AUTO_LISTEN_S, 3 s), which isn't worth
/// an alert; one that lasts longer is.
const kNotPollingAfter = Duration(seconds: 10);

/// Holds a condition back until it has lasted [after]; it starts over each
/// time the condition clears.
class Persistence {
  Persistence(this.after);

  final Duration after;
  Duration? _since;

  /// Whether [active] has held continuously for [after] by [now] (a
  /// monotonic time).
  bool held(bool active, Duration now) {
    if (!active) {
      _since = null;
      return false;
    }
    final since = _since ??= now;
    return now - since >= after;
  }
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

/// How long a cleared advisory must be gone before it shows again when it
/// comes back. Shorter gaps are the same problem: camera-manager retries a
/// camera every 10 s, and the advisory drops out while it tries.
const kForgetClearedAfter = Duration(seconds: 30);

/// Advisories the driver has cleared. One stays hidden while it lasts, and
/// shows again if it comes back after being gone for [forgetAfter], or after
/// the dashboard restarts (nothing is saved).
class ClearedAlerts extends ChangeNotifier {
  ClearedAlerts(this.forgetAfter);

  final Duration forgetAfter;

  /// Each cleared alert's id, and when it was last active (monotonic).
  final _lastSeen = <String, Duration>{};

  /// Hides [alert] while it lasts. Critical alerts are refused.
  void clear(BannerAlert alert, Duration now) {
    if (!alert.clearable) return;
    _lastSeen[alert.id] = now;
    notifyListeners();
  }

  /// [all] without the cleared alerts that are still active, at [now]. Also
  /// forgets the ones gone for [forgetAfter].
  List<BannerAlert> visible(List<BannerAlert> all, Duration now) {
    if (_lastSeen.isEmpty) return all;
    final active = {for (final a in all) a.id};
    for (final id in active) {
      if (_lastSeen.containsKey(id)) _lastSeen[id] = now;
    }
    _lastSeen.removeWhere((id, seen) => now - seen >= forgetAfter);
    return [for (final a in all) if (!_lastSeen.containsKey(a.id)) a];
  }
}

/// Every active alert the driver hasn't cleared, critical first; within a
/// level "not polling" first, then the vehicle's (in the store's order), then
/// the cameras'.
List<BannerAlert> bannerAlerts(AppServices s) {
  final store = s.store;
  final all = [
    ...() {
      final polling = pollingAlerts(store.source);
      return s.notPolling.held(polling.isNotEmpty, store.clock.now()) ? polling : const <BannerAlert>[];
    }(),
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
  return s.cleared.visible([for (final i in order) all[i]], store.clock.now());
}
