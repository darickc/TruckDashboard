#include "Derived.h"

namespace obd::derived {

void update(VehicleData& data, uint32_t now, const Config& cfg)
{
    const Snapshot s = data.snapshot(now);

    if (s.isFresh(ChannelId::EotF, cfg.maxInputAgeMs) &&
        s.isFresh(ChannelId::EctF, cfg.maxInputAgeMs)) {
        data.set(ChannelId::EctEotDeltaF,
                 s.value(ChannelId::EotF) - s.value(ChannelId::EctF), now);
    }

    if (s.isFresh(ChannelId::MapPsi, cfg.maxInputAgeMs) &&
        s.isFresh(ChannelId::BaroPsi, cfg.maxInputAgeMs)) {
        data.set(ChannelId::BoostPsi,
                 s.value(ChannelId::MapPsi) - s.value(ChannelId::BaroPsi), now);
    }
}

} // namespace obd::derived
