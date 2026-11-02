import 'package:flutter/material.dart';

import '../theme.dart';

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.title, this.padding = const EdgeInsets.all(10)});

  final String? title;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      padding: padding,
      child: title == null
          ? child
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title!,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.textDim)),
              const SizedBox(height: 6),
              Expanded(child: child),
            ]),
    );
  }
}

/// Full-screen notice for a feature that does not exist yet. Says so plainly,
/// so nobody mistakes it for a broken or disconnected feature.
class NotImplementedScreen extends StatelessWidget {
  const NotImplementedScreen({
    super.key,
    required this.icon,
    required this.title,
    required this.lines,
  });

  final IconData icon;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Panel(
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: p.textDim),
          const SizedBox(height: 10),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: p.text)),
          const SizedBox(height: 8),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l,
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: p.textDim)),
            ),
        ]),
      ),
    );
  }
}
