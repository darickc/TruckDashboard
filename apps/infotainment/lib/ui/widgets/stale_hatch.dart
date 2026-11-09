import 'package:flutter/material.dart';

/// Diagonal stripes drawn behind a last-good value. Shows that the number is
/// old even when it's only glimpsed: the stripes are visible at a glance where
/// the "STALE" text may not be read.
class StaleHatch extends StatelessWidget {
  const StaleHatch({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _HatchPainter(color.withValues(alpha: 0.16)), child: const SizedBox.expand());
}

class _HatchPainter extends CustomPainter {
  _HatchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 6;
    const step = 18.0;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var x = -size.height; x < size.width; x += step) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HatchPainter old) => old.color != color;
}
