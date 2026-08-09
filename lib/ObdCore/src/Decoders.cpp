#include "Decoders.h"

namespace obd {

bool decodePid(const PidDefinition& pid, const uint8_t* payload, size_t len, float& out)
{
    if (pid.decodeFn != nullptr) {
        return pid.decodeFn(payload, len, out);
    }

    const LinearDecode& d = pid.decode;
    if (d.width != 1 && d.width != 2) {
        return false;
    }
    if (static_cast<size_t>(d.byteOffset) + d.width > len) {
        return false; // truncated payload — never decode garbage
    }

    float raw;
    if (d.width == 2) {
        const uint16_t u = static_cast<uint16_t>((payload[d.byteOffset] << 8) |
                                                 payload[d.byteOffset + 1]);
        raw = d.isSigned ? static_cast<float>(static_cast<int16_t>(u))
                         : static_cast<float>(u);
    } else {
        const uint8_t u = payload[d.byteOffset];
        raw = d.isSigned ? static_cast<float>(static_cast<int8_t>(u))
                         : static_cast<float>(u);
    }

    out = raw * d.scale + d.bias;
    return true;
}

} // namespace obd
