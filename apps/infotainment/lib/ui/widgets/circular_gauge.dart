import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../model/units.dart';
import '../app_scope.dart';
import '../theme.dart';
import 'badges.dart';
import 'gauge_tile.dart';
import 'signal_builder.dart';

/// Display ranges for circular gauges (canonical units). UI configuration,
/// not vehicle data. Signals not listed use their plausibility range.
const _gaugeRange = <String, (double, double)>{
  'rpm': (0, 4000),
  'boost': (0, 240),
  'speed': (0, 160),
  'load': (0, 100),
};

class CircularGauge extends StatelessWidget {
  const CircularGauge({super.key, required this.signalId});

  final String signalId;

  @override
  Widget build(BuildContext context) {
    final units = AppScope.of(context).settings.units;
    return SignalBuilder(
      signalId: signalId,
      builder: (context, v) {
        final p = Palette.of(context);
        final (lo, hi) = _gaugeRange[signalId] ?? (v.def.min, v.def.max);
        final s = AppScope.of(context).store[signalId]!;
        final fraction = v.isCurrent ? ((s.value! - lo) / (hi - lo)).clamp(0.0, 1.0) : null;
        return GaugeFrame(
          view: v,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Stack(children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ArcPainter(
                    fraction: fraction,
                    track: p.border,
                    fill: v.isCurrent ? levelColor(v.level, p) == p.border ? p.accent : levelColor(v.level, p) : p.stale,
                  ),
                ),
              ),
              Positioned(
                left: 4,
                top: 0,
                right: 4,
                child: Row(children: [
                  Expanded(
                      child: Text(v.def.shortName,
                          maxLines: 1,
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600, color: p.textDim))),
                  if (v.isUnverified) const UnverifiedBadge(),
                ]),
              ),
              Positioned.fill(
                top: 18,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(v.primary,
                          key: ValueKey('value-$signalId'),
                          style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              fontFeatures: tabular,
                              color: v.isCurrent ? p.text : p.stale)),
                      Text(v.isCurrent ? v.unit : v.status,
                          key: ValueKey('status-$signalId'),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: v.isCurrent ? p.textDim : v.statusColor)),
                    ]),
                  ),
                ),
              ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 0,
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  for (final edge in [lo, hi])
                    Text(formatValue(v.def, edge, units),
                        style: TextStyle(fontSize: 11, color: p.textDim)),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({required this.fraction, required this.track, required this.fill});

  /// Null when there is no current value: draw the track only.
  final double? fraction;
  final Color track;
  final Color fill;

  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2 - 8;
    if (r <= 0) return;
    final rect = Rect.fromCircle(center: size.center(Offset(0, 6)), radius: r);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, stroke..color = track);
    final f = fraction;
    if (f != null && f > 0) {
      canvas.drawArc(rect, _start, _sweep * f, false, stroke..color = fill);
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.fraction != fraction || old.fill != fill || old.track != track;
}
