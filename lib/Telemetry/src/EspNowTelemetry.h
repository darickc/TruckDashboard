#pragma once
//
// FUTURE: ESP-NOW broadcast of the vehicle data model to additional gauge
// units. Only the wire format and a no-op stub exist today — the main gauge
// must never depend on ESP-NOW to operate.
//
// IMPORTANT COEXISTENCE CAVEAT (evaluate before implementing): ESP-NOW needs
// the Wi-Fi radio active while Bluetooth Classic SPP is streaming; on the
// original ESP32 the two share one 2.4 GHz radio and coexistence arbitration
// throttles both. Before building this out, measure whether OBD polling
// throughput stays acceptable with Wi-Fi up — otherwise secondary gauges may
// need their own MX+-facing design or a wired link.

#include <cstdint>
#include <cstring>

#include "VehicleData.h"

namespace telemetry {

constexpr uint8_t kPacketVersion = 1;

/// Fixed-size, versioned snapshot of every channel. ~150 bytes — fits well
/// inside the 250-byte ESP-NOW payload limit.
struct __attribute__((packed)) Packet {
    uint8_t version;
    uint8_t reserved[3];
    uint32_t seq;
    uint32_t uptimeMs;
    uint32_t validMask;                   ///< bit i = ChannelId i has ever been valid
    float value[obd::kChannelCount];
    uint16_t ageMs[obd::kChannelCount];   ///< saturated at 65535
};

static_assert(obd::kChannelCount <= 32, "validMask is 32 bits");
static_assert(sizeof(Packet) <= 250, "ESP-NOW payload limit is 250 bytes");

inline Packet buildPacket(const obd::Snapshot& snap, uint32_t seq)
{
    Packet p{};
    p.version = kPacketVersion;
    p.seq = seq;
    p.uptimeMs = snap.nowMs;
    for (size_t i = 0; i < obd::kChannelCount; ++i) {
        const obd::Channel& c = snap.ch[i];
        p.value[i] = c.value;
        if (c.everValid) {
            p.validMask |= (1u << i);
            const uint32_t age = obd::timeSince(snap.nowMs, c.updatedAtMs);
            p.ageMs[i] = age > 65535u ? 65535u : static_cast<uint16_t>(age);
        } else {
            p.ageMs[i] = 65535u;
        }
    }
    return p;
}

/// No-op stub. A real implementation will bring up esp_now, manage peers,
/// and broadcast packets — after the coexistence caveat above is evaluated.
class EspNowTelemetry {
public:
    bool begin() { return false; } // not implemented
    void broadcast(const Packet&) {}
};

} // namespace telemetry
