import 'package:flutter/material.dart';

import '../../telemetry/warnings.dart';
import '../presentation.dart';
import '../theme.dart';
import 'badges.dart';
import 'signal_builder.dart';
import 'stale_hatch.dart';

Color levelColor(AlertLevel level, Palette p) => switch (level) {
      AlertLevel.critical => p.critical,
      AlertLevel.advisory => p.advisory,
      AlertLevel.none => p.border,
    };

/// Shared frame for every gauge style: border shows the warning level, the
/// hatch shows staleness, a badge shows an unverified definition.
class GaugeFrame extends StatelessWidget {
  const GaugeFrame({super.key, required this.view, required this.child});

  final SignalView view;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final level = view.level;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: levelColor(level, p), width: level == AlertLevel.none ? 1 : 3),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        if (view.showHatch) Positioned.fill(child: StaleHatch(color: p.advisory)),
        Positioned.fill(child: child),
      ]),
    );
  }
}

/// Large digital readout. Scales its numerals to the space it gets.
class DigitalGauge extends StatelessWidget {
  const DigitalGauge({super.key, required this.signalId, this.label});

  final String signalId;

  /// Overrides the signal's short name.
  final String? label;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      signalId: signalId,
      builder: (context, v) {
        final p = Palette.of(context);
        final valueColor = v.isCurrent ? p.text : p.stale;
        return GaugeFrame(
          view: v,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(label ?? v.def.shortName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600, color: p.textDim)),
                  ),
                  if (v.isUnverified) const UnverifiedBadge(),
                ]),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(v.primary,
                            key: ValueKey('value-$signalId'),
                            style: TextStyle(
                                fontSize: 56,
                                height: 1.0,
                                fontWeight: FontWeight.w700,
                                fontFeatures: tabular,
                                color: valueColor)),
                        // A unit beside a dash reads as a value; omit it.
                        if (v.primary != '—') ...[
                          const SizedBox(width: 4),
                          Text(v.unit, style: TextStyle(fontSize: 20, color: p.textDim)),
                        ],
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: 18,
                  child: Text(v.status,
                      key: ValueKey('status-$signalId'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700, color: v.statusColor)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One-line indicator: name, value, status dot. For dense summaries.
class CompactIndicator extends StatelessWidget {
  const CompactIndicator({super.key, required this.signalId});

  final String signalId;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      signalId: signalId,
      builder: (context, v) {
        final p = Palette.of(context);
        final dot = v.isCurrent ? levelColor(v.level, p) : v.statusColor;
        return SizedBox(
          height: 26,
          child: Row(children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: v.isCurrent && v.level == AlertLevel.none ? p.ok : dot,
                    shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(v.def.shortName,
                    maxLines: 1, style: TextStyle(fontSize: 15, color: p.textDim))),
            Text(
              v.isCurrent ? '${v.primary} ${v.unit}' : (v.status.isEmpty ? '—' : v.status),
              key: ValueKey('compact-$signalId'),
              maxLines: 1,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFeatures: tabular,
                  color: v.isCurrent ? p.text : v.statusColor),
            ),
          ]),
        );
      },
    );
  }
}
