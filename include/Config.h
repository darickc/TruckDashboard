#pragma once
//
// Central configuration — everything a user should ever need to tune lives
// here. See README.md "Configuration" for details.

#include "Log.h"
#include "PidDefs.h"
#include "Warnings.h"

namespace config {

// ---------------------------------------------------------------------------
// Serial / logging
// ---------------------------------------------------------------------------
inline constexpr uint32_t kSerialBaud = 115200;

/// Runtime log ceiling (compile-time floor is -DTD_LOG_LEVEL in platformio.ini).
///
/// Info, not Debug, because the serial port is shared with the console: at ~11
/// requests/s the Debug lines alone (two state transitions and one decoded value
/// per request) scroll anything you type off the screen before you can read it.
/// Raise it at runtime with `log level 4` when you want them.
inline constexpr TdLogLevel kRuntimeLogLevel = TdLogLevel::Info;

/// Mirror every raw ELM TX/RX/RSP line at INFO level.
///
/// Off by default for the same reason — it is another ~5 lines per request. The
/// console's `probe` already prints the raw bytes of every responder, so this is
/// rarely needed; `log raw on` turns it on for a single experiment without a
/// reflash. Verbose logging also costs real polling throughput.
inline constexpr bool kLogRawObdTraffic = false;

// ---------------------------------------------------------------------------
// Bluetooth (OBDLink MX+)
// ---------------------------------------------------------------------------
/// Name this ESP32 advertises.
inline constexpr char kBtLocalName[] = "TruckDash";

/// Discovery fallback ONLY — used when kUseObdMac is false. BluetoothSerial
/// matches this against the advertised name exactly, and MX+ units advertise
/// with a serial-number suffix, so the generic "OBDLink MX+" will not match.
inline constexpr char kObdDeviceName[] = "OBDLink MX+ 15326";

/// Connecting by MAC skips the (slow, ~10-30 s) discovery scan. After the
/// first successful connect-by-name the firmware logs the adapter's MAC —
/// paste it here and set kUseObdMac = true.
/// Set false to fall back to discovery by kObdDeviceName (e.g. if the
/// adapter is ever replaced).
/// MAC below verified on the truck 2026-08-09.
inline constexpr bool kUseObdMac = true;
inline constexpr uint8_t kObdMac[6] = {0x00, 0x04, 0x3E, 0x85, 0xEA, 0xFC};

/// SPP pairing PIN (OBDLink MX+ default is "1234").
inline constexpr char kObdPin[] = "1234";

/// Reconnect backoff: doubles from min to max on repeated failures.
inline constexpr uint32_t kReconnectMinMs = 2000;
inline constexpr uint32_t kReconnectMaxMs = 30000;

// ---------------------------------------------------------------------------
// ELM/OBDLink initialization sequence (sent after ATZ, in order).
//   ATE0  echo off        ATL0  linefeeds off     ATS0  spaces off
//   ATH1  headers ON (the parser expects CAN IDs + ISO-TP PCI bytes)
//   ATAT1 adaptive timing ATSP0 protocol auto-detect
// The 2005+ 6.0L Super Duty is expected to land on ISO 15765-4 CAN
// (11-bit/500k = ATSP6); ATSP0 lets the adapter confirm that rather than
// assuming. Pin it to "ATSP6" here once verified on the truck.
// ---------------------------------------------------------------------------
inline constexpr const char* kElmInitCommands[] = {
    "ATE0", "ATL0", "ATS0", "ATH1", "ATAT1", "ATSP0",
};
inline constexpr size_t kElmInitCommandCount =
    sizeof(kElmInitCommands) / sizeof(kElmInitCommands[0]);

// ---------------------------------------------------------------------------
// Enabled PIDs.
//
// MILESTONE 1: generic engine RPM only (plus barometric pressure, the input
// for derived boost). Enable Ford PIDs ONE AT A TIME while watching raw
// traffic (kLogRawObdTraffic) and verifying readings against a known-good
// tool — see docs/FORD_6_0_PIDS.md. Poll rates/priorities live in the PID
// table (lib/ObdCore/src/PidDefs.cpp).
// ---------------------------------------------------------------------------
inline constexpr obd::PidKey kEnabledPids[] = {
    obd::PidKey::RpmSae,
    obd::PidKey::BaroSae,
    // --- verified generic, enable when wanted ---
    // obd::PidKey::SpeedSae,
    // obd::PidKey::EctSae,
    // obd::PidKey::LoadSae,
    // --- Ford enhanced (from Torque export) — verify on truck one by one ---
    // obd::PidKey::Eot,
    // obd::PidKey::FicmMainPower,
    // obd::PidKey::Icp,
    // obd::PidKey::IprDuty,
    // obd::PidKey::VgtDuty,
    // obd::PidKey::Map,
    // obd::PidKey::Ebp,
    // obd::PidKey::TransTemp1,
    // obd::PidKey::Gear1,
    // obd::PidKey::BatteryVoltage,
};
inline constexpr size_t kEnabledPidCount =
    sizeof(kEnabledPids) / sizeof(kEnabledPids[0]);

/// Measured adapter throughput, requests/s — the budget the poll intervals in
/// PidDefs.cpp are spent from. Derived from the on-truck log: a 010C request
/// written at t=89607 ms saw its '>' prompt at t=89703 ms, i.e. ~96 ms per
/// round trip on a functional (7DF) request that two ECUs answer.
/// Re-measure with the console `stats` command after any addressing change and
/// update this — the scheduler warns when the enabled set over-promises.
inline constexpr float kMeasuredRequestsPerSec = 10.0f;

// ---------------------------------------------------------------------------
// Freshness / display
// ---------------------------------------------------------------------------
/// A value older than this is treated as stale (shown flagged, warnings
/// switch to Stale instead of judging old data).
inline constexpr uint32_t kStaleAfterMs = 3000;

/// Serial/debug display refresh period.
inline constexpr uint32_t kDisplayIntervalMs = 1000;

/// UI evaluation tick (derived values + warnings).
inline constexpr uint32_t kUiTickMs = 250;

// ---------------------------------------------------------------------------
// Warning thresholds.
//
// *** EXAMPLE DEFAULTS ONLY — VERIFY BEFORE TRUSTING. ***
// These are commonly cited 6.0L community numbers, NOT engineering limits.
// Review every threshold for your truck, tune, and treat warnings as advice.
// NaN (obd::kNoBound) disables a bound.
//   {channel, lowCritical, lowCaution, highCaution, highCritical, hysteresis}
// ---------------------------------------------------------------------------
inline const obd::WarningRule kWarningRules[] = {
    // ECT: EXAMPLE — thermostat runs ~192-203 F; sustained >230 F is trouble.
    {obd::ChannelId::EctF, obd::kNoBound, obd::kNoBound, 225.0f, 240.0f, 3.0f},
    // EOT: EXAMPLE.
    {obd::ChannelId::EotF, obd::kNoBound, obd::kNoBound, 230.0f, 250.0f, 3.0f},
    // ECT/EOT delta: EXAMPLE — a large delta suggests a clogging oil cooler.
    {obd::ChannelId::EctEotDeltaF, obd::kNoBound, obd::kNoBound, 15.0f, 25.0f, 2.0f},
    // FICM main power: EXAMPLE — healthy is ~48 V; sagging FICM kills injectors.
    {obd::ChannelId::FicmMainV, 44.0f, 46.0f, obd::kNoBound, obd::kNoBound, 0.5f},
    // Transmission temp: EXAMPLE.
    {obd::ChannelId::TransTempF, obd::kNoBound, obd::kNoBound, 220.0f, 240.0f, 3.0f},
    // Battery/charging voltage: EXAMPLE — low and high are both bad.
    {obd::ChannelId::BatteryV, 11.8f, 12.4f, 15.0f, 15.5f, 0.2f},
};
inline constexpr size_t kWarningRuleCount =
    sizeof(kWarningRules) / sizeof(kWarningRules[0]);

} // namespace config
