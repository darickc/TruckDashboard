import 'package:flutter/material.dart';

import '../../cameras/camera_state.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/badges.dart';
import '../widgets/panel.dart';
import '../widgets/save_clip_button.dart';
import '../widgets/tap_target.dart';

/// Picks a camera by hand (the same moves as the 5-way switch) and says how
/// the camera system stands: on the left the cameras, on the right front and
/// rear recording (ADR-0027) with "Save clip". A chosen camera replaces every
/// screen with camera mode (shell/camera_mode.dart) until it is closed.
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
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _cameras(context, s, status, p, up)),
                if (up) ...[
                  VerticalDivider(width: 24, color: p.border),
                  Expanded(child: _Recording(status: status)),
                ],
              ]),
            ),
            Text('Not a safety system. Always use the mirrors.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.advisory)),
          ]),
        );
      },
    );
  }

  Widget _cameras(
      BuildContext context, AppServices s, CameraStatus status, Palette p, bool up) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (up)
              SizedBox(
                height: 64,
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
                            Icon(icon, size: 24, color: p.text),
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
            const SizedBox(height: 8),
            // Scrolls only if the lines outgrow the panel (an alert banner
            // above it): the buttons stay put.
            Expanded(
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (up) ...[
                    _line(p, Icons.swap_vert_rounded, _reverseText(status.view?.reverse)),
                    if (status.view?.blockedBySpeed ?? false)
                      _line(p, Icons.speed_rounded,
                          'Hidden above the speed limit; it shows again when slower.'),
                  ],
                  _line(p, Icons.gamepad_outlined,
                      'The camera switch does the same: forward front, back rear. Press closes.'),
                ]),
              ),
            ),
    ]);
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

  static Widget _line(Palette p, IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: p.textDim),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 14, color: p.textDim))),
        ]),
      );
}

/// Front and rear recording as camera-manager reports it, and Save clip.
/// Only from camera-manager: nothing is claimed before it says.
class _Recording extends StatelessWidget {
  const _Recording({required this.status});

  final CameraStatus status;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final r = status.recording;
    Widget line(String key, IconData icon, Color color, String text, {int maxLines = 1}) => Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text,
                    key: ValueKey(key),
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: color == p.textDim ? p.textDim : p.text))),
          ]),
        );
    final header = Row(children: [
      Text('Recording', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text)),
      if (status.simulated) ...[
        const SizedBox(width: 10),
        Pill('SIMULATED', key: const ValueKey('recording-simulated'), color: p.simulated),
      ],
    ]);
    if (r == null || r.isOff) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        header,
        const SizedBox(height: 6),
        Text(
            r == null
                ? "camera-manager hasn't reported recording."
                : 'Recording is off (RECORD_CAMERAS).',
            key: const ValueKey('recording-off'),
            style: TextStyle(fontSize: 15, color: p.textDim)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      header,
      const SizedBox(height: 6),
      // Scrolls only if the lines outgrow the panel; Save clip stays put.
      Expanded(
          child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final c in r.cameras)
        switch (c.state) {
          RecordingState.recording => line(
              'recording-${c.camera?.name ?? 'unknown'}',
              Icons.fiber_manual_record,
              status.simulated ? p.simulated : p.critical,
              '${cameraShortName(c.camera)}: recording'
              '${c.segment.isEmpty ? '' : ' (${c.segment})'}'),
          RecordingState.starting => line('recording-${c.camera?.name ?? 'unknown'}',
              Icons.hourglass_top_rounded, p.textDim,
              '${cameraShortName(c.camera)}: starting${c.detail.isEmpty ? '' : ': ${c.detail}'}'),
          RecordingState.notRecording => line(
              'recording-${c.camera?.name ?? 'unknown'}',
              Icons.warning_amber_rounded,
              p.advisory,
              '${cameraShortName(c.camera)}: not recording'
              '${c.detail.isEmpty ? '' : ': ${c.detail}'}',
              maxLines: 2),
        },
      if (r.driveMounted)
        line('recording-drive', Icons.storage_rounded, p.textDim,
            'Drive: ${formatGb(r.driveFreeBytes)} free · video ${formatGb(r.recordedBytes)}')
      else
        line('recording-drive', Icons.storage_rounded, p.advisory,
            'No data drive: nothing records, never to the SD card.',
            maxLines: 2),
      line(
          'recording-clips',
          Icons.bookmark_outline_rounded,
          p.textDim,
          'Saved clips: ${formatGb(r.protectedBytes)} of ${formatGb(r.protectedMaxBytes)}'
          '${r.clipSegmentsPending > 0 ? ' · ${r.clipSegmentsPending} to come' : ''}'),
      if (!r.clockTrusted)
        line('recording-clock', Icons.schedule_rounded, p.textDim,
            'Clock not synchronized: no dates in names, no deleting by age.',
            maxLines: 2),
      if (r.problem.isNotEmpty)
        line('recording-problem', Icons.error_outline, p.advisory, r.problem, maxLines: 2),
      ]))),
      const SizedBox(height: 4),
      const SizedBox(
          width: double.infinity, child: SaveClipButton(keyPrefix: 'cameras-save-clip')),
      const SizedBox(height: 6),
    ]);
  }
}
