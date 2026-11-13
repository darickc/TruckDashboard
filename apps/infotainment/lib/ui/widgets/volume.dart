import 'dart:async';

import 'package:flutter/material.dart';

import '../../audio/audio_state.dart';
import '../theme.dart';
import 'tap_target.dart';

/// Volume −, the level, Volume + and Mute, on the Media screen (ADR-0043).
/// Each tap goes to audio-manager; the level shown is what it reports.
class VolumeControls extends StatelessWidget {
  const VolumeControls({super.key, required this.audio, required this.volume, this.onNote});

  final AudioSource audio;

  /// Null: audio-manager has no volume (an older one); the buttons are off.
  final VolumeStatus? volume;

  /// What wasn't as asked (above the cap), or why the call failed.
  final void Function(String note)? onNote;

  Future<void> _set(VolumeChange c) async {
    try {
      final r = await audio.setVolume(c);
      if (r.detail.isNotEmpty) onNote?.call(r.detail);
    } catch (e) {
      onNote?.call('audio-manager didn\'t answer: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final v = volume;
    final on = v != null;
    Widget button(String k, String label, IconData icon, VolumeChange c, {bool selected = false}) => Opacity(
      opacity: on ? 1 : 0.45,
      child: TapTarget(
        key: ValueKey(k),
        label: on ? label : '$label (unavailable)',
        selected: selected,
        padding: EdgeInsets.zero,
        onTap: on ? () => _set(c) : () {},
        child: Icon(icon, size: 30, color: p.text),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button('media-volume-down', 'Volume down', Icons.volume_down_rounded, const VolumeChange.steps(-1)),
        SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                v == null ? '—' : (v.muted ? 'Muted' : '${v.level}'),
                key: const ValueKey('media-volume-level'),
                maxLines: 1,
                style: TextStyle(
                  fontSize: v != null && v.muted ? 17 : 24,
                  fontWeight: FontWeight.w800,
                  color: v != null && v.muted ? p.advisory : p.text,
                ),
              ),
              Text(
                v == null ? 'volume' : (v.level >= v.max && v.max < v.steps ? 'max' : 'volume'),
                style: TextStyle(fontSize: 12, color: p.textDim),
              ),
            ],
          ),
        ),
        button('media-volume-up', 'Volume up', Icons.volume_up_rounded, const VolumeChange.steps(1)),
        const SizedBox(width: kGap),
        button(
          'media-volume-mute',
          v != null && v.muted ? 'Unmute' : 'Mute',
          Icons.volume_off_rounded,
          const VolumeChange.toggleMute(),
          selected: v != null && v.muted,
        ),
      ],
    );
  }
}

/// The level for 2 s after any change (the knob), over the bottom of the
/// screen area on every screen but Media, which shows the level beside its
/// buttons (the overlay would cover them). The alert banner is above the
/// screen area, so this never covers it; it takes no taps.
class VolumeOverlay extends StatefulWidget {
  const VolumeOverlay({
    super.key,
    required this.audio,
    this.hidden = false,
    this.showFor = const Duration(seconds: 2),
  });

  final AudioSource audio;

  /// Not shown (the Media screen); changes are still followed.
  final bool hidden;
  final Duration showFor;

  @override
  State<VolumeOverlay> createState() => _VolumeOverlayState();
}

class _VolumeOverlayState extends State<VolumeOverlay> {
  VolumeStatus? _last;
  bool _showing = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _last = widget.audio.status.value.report?.volume;
    widget.audio.status.addListener(_changed);
  }

  @override
  void didUpdateWidget(VolumeOverlay old) {
    super.didUpdateWidget(old);
    if (old.audio != widget.audio) {
      old.audio.status.removeListener(_changed);
      widget.audio.status.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.audio.status.removeListener(_changed);
    _hide?.cancel();
    super.dispose();
  }

  void _changed() {
    final v = widget.audio.status.value.report?.volume;
    final was = _last;
    _last = v ?? was;
    // Only a change of level or mute shows it: not the first report, not a
    // link coming back, not the once-a-second update.
    if (v == null || was == null || (v.level == was.level && v.muted == was.muted)) {
      if (_showing) setState(() {});
      return;
    }
    _hide?.cancel();
    _hide = Timer(widget.showFor, () {
      if (mounted) setState(() => _showing = false);
    });
    setState(() => _showing = true);
  }

  @override
  Widget build(BuildContext context) {
    final v = _last;
    if (!_showing || v == null || widget.hidden) return const SizedBox.shrink();
    final p = Palette.of(context);
    final fraction = v.steps == 0 ? 0.0 : (v.level / v.steps).clamp(0.0, 1.0);
    final cap = v.steps == 0 ? 1.0 : (v.max / v.steps).clamp(0.0, 1.0);
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          key: const ValueKey('volume-overlay'),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: p.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                v.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                size: 28,
                color: v.muted ? p.advisory : p.text,
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 280,
                height: 14,
                child: LayoutBuilder(
                  builder: (context, c) {
                    return Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(color: p.background, borderRadius: BorderRadius.circular(7)),
                        ),
                        FractionallySizedBox(
                          widthFactor: fraction,
                          child: Container(
                            decoration: BoxDecoration(
                              color: v.muted ? p.textDim : p.accent,
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                        ),
                        // The cap (configuration), when below the top step.
                        if (cap < 1)
                          Positioned(
                            key: const ValueKey('volume-overlay-cap'),
                            left: c.maxWidth * cap - 1,
                            top: 0,
                            bottom: 0,
                            child: Container(width: 2, color: p.advisory),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 70,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.muted ? 'Muted' : '${v.level}',
                      key: const ValueKey('volume-overlay-level'),
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: v.muted ? p.advisory : p.text),
                    ),
                    if (!v.applied)
                      Text(
                        'not applied',
                        key: const ValueKey('volume-overlay-not-applied'),
                        style: TextStyle(fontSize: 12, color: p.advisory),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
