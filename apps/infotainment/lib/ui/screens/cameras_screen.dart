import 'package:flutter/material.dart';

import '../../cameras/camera_state.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/badges.dart';
import '../widgets/panel.dart';
import '../widgets/save_clip_button.dart';
import '../widgets/tap_target.dart';

/// Picks a camera by hand and says how the camera system stands: on the
/// left a top-down truck with a button where each camera is (the same moves
/// as the 5-way switch), on the right front and rear recording (ADR-0027)
/// with "Save clip" and the way to copy recordings to a USB stick
/// (ADR-0037). A chosen camera replaces every screen with camera mode
/// (shell/camera_mode.dart) until it is closed.
class CamerasScreen extends StatelessWidget {
  const CamerasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ValueListenableBuilder(
      valueListenable: s.cameras.status,
      builder: (context, status, _) {
        final up = status.link == CameraLink.up;
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: 372, child: _Picker(status: status)),
          const SizedBox(width: kGap),
          Expanded(child: up ? _Recording(status: status) : _Offline(status: status)),
        ]);
      },
    );
  }
}

Widget _link(CameraStatus status, Palette p) => switch (status.link) {
      CameraLink.up when status.simulated =>
        Pill('SIMULATED: NO PICTURE', key: const ValueKey('cameras-link'), color: p.simulated, filled: true),
      CameraLink.up => Pill('CONNECTED', key: const ValueKey('cameras-link'), color: p.ok),
      CameraLink.connecting => Pill('CONNECTING', key: const ValueKey('cameras-link'), color: p.stale),
      CameraLink.down => Pill('OFFLINE', key: const ValueKey('cameras-link'), color: p.advisory),
    };

/// The cameras on a top-down truck, front up: Front above it, Rear below,
/// Left and Right beside it, each a full touch target.
class _Picker extends StatelessWidget {
  const _Picker({required this.status});

  final CameraStatus status;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final up = status.link == CameraLink.up;
    Widget button(CameraId camera, SwitchMove move, IconData? icon, double width) => SizedBox(
          width: width,
          height: kMinTouch,
          child: TapTarget(
            key: ValueKey('cameras-open-${camera.name}'),
            label: 'Show the ${cameraName(camera).toLowerCase()}',
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onTap: () => s.cameras.move(move).ignore(),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 22, color: p.text), const SizedBox(width: 4)],
              Flexible(
                child: Text(cameraShortName(camera),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
              ),
            ]),
          ),
        );
    final view = status.view;
    return Panel(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('Cameras', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.text)),
          const SizedBox(width: 12),
          Flexible(child: _link(status, p)),
        ]),
        const SizedBox(height: 8),
        if (!up)
          Expanded(
            child: Text(
                status.link == CameraLink.connecting
                    ? 'Connecting to camera-manager…'
                    : 'camera-manager isn\'t reachable${status.detail == null ? '' : ': ${status.detail}'}. '
                        'No camera can be shown until it is.',
                key: const ValueKey('cameras-unreachable'),
                style: TextStyle(fontSize: 16, color: p.text)),
          )
        else ...[
          Center(child: button(CameraId.front, SwitchMove.forward, Icons.arrow_upward_rounded, 150)),
          const SizedBox(height: 6),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: button(CameraId.left, SwitchMove.left, null, 96)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: CustomPaint(
                    key: const ValueKey('cameras-truck'),
                    size: Size.infinite,
                    painter: TruckPainter(
                      body: p.surfaceHigh,
                      outline: p.border,
                      glass: p.textDim.withValues(alpha: 0.35),
                      camera: p.accent,
                    ),
                  ),
                ),
              ),
              Center(child: button(CameraId.right, SwitchMove.right, null, 96)),
            ]),
          ),
          const SizedBox(height: 6),
          Center(child: button(CameraId.rear, SwitchMove.back, Icons.arrow_downward_rounded, 150)),
          const SizedBox(height: 8),
          _line(p, Icons.swap_vert_rounded, _reverseText(view?.reverse)),
          if (view?.blockedBySpeed ?? false)
            _line(p, Icons.speed_rounded, 'Hidden above the speed limit; it shows again when slower.'),
        ],
      ]),
    );
  }

  static String _reverseText(ReverseStatus? r) => switch (r) {
        ReverseStatus.off || null => 'Rear camera in reverse: off until the reverse signal is verified.',
        ReverseStatus.unknown => 'Reverse signal unknown: no automatic rear camera.',
        ReverseStatus.notEngaged => 'Rear camera in reverse: ready.',
        ReverseStatus.engaged => 'In reverse.',
      };
}

Widget _line(Palette p, IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: p.textDim),
        const SizedBox(width: 6),
        Expanded(
            child: Text(text,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.textDim))),
      ]),
    );

/// A top-down pickup, front up, scaled to fit: cab, hood, bed, and a dot
/// where each camera looks out. A picture to place the buttons by, not a
/// claim about where the cameras are mounted.
class TruckPainter extends CustomPainter {
  const TruckPainter({required this.body, required this.outline, required this.glass, required this.camera});

  final Color body, outline, glass, camera;

  @override
  void paint(Canvas canvas, Size size) {
    // About a crew cab long bed's proportions: 2 wide, 5 long.
    final h = size.height.clamp(0.0, size.width * 2.6);
    final w = h / 2.6;
    if (w < 12) return;
    final r = Rect.fromCenter(center: size.center(Offset.zero), width: w, height: h);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = outline;
    final fill = Paint()..color = body;
    final shell = RRect.fromRectAndCorners(r,
        topLeft: Radius.circular(w * 0.28),
        topRight: Radius.circular(w * 0.28),
        bottomLeft: Radius.circular(w * 0.1),
        bottomRight: Radius.circular(w * 0.1));
    canvas.drawRRect(shell, fill);
    canvas.drawRRect(shell, stroke);
    final inset = w * 0.12;
    // Windshield, roof, rear window.
    canvas.drawRRect(
        RRect.fromLTRBR(r.left + inset, r.top + h * 0.17, r.right - inset, r.top + h * 0.27, Radius.circular(w * 0.08)),
        Paint()..color = glass);
    canvas.drawRRect(
        RRect.fromLTRBR(r.left + inset, r.top + h * 0.29, r.right - inset, r.top + h * 0.47, Radius.circular(w * 0.04)),
        Paint()..color = outline.withValues(alpha: 0.5));
    canvas.drawRect(Rect.fromLTRB(r.left + inset, r.top + h * 0.48, r.right - inset, r.top + h * 0.52),
        Paint()..color = glass);
    // Bed.
    canvas.drawRRect(
        RRect.fromLTRBR(r.left + inset * 0.8, r.top + h * 0.56, r.right - inset * 0.8, r.bottom - inset * 0.8,
            Radius.circular(w * 0.04)),
        stroke);
    // Mirrors.
    final mirror = Paint()..color = outline;
    canvas.drawRRect(
        RRect.fromLTRBR(r.left - w * 0.12, r.top + h * 0.24, r.left, r.top + h * 0.29, const Radius.circular(2)),
        mirror);
    canvas.drawRRect(
        RRect.fromLTRBR(r.right, r.top + h * 0.24, r.right + w * 0.12, r.top + h * 0.29, const Radius.circular(2)),
        mirror);
    // Where each camera looks out.
    final dot = Paint()..color = camera;
    final d = (w * 0.07).clamp(3.0, 6.0);
    canvas.drawCircle(Offset(r.center.dx, r.top - d * 1.6), d, dot);
    canvas.drawCircle(Offset(r.center.dx, r.bottom + d * 1.6), d, dot);
    canvas.drawCircle(Offset(r.left - w * 0.12 - d * 1.6, r.top + h * 0.265), d, dot);
    canvas.drawCircle(Offset(r.right + w * 0.12 + d * 1.6, r.top + h * 0.265), d, dot);
  }

  @override
  bool shouldRepaint(TruckPainter old) =>
      old.body != body || old.outline != outline || old.glass != glass || old.camera != camera;
}

/// The two ways out that don't need a camera: copying recordings to a USB
/// stick (usb-export's, ADR-0037), and the safety reminder.
Widget _toUsb(BuildContext context, {required bool wide}) {
  final s = AppScope.of(context);
  final p = Palette.of(context);
  return TapTarget(
    key: const ValueKey('cameras-recordings'),
    label: 'Copy recordings to a USB stick',
    onTap: () => s.screens.open(AppScreen.recordings),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.usb_rounded, size: 24, color: p.text),
      const SizedBox(width: 8),
      Flexible(
        child: Text(wide ? 'Recordings to USB' : 'To USB',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
      ),
    ]),
  );
}

// Never cut short: it wraps instead (the panel's font cut it to "…mirr…",
// bench 2026-11-19).
Widget _safety(Palette p) => Text('Not a safety system. Always use the mirrors.',
    key: const ValueKey('cameras-safety'),
    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.advisory));

/// Without camera-manager: recordings can still be copied.
class _Offline extends StatelessWidget {
  const _Offline({required this.status});

  final CameraStatus status;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Panel(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Recordings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.text)),
        const SizedBox(height: 6),
        Text('Copying recordings to a USB stick works without camera-manager.',
            style: TextStyle(fontSize: 14, color: p.textDim)),
        const Spacer(),
        SizedBox(height: kMinTouch, child: _toUsb(context, wide: true)),
        const SizedBox(height: 8),
        _safety(p),
      ]),
    );
  }
}

/// Front and rear recording as camera-manager reports it, storage as bars,
/// and Save clip. Only from camera-manager: nothing is claimed before it
/// says.
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
    Widget meter(String key, String text, double? fraction, Color color, {Color? textColor}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(text,
                key: ValueKey(key),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontFeatures: tabular, color: textColor ?? p.textDim)),
            if (fraction != null) ...[
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 8,
                  child: LinearProgressIndicator(
                    key: ValueKey('$key-bar'),
                    value: fraction.clamp(0.0, 1.0),
                    backgroundColor: p.border,
                    color: color,
                  ),
                ),
              ),
            ],
          ]),
        );
    final header = Row(children: [
      Text('Recording', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.text)),
      if (status.simulated) ...[
        const SizedBox(width: 10),
        Pill('SIMULATED', key: const ValueKey('recording-simulated'), color: p.simulated),
      ],
    ]);
    final recording = r != null && !r.isOff;
    final List<Widget> body;
    if (!recording) {
      body = [
        Text(r == null ? "camera-manager hasn't reported recording." : 'Recording is off (RECORD_CAMERAS).',
            key: const ValueKey('recording-off'), style: TextStyle(fontSize: 15, color: p.textDim)),
      ];
    } else {
      final videoAndFree = r.recordedBytes + r.driveFreeBytes;
      body = [
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
        const SizedBox(height: 4),
        if (r.driveMounted)
          // The bar is video against the room left for it (video + free),
          // not the whole drive: other data shares it.
          meter('recording-drive', 'Drive: ${formatGb(r.driveFreeBytes)} free · video ${formatGb(r.recordedBytes)}',
              videoAndFree > 0 ? r.recordedBytes / videoAndFree : null, p.accent)
        else
          meter('recording-drive', 'No data drive: nothing records, never to the SD card.', null, p.advisory,
              textColor: p.advisory),
        meter(
            'recording-clips',
            'Saved clips: ${formatGb(r.protectedBytes)} of ${formatGb(r.protectedMaxBytes)}'
                '${r.clipSegmentsPending > 0 ? ' · ${r.clipSegmentsPending} to come' : ''}',
            r.protectedMaxBytes > 0 ? r.protectedBytes / r.protectedMaxBytes : null,
            r.protectedMaxBytes > 0 && r.protectedBytes >= 0.9 * r.protectedMaxBytes ? p.advisory : p.ok),
        if (!r.clockTrusted)
          line('recording-clock', Icons.schedule_rounded, p.textDim,
              'Clock not synchronized: no dates in names, no deleting by age.',
              maxLines: 2),
        if (r.problem.isNotEmpty) line('recording-problem', Icons.error_outline, p.advisory, r.problem, maxLines: 2),
      ];
    }
    return Panel(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        const SizedBox(height: 8),
        // Scrolls only if the lines outgrow the panel (an alert banner
        // above it); the buttons stay put.
        Expanded(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 68,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (recording) ...[
              const Expanded(child: SaveClipButton(keyPrefix: 'cameras-save-clip', compact: true)),
              const SizedBox(width: kGap),
            ],
            Expanded(child: _toUsb(context, wide: !recording)),
          ]),
        ),
        const SizedBox(height: 8),
        _safety(p),
      ]),
    );
  }
}
