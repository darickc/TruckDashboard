import 'package:flutter/material.dart';

import '../../audio/audio_state.dart';
import '../app_scope.dart';
import '../theme.dart';
import 'tap_target.dart';

/// Settings → Speakers (ADR-0039 decision 7): fader, balance and sub level
/// as sliders, the crossover in steps, through audio-manager, which
/// validates, saves and applies them to the filter-chain in front of the
/// DAC. Everything applies live, the crossover included (no restart:
/// ADR-0039 amendment); a slider sends while it is dragged, the newest value
/// winning, so the change is heard as the thumb moves. Defaults is at the
/// bottom. The limits and defaults are audio-manager's configuration:
/// examples, not recommendations (CLAUDE.md rule 10).
class SpeakerSettingsView extends StatefulWidget {
  const SpeakerSettingsView({super.key});

  @override
  State<SpeakerSettingsView> createState() => _SpeakerSettingsViewState();
}

class _SpeakerSettingsViewState extends State<SpeakerSettingsView> {
  SpeakerSnapshot? _snap;
  String? _error, _message;

  /// What a slider shows while its value is on its way (dragged, sent, not
  /// answered yet).
  SpeakerSettings? _shown;

  /// The newest value waiting to be sent, and whether a send is running.
  SpeakerSettings? _queued;
  bool _sending = false;
  AudioLink? _lastLink;
  late AudioSource _audio;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _audio = AppScope.of(context).audio;
    _audio.status.removeListener(_onStatus);
    _audio.status.addListener(_onStatus);
    if (_lastLink == null) {
      _lastLink = _audio.status.value.link;
      if (_lastLink == AudioLink.up) _read();
    }
  }

  @override
  void dispose() {
    _audio.status.removeListener(_onStatus);
    super.dispose();
  }

  void _onStatus() {
    final link = _audio.status.value.link;
    final was = _lastLink;
    _lastLink = link;
    if (link == AudioLink.up && was != AudioLink.up) _read();
  }

  Future<void> _read() async {
    setState(() => _error = null);
    try {
      final s = await _audio.getSpeakers();
      if (mounted) setState(() => _snap = s);
    } catch (e) {
      if (mounted) setState(() => _error = 'The speaker settings can\'t be read: $e');
    }
  }

  /// Sends [s], or queues it behind the send that is running: only the
  /// newest queued value goes next.
  Future<void> _send(SpeakerSettings s) async {
    _queued = s;
    if (_sending) return;
    _sending = true;
    try {
      while (_queued != null && mounted) {
        final next = _queued!;
        _queued = null;
        await _set(next);
      }
    } finally {
      _sending = false;
    }
  }

  Future<void> _set(SpeakerSettings s) async {
    final snap = _snap;
    if (snap == null) return;
    final why = snap.limits.check(s);
    if (why != null) {
      setState(() {
        _message = why;
        _shown = null;
      });
      return;
    }
    try {
      final r = await _audio.setSpeakers(s);
      if (!mounted) return;
      setState(() {
        _message = r.detail.isEmpty ? null : r.detail;
        if (r.ok) _snap = SpeakerSnapshot(settings: s, limits: snap.limits, defaults: snap.defaults);
        // Settled: show what audio-manager has, unless a newer value waits.
        if (_queued == null) _shown = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = 'Not applied: $e';
          if (_queued == null) _shown = null;
        });
      }
    }
  }

  void _change(SpeakerSettings s) {
    setState(() => _shown = s);
    _send(s);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ValueListenableBuilder<AudioStatus>(
      valueListenable: _audio.status,
      builder: (context, status, _) {
        if (status.link != AudioLink.up) {
          return Text(
              'audio-manager not connected${status.detail == null ? '' : ' (${status.detail})'}: '
              'the speaker settings can\'t be read or changed.',
              key: const ValueKey('spk-detail'),
              style: TextStyle(fontSize: 15, color: p.advisory));
        }
        final snap = _snap;
        if (snap == null) {
          return Text(_error ?? 'Reading the speaker settings…',
              key: const ValueKey('spk-detail'),
              style: TextStyle(fontSize: 15, color: _error == null ? p.textDim : p.advisory));
        }
        final s = _shown ?? snap.settings;
        final l = snap.limits;
        String side(int v, String neg, String pos) {
          if (v == 0) return 'Centre';
          final far = v.abs() >= l.steps;
          final db = (v.abs() * l.stepDb).toStringAsFixed(l.stepDb % 1 == 0 ? 0 : 1);
          return v > 0 ? '$pos ${v.abs()}${far ? ' ($neg off)' : ' ($neg −$db dB)'}' : '$neg ${v.abs()}${far ? ' ($pos off)' : ' ($pos −$db dB)'}';
        }

        final r = status.report;
        final dsp = switch (r?.dsp) {
          DspPhase.applied => 'Applied to the speakers.',
          DspPhase.starting => 'The crossover is starting…',
          _ => 'The crossover isn\'t running${r == null || r.dspDetail.isEmpty ? '' : ' (${r.dspDetail})'}.',
        };
        final note = 'Limits and defaults are examples from audio-manager\'s configuration: '
            'crossover ${l.crossoverMinHz}–${l.crossoverMaxHz} Hz, sub ${l.subMinDb}…+${l.subMaxDb} dB. '
            'Tune them in the truck. $dsp';

        final rows = <Widget>[
          _slider('fader', 'Fader', side(s.fader, 'Rear', 'Front'), 'Rear', 'Front', s.fader, -l.steps, l.steps,
              (v) => s.copyWith(fader: v)),
          _slider('balance', 'Balance', side(s.balance, 'Left', 'Right'), 'Left', 'Right', s.balance, -l.steps,
              l.steps, (v) => s.copyWith(balance: v)),
          _slider('sub', 'Sub level', '${s.subLevelDb > 0 ? '+' : ''}${s.subLevelDb} dB', '${l.subMinDb}',
              '+${l.subMaxDb}', s.subLevelDb, l.subMinDb, l.subMaxDb, (v) => s.copyWith(subLevelDb: v)),
          _crossover(s, l),
        ];
        final bottom = Row(children: [
          SizedBox(
            width: 200,
            child: _button('spk-reset', 'Defaults', s == snap.defaults ? null : () => _change(snap.defaults)),
          ),
          const SizedBox(width: 12),
          // What the last change did above the note, which always says the
          // limits are examples (CLAUDE.md rule 10).
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (_message != null)
                Text(_message!,
                    key: const ValueKey('spk-message'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
              Text(note,
                  key: const ValueKey('spk-note'),
                  maxLines: _message == null ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: p.textDim)),
            ]),
          ),
        ]);
        // Defaults at the bottom; when an alert banner takes height, the
        // whole view scrolls instead of squeezing the 60 px controls.
        return LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final (i, w) in rows.indexed) ...[if (i > 0) const SizedBox(height: 2), w],
                  const Spacer(),
                  const SizedBox(height: 6),
                  bottom,
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The name and the value, at the left of every row.
  Widget _label(String key, String name, String value) {
    final p = Palette.of(context);
    return SizedBox(
      width: 170,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
        Text(value,
            key: ValueKey('spk-$key'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: p.text)),
      ]),
    );
  }

  Widget _end(String text, TextAlign align) {
    final p = Palette.of(context);
    return SizedBox(
      width: 48,
      child: Text(text, textAlign: align, style: TextStyle(fontSize: 14, color: p.textDim)),
    );
  }

  Widget _slider(String key, String name, String value, String less, String more, int v, int min, int max,
      SpeakerSettings Function(int) at) {
    final p = Palette.of(context);
    return SizedBox(
      height: kMinTouch,
      child: Row(children: [
        _label(key, name, value),
        _end(less, TextAlign.right),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 8,
              // Fader, balance and sub run both ways from a middle: no
              // "filled" side.
              activeTrackColor: p.surfaceHigh,
              inactiveTrackColor: p.surfaceHigh,
              activeTickMarkColor: p.textDim,
              inactiveTickMarkColor: p.textDim,
              thumbColor: p.accent,
              overlayColor: p.accent.withValues(alpha: 0.18),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
              // 60 px across: the touch target.
              overlayShape: const RoundSliderOverlayShape(overlayRadius: kMinTouch / 2),
            ),
            child: Slider(
              key: ValueKey('spk-$key-slider'),
              value: v.clamp(min, max).toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              semanticFormatterCallback: (_) => value,
              onChanged: (d) {
                final n = d.round();
                if (n != v) _change(at(n));
              },
            ),
          ),
        ),
        _end(more, TextAlign.left),
      ]),
    );
  }

  Widget _crossover(SpeakerSettings s, SpeakerLimits l) {
    final step = l.crossoverStepHz;
    return SizedBox(
      height: kMinTouch,
      child: Row(children: [
        _label('crossover', 'Crossover', '${s.crossoverHz} Hz'),
        const SizedBox(width: 48),
        Expanded(
          child: _button(
              'spk-crossover-down',
              '− $step Hz',
              s.crossoverHz - step >= l.crossoverMinHz
                  ? () => _change(s.copyWith(crossoverHz: s.crossoverHz - step))
                  : null),
        ),
        const SizedBox(width: kGap),
        Expanded(
          child: _button(
              'spk-crossover-up',
              '+ $step Hz',
              s.crossoverHz + step <= l.crossoverMaxHz
                  ? () => _change(s.copyWith(crossoverHz: s.crossoverHz + step))
                  : null),
        ),
        const SizedBox(width: 48),
      ]),
    );
  }

  Widget _button(String key, String text, VoidCallback? onTap) {
    final p = Palette.of(context);
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: TapTarget(
        key: ValueKey(key),
        label: onTap == null ? '$text (unavailable)' : text,
        padding: EdgeInsets.zero,
        onTap: onTap ?? () {},
        child: Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
      ),
    );
  }
}
