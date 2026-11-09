# F-250 AGL Head Unit — Project Plan

> Plan of record for the pivot from the ESP32-only gauge to an AGL head unit.
> Written 2026-11-01.
>
> **Revision 2026-11-01 (evening).** An **MX+ truck trial, Phase 3.5**, now
> comes before any hardware purchase. It runs the Pi 5, the original display
> and the OBDLink MX+ over Bluetooth on Raspberry Pi OS. Phase 3 is reordered
> to build the MX+ path first, and the CAN-specific work moves into Phase 4.
> See [ADR-0011](architecture/adr/0011-mx-plus-trial-first.md). Progress is
> tracked in [ROADMAP.md](ROADMAP.md).

---

## Context

The repository today holds working ESP32 firmware. It reads the truck through an
OBDLink MX+ over Bluetooth SPP and prints gauge pages to the serial port. It has
140 host-side tests, a serial console, and a verification log of real findings
from the truck.

The project is now becoming a **Raspberry Pi 5 head unit running Automotive Grade
Linux (AGL)**. It replaces the aftermarket radio and provides:

- a touchscreen UI
- reliable Power Stroke telemetry
- Bluetooth audio
- offline navigation
- cameras
- logging
- ignition-aware power management

The ESP32 stays as an **auxiliary I/O controller**. The original Ford cluster and
every safety-critical system stay independent of the Pi.

Engineering priorities, in this order:

1. Reliable telemetry
2. Honest stale-data warnings
3. A responsive 800×480 UI
4. Safe electrical integration
5. A modular architecture

### Knowledge carried forward from the existing repo (verified on the truck)

These are facts, recorded in [docs/VERIFICATION_LOG.md](diagnostics/VERIFICATION_LOG.md). They
seed the new signal registry. They are not assumptions.

| Fact | Evidence |
|---|---|
| The diagnostic link is ISO 15765-4, CAN 11-bit, 500 kbaud (ELM protocol 6) | `ATDPN` → `A6`, 2026-08-09 |
| Two modules answer every functional (`7DF`) request: `7E8` and `7E9` | `010C` captures |
| `7E9` is the TCM: it owns `22 1674`. The PCM answers `7F 22 31` | Transmission temp: 130.4 °F, against Torque's 132.1 °F |
| The MX+ round trip is about 96 ms, so about 10 requests/s on `7DF` with two responders | Serial log timing |
| Differing bytes from two responders are not a disagreement. Compare decoded values | `maxResponderSpread` |
| Still open: physical addressing (`ATSH 7E0`/`7E1`) and every other Ford DID | `TRUCK_SESSION.md` Parts 1–3 |

Reusable logic that will be ported to Rust:

- the ELM parser and ISO-TP reassembly (`lib/ObdCore/src/ElmParser.cpp`)
- the responder bookkeeping and recovery ladder (`ElmClient.cpp`)
- the priority scheduler with its throughput budget (`PidScheduler.cpp`)
- the decoders (`Decoders.cpp`)
- the derived values (`Derived.cpp`)
- the warning rules (`Warnings.cpp`)
- the Torque CSV generator (`scripts/gen_pids.py`)

The existing C++ tests are the source of the Rust test vectors.

---

## Research findings (2026-11-01)

Status key:

- **V** = verified in an official or manufacturer source
- **F** = forum or secondary source
- **U** = unverified
- **C** = sources conflict

### AGL / OS

| Item | Finding | Status |
|---|---|---|
| Latest stable release | **Vibrant Vimba 22.0.0**, built on Yocto 6.0 "Wrynose". **Correction:** the release files are dated **18 Sep 2026**. The October date is only the announcement page's "last updated" stamp | V |
| Previous release | Ultimate Unagi 21.0.x (21.0.4, Sep 2026). AGL's Tokyo 2026 slides reportedly call it the LTS release, based on Scarthgap, maintained until 2028 | V / C (LTS claim) |
| Raspberry Pi 5 | `MACHINE = "raspberrypi5"`. Prebuilt `agl-ivi-demo-flutter` and `-qt` images exist. Kernel **6.18.33**. U-Boot boot. The docs still only cover the Pi 4 | V |
| Flutter | **Flutter 3.38.3**, `flutter-auto 2.0` (meta-flutter / ivi-homescreen), applaunchd app template | V |
| Qt | Qt 6.12-beta3. Not deprecated | V |
| Compositor | `agl-compositor` (libweston, `agl-shell` roles, `app_id` activation). applaunchd starts apps from systemd units over gRPC | V |
| Audio and Bluetooth | PipeWire 1.6.6, WirePlumber 0.5.14 with AGL config, BlueZ 5.86, the bluez5 SPA plugin, ofono. **Working A2DP sink is not documented** | V (packages) / U (A2DP) |
| CAN | `can-utils`. Modules: `can-isotp`, `mcp251x`, `gs-usb`, `mcp251xfd`. `mcp2515-can0` overlay deployed. `kuksa-databroker` and `kuksa-can-provider` ship | V |
| Video | GStreamer 1.28.2 with the V4L2 plugin, libcamera 0.6 | V |
| Build host | Native Linux: Ubuntu 22.04/24.04/26.04, Debian, Fedora, and others. **At least 300 GB for Flutter images**. 32 GB RAM. No macOS. An aarch64 host is not documented | V / U (aarch64) |

### Original 7" DSI display on the Pi 5

| Item | Finding | Status |
|---|---|---|
| Cable | 22-way to 15-way FFC, the display cable type. A camera-type cable holds the I2C clock low and leaves the screen dark (raspberrypi/linux#5813) | V |
| Overlay | `dtoverlay=vc4-kms-dsi-7inch` (DSI1 by default; add `,dsi0` for port 0). It includes the edt-ft5406 touch driver and needs `vc4-kms-v3d` | V |
| Backlight | Regulator-based (`rpi-panel-attiny-regulator` at 0x45). On the Pi 5 the display buses are i2c-4/i2c-6, so older `rpi_backlight` tools look in the wrong place | V |
| AGL support | The overlay and drivers ship. The AGL `config.txt` only has `vc4-kms-v3d-pi5,cma-256` and no `display_auto_detect`. **The display must be turned on explicitly** with `RPI_EXTRA_CONFIG` in meta-f250 | V |

### CarPiHAT PRO 5 (TJD; sold by The Pi Hut and Core Electronics)

> **Not used.** Dropped on 2026-11-04 in favour of a mini-box DCDC-USB, a
> separate opto input board and a DAC HAT
> ([ADR-0013](architecture/adr/0013-dcdc-usb-power-supply.md)). The findings
> below are kept as a research record.

Documentation lives on the GitHub wiki (gecko242/CarPiHat). It is not specific to
the PRO 5.

| Item | Finding | Status |
|---|---|---|
| Power | 12 V → 5 V buck, up to 5 A, fused and filtered. Under 1 mA when off. Has a 5 V output for the display | V |
| Input range, load-dump/TVS, reverse polarity | **Not published** | U |
| Ignition and latch | Ignition sense on BCM12. Power latch on BCM25. `dtoverlay=gpio-poweroff,gpiopin=25,active_low` | V |
| CAN | MCP2515, 8 MHz crystal, INT on **BCM23**, SPI0 CE0. **120 Ω termination fitted. No jumper documented.** Not isolated | V / U (jumper) / inferred (isolation) |
| DAC | Burr-Brown, 192 kHz/24-bit, 3.5 mm out, `hifiberry-dacplus-std` (PCM512x family inferred). Line-out level not documented. Config instructions conflict between sources | V / C |
| 12 V inputs | 5 opto-isolated, 12–18 V: IGN BCM12, REV BCM7, ILLUM BCM13, IN_1 BCM14, IN_2 BCM17 | V |
| 12 V outputs | OUT_0 BCM27 and OUT_1 BCM22, high-side, 1 A each | V |
| RTC | DS1307 (`i2c-rtc,ds1307`). No battery; runs from the permanent 12 V feed. Not needed: the head unit uses the Pi 5's onboard RTC with a J5 battery ([matrix](hardware/compatibility-matrix.md#raspberry-pi-5-onboard-rtc)) | V |
| Pin conflicts | SPI CE1 shares BCM7 with the reverse input (fix: `spi0-cs,cs1_pin=24`). BCM14 is UART TX | V / inferred |
| Display fit | The HAT's 5 V output was tested with the original display. Whether the DSI ribbon clears the HAT on a Pi 5 is not documented | V / U |

### 2007 F-250 network

| Item | Finding | Status |
|---|---|---|
| HS-CAN | 500 k on pins 6/14. Modules: PCM, TCM, ABS, IC, TBC | **Verified on this truck** (protocol 6) / F (module list) |
| ISO 9141 K-line | RCM and GEM, on pin 7. **The MCP2515 cannot reach these. The MX+ can** | F |
| MS-CAN | Ford's 2008 manual lists it. 2006–07 owner scans found no MS-CAN modules | C |
| FICM | Not a separate module in owner scans. Its voltages appear as PCM PIDs | F |
| Turn-signal and reverse broadcasts | **Turn signals are not on HS-CAN**: an analogue flasher-relay circuit (owner, 2026-11-07; none in the census). Reverse is broadcast (candidates, [CAN_CENSUS](diagnostics/CAN_CENSUS.md)) | owner / T |

### Consequences for the design

1. **CAN termination is a hard installation gate.** A third 120 Ω resistor on the
   DLC stub would drop the bus to about 40 Ω. Before the HAT touches the truck,
   measure the HAT's resistance between CANH and CANL. Then either remove the
   resistor or confirm how to disable it.
2. **Input protection is unpublished.** Ask TJD for the input range, TVS and
   reverse-polarity details. Plan an external fuse and TVS until they answer.
3. **The DSI cable fit and the HAT stack must be checked by hand.** This includes
   any NVMe base.
4. **Reverse comes from HS-CAN, a 5-way switch picks the camera**
   ([ADR-0024](architecture/adr/0024-camera-selection-switch-and-can-reverse.md),
   2026-11-09). Reverse is broadcast (`230` byte 0) and read listen-only by
   the gateway; never OBD polling. The turn signals (an analogue
   flasher-relay circuit, not on HS-CAN) aren't used. No opto board.
5. **The MX+ is still needed for K-line modules.** Its Bluetooth link shares the
   Pi's radio with A2DP. Mitigations:
   - use the transport for validation only
   - add a USB Bluetooth dongle
   - use the ESP32 as an SPP→USB bridge
6. **The Mac cannot host the Yocto build.** It runs macOS and has only 146 GB
   free, against more than 300 GB needed. See ADR-004.

### Alternatives if the CarPiHAT PRO 5 can't be confirmed

- **CAN:** a USB candleLight/CANable adapter (`gs_usb` is already in the AGL
  image). No SPI or interrupt conflicts.
- **CAN, isolated:** Waveshare 2-CH CAN HAT. Isolated, jumper termination,
  16 MHz, INT GPIO23/25. Its pins conflict with the CarPiHAT if stacked.
- **Power:** a dedicated automotive Pi power supply with ignition latch, plus a
  separate I2S DAC HAT.

---

## Architecture decisions (each becomes an ADR in `docs/architecture/adr/`)

| ADR | Decision | Why |
|---|---|---|
| 001 | **Target AGL Vimba 22.0.x** and pin the exact tag. Unagi 21 LTS is the fallback | Verified prebuilt Pi 5 images, Flutter 3.38.3, kernel 6.18. Re-check Unagi's Pi 5 image and LTS status before Phase 5 locks it in |
| 002 | Rust services; a Flutter UI **pinned to 3.38.3** (via `.fvmrc`, to match the target engine); gRPC between them over **Unix domain sockets** | Matches the AGL runtime. UDS lets file permissions enforce isolation |
| 003 | **Own versioned API** (`f250.vehicle.v1`) as the source of truth, with an optional KUKSA databroker bridge later | VSS/KUKSA can't model staleness, provenance or communication health. The bridge keeps AGL demo apps usable |
| 004 | Yocto builds on a **Linux x86_64 host** (spare PC or cloud VM: 8+ cores, 32 GB+, 400 GB+). Daily development stays on macOS. A Lima/UTM aarch64 VM is an unsupported experiment only | AGL/Yocto host requirements; disk space on the Mac |
| 005 | **Staged AGL bring-up.** First boot the prebuilt Vimba image with `config.txt` changes and sideloaded binaries. Then the full `meta-f250` image | Gets hardware answers before spending a 300 GB build |
| 006 | Signal definitions are **YAML data** (`shared/signals/`) with a **safe formula grammar** parsed in Rust. No `eval` | Imported Torque formulas are untrusted input |
| 007 | **Read-only vehicle access by default.** Diagnostic transmit is off at boot. Enabling it takes an explicit config flag plus a recorded electrical-verification checklist. Write services (`2E`, `31`, `14`, `3B`, `10`, and others) are refused in code | Safety requirements |
| 008 | **Libraries live in `crates/`**, daemons in `services/`. `services/telemetry` becomes `crates/telemetry` | A library under `services/` is misleading. This is the one deviation from the suggested layout |
| 009 | **Camera rendering is decided by a spike**: a Flutter texture (alerts stay overlaid) versus a GStreamer `waylandsink` surface raised through `agl-shell` | Alerts must stay visible. Must be measured on the Pi 5 |
| 010 | **Map: `flutter_map` with offline MBTiles/PMTiles. Routing: a Valhalla service.** Both are prototyped before committing | Runs offline and fits Flutter on Linux. Valhalla's offline tiles are a better fit than GraphHopper's JVM |
| 011 | **MX+ truck trial before buying CAN hardware.** Run the real stack (gateway, recorder, UI) on Raspberry Pi OS with the MX+ over Bluetooth. Purchases are decided from its data | Uses hardware already owned. Tests five of the six dropout hypotheses. Exercises the gateway on a real vehicle early |

---

## Target repository layout

```
TruckDashboard/
├── README.md, CLAUDE.md, Makefile, Cargo.toml (workspace), .fvmrc
├── docs/{architecture/{adr},hardware,wiring,setup,diagnostics,development}/
├── agl/{meta-f250,configurations,scripts}/
├── crates/                 telemetry (model, units, registry, formula, staleness, warnings),
│                           proto (generated), elm (ELM/STN client), isotp, can-decode
├── services/{vehicle-gateway,recorder,power-manager,camera-manager,audio-manager}/
├── apps/infotainment/      Flutter app
├── shared/{proto/f250/*/v1,signals,configuration}/
├── firmware/esp32/         existing PlatformIO project, moved with git mv
├── simulator/powerstroke/  scenario YAML + Rust simulated transport
├── tools/{can-monitor,pid-importer,obd-console,diagnostics,pi,dev}/
├── tests/{integration,hardware}/
└── .github/workflows/
```

---

## Step-by-step plan

Gate markers:

- **[HW]** needs physical hardware
- **[HUMAN]** needs a person to inspect or approve before continuing (wiring and installation)
- **[SIM]** runs entirely in simulation

No hardware-dependent step is marked done until it has run on real hardware.

### Phase 0 — Repository migration

1. **0.1** Create branch `feat/agl-pivot` from the current branch, after the pending docs are committed.
2. **0.2** Move the firmware with `git mv` into `firmware/esp32/`:
   - `platformio.ini`
   - `include/`, `src/`, `lib/`, `test/`
   - `scripts/gen_pids.py`
   - `exportedPIDs.csv` → `shared/signals/imports/torque/exportedPIDs.csv`, with `gen_pids.py` and the docs updated to point there (one copy, no duplicate)
3. **0.3** Move the existing docs:
   - ESP32 docs → `docs/esp32/`
   - `FORD_6_0_PIDS.md`, `VERIFICATION_LOG.md`, `TRUCK_SESSION.md` → `docs/diagnostics/`
   - fix every relative link
4. **0.4** Verify the move:
   - `cd firmware/esp32 && pio test -e native` passes all 140 tests
   - `pio run -e esp32dev` builds
   - `grep` finds no stale paths

   *Done when:* the firmware builds and passes its tests from its new home, and history is preserved (`git log --follow`).

### Phase 1 — Architecture, documentation, development environment

1. **1.1** Write `CLAUDE.md`. It covers:
   - architecture rules (the UI never touches CAN; everything goes through the gateway)
   - safety rules (ADR-007, no invented PIDs or CAN IDs)
   - verified, imported and guessed terminology
   - build and test commands
   - the "never claim hardware-tested" rule
   - commit conventions
2. **1.2** Rewrite `README.md` for the head-unit project: status, quick start, layout, and links to this plan.
3. **1.3** Write the architecture documents in `docs/architecture/`:
   - `overview.md`, with Mermaid diagrams of the components, data flow, process and systemd-unit map, and the trust boundaries
   - `telemetry-model.md`
   - `diagnostic-recovery.md`, covering the state machines
   - `power-states.md`
   - `camera-policy.md`
   - `audio-routing.md`
   - ADRs 001–010
4. **1.4** Write `docs/hardware/compatibility-matrix.md` from the research tables above, keeping the V/F/U/C status and sources. Add:
   - `open-questions.md`: termination jumper, TJD protection specs, DSI ribbon fit with the HAT, NVMe stacking, amplifier inventory, camera selection, GPS model, storage medium, line-out level, OUT_x default state on reset
   - `shopping-list.md`, with alternatives
5. **1.5** Write `docs/safety/assumptions.md`:
   - the system is not a certified safety camera
   - it is read-only
   - the cluster stays independent
   - a person must verify every wiring change
6. **1.6** Set up the development environment:
   - a root `Makefile` with targets: `setup`, `proto`, `test`, `lint`, `sim`, `ui`, `ui-test`, `fw-test`, `linux-test` (Docker), `deploy`, `logs`
   - `docs/setup/macos.md` (Homebrew: rustup, protobuf, buf, fvm, PlatformIO; VS Code extensions)
   - `docs/setup/linux-build-host.md` (ADR-004)
   - `rust-toolchain.toml`
   - `.fvmrc` pinned to 3.38.3
7. **1.7** Write `docs/ROADMAP.md`: a phase checklist that links back to this plan.
8. **1.8** Set up CI in `.github/workflows/`:
   - `rust.yml` (fmt, clippy, test on macOS and Ubuntu)
   - `flutter.yml` (analyze, test)
   - `firmware.yml` (`pio test -e native`)
   - `proto.yml` (`buf lint` and breaking-change check)
   - `linux-integration.yml` (vcan; whether hosted runners can load vcan has to be confirmed, with an in-process mock CAN as the fallback)

   *Done when:* `make setup && make test` works on the Mac, and CI is green.

### Phase 2 — Working simulated dashboard [SIM]

1. **2.1** Define the shared scenario format in `simulator/powerstroke/scenarios/*.yaml`. A scenario has signal trajectories (warm-up, idle, tow-climb, cooldown) and injected faults:
   - **EOT/ECT freeze**, the reported field symptom
   - a single PID going silent
   - total link loss and recovery
   - FICM sag
   - out-of-range values
   - an invalid response
2. **2.2** Scaffold the Flutter app `apps/infotainment`:
   - macOS desktop target with the window fixed at 800×480
   - `devicePixelRatio` assumptions documented (design in 800×480 logical px)
   - day and night themes
3. **2.3** Build the data layer as a `VehicleDataSource` interface with two implementations:
   - `SimulatedVehicleDataSource`, which plays the scenarios and emits normalized samples with validity and age
   - a stub that will later become `GrpcVehicleDataSource`

   The Dart-side model mirrors the planned proto.
4. **2.4** Build the app shell:
   - bottom navigation for Home, Gauges, Media, Navigation, Cameras, Diagnostics
   - a **global alert layer** above all routes (critical engine alerts, communication loss)
   - a status bar showing link health, passive/active mode, and the clock
5. **2.5** Build the widgets:
   - digital gauge
   - circular gauge
   - compact indicator
   - **stale state**: shows the last good value, its age, and a hatched or greyed warning, and is never drawn as current
   - an "unverified definition" badge
6. **2.6** Build the screens:
   - **Home:** EOT, ECT, the delta, media card, shortcuts, health
   - **Gauges:** engine and towing profiles, configurable through JSON
   - **Diagnostics:** live signal list with age and validity, link-health panel, a DTC list (simulated), and a log view
   - **Media and Navigation:** clearly labelled placeholders that don't pretend to work
7. **2.7** Implement warnings in the UI: advisory and critical levels with hysteresis, driven by thresholds from config labelled **example — verify**. They are never hard-coded as universal.
8. **2.8** Write the tests:
   - widget tests at 800×480 (`tester.view.physicalSize`): no overflow on any screen
   - touch targets ≥ 60×60 px (about 11 mm on this panel)
   - navigation between all screens
   - a critical alert stays visible on every screen
   - a stale signal renders as stale, and the delta is hidden when either input is stale
   - unit tests for hysteresis and unit conversion

   *Done when:* `make ui` runs the dashboard on the Mac, `make ui-test` is green, and the EOT/ECT-freeze scenario visibly produces stale warnings.

### Phase 3 — Vehicle-data backend [SIM]

**Build order (revised).** Build first what the MX+ trial (Phase 3.5) needs:
3.1, 3.2, 3.3, 3.5, the `Simulated` and `ObdLink` transports of 3.6, then 3.7–3.11
and 3.13–3.14. The `SocketCan` transport moves to Phase 4, where CAN hardware
exists. 3.4 (the Torque importer) can follow the trial: the trial's registry is
seeded by hand from `FORD_6_0_PIDS.md`.

1. **3.1** Write the protos in `shared/proto/f250/vehicle/v1/`, wired up with `make proto` and buf:
   - `telemetry.proto`
   - `health.proto`
   - `diagnostics.proto`

   A sample carries:
   - signal id
   - value
   - unit
   - monotonic and wall timestamps
   - validity (`VALID`, `STALE`, `NO_DATA`, `OUT_OF_RANGE`, `DECODE_ERROR`, `DISABLED`)
   - last-good value and its time
   - source (transport, ECU/responder, request)
   - provenance (`SAE`, `VERIFIED_ON_TRUCK`, `IMPORTED_UNVERIFIED`, `COMPUTED`, `AUX_SENSOR`)
2. **3.2** Build `crates/telemetry`:
   - the signal registry, loaded from YAML and validated against a JSON Schema
   - units with metric/imperial conversion
   - **the safe formula grammar**: bytes `A`–`D`…, `signed()`, arithmetic, references to other signals, all with tests
   - staleness tracking
   - computed signals, valid only while all their inputs are valid
   - warnings with hysteresis
3. **3.3** Seed `shared/signals/`:
   - SAE Mode 01 PIDs
   - `22 1674` as **VERIFIED** (responder `7E9`, with its evidence link)
   - the remaining Torque Ford DIDs as `IMPORTED_UNVERIFIED`, disabled
   - nothing invented
4. **3.4** Build `tools/pid-importer`, a Rust CLI:
   - Torque CSV → registry YAML
   - translates formulas into the grammar and rejects anything it can't parse
   - flags `BARO()` and similar as dependencies
   - marks every row unverified
   - prints a validation report
   - tests use `exportedPIDs.csv`
5. **3.5** Build `crates/elm`, a port of the C++ ElmParser and ElmClient:
   - works over any byte stream
   - responder attribution
   - ISO-TP reassembly
   - NRC handling
   - `expectedResponder`

   Its tests port the existing C++ test vectors.
6. **3.6** Build `services/vehicle-gateway` with a `Transport` trait and these implementations:
   - `Simulated`, which emits frame-level responses from scenarios, including faults
   - `ObdLink`, an ELM/STN byte stream (via `crates/elm`) over:
     - Bluetooth RFCOMM on Linux (BlueZ)
     - a serial device: a macOS `/dev/cu.*` Bluetooth serial port, or the ESP32 as a USB bridge
   - Not in this phase: `SocketCan` (Linux-only, behind a cfg flag), moved to Phase 4.1
7. **3.7** Build the scheduler: priority plus throughput budget (ported), adaptive intervals, per-PID timeouts, bounded retries with jitter.
8. **3.8** Build the **recovery state machines**:
   - **per PID:** `ACTIVE → SUSPECT → BACKOFF(exp, capped) → QUARANTINED` (low-rate probe) `→ ACTIVE`
   - **per link:** `DISABLED / PASSIVE_ONLY / INITIALIZING / POLLING / DEGRADED / RECOVERING (soft→adapter reset→reconnect) / BACKOFF / FAULT`

   Every transition has an explicit limit. The transmit budget is never exceeded during recovery. A watchdog reports faults and never reboots the Pi.
9. **3.9** Add diagnostic event history (structured events) and the health API.
10. **3.10** Build `services/recorder`:
    - SQLite in WAL mode
    - configurable sample intervals
    - retention limits
    - a bounded ring for raw captures
    - CSV export
11. **3.11** Point the Flutter app's `GrpcVehicleDataSource` at the gateway in simulated mode (`make sim`).
12. **3.12** Write the tests:
    - PID parsing and Ford response decoding (verified vectors only)
    - unit conversion
    - timeouts, invalid responses, staleness, connection loss
    - every recovery transition
    - scheduler fairness and budget
    - frame decoding: wrong DLC, unknown IDs, bus-error handling, passive mode refusing to transmit
    - recorder retention
13. **3.13** Build `tools/obd-console`, the Pi-side equivalent of the ESP32 serial console. It works through the gateway's diagnostics API and provides:
    - `pids`, `on`/`off`, `probe`, `raw`, `stats`
    - `raw` restricted to AT commands plus the ADR-0007 read-service allow-list
    - every transcript saved for `VERIFICATION_LOG.md`

    This lets `TRUCK_SESSION.md` run on the Pi. The ESP32 console stays as a fallback.
14. **3.14** Add a **Linux desktop target** to the Flutter app (`apps/infotainment/linux`) for Raspberry Pi OS:
    - fullscreen at 800×480
    - built on the Pi with Flutter 3.38.3 (linux-arm64)

    Confirming that Flutter's Linux arm64 host build works on the Pi 5 is part of this step. `flutter-pi` is the fallback.

    *Done when:*
    - the UI is driven by the gateway
    - the EOT/ECT-freeze scenario is detected, quarantined, recovered and logged
    - the `ObdLink` transport passes against a scripted ELM transcript (the ported C++ vectors)
    - `make test` is green on macOS and in Linux CI

### Phase 3.5 — MX+ truck trial (nothing to buy) [HW] [HUMAN]

Run the real stack on the Pi 5 with the original display, Raspberry Pi OS and
the OBDLink MX+ over Bluetooth. It produces real data before any money is spent
([ADR-0011](architecture/adr/0011-mx-plus-trial-first.md)).

1. **3.5.1 Pi preparation (bench).**
   - Install current 64-bit Raspberry Pi OS. Confirm the display, touch and the 22→15-way ribbon (ADR-0005 stage 0).
   - Run `tools/pi/setup-raspios.sh`. It installs the build dependencies, Rust, fvm and Flutter 3.38.3. BlueZ ships with the OS.
   - Build the gateway, recorder and app on the Pi, or cross-build the Rust parts from the Mac.
   - `make pi-run` starts all three. The app runs fullscreen.
2. **3.5.2 Pair the MX+.**
   - Use `bluetoothctl` with an agent running (`agent on`, `default-agent`), then `pair` and `trust`. The address is `00:04:3E:85:EA:FC` (recorded in the firmware config).
   - **Pairing is Secure Simple Pairing, not a PIN.** When the owner paired it, a one-time passkey was displayed (not `1234`) and nothing had to be typed (2026-11-01, `bench-log.md`). If `bluetoothctl` asks to confirm a passkey, answer `yes`. Don't enter `1234`.
   - Pair once, interactively. No PIN goes in the gateway config.
   - Disconnect the phone (Torque) and the ESP32 first. The MX+ takes one Bluetooth master at a time.
   - Gateway config: `make pi-run TRANSPORT=obdlink TRANSMIT=1`. The address defaults to the one above ([setup/raspberry-pi.md](setup/raspberry-pi.md)).
   - ADR-0007's opt-in still applies. The trial's checklist entry records "commercial OBD adapter in the DLC, no added wiring" in `bench-log.md`.
3. **3.5.3 Temporary truck setup** [HUMAN].
   - Power the Pi from a USB-C PD supply able to deliver 5 V / 5 A. A 3 A supply works, with reduced USB current. This is **for the trial only, not a permanent install** (Phase 7).
   - Mount the screen securely, out of the airbag path and the driver's view of the road.
   - There is no ignition sensing yet, so shut down from the UI or over SSH before key-off.
   - The recorder uses SQLite WAL so a power cut loses at most the last seconds. SD-card corruption is the remaining risk; keep a spare image.
4. **3.5.4 Driveway session** (KOEO and idle).
   - Run `TRUCK_SESSION.md` Parts 1–4 through `tools/obd-console` on the Pi, or the ESP32 console as a fallback:
     - physical addressing (`ATSH 7E0`/`7E1`)
     - the response-count digit
     - bare `ATCRA`
     - multi-DID batching
     - every Ford DID, including `22 16C1` fuel level
     - throughput
   - Record every transcript in `VERIFICATION_LOG.md`. Promote PIDs only with evidence.
5. **3.5.5 Speed calibration.** Measure the factor against GPS ([CALIBRATION.md](diagnostics/CALIBRATION.md)) and commit it to `calibration.json`.
6. **3.5.6 Logged drives.** Normal driving and, if possible, towing. The recorder keeps:
   - every request and response line, with latency and responder
   - negative responses, timeouts, `STOPPED`, `BUFFER FULL`, `CAN ERROR`
   - every unsolicited STN line (`LV RESET`, `ACT ALERT`, `SLEEPING`)
   - per-PID and per-link state transitions, and each recovery step taken
   - adapter supply voltage from `ATRV` (the ELM's own reading at DLC pin 16) every few seconds

   Run at least two configurations:
   - the poll set and rate Torque used
   - the gateway's budgeted schedule (and physical addressing, if Part 1 showed it works)
7. **3.5.7 Analyse and decide.** Write `docs/diagnostics/mx-plus-trial.md`:
   - which dropout hypotheses the logs eliminate or support (see the table below)
   - whether automatic recovery restored frozen PIDs without unplugging the adapter
   - measured throughput
   - the hardware decision. Already made: the USB CAN adapter (ADR-0012) and, for power, the DCDC-USB with no CarPiHAT (ADR-0013). Record anything further in `shopping-list.md`.

   *Done when:*
   - the truck's dashboard has run on the Pi from MX+ data
   - at least a few hours of driving are logged
   - each `TRUCK_SESSION.md` question is answered or recorded as blocked
   - the purchase decision is written down

   *What the trial cannot show:*
   - whether a missing response was ever on the wire. That needs a listen-only CAN capture (Phase 4.7)
   - AGL-specific behaviour (Phase 5)
   - ignition-driven power behaviour (Phase 6–7)

### Phase 4 — CAN hardware communication [HW] [HUMAN]

Starts after the purchase decision in 3.5.7. The hardware it uses is whatever
that decision chose.

1. **4.1** Do the **bench bring-up** on a Pi 5 running Raspberry Pi OS, with the USB CAN adapter (ADR-0012; the CarPiHAT is dropped, ADR-0013). Add the gateway's `SocketCan` transport (moved here from 3.6):
   - firmware and listen-only on the adapter
   - loopback test
   - **measure and resolve the termination**
2. **4.2** Build `tools/can-monitor`:
   - listen-only setup (`ip link … listen-only on`)
   - bitrate check
   - raw capture with timestamps and error counters
   - bounded capture files
   - export to candump and CSV
3. **4.3** **Stage A on the truck**, passive and listen-only only, after a [HUMAN] wiring checklist:
   - confirm 500 k
   - record the broadcast census at KOEO, idle and driving
   - the **event captures**: reverse and brake, one capture each ([can.md](setup/can.md#event-captures-reverse-and-brake)). The turn signals are settled: not on the bus, and not used (ADR-0024, H14)
4. **4.4** **Stage B:** decoders only for broadcast signals that can be corroborated (for example against the RPM and speed PIDs). Each records its provenance and confidence. **No guessed definitions are shown as validated.**
5. **4.5** **Stage C:** active diagnostics through kernel ISO-TP (`can-isotp`), PCM `7E0/7E8` and TCM `7E1/7E9`, first proven with a single request. It needs both the transmit opt-in and the checklist. Polling is conservative and has a kill switch.
6. **4.6** **Stage D:** the OBDLink transport already ran on the truck in Phase 3.5. Here, confirm two things:
   - switching transports by config with no UI change
   - the **never transmit on two transports at once** rule, with the MX+ and CAN hardware both present
7. **4.7** **The intermittent-dropout experiment** (see the diagnostics section below).
8. **4.8** Finish any `TRUCK_SESSION.md` items Phase 3.5 left open, now over direct CAN, and promote PIDs only with log evidence.

### Phase 5 — AGL deployment [HW]

1. **5.1** Confirm the build host (ADR-004) and the release (ADR-001).
2. **5.2** First flash the **prebuilt Vimba Pi 5 Flutter image** and enable:
   - `vc4-kms-dsi-7inch`
   - ~~the CAN overlay~~: none needed, the CAN adapter is USB (ADR-0012). Instead,
     override the image's own CAN defaults before the adapter meets the truck
     ([ADR-0015](architecture/adr/0015-agl-can-defaults.md))
   - the DAC HAT's overlay
   - `HandlePowerKey=ignore` for logind (power-manager handles the key; ADR-0013)
   - RTC battery charging on the Pi 5's onboard RTC (`dtparam=rtc_bbat_vchg=3000000`; [H20](hardware/open-questions.md))

   Then check the display, touch, backlight, CAN and audio. Write `agl/scripts/diagnose-display.sh`, which collects:
   - DRM connectors
   - `dmesg`
   - the i2c-4/6 probe
   - the touch input device
   - backlight sysfs
   - compositor logs
3. **5.3** Write the **HDMI and Raspberry Pi OS fallback procedure** for separating a hardware fault from an AGL driver fault.
4. **5.4** Build `agl/meta-f250` ([ADR-0017](architecture/adr/0017-meta-f250-layer.md), [ADR-0021](architecture/adr/0021-trimmed-dev-and-release-images.md)):
   - ~~`RPI_EXTRA_CONFIG` overlays~~: an `rpi-config` append writes
     `agl/boot/config-f250.txt` into `config.txt`, the same block Stage 1 adds
   - ~~a kernel config fragment (CAN, ISO-TP)~~: none needed. The image's kernel
     has `gs_usb`, `can-raw` and `can-isotp`, and ISO-TP is our own code over a
     raw socket ([ADR-0012](architecture/adr/0012-direct-can-usb-adapter.md)). A fragment comes with the first
     feature that needs a kernel option
   - one recipe, `f250-services`, for the Rust services (OE's `cargo` class,
     the AGL tree's Rust 1.96.1, crate list generated from `Cargo.lock`)
   - ~~the Flutter app via the applaunchd template~~: meta-flutter's
     `flutter-app` class; the dashboard is a systemd unit bound to the
     compositor, and the images have no applaunchd
   - systemd units with hardening and watchdogs
   - udev rules (backlight, GPIO): with their Phase 6 features. CAN needs none
   - two images on AGL's compositor image: `agl-f250` (development) and
     `agl-f250-release` (root by key only)
   - ~~`kas` or~~ AGL's `aglsetup.sh`, run by `agl/scripts/agl-build.sh`, with
     the release pin in `agl/configurations/vimba.env`
5. **5.5** Set up deployment: `make deploy` copies the binaries (cross-built ~~with cargo-zigbuild or cross~~ in an arm64 Docker container, [ADR-0016](architecture/adr/0016-stage1-sideload-layout.md)) and the Flutter bundle to the Pi over SSH. Write the image build and flash instructions, and the log-collection script.

### Phase 6 — Infotainment features

1. **6.1** **audio-manager**:
   - BlueZ agent with controlled pairing (a pairing window, no open discoverability)
   - A2DP sink via PipeWire bluez5 and WirePlumber
   - AVRCP control and metadata (MediaPlayer1)
   - automatic reconnect
   - an active-device policy for multiple phones
   - volume limits
   - leaves an extension point for HFP and echo cancellation
2. **6.2** **Amplifier switching and mute** (ADR-0014):
   - the amplifier remote is on ACC with no timer, not on the Pi (amended 2026-11-09)
   - measure whether the DAC8x pops at power-up with the amps on; if it does, add a delay-on timer relay [HW] (H6)
   - the DAC stays muted until the pipeline is up, and is muted before shutdown
   - record what the speakers do when the Pi panics or the watchdog resets it with the amps on [HW] (H5)
3. **6.3** **Physical volume knob** on the ESP32 (encoder) or on Pi GPIO.
4. **6.4** **GPS**: a USB GNSS receiver through gpsd. gpsd 3.27.5 is in the Vimba 22.0.1 Pi 5 image (manifest, 2026-11-06).
5. **6.5** **Navigation**, in order:
   1. offline map display and current position
   2. Valhalla routing and turn-by-turn
   3. a map update workflow over Wi-Fi or USB
   4. documentation of ODbL attribution, storage and limits, including **no heavy-vehicle or trailer guarantees**
6. **6.6** **camera-manager**:
   - V4L2 and GStreamer pipelines
   - the ADR-009 rendering spike
   - the policy state machine (ADR-0024): reverse priority, then the 5-way switch's latched choice at any speed, restore the previous screen
   - camera-loss warnings, and a visible "reverse unknown" when the CAN reverse signal is stale
   - reverse from the gateway (HS-CAN broadcast `230`, once its decoder is verified); the switch from power-manager. No vehicle wire on GPIO
   - camera hardware chosen by measured driver support and latency on the Pi 5 (UVC first)

   Tests: reverse priority, stale reverse, the latched choice, switch debounce, missing source, and return to the previous screen.
7. **6.7** **power-manager**, the single owner of the GPIO and the power key, pulse-only ([power-states.md](architecture/power-states.md); ADR-0013 amended 2026-11-09):
   - states: `OFF, STARTING, RUNNING, SHUTTING_DOWN, FAULT`
   - the power key (the DCDC-USB's PSW pulse on J2): ignored during the boot window, otherwise it shuts down
   - ~~ignition and battery voltage over USB, reboot instead of halt, low-voltage shutdown~~: dropped, the DCDC-USB's USB isn't connected
   - the camera switch (five GPIO contacts, debounced), passed to camera-manager (ADR-0024)
   - day/night from sun position and a manual override (no illumination wire)
   - backlight dimming
   - systemd and hardware watchdogs
   - the dashboard **Power** button becomes Restart: the Pi can't tell when Shut down is safe (ADR-0013 decision 5)

   Tests: the power key in every state, stray pulses during boot, and a process dying unexpectedly.

### Phase 7 — Installation and reliability [HW] [HUMAN]

1. **7.1** Wiring diagrams in `docs/wiring/`:
   - fused constant feed and the ACC feed to the DCDC-USB ([power-and-inputs.md](wiring/power-and-inputs.md))
   - PSW to J2, and VOUT to the Pi's USB-C input
   - external TVS
   - ground scheme
   - DLC tap or Y-cable
   - amplifier signal, remote and separate fused power
   - the camera switch's cable to the Pi's GPIO
   - camera power

   Each diagram must be reviewed by a person before installation.
2. **7.2** Electrical validation: cranking dip, load dump, parked current draw (target ≤ 1 mA when off), the ACC feed's behaviour while cranking (H22), HARDOFF against the measured shutdown time, and the CAN termination measured again in the vehicle.
3. **7.3** Thermal validation in a closed cab in summer, with throttle logging.
4. **7.4** Communication stress tests: long drives, dropout injection, and recovery statistics.
5. **7.5** An on-vehicle acceptance checklist and a troubleshooting guide.

---

## Diagnosing the intermittent EOT/ECT dropout

The goal is a design that diagnoses the dropout and recovers from it, without
unplugging the adapter.

### Hypotheses and how to tell them apart

| Hypothesis | Signature | Discriminating test |
|---|---|---|
| Functional `7DF` with two responders desynchronises the adapter (a straggler arrives mid-request, `STOPPED`, a stale filter) | Errors cluster after two-responder PIDs, and the adapter recovers on reset | Poll the same set through physical addressing compared with `7DF`, and count desync events |
| Polling overload or adapter buffer limits | Latency climbs before the dropout | Sweep the request rate. Record latency percentiles and the count of `BUFFER FULL` |
| A wrong ECU owns the DID, or the response is misattributed | One PID dies while others live, and the responder changes | Record the responder per sample (already in the model) |
| Adapter state goes bad (sleep or LV reset chatter) | `LV RESET`, `ACT ALERT` or `SLEEPING` lines | Log all unsolicited STN lines |
| Electrical: DLC pin contact or adapter power | Dropouts track bumps or voltage. The fix is reseating | Log battery voltage alongside. Inspect and clean DLC pins 4, 5, 6, 14, 16 |
| ECU-side: the PCM stops answering a DID | The ECU sends no response frame on the wire at all | **The decisive test is below** |

### What the MX+ trial (Phase 3.5) can already show

| Hypothesis | Evidence from the MX+ logs alone |
|---|---|
| Two-responder desync | `STOPPED` / unexpected-line counts around freezes; A/B between `7DF` and physical addressing |
| Polling overload | Latency percentiles and `BUFFER FULL` before freezes; A/B between Torque's rate and the budgeted rate |
| Wrong ECU / misattribution | The responder recorded per sample changes, or a negative response appears, at the freeze |
| Adapter state | Unsolicited STN lines logged near freezes |
| Electrical / adapter power | `ATRV` voltage dips correlated with freezes |
| ECU stops answering | **Not separable** from "adapter dropped it". Needs the experiment below |

### The decisive experiment (Phase 4.7)

1. Use a **DLC Y-cable**.
2. Let the MX+ poll exactly as Torque did.
3. Run the Pi's CAN interface **in listen-only mode**, recording every `7DF`/`7E0`/`7E8`/`7E9` frame.
4. When a gauge freezes, compare the two:
   - If the ECU response is on the wire but the adapter reported nothing, the fault is in the adapter or the host.
   - If the request is on the wire but no response came back, the fault is in the ECU or the protocol.
   - If no request was sent, the fault is in the scheduler or the adapter.

Only one device ever transmits. The capture is bounded and exported for analysis.
The procedure goes in `docs/diagnostics/dropout-capture.md`.

---

## Security and safety requirements (enforced in code and review)

- Diagnostic transmit is off at boot.
- Passive by default.
- Write, control, flash and DTC-clear services are refused in code. DTC clear is a
  future opt-in, if ever.
- The CAN input is untrusted:
  - DLC and length validation
  - bounded queues
  - rate-limited logging
- Services run under systemd hardening:
  - `DynamicUser` or a dedicated user
  - `ProtectSystem=strict`
  - a minimal capability set
  - per-service sockets with file-mode access control
- No unneeded network services. SSH is key-only, in a development image variant.
- Bluetooth pairing only inside an explicit pairing window.
- Configuration is validated against a schema at load time, and a bad
  configuration falls back to safe defaults.
- Software and hardware watchdogs.
- Every wiring step is gated on a person checking it.

---

## Verification (how each phase is shown to work)

| Phase | Command or evidence |
|---|---|
| 0 | `cd firmware/esp32 && pio test -e native` (140 pass); `pio run -e esp32dev`; `git log --follow` on a moved file |
| 1 | `make setup && make test` on macOS; CI green; links checked |
| 2 | `make ui` (800×480 window; run the freeze scenario and see stale badges); `make ui-test` |
| 3 | `make test` (Rust and Flutter); `make sim` drives the UI through the gateway; recovery-transition tests; `make linux-test` in Docker |
| 3.5 | Pi dashboard live from the MX+ on the truck; transcripts in `VERIFICATION_LOG.md`; drive logs plus `docs/diagnostics/mx-plus-trial.md`; purchase decision recorded |
| 4–7 | Hardware logs and photos recorded in `docs/diagnostics/VERIFICATION_LOG.md` and `docs/hardware/bench-log.md`. Nothing is marked tested without that evidence |

## Hardware to buy (nothing owned yet beyond the Pi 5, display, MX+ and ESP32)

**Nothing is needed before the MX+ trial (Phase 3.5)**, beyond a USB-C supply
for the Pi in the truck if one isn't already on hand. Everything below waits
for the trial's purchase decision (3.5.7), except the display cable, which you
already have if the display runs on the Pi 5.

| Item | Note |
|---|---|
| mini-box DCDC-USB | Chosen 2026-11-04 instead of the CarPiHAT PRO 5 (ADR-0013) |
| I2S DAC HAT (DAC8x), a 5-way camera switch | The CarPiHAT's other jobs (ADR-0013, ADR-0014, ADR-0024). No opto board and no amplifier-remote part since 2026-11-09 |
| USB candleLight CAN adapter | Bought 2026-11-03 (ADR-0012) |
| 22→15-way display FFC | Display type, **not** a camera cable |
| OBD-II Y-splitter and DLC breakout | |
| USB GNSS receiver | u-blox based |
| USB SSD, or a confirmed-compatible NVMe base | |
| External inline fuse and TVS | |
| Rotary encoder | For the volume knob |
| Cameras and capture | Chosen in Phase 6 |
| Amplifier | Only after inspecting the existing ones |

The camera hardware and the amplifier are chosen later because they depend on
inspection and measurement.
