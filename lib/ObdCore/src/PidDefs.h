#pragma once
//
// Data-driven PID definitions.
//
// Two families of request:
//   * Generic SAE J1979 Mode 01 (service 0x01, 1-byte PID) — RPM, speed, ECT,
//     baro. Formulas are the published SAE ones and are marked verified.
//   * Ford enhanced diagnostics (service 0x22, 2-byte DID) — everything 6.0L
//     specific. DIDs and scaling come from the user's Torque Pro export
//     (exportedPIDs.csv); they are trusted as "definition verified from
//     Torque" but each remains verified=false until confirmed on the truck.
//     See docs/FORD_6_0_PIDS.md and docs/TORQUE_PID_IMPORT.md.
//
// IMPORTANT: never invent Ford DIDs, headers, or scaling. Unverified module
// addressing is represented as a nullptr ATSH header, which ElmClient refuses
// to use (logged, skipped) rather than guessing.

#include <cstddef>
#include <cstdint>

#include "Units.h"

namespace obd {

// ---------------------------------------------------------------------------
// Channels: the slots of the central vehicle data model.
// ---------------------------------------------------------------------------
enum class ChannelId : uint8_t {
    Rpm,
    SpeedMph,
    EctF,
    EotF,
    EctEotDeltaF, // derived: EOT - ECT
    FicmMainV,
    IcpPsi,
    IprPct,
    VgtPct,
    MapPsi,
    BoostPsi,     // derived: MAP - barometric
    EbpPsi,
    TransTempF,
    GearNum,
    BatteryV,
    BaroPsi,
    EngineLoadPct,
    Count,
};

constexpr size_t kChannelCount = static_cast<size_t>(ChannelId::Count);

const char* channelName(ChannelId id);
const char* channelShortName(ChannelId id);
Unit channelUnit(ChannelId id);

// ---------------------------------------------------------------------------
// Module / header abstraction.
//
// Torque's Header column is symbolic ("Auto", "TCM", "ABS") or literal
// ("726", "C410F1"). Symbolic names do NOT tell us the OBDLink ATSH value —
// those map to nullptr (UNVERIFIED) until confirmed on the truck.
// "Auto" maps to 7DF, the ISO 15765-4 standard functional request ID that is
// also the ELM327 default header on CAN — this is SAE-standard, not guessed.
// ---------------------------------------------------------------------------
enum class ObdModule : uint8_t {
    Auto,      ///< adapter default functional addressing (ATSH 7DF)
    Pcm,       ///< TODO: verify physical PCM header on truck (likely 7E0/7E8)
    Tcm,       ///< TODO: verify TCM header on truck
    Abs,       ///< TODO: verify ABS module header on truck
    Hdr726,    ///< literal header "726" from Torque export
    HdrC410F1, ///< literal header "C410F1" from Torque export (KWP-style — likely N/A on CAN)
};

/// ATSH header string for a module, or nullptr when the real header is
/// unverified (ElmClient will refuse to send and log a warning).
const char* moduleAtshHeader(ObdModule m);
const char* moduleName(ObdModule m);

// ---------------------------------------------------------------------------
// PID identity & decode description.
// ---------------------------------------------------------------------------

/// Stable identity for every table row (Config.h enables PIDs by key).
/// Distinct from ChannelId because several alternate PIDs can feed one
/// channel (e.g. three transmission-temperature methods).
enum class PidKey : uint8_t {
    // Generic SAE Mode 01 — formulas verified (SAE J1979).
    RpmSae,
    SpeedSae,
    EctSae,
    BaroSae,
    LoadSae,
    // Ford enhanced (service 0x22) — from Torque export.
    Eot,
    FicmMainPower,
    Icp,
    IprDuty,
    VgtDuty,
    Map,
    Ebp,
    TransTemp1,     // 22 1674, Header=Auto
    TransTemp2,     // 22 1674, Header=TCM (module header UNVERIFIED)
    TransTemp3,     // 22 11BD, Header=C410F1 (KWP-style header — likely N/A)
    Gear1,          // 22 11B3, Header=Auto
    Gear2,          // 22 11B3, Header=TCM (module header UNVERIFIED)
    BatteryVoltage, // 22 1172
    Count,
};

/// Linear decode: value = raw * scale + bias, where raw is a big-endian
/// 1- or 2-byte field at byteOffset within the payload AFTER the positive-
/// response echo (41 xx / 62 xxxx) has been stripped.
struct LinearDecode {
    uint8_t byteOffset;
    uint8_t width;    ///< 1 or 2
    bool isSigned;    ///< interpret raw as two's complement
    float scale;
    float bias;
};

/// Optional custom decoder for non-linear formulas. Returns success.
using DecodeFn = bool (*)(const uint8_t* payload, size_t len, float& out);

struct PidDefinition {
    PidKey key;
    ChannelId channel;
    const char* name;
    const char* shortName;
    uint8_t service;   ///< 0x01 (SAE Mode 01) or 0x22 (Ford enhanced read-by-DID)
    uint16_t pid;      ///< 1-byte PID for service 01, 2-byte DID for service 22
    ObdModule module;
    LinearDecode decode;
    DecodeFn decodeFn; ///< nullptr => use `decode`
    Unit unit;         ///< unit the formula yields (converted to channel unit on store)
    uint16_t pollIntervalMs;
    uint8_t priority;  ///< 0 = highest; used when the bus is oversubscribed
    uint16_t timeoutMs;
    uint8_t maxRetries;
    bool verified;     ///< true only after confirmation against the real truck
};

extern const PidDefinition kPidTable[];
extern const size_t kPidTableSize;

const PidDefinition* findPid(PidKey key);

/// Payload length of the response echo for a service (bytes to skip before
/// decoder byteOffset applies): 2 for "41 xx", 3 for "62 xx xx".
constexpr size_t responseEchoLen(uint8_t service)
{
    return service == 0x22 ? 3u : 2u;
}

} // namespace obd
