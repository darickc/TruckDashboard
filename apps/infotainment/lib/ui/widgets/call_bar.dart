import 'dart:async';

import 'package:flutter/material.dart';

import '../../audio/audio_state.dart';
import '../theme.dart';
import 'badges.dart';
import 'tap_target.dart';

/// Up to two initials from a name (words that start with a letter); empty
/// for a name with none ("555 0100"): a person icon goes there instead. The
/// call view and the contacts list.
String nameInitials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => RegExp(r'^\p{L}', unicode: true).hasMatch(w));
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}

/// A caller's initials for the Phone screen's call view; none for a number
/// or a withheld caller.
abstract final class CallBarInitials {
  static String of(PhoneCall call) => call.withheld || call.name.trim().isEmpty ? '' : nameInitials(call.name);
}

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

  /// A touch target and 4 px above and below it (84 until 2026-11-18: the
  /// bar covered the top of every screen more than it needed to).
  static const height = kMinTouch + kGap;

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

  static String _details(CallsStatus calls, PhoneCall call, {bool compact = false, bool time = true}) => [
        if (call.secondLine.isNotEmpty && !compact) call.secondLine,
        if (call.phase == CallPhase.active && time) formatTrackTime(call.active),
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
        // The time is the large figure under the caller.
        CallPhase.active => 'In call',
        CallPhase.unknown => 'Call',
      };



  /// The Phone screen (redesign 2026-11-18): what is happening at the top,
  /// the caller's initials, name and details in the middle with the call's
  /// time large, and a full-width row of large buttons at the bottom.
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
    final letters = CallBarInitials.of(call);
    return Container(
      key: const ValueKey('call-view'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent, width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: 26, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_status(call),
                key: const ValueKey('call-status'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: accent)),
          ),
          if (report.simulated) Pill('SIMULATED', color: p.simulated),
        ]),
        Expanded(
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              key: const ValueKey('call-avatar'),
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.22), shape: BoxShape.circle),
              child: letters.isEmpty
                  ? Icon(Icons.person_rounded, size: 52, color: accent)
                  : Text(letters,
                      key: const ValueKey('call-initials'),
                      style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: p.text)),
            ),
            const SizedBox(width: 22),
            Flexible(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(call.caller,
                          key: const ValueKey('call-caller'),
                          maxLines: 1,
                          style: TextStyle(fontSize: 38, height: 1.1, fontWeight: FontWeight.w800, color: p.text)),
                    ),
                    if (note.isNotEmpty || details.isNotEmpty)
                      Text(
                        note.isNotEmpty ? note : details,
                        key: const ValueKey('call-detail'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, color: note.isNotEmpty ? p.critical : p.textDim),
                      ),
                    if (call.phase == CallPhase.active)
                      Text(formatTrackTime(call.active),
                          key: const ValueKey('call-timer'),
                          style: TextStyle(
                              fontSize: 44, height: 1.15, fontWeight: FontWeight.w300, fontFeatures: tabular, color: p.text)),
                  ]),
            ),
          ]),
        ),
        SizedBox(height: 80, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: _largeButtons(context, calls, call))),
      ]),
    );
  }

  /// The Phone screen's buttons: 80 px high, side by side across the full
  /// width. Hang up and Decline are filled red, Answer filled green; Mute
  /// takes less room than Hang up.
  List<Widget> _largeButtons(BuildContext context, CallsStatus calls, PhoneCall call) {
    final p = Palette.of(context);
    Widget button(String key, String text, IconData icon, VoidCallback onTap,
        {Color? fill, Color? color, bool selected = false, String? label, int flex = 1}) {
      final fg = fill != null ? TapTarget.onFill(fill) : (color ?? p.text);
      return Expanded(
        flex: flex,
        child: TapTarget(
          key: ValueKey(key),
          label: label ?? '$text: ${call.caller}',
          selected: selected,
          fill: fill,
          onTap: onTap,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 30, color: fg),
            const SizedBox(width: 10),
            Flexible(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: fg)),
            ),
          ]),
        ),
      );
    }

    final hangUp = button('call-hang-up', call.rings ? 'Decline' : 'Hang up', Icons.call_end_rounded,
        () => _ask(call.id, () => widget.audio.hangUp(call.id)),
        fill: p.critical, flex: call.phase == CallPhase.active ? 8 : 5);
    const gap = SizedBox(width: kGap + 2);
    return switch (call.phase) {
      CallPhase.incoming => [
          hangUp,
          gap,
          button('call-answer', 'Answer', Icons.call_rounded,
              () => _ask(call.id, () => widget.audio.answerCall(call.id)),
              fill: p.ok, flex: 5),
        ],
      CallPhase.active => [
          button(
            'call-mute',
            calls.micMuted ? 'Muted' : 'Mute',
            calls.micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            () => _ask(call.id, () => widget.audio.setMicMuted(!calls.micMuted)),
            color: calls.micMuted ? p.advisory : p.text,
            selected: calls.micMuted,
            label: calls.micMuted ? 'Unmute the microphone' : 'Mute the microphone',
            flex: 5,
          ),
          gap,
          hangUp,
        ],
      // Dialling, ringing out, on hold, waiting: Hang up alone, centred.
      _ => [const Spacer(flex: 2), hangUp, const Spacer(flex: 2)],
    };
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

  /// Over the top of a screen (redesign 2026-11-18): what it is and who on
  /// one line, with the call's time; the details (or a refusal) under it;
  /// the buttons as icons, each a full touch target with its word as its
  /// label.
  Widget _bar(BuildContext context, AudioReport report, CallsStatus calls, PhoneCall call) {
    final p = Palette.of(context);
    final note = _noteCall == call.id ? _note : '';
    final (label, icon) = _label(call);
    final details = _details(calls, call, time: false);
    final accent = call.rings ? p.ok : p.accent;
    return Container(
      key: const ValueKey('call-bar'),
      height: CallBar.height,
      // The 3 px bottom border takes its room from the padding under the
      // buttons, so they stay 60 px.
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 1),
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
        Icon(icon, size: 26, color: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '$label  ', style: TextStyle(fontSize: 13, color: p.textDim)),
                      TextSpan(
                          text: call.caller, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.text)),
                    ]),
                    key: const ValueKey('call-caller'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (call.phase == CallPhase.active) ...[
                  const SizedBox(width: 10),
                  Text(formatTrackTime(call.active),
                      key: const ValueKey('call-bar-timer'),
                      style: TextStyle(fontSize: 18, fontFeatures: tabular, color: accent)),
                ],
              ]),
              if (note.isNotEmpty || details.isNotEmpty)
                Text(
                  note.isNotEmpty ? note : details,
                  key: const ValueKey('call-detail'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: note.isNotEmpty ? p.critical : p.textDim),
                ),
            ],
          ),
        ),
        const SizedBox(width: kGap),
        ..._barButtons(context, calls, call),
      ]),
    );
  }

  /// The bar's buttons: icons, 60 px high. Hang up and Decline filled red,
  /// Answer filled green, Mute plain (highlighted while muted).
  List<Widget> _barButtons(BuildContext context, CallsStatus calls, PhoneCall call) {
    final p = Palette.of(context);
    Widget button(String key, String label, IconData icon, VoidCallback onTap,
        {Color? fill, Color? color, bool selected = false, double width = 96}) {
      return Padding(
        padding: const EdgeInsets.only(left: kGap),
        child: SizedBox(
          width: width,
          height: kMinTouch,
          child: TapTarget(
            key: ValueKey(key),
            label: label,
            selected: selected,
            fill: fill,
            padding: EdgeInsets.zero,
            onTap: onTap,
            child: Icon(icon, size: 28, color: fill != null ? TapTarget.onFill(fill) : (color ?? p.text)),
          ),
        ),
      );
    }

    final hangUp = button('call-hang-up', '${call.rings ? 'Decline' : 'Hang up'}: ${call.caller}',
        Icons.call_end_rounded, () => _ask(call.id, () => widget.audio.hangUp(call.id)),
        fill: p.critical);
    return switch (call.phase) {
      CallPhase.incoming => [
          hangUp,
          button('call-answer', 'Answer: ${call.caller}', Icons.call_rounded,
              () => _ask(call.id, () => widget.audio.answerCall(call.id)),
              fill: p.ok),
        ],
      CallPhase.active => [
          button(
            'call-mute',
            calls.micMuted ? 'Unmute the microphone' : 'Mute the microphone',
            calls.micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            () => _ask(call.id, () => widget.audio.setMicMuted(!calls.micMuted)),
            color: calls.micMuted ? p.advisory : p.text,
            selected: calls.micMuted,
            width: 64,
          ),
          hangUp,
        ],
      _ => [hangUp],
    };
  }

  /// Camera mode's buttons (the column under the caller), worded; the bar
  /// has [_barButtons], the Phone screen [_largeButtons].
  List<Widget> _buttons(BuildContext context, CallsStatus calls, PhoneCall call) {
    final p = Palette.of(context);
    Widget button(String key, String text, IconData icon, Color color, VoidCallback onTap,
            {bool selected = false, String? label}) =>
        Padding(
          padding: const EdgeInsets.only(right: 3),
          child: SizedBox(
            width: double.infinity,
            height: kMinTouch,
            child: TapTarget(
              key: ValueKey(key),
              label: label ?? '$text: ${call.caller}',
              selected: selected,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              onTap: onTap,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
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
