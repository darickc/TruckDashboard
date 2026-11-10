import 'package:flutter/material.dart';

import '../../cameras/camera_state.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/tap_target.dart';

/// The dashboard while camera-manager shows a camera (ADR-0009). The layout
/// is fixed so it lines up with the compositor's activation area
/// (agl/flutter/config.toml: x 220, y 44, 580×435; the dashboard's camera
/// area is one row taller, to the screen's bottom):
///
///   0–44, full width    the status bar (with the camera chip), or the alert
///                       bar while an alert is active: alerts stay above the
///                       camera, never under it
///   44–480, x 0–220     [CameraControls]: every camera and Close
///   44–480, x 220–800   [CameraArea]: camera-manager's window covers it
///                       while live (a 4:3 picture at 580×435)
///
/// The dashboard draws nothing over the picture and never claims a picture
/// it can't confirm: it only shows what camera-manager reports. Which
/// camera is up shows twice: the highlighted button and the status chip
/// (owner, 2026-11-10: the camera strip went, for a bigger picture).

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

/// The left column while a camera shows: every camera and Close, sent to
/// camera-manager as switch moves. They do what the switch does (forward
/// front, left, back rear, right; press closes). Five buttons over 436 px,
/// each about 85 px tall.
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
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: SizedBox(
              width: double.infinity,
              child: TapTarget(
                key: ValueKey(key),
                label: label,
                selected: selected,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                onTap: () => s.cameras.move(move).ignore(),
                child: Row(children: [
                  Icon(icon, size: 30, color: selected ? p.accent : p.text),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: selected ? p.accent : p.text)),
                  ),
                ]),
              ),
            ),
          ),
        );

    return Container(
      key: const ValueKey('camera-controls'),
      width: kCameraControlsWidth,
      color: p.surface,
      padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
      child: Column(children: [
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
