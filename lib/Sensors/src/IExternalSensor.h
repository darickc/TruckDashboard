#pragma once
//
// FUTURE: external sensor inputs.
//
// The stock 6.0L PCM does NOT expose everything worth watching. Two values in
// particular must come from added hardware, never faked from OBD:
//
//   * Low-pressure fuel pressure — external transducer (e.g. 0-30 psi,
//     0.5-4.5 V output into an ADC; the ESP32 ADC needs a divider/buffer).
//   * EGT — thermocouple + amplifier (e.g. type-K + MAX31856) ahead of the
//     turbo.
//
// Implementations will poll their hardware and publish into VehicleData
// exactly like OBD PIDs do (new ChannelIds: FuelPressurePsi, EgtF), which
// makes them first-class citizens for warnings/display/telemetry with zero
// changes to that machinery.

#include <cstdint>

namespace sensors {

class IExternalSensor {
public:
    virtual ~IExternalSensor() = default;

    virtual bool begin() = 0;

    /// Non-blocking poll; returns true when a new sample was published.
    virtual bool poll(uint32_t nowMs) = 0;

    virtual const char* name() const = 0;
};

} // namespace sensors
