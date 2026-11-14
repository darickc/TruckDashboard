import 'package:flutter/material.dart';

import '../../audio/audio_state.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/audio_button.dart';
import '../widgets/panel.dart';
import '../widgets/tap_target.dart';

/// The keypad works only below this speed, km/h, from a current reading of
/// the truck's speed (ADR-0045 decision 8: a dial pad only when stopped). A
/// stale or missing speed counts as moving. An example value.
const kKeypadStoppedBelowKmh = 1.0;

/// Stopped, for the keypad: a current vehicle speed below
/// [kKeypadStoppedBelowKmh]. Never from a stale value (CLAUDE.md rule 4).
bool keypadAllowed(AppServices s) {
  final v = s.store['speed'];
  return v != null && v.isValid && v.value != null && v.value! < kKeypadStoppedBelowKmh;
}

/// Why calls can't be placed now, or null when they can.
String? callBlocker(AudioReport r) {
  if (r.phone == null) return 'No phone is connected.';
  final c = r.calls;
  if (c == null) return 'This audio-manager has no calls.';
  if (!c.available) return c.detail.isEmpty ? 'Calls stay on the phone.' : c.detail;
  return null;
}

/// "Today 8:15 AM", "Yesterday 5:10 PM", "Nov 13 9:30 AM"; the phone's own
/// clock, as it gave it.
String recentTime(DateTime t, DateTime now) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final clock = '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'Today $clock';
  if (days == 1) return 'Yesterday $clock';
  return '${months[t.month - 1]} ${t.day} $clock';
}

/// One line under a list: the request refused, else why calls can't be
/// placed, else the lists' own state.
Widget _footnote(BuildContext context, String text, {bool warn = true}) {
  final p = Palette.of(context);
  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(text,
        key: const ValueKey('phone-note'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 15, color: warn ? p.advisory : p.textDim)),
  );
}

/// What the phone's lists can't show yet, or null when there is something
/// to list.
Widget? _listState(BuildContext context, AudioReport r, int count, String fetchError, String what,
    Future<void> Function() onRefresh) {
  final p = Palette.of(context);
  final b = r.phonebook;
  Widget say(String text, {Widget? action, Color? color}) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(text,
              key: const ValueKey('phone-list-state'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: color ?? p.textDim)),
          if (action != null) ...[const SizedBox(height: 12), action],
        ]),
      );
  if (r.phone == null) {
    return say('No phone is connected. Connect one under Phones.',
        action: SizedBox(
          width: 220,
          child: AudioButton(
            key: const ValueKey('phone-go-phones'),
            text: 'Phones',
            icon: Icons.bluetooth_rounded,
            onTap: () => AppScope.of(context).phoneTab.value = PhoneTab.phones,
          ),
        ));
  }
  if (b == null) return say('This audio-manager doesn\'t read the phone\'s $what.', color: p.advisory);
  if (count > 0) return null;
  final again = SizedBox(
    width: 220,
    child: AudioButton(
      key: const ValueKey('phone-refresh'),
      text: 'Try again',
      icon: Icons.refresh_rounded,
      onTap: onRefresh,
    ),
  );
  return switch (b.phase) {
    PhonebookPhase.off => say(b.detail.isEmpty ? 'The phone\'s $what aren\'t read here.' : b.detail, color: p.advisory),
    PhonebookPhase.failed => say('The phone didn\'t share its $what: ${b.detail}', action: again, color: p.advisory),
    PhonebookPhase.loading || PhonebookPhase.none => say('Reading $what from ${r.phone!.name}…'),
    PhonebookPhase.ready when fetchError.isNotEmpty => say(fetchError, action: again, color: p.advisory),
    PhonebookPhase.ready => say('${r.phone!.name} shared no $what.', action: again),
  };
}

/// The footnote for a list: refused request, call blocker, or the lists
/// being read again or failing while older ones show.
String? _listNote(AudioReport r, String note) {
  if (note.isNotEmpty) return note;
  final block = callBlocker(r);
  if (block != null) return block;
  final b = r.phonebook;
  if (b?.phase == PhonebookPhase.loading) return 'Reading the lists again…';
  if (b?.phase == PhonebookPhase.failed) return 'Couldn\'t read them again: ${b!.detail}';
  return null;
}

/// A row: an icon, two lines of text, and a Call button.
Widget _callRow(BuildContext context,
    {required Key key,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String callKey,
    required String callLabel,
    required VoidCallback? onCall}) {
  final p = Palette.of(context);
  return SizedBox(
    key: key,
    height: kMinTouch + 6,
    child: Row(children: [
      Icon(icon, size: 26, color: iconColor),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: p.text)),
          if (subtitle.isNotEmpty)
            Text(subtitle,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: p.textDim)),
        ]),
      ),
      const SizedBox(width: kGap),
      SizedBox(
        width: 130,
        child: AudioButton(key: ValueKey(callKey), text: 'Call', icon: Icons.call_rounded, onTap: onCall),
      ),
      // Keeps the button off the scroll bar.
      const SizedBox(width: 6),
    ]),
  );
}

/// The connected phone's contacts, one row per number, by name, with a row
/// of letter groups to jump with. Usable while driving (owner, 2026-11-14):
/// a tap on Call, nothing to type.
class ContactsView extends StatefulWidget {
  const ContactsView({
    super.key,
    required this.report,
    required this.data,
    required this.fetchError,
    required this.note,
    required this.onDial,
    required this.onRefresh,
  });

  final AudioReport report;
  final PhonebookData data;
  final String fetchError, note;
  final Future<bool> Function(String number) onDial;
  final Future<void> Function() onRefresh;

  /// Each row's height, so a letter group's first row can be scrolled to.
  static const rowExtent = kMinTouch + 6 + 9;

  static const groups = ['ABC', 'DEF', 'GHI', 'JKL', 'MNO', 'PQRS', 'TUV', 'WXYZ'];

  @override
  State<ContactsView> createState() => _ContactsViewState();
}

class _ContactsViewState extends State<ContactsView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The first row whose name starts at or after [group]'s first letter;
  /// names starting with a digit or symbol come first.
  int _firstOf(List<(Contact, ContactNumber)> rows, String group) {
    for (var i = 0; i < rows.length; i++) {
      final t = rows[i].$1.name.toUpperCase();
      if (t.isNotEmpty && t.compareTo(group[0]) >= 0) return i;
    }
    return rows.length;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final r = widget.report;
    final contacts = r.phone == null ? const <Contact>[] : widget.data.contacts;
    final empty = _listState(context, r, contacts.length, widget.fetchError, 'contacts', widget.onRefresh);
    if (empty != null) return Panel(child: empty);
    final rows = [
      for (final c in contacts)
        for (final n in c.numbers) (c, n),
    ];
    final canCall = callBlocker(r) == null;
    final note = _listNote(r, widget.note);
    return Panel(
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: ListView.builder(
              key: const ValueKey('contacts-list'),
              controller: _scroll,
              itemExtent: ContactsView.rowExtent,
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final (c, n) = rows[i];
                final same = i > 0 && identical(rows[i - 1].$1, c);
                return Column(children: [
                  Divider(height: 9, color: same || i == 0 ? Colors.transparent : p.border),
                  _callRow(
                    context,
                    key: ValueKey('contact-$i'),
                    icon: same ? Icons.subdirectory_arrow_right_rounded : Icons.person_rounded,
                    iconColor: p.textDim,
                    title: c.title,
                    subtitle: [if (n.label.isNotEmpty) n.label, n.number].join(' · '),
                    callKey: 'contact-call-$i',
                    callLabel: 'Call ${c.title}',
                    onCall: canCall ? () => widget.onDial(n.number) : null,
                  ),
                ]);
              },
            ),
          ),
        ),
        if (note != null) _footnote(context, note, warn: note != 'Reading the lists again…'),
        if (rows.length > 6) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: kMinTouch,
            child: Row(children: [
              for (final (i, g) in ContactsView.groups.indexed) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: TapTarget(
                    key: ValueKey('contacts-jump-$g'),
                    label: 'Contacts from $g',
                    padding: EdgeInsets.zero,
                    onTap: () {
                      final at = _firstOf(rows, g) * ContactsView.rowExtent;
                      _scroll.jumpTo(at.clamp(0, _scroll.position.maxScrollExtent));
                    },
                    child: Text(g, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
                  ),
                ),
              ],
              const SizedBox(width: 6),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// The phone's recent calls, newest first: tap Call to call back.
class RecentView extends StatelessWidget {
  const RecentView({
    super.key,
    required this.report,
    required this.data,
    required this.fetchError,
    required this.note,
    required this.onDial,
    required this.onRefresh,
  });

  final AudioReport report;
  final PhonebookData data;
  final String fetchError, note;
  final Future<bool> Function(String number) onDial;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final r = report;
    final recent = r.phone == null ? const <RecentCall>[] : data.recent;
    final empty = _listState(context, r, recent.length, fetchError, 'recent calls', onRefresh);
    if (empty != null) return Panel(child: empty);
    final canCall = callBlocker(r) == null;
    final note = _listNote(r, this.note);
    final now = DateTime.now();
    return Panel(
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: ListView.separated(
            key: const ValueKey('recent-list'),
            itemCount: recent.length,
            separatorBuilder: (_, _) => Divider(height: 9, color: p.border),
            itemBuilder: (context, i) {
              final c = recent[i];
              final (icon, color, kind) = switch (c.kind) {
                RecentKind.missed => (Icons.call_missed_rounded, p.critical, 'Missed'),
                RecentKind.received => (Icons.call_received_rounded, p.ok, 'Incoming'),
                RecentKind.dialed => (Icons.call_made_rounded, p.accent, 'Outgoing'),
                RecentKind.unknown => (Icons.call_rounded, p.textDim, ''),
              };
              final t = c.time;
              return _callRow(
                context,
                key: ValueKey('recent-$i'),
                icon: icon,
                iconColor: color,
                title: c.title,
                subtitle: [
                  if (kind.isNotEmpty) kind,
                  if (t != null) recentTime(t, now),
                  if (c.name.isNotEmpty && c.number.isNotEmpty) c.number,
                ].join(' · '),
                callKey: 'recent-call-$i',
                callLabel: 'Call ${c.title} back',
                onCall: canCall && c.number.isNotEmpty ? () => onDial(c.number) : null,
              );
            },
          ),
        ),
        if (note != null) _footnote(context, note, warn: note != 'Reading the lists again…'),
      ]),
    );
  }
}

/// A number typed in, only when stopped (ADR-0045 decision 8): the keys
/// stay on screen while moving, dimmed, and say why.
class KeypadView extends StatefulWidget {
  const KeypadView({super.key, required this.report, required this.note, required this.onDial});

  final AudioReport report;
  final String note;
  final Future<bool> Function(String number) onDial;

  static const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];
  static const letters = {
    '2': 'ABC',
    '3': 'DEF',
    '4': 'GHI',
    '5': 'JKL',
    '6': 'MNO',
    '7': 'PQRS',
    '8': 'TUV',
    '9': 'WXYZ',
    '0': '+',
  };

  /// The longest number typed.
  static const maxLength = 32;

  @override
  State<KeypadView> createState() => _KeypadViewState();
}

class _KeypadViewState extends State<KeypadView> {
  String _number = '';

  void _press(String k) {
    if (_number.length >= KeypadView.maxLength) return;
    setState(() => _number += k);
  }

  /// 0 held: a +, as on a phone.
  void _plus() {
    if (_number.isEmpty) setState(() => _number = '+');
  }

  Future<void> _call() async {
    // Cleared once the call is placed (the call view then shows); kept to
    // correct when refused.
    if (await widget.onDial(_number) && mounted) setState(() => _number = '');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    return ListenableBuilder(
      listenable: s.store,
      builder: (context, _) {
        final stopped = keypadAllowed(s);
        final block = callBlocker(widget.report);
        final note = widget.note.isNotEmpty
            ? widget.note
            : !stopped
                ? 'Stop the truck to use the keypad. Contacts and Recent work while driving.'
                : block;
        Widget key(String k) {
          final sub = KeypadView.letters[k];
          return Opacity(
            opacity: stopped ? 1 : 0.4,
            child: GestureDetector(
              onLongPress: stopped && k == '0' ? _plus : null,
              child: TapTarget(
                key: ValueKey('keypad-$k'),
                label: stopped ? 'Key $k' : 'Key $k (stop the truck to use the keypad)',
                padding: EdgeInsets.zero,
                onTap: stopped ? () => _press(k) : () {},
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(k, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: p.text)),
                  if (sub != null) Text(sub, style: TextStyle(fontSize: 11, color: p.textDim)),
                ]),
              ),
            ),
          );
        }

        // Tight padding and gaps: under an alert banner four rows of keys
        // still get 60 px each.
        return Panel(
          padding: const EdgeInsets.all(6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              flex: 5,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  height: kMinTouch + 10,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: p.surfaceHigh,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.border),
                  ),
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(_number.isEmpty ? 'Number' : _number,
                        key: const ValueKey('keypad-number'),
                        maxLines: 1,
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: _number.isEmpty ? p.textDim : p.text)),
                  ),
                ),
                const SizedBox(height: kGap),
                SizedBox(
                  height: kMinTouch,
                  child: Row(children: [
                    Expanded(
                      child: AudioButton(
                        key: const ValueKey('keypad-delete'),
                        text: 'Delete',
                        icon: Icons.backspace_rounded,
                        onTap: _number.isEmpty
                            ? null
                            : () => setState(() => _number = _number.substring(0, _number.length - 1)),
                      ),
                    ),
                    const SizedBox(width: kGap),
                    Expanded(
                      child: AudioButton(
                        key: const ValueKey('keypad-clear'),
                        text: 'Clear',
                        icon: Icons.clear_rounded,
                        onTap: _number.isEmpty ? null : () => setState(() => _number = ''),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: kGap),
                SizedBox(
                  height: kMinTouch + 10,
                  child: AudioButton(
                    key: const ValueKey('keypad-call'),
                    text: 'Call',
                    icon: Icons.call_rounded,
                    emphasis: true,
                    onTap: stopped && block == null && _number.isNotEmpty ? _call : null,
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(height: 6),
                  Flexible(
                    child: Text(note,
                        key: const ValueKey('phone-note'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, color: p.advisory)),
                  ),
                ],
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 6,
              child: Column(children: [
                for (var row = 0; row < 4; row++) ...[
                  if (row > 0) const SizedBox(height: 4),
                  Expanded(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (var col = 0; col < 3; col++) ...[
                        if (col > 0) const SizedBox(width: 6),
                        Expanded(child: key(KeypadView.keys[row * 3 + col])),
                      ],
                    ]),
                  ),
                ],
              ]),
            ),
          ]),
        );
      },
    );
  }
}
