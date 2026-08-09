#pragma once
//
// Time abstraction so the core never calls millis() directly.
// Firmware injects Arduino millis(); tests inject a virtual clock.
// All timing math uses int32_t subtraction so uint32 wraparound (~49.7 days)
// is handled correctly: (int32_t)(now - deadline) >= 0 means "expired".

#include <cstdint>

namespace obd {

using TimeFn = uint32_t (*)();

/// True when `now` has reached or passed `deadline`, wraparound-safe.
inline bool timeReached(uint32_t now, uint32_t deadline)
{
    return static_cast<int32_t>(now - deadline) >= 0;
}

/// Age of a timestamp relative to now, wraparound-safe (0 if in the future).
inline uint32_t timeSince(uint32_t now, uint32_t then)
{
    const int32_t d = static_cast<int32_t>(now - then);
    return d > 0 ? static_cast<uint32_t>(d) : 0u;
}

} // namespace obd
