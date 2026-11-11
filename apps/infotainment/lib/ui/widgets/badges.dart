import 'package:flutter/material.dart';

import '../../model/signal.dart';
import '../theme.dart';

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color, this.filled = false});

  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: filled ? Palette.of(context).background : color,
        ),
      ),
    );
  }
}

/// Marks a value whose definition hasn't been confirmed on this truck.
class UnverifiedBadge extends StatelessWidget {
  const UnverifiedBadge({super.key});

  @override
  Widget build(BuildContext context) =>
      Pill('UNVERIFIED', color: Palette.of(context).textDim);
}

String provenanceLabel(Provenance p) => switch (p) {
      Provenance.sae => 'SAE',
      Provenance.verifiedOnTruck => 'Verified',
      Provenance.importedUnverified => 'Unverified',
      Provenance.computed => 'Computed',
      Provenance.auxSensor => 'Aux sensor',
    };

String validityLabel(Validity v) => switch (v) {
      Validity.valid => 'VALID',
      Validity.stale => 'STALE',
      Validity.noData => 'NO DATA',
      Validity.outOfRange => 'RANGE',
      Validity.decodeError => 'DECODE',
      Validity.unsupported => 'UNSUPPORTED',
      Validity.disabled => 'DISABLED',
    };

Color validityColor(Validity v, Palette p) => switch (v) {
      Validity.valid => p.ok,
      Validity.stale => p.advisory,
      Validity.outOfRange || Validity.decodeError => p.critical,
      Validity.noData || Validity.unsupported || Validity.disabled => p.stale,
    };
