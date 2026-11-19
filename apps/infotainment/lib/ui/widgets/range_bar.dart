import 'package:flutter/material.dart';

import '../../telemetry/warnings.dart';
import '../theme.dart';

/// Display ranges for gauges (canonical units): a circular gauge's arc and a
/// digital tile's range bar. UI configuration, not vehicle data: chosen so
/// the normal range sits mid-scale and the example warning thresholds
/// (warning_rules.json) show. Signals not listed use their plausibility
/// range on a circular gauge and get no range bar.
const gaugeRanges = <String, (double, double)>{
  'rpm': (0, 4000),
  'boost': (0, 240),
  'speed': (0, 160),
  'load': (0, 100),
  // °C: 104–266 °F.
  'eot': (40, 130),
  'ect': (40, 130),
  'trans_temp': (40, 130),
  // °C difference: 0–36 °F.
  'eot_ect_delta': (0, 20),
  'ficm_main': (40, 52),
  'battery': (10, 15),
};

/// One coloured stretch of a range bar, as fractions of its width.
@immutable
class RangeZone {
  const RangeZone(this.from, this.to, this.level);

  final double from, to;
  final AlertLevel level;

  @override
  bool operator ==(Object other) =>
      other is RangeZone && other.from == from && other.to == to && other.level == level;

  @override
  int get hashCode => Object.hash(from, to, level);

  @override
  String toString() => 'RangeZone(${from.toStringAsFixed(3)}–${to.toStringAsFixed(3)}, ${level.name})';
}

/// The advisory and critical stretches of [rule] on a bar from [lo] to [hi]
/// (canonical units), by trigger: where the alert would start. Hysteresis
/// and minimum durations are the warning engine's; the bar only shows where
/// the limits are.
List<RangeZone> rangeZones(WarningRule rule, double lo, double hi) {
  double f(double x) => ((x - lo) / (hi - lo)).clamp(0.0, 1.0);
  final adv = rule.advisory?.trigger;
  final crit = rule.critical?.trigger;
  final zones = <RangeZone>[];
  if (rule.direction == Direction.above) {
    if (adv != null) zones.add(RangeZone(f(adv), f(crit ?? hi), AlertLevel.advisory));
    if (crit != null) zones.add(RangeZone(f(crit), 1, AlertLevel.critical));
  } else {
    if (crit != null) zones.add(RangeZone(0, f(crit), AlertLevel.critical));
    if (adv != null) zones.add(RangeZone(f(crit ?? lo), f(adv), AlertLevel.advisory));
  }
  return [for (final z in zones) if (z.to > z.from) z];
}

/// Where [value] sits on a bar from [lo] to [hi], clamped to its ends.
double rangeFraction(double value, double lo, double hi) => ((value - lo) / (hi - lo)).clamp(0.0, 1.0);

/// A thin bar with the example warning zones and, while the value is
/// current, a marker at it. Without a current value there is no marker and
/// the bar dims: it never points at a reading that isn't current.
class RangeBar extends StatelessWidget {
  const RangeBar({super.key, required this.zones, required this.marker});

  final List<RangeZone> zones;

  /// The current value's place (0–1), or null when it isn't current.
  final double? marker;

  static const height = 12.0;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Opacity(
      opacity: marker == null ? 0.4 : 1,
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: CustomPaint(painter: _RangeBarPainter(zones, marker, p)),
      ),
    );
  }
}

class _RangeBarPainter extends CustomPainter {
  _RangeBarPainter(this.zones, this.marker, this.p);

  final List<RangeZone> zones;
  final double? marker;
  final Palette p;

  static const _track = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 4) return;
    final top = (size.height - _track) / 2;
    final track = RRect.fromLTRBR(0, top, size.width, top + _track, const Radius.circular(3));
    canvas.save();
    canvas.clipRRect(track);
    canvas.drawRect(Offset.zero & size, Paint()..color = p.border);
    for (final z in zones) {
      final color = z.level == AlertLevel.critical ? p.critical : p.advisory;
      canvas.drawRect(Rect.fromLTRB(z.from * size.width, top, z.to * size.width, top + _track),
          Paint()..color = color.withValues(alpha: 0.55));
    }
    canvas.restore();
    final m = marker;
    if (m != null) {
      final x = (m * size.width).clamp(1.5, size.width - 1.5);
      canvas.drawRRect(
          RRect.fromLTRBR(x - 1.5, 0, x + 1.5, size.height, const Radius.circular(1.5)), Paint()..color = p.text);
    }
  }

  @override
  bool shouldRepaint(_RangeBarPainter old) => old.marker != marker || old.zones != zones || old.p != p;
}
