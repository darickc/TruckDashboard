#pragma once
//
// Warning manager: evaluates configurable per-channel thresholds against a
// Snapshot and produces Normal / Caution / Critical levels with hysteresis
// (a level is only released once the value clears the threshold by the
// hysteresis margin, so readings hovering at a limit don't flap).
//
// Stale data and lost adapter connection are surfaced separately — a stale
// channel reports Stale rather than pretending to know the level.
//
// Threshold VALUES live in include/Config.h and are labeled EXAMPLE defaults
// the user must verify for their truck — nothing here bakes in 6.0L limits.

#include <cmath>
#include <cstdint>
#include <limits>

#include "VehicleData.h"

namespace obd {

enum class WarnLevel : uint8_t {
    Normal,
    Caution,
    Critical,
    Stale, ///< channel has data but it is too old to trust
};

/// NaN disables a bound.
struct WarningRule {
    ChannelId channel;
    float lowCritical;
    float lowCaution;
    float highCaution;
    float highCritical;
    float hysteresis;
};

constexpr float kNoBound = std::numeric_limits<float>::quiet_NaN();

struct WarningState {
    WarnLevel level[kChannelCount] = {};
    bool obdConnected = false;
    bool anyStale = false;
    bool anyCaution = false;
    bool anyCritical = false;

    WarnLevel channelLevel(ChannelId id) const
    {
        return level[static_cast<size_t>(id)];
    }
};

class WarningManager {
public:
    static constexpr size_t kMaxRules = 24;

    void begin(const WarningRule* rules, size_t count, uint32_t staleAfterMs);
    void evaluate(const Snapshot& snap, bool obdConnected);
    const WarningState& state() const { return state_; }

private:
    WarnLevel classify(const WarningRule& r, float v, WarnLevel prev) const;

    WarningRule rules_[kMaxRules];
    size_t count_ = 0;
    uint32_t staleAfterMs_ = 3000;
    WarningState state_;
    WarnLevel prev_[kChannelCount] = {};
};

} // namespace obd
