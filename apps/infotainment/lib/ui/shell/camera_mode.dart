import 'package:flutter/material.dart';

import '../../cameras/camera_state.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/badges.dart';
import '../widgets/tap_target.dart';

/// The dashboard while camera-manager shows a camera (ADR-0009). The layout
/// is fixed so it lines up with the compositor's activation area
/// (agl/flutter/config.toml, y 96–416):
///
///   0–44     status bar (with the camera chip)
///   44–96    [CameraStrip], or the alert banner when an alert is active
///   96–416   [CameraArea]: camera-manager's window covers it while live
///   416–480  [CameraControls] in place of the nav bar
///
/// The dashboard draws nothing over the picture and never claims a picture
/// it can't confirm: it only shows what camera-manager reports.

/// Which camera is up and why, in the alert banner's strip while no alert
/// is active. The strip is reserved either way, so the camera area never
/// moves.
class CameraStrip extends StatelessWidget {
  const CameraStrip({super.key, required this.view});

  final CameraView view;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final reverse = view.reason == CameraReason.reverse;
    return Container(
      key: const ValueKey('camera-strip'),
      height: kAlertBannerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: p.surfaceHigh,
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(children: [
        Icon(Icons.videocam_rounded, size: 28, color: p.text),
        const SizedBox(width: 10),
        Text(cameraName(view.camera!),
            key: const ValueKey('camera-strip-name'),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.text)),
        const SizedBox(width: 10),
        if (reverse)
          Pill('REVERSE', key: const ValueKey('camera-strip-reverse'), color: p.advisory, filled: true)
        else
          Pill('SWITCH', color: p.textDim),
        const SizedBox(width: 12),
        Expanded(
          child: Text('Not a safety system. Use the mirrors.',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: p.textDim)),
        ),
      ]),
    );
  }
}

/// The area under camera-manager's window: what the driver sees when there
/// is no picture.
class CameraArea extends StatelessWidget {
  const CameraArea({super.key, required this.view, required this.simulated});

  final CameraView view;
  final bool simulated;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final name = cameraName(view.camera!);
    final (IconData icon, Color color, String title, String detail) = switch (view.feed) {
      FeedState.live when simulated => (
          Icons.videocam_outlined,
          p.simulated,
          'SIMULATED: no camera picture',
          '$name would be live here. The preview has no camera-manager.'
        ),
      // camera-manager's window covers this; it shows only if the window
      // isn't there.
      FeedState.live => (
          Icons.videocam_outlined,
          p.textDim,
          '$name is live',
          'The picture should cover this area. If you can read this, it isn\'t showing.'
        ),
      FeedState.unavailable => (
          Icons.videocam_off_rounded,
          p.critical,
          '$name unavailable',
          view.feedDetail.isEmpty ? 'Use the mirrors.' : '${view.feedDetail}. Use the mirrors.'
        ),
      FeedState.starting || null => (
          Icons.hourglass_top_rounded,
          p.textDim,
          'Starting ${name.toLowerCase()}…',
          'Use the mirrors until the picture shows.'
        ),
    };
    return Container(
      key: const ValueKey('camera-area'),
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 48, color: color),
        const SizedBox(height: 8),
        Text(title,
            key: const ValueKey('camera-area-title'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 6),
        Text(detail,
            key: const ValueKey('camera-area-detail'),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, color: Color(0xFFB8BEC6))),
      ]),
    );
  }
}

/// The nav bar's place while a camera shows: every camera and Close, sent to
/// camera-manager as switch moves. They do what the switch does (forward
/// front, left, back rear, right; press closes).
class CameraControls extends StatelessWidget {
  const CameraControls({super.key, required this.view});

  final CameraView view;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);

    Widget button(String key, String label, IconData icon, SwitchMove move, {bool selected = false}) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: TapTarget(
              key: ValueKey(key),
              label: label,
              selected: selected,
              padding: EdgeInsets.zero,
              onTap: () => s.cameras.move(move).ignore(),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 26, color: selected ? p.accent : p.text),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: selected ? p.accent : p.text)),
              ]),
            ),
          ),
        );

    return Container(
      key: const ValueKey('camera-controls'),
      height: kNavBarHeight,
      color: p.surface,
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      child: Row(children: [
        button('camera-front', 'Front', Icons.arrow_upward_rounded, SwitchMove.forward,
            selected: view.camera == CameraId.front),
        button('camera-left', 'Left', Icons.arrow_back_rounded, SwitchMove.left,
            selected: view.camera == CameraId.left),
        button('camera-rear', 'Rear', Icons.arrow_downward_rounded, SwitchMove.back,
            selected: view.camera == CameraId.rear),
        button('camera-right', 'Right', Icons.arrow_forward_rounded, SwitchMove.right,
            selected: view.camera == CameraId.right),
        button('camera-close', 'Close', Icons.close_rounded, SwitchMove.press),
      ]),
    );
  }
}
