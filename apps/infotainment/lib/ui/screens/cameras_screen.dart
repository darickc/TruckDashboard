import 'package:flutter/material.dart';

import '../../cameras/camera_state.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/badges.dart';
import '../widgets/panel.dart';
import '../widgets/tap_target.dart';

/// Picks a camera by hand (the same moves as the 5-way switch) and says how
/// the camera system stands. A chosen camera replaces every screen with
/// camera mode (shell/camera_mode.dart) until it is closed.
class CamerasScreen extends StatelessWidget {
  const CamerasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ValueListenableBuilder(
      valueListenable: s.cameras.status,
      builder: (context, status, _) {
        final p = Palette.of(context);
        final up = status.link == CameraLink.up;
        return Panel(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Cameras',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.text)),
              const SizedBox(width: 12),
              _link(status, p),
            ]),
            const SizedBox(height: 10),
            if (up)
              SizedBox(
                height: 76,
                child: Row(children: [
                  for (final (camera, move, icon) in const [
                    (CameraId.front, SwitchMove.forward, Icons.arrow_upward_rounded),
                    (CameraId.left, SwitchMove.left, Icons.arrow_back_rounded),
                    (CameraId.rear, SwitchMove.back, Icons.arrow_downward_rounded),
                    (CameraId.right, SwitchMove.right, Icons.arrow_forward_rounded),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: TapTarget(
                          key: ValueKey('cameras-open-${camera.name}'),
                          label: 'Show the ${cameraName(camera).toLowerCase()}',
                          onTap: () => s.cameras.move(move).ignore(),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(icon, size: 28, color: p.text),
                            const SizedBox(height: 2),
                            Text(cameraName(camera).split(' ').first,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
                          ]),
                        ),
                      ),
                    ),
                ]),
              )
            else
              Text(
                  status.link == CameraLink.connecting
                      ? 'Connecting to camera-manager…'
                      : 'camera-manager isn\'t reachable${status.detail == null ? '' : ': ${status.detail}'}. '
                          'No camera can be shown until it is.',
                  key: const ValueKey('cameras-unreachable'),
                  style: TextStyle(fontSize: 16, color: p.text)),
            const SizedBox(height: 10),
            if (up) ...[
              _line(p, Icons.swap_vert_rounded, _reverseText(status.view?.reverse)),
              if (status.view?.blockedBySpeed ?? false)
                _line(p, Icons.speed_rounded,
                    'Hidden above the speed limit; it shows again when slower.'),
            ],
            _line(p, Icons.gamepad_outlined,
                'The camera switch does the same: forward front, back rear. Press closes.'),
            const Spacer(),
            Text('Not a safety system. Always use the mirrors.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.advisory)),
          ]),
        );
      },
    );
  }

  Widget _link(CameraStatus status, Palette p) => switch (status.link) {
        CameraLink.up when status.simulated =>
          Pill('SIMULATED: NO PICTURE', key: const ValueKey('cameras-link'), color: p.simulated, filled: true),
        CameraLink.up => Pill('CONNECTED', key: const ValueKey('cameras-link'), color: p.ok),
        CameraLink.connecting => Pill('CONNECTING', key: const ValueKey('cameras-link'), color: p.stale),
        CameraLink.down => Pill('OFFLINE', key: const ValueKey('cameras-link'), color: p.advisory),
      };

  static String _reverseText(ReverseStatus? r) => switch (r) {
        ReverseStatus.off || null =>
          'Rear camera in reverse: off until the reverse signal is verified.',
        ReverseStatus.unknown => 'Reverse signal unknown: no automatic rear camera.',
        ReverseStatus.notEngaged => 'Rear camera in reverse: ready.',
        ReverseStatus.engaged => 'In reverse.',
      };

  Widget _line(Palette p, IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: p.textDim),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 15, color: p.textDim))),
        ]),
      );
}
