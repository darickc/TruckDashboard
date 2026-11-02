import 'package:f250_infotainment/model/signal.dart';
import 'package:f250_infotainment/model/signal_catalog.dart';
import 'package:f250_infotainment/model/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('absolute temperatures convert with the offset', () {
    expect(toDisplay(Quantity.temperature, 100, UnitSystem.imperial), closeTo(212, 1e-9));
    expect(toDisplay(Quantity.temperature, -40, UnitSystem.imperial), closeTo(-40, 1e-9));
    expect(toDisplay(Quantity.temperature, 90, UnitSystem.metric), 90);
  });

  test('temperature differences convert by scale only', () {
    // A 10 °C difference is an 18 °F difference, not 50 °F.
    expect(toDisplay(Quantity.temperatureDelta, 10, UnitSystem.imperial), closeTo(18, 1e-9));
  });

  test('pressure and speed', () {
    expect(toDisplay(Quantity.pressure, 100, UnitSystem.imperial), closeTo(14.5038, 1e-3));
    expect(toDisplay(Quantity.speed, 100, UnitSystem.imperial), closeTo(62.137, 1e-3));
  });

  test('formatting uses per-quantity precision and per-signal overrides', () {
    expect(formatValue(signalsById['eot']!, 90, UnitSystem.imperial), '194');
    expect(formatValue(signalsById['boost']!, 100, UnitSystem.imperial), '14.5');
    expect(formatValue(signalsById['icp']!, 4000, UnitSystem.imperial), '580');
    expect(formatValue(signalsById['ficm_main']!, 48.04, UnitSystem.metric), '48.0');
  });

  test('never renders negative zero', () {
    expect(formatValue(signalsById['eot_ect_delta']!, -0.1, UnitSystem.metric), '0');
  });

  test('every catalog signal has a display unit in both systems', () {
    for (final s in signalCatalog) {
      for (final u in UnitSystem.values) {
        expect(displayUnitFor(s.quantity, u).label, isNotEmpty);
      }
    }
  });
}
