#pragma once
//
// Unit tags and conversions.
//
// PID decoders produce values in whatever unit the (verified) formula yields —
// e.g. Ford EOT decodes to °C, transmission temp to °F, MAP to psi. Each
// VehicleData channel declares its canonical (display) unit — Fahrenheit, PSI,
// MPH, Volts per the project defaults — and convertUnit() bridges the two at
// store time so everything downstream (UI, warnings, telemetry) sees one unit.

#include <cstdint>

namespace obd {

enum class Unit : uint8_t {
    None,
    Rpm,
    Celsius,
    Fahrenheit,
    Kpa,
    Psi,
    Kmh,
    Mph,
    Volts,
    Percent,
    Gear,
    Count,
    Microseconds,
    MgPerStroke,
    Gph,
    Degrees,
    Gforce,
};

constexpr float cToF(float c) { return c * 9.0f / 5.0f + 32.0f; }
constexpr float fToC(float f) { return (f - 32.0f) * 5.0f / 9.0f; }
constexpr float kpaToPsi(float kpa) { return kpa * 0.1450377f; }
constexpr float psiToKpa(float psi) { return psi / 0.1450377f; }
constexpr float kmhToMph(float kmh) { return kmh * 0.6213712f; }

/// Convert between units. Unknown pairs pass the value through unchanged
/// (same-dimension identity is the common case: Psi->Psi, Volts->Volts, ...).
inline float convertUnit(float v, Unit from, Unit to)
{
    if (from == to) {
        return v;
    }
    if (from == Unit::Celsius && to == Unit::Fahrenheit) return cToF(v);
    if (from == Unit::Fahrenheit && to == Unit::Celsius) return fToC(v);
    if (from == Unit::Kpa && to == Unit::Psi) return kpaToPsi(v);
    if (from == Unit::Psi && to == Unit::Kpa) return psiToKpa(v);
    if (from == Unit::Kmh && to == Unit::Mph) return kmhToMph(v);
    if (from == Unit::Mph && to == Unit::Kmh) return v / 0.6213712f;
    return v;
}

const char* unitSuffix(Unit u);

} // namespace obd
