import 'package:flutter/material.dart';

import '../theme.dart';
import 'tap_target.dart';

/// A touchscreen keyboard for the 800×480 panel: the head unit has no
/// system keyboard (cage runs the dashboard alone). Letters, and a second
/// layer of digits and the punctuation addresses use. Every key is at least
/// 60 px square (TapTarget). Four rows of keys: 4 × 60 + 3 gaps.
class OnScreenKeyboard extends StatefulWidget {
  const OnScreenKeyboard({
    super.key,
    required this.onText,
    required this.onBackspace,
    required this.onDone,
    this.doneLabel = 'Done',
  });

  /// A key's text, to add at the end.
  final ValueChanged<String> onText;
  final VoidCallback onBackspace;

  /// The keyboard is no longer wanted (show the results).
  final VoidCallback onDone;
  final String doneLabel;

  static const gap = 5.0;
  static const height = kMinTouch * 4 + gap * 3;

  @override
  State<OnScreenKeyboard> createState() => _OnScreenKeyboardState();
}

class _OnScreenKeyboardState extends State<OnScreenKeyboard> {
  bool _digits = false;

  static const _letters = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
  static const _symbols = ['1234567890', "-/#&.,'", '()@'];

  @override
  Widget build(BuildContext context) {
    final rows = _digits ? _symbols : _letters;
    return SizedBox(
      key: const ValueKey('osk'),
      height: OnScreenKeyboard.height,
      child: Column(
        children: [
          _row([for (final c in rows[0].split('')) _char(c)]),
          _gap(),
          _row([const Spacer(flex: 1), for (final c in rows[1].split('')) _char(c), const Spacer(flex: 1)]),
          _gap(),
          _row([
            for (final c in rows[2].split('')) _char(c),
            if (_digits) const Spacer(flex: 4),
            _key(
              'osk-backspace',
              'Delete',
              const Icon(Icons.backspace_outlined, size: 28),
              widget.onBackspace,
              flex: 3,
            ),
          ]),
          _gap(),
          _row([
            _key(
              'osk-layer',
              _digits ? 'Letters' : 'Numbers',
              Text(_digits ? 'ABC' : '123', style: _labelStyle),
              () => setState(() => _digits = !_digits),
              flex: 3,
            ),
            _key('osk-space', 'Space', const Text('space', style: _labelStyle), () => widget.onText(' '), flex: 10),
            _key('osk-done', widget.doneLabel, Text(widget.doneLabel, style: _labelStyle), widget.onDone, flex: 4),
          ]),
        ],
      ),
    );
  }

  static const _labelStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.w700);

  Widget _gap() => const SizedBox(height: OnScreenKeyboard.gap);

  Widget _row(List<Widget> keys) {
    final spaced = <Widget>[];
    for (final (i, k) in keys.indexed) {
      if (i > 0) spaced.add(const SizedBox(width: OnScreenKeyboard.gap));
      spaced.add(k);
    }
    return SizedBox(
      height: kMinTouch,
      child: Row(children: spaced),
    );
  }

  Widget _char(String c) => _key(
    'osk-key-$c',
    c,
    Text(c.toUpperCase(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
    () => widget.onText(c),
    flex: 2,
  );

  Widget _key(String key, String label, Widget child, VoidCallback onTap, {int flex = 2}) => Expanded(
    flex: flex,
    child: TapTarget(key: ValueKey(key), label: label, onTap: onTap, padding: EdgeInsets.zero, child: child),
  );
}
