#pragma once
//
// Central vehicle data model: the latest known value of every channel with a
// per-channel timestamp and validity, so stale data is never mistaken for
// fresh data.
//
// Thread safety: the firmware installs FreeRTOS mutex lock hooks (see
// main.cpp); unit tests run single-threaded with no hooks. The OBD task holds
// the lock for a few stores; the UI takes it once per frame to copy a
// Snapshot and then works lock-free on the copy.

#include <cstdint>

#include "PidDefs.h"
#include "TimeSource.h"

namespace obd {

struct Channel {
    float value = 0.0f;
    uint32_t updatedAtMs = 0;
    bool everValid = false;   ///< at least one good sample since boot
    uint16_t errorCount = 0;  ///< decode failures / NO DATA / timeouts

    bool isFresh(uint32_t now, uint32_t maxAgeMs) const
    {
        return everValid && timeSince(now, updatedAtMs) <= maxAgeMs;
    }
};

/// Value copy of the whole model, safe to use without locking.
struct Snapshot {
    Channel ch[kChannelCount];
    uint32_t nowMs = 0;

    const Channel& channel(ChannelId id) const { return ch[static_cast<size_t>(id)]; }
    float value(ChannelId id) const { return channel(id).value; }
    bool isFresh(ChannelId id, uint32_t maxAgeMs) const
    {
        return channel(id).isFresh(nowMs, maxAgeMs);
    }
};

class VehicleData {
public:
    using LockFn = void (*)(void* ctx);

    /// Install lock/unlock hooks (FreeRTOS mutex in firmware, none in tests).
    void setLockHooks(LockFn lock, LockFn unlock, void* ctx);

    void set(ChannelId id, float value, uint32_t now);
    void markError(ChannelId id);
    Snapshot snapshot(uint32_t now);

private:
    void lock() { if (lock_ != nullptr) lock_(lockCtx_); }
    void unlock() { if (unlock_ != nullptr) unlock_(lockCtx_); }

    Channel channels_[kChannelCount];
    LockFn lock_ = nullptr;
    LockFn unlock_ = nullptr;
    void* lockCtx_ = nullptr;
};

} // namespace obd
