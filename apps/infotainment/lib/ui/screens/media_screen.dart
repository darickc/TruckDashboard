import 'package:flutter/material.dart';

import '../../audio/audio_state.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/badges.dart';
import '../widgets/panel.dart';
import '../widgets/audio_button.dart';

/// Bluetooth audio from a phone (ADR-0039), the full width: what is
/// playing and the transport controls. Phones (paired phones, connecting
/// one, pairing a new one) is a screen of its own, opened from the button at
/// the top right. Everything comes from services/audio-manager; nothing is
/// shown as current without it, and a phone that has gone takes its track
/// with it.
class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key});

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  /// What the last tap did, when it didn't work.
  String? _message;
  bool _busy = false;

  Future<void> _run(Future<CommandResult> Function() f) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final r = await f();
      if (mounted) setState(() => _message = r.ok ? null : r.detail);
    } catch (e) {
      if (mounted) setState(() => _message = 'audio-manager didn\'t answer: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final audio = AppScope.of(context).audio;
    return ValueListenableBuilder<AudioStatus>(
      valueListenable: audio.status,
      builder: (context, status, _) {
        final r = status.report;
        if (r == null) return _noService(status);
        return _playing(r, audio);
      },
    );
  }

  Widget _noService(AudioStatus s) {
    final p = Palette.of(context);
    final connecting = s.link == AudioLink.connecting;
    return Panel(
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bluetooth_disabled_rounded, size: 56, color: p.textDim),
          const SizedBox(height: 10),
          Text(connecting ? 'Connecting to audio-manager…' : 'audio-manager not connected',
              key: const ValueKey('media-link'),
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: p.text)),
          const SizedBox(height: 8),
          Text(
              '${s.detail == null ? '' : '${s.detail}. '}No phone, track or pairing window is shown until it answers.',
              key: const ValueKey('media-link-detail'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: connecting ? p.textDim : p.advisory)),
        ]),
      ),
    );
  }

  /// Phones, at the top right: the connected phone's name, or what needs
  /// the driver (a phone asking to pair, a connection being tried).
  Widget _phonesButton(AudioReport r) {
    final screens = AppScope.of(context).screens;
    final String label;
    if (r.pairing.question != null) {
      label = 'Phones · pairing request';
    } else if (r.connect.busy) {
      label = 'Phones · connecting…';
    } else if (r.pairing.open) {
      label = 'Phones · pairing open';
    } else {
      label = 'Phones';
    }
    return SizedBox(
      width: 250,
      child: AudioButton(
        key: const ValueKey('media-phones'),
        text: label,
        icon: Icons.smartphone_rounded,
        onTap: () => screens.open(AppScreen.phones),
        emphasis: r.pairing.question != null,
      ),
    );
  }

  Widget _playing(AudioReport r, AudioSource audio) {
    final p = Palette.of(context);
    final phone = r.phone;
    final np = r.nowPlaying;
    // The source and its badges at the left, taking the room they need
    // (the name ellipsized only when it must be), Phones at the right.
    Widget header() => Row(children: [
          Icon(Icons.bluetooth_audio_rounded, size: 22, color: phone == null ? p.textDim : p.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Row(children: [
              Flexible(
                child: Text(phone == null ? 'Bluetooth' : 'Bluetooth · ${phone.name}',
                    key: const ValueKey('media-source'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.textDim)),
              ),
              if (r.pausedForPrompt || r.speaking) ...[
                const SizedBox(width: 6),
                Pill(r.pausedForPrompt ? 'PAUSED FOR DIRECTIONS' : 'DIRECTIONS',
                    key: const ValueKey('media-directions'), color: p.accent),
              ],
              if (r.streaming) ...[
                const SizedBox(width: 6),
                Pill('STREAMING', key: const ValueKey('media-streaming'), color: p.ok),
              ],
              // Without the filter-chain the speakers get the plain stereo
              // mix: said, except in the simulation (which never has one).
              if (r.dsp == DspPhase.notRunning && !r.simulated) ...[
                const SizedBox(width: 6),
                Pill('NO CROSSOVER', key: const ValueKey('media-dsp'), color: p.advisory),
              ],
              if (r.simulated) ...[
                const SizedBox(width: 6),
                Pill('SIMULATED', key: const ValueKey('media-simulated'), color: p.simulated),
              ],
            ]),
          ),
          const SizedBox(width: kGap),
          _phonesButton(r),
        ]);

    final String headline;
    final String explain;
    final c = r.connect;
    if (!r.bluetoothReady) {
      headline = 'Bluetooth unavailable';
      explain = r.bluetoothDetail.isEmpty ? 'No phone can connect.' : r.bluetoothDetail;
    } else if (phone == null && c.busy) {
      headline = 'Connecting to ${c.name}…';
      explain = c.automatic
          ? 'It was the last phone connected; trying it again by itself. Phones lists the others.'
          : 'Make sure Bluetooth is on on the phone.';
    } else if (phone == null) {
      headline = 'No phone connected';
      explain = c.detail.isNotEmpty
          ? c.detail
          : r.known.isEmpty
              ? 'Tap Phones to pair a phone.'
              : 'Tap Phones to connect a paired phone or pair another.';
    } else if (np == null) {
      headline = 'Connected to ${phone.name}';
      explain = 'The phone hasn\'t sent track information or offered controls (no AVRCP player).';
    } else {
      headline = '';
      explain = '';
    }

    final controlsEnabled = np != null && !_busy;
    final playing = np?.state == PlayState.playing;
    return Panel(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        header(),
        const SizedBox(height: 10),
        Expanded(
          child: np == null
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(headline,
                      key: const ValueKey('media-headline'),
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: p.text)),
                  const SizedBox(height: 6),
                  Text(explain,
                      key: const ValueKey('media-explain'),
                      style: TextStyle(
                          fontSize: 17,
                          color: !r.bluetoothReady || (phone == null && c.detail.isNotEmpty && !c.busy)
                              ? p.advisory
                              : p.textDim)),
                ])
              : _track(np),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(_message!,
                key: const ValueKey('media-message'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: p.advisory)),
          ),
        Row(children: [
          Expanded(
              child: AudioButton(
                  key: const ValueKey('media-previous'),
                  text: 'Previous',
                  icon: Icons.skip_previous_rounded,
                  onTap: controlsEnabled ? () => _run(() => audio.control(MediaCommand.previous)) : null)),
          const SizedBox(width: kGap),
          Expanded(
              child: AudioButton(
                  key: const ValueKey('media-play-pause'),
                  text: playing ? 'Pause' : 'Play',
                  icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  onTap: controlsEnabled
                      ? () => _run(() => audio.control(playing ? MediaCommand.pause : MediaCommand.play))
                      : null,
                  emphasis: true)),
          const SizedBox(width: kGap),
          Expanded(
              child: AudioButton(
                  key: const ValueKey('media-next'),
                  text: 'Next',
                  icon: Icons.skip_next_rounded,
                  onTap: controlsEnabled ? () => _run(() => audio.control(MediaCommand.next)) : null)),
        ]),
      ]),
    );
  }

  Widget _track(NowPlaying np) {
    final p = Palette.of(context);
    final d = np.duration;
    final pos = np.position;
    final fraction = (d == null || pos == null || d.inMilliseconds == 0)
        ? null
        : (pos.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
    final state = switch (np.state) {
      PlayState.playing => 'Playing',
      PlayState.paused => 'Paused',
      PlayState.stopped => 'Stopped',
      PlayState.forwardSeek => 'Fast forward',
      PlayState.reverseSeek => 'Rewind',
      PlayState.error => 'The phone reports an error',
      PlayState.unknown => 'State unknown',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(np.title.isEmpty ? 'Untitled (the phone sent no title)' : np.title,
          key: const ValueKey('media-title'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: p.text)),
      const SizedBox(height: 4),
      Text(np.artist,
          key: const ValueKey('media-artist'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 19, color: p.text)),
      Text(np.album,
          key: const ValueKey('media-album'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 15, color: p.textDim)),
      const Spacer(),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          key: const ValueKey('media-progress'),
          value: fraction ?? 0,
          minHeight: 8,
          backgroundColor: p.surfaceHigh,
          color: fraction == null ? p.textDim : p.accent,
        ),
      ),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(
          child: Text(state,
              key: const ValueKey('media-state'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14, color: np.state == PlayState.error ? p.advisory : p.textDim)),
        ),
        const SizedBox(width: 8),
        Text(
            pos == null
                ? 'time unknown'
                : d == null
                    ? formatTrackTime(pos)
                    : '${formatTrackTime(pos)} / ${formatTrackTime(d)}',
            key: const ValueKey('media-time'),
            style: TextStyle(fontSize: 14, color: p.textDim)),
      ]),
      const SizedBox(height: 8),
    ]);
  }
}
