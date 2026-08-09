#include "Warnings.h"

namespace obd {

namespace {

bool bounded(float bound) { return !std::isnan(bound); }

} // namespace

void WarningManager::begin(const WarningRule* rules, size_t count, uint32_t staleAfterMs)
{
    count_ = count < kMaxRules ? count : kMaxRules;
    for (size_t i = 0; i < count_; ++i) {
        rules_[i] = rules[i];
    }
    staleAfterMs_ = staleAfterMs;
    state_ = WarningState{};
    for (size_t i = 0; i < kChannelCount; ++i) {
        prev_[i] = WarnLevel::Normal;
    }
}

WarnLevel WarningManager::classify(const WarningRule& r, float v, WarnLevel prev) const
{
    const float h = r.hysteresis;

    // Raw level ignoring hysteresis.
    WarnLevel raw = WarnLevel::Normal;
    if ((bounded(r.highCritical) && v >= r.highCritical) ||
        (bounded(r.lowCritical) && v <= r.lowCritical)) {
        raw = WarnLevel::Critical;
    } else if ((bounded(r.highCaution) && v >= r.highCaution) ||
               (bounded(r.lowCaution) && v <= r.lowCaution)) {
        raw = WarnLevel::Caution;
    }

    if (raw >= prev || prev == WarnLevel::Stale) {
        return raw; // escalation (or recovery from stale) applies immediately
    }

    // De-escalation: value must clear the previous level's threshold by the
    // hysteresis margin, otherwise the previous level holds.
    if (prev == WarnLevel::Critical) {
        const bool clearedHigh = !bounded(r.highCritical) || v < r.highCritical - h;
        const bool clearedLow = !bounded(r.lowCritical) || v > r.lowCritical + h;
        if (!(clearedHigh && clearedLow)) {
            return WarnLevel::Critical;
        }
    }
    if (raw < WarnLevel::Caution &&
        (prev == WarnLevel::Caution || prev == WarnLevel::Critical)) {
        const bool clearedHigh = !bounded(r.highCaution) || v < r.highCaution - h;
        const bool clearedLow = !bounded(r.lowCaution) || v > r.lowCaution + h;
        if (!(clearedHigh && clearedLow)) {
            return WarnLevel::Caution;
        }
    }
    return raw;
}

void WarningManager::evaluate(const Snapshot& snap, bool obdConnected)
{
    state_.obdConnected = obdConnected;
    state_.anyStale = false;
    state_.anyCaution = false;
    state_.anyCritical = false;
    for (size_t i = 0; i < kChannelCount; ++i) {
        state_.level[i] = WarnLevel::Normal;
    }

    for (size_t i = 0; i < count_; ++i) {
        const WarningRule& r = rules_[i];
        const size_t idx = static_cast<size_t>(r.channel);
        const Channel& c = snap.channel(r.channel);

        if (!c.everValid) {
            continue; // no data yet — not a warning, just unknown
        }
        if (!c.isFresh(snap.nowMs, staleAfterMs_)) {
            state_.level[idx] = WarnLevel::Stale;
            prev_[idx] = WarnLevel::Stale;
            state_.anyStale = true;
            continue;
        }

        const WarnLevel lvl = classify(r, c.value, prev_[idx]);
        state_.level[idx] = lvl;
        prev_[idx] = lvl;
        if (lvl == WarnLevel::Caution) state_.anyCaution = true;
        if (lvl == WarnLevel::Critical) state_.anyCritical = true;
    }
}

} // namespace obd
