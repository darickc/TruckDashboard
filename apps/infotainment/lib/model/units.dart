import 'signal.dart';

enum UnitSystem { imperial, metric }

/// A display unit for one quantity in one unit system.
class DisplayUnit {
  const DisplayUnit(this.label, this._convert, this.decimals);

  final String label;
  final double Function(double canonical) _convert;
  final int decimals;

  double convert(double canonical) => _convert(canonical);
}

double _id(double v) => v;
double _cToF(double c) => c * 9 / 5 + 32;
double _cDeltaToF(double c) => c * 9 / 5;
double _kPaToPsi(double kPa) => kPa * 0.145037738;
double _kmhToMph(double kmh) => kmh * 0.621371192;

/// Canonical units (telemetry-model.md): degC, kPa, V, km/h, rpm, %.
DisplayUnit displayUnitFor(Quantity q, UnitSystem s) => switch ((q, s)) {
      (Quantity.temperature, UnitSystem.imperial) => const DisplayUnit('°F', _cToF, 0),
      (Quantity.temperature, UnitSystem.metric) => const DisplayUnit('°C', _id, 0),
      (Quantity.temperatureDelta, UnitSystem.imperial) => const DisplayUnit('°F', _cDeltaToF, 0),
      (Quantity.temperatureDelta, UnitSystem.metric) => const DisplayUnit('°C', _id, 0),
      (Quantity.pressure, UnitSystem.imperial) => const DisplayUnit('psi', _kPaToPsi, 1),
      (Quantity.pressure, UnitSystem.metric) => const DisplayUnit('kPa', _id, 0),
      (Quantity.voltage, _) => const DisplayUnit('V', _id, 1),
      (Quantity.speed, UnitSystem.imperial) => const DisplayUnit('mph', _kmhToMph, 0),
      (Quantity.speed, UnitSystem.metric) => const DisplayUnit('km/h', _id, 0),
      (Quantity.rotation, _) => const DisplayUnit('rpm', _id, 0),
      (Quantity.percent, _) => const DisplayUnit('%', _id, 0),
    };

/// Formats a canonical value for display. Values that round to zero never
/// show as "-0".
String formatValue(SignalDef def, double canonical, UnitSystem s) {
  final unit = displayUnitFor(def.quantity, s);
  final decimals = def.displayDecimals ?? unit.decimals;
  final v = unit.convert(canonical);
  final text = v.toStringAsFixed(decimals);
  return RegExp(r'^-0(\.0+)?$').hasMatch(text) ? text.substring(1) : text;
}

/// Converts a canonical threshold or value to the display unit (for labels).
double toDisplay(Quantity q, double canonical, UnitSystem s) =>
    displayUnitFor(q, s).convert(canonical);
