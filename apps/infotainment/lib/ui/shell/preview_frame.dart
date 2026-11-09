import 'package:flutter/material.dart';

import '../theme.dart';

/// Lays the UI out at exactly 800×480. On the target panel this is a
/// pass-through. In a desktop window or browser of any other size it
/// letterboxes and scales the panel, so development always sees the real
/// layout.
class PreviewFrame extends StatelessWidget {
  const PreviewFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final exact = (c.maxWidth - kScreenSize.width).abs() < 0.5 &&
          (c.maxHeight - kScreenSize.height).abs() < 0.5;
      final panel = SizedBox.fromSize(size: kScreenSize, child: ClipRect(child: child));
      if (exact) return panel;
      return ColoredBox(
        color: const Color(0xFF000000),
        child: Center(child: FittedBox(child: panel)),
      );
    });
  }
}
