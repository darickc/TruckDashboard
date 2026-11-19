import 'package:flutter/material.dart';

import '../theme.dart';

/// The only way this app makes something tappable. Guarantees the minimum
/// touch target (tests check every InkWell against it) and gives it a
/// semantic label.
class TapTarget extends StatelessWidget {
  const TapTarget({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.selected = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.fill,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;
  final bool selected;
  final EdgeInsets padding;

  /// A filled button in this colour (Hang up, Answer) instead of the usual
  /// surface; its child chooses a readable colour on it ([onFill]).
  final Color? fill;

  /// White or near-black, whichever reads on [fill].
  static Color onFill(Color fill) =>
      ThemeData.estimateBrightnessForColor(fill) == Brightness.dark ? Colors.white : const Color(0xFF0B0D10);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: fill ?? (selected ? p.accent.withValues(alpha: 0.18) : p.surfaceHigh),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
              color: fill ?? (selected ? p.accent : p.border), width: selected && fill == null ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: kMinTouch, minHeight: kMinTouch),
            child: Padding(padding: padding, child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}
