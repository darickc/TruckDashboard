import 'dart:async';

import 'package:flutter/material.dart';

import '../../audio/audio_state.dart';
import '../theme.dart';
import 'badges.dart';
import 'tap_target.dart';

/// A phone call (ADR-0045 decision 5), over the top of whatever screen shows:
/// below the status bar and the alert banner (vehicle alerts stay above it),
/// on every screen. Ringing: who is calling, Answer and Decline (a waiting
/// call is answered on the phone). During a call: who, how long, Mute and
/// Hang up. Nothing to type. Gone with the call, the phone or audio-manager:
/// a call is never shown from a report that isn't current.
///
/// [compact]: camera mode's left column (220 px wide), where the camera's
/// window covers the rest of the screen: the caller over two lines, the
/// buttons below, side by side.
///
/// [large]: the Phone screen's call view (ADR-0045 phase 2), filling the
/// screen area: what is happening, the caller large, and larger buttons.
/// The bar over the top of the screen is hidden there.
class CallBar extends StatefulWidget {
  const CallBar({super.key, required this.audio, this.compact = false, this.large = false});

  final AudioSource audio;
  final bool compact, large;

  static const height = kMinTouch + 2 * kGap + 4;

  @override
  State<CallBar> createState() => _CallBarState();
}

class _CallBarState extends State<CallBar> {
  /// What the last request answered, when it wasn't done; cleared after a
  /// few seconds and when the call changes.
  String _note = '';
  int? _noteCall;
  Timer? _clear;
  bool _busy = false;

  @override
  void dispose() {
    _clear?.cancel();
    super.dispose();
  }

  Future<void> _ask(int call, Future<CommandResult> Function() request) async {
    if (_busy) return;
    setState(() => _busy = true);
    CommandResult r;
    try {
      r = await request();
    } catch (e) {
      r = CommandResult(ok: false, detail: 'audio-manager didn\'t answer: $e');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _note = r.ok ? '' : r.detail;
      _noteCall = call;
    });
    _clear?.cancel();
    if (!r.ok) {
      _clear = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _note = '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.audio.status,
      builder: (context, status, _) {
        final report = status.link == AudioLink.up ? status.report : null;
        final calls = report?.calls;
        final call = calls?.call;
        if (report == null || calls == null || call == null) return const SizedBox.shrink();
        if (widget.large) return _large(context, report, calls, call);
        return widget.compact ? _panel(context, report, calls, call) : _bar(context, report, calls, call);
      },
    );
  }

  static (String, IconData) _label(PhoneCall call) => switch (call.phase) {
        CallPhase.incoming => ('Incoming call', Icons.ring_volume_rounded),
        CallPhase.waiting => ('Another call', Icons.ring_volume_rounded),
        CallPhase.dialing || CallPhase.alerting => ('Calling', Icons.call_made_rounded),
        CallPhase.held => ('On hold', Icons.phone_paused_rounded),
        CallPhase.active || CallPhase.unknown => ('Call', Icons.phone_in_talk_rounded),
      };

  static String _details(CallsStatus calls, PhoneCall call, {bool compact = false}) => [
        if (call.secondLine.isNotEmpty && !compact) call.secondLine,
        if (call.phase == CallPhase.active) formatTrackTime(call.active),
        if (calls.otherCalls > 0) '${calls.otherCalls} more on the phone',
        if (call.phase == CallPhase.waiting) 'answer it on the phone',
        if (calls.phoneName.isNotEmpty && !compact) 'on ${calls.phoneName}',
      ].join(' · ');

  /// What is happening, in words, for the Phone screen.
  static String _status(PhoneCall call) => switch (call.phase) {
        CallPhase.incoming => 'Incoming call',
        CallPhase.waiting => 'Another call · answer it on the phone',
        CallPhase.dialing => 'Calling…',
        CallPhase.alerting => 'Ringing…',
        CallPhase.held => 'On hold',
        CallPhase.active => 'In call · ${formatTrackTime(call.active)}',
        CallPhase.unknown => 'Call',
      };

  /// The Phone screen: the caller large in the middle, the buttons below.
  Widget _large(BuildContext context, AudioReport report, CallsStatus calls, PhoneCall call) {
    final p = Palette.of(context);
    final note = _noteCall == call.id ? _note : '';
    final (_, icon) = _label(call);
    final accent = call.rings ? p.ok : p.accent;
    final details = [
      if (call.secondLine.isNotEmpty) call.secondLine,
      if (calls.otherCalls > 0) '${calls.otherCalls} more on the phone',
      if (calls.phoneName.isNotEmpty) 'on ${calls.phoneName}',
    ].join(' · ');
    return Container(
      key: const ValueKey('call-view'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent, width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: 30, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_status(call),
                key: const ValueKey('call-status'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: accent)),
          ),
          if (report.simulated) Pill('SIMULATED', color: p.simulated),
        ]),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(call.caller,
                  key: const ValueKey('call-caller'),
                  maxLines: 1,
                  style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: p.text)),
            ),
            if (note.isNotEmpty || details.isNotEmpty)
              Text(
                note.isNotEmpty ? note : details,
                key: const ValueKey('call-detail'),
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, color: note.isNotEmpty ? p.critical : p.textDim),
              ),
          ]),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: _buttons(context, calls, call)),
      ]),
    );
  }

  /// Camera mode: the caller over two lines, the buttons side by side.
  Widget _panel(BuildContext context, AudioReport report, CallsStatus calls, PhoneCall call) {
    final p = Palette.of(context);
    final note = _noteCall == call.id ? _note : '';
    final (label, icon) = _label(call);
    final details = _details(calls, call, compact: true);
    final accent = call.rings ? p.ok : p.accent;
    return Container(
      key: const ValueKey('call-bar'),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 3),
      decoration: BoxDecoration(
        color: p.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent, width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (report.simulated) ...[
            Pill('SIM', color: p.simulated),
            const SizedBox(width: 6),
          ],
          Icon(icon, size: 20, color: accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.textDim)),
          ),
        ]),
        Text.rich(
          TextSpan(text: call.caller, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text)),
          key: const ValueKey('call-caller'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (note.isNotEmpty || details.isNotEmpty)
          Text(
            note.isNotEmpty ? note : details,
            key: const ValueKey('call-detail'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: note.isNotEmpty ? p.critical : p.textDim),
          ),
        const SizedBox(height: 4),
        SizedBox(
          height: kMinTouch,
          child: Row(children: [
            for (final b in _buttons(context, calls, call)) Expanded(child: b),
          ]),
        ),
      ]),
    );
  }

  Widget _bar(BuildContext context, AudioReport report, CallsStatus calls, PhoneCall call) {
    final p = Palette.of(context);
    final note = _noteCall == call.id ? _note : '';
    final (label, icon) = _label(call);
    final details = _details(calls, call);
    final accent = call.rings ? p.ok : p.accent;
    return Container(
      key: const ValueKey('call-bar'),
      height: CallBar.height,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: kGap),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: accent, width: 3)),
        boxShadow: const [BoxShadow(blurRadius: 8, color: Color(0x66000000))],
      ),
      child: Row(children: [
        if (report.simulated) ...[
          Pill('SIM', color: p.simulated),
          const SizedBox(width: 8),
        ],
        Icon(icon, size: 30, color: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '$label  ', style: TextStyle(fontSize: 14, color: p.textDim)),
                  TextSpan(text: call.caller, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.text)),
                ]),
                key: const ValueKey('call-caller'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                note.isNotEmpty ? note : details,
                key: const ValueKey('call-detail'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: note.isNotEmpty ? p.critical : p.textDim),
              ),
            ],
          ),
        ),
        ..._buttons(context, calls, call),
      ]),
    );
  }

  List<Widget> _buttons(BuildContext context, CallsStatus calls, PhoneCall call) {
    final p = Palette.of(context);
    final compact = widget.compact;
    final large = widget.large;
    Widget button(String key, String text, IconData icon, Color color, VoidCallback onTap,
            {bool selected = false, String? label}) =>
        Padding(
          padding: EdgeInsets.only(left: compact ? 0 : kGap, right: compact ? 3 : 0),
          child: SizedBox(
            width: compact ? double.infinity : (large ? 200 : 140),
            height: large ? 76 : kMinTouch,
            child: TapTarget(
              key: ValueKey(key),
              label: label ?? '$text: ${call.caller}',
              selected: selected,
              padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8),
              onTap: onTap,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: compact ? 22 : (large ? 32 : 26), color: color),
                SizedBox(width: compact ? 3 : 6),
                Flexible(
                  child: Text(text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: compact ? 15 : (large ? 20 : 17), fontWeight: FontWeight.w800, color: color)),
                ),
              ]),
            ),
          ),
        );
    final hangUp = button('call-hang-up', call.rings ? 'Decline' : 'Hang up', Icons.call_end_rounded, p.critical,
        () => _ask(call.id, () => widget.audio.hangUp(call.id)));
    return switch (call.phase) {
      CallPhase.incoming => [
          hangUp,
          button('call-answer', 'Answer', Icons.call_rounded, p.ok,
              () => _ask(call.id, () => widget.audio.answerCall(call.id))),
        ],
      CallPhase.active => [
          button(
            'call-mute',
            calls.micMuted ? 'Muted' : 'Mute',
            calls.micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            calls.micMuted ? p.advisory : p.text,
            () => _ask(call.id, () => widget.audio.setMicMuted(!calls.micMuted)),
            selected: calls.micMuted,
            label: calls.micMuted ? 'Unmute the microphone' : 'Mute the microphone',
          ),
          hangUp,
        ],
      _ => [hangUp],
    };
  }
}
