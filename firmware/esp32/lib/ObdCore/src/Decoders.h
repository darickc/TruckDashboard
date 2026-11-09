#pragma once
//
// PID payload decoding. Payload passed here starts AFTER the positive-response
// echo (ElmClient strips "41 xx" / "62 xx xx" and validates it first).

#include <cstddef>
#include <cstdint>

#include "PidDefs.h"

namespace obd {

/// Decode a payload using the PID's LinearDecode (or its custom DecodeFn).
/// Rejects truncated payloads. Returns success; `out` is in pid.unit.
bool decodePid(const PidDefinition& pid, const uint8_t* payload, size_t len, float& out);

} // namespace obd
