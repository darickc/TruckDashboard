# TruckDashboard

Custom digital gauge firmware for a **2007 Ford F-250 6.0L Power Stroke**, running
entirely on **one ESP32-WROOM-32**:

```
OBDLink MX+  ──Bluetooth Classic (SPP)──►  ESP32-WROOM-32  ──►  round AMOLED gauge
 (OBD-II port)                              (this firmware)      (future; Serial today)
                                                 │
                                                 └──►  optional ESP-NOW to extra gauges (future)
```

The ESP32 connects to the OBDLink MX+ as a Bluetooth Classic SPP master, initializes
it as an ELM327/STN device, polls generic SAE and Ford enhanced (service `22`) PIDs
on a priority scheduler, maintains a central vehicle-data model with per-value
freshness, computes derived values (boost, ECT/EOT delta) and warnings, and renders
gauge pages — currently to USB Serial, later to a 1.75" round 466×466 AMOLED.

## Current status — Milestone 2 (tooling done, truck session next)

**Working now:**
- Builds for ESP32-WROOM-32 with PlatformIO (Arduino framework, C++17)
- Bluetooth Classic startup, connect to the MX+ by MAC (or name), auto-reconnect
  with exponential backoff
- Full ELM init (`ATZ`, `ATE0`, `ATL0`, `ATS0`, `ATH1`, `ATAT1`, `ATSP0` — configurable)
- Non-blocking request/response engine: `>`-prompt lifecycle, timeouts, retries,
  `NO DATA`/`STOPPED`/negative-response handling, ISO-TP reassembly, recovery ladder
- Verified generic PID polling: **engine RPM** (`01 0C`) decoded and printed
  (`RPM: 1726`) — plus baro (`01 33`) for future boost calculation
- **Responder recording**: two ECUs (7E8 and 7E9) answer every functional request
  on this truck, so every answer is kept with the CAN ID that sent it. Divergence
  is judged on *decoded* values, not bytes — at idle the two disagree in bytes on
  nearly every request but by only ~1 rpm in meaning
- **[Interactive serial console](docs/CONSOLE.md)**: `pids`, `on`/`off`,
  `probe <pid> [n]`, `raw`, `hdr`, `snap`, `stats`, `display` — verify a PID or
  try an ATSH candidate without a reflash. Input is echoed, the display pauses
  when you start typing, and write/clear/control services are refused unless
  `unsafe on` is typed
- Vehicle data model, PID scheduler with per-PID stats and a throughput-budget
  warning, warning manager, derived values, Serial "display",
  **137 host-side unit tests**

**Scaffolded, not yet verified on the truck:** all Ford enhanced PIDs (EOT, FICM,
ICP, IPR, VGT, MAP, EBP, trans temp, gear, battery) — definitions imported from a
Torque Pro export, disabled by default. The tooling to verify them now exists;
the session itself is next. See [docs/FORD_6_0_PIDS.md](docs/FORD_6_0_PIDS.md)
for the procedure and [docs/VERIFICATION_LOG.md](docs/VERIFICATION_LOG.md) for
where the evidence goes.

**Known:** the measured Bluetooth round trip is ~96 ms (~10 requests/s), not the
30–60 ms originally assumed. The PID table's poll intervals ask for far more than
that once the Ford PIDs are on; the scheduler degrades by priority and now says
so out loud. Rebalancing is a job for after the throughput experiments — see
[docs/OBD_PROTOCOL.md](docs/OBD_PROTOCOL.md#throughput-budget).

## Hardware

| Part | Notes |
|---|---|
| ESP32-WROOM-32 dev board (30-pin, USB-C, CP2102) | **Original ESP32, not S3** — Bluetooth Classic SPP is required and the S3 only has BLE |
| OBDLink MX+ | ELM327/STN-compatible, in the truck's OBD-II port |
| 1.75" round AMOLED ~466×466 | Future; controller not selected — display layer is abstracted |
| 2007 F-250 6.0L Power Stroke, auto trans | HS-CAN diagnostics expected (ISO 15765-4) |

## Architecture (short version)

Two FreeRTOS tasks; everything inside each task is non-blocking:

- **ObdTask** (core 1, prio 3) — Bluetooth connect (the one legitimately blocking
  call lives here), ELM state machine, PID scheduler, decode → `VehicleData`.
- **UI (loopTask)** — every 250 ms: snapshot → derived values → warnings → render.
  A Bluetooth stall can never freeze the display.

The only shared object is `VehicleData`, guarded by one mutex; the UI copies a
snapshot and works lock-free. The whole protocol stack (`lib/ObdCore`) has **zero
Arduino dependencies** and runs natively under unit tests.

Full details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/OBD_PROTOCOL.md](docs/OBD_PROTOCOL.md).

## Building and flashing

```bash
# Build firmware
pio run -e esp32dev

# Flash over USB (hold BOOT on stubborn boards)
pio run -e esp32dev -t upload

# Watch logs (115200 baud)
pio device monitor

# Run the host-side unit tests (no hardware needed)
pio test -e native
```

(If `pio` isn't on your PATH it lives at `~/.platformio/penv/bin/pio`.)

## Configuration

Everything tunable is in [include/Config.h](include/Config.h):

- **`kObdDeviceName`** — the adapter's Bluetooth name (default `"OBDLink MX+"`).
  Check yours; the visible name is not guaranteed.
- **`kObdMac` / `kUseObdMac`** — connecting by name requires a ~10-30 s discovery
  scan. After the first successful connection the firmware logs
  `connected to XX:XX:XX:XX:XX:XX — paste into Config.h`; do that and set
  `kUseObdMac = true` for ~3 s reconnects.
- **`kObdPin`** — SPP PIN, MX+ default `1234`.
- **`kEnabledPids`** — which PIDs poll (milestone 1: RPM + baro only).
- **`kElmInitCommands`** — adapter init sequence; pin `ATSP0` → `ATSP6` once the
  protocol is confirmed on the truck.
- **`kWarningRules`** — thresholds. **EXAMPLE values — verify before trusting.**
- **`kLogRawObdTraffic`** — mirror raw TX/RX at INFO for on-truck PID verification.
  Turn off for normal use; verbose logging costs polling throughput.
- Units: display units default to °F / PSI / MPH / V (per-channel in `PidDefs.cpp`).

## First bench test

1. Flash, open the monitor. Expect `Bluetooth Classic up as 'TruckDash' (master)`.
2. Turn the ignition on (adapter must be powered; wake it if it's asleep).
3. Watch: `connecting by name 'OBDLink MX+'` → `SPP link established` →
   `connected to <MAC>` → init chatter → `OBDLink connected` → `RPM: 0`
   (engine off) or live RPM.
4. Pull the adapter (or kill ignition): expect `SPP link closed` and automatic
   reconnect attempts with backoff; plug back in and RPM resumes.

**Note:** the MX+ pairs with one master at a time — disconnect your phone
(Torque/OBDLink app) first or the ESP32 cannot connect.

## Adding a new PID

1. If it's in the Torque export: `python3 scripts/gen_pids.py exportedPIDs.csv`
   prints ready-made rows — or copy the reference comment already in
   [lib/ObdCore/src/PidDefs.cpp](lib/ObdCore/src/PidDefs.cpp).
2. Add a `PidKey` enum value ([PidDefs.h](lib/ObdCore/src/PidDefs.h)) and, if it's a
   new physical quantity, a `ChannelId` + metadata row.
3. Add the table row in `PidDefs.cpp` with `verified=false`,
   `expectedResponder=0` and `expectedResponses=0`.
4. Flash once. From then on use the [console](docs/CONSOLE.md) — no reflash per
   PID: `log raw on`, then `probe <pid> 10`.
5. Compare against an independent reference. Note that Torque uses the same
   definitions imported here, so agreeing with it proves the transport works,
   not that the scaling is right — prefer a multimeter, a cross-check against a
   verified SAE PID, or a distinctive expected value.
6. Record the evidence in [docs/VERIFICATION_LOG.md](docs/VERIFICATION_LOG.md),
   flip `verified=true`, and update [docs/FORD_6_0_PIDS.md](docs/FORD_6_0_PIDS.md).
   If two ECUs answered with different values, pin `expectedResponder` to the one
   that proved to own the DID.

Details: [docs/TORQUE_PID_IMPORT.md](docs/TORQUE_PID_IMPORT.md).

## Adding the AMOLED display later

Implement `IDisplay` (three methods) in a new class against the chosen
controller's driver, swap the instance in `main.cpp`. Nothing else changes — the
OBD stack has no idea what renders. Plan: [docs/DISPLAY_PLAN.md](docs/DISPLAY_PLAN.md).

## Future external sensors (EGT, low-pressure fuel)

The stock PCM does not expose EGT or low-pressure fuel pressure — those need real
hardware (thermocouple + amplifier; pressure transducer). The interface stub is
[lib/Sensors/src/IExternalSensor.h](lib/Sensors/src/IExternalSensor.h); implementations
publish into `VehicleData` like any PID. These values are never faked from OBD.

## Future ESP-NOW gauges

A versioned telemetry packet already exists
([lib/Telemetry/src/EspNowTelemetry.h](lib/Telemetry/src/EspNowTelemetry.h)); broadcast is a
no-op stub. **Caveat recorded there:** Bluetooth Classic + Wi-Fi share the ESP32's
single 2.4 GHz radio; measure OBD throughput with Wi-Fi up before committing to
this design. The main gauge never depends on ESP-NOW.

## ⚠️ Automotive power (read before installing in the truck)

The dev board is USB-powered on the bench. **Never feed raw vehicle 12–14 V to
the ESP32.** Vehicle power is filthy: load dump, cranking sags, alternator
transients. A permanent install needs, in order from the battery/fuse box:

1. **Fuse** (low-value, close to the tap)
2. **Reverse-polarity protection** (series Schottky or P-FET)
3. **Transient/load-dump clamp** (automotive TVS, e.g. SMBJ/SMCJ series rated for 12 V systems)
4. **Automotive-rated buck converter** (wide-input, e.g. 6–36 V in, 5 V out;
   not a bare LM2596 board)
5. **Proper grounding** (chassis ground, no ground loops through the OBD port)

Also decide switched vs. constant power: on constant power the unit must sleep
hard when the ignition is off or it will drain the batteries.

## Repository layout

```
include/Config.h        all user configuration
src/                    main.cpp + ObdTask + UiTask (wiring only)
lib/ObdCore/            platform-independent protocol stack (unit-tested natively)
lib/Console/            serial console: parser, grammar, task mailbox, executor
lib/ObdBt/              Bluetooth Classic SPP transport
lib/Display/            IDisplay abstraction + SerialDisplay debug renderer
lib/Telemetry/          future ESP-NOW packet + stub
lib/Sensors/            future external sensor interface
lib/Log/                leveled logger
scripts/gen_pids.py     Torque CSV → C++ PID table generator (run once, reviewed)
test/                   host-side Unity tests + scripted mock transport
docs/                   architecture / protocol / PID / display / testing docs
exportedPIDs.csv        Torque Pro export (source of Ford PID definitions)
```
