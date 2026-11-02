import 'package:flutter/widgets.dart';

import '../model/signal.dart';
import '../model/signal_catalog.dart';
import '../model/units.dart';
import '../telemetry/signal_state.dart';
import '../telemetry/telemetry_store.dart';
import '../telemetry/warnings.dart';
import 'theme.dart';

/// Status-bar clock: 12-hour with AM/PM, no leading zero ("7:05 PM").
/// Midnight is 12:xx AM and noon is 12:xx PM.
String formatClock(DateTime t) {
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final suffix = t.hour < 12 ? 'AM' : 'PM';
  return '$h12:${t.minute.toString().padLeft(2, '0')} $suffix';
}

String formatAge(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return '$s s';
  if (s < 3600) return '${s ~/ 60} min';
  return '${s ~/ 3600} h';
}

/// How one signal should look right now. All the rules about what may be
/// shown live here, so every widget renders validity the same way.
class SignalView {
  SignalView._({
    required this.def,
    required this.primary,
    required this.unit,
    required this.status,
    required this.statusColor,
    required this.isCurrent,
    required this.showHatch,
    required this.level,
    required this.validity,
    required this.isUnverified,
  });

  final SignalDef def;

  /// Main text: a current value, a dimmed last-good value, or an em dash.
  final String primary;
  final String unit;

  /// Second line, e.g. "STALE · 42 s" or "No data". Empty when current.
  final String status;
  final Color statusColor;

  /// True only for a valid, current value.
  final bool isCurrent;

  /// Draw the stale hatch (a last-good value is on screen, but it is old).
  final bool showHatch;

  /// Highest threshold alert on this signal.
  final AlertLevel level;
  final Validity validity;

  /// The definition (or, for a computed signal, any input's definition) has
  /// not been confirmed on this truck.
  final bool isUnverified;

  static bool _unverified(SignalDef def) =>
      def.provenance == Provenance.importedUnverified ||
      def.inputs.any((id) => signalsById[id] != null && _unverified(signalsById[id]!));

  static SignalView of(TelemetryStore store, String id, UnitSystem units, Palette p) {
    final s = store[id]!;
    final def = s.def;
    final now = store.clock.now();
    final unit = displayUnitFor(def.quantity, units).label;
    var level = AlertLevel.none;
    for (final a in store.alerts) {
      if (a.kind == AlertKind.threshold && a.signalId == id && a.level.index > level.index) {
        level = a.level;
      }
    }
    String fmt(double v) => formatValue(def, v, units);
    SignalView make(String primary, String status, Color color,
            {bool current = false, bool hatch = false}) =>
        SignalView._(
          def: def,
          primary: primary,
          unit: unit,
          status: status,
          statusColor: color,
          isCurrent: current,
          showHatch: hatch,
          level: current ? level : AlertLevel.none,
          validity: s.validity,
          isUnverified: _unverified(def),
        );

    switch (s.validity) {
      case Validity.valid:
        return make(fmt(s.value!), '', p.ok, current: true);
      case Validity.stale:
        if (def.isComputed) {
          return make('—', _inputsText(s, 'stale'), p.advisory);
        }
        if (s.lastGoodValue == null) return make('—', 'No data', p.stale);
        return make(fmt(s.lastGoodValue!), 'STALE · ${formatAge(s.ageAt(now)!)}', p.advisory,
            hatch: true);
      case Validity.noData:
        return make('—', def.isComputed ? _inputsText(s, 'no data') : 'No data', p.stale);
      case Validity.outOfRange:
        final rejected = s.lastRejectedValue;
        return make('—', rejected == null ? 'Out of range' : 'Implausible: ${fmt(rejected)} $unit',
            p.critical);
      case Validity.decodeError:
        return make('—', 'Bad response', p.critical);
      case Validity.unsupported:
        final nrc = s.lastNrc;
        return make('—',
            nrc == null ? 'Not supported' : 'Not supported (NRC ${nrc.toRadixString(16).toUpperCase()})',
            p.stale);
      case Validity.disabled:
        return make('—', def.disabledReason ?? 'Disabled', p.stale);
    }
  }

  static String _inputsText(SignalState s, String what) {
    final names = s.invalidInputs.map((id) => signalsById[id]?.shortName ?? id).join(', ');
    return names.isEmpty ? 'Inputs $what' : '$names $what';
  }
}

/// Title and detail text for an alert, in the user's units.
(String, String) describeAlert(Alert a, TelemetryStore store, UnitSystem units) {
  final now = store.clock.now();
  switch (a.kind) {
    case AlertKind.sourceLost:
      return (
        'Vehicle gateway not responding',
        'No data for ${formatAge(now - a.since)} · all values are stale'
      );
    case AlertKind.linkLost:
      return (
        'Vehicle data lost',
        'No response for ${formatAge(now - a.since)} · all values are stale'
      );
    case AlertKind.signalNotUpdating:
      final s = store[a.signalId!]!;
      final last = s.lastGoodValue;
      final detail = last == null || s.lastGoodAt == null
          ? 'No reading yet'
          : 'Last ${formatValue(s.def, last, units)} '
              '${displayUnitFor(s.def.quantity, units).label} · ${formatAge(s.ageAt(now)!)} ago';
      return ('${s.def.shortName} not updating', detail);
    case AlertKind.threshold:
      final s = store[a.signalId!]!;
      final rule = a.rule;
      final unit = displayUnitFor(s.def.quantity, units).label;
      final above = rule != null ? rule.direction == Direction.above : (a.above ?? true);
      final trigger = rule != null
          ? (a.level == AlertLevel.critical ? rule.critical! : rule.advisory!).trigger
          : a.threshold;
      final word = above ? 'high' : 'low';
      final cmp = above ? 'above' : 'below';
      final value = s.value == null ? '—' : formatValue(s.def, s.value!, units);
      return (
        '${s.def.shortName} $word',
        trigger == null
            ? '$value $unit'
            : '$value $unit · limit $cmp ${formatValue(s.def, trigger, units)} $unit (example)'
      );
  }
}
