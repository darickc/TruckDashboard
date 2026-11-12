import 'package:flutter/material.dart';

import '../../audio/audio_state.dart';
import '../app_scope.dart';
import '../theme.dart';
import 'tap_target.dart';

/// Settings → Speakers (ADR-0039 decision 7): fader, balance, sub level and
/// the crossover, through audio-manager, which validates, saves and applies
/// them to the filter-chain in front of the DAC. Each tap is applied at once;
/// a crossover change restarts the filter-chain (a moment of silence). The
/// limits and defaults are audio-manager's configuration: examples, not
/// recommendations (CLAUDE.md rule 10).
class SpeakerSettingsView extends StatefulWidget {
  const SpeakerSettingsView({super.key});

  @override
  State<SpeakerSettingsView> createState() => _SpeakerSettingsViewState();
}

class _SpeakerSettingsViewState extends State<SpeakerSettingsView> {
  SpeakerSnapshot? _snap;
  String? _error, _message;
  bool _busy = false;
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

  Future<void> _set(SpeakerSettings s) async {
    final snap = _snap;
    if (snap == null) return;
    final why = snap.limits.check(s);
    if (why != null) {
      setState(() => _message = why);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final r = await _audio.setSpeakers(s);
      if (!mounted) return;
      setState(() {
        _message = r.detail.isEmpty ? null : r.detail;
        if (r.ok) _snap = SpeakerSnapshot(settings: s, limits: snap.limits, defaults: snap.defaults);
      });
    } catch (e) {
      if (mounted) setState(() => _message = 'Not applied: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        final s = snap.settings;
        final l = snap.limits;
        String side(int v, String neg, String pos) {
          if (v == 0) return 'Centre';
          final far = v.abs() >= l.steps;
          final db = (v.abs() * l.stepDb).toStringAsFixed(l.stepDb % 1 == 0 ? 0 : 1);
          return v > 0 ? '$pos ${v.abs()}${far ? ' ($neg off)' : ' ($neg −$db dB)'}' : '$neg ${v.abs()}${far ? ' ($pos off)' : ' ($pos −$db dB)'}';
        }

        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: ListView(children: [
              _row('fader', 'Fader', side(s.fader, 'Rear', 'Front'), 'Rear', 'Front',
                  s.fader > -l.steps ? () => _set(s.copyWith(fader: s.fader - 1)) : null,
                  s.fader < l.steps ? () => _set(s.copyWith(fader: s.fader + 1)) : null),
              const SizedBox(height: 6),
              _row('balance', 'Balance', side(s.balance, 'Left', 'Right'), 'Left', 'Right',
                  s.balance > -l.steps ? () => _set(s.copyWith(balance: s.balance - 1)) : null,
                  s.balance < l.steps ? () => _set(s.copyWith(balance: s.balance + 1)) : null),
              const SizedBox(height: 6),
              _row('sub', 'Sub level', '${s.subLevelDb > 0 ? '+' : ''}${s.subLevelDb} dB', '−', '+',
                  s.subLevelDb > l.subMinDb ? () => _set(s.copyWith(subLevelDb: s.subLevelDb - 1)) : null,
                  s.subLevelDb < l.subMaxDb ? () => _set(s.copyWith(subLevelDb: s.subLevelDb + 1)) : null),
              const SizedBox(height: 6),
              _row('crossover', 'Crossover', '${s.crossoverHz} Hz', '−', '+',
                  s.crossoverHz - l.crossoverStepHz >= l.crossoverMinHz
                      ? () => _set(s.copyWith(crossoverHz: s.crossoverHz - l.crossoverStepHz))
                      : null,
                  s.crossoverHz + l.crossoverStepHz <= l.crossoverMaxHz
                      ? () => _set(s.copyWith(crossoverHz: s.crossoverHz + l.crossoverStepHz))
                      : null),
            ]),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: ListView(children: [
              _small('spk-reset', 'Defaults', s == snap.defaults || _busy ? null : () => _set(snap.defaults)),
              if (_message != null) ...[
                const SizedBox(height: 6),
                Text(_message!, key: const ValueKey('spk-message'), style: TextStyle(fontSize: 14, color: p.text)),
              ],
              const SizedBox(height: 8),
              Text(
                  'Limits and defaults are examples from audio-manager\'s configuration: '
                  'crossover ${l.crossoverMinHz}–${l.crossoverMaxHz} Hz, sub ${l.subMinDb}…+${l.subMaxDb} dB. '
                  'Tune them in the truck. Changing the crossover restarts the speakers: a moment of silence.',
                  key: const ValueKey('spk-note'),
                  style: TextStyle(fontSize: 13, color: p.textDim)),
            ]),
          ),
        ]);
      },
    );
  }

  Widget _row(String key, String name, String value, String less, String more, VoidCallback? down,
      VoidCallback? up) {
    final p = Palette.of(context);
    return Row(children: [
      SizedBox(
          width: 100,
          child: Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text))),
      _small('spk-$key-down', less, _busy ? null : down, width: 80),
      const SizedBox(width: kGap),
      Expanded(
        child: Text(value,
            key: ValueKey('spk-$key'),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 16, color: p.text)),
      ),
      const SizedBox(width: kGap),
      _small('spk-$key-up', more, _busy ? null : up, width: 80),
    ]);
  }

  Widget _small(String key, String text, VoidCallback? onTap, {double width = 220}) {
    final p = Palette.of(context);
    return SizedBox(
      width: width,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: TapTarget(
          key: ValueKey(key),
          label: onTap == null ? '$text (unavailable)' : text,
          padding: EdgeInsets.zero,
          onTap: onTap ?? () {},
          child: Text(text, style: TextStyle(fontSize: 16, color: p.text)),
        ),
      ),
    );
  }
}
