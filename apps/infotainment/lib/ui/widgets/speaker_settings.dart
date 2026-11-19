import 'package:flutter/material.dart';

import '../../audio/audio_state.dart';
import '../app_scope.dart';
import '../theme.dart';
import 'display_settings.dart';
import 'tap_target.dart';

/// Settings → Speakers (ADR-0039 decision 7): fader, balance and sub level
/// as sliders, the crossover in steps, through audio-manager, which
/// validates, saves and applies them to the filter-chain in front of the
/// DAC. Everything applies live, the crossover included (no restart:
/// ADR-0039 amendment); a slider sends while it is dragged, the newest value
/// winning, so the change is heard as the thumb moves. Each row is laid out
/// like Display's (name and value on the left) with − and + at its ends for
/// one step a tap; the crossover is a stepped bar like Brightness, and a cab
/// beside the rows shows where the sound is centred (design review,
/// 2026-11-19). Whether the settings reach the speakers, the note and
/// Defaults are at the bottom. The limits and defaults are audio-manager's
/// configuration: examples, not recommendations (CLAUDE.md rule 10).
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
        final (dsp, dspColor) = switch (r?.dsp) {
          DspPhase.applied => ('Applied to the speakers', p.ok),
          DspPhase.starting => ('Crossover starting…', p.textDim),
          _ => ('Crossover not running${r == null || r.dspDetail.isEmpty ? '' : ' (${r.dspDetail})'}', p.advisory),
        };
        const note = 'Limits and defaults are examples from audio-manager\'s configuration.';

        final rows = <Widget>[
          _sliderRow(
            'fader',
            'Fader',
            side(s.fader, 'Rear', 'Front'),
            'Rear',
            'Front',
            s.fader,
            -l.steps,
            l.steps,
            (c) => c.fader,
            (c, v) => c.copyWith(fader: v),
          ),
          _sliderRow(
            'balance',
            'Balance',
            side(s.balance, 'Left', 'Right'),
            'Left',
            'Right',
            s.balance,
            -l.steps,
            l.steps,
            (c) => c.balance,
            (c, v) => c.copyWith(balance: v),
          ),
          _sliderRow(
            'sub',
            'Sub level',
            '${s.subLevelDb > 0 ? '+' : ''}${s.subLevelDb} dB',
            '${l.subMinDb} dB',
            '+${l.subMaxDb} dB',
            s.subLevelDb,
            l.subMinDb,
            l.subMaxDb,
            (c) => c.subLevelDb,
            (c, v) => c.copyWith(subLevelDb: v),
          ),
          _crossover(s, l),
        ];
        final bottom = SizedBox(
          height: kMinTouch,
          child: Row(
            children: [
              // Whether the settings reach the speakers, always shown.
              SizedBox(
                width: 230,
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: dspColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        dsp,
                        key: const ValueKey('spk-dsp'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: dspColor),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // What the last change did above the note, which always says the
              // limits are examples (CLAUDE.md rule 10).
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_message != null)
                      Text(
                        _message!,
                        key: const ValueKey('spk-message'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.text),
                      ),
                    Text(
                      note,
                      key: const ValueKey('spk-note'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.textDim),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 150,
                child: _button('spk-reset', 'Defaults', s == snap.defaults ? null : () => _change(snap.defaults)),
              ),
            ],
          ),
        );
        // The rows with the cab beside them, the status and Defaults at the
        // bottom; when an alert banner takes height, the whole view scrolls
        // instead of squeezing the 60 px controls.
        return LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The cab as tall as the rows.
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  for (final (i, w) in rows.indexed) ...[if (i > 0) const SizedBox(height: 2), w],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            SpeakerCab(fader: s.fader, balance: s.balance, steps: l.steps),
                          ],
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(height: 4),
                      Divider(height: 1, color: p.border),
                      const SizedBox(height: 4),
                      bottom,
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// One setting: its name and value on the left (as on Display), − and +
  /// (one step each) around [middle], with [less] and [more] under its ends.
  Widget _row(
    String key,
    String name,
    String value,
    String less,
    String more,
    Widget middle, {
    required VoidCallback? down,
    required VoidCallback? up,
    required String downLabel,
    required String upLabel,
  }) {
    final p = Palette.of(context);
    final ends = TextStyle(fontSize: 11, color: p.textDim);
    return SizedBox(
      height: kMinTouch,
      child: Row(
        children: [
          // Display's row label (SettingRow), its value kept to one line to
          // fit the 60 px row.
          SizedBox(
            width: kSettingLabelWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text),
                ),
                Text(
                  value,
                  key: ValueKey('spk-$key'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.textDim),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                SizedBox(width: kMinTouch, child: _step('spk-$key-down', Icons.remove, downLabel, down)),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: middle),
                      Positioned(
                        left: kEndInset,
                        bottom: 0,
                        child: Text(less, style: ends),
                      ),
                      Positioned(
                        right: kEndInset,
                        bottom: 0,
                        child: Text(more, style: ends),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: kMinTouch, child: _step('spk-$key-up', Icons.add, upLabel, up)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Where a slider's track starts inside it, and so where the bars and the
  /// end labels start, to line up with the sliders.
  static const kEndInset = 24.0;

  Widget _sliderRow(
    String key,
    String name,
    String value,
    String less,
    String more,
    int v,
    int min,
    int max,
    int Function(SpeakerSettings) read,
    SpeakerSettings Function(SpeakerSettings, int) write,
  ) {
    final p = Palette.of(context);
    return _row(
      key,
      name,
      value,
      less,
      more,
      SliderTheme(
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
          padding: const EdgeInsets.symmetric(horizontal: kEndInset),
          value: v.clamp(min, max).toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          semanticFormatterCallback: (_) => value,
          onChanged: (d) {
            final n = d.round();
            final c = _current;
            if (c != null && n != read(c)) _change(write(c, n));
          },
        ),
      ),
      down: v > min ? () => _nudge(read, write, -1, min, max) : null,
      up: v < max ? () => _nudge(read, write, 1, min, max) : null,
      downLabel: '$name toward $less',
      upLabel: '$name toward $more',
    );
  }

  Widget _crossover(SpeakerSettings s, SpeakerLimits l) {
    final step = l.crossoverStepHz;
    final n = (l.crossoverMaxHz - l.crossoverMinHz) ~/ step + 1;
    final filled = ((s.crossoverHz - l.crossoverMinHz) ~/ step + 1).clamp(1, n);
    return _row(
      'crossover',
      'Crossover',
      '${s.crossoverHz} Hz',
      '${l.crossoverMinHz} Hz',
      '${l.crossoverMaxHz} Hz',
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: kEndInset),
        child: Center(
          child: StepBar(pct: (filled * 100 / n).round(), steps: n),
        ),
      ),
      down: s.crossoverHz - step >= l.crossoverMinHz
          ? () => _nudge((c) => c.crossoverHz, (c, v) => c.copyWith(crossoverHz: v), -step, l.crossoverMinHz,
              l.crossoverMaxHz)
          : null,
      up: s.crossoverHz + step <= l.crossoverMaxHz
          ? () => _nudge((c) => c.crossoverHz, (c, v) => c.copyWith(crossoverHz: v), step, l.crossoverMinHz,
              l.crossoverMaxHz)
          : null,
      downLabel: 'Crossover down $step Hz',
      upLabel: 'Crossover up $step Hz',
    );
  }

  /// What the rows show now: the newest value sent or waiting, else
  /// audio-manager's. A step reads it when tapped, not when the row was
  /// built, so taps quicker than the screen redraws each count.
  SpeakerSettings? get _current => _shown ?? _snap?.settings;

  /// One step of [delta] from the current value, kept inside [min]..[max].
  void _nudge(int Function(SpeakerSettings) read, SpeakerSettings Function(SpeakerSettings, int) write, int delta,
      int min, int max) {
    final c = _current;
    if (c == null) return;
    final n = read(c) + delta;
    if (n < min || n > max) return;
    _change(write(c, n));
  }

  /// − or +: one step, dimmed at the end of the range.
  Widget _step(String key, IconData icon, String label, VoidCallback? onTap) {
    final p = Palette.of(context);
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: TapTarget(
        key: ValueKey(key),
        label: onTap == null ? '$label (unavailable)' : label,
        padding: EdgeInsets.zero,
        onTap: onTap ?? () {},
        child: Icon(icon, size: 28, color: p.text),
      ),
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

/// Where the sound is centred, seen from above the cab (front at the top):
/// a dot that fader and balance move. It shows the setting; it isn't a
/// control (the rows beside it are).
class SpeakerCab extends StatelessWidget {
  const SpeakerCab({super.key, required this.fader, required this.balance, required this.steps});

  final int fader, balance, steps;

  static const width = 150.0;

  /// The dot inside the cab's seating area, 0..1 across and down: the
  /// middle at centre, the front (fader +) up, the right (balance +) right.
  static Offset dot(int fader, int balance, int steps) {
    double f(int v) => steps <= 0 ? 0 : (v.clamp(-steps, steps) / steps);
    return Offset(0.5 + f(balance) / 2, 0.5 - f(fader) / 2);
  }

  String get _describe {
    String one(int v, String neg, String pos) => v == 0 ? 'centre' : (v > 0 ? '$pos $v' : '$neg ${-v}');
    return 'Sound centred: ${one(fader, 'rear', 'front')}, ${one(balance, 'left', 'right')}';
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final small = TextStyle(fontSize: 12, color: p.textDim);
    // Read as one description, not its Front and Rear labels.
    return Semantics(
      label: _describe,
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('spk-cab'),
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: p.background,
          border: Border.all(color: p.border),
          borderRadius: BorderRadius.circular(12),
        ),
        // Stretched across; as tall as the rows beside it. Size.zero: no
        // height of its own, so it adds none to the rows' intrinsic height.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Front', textAlign: TextAlign.center, style: small),
            const SizedBox(height: 4),
            Expanded(
              child: CustomPaint(size: Size.zero, painter: _CabPainter(dot(fader, balance, steps), p)),
            ),
            const SizedBox(height: 4),
            Text('Rear · sub', textAlign: TextAlign.center, style: small),
          ],
        ),
      ),
    );
  }
}

class _CabPainter extends CustomPainter {
  _CabPainter(this.dot, this.p);

  final Offset dot;
  final Palette p;

  @override
  void paint(Canvas canvas, Size size) {
    // The cab: as tall as there is room, about 0.6 as wide.
    final h = size.height;
    final w = (h * 0.6).clamp(0.0, size.width - 24);
    final cab = Rect.fromCenter(center: size.center(Offset.zero), width: w, height: h);
    final line = Paint()
      ..color = p.textDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(RRect.fromRectAndRadius(cab, Radius.circular(w * 0.22)), Paint()..color = p.surface);
    canvas.drawRRect(RRect.fromRectAndRadius(cab, Radius.circular(w * 0.22)), line);
    // Seats: two in front, a bench behind.
    final seat = Paint()..color = p.surfaceHigh;
    final sw = w * 0.32, sh = h * 0.2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cab.left + w * 0.13, cab.top + h * 0.22, sw, sh), const Radius.circular(5)),
      seat,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cab.right - w * 0.13 - sw, cab.top + h * 0.22, sw, sh),
        const Radius.circular(5),
      ),
      seat,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cab.left + w * 0.13, cab.top + h * 0.58, w * 0.74, sh),
        const Radius.circular(5),
      ),
      seat,
    );
    // The four speakers on the doors and the sub at the back.
    final spk = Paint()..color = p.border;
    final spkLine = Paint()
      ..color = p.textDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final o in [
      Offset(cab.left, cab.top + h * 0.32),
      Offset(cab.right, cab.top + h * 0.32),
      Offset(cab.left, cab.top + h * 0.68),
      Offset(cab.right, cab.top + h * 0.68),
    ]) {
      canvas.drawCircle(o, 6, spk);
      canvas.drawCircle(o, 6, spkLine);
    }
    final sub = Rect.fromCenter(
      center: Offset(cab.center.dx, cab.bottom - h * 0.07),
      width: w * 0.26,
      height: h * 0.07,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(sub, const Radius.circular(3)), spk);
    canvas.drawRRect(RRect.fromRectAndRadius(sub, const Radius.circular(3)), spkLine);
    // The dot, inside the seating area, centred in the cab at Centre.
    final area = Rect.fromLTRB(cab.left + w * 0.15, cab.top + h * 0.15, cab.right - w * 0.15, cab.bottom - h * 0.15);
    final at = Offset(area.left + dot.dx * area.width, area.top + dot.dy * area.height);
    canvas.drawCircle(at, 10, Paint()..color = p.accent.withValues(alpha: 0.25));
    canvas.drawCircle(
      at,
      10,
      Paint()
        ..color = p.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(at, 4, Paint()..color = p.accent);
  }

  @override
  bool shouldRepaint(_CabPainter old) => old.dot != dot || old.p != p;
}
