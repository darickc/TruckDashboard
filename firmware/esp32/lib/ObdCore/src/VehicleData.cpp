#include "VehicleData.h"

namespace obd {

void VehicleData::setLockHooks(LockFn lock, LockFn unlock, void* ctx)
{
    lock_ = lock;
    unlock_ = unlock;
    lockCtx_ = ctx;
}

void VehicleData::set(ChannelId id, float value, uint32_t now)
{
    lock();
    Channel& c = channels_[static_cast<size_t>(id)];
    c.value = value;
    c.updatedAtMs = now;
    c.everValid = true;
    unlock();
}

void VehicleData::markError(ChannelId id)
{
    lock();
    Channel& c = channels_[static_cast<size_t>(id)];
    if (c.errorCount < UINT16_MAX) {
        ++c.errorCount;
    }
    unlock();
}

Snapshot VehicleData::snapshot(uint32_t now)
{
    Snapshot s;
    lock();
    for (size_t i = 0; i < kChannelCount; ++i) {
        s.ch[i] = channels_[i];
    }
    unlock();
    s.nowMs = now;
    return s;
}

} // namespace obd
