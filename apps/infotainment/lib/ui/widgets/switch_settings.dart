import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../switch/switch_state.dart';
import '../app_scope.dart';
import '../theme.dart';
import 'tap_target.dart';

/// The order the learn flow asks for the directions.
const learnOrder = [SwitchRole.up, SwitchRole.down, SwitchRole.left, SwitchRole.right, SwitchRole.press];

/// The drawn switch's size.
const kSwitchDiagramSize = 236.0;

/// Settings › System › 5-way switch (ADR-0051; design review 2026-11-21):
/// which of the switch's wires is Up, Down, Left, Right and Press, since
/// that depends on how the switch is mounted.
///
/// The overview draws the switch as you face it. Each direction sits where
/// the thumb goes, with its tap action large and its hold action under it.
/// The drawing shows; it isn't a control.
///
/// "Set up directions" uses the same drawing:
/// - the direction asked for is lit, found ones are green with their pin
/// - a countdown shows until power-manager ends learning
/// - power-manager reports each push without acting on it, so the volume and
///   the cameras don't change during set-up
/// - nothing changes until Save
///
/// The functions of each direction are fixed: a tap is media and calls, a
/// hold a camera.
class SwitchSettingsView extends StatefulWidget {
  const SwitchSettingsView({super.key, this.leading});

  /// Shown at the left of the top row (Settings › System's back button).
  final Widget? leading;

  @override
  State<SwitchSettingsView> createState() => _SwitchSettingsViewState();
}

class _SwitchSettingsViewState extends State<SwitchSettingsView> {
  late SwitchSource _source;

  /// Learning on this screen: the wires pushed so far, in [learnOrder].
  List<SwitchWire>? _learned;

  /// power-manager has said learning is on since this screen asked for it,
  /// so a later "off" means it ended there (it ran out).
  bool _learningSeen = false;

  /// When learning started or last saw a push (the store's clock): power-
  /// manager's timeout counts from then.
  Duration? _activityAt;

  /// The last press already handled, so each counts once.
  int? _seenSeq;

  /// What happened last; [_warn] shows it as a warning (a repeated push).
  String? _message;
  bool _warn = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _source = AppScope.of(context).switchSource;
    _source.status.removeListener(_onStatus);
    _source.status.addListener(_onStatus);
    _seenSeq ??= _source.status.value.lastPress?.seq ?? -1;
  }

  @override
  void dispose() {
    _source.status.removeListener(_onStatus);
    // Never leave the switch doing nothing because this screen went away.
    if (_learned != null) unawaited(_source.setLearning(false).catchError((_) {}));
    super.dispose();
  }

  Duration _now() => AppScope.of(context).store.clock.now();

  void _say(String? message, {bool warn = false}) {
    _message = message;
    _warn = warn;
  }

  void _onStatus() {
    final s = _source.status.value;
    final learned = _learned;
    if (learned == null) {
      _seenSeq = s.lastPress?.seq ?? _seenSeq;
      return;
    }
    if (!s.usable) {
      setState(() {
        _learned = null;
        _say('power-manager went away: nothing was changed.');
      });
      return;
    }
    final r = s.report!;
    if (r.learning) {
      _learningSeen = true;
    } else if (_learningSeen) {
      setState(() {
        _learned = null;
        _say('Set-up ended: no push for ${r.learningTimeoutS} s. Nothing was changed.');
      });
      return;
    }
    final p = s.lastPress;
    if (p == null || p.seq == _seenSeq) return;
    _seenSeq = p.seq;
    _activityAt = _now();
    if (learned.length >= learnOrder.length) return;
    final want = learnOrder[learned.length];
    final already = learned.indexOf(p.wire);
    setState(() {
      if (already >= 0) {
        _say('That was ${learnOrder[already].label} again. Push the switch ${want.label.toLowerCase()}.', warn: true);
      } else {
        _learned = [...learned, p.wire];
        _say('${want.label} is on ${_pinShort(r, p.wire)}.');
      }
    });
  }

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => _say('power-manager didn\'t answer: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startLearning() => _run(() async {
    setState(() {
      _learned = [];
      _learningSeen = false;
      _activityAt = _now();
      _seenSeq = _source.status.value.lastPress?.seq ?? -1;
      _say(null);
    });
    try {
      await _source.setLearning(true);
    } catch (_) {
      if (mounted) setState(() => _learned = null);
      rethrow;
    }
  });

  void _restart() => setState(() {
    _learned = [];
    _say(null);
  });

  void _cancel() => _run(() async {
    setState(() {
      _learned = null;
      _say('Cancelled: the directions are as they were.');
    });
    await _source.setLearning(false);
  });

  void _save() => _run(() async {
    final learned = _learned!;
    final mapping = {for (final (i, w) in learned.indexed) w: learnOrder[i]};
    final r = await _source.setMapping(mapping);
    if (!mounted) return;
    setState(() {
      // Saved, or applied without a file to keep it in: either way done.
      if (r.saved || r.detail.startsWith('Applied')) _learned = null;
      _say(r.detail.isEmpty ? (r.saved ? 'Saved.' : 'Not saved.') : r.detail);
    });
  });

  void _reset() => _run(() async {
    final r = await _source.resetMapping();
    if (mounted) setState(() => _say(r.saved ? 'Back to the default directions.' : r.detail));
  });

  /// "BCM6" from "BCM6, pin 31".
  static String _pinShort(SwitchReport r, SwitchWire w) => (r.info(w)?.pin ?? w.key).split(',').first;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ValueListenableBuilder<SwitchStatus>(
      valueListenable: _source.status,
      builder: (context, s, _) {
        if (!s.usable) {
          final why = s.detail.isEmpty ? '' : ' (${s.detail})';
          return Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.leading != null) ...[widget.leading!, const SizedBox(width: 12)],
                Expanded(
                  child: Text(
                    'power-manager not connected$why: the switch\'s directions can\'t be read or changed.',
                    key: const ValueKey('sw-detail'),
                    style: TextStyle(fontSize: 15, color: p.advisory),
                  ),
                ),
              ],
            ),
          );
        }
        final r = s.report!;
        final body = _learned == null ? _overview(s, r) : _learn(s, r, _learned!);
        // Scrolls rather than squeezing when an alert banner takes height.
        return SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.fromLTRB(6, 2, 6, 6), child: body),
        );
      },
    );
  }

  // ---- the overview ---------------------------------------------------------

  Widget _overview(SwitchStatus s, SwitchReport r) {
    final p = Palette.of(context);
    final last = s.lastPress;
    final ms = r.longPressMs;
    final hold = (ms / 1000).toStringAsFixed(ms % 1000 == 0 ? 0 : 1);
    final wires = [
      for (final role in learnOrder)
        if (r.wireFor(role) case final w?) '${role.label} ${_pinShort(r, w.wire)}${w.present ? '' : ' (not readable)'}',
    ].join(' · ');
    final status = _message ?? (r.problem.isEmpty ? null : r.problem);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: kMinTouch,
          child: Row(
            children: [
              if (widget.leading != null) ...[widget.leading!, const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '5-way switch',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.text),
                    ),
                    Text(
                      'Tap: media and calls · Hold $hold s: a camera',
                      key: const ValueKey('sw-summary'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: p.textDim),
                    ),
                  ],
                ),
              ),
              if (s.link == SwitchLink.simulated) _simulatedBadge(),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // As tall as the drawing or the column, whichever is taller: the
        // buttons sit at the bottom, and long text never overflows.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: _diagram({for (final role in learnOrder) role: _overviewTile(role, r)}),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: kSwitchDiagramSize),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: p.surfaceHigh, borderRadius: BorderRadius.circular(10)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'LAST PRESS',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                color: p.textDim,
                              ),
                            ),
                            Text(
                              last == null
                                  ? 'None yet'
                                  : '${last.role.label} · ${last.kind == PressKind.short ? 'tap' : 'hold'}: ${last.result}',
                              key: const ValueKey('sw-last'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Press also answers a ringing call and hangs up. Skips are ignored during a call.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: p.text),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Wires: $wires',
                        key: const ValueKey('sw-wires'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: p.textDim),
                      ),
                      if (status != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          status,
                          key: ValueKey(_message != null ? 'sw-message' : 'sw-problem'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _message != null ? p.text : p.advisory,
                          ),
                        ),
                      ],
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: _button(
                              'sw-learn',
                              'Set up directions',
                              _busy ? null : _startLearning,
                              primary: true,
                            ),
                          ),
                          const SizedBox(width: kGap),
                          SizedBox(
                            width: 170,
                            child: _button('sw-reset', 'Reset to default', _busy || r.defaultMapping ? null : _reset),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (s.link == SwitchLink.simulated) ...[const SizedBox(height: 8), _simulateRow(r)],
      ],
    );
  }

  Widget _overviewTile(SwitchRole role, SwitchReport r) {
    final p = Palette.of(context);
    final w = r.wireFor(role);
    final missing = w == null || !w.present;
    return _tile(
      role,
      fill: role == SwitchRole.press ? p.accent.withValues(alpha: 0.10) : p.surfaceHigh,
      border: missing ? p.advisory : p.border,
      children: [
        Text(
          role.label.toUpperCase(),
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: p.textDim),
        ),
        _fit(
          Text(
            role.tileAction,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text),
          ),
        ),
        _fit(Text(role.tileHold, style: TextStyle(fontSize: 11, color: p.textDim))),
      ],
    );
  }

  // ---- set-up ---------------------------------------------------------------

  Widget _learn(SwitchStatus s, SwitchReport r, List<SwitchWire> learned) {
    final p = Palette.of(context);
    final done = learned.length >= learnOrder.length;
    final step = done ? learnOrder.length : learned.length + 1;
    final store = AppScope.of(context).store;
    final message = _message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _diagram({for (final (i, role) in learnOrder.indexed) role: _learnTile(role, i, learned, r)}),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: kSwitchDiagramSize + 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'STEP $step OF ${learnOrder.length}',
                            key: const ValueKey('sw-step'),
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.textDim),
                          ),
                          const SizedBox(width: 10),
                          // Rebuilt with the store's refresh (4 a second in the app).
                          Expanded(
                            child: ListenableBuilder(
                              listenable: store,
                              builder: (context, _) {
                                final since = _activityAt == null ? Duration.zero : store.clock.now() - _activityAt!;
                                final left = math.max(0, r.learningTimeoutS - since.inSeconds);
                                return Text(
                                  left > 0 ? 'Stops in $left s without a push' : 'Stopping…',
                                  key: const ValueKey('sw-countdown'),
                                  textAlign: TextAlign.end,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, color: p.textDim, fontFeatures: tabular),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (done)
                        Text(
                          'All five found.',
                          key: const ValueKey('sw-prompt'),
                          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: p.text),
                        )
                      else
                        _fit(
                          Row(
                            key: const ValueKey('sw-prompt'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Push ',
                                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: p.text),
                              ),
                              Text(
                                learnOrder[learned.length].label.toUpperCase(),
                                key: const ValueKey('sw-want'),
                                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: p.accent),
                              ),
                            ],
                          ),
                          alignment: Alignment.centerLeft,
                        ),
                      const SizedBox(height: 8),
                      if (message != null && _warn)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: p.advisory.withValues(alpha: 0.12),
                            border: Border.all(color: p.advisory),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 20, color: p.advisory),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  message,
                                  key: const ValueKey('sw-learn-msg'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text),
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (message != null)
                        Text(
                          message,
                          key: const ValueKey('sw-learn-msg'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text),
                        ),
                      const SizedBox(height: 6),
                      Text(
                        done
                            ? 'Save to use these directions, or start over.'
                            : 'Pushes here don\'t change the volume or the camera. Nothing is saved until Save.',
                        key: const ValueKey('sw-hint'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: p.textDim),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          SizedBox(width: 130, child: _button('sw-cancel', 'Cancel', _busy ? null : _cancel)),
                          const SizedBox(width: kGap),
                          SizedBox(
                            width: 150,
                            child: _button('sw-restart', 'Start over', _busy || learned.isEmpty ? null : _restart),
                          ),
                          const Spacer(),
                          SizedBox(
                            width: 130,
                            child: _button('sw-save', 'Save', _busy || !done ? null : _save, primary: true),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (s.link == SwitchLink.simulated) ...[const SizedBox(height: 8), _simulateRow(r, badge: true)],
      ],
    );
  }

  Widget _learnTile(SwitchRole role, int i, List<SwitchWire> learned, SwitchReport r) {
    final p = Palette.of(context);
    if (i < learned.length) {
      return _tile(
        role,
        fill: p.ok.withValues(alpha: 0.12),
        border: p.ok,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                role.label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text),
              ),
              // An icon, not a check character: the panel's fonts may lack it.
              const SizedBox(width: 4),
              Icon(Icons.check, size: 16, color: p.ok),
            ],
          ),
          Text(_pinShort(r, learned[i]), style: TextStyle(fontSize: 11, color: p.textDim)),
        ],
      );
    }
    if (i == learned.length) {
      return _tile(
        role,
        fill: p.accent.withValues(alpha: 0.22),
        border: p.accent,
        width: 2,
        children: [
          Icon(
            switch (role) {
              SwitchRole.up => Icons.arrow_upward,
              SwitchRole.down => Icons.arrow_downward,
              SwitchRole.left => Icons.arrow_back,
              SwitchRole.right => Icons.arrow_forward,
              SwitchRole.press => Icons.radio_button_checked,
            },
            size: 24,
            color: p.accent,
          ),
          Text(
            role.label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.accent),
          ),
        ],
      );
    }
    return _tile(
      role,
      fill: p.surface,
      border: p.border,
      children: [
        Text(
          role.label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.textDim),
        ),
      ],
    );
  }

  // ---- the drawn switch ----------------------------------------------------

  /// The switch as you face it: each role's tile where the thumb goes. It
  /// shows the switch; it isn't a control.
  Widget _diagram(Map<SwitchRole, Widget> tiles) {
    final p = Palette.of(context);
    const side = 76.0, h = 70.0, edge = 72.0;
    const mid = (kSwitchDiagramSize - side) / 2;
    const midY = (kSwitchDiagramSize - h) / 2;
    Widget at(double left, double top, double w, SwitchRole r) =>
        Positioned(left: left, top: top, width: w, height: h, child: tiles[r]!);
    return Semantics(
      label: 'The 5-way switch',
      container: true,
      child: Container(
        key: const ValueKey('sw-diagram'),
        width: kSwitchDiagramSize,
        height: kSwitchDiagramSize,
        decoration: BoxDecoration(
          color: p.background,
          shape: BoxShape.circle,
          border: Border.all(color: p.border),
        ),
        child: Stack(
          children: [
            at(mid, 6, side, SwitchRole.up),
            at(mid, kSwitchDiagramSize - h - 6, side, SwitchRole.down),
            at(4, midY, edge, SwitchRole.left),
            at(kSwitchDiagramSize - edge - 4, midY, edge, SwitchRole.right),
            at(mid, midY, side, SwitchRole.press),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    SwitchRole role, {
    required Color fill,
    required Color border,
    double width = 1,
    required List<Widget> children,
  }) {
    return Container(
      key: ValueKey('sw-tile-${role.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border, width: width),
        borderRadius: BorderRadius.circular(role == SwitchRole.press ? 35 : 10),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [for (final c in children) _fit(c)]),
    );
  }

  /// Scales a label down rather than clipping it (the panel's font is wide).
  Widget _fit(Widget child, {Alignment alignment = Alignment.center}) =>
      FittedBox(fit: BoxFit.scaleDown, alignment: alignment, child: child);

  // ---- shared ----------------------------------------------------------------

  /// No switch here: buttons that stand in for its five wires.
  Widget _simulateRow(SwitchReport r, {bool badge = false}) {
    final src = _source;
    if (src is! SimulatedSwitchSource) return const SizedBox.shrink();
    final p = Palette.of(context);
    return Row(
      children: [
        if (badge) ...[_simulatedBadge(), const SizedBox(width: kGap)],
        for (final (i, w) in SwitchWire.values.indexed) ...[
          if (i > 0) const SizedBox(width: kGap),
          Expanded(
            child: TapTarget(
              key: ValueKey('sw-sim-${w.name}'),
              label: 'Simulate wire ${r.info(w)?.pin ?? w.key}',
              padding: EdgeInsets.zero,
              onTap: () => src.simulatePress(w),
              child: Text(
                'Sim ${_pinShort(r, w)}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.simulated),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _simulatedBadge() {
    final p = Palette.of(context);
    return Container(
      key: const ValueKey('sw-simulated'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: p.simulated),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'SIMULATED: no switch',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.simulated),
      ),
    );
  }

  Widget _button(String key, String text, VoidCallback? onTap, {bool primary = false}) {
    final p = Palette.of(context);
    final fill = primary && onTap != null ? p.accent : null;
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: TapTarget(
        key: ValueKey(key),
        label: onTap == null ? '$text (unavailable)' : text,
        padding: EdgeInsets.zero,
        fill: fill,
        onTap: onTap ?? () {},
        child: Text(
          text,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: fill == null ? p.text : TapTarget.onFill(fill),
          ),
        ),
      ),
    );
  }
}
