import 'package:flutter/material.dart';

import '../theme.dart';
import 'tap_target.dart';

/// A 60 px button with an icon and a label, dimmed when [onTap] is null:
/// the Media and Phones screens' buttons.
class AudioButton extends StatelessWidget {
  const AudioButton({
    super.key,
    required this.text,
    required this.icon,
    required this.onTap,
    this.emphasis = false,
  });

  final String text;
  final IconData icon;
  final VoidCallback? onTap;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: TapTarget(
        label: onTap == null ? '$text (unavailable)' : text,
        selected: emphasis && onTap != null,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        onTap: onTap ?? () {},
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 28, color: p.text),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
          ),
        ]),
      ),
    );
  }
}
