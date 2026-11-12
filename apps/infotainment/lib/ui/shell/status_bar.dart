import 'package:flutter/material.dart';

import '../../cameras/camera_state.dart';
import '../../nav/map_update.dart';
import '../../telemetry/telemetry_store.dart';
import '../app_scope.dart';
import '../presentation.dart';
import '../theme.dart';
import '../widgets/badges.dart';
import 'nav_buttons.dart';

String linkLabel(LinkState s) => switch (s) {
      LinkState.connecting => 'Connecting',
      LinkState.up => 'Link up',
      LinkState.degraded => 'Degraded',
      LinkState.down => 'Link down',
    };

Color linkColor(LinkState s, Palette p) => switch (s) {
      LinkState.connecting => p.stale,
      LinkState.up => p.ok,
      LinkState.degraded => p.advisory,
      LinkState.down => p.critical,
    };

/// The camera on screen (it stays named when an alert takes the camera
/// strip), or camera-manager being unreachable. Nothing while it is
/// connecting or idle.
List<Widget> _cameraChip(CameraStatus c, Palette p) {
  final camera = c.camera;
  final (String? text, Color color) = switch (c.link) {
    CameraLink.up when camera != null => (
        // Reverse always shows the rear camera; the word says why.
        c.view?.reason == CameraReason.reverse
            ? 'REVERSE'
            : '${camera.name.toUpperCase()} CAMERA',
        c.view?.feed == FeedState.unavailable
            ? p.critical
            : c.view?.reason == CameraReason.reverse
                ? p.advisory
                : p.accent
      ),
    CameraLink.down => ('CAMERAS OFFLINE', p.advisory),
    _ => (null, p.textDim),
  };
  if (text == null) return const [];
  return [Pill(text, key: const ValueKey('camera-chip'), color: color), const SizedBox(width: 10)];
}

/// A map stick being imported (ADR-0033), or one that just finished, so it
/// shows on every screen: the Nav screen says more.
List<Widget> _mapUpdateChip(MapUpdateStatus? u, DateTime now, Palette p) {
  if (u == null || !u.shownAt(now)) return const [];
  final (String text, Color color) = switch (u.state) {
    MapUpdateState.copying => ('MAP ${u.percent}%', p.accent),
    MapUpdateState.checking => ('MAP CHECK', p.accent),
    MapUpdateState.updated => ('MAP UPDATED', p.ok),
    MapUpdateState.current => ('MAP UP TO DATE', p.ok),
    MapUpdateState.failed => ('MAP UPDATE FAILED', p.advisory),
  };
  return [Pill(text, key: const ValueKey('map-update-chip'), color: color), const SizedBox(width: 10)];
}

/// Recording (ADR-0027 decision 9), only as camera-manager reports it: the
/// recorded cameras that are recording ("REC FRONT REAR"), or, if any camera
/// set to record isn't, which ("NOT RECORDING: REAR") in the advisory
/// colour. "SIM" in front of either with the simulated source. Null without
/// camera-manager or with recording off.
Widget? _recordingChip(CameraStatus c, Palette p) {
  final r = c.recording;
  if (r == null || r.isOff) return null;
  String names(Iterable<CameraRecording> cams) =>
      cams.map((x) => cameraShortName(x.camera).toUpperCase()).join(' ');
  final sim = c.simulated ? 'SIM ' : '';
  final down = r.inState(RecordingState.notRecording);
  final rec = r.inState(RecordingState.recording);
  final (String text, Color color, bool filled) = down.isNotEmpty
      ? ('${sim}NOT RECORDING: ${names(down)}', p.advisory, false)
      : rec.isNotEmpty
          ? ('${sim}REC ${names(rec)}', c.simulated ? p.simulated : p.critical, !c.simulated)
          : ('${sim}REC STARTING', p.stale, false);
  return Pill(text, key: const ValueKey('rec-chip'), color: color, filled: filled);
}

/// Always-visible strip. Left: Back (and Home) outside camera mode, then
/// the scenario name. Centre, on the panel's centre line: the data source and
/// link health. Right: chips, and the clock at the right edge. Only Back and
/// Home are tappable; the rest is for glancing.
///
/// [navigation] is the shell's normal mode: the bar holds Back, so it is a
/// full touch target high (kMinTouch) on every screen, Home included, and
/// nothing moves between screens. Camera mode keeps it 44 high, with no
/// Back: the camera's window sits right under it.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, this.navigation = false});

  final bool navigation;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.store, s.cameras.status, s.map.update]),
      builder: (context, _) {
        final p = Palette.of(context);
        final link = s.store.link;
        final source = s.store.source;
        final now = DateTime.now();
        final clock = formatClock(now);
        final rec = _recordingChip(s.cameras.status.value, p);
        // The two sides share what the centre leaves equally, so the centre
        // is on the panel's centre line. Chips are Flexible and ellipsize
        // rather than overflow. The clock is the right side's last child, so
        // it is flush right. (A loose Flexible beside a Spacer once left
        // blank space after the clock: on the truck, with no scenario name,
        // it sat half the free width left of the edge.)
        List<Widget> flexible(List<Widget> chip) =>
            [for (final w in chip) w is SizedBox ? w : Flexible(child: w)];
        return Container(
          height: navigation ? kMinTouch : kStatusBarHeight,
          color: p.surface,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(
              child: Row(children: [
                if (navigation) const NavButtons(),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(source.scenario ?? '',
                        key: const ValueKey('status-scenario'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: p.textDim)),
                  ),
                ),
              ]),
            ),
            Row(key: const ValueKey('status-link'), mainAxisSize: MainAxisSize.min, children: [
              if (source.simulated) ...[
                Pill('SIMULATED', key: const ValueKey('simulated-badge'), color: p.simulated, filled: true),
                const SizedBox(width: 8),
              ],
              Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: linkColor(link, p), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(linkLabel(link),
                  key: const ValueKey('link-state'),
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: linkColor(link, p))),
              const SizedBox(width: 6),
              Text('· ${formatAge(s.store.clock.now() - s.store.linkSince)}',
                  style: TextStyle(fontSize: 13, color: p.textDim)),
            ]),
            Expanded(
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                const SizedBox(width: 10),
                if (rec != null)
                  Flexible(flex: 3, child: Padding(padding: const EdgeInsets.only(right: 10), child: rec)),
                ...flexible(_mapUpdateChip(s.map.update.value, now, p)),
                ...flexible(_cameraChip(s.cameras.status.value, p)),
                Text(clock,
                    key: const ValueKey('status-clock'),
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w600, fontFeatures: tabular, color: p.text)),
              ]),
            ),
          ]),
        );
      },
    );
  }
}
