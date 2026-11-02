#pragma once
//
// Derived values, computed in one place from fresh inputs only:
//
//   * ECT/EOT delta = EOT - ECT (the classic 6.0L oil-cooler health metric).
//   * Boost = MAP(absolute, psi) - barometric(psi). The Ford DID 1440 MAP
//     reading is absolute pressure — it is NOT boost by itself. Barometric
//     comes from SAE PID 0133 today; a physical baro sensor could replace it
//     later without touching this code.
//
// A derived channel is only written when every input is fresh; otherwise it
// goes stale naturally and the UI shows it as such.

#include <cstdint>

#include "VehicleData.h"

namespace obd::derived {

struct Config {
    uint32_t maxInputAgeMs = 3000; ///< inputs older than this don't produce output
};

void update(VehicleData& data, uint32_t now, const Config& cfg = {});

} // namespace obd::derived
