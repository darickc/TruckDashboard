import 'package:flutter/material.dart';

import '../../cameras/camera_state.dart';
import '../../telemetry/telemetry_store.dart';
import '../app_scope.dart';
import '../presentation.dart';
import '../theme.dart';
import '../widgets/badges.dart';

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

/// Recording (ADR-0027 decision 9), only as camera-manager reports it: the
/// recorded cameras that are recording ("REC FRONT REAR"), or, if any camera
/// set to record isn't, which ("NOT RECORDING: REAR") in the advisory
/// colour. "SIM" in front of either with the simulated source. Nothing
/// without camera-manager or with recording off: then a spacer, which keeps
/// the clock at the right edge.
List<Widget> _recordingChip(CameraStatus c, Palette p) {
  final r = c.recording;
  if (r == null || r.isOff) return const [Spacer()];
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
  // Right-aligned in three quarters of the space the scenario name and it
  // share, so it ellipsizes (after "REC") rather than overflow, and the
  // clock stays at the right edge.
  return [
    Expanded(
        flex: 3,
        child: Align(
            alignment: Alignment.centerRight,
            child: Pill(text, key: const ValueKey('rec-chip'), color: color, filled: filled))),
    const SizedBox(width: 10),
  ];
}

/// Always-visible strip: data source, link health, clock. Nothing here is
/// tappable; it is for glancing.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.store, s.cameras.status]),
      builder: (context, _) {
        final p = Palette.of(context);
        final link = s.store.link;
        final source = s.store.source;
        final now = DateTime.now();
        final clock = formatClock(now);
        return Container(
          height: kStatusBarHeight,
          color: p.surface,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
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
            const SizedBox(width: 12),
            // Loose: a short name leaves its space blank, so a REC pill
            // beside it stays right-aligned.
            Flexible(
              child: Text(source.scenario ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: p.textDim)),
            ),
            ..._recordingChip(s.cameras.status.value, p),
            ..._cameraChip(s.cameras.status.value, p),
            Text(clock,
                key: const ValueKey('status-clock'),
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w600, fontFeatures: tabular, color: p.text)),
          ]),
        );
      },
    );
  }
}
