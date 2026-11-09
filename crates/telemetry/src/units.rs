//! Quantities, units and conversions.
//!
//! Every value inside the model is in the **canonical unit** of its quantity
//! (`degC`, `kPa`, `V`, `km/h`, `rpm`, `%`; see
//! `docs/architecture/telemetry-model.md`). A registry formula may produce a
//! different, *formula-native* unit (Torque's Ford rows are in °F and psi);
//! [`to_canonical`] converts that once, at decode time. Display conversion
//! (metric or imperial) mirrors `apps/infotainment/lib/model/units.dart`.

use std::fmt;

use serde::{Deserialize, Serialize};

/// Physical quantity. Selects the unit family and the display conversion.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Quantity {
    Temperature,
    /// A difference of temperatures: converts by scale only, without the
    /// +32 offset absolute temperatures get.
    TemperatureDelta,
    Pressure,
    Voltage,
    Speed,
    Rotation,
    Percent,
}

impl Quantity {
    /// All quantities, for exhaustive tests.
    pub const ALL: [Quantity; 7] = [
        Quantity::Temperature,
        Quantity::TemperatureDelta,
        Quantity::Pressure,
        Quantity::Voltage,
        Quantity::Speed,
        Quantity::Rotation,
        Quantity::Percent,
    ];

    /// The unit every value of this quantity is stored in.
    pub fn canonical_unit(self) -> Unit {
        match self {
            Quantity::Temperature | Quantity::TemperatureDelta => Unit::DegC,
            Quantity::Pressure => Unit::Kpa,
            Quantity::Voltage => Unit::Volt,
            Quantity::Speed => Unit::Kmh,
            Quantity::Rotation => Unit::Rpm,
            Quantity::Percent => Unit::Percent,
        }
    }

    /// Whether `unit` measures this quantity.
    pub fn accepts(self, unit: Unit) -> bool {
        match self {
            Quantity::Temperature | Quantity::TemperatureDelta => {
                matches!(unit, Unit::DegC | Unit::DegF)
            }
            Quantity::Pressure => matches!(unit, Unit::Kpa | Unit::Psi),
            Quantity::Voltage => unit == Unit::Volt,
            Quantity::Speed => matches!(unit, Unit::Kmh | Unit::Mph),
            Quantity::Rotation => unit == Unit::Rpm,
            Quantity::Percent => unit == Unit::Percent,
        }
    }
}

/// A unit a formula may produce. Spelled in YAML as `degC`, `degF`, `kPa`,
/// `psi`, `V`, `km/h`, `mph`, `rpm`, `%`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Unit {
    #[serde(rename = "degC")]
    DegC,
    #[serde(rename = "degF")]
    DegF,
    #[serde(rename = "kPa")]
    Kpa,
    #[serde(rename = "psi")]
    Psi,
    #[serde(rename = "V")]
    Volt,
    #[serde(rename = "km/h")]
    Kmh,
    #[serde(rename = "mph")]
    Mph,
    #[serde(rename = "rpm")]
    Rpm,
    #[serde(rename = "%")]
    Percent,
}

impl Unit {
    pub fn symbol(self) -> &'static str {
        match self {
            Unit::DegC => "degC",
            Unit::DegF => "degF",
            Unit::Kpa => "kPa",
            Unit::Psi => "psi",
            Unit::Volt => "V",
            Unit::Kmh => "km/h",
            Unit::Mph => "mph",
            Unit::Rpm => "rpm",
            Unit::Percent => "%",
        }
    }
}

impl fmt::Display for Unit {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.symbol())
    }
}

impl fmt::Display for Quantity {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Quantity::Temperature => "temperature",
            Quantity::TemperatureDelta => "temperature_delta",
            Quantity::Pressure => "pressure",
            Quantity::Voltage => "voltage",
            Quantity::Speed => "speed",
            Quantity::Rotation => "rotation",
            Quantity::Percent => "percent",
        })
    }
}

/// `unit` does not measure `quantity`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
#[error("unit {unit} does not measure {quantity}")]
pub struct UnitMismatch {
    pub quantity: Quantity,
    pub unit: Unit,
}

/// kPa per psi (1 psi = 6.894757293168 kPa).
const KPA_PER_PSI: f64 = 6.894_757_293_168;
/// km per statute mile.
const KM_PER_MILE: f64 = 1.609_344;

/// Converts `value`, expressed in `unit`, to the canonical unit of
/// `quantity`. Temperature deltas scale without the 32 °F offset.
pub fn to_canonical(quantity: Quantity, unit: Unit, value: f64) -> Result<f64, UnitMismatch> {
    if !quantity.accepts(unit) {
        return Err(UnitMismatch { quantity, unit });
    }
    Ok(match (quantity, unit) {
        (Quantity::Temperature, Unit::DegF) => (value - 32.0) * 5.0 / 9.0,
        (Quantity::TemperatureDelta, Unit::DegF) => value * 5.0 / 9.0,
        (_, Unit::Psi) => value * KPA_PER_PSI,
        (_, Unit::Mph) => value * KM_PER_MILE,
        _ => value,
    })
}

/// Display preference.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum UnitSystem {
    Imperial,
    Metric,
}

/// A display unit for one quantity in one unit system.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DisplayUnit {
    pub label: &'static str,
    /// Default number of decimals.
    pub decimals: u8,
    conversion: Conversion,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Conversion {
    Identity,
    CToF,
    CDeltaToF,
    KpaToPsi,
    KmhToMph,
}

impl DisplayUnit {
    const fn new(label: &'static str, conversion: Conversion, decimals: u8) -> Self {
        Self {
            label,
            decimals,
            conversion,
        }
    }

    /// Canonical value → this display unit. Constants as in units.dart.
    pub fn convert(&self, canonical: f64) -> f64 {
        match self.conversion {
            Conversion::Identity => canonical,
            Conversion::CToF => canonical * 9.0 / 5.0 + 32.0,
            Conversion::CDeltaToF => canonical * 9.0 / 5.0,
            Conversion::KpaToPsi => canonical * 0.145_037_738,
            Conversion::KmhToMph => canonical * 0.621_371_192,
        }
    }
}

/// The display unit for `quantity` in `system` (mirrors `displayUnitFor`).
pub fn display_unit_for(quantity: Quantity, system: UnitSystem) -> DisplayUnit {
    use Conversion::*;
    use UnitSystem::*;
    match (quantity, system) {
        (Quantity::Temperature, Imperial) => DisplayUnit::new("°F", CToF, 0),
        (Quantity::Temperature, Metric) => DisplayUnit::new("°C", Identity, 0),
        (Quantity::TemperatureDelta, Imperial) => DisplayUnit::new("°F", CDeltaToF, 0),
        (Quantity::TemperatureDelta, Metric) => DisplayUnit::new("°C", Identity, 0),
        (Quantity::Pressure, Imperial) => DisplayUnit::new("psi", KpaToPsi, 1),
        (Quantity::Pressure, Metric) => DisplayUnit::new("kPa", Identity, 0),
        (Quantity::Voltage, _) => DisplayUnit::new("V", Identity, 1),
        (Quantity::Speed, Imperial) => DisplayUnit::new("mph", KmhToMph, 0),
        (Quantity::Speed, Metric) => DisplayUnit::new("km/h", Identity, 0),
        (Quantity::Rotation, _) => DisplayUnit::new("rpm", Identity, 0),
        (Quantity::Percent, _) => DisplayUnit::new("%", Identity, 0),
    }
}

/// Converts a canonical value to the display unit (for labels and thresholds).
pub fn to_display(quantity: Quantity, canonical: f64, system: UnitSystem) -> f64 {
    display_unit_for(quantity, system).convert(canonical)
}

/// Formats a canonical value for display. `decimals` overrides the
/// per-quantity precision. Values that round to zero never show as "-0".
pub fn format_value(
    quantity: Quantity,
    canonical: f64,
    system: UnitSystem,
    decimals: Option<u8>,
) -> String {
    let unit = display_unit_for(quantity, system);
    let decimals = usize::from(decimals.unwrap_or(unit.decimals));
    let text = format!("{:.*}", decimals, unit.convert(canonical));
    match text.strip_prefix('-') {
        Some(rest) if rest.chars().all(|c| c == '0' || c == '.') => rest.to_owned(),
        _ => text,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn close(a: f64, b: f64, eps: f64) -> bool {
        (a - b).abs() < eps
    }

    #[test]
    fn absolute_temperatures_convert_with_the_offset() {
        assert!(close(
            to_display(Quantity::Temperature, 100.0, UnitSystem::Imperial),
            212.0,
            1e-9
        ));
        assert!(close(
            to_display(Quantity::Temperature, -40.0, UnitSystem::Imperial),
            -40.0,
            1e-9
        ));
        assert_eq!(
            to_display(Quantity::Temperature, 90.0, UnitSystem::Metric),
            90.0
        );
    }

    #[test]
    fn temperature_differences_convert_by_scale_only() {
        // A 10 °C difference is an 18 °F difference, not 50 °F.
        assert!(close(
            to_display(Quantity::TemperatureDelta, 10.0, UnitSystem::Imperial),
            18.0,
            1e-9
        ));
    }

    #[test]
    fn pressure_and_speed() {
        assert!(close(
            to_display(Quantity::Pressure, 100.0, UnitSystem::Imperial),
            14.5038,
            1e-3
        ));
        assert!(close(
            to_display(Quantity::Speed, 100.0, UnitSystem::Imperial),
            62.137,
            1e-3
        ));
    }

    #[test]
    fn formatting_uses_per_quantity_precision_and_overrides() {
        let f = |q, v, s, d| format_value(q, v, s, d);
        assert_eq!(
            f(Quantity::Temperature, 90.0, UnitSystem::Imperial, None),
            "194"
        );
        assert_eq!(
            f(Quantity::Pressure, 100.0, UnitSystem::Imperial, None),
            "14.5"
        );
        assert_eq!(
            f(Quantity::Pressure, 4000.0, UnitSystem::Imperial, Some(0)),
            "580"
        );
        assert_eq!(
            f(Quantity::Voltage, 48.04, UnitSystem::Metric, None),
            "48.0"
        );
    }

    #[test]
    fn never_renders_negative_zero() {
        assert_eq!(
            format_value(Quantity::TemperatureDelta, -0.1, UnitSystem::Metric, None),
            "0"
        );
        assert_eq!(
            format_value(Quantity::Voltage, -0.01, UnitSystem::Metric, None),
            "0.0"
        );
        assert_eq!(
            format_value(Quantity::Voltage, -0.1, UnitSystem::Metric, None),
            "-0.1"
        );
    }

    #[test]
    fn every_quantity_has_a_display_unit_in_both_systems() {
        for q in Quantity::ALL {
            for s in [UnitSystem::Imperial, UnitSystem::Metric] {
                assert!(!display_unit_for(q, s).label.is_empty());
            }
        }
    }

    #[test]
    fn native_units_convert_to_canonical() {
        let t = |q, u, v| to_canonical(q, u, v).expect("compatible units");
        // 130.375 °F (the verified trans-temp capture, 0x0413/8) ≈ 54.65 °C.
        assert!(close(
            t(Quantity::Temperature, Unit::DegF, 130.375),
            54.652_777,
            1e-5
        ));
        assert!(close(
            t(Quantity::Temperature, Unit::DegF, 212.0),
            100.0,
            1e-9
        ));
        // Deltas scale without the offset: 18 °F of difference is 10 °C.
        assert!(close(
            t(Quantity::TemperatureDelta, Unit::DegF, 18.0),
            10.0,
            1e-9
        ));
        assert!(close(
            t(Quantity::Pressure, Unit::Psi, 14.503_773_8),
            100.0,
            1e-6
        ));
        assert!(close(t(Quantity::Speed, Unit::Mph, 60.0), 96.560_64, 1e-9));
        assert_eq!(t(Quantity::Rotation, Unit::Rpm, 700.0), 700.0);
        assert_eq!(t(Quantity::Pressure, Unit::Kpa, 101.0), 101.0);
    }

    #[test]
    fn canonical_round_trips_through_display() {
        let c = to_canonical(Quantity::Temperature, Unit::DegF, 194.0).expect("temp");
        assert!(close(
            to_display(Quantity::Temperature, c, UnitSystem::Imperial),
            194.0,
            1e-9
        ));
        let p = to_canonical(Quantity::Pressure, Unit::Psi, 30.0).expect("pressure");
        assert!(close(
            to_display(Quantity::Pressure, p, UnitSystem::Imperial),
            30.0,
            1e-6
        ));
    }

    #[test]
    fn incompatible_units_are_rejected() {
        assert_eq!(
            to_canonical(Quantity::Pressure, Unit::DegF, 1.0),
            Err(UnitMismatch {
                quantity: Quantity::Pressure,
                unit: Unit::DegF
            })
        );
        assert!(to_canonical(Quantity::Voltage, Unit::Percent, 1.0).is_err());
    }

    #[test]
    fn canonical_units_belong_to_their_quantity() {
        for q in Quantity::ALL {
            assert!(q.accepts(q.canonical_unit()), "{q}");
        }
    }
}
