import 'package:flutter/material.dart';

import '../../audio/audio_state.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/signal_builder.dart';
import '../widgets/tap_target.dart';
import 'media_screen.dart' show CoverArt;

/// The truck's speed beside the Nav screen's buttons, from the vehicle's
/// speed signal (SAE 01 0D), in the driver's units. Not a speedometer (the
/// cluster is): a glance while the map has the eyes. "—" when the signal
/// isn't current (CLAUDE.md rule 4); the age and reason are Gauges' and
/// Diagnostics' to show.
class NavSpeed extends StatelessWidget {
  const NavSpeed({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SignalBuilder(
      signalId: 'speed',
      builder: (context, v) {
        final current = v.isCurrent && v.primary != '—';
        return Semantics(
          label: current ? 'Speed ${v.primary} ${v.unit}' : 'Speed not current',
          excludeSemantics: true,
          child: Container(
            width: 86,
            height: kMinTouch,
            decoration: BoxDecoration(
              color: p.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.border),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  current ? v.primary : '—',
                  key: const ValueKey('nav-speed'),
                  style: TextStyle(
                    fontSize: 26,
                    height: 1.0,
                    fontWeight: FontWeight.w700,
                    fontFeatures: tabular,
                    color: current ? p.text : p.stale,
                  ),
                ),
                if (current) Text(v.unit, style: TextStyle(fontSize: 12, color: p.textDim)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One row of what the phone is playing over the bottom of the map (beside
/// the speed, at the end of the Nav screen's buttons): the
/// picture, the track (a tap opens Media), Play/Pause and Next. Only while
/// a connected phone has a player; nothing otherwise, so the map keeps the
/// room. Failures show on Media, not here.
class NavMediaStrip extends StatelessWidget {
  const NavMediaStrip({super.key});

  /// Narrower than this, the track has no room to be read: [NavGlance]
  /// leaves the strip out.
  static const minWidth = 300.0;
  static const maxWidth = 470.0;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    return ValueListenableBuilder<AudioStatus>(
      valueListenable: s.audio.status,
      builder: (context, status, _) {
        final r = status.report;
        final np = r?.nowPlaying;
        if (status.link != AudioLink.up || r?.phone == null || np == null) return const SizedBox.shrink();
        final playing = np.state == PlayState.playing;
        void send(MediaCommand c) =>
            s.audio.control(c).catchError((Object _) => const CommandResult(ok: false));
        Widget button(String key, String label, IconData icon, VoidCallback onTap, {bool emphasis = false}) =>
            SizedBox(
              width: 64,
              child: TapTarget(
                key: ValueKey(key),
                label: label,
                selected: emphasis,
                padding: EdgeInsets.zero,
                onTap: onTap,
                child: Icon(icon, size: 30, color: p.text),
              ),
            );
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: Container(
            key: const ValueKey('nav-player'),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: p.surface.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.border),
            ),
            child: SizedBox(
              height: kMinTouch,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: kMinTouch,
                    child: CoverArt(audio: s.audio, id: np.coverArtId, detail: np.coverArtDetail),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TapTarget(
                      key: const ValueKey('nav-player-open'),
                      label: 'Open Media: ${np.title}',
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      onTap: () => s.screens.open(AppScreen.media),
                      // Left-aligned beside the picture (TapTarget centres).
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            np.title.isEmpty ? 'Untitled' : np.title,
                            key: const ValueKey('nav-player-title'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text),
                          ),
                          if (np.artist.isNotEmpty)
                            Text(
                              np.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: p.textDim),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  button(
                    'nav-player-play-pause',
                    playing ? 'Pause' : 'Play',
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    () => send(playing ? MediaCommand.pause : MediaCommand.play),
                    emphasis: true,
                  ),
                  const SizedBox(width: 6),
                  button('nav-player-next', 'Next', Icons.skip_next_rounded, () => send(MediaCommand.next)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The speed, then the media strip, at the end of the Nav screen's bottom
/// row of buttons, in whatever width the buttons leave: both, the speed
/// alone, or nothing. They never push the buttons or overflow, and never
/// add a row (a taller column would cover the truck at the map's centre).
class NavGlance extends StatelessWidget {
  const NavGlance({super.key});

  static const _speedWidth = 86.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        if (w < kGap + _speedWidth) return const SizedBox.shrink(key: ValueKey('nav-glance-none'));
        final strip = w >= kGap + _speedWidth + kGap + NavMediaStrip.minWidth;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: kGap),
            const NavSpeed(),
            if (strip) ...[const SizedBox(width: kGap), const Flexible(child: NavMediaStrip())],
          ],
        );
      },
    );
  }
}
