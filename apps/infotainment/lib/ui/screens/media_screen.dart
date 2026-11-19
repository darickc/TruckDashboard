import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../audio/audio_state.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/badges.dart';
import '../widgets/panel.dart';
import '../widgets/audio_button.dart';
import '../widgets/tap_target.dart';
import '../widgets/volume.dart';

/// Bluetooth audio from a phone (ADR-0039), the full width: the track's
/// picture when the phone sends one (ADR-0042) with the source and the
/// track beside it, then the transport buttons and the volume (ADR-0043).
/// Phones (paired phones, connecting one, pairing a new one) is a screen of
/// its own, opened from the button at the top right: an icon, worded when
/// something needs the driver. Everything comes from services/audio-manager; nothing is
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

  /// Phones, at the top right: an icon, or a worded button when something
  /// needs the driver (a phone asking to pair, a connection being tried,
  /// pairing open).
  Widget _phonesButton(AudioReport r) {
    final screens = AppScope.of(context).screens;
    final String? label;
    if (r.pairing.question != null) {
      label = 'Phones · pairing request';
    } else if (r.connect.busy) {
      label = 'Phones · connecting…';
    } else if (r.pairing.open) {
      label = 'Phones · pairing open';
    } else {
      label = null;
    }
    void open() {
      AppScope.of(context).phoneTab.value = PhoneTab.phones;
      screens.open(AppScreen.phones);
    }

    if (label == null) {
      return SizedBox(
        width: kMinTouch,
        height: kMinTouch,
        child: TapTarget(
          key: const ValueKey('media-phones'),
          label: 'Phones',
          padding: EdgeInsets.zero,
          onTap: open,
          child: Icon(Icons.smartphone_rounded, size: 26, color: Palette.of(context).text),
        ),
      );
    }
    return SizedBox(
      width: 230,
      height: kMinTouch,
      child: AudioButton(
        key: const ValueKey('media-phones'),
        text: label,
        icon: Icons.smartphone_rounded,
        onTap: open,
        emphasis: r.pairing.question != null,
      ),
    );
  }

  Widget _playing(AudioReport r, AudioSource audio) {
    final p = Palette.of(context);
    final phone = r.phone;
    final np = r.nowPlaying;
    // The source's state as badges, on their own line under its name so
    // they never crowd it (or the Phones button) in the column beside the
    // picture; they wrap rather than overflow.
    final badges = <Widget>[
      if (r.pausedForPrompt || r.speaking)
        Pill(r.pausedForPrompt ? 'PAUSED FOR DIRECTIONS' : 'DIRECTIONS',
            key: const ValueKey('media-directions'), color: p.accent),
      if (r.streaming) Pill('STREAMING', key: const ValueKey('media-streaming'), color: p.ok),
      // Without the filter-chain the speakers get the plain stereo mix:
      // said, except in the simulation (which never has one).
      if (r.dsp == DspPhase.notRunning && !r.simulated)
        Pill('NO CROSSOVER', key: const ValueKey('media-dsp'), color: p.advisory),
      if (r.simulated) Pill('SIMULATED', key: const ValueKey('media-simulated'), color: p.simulated),
    ];
    Widget header() => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.bluetooth_audio_rounded, size: 22, color: phone == null ? p.textDim : p.accent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(phone == null ? 'Bluetooth' : 'Bluetooth · ${phone.name}',
                      key: const ValueKey('media-source'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.textDim)),
                ),
              ]),
              if (badges.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: badges),
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
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      header(),
      const SizedBox(height: 6),
      Expanded(
        child: np == null
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 4),
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
            : _trackText(np),
      ),
    ]);
    return Panel(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: np == null
              ? info
              // The picture at the left, as big as the room allows, the
              // source and the track beside it.
              : LayoutBuilder(builder: (context, box) {
                  final side = math.min(box.maxHeight, 240.0);
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: side,
                      height: side,
                      child: CoverArt(audio: audio, id: np.coverArtId, detail: np.coverArtDetail),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: info),
                  ]);
                }),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_message!,
                key: const ValueKey('media-message'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: p.advisory)),
          ),
        const SizedBox(height: 10),
        SizedBox(
          height: 72,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _TransportButton(
                keyName: 'media-previous',
                label: 'Previous',
                icon: Icons.skip_previous_rounded,
                width: 88,
                onTap: controlsEnabled ? () => _run(() => audio.control(MediaCommand.previous)) : null),
            const SizedBox(width: kGap),
            _TransportButton(
                keyName: 'media-play-pause',
                label: playing ? 'Pause' : 'Play',
                icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                width: 120,
                emphasis: true,
                onTap: controlsEnabled
                    ? () => _run(() => audio.control(playing ? MediaCommand.pause : MediaCommand.play))
                    : null),
            const SizedBox(width: kGap),
            _TransportButton(
                keyName: 'media-next',
                label: 'Next',
                icon: Icons.skip_next_rounded,
                width: 88,
                onTap: controlsEnabled ? () => _run(() => audio.control(MediaCommand.next)) : null),
            const Spacer(),
            // With or without a phone: the volume is the speakers'.
            Center(
              child: VolumeControls(
                audio: audio,
                volume: r.volume,
                onNote: (note) {
                  if (mounted) setState(() => _message = note);
                },
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _trackText(NowPlaying np) {
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
      // The track in the middle of the room left, not pushed to the top.
      Expanded(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(np.title.isEmpty ? 'Untitled (the phone sent no title)' : np.title,
                  key: const ValueKey('media-title'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 30, height: 1.15, fontWeight: FontWeight.w800, color: p.text)),
              const SizedBox(height: 4),
              Text(np.artist,
                  key: const ValueKey('media-artist'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 20, color: p.text)),
              Text(np.album,
                  key: const ValueKey('media-album'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, color: p.textDim)),
            ]),
      ),
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
            style: TextStyle(fontSize: 14, fontFeatures: tabular, color: p.textDim)),
      ]),
    ]);
  }
}

/// A transport button: a large icon, its word as the semantic label (the
/// icons are the usual ones). Dim and inert without a player.
class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.keyName,
    required this.label,
    required this.icon,
    required this.width,
    required this.onTap,
    this.emphasis = false,
  });

  final String keyName;
  final String label;
  final IconData icon;
  final double width;
  final VoidCallback? onTap;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SizedBox(
      width: width,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: TapTarget(
          key: ValueKey(keyName),
          label: onTap == null ? '$label (unavailable)' : label,
          selected: emphasis && onTap != null,
          padding: EdgeInsets.zero,
          onTap: onTap ?? () {},
          child: Icon(icon, size: emphasis ? 40 : 34, color: p.text),
        ),
      ),
    );
  }
}

/// The track's picture (ADR-0042), fetched from audio-manager by its id.
/// A new id clears the old picture at once: another track's picture is never
/// shown, not even while the new one loads. No id (or a failed fetch): a
/// note symbol, with why when audio-manager says.
class CoverArt extends StatefulWidget {
  const CoverArt({super.key, required this.audio, required this.id, this.detail = ''});

  final AudioSource audio;
  final String id;
  final String detail;

  @override
  State<CoverArt> createState() => _CoverArtState();
}

class _CoverArtState extends State<CoverArt> {
  CoverArtImage? _image;
  String _imageId = '';
  String _failed = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CoverArt old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id || !identical(old.audio, widget.audio)) _load();
  }

  Future<void> _load() async {
    final id = widget.id;
    setState(() {
      _image = null;
      _imageId = '';
      _failed = '';
    });
    if (id.isEmpty) return;
    try {
      final image = await widget.audio.coverArt(id);
      if (!mounted || widget.id != id) return;
      setState(() {
        _image = image;
        _imageId = id;
      });
    } catch (e) {
      if (!mounted || widget.id != id) return;
      setState(() => _failed = 'The picture didn\'t arrive: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final image = _imageId == widget.id ? _image : null;
    if (image != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          image.bytes,
          key: ValueKey('media-cover-art-${widget.id}'),
          fit: BoxFit.cover,
          gaplessPlayback: false,
          semanticLabel: 'Cover art',
          errorBuilder: (context, _, _) => _none(p, 'The phone\'s picture couldn\'t be shown.'),
        ),
      );
    }
    final loading = widget.id.isNotEmpty && _failed.isEmpty;
    return _none(p, loading ? '' : (_failed.isNotEmpty ? _failed : widget.detail));
  }

  Widget _none(Palette p, String why) {
    return DecoratedBox(
      key: const ValueKey('media-cover-none'),
      decoration: BoxDecoration(
        color: p.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final small = c.maxHeight < 140;
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.music_note_rounded, size: c.maxHeight * (why.isEmpty || small ? 0.45 : 0.32), color: p.textDim),
            if (why.isNotEmpty && !small) ...[
              const SizedBox(height: 6),
              Text(why,
                  key: const ValueKey('media-cover-why'),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: p.textDim)),
            ],
          ]),
        );
      }),
    );
  }
}
