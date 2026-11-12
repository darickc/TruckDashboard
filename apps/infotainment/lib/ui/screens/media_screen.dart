import 'package:flutter/material.dart';

import '../../audio/audio_state.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/badges.dart';
import '../widgets/panel.dart';
import '../widgets/tap_target.dart';

/// Bluetooth audio from a phone (ADR-0039): on the left what is playing and
/// the transport controls; on the right the phone and the pairing window
/// (Pair, its countdown, and the phone's code to confirm). Everything comes
/// from services/audio-manager; nothing is shown as current without it, and a
/// phone that has gone takes its track with it.
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
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _playing(r, audio)),
          const SizedBox(width: kGap),
          SizedBox(width: 290, child: _phonePanel(r, audio)),
        ]);
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

  Widget _playing(AudioReport r, AudioSource audio) {
    final p = Palette.of(context);
    final phone = r.phone;
    final np = r.nowPlaying;
    Widget header() => Row(children: [
          Icon(Icons.bluetooth_audio_rounded, size: 20, color: phone == null ? p.textDim : p.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(phone == null ? 'Bluetooth' : 'Bluetooth · ${phone.name}',
                key: const ValueKey('media-source'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.textDim)),
          ),
          if (r.streaming) ...[
            const SizedBox(width: 6),
            Pill('STREAMING', key: const ValueKey('media-streaming'), color: p.ok),
          ],
          if (r.simulated) ...[
            const SizedBox(width: 6),
            Pill('SIMULATED', key: const ValueKey('media-simulated'), color: p.simulated),
          ],
        ]);

    final String headline;
    final String explain;
    if (!r.bluetoothReady) {
      headline = 'Bluetooth unavailable';
      explain = r.bluetoothDetail.isEmpty ? 'No phone can connect.' : r.bluetoothDetail;
    } else if (phone == null) {
      headline = 'No phone connected';
      explain = r.known.isEmpty
          ? 'Tap Pair a phone, then pick ${r.pairing.name.isEmpty ? 'this head unit' : r.pairing.name} in the phone\'s Bluetooth settings.'
          : 'Turn Bluetooth on on a paired phone and it connects by itself, or pair another.';
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
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: p.text)),
                  const SizedBox(height: 6),
                  Text(explain,
                      key: const ValueKey('media-explain'),
                      style: TextStyle(
                          fontSize: 16, color: r.bluetoothReady ? p.textDim : p.advisory)),
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
              child: _button('media-previous', 'Previous', Icons.skip_previous_rounded,
                  controlsEnabled ? () => _run(() => audio.control(MediaCommand.previous)) : null)),
          const SizedBox(width: kGap),
          Expanded(
              child: _button(
                  'media-play-pause',
                  playing ? 'Pause' : 'Play',
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  controlsEnabled
                      ? () => _run(() => audio.control(playing ? MediaCommand.pause : MediaCommand.play))
                      : null,
                  emphasis: true)),
          const SizedBox(width: kGap),
          Expanded(
              child: _button('media-next', 'Next', Icons.skip_next_rounded,
                  controlsEnabled ? () => _run(() => audio.control(MediaCommand.next)) : null)),
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

  Widget _phonePanel(AudioReport r, AudioSource audio) {
    final p = Palette.of(context);
    final pairing = r.pairing;
    final q = pairing.question;
    if (q != null) return _question(q, audio);
    final phone = r.phone;
    final open = pairing.open;
    final note = TextStyle(fontSize: 14, color: p.textDim);
    final String windowText = switch (pairing.phase) {
      PairingPhase.open =>
        'Visible as "${pairing.name}" for ${formatTrackTime(Duration(seconds: pairing.secondsLeft))}. Pick it in the phone\'s Bluetooth settings.',
      PairingPhase.opening => 'Opening the pairing window…',
      PairingPhase.closing => 'Closing the pairing window…',
      PairingPhase.failed => pairing.detail,
      PairingPhase.closed => pairing.detail.isEmpty
          ? 'Not visible to new phones. Pairing opens only from here, and closes by itself.'
          : pairing.detail,
    };
    return Panel(
      title: 'Phone',
      child: ListView(children: [
        Text(phone?.name ?? (r.bluetoothReady ? 'None connected' : 'Bluetooth unavailable'),
            key: const ValueKey('media-phone'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: phone == null ? p.textDim : p.text)),
        for (final k in r.known)
          Text('${k.name}: paired, not connected',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: note),
        const SizedBox(height: 10),
        _button(
          'media-pair',
          open
              ? (pairing.phase == PairingPhase.open
                  ? 'Stop pairing · ${formatTrackTime(Duration(seconds: pairing.secondsLeft))}'
                  : 'Stop pairing')
              : 'Pair a phone',
          open ? Icons.bluetooth_disabled_rounded : Icons.bluetooth_searching_rounded,
          !r.bluetoothReady || _busy || pairing.phase == PairingPhase.closing
              ? null
              : open
                  ? () => _run(() async => CommandResult(ok: await audio.closePairing()))
                  : () => _run(() => audio.openPairing()),
          emphasis: open,
        ),
        const SizedBox(height: 6),
        Text(windowText,
            key: const ValueKey('media-pairing'),
            style: TextStyle(
                fontSize: 14, color: pairing.phase == PairingPhase.failed ? p.advisory : (open ? p.text : p.textDim))),
        const SizedBox(height: 10),
        Text(
            switch (r.dsp) {
              DspPhase.applied => 'Speakers: crossover, fader and sub applied.',
              DspPhase.starting => 'Speakers: starting the crossover…',
              DspPhase.notRunning =>
                'Speakers: crossover not running${r.dspDetail.isEmpty ? '' : ' (${r.dspDetail})'}.',
            },
            key: const ValueKey('media-dsp'),
            style: TextStyle(fontSize: 13, color: r.dsp == DspPhase.notRunning && !r.simulated ? p.advisory : p.textDim)),
      ]),
    );
  }

  Widget _question(PasskeyQuestion q, AudioSource audio) {
    final p = Palette.of(context);
    return Container(
      key: const ValueKey('media-question'),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.accent, width: 2),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${q.phoneName} wants to pair',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text)),
        const SizedBox(height: 6),
        if (q.passkey != null) ...[
          Text('Does the phone show this code?', style: TextStyle(fontSize: 15, color: p.textDim)),
          Text('${q.code.substring(0, 3)} ${q.code.substring(3)}',
              key: const ValueKey('media-passkey'),
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: 2, color: p.text)),
        ] else
          Text('It shows no code. Accept only if it is the phone in your hand.',
              style: TextStyle(fontSize: 15, color: p.advisory)),
        Text('Refused by itself in ${q.secondsLeft} s.', style: TextStyle(fontSize: 13, color: p.textDim)),
        const Spacer(),
        _button('media-confirm-yes', q.passkey != null ? 'Yes, it matches' : 'Accept', Icons.check_rounded,
            _busy ? null : () => _run(() => audio.confirm(q.id, true)),
            emphasis: true),
        const SizedBox(height: kGap),
        _button('media-confirm-no', 'No', Icons.close_rounded,
            _busy ? null : () => _run(() => audio.confirm(q.id, false))),
      ]),
    );
  }

  Widget _button(String key, String text, IconData icon, VoidCallback? onTap, {bool emphasis = false}) {
    final p = Palette.of(context);
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: TapTarget(
        key: ValueKey(key),
        label: onTap == null ? '$text (unavailable)' : text,
        selected: emphasis && onTap != null,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        onTap: onTap ?? () {},
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 28, color: p.text),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
          ),
        ]),
      ),
    );
  }
}
