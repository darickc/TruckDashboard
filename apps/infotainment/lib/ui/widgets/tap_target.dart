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
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;
  final bool selected;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? p.accent.withValues(alpha: 0.18) : p.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? p.accent : p.border, width: selected ? 2 : 1),
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
