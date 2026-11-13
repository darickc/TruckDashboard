#include "Dial.h"

#include <cmath>
#include <cstdio>

namespace knob {

void Dial::onData(const DataFrame& d, uint32_t nowMs)
{
    data_ = d;
    dataAtMs_ = nowMs;
    hasData_ = true;
}

bool Dial::linkLost(uint32_t nowMs) const
{
    return !hasData_ || static_cast<uint32_t>(nowMs - dataAtMs_) >= timeoutMs_;
}

View Dial::view(Slot s, uint32_t nowMs) const
{
    const size_t i = static_cast<size_t>(s);
    const SlotConfig& c = config_.slots[i];
    View v;
    v.unverified = c.set && c.unverified;
    v.unit = c.set ? c.unit : "";
    if (!hasData_) return v;
    const SlotValue& sv = data_.slots[i];
    if (!sv.set || sv.state == State::None) return v;
    v.state = sv.state;
    v.value = sv.value;
    v.ageS = sv.state == State::Stale ? sv.ageS : 0;
    if (linkLost(nowMs)) {
        // The value was good when the last frame came; it has aged since.
        const float since = static_cast<float>(static_cast<uint32_t>(nowMs - dataAtMs_)) / 1000.0f;
        v.ageS += since;
        v.state = State::Stale;
    }
    if (c.set) {
        float f = (v.value - c.min) / (c.max - c.min);
        v.fraction = f < 0 ? 0 : (f > 1 ? 1 : f);
    }
    return v;
}

void formatValue(Slot s, const View& v, char* buf, size_t size)
{
    if (v.state == State::None) {
        std::snprintf(buf, size, "\xE2\x80\x94");  // an em dash
        return;
    }
    const long n = std::lround(v.value);
    switch (s) {
        case Slot::Speed: std::snprintf(buf, size, "%ld", n); break;
        case Slot::Fuel: std::snprintf(buf, size, "%ld%%", n); break;
        case Slot::Delta: std::snprintf(buf, size, "%+ld\xC2\xB0", n); break;
        case Slot::Eot:
        case Slot::Ect: std::snprintf(buf, size, "%ld\xC2\xB0", n); break;
    }
}

void formatAge(float ageS, char* buf, size_t size)
{
    const long s = std::lround(ageS < 0 ? 0 : ageS);
    if (s < 60) {
        std::snprintf(buf, size, "%ld s", s);
    } else if (s < 3600) {
        std::snprintf(buf, size, "%ld min", s / 60);
    } else {
        std::snprintf(buf, size, "%ld h", s / 3600);
    }
}

}  // namespace knob
