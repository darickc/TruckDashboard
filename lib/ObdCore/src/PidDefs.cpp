#include "PidDefs.h"

#include <cstring>

namespace obd {

// ---------------------------------------------------------------------------
// Channel metadata
// ---------------------------------------------------------------------------
namespace {

struct ChannelMeta {
    const char* name;
    const char* shortName;
    Unit unit;
};

// Order must match ChannelId.
constexpr ChannelMeta kChannelMeta[kChannelCount] = {
    {"Engine RPM", "RPM", Unit::Rpm},
    {"Vehicle Speed", "SPEED", Unit::Mph},
    {"Engine Coolant Temp", "ECT", Unit::Fahrenheit},
    {"Engine Oil Temp", "EOT", Unit::Fahrenheit},
    {"ECT/EOT Delta", "DELTA", Unit::Fahrenheit},
    {"FICM Main Voltage", "FICM", Unit::Volts},
    {"Injection Control Pressure", "ICP", Unit::Psi},
    {"IPR Duty Cycle", "IPR", Unit::Percent},
    {"VGT Duty Cycle", "VGT", Unit::Percent},
    {"Manifold Absolute Pressure", "MAP", Unit::Psi},
    {"Boost", "BOOST", Unit::Psi},
    {"Exhaust Back Pressure", "EBP", Unit::Psi},
    {"Transmission Temp", "TRANS", Unit::Fahrenheit},
    {"Transmission Gear", "GEAR", Unit::Gear},
    {"Battery Voltage", "BATT", Unit::Volts},
    {"Barometric Pressure", "BARO", Unit::Psi},
    {"Engine Load", "LOAD", Unit::Percent},
};

} // namespace

const char* channelName(ChannelId id)
{
    return kChannelMeta[static_cast<size_t>(id)].name;
}

const char* channelShortName(ChannelId id)
{
    return kChannelMeta[static_cast<size_t>(id)].shortName;
}

Unit channelUnit(ChannelId id)
{
    return kChannelMeta[static_cast<size_t>(id)].unit;
}

const char* unitSuffix(Unit u)
{
    switch (u) {
    case Unit::Rpm: return "rpm";
    case Unit::Celsius: return "C";
    case Unit::Fahrenheit: return "F";
    case Unit::Kpa: return "kPa";
    case Unit::Psi: return "PSI";
    case Unit::Kmh: return "km/h";
    case Unit::Mph: return "MPH";
    case Unit::Volts: return "V";
    case Unit::Percent: return "%";
    case Unit::Gear: return "";
    case Unit::Count: return "";
    case Unit::Microseconds: return "us";
    case Unit::MgPerStroke: return "mg";
    case Unit::Gph: return "GPH";
    case Unit::Degrees: return "deg";
    case Unit::Gforce: return "g";
    case Unit::None: return "";
    }
    return "";
}

// ---------------------------------------------------------------------------
// Module / header abstraction.
//
// DO NOT fill in Pcm/Tcm/Abs headers by guessing. Torque's symbolic names do
// not identify the OBDLink ATSH value; the real per-module CAN request IDs
// must be verified on the truck first (see docs/FORD_6_0_PIDS.md for the
// verification procedure). A nullptr header makes ElmClient refuse the PID.
// ---------------------------------------------------------------------------
namespace {

constexpr size_t kModuleCount = static_cast<size_t>(ObdModule::HdrC410F1) + 1;

struct AddressingOverride {
    bool active = false;
    char txHeader[12] = {0};
    char rxFilter[12] = {0};
    bool hasFilter = false;
};

AddressingOverride g_overrides[kModuleCount];

} // namespace

bool setModuleAddressingOverride(ObdModule m, const char* txHeader, const char* rxFilter)
{
    const size_t i = static_cast<size_t>(m);
    if (i >= kModuleCount || txHeader == nullptr) {
        return false;
    }
    AddressingOverride o;
    if (std::strlen(txHeader) >= sizeof(o.txHeader)) {
        return false;
    }
    std::strcpy(o.txHeader, txHeader);
    if (rxFilter != nullptr && rxFilter[0] != '\0') {
        if (std::strlen(rxFilter) >= sizeof(o.rxFilter)) {
            return false;
        }
        std::strcpy(o.rxFilter, rxFilter);
        o.hasFilter = true;
    }
    o.active = true;
    g_overrides[i] = o;
    return true;
}

void clearModuleAddressingOverrides()
{
    for (size_t i = 0; i < kModuleCount; ++i) {
        g_overrides[i] = AddressingOverride{};
    }
}

bool hasModuleAddressingOverride(ObdModule m)
{
    const size_t i = static_cast<size_t>(m);
    return i < kModuleCount && g_overrides[i].active;
}

ObdAddressing moduleAddressing(ObdModule m)
{
    const size_t i = static_cast<size_t>(m);
    if (i < kModuleCount && g_overrides[i].active) {
        const AddressingOverride& o = g_overrides[i];
        return {o.txHeader, o.hasFilter ? o.rxFilter : nullptr};
    }
    switch (m) {
    // ISO 15765-4 functional request (also the ELM327 CAN default). No receive
    // filter: by definition every ECU on the bus may answer.
    case ObdModule::Auto: return {"7DF", nullptr};
    case ObdModule::Pcm: return {nullptr, nullptr};  // TODO: verify on truck (likely 7E0/7E8)
    case ObdModule::Tcm: return {nullptr, nullptr};  // TODO: verify on truck
    case ObdModule::Abs: return {nullptr, nullptr};  // TODO: verify on truck
    case ObdModule::Hdr726: return {"726", nullptr};       // literal from Torque export (TPMS rows)
    case ObdModule::HdrC410F1: return {"C410F1", nullptr}; // literal from Torque export (KWP-style)
    }
    return {nullptr, nullptr};
}

bool isFunctionalHeader(const char* header)
{
    return header != nullptr && std::strcmp(header, "7DF") == 0;
}

const char* moduleName(ObdModule m)
{
    switch (m) {
    case ObdModule::Auto: return "Auto";
    case ObdModule::Pcm: return "PCM";
    case ObdModule::Tcm: return "TCM";
    case ObdModule::Abs: return "ABS";
    case ObdModule::Hdr726: return "726";
    case ObdModule::HdrC410F1: return "C410F1";
    }
    return "?";
}

// ---------------------------------------------------------------------------
// The PID table.
//
// SAE Mode 01 rows are hand-written with published J1979 formulas (verified).
// Service 0x22 rows were generated by scripts/gen_pids.py from the Torque Pro
// export (exportedPIDs.csv) and hand-reviewed. They stay verified=false until
// each is confirmed against the truck (enable raw logging, compare with a
// known-good reading — procedure in docs/FORD_6_0_PIDS.md).
// ---------------------------------------------------------------------------
const PidDefinition kPidTable[] = {
    // ---- Generic SAE J1979 Mode 01 (verified formulas) ----

    // Engine RPM: 01 0C, ((A*256)+B)/4 rpm
    {PidKey::RpmSae, ChannelId::Rpm, "Engine RPM", "RPM",
     0x01, 0x000C, ObdModule::Auto, /*resp=*/0, /*count=*/0,
     {0, 2, false, 0.25f, 0.0f},
     nullptr, Unit::Rpm, 100, 0, 500, 2, true},

    // Vehicle speed: 01 0D, A km/h
    {PidKey::SpeedSae, ChannelId::SpeedMph, "Vehicle Speed", "SPEED",
     0x01, 0x000D, ObdModule::Auto, /*resp=*/0, /*count=*/0,
     {0, 1, false, 1.0f, 0.0f},
     nullptr, Unit::Kmh, 200, 1, 500, 2, true},

    // Engine coolant temp: 01 05, A-40 °C
    {PidKey::EctSae, ChannelId::EctF, "Engine Coolant Temp", "ECT",
     0x01, 0x0005, ObdModule::Auto, /*resp=*/0, /*count=*/0,
     {0, 1, false, 1.0f, -40.0f},
     nullptr, Unit::Celsius, 500, 3, 500, 2, true},

    // Barometric pressure: 01 33, A kPa (input for derived boost = MAP - baro)
    {PidKey::BaroSae, ChannelId::BaroPsi, "Barometric Pressure", "BARO",
     0x01, 0x0033, ObdModule::Auto, /*resp=*/0, /*count=*/0,
     {0, 1, false, 1.0f, 0.0f},
     nullptr, Unit::Kpa, 5000, 5, 500, 2, true},

    // Calculated engine load: 01 04, A*100/255 %
    {PidKey::LoadSae, ChannelId::EngineLoadPct, "Engine Load", "LOAD",
     0x01, 0x0004, ObdModule::Auto, /*resp=*/0, /*count=*/0,
     {0, 1, false, 0.392156863f, 0.0f},
     nullptr, Unit::Percent, 500, 4, 500, 2, true},

    // ---- Ford enhanced (service 0x22) — generated by scripts/gen_pids.py ----
    // ---- from exportedPIDs.csv (Torque Pro export), hand-reviewed.       ----

    // [FORD]Battery Voltage — Torque: 0x221172 "A/16" [V] hdr=Auto
    {PidKey::BatteryVoltage, ChannelId::BatteryV, "Battery Voltage", "VBatt",
     0x22, 0x1172, ObdModule::Auto, /*resp=*/0, /*count=*/0,
     {0, 1, false, 0.0625f, 0.0f},
     nullptr, Unit::Volts, 1000, 4, 500, 2, false},

    // [FORD]Engine Oil Temp — Torque: 0x221310 "(((A*256)+B)/100)-40" [°C] hdr=Auto
    {PidKey::Eot, ChannelId::EotF, "Engine Oil Temp", "EOT",
     0x22, 0x1310, ObdModule::Auto, /*resp=*/0, /*count=*/0,
     {0, 2, false, 0.01f, -40.0f},
     nullptr, Unit::Celsius, 500, 3, 500, 2, false},

    // [FORD]Exhaust Back Pressure — Torque: 0x221445 "(((A*256)+B)*0.03625)" [psi] hdr=Auto
    {PidKey::Ebp, ChannelId::EbpPsi, "Exhaust Back Pressure", "EBP",
     0x22, 0x1445, ObdModule::Auto, /*resp=*/0, /*count=*/0,
     {0, 2, false, 0.03625f, 0.0f},
     nullptr, Unit::Psi, 200, 2, 500, 2, false},

    // [FORD]FICM Main Power — Torque: 0x2209d0 "((A*256)+B)*(100/256)/100" [Volts] hdr=Auto
    {PidKey::FicmMainPower, ChannelId::FicmMainV, "FICM Main Power", "FMP",
     0x22, 0x09D0, ObdModule::Auto, /*resp=*/0, /*count=*/0,
     {0, 2, false, 0.00390625f, 0.0f},
     nullptr, Unit::Volts, 400, 3, 500, 2, false},

    // [FORD]Injection Control Pressure — Torque: 0x221446 "((A*256)+B)*(57/100)" [psi] hdr=Auto
    {PidKey::Icp, ChannelId::IcpPsi, "Injection Control Pressure", "HPOP",
     0x22, 0x1446, ObdModule::Auto, /*resp=*/0, /*count=*/0,
     {0, 2, false, 0.57f, 0.0f},
     nullptr, Unit::Psi, 100, 1, 500, 2, false},

    // [FORD]Injector Pressure Regulator Duty Cycle — Torque: 0x221434 "(A*13.53)/35" [%] hdr=Auto
    {PidKey::IprDuty, ChannelId::IprPct, "IPR Duty Cycle", "IPR",
     0x22, 0x1434, ObdModule::Auto, /*resp=*/0, /*count=*/0,
     {0, 1, false, 0.386571429f, 0.0f},
     nullptr, Unit::Percent, 150, 2, 500, 2, false},

    // [FORD]MAP (Ford specific) — Torque: 0x221440 "(((A*256)+B)*0.03625)" [psi] hdr=Auto
    // NOTE: absolute pressure. Boost = MAP - baro is computed in Derived.cpp
    // (the Torque "Boost (Ford specific)" row with BARO() is intentionally
    // NOT in this table).
    {PidKey::Map, ChannelId::MapPsi, "MAP (Ford specific)", "MAP",
     0x22, 0x1440, ObdModule::Auto, /*resp=*/0, /*count=*/0,
     {0, 2, false, 0.03625f, 0.0f},
     nullptr, Unit::Psi, 100, 0, 500, 2, false},

    // [FORD]Transmission Fluid Temp (Method 1) — Torque: 0x221674 "((A*256)+B)/8" [°F] hdr=Auto
    {PidKey::TransTemp1, ChannelId::TransTempF, "Trans Fluid Temp (Method 1)", "TransFl",
     0x22, 0x1674, ObdModule::Auto, /*resp=*/0, /*count=*/0,
     {0, 2, false, 0.125f, 0.0f},
     nullptr, Unit::Fahrenheit, 500, 3, 500, 2, false},

    // [FORD]Transmission Fluid Temp (Method 2) — Torque: 0x221674 "((A*256)+B)/8" [°F] hdr=TCM
    // Module header UNVERIFIED — will be refused until ObdModule::Tcm gets a
    // real ATSH value verified on the truck.
    {PidKey::TransTemp2, ChannelId::TransTempF, "Trans Fluid Temp (Method 2)", "TransFl",
     0x22, 0x1674, ObdModule::Tcm, /*resp=*/0, /*count=*/0,
     {0, 2, false, 0.125f, 0.0f},
     nullptr, Unit::Fahrenheit, 500, 3, 500, 2, false},

    // [FORD]Transmission Fluid Temp (Method 3) — Torque: 0x2211bd
    // "(((A*256)+B)*-0.0036)+212.98" [°F] hdr=C410F1 (KWP-style header —
    // likely N/A on this CAN truck; kept verbatim from the export).
    // NOTE: Torque equation says signed(A); decoder treats raw as signed 16-bit.
    {PidKey::TransTemp3, ChannelId::TransTempF, "Trans Fluid Temp (Method 3)", "TransFl",
     0x22, 0x11BD, ObdModule::HdrC410F1, /*resp=*/0, /*count=*/0,
     {0, 2, true, -0.0036f, 212.98f},
     nullptr, Unit::Fahrenheit, 500, 3, 500, 2, false},

    // [FORD]Transmission Gear — Torque: 0x2211b3 "A/2" [Gear] hdr=Auto
    {PidKey::Gear1, ChannelId::GearNum, "Transmission Gear", "Gear",
     0x22, 0x11B3, ObdModule::Auto, /*resp=*/0, /*count=*/0,
     {0, 1, false, 0.5f, 0.0f},
     nullptr, Unit::Gear, 500, 4, 500, 2, false},

    // [FORD]Transmission Gear (Method 2) — Torque: 0x2211b3 "A/2" [Gear] hdr=TCM
    {PidKey::Gear2, ChannelId::GearNum, "Transmission Gear (Method 2)", "Gear",
     0x22, 0x11B3, ObdModule::Tcm, /*resp=*/0, /*count=*/0,
     {0, 1, false, 0.5f, 0.0f},
     nullptr, Unit::Gear, 500, 4, 500, 2, false},

    // [FORD]VGT Duty Cycle — Torque: 0x22096d "((A*256)+B)*(100/32767)" [%] hdr=Auto
    {PidKey::VgtDuty, ChannelId::VgtPct, "VGT Duty Cycle", "VGT",
     0x22, 0x096D, ObdModule::Auto, /*resp=*/0, /*count=*/0,
     {0, 2, false, 0.00305185095f, 0.0f},
     nullptr, Unit::Percent, 150, 2, 500, 2, false},
};

const size_t kPidTableSize = sizeof(kPidTable) / sizeof(kPidTable[0]);

const PidDefinition* findPid(PidKey key)
{
    for (size_t i = 0; i < kPidTableSize; ++i) {
        if (kPidTable[i].key == key) {
            return &kPidTable[i];
        }
    }
    return nullptr;
}

// ---------------------------------------------------------------------------
// Remaining Torque export rows (reference — generated by scripts/gen_pids.py;
// add to the table + PidKey enum when needed):
//
//   [FORD]Accelerator Pedal Position: svc 0x22 pid 0x09D4 hdr=Auto decode{0,1,U,0.5,0} [%]
//   [FORD]Cyl 1-8 Misfire counts:     svc 0x22 pid 0x160E..0x1615 hdr=Auto decode{0,2,U,1,0} [Count]
//   [FORD]Cylinder head temperature:  svc 0x22 pid 0x1624 hdr=Auto decode{0,2,U,1.999,32} [°F]
//   [FORD]Cylinder head temp (alt):   svc 0x22 pid 0x1685 hdr=Auto decode{0,2,U,0.281,0} [°F]
//   [FORD]Fan Speed Sensor:           svc 0x22 pid 0x099F hdr=Auto decode{0,2,U,0.25,0} [rpm]
//   [FORD]FICM Logic Power:           svc 0x22 pid 0x09CF hdr=Auto decode{0,2,U,0.00390625,0} [V]
//   [FORD]FICM Vehicle Power:         svc 0x22 pid 0x09CE hdr=Auto decode{0,2,U,0.00390625,0} [V]
//   [FORD]Fuel Injector Pulse Width:  svc 0x22 pid 0x1410 hdr=Auto decode{0,2,U,8,0} [µs]
//   [FORD]Fuel Level:                 svc 0x22 pid 0x16C1 hdr=Auto decode{0,2,U,0.003048780,0} [%]
//   [FORD]Fuel pump duty cycle:       svc 0x22 pid 0x1672 hdr=Auto decode{0,1,U,0.78125,0} [%]
//   [FORD]Fuel tank pressure:         svc 0x22 pid 0x1639 hdr=Auto decode{0,2,U,0.1449,0} [PSI]
//   [FORD]IAT2 (Method 1):            svc 0x22 pid 0x16A8 hdr=Auto decode{0,2,U,0.555555,-17.7777} [°C]
//   [FORD]IAT2 (Method 2):            svc 0x22 pid 0x03CA hdr=Auto decode{0,1,U,1,-40} [°C]
//   [FORD]Injector timing BTDC:       svc 0x22 pid 0x09CC hdr=Auto decode{0,2,U,0.015625,0} [deg]
//   [FORD]Knock Sensor:               svc 0x22 pid 0x0404 hdr=Auto decode{0,1,U,1,0} [Count]
//   [FORD]Mass Fuel Desired:          svc 0x22 pid 0x1412 hdr=Auto decode{0,2,U,0.0625,0} [mg/stroke]
//   [FORD]Steering wheel angle:       svc 0x22 pid 0x3201 hdr=ABS decode{0,1,U,6.25,-800} [°]  (hdr UNVERIFIED)
//   [FORD]Throttle Pos (Actual):      svc 0x22 pid 0x093C hdr=Auto decode{0,2,U,0.012207,0} [°]
//   [FORD]Throttle Pos (Desired):     svc 0x22 pid 0x091A hdr=Auto decode{0,2,U,0.012207,0} [°]
//   [FORD]Torque converter slip:      svc 0x22 pid 0x11B8 hdr=Auto decode{0,2,U,0.6103,0} [rpm]
//   [FORD]Torque into converter:      svc 0x22 pid 0x09CB hdr=Auto decode{0,2,U,1,0} [Ft-Lb]
//   [FORD]Total misfires:             svc 0x22 pid 0x1616 hdr=Auto decode{0,2,U,1,0} [Count]
//   [FORD]Transmission Temp (alt):    svc 0x22 pid 0x1E1C hdr=Auto decode{0,2,S,0.1125,32} [°F]
//   [FORD]Volume Fuel Desired:        svc 0x22 pid 0x1411 hdr=Auto decode{0,2,U,0.00047551,0} [GPH]
//   [FORD]ABS lateral accel:          svc 0x22 pid 0x3A51 hdr=ABS decode{0,2,U,0.02,0} [g]      (hdr UNVERIFIED)
//   [FORD]ABS wheel speeds 1-4:       svc 0x22 pid 0x3987 hdr=ABS decode{0..3,1,U,1,0} [km/h]   (hdr UNVERIFIED)
//   [FORD]Tyre pressures LF/RF/LR/RR: svc 0x22 pid 0x2813/14/15/16 hdr=726 decode{0,2,U,0.048333,1.063333} [psi]
//   [FORD]Coolant temp (from TCM):    svc 0x01 pid 0x05 hdr=TCM decode{0,1,U,1,-40} [°C]        (hdr UNVERIFIED)
// ---------------------------------------------------------------------------

} // namespace obd
