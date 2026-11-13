// What the dial shows (ADR-0044 decision 4), from the last frames and the
// time since. The dial decides one thing on its own: with no data frame for
// `linkTimeoutMs`, everything is stale, its age counting on.

#pragma once

#include <cstddef>
#include <cstdint>

#include "Frame.h"

namespace knob {

struct View {
    State state = State::None;
    // Meaningful unless state is None.
    float value = 0;
    // Stale only: how old the value is now.
    float ageS = 0;
    // 0..1 along the slot's arc (0 when there is nothing to show or no range).
    float fraction = 0;
    bool unverified = false;
    const char* unit = "";
};

class Dial {
public:
    explicit Dial(uint32_t linkTimeoutMs = 2000) : timeoutMs_(linkTimeoutMs) {}

    void onConfig(const ConfigFrame& c) { config_ = c; }
    void onData(const DataFrame& d, uint32_t nowMs);

    View view(Slot s, uint32_t nowMs) const;

    // No data frame yet, or none for the timeout.
    bool linkLost(uint32_t nowMs) const;
    bool everHadData() const { return hasData_; }
    bool simulated() const { return hasData_ && data_.simulated; }

private:
    uint32_t timeoutMs_;
    ConfigFrame config_;
    DataFrame data_;
    bool hasData_ = false;
    uint32_t dataAtMs_ = 0;
};

// The text under an arc or in the middle: "62", "205°", "+9°", "61%", "—".
// `buf` takes at least 12 characters.
void formatValue(Slot s, const View& v, char* buf, size_t size);

// "12 s", "3 min", "2 h": a stale value's age.
void formatAge(float ageS, char* buf, size_t size);

}  // namespace knob
