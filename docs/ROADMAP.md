# Roadmap

This checklist tracks progress against [PROJECT_PLAN.md](PROJECT_PLAN.md).
Step numbers match the plan.

Legend:

- `[x]` done
- `[~]` done, with a caveat noted
- `[ ]` not started

Tags:

- **[SIM]** runs in simulation only
- **[HW]** needs hardware
- **[HUMAN]** needs a person to check it

## Phase 0 — Repository migration ✅ (2026-11-01)

- [x] 0.1 Branch `feat/agl-pivot`
- [x] 0.2 Firmware moved with `git mv` to `firmware/esp32/`. The Torque export
      is at `shared/signals/imports/torque/`
- [x] 0.3 Docs regrouped into `docs/esp32/` and `docs/diagnostics/`, links fixed
      (`make docs-lint`: 0 broken)
- [x] 0.4 `pio test -e native`: 140/140 pass. `pio run -e esp32dev` builds.
      History follows the moved files

## Phase 1 — Architecture, documentation, development environment

- [x] 1.1 `CLAUDE.md`
- [x] 1.2 `README.md` rewritten for the head unit
- [x] 1.3 Architecture docs and ADRs 0001–0010 (`docs/architecture/`)
- [x] 1.4 Hardware compatibility matrix, open questions, shopping list, bench log
- [x] 1.5 Safety assumptions
- [~] 1.6 `Makefile`, `rust-toolchain.toml` (Rust 1.99.1) and `.fvmrc` (Flutter 3.38.3),
      macOS and Linux build-host setup docs. `make setup` succeeds on the development
      Mac (2026-11-01). Xcode 27.2 is installed but not selected with `xcode-select`. The
      Makefile sets `DEVELOPER_DIR` for Xcode builds, and `make setup` prints the
      one-line `sudo xcode-select -s` fix. CocoaPods isn't needed, since the app has no
      plugins
- [x] 1.7 This roadmap
- [x] 1.8 CI in `.github/workflows/ci.yml` (docs, firmware, plus Rust, proto and
      Flutter jobs that activate when those components exist). First run was green
      on 2026-11-01 ([run 41369789926](https://github.com/darickc/TruckDashboard/actions/runs/41369789926)).
      The Rust, proto and Flutter jobs only reported "skip" so far. The vcan
      integration job is deferred to Phase 3, since there is no Linux code to test yet

## Phase 2 — Simulated dashboard [SIM] ✅ (2026-11-01)

- [x] 2.1 Scenario format `f250.scenario.v1` (`simulator/powerstroke`). Six scenarios,
      including the EOT/ECT freeze, link loss, FICM sag and bad responses
- [x] 2.2 Flutter app `apps/infotainment`: an 800×480 layout that letterboxes in any
      dev window, day and night themes. Platforms are macOS and web (preview)
- [x] 2.3 `VehicleDataSource` plus `SimulatedVehicleDataSource`. The gRPC source is
      not written; it arrives in Phase 3 rather than shipping as a stub
- [x] 2.4 Shell: status bar (SIMULATED badge, link state, clock), a global alert
      banner that can't be dismissed, and the nav bar
- [x] 2.5 Digital, circular and compact gauges. Stale gauges show the hatch,
      last-good value and age. An unverified definition gets a badge
- [x] 2.6 Home, Gauges (engine and towing profiles from JSON), Diagnostics (signals,
      link, DTCs, events, developer). Media, Navigation and Cameras say plainly
      that they are not implemented
- [x] 2.7 Warnings with hysteresis, minimum duration and gates, from
      `assets/config/warning_rules.json`, labelled as examples
- [x] 2.8 Tests: 99 app tests (unit, scenario playback, 800×480 layout across
      5 situations × 2 themes, touch targets, navigation, alert visibility, stale
      rendering) and 27 simulator tests
- [x] Fuel level (`22 16 C1` from the Torque export, **unverified**) on Home and in the
      towing profile. Computed values now inherit UNVERIFIED from their inputs, and
      compact rows show the badge
- [x] Per-signal calibration (`raw × scale + offset`), configured in
      `assets/config/calibration.json`, with a live speed-scale control under
      Developer. Speed is back on the Home summary and in the towing profile, in the
      slot EGT had (no probe installed). Profiles can show one extra signal at the
      right of the selector row (`"header"` in `gauge_profiles.json`); towing shows RPM Procedure:
      [CALIBRATION.md](diagnostics/CALIBRATION.md). The factor has not been measured
      on the truck yet; it ships at ×1.0
- [x] Checked by eye in a browser (`make ui-web`). The macOS app builds with Xcode 27.2
      (deployment target raised to 12.0, Xcode 27's minimum) and launches in an
      800×480 window (2026-11-01). Nothing has run on the Pi

## Phase 3 — Vehicle-data backend [SIM] ✅ (2026-11-01)

The build order followed the MX+ trial ([ADR-0011](architecture/adr/0011-mx-plus-trial-first.md)).
How to run it: [setup/gateway.md](setup/gateway.md).

- [x] 3.1 Protos `f250.vehicle.v1` (VehicleService, DiagnosticsService), buf lint clean; Rust and Dart codegen
- [x] 3.2 `crates/telemetry`: registry, units, formula grammar, calibration, validity/staleness, computed signals, link state, warnings (123 tests)
- [x] 3.3 `shared/signals/` seeded from the Dart catalog, SAE J1979 and the Torque export only; trans_temp is the only VERIFIED_ON_TRUCK signal
- [ ] 3.4 `tools/pid-importer` CLI: deferred until after the trial. The formula translator it needs exists (all 55 Torque rows translate)
- [x] 3.5 `crates/elm`: sans-IO port of the C++ client with every C++ test, the real captures, the allow-list and ATRV (96 tests)
- [x] 3.6 Transports: simulated (Rust port of the scenario engine, matches Dart on 38,520 golden observations) and OBDLink (serial / TCP / RFCOMM feature). SocketCAN moved to 4.1
- [x] 3.7 Scheduler: priority, throughput budget, starvation guard, probe budget
- [x] 3.8 Recovery: per-PID (ACTIVE → SUSPECT → BACKOFF → QUARANTINED) and per-link (connect / reset / reconnect ladder, capped jittered backoff, FAULT)
- [x] 3.9 Event history and the health API (gateway and store events, ListEvents, Stats)
- [x] 3.10 `services/recorder`: SQLite in WAL mode, retention by age and rows, CSV export; checked live against the gateway
- [x] 3.11 App gateway mode (`VEHICLE_SOURCE=gateway`) with its own feed watchdog; `make sim`
- [x] 3.12 Tests: 300 Rust tests, a fake ELM adapter replaying the truck's captures, and app integration tests against the real gateway binary. All 300 also pass on Linux arm64 (Docker, the Pi 5's architecture), and the gateway builds there with the BlueZ RFCOMM feature (`make linux-test`, 2026-11-01). The vcan job moves to Phase 4 with SocketCAN
- [x] 3.13 `tools/obd-console`: pids, on/off, probe, raw, stats, events, with a transcript file
- [x] 3.14 Flutter Linux target added (800×480, `F250_FULLSCREEN=1`). Built and run on the Pi 5 under `cage`, with no display attached **[BENCH]** (2026-11-01, H17 closed)

Found along the way:

- The ESP32-era poll intervals ask more of the MX+ than it delivers, so low priorities stretch, honestly reported. Retune them from the 3.5.4 throughput measurement ([setup/gateway.md](setup/gateway.md#known-issue-the-poll-intervals-ask-too-much-of-the-mx))
- Fixed: a disabled watched signal marked the link degraded (Rust and Dart)
- Fixed: after a timeout the ELM client sent a bare CR, which the adapter answers by repeating the last command, so later replies paired with the wrong request (seen on the truck 2026-11-02; [bench-log](hardware/bench-log.md)). It now waits for the late prompt, then probes with `ATI` **[SIM]**. The ESP32 firmware still sends the bare CR
- Fixed: the browser build's simulated values differed from the VM's (32-bit hashing)

## Phase 3.5 — MX+ truck trial (nothing to buy) [HW] [HUMAN]

- [x] 3.5.1 Raspberry Pi OS on the Pi 5. Display, touch and ribbon confirmed. `tools/pi/setup-raspios.sh`, `make pi-run`.
      The scripts and `make pi-setup` / `pi-build` / `pi-run` exist ([setup/raspberry-pi.md](setup/raspberry-pi.md)).
      On the Pi (Raspberry Pi OS Lite, no display yet): setup, build and the whole stack under `cage` on a virtual display
      work **[BENCH]** ([bench-log](hardware/bench-log.md)). The original 7" display shows the console on DSI1 with stock
      `config.txt`, no HAT fitted; touch works and `make pi-run` fills the screen under `cage` **[BENCH]** (2026-11-02).
      The ribbon fit with the DAC HAT (H3) is left to its arrival
- [ ] 3.5.2 MX+ paired (`00:04:3E:85:EA:FC`, Secure Simple Pairing: confirm the shown passkey, no PIN). Phone and ESP32 disconnected. Opt-in recorded in `bench-log.md`
- [ ] 3.5.3 Temporary truck setup: USB-C power (5 V / 5 A preferred), secure mount, shutdown before key-off.
      Dashboard **Power** button (confirm, then clean stop and `systemctl poweroff`; [setup/raspberry-pi.md](setup/raspberry-pi.md#power)) works on the Pi **[BENCH]** (2026-11-02, [bench-log](hardware/bench-log.md)).
      Still open: power supply and mount in the truck
- [ ] 3.5.4 Driveway session: `TRUCK_SESSION.md` Parts 1–4 through `obd-console`, transcripts in `VERIFICATION_LOG.md`
- [ ] 3.5.5 Speed calibration factor measured against GPS
- [ ] 3.5.6 Logged drives: Torque-style polling and the budgeted schedule, with `ATRV` voltage and STN chatter logged
- [ ] 3.5.7 `docs/diagnostics/mx-plus-trial.md`: hypotheses eliminated, recovery results, throughput, **purchase decision**

## Phase 4 — CAN hardware communication [HW] [HUMAN]

Starts after the purchase decision in 3.5.7. The USB CAN adapter was bought
early (2026-11-03, [ADR-0012](architecture/adr/0012-direct-can-usb-adapter.md)),
so 4.1, 4.3, 4.5 and 4.7 can run with it.

- [ ] 4.1 Bench bring-up plus the gateway's SocketCAN transport. **Resolve the CAN termination** (the adapter's switch)
      Done `[SIM]`: `--transport can` (single-frame ISO-TP on a raw SocketCAN socket), `tools/pi/can.sh`
      (listen-only by default, `active` on request, capture), tests against an in-memory bus replaying
      the truck's captures; compiled and unit-tested on the Pi 5. Adapter arrived with slcan firmware,
      which can't do listen-only; flashed with Candlelight 2.5, now `can0` under `gs_usb`, listen-only accepted `[BENCH]`. Terminator and
      breakout checked on the bench. Still open: the ≈ 60 Ω checks at the truck's DLC, [docs/setup/can.md](setup/can.md)
- [ ] 4.2 `tools/can-monitor`
- [ ] 4.3 Stage A: passive census on the truck, plus the turn-signal/reverse event captures (H14)
- [ ] 4.4 Stage B: corroborated broadcast decoders
- [ ] 4.5 Stage C: ISO-TP diagnostics (opt-in). Our own single-frame ISO-TP instead of kernel `can-isotp` (ADR-0012)
- [ ] 4.6 Stage D: transport switching and the no-simultaneous-transmit rule, MX+ and CAN both present
- [ ] 4.7 Dropout experiment (listen-only CAN capture while the MX+ polls)
- [ ] 4.8 Finish whatever 3.5 left open in `TRUCK_SESSION.md`, over direct CAN

## Phase 5 — AGL deployment [HW]

Guide: [setup/agl.md](setup/agl.md). Nothing in this phase has run on the AGL
image yet.

- [~] 5.1 Release confirmed: **Vimba 22.0.1** (2026-11-02), pinned with its SHA-256 in
      `agl/configurations/vimba.env`, `make agl-image` fetches and checks it ([ADR-0001](architecture/adr/0001-agl-release.md)).
      Still open: **the build host** (ADR-0004), needed for 5.4 only
- [~] 5.2 Done `[SIM]`: `agl/boot/config-f250.txt` (DSI panel, RTC charging, DAC8x commented
      until fitted; no CAN overlay: the adapter is USB), the logind power-key drop-in, and
      `agl/scripts/stage1-setup.sh` (apply, `--check`, `--restore-demo`; 79 tests in `make agl-test`).
      `agl/scripts/diagnose-display.sh` collects DRM connectors, dmesg, the I2C devices, input,
      backlight sysfs and the compositor's logs. Found in the image's sources: its networkd
      config would put the CAN adapter in normal mode, and a KUKSA provider reads `can0`; both are
      overridden first ([ADR-0015](architecture/adr/0015-agl-can-defaults.md)).
      Still open: flash, boot and the ten checks in [agl.md](setup/agl.md#5-bring-up-checks-phase-52) **[HW]**
- [~] 5.3 Fallback procedure written ([agl.md §6](setup/agl.md#6-fallback-is-it-the-hardware-or-agl)): the same
      diagnose script on both cards, a fault table, HDMI0, `--restore-demo`. Not exercised
- [ ] 5.4 `agl/meta-f250`: waits for the build host. The Stage 1 files in `agl/rootfs/` are written to be reused by it
- [~] 5.5 `make deploy PI=` (arm64 Docker build, engine-version check, copy, setup), `make deploy-build`,
      `make logs PI=`, `make agl-image`, flashing docs. The arm64 build works on the Mac; the gateway,
      recorder and `obd-console` ran against each other in an arm64 container `[SIM]`
      ([ADR-0016](architecture/adr/0016-stage1-sideload-layout.md)). Not run against the Pi

## Phase 6 — Infotainment

- [ ] 6.1 audio-manager (A2DP sink, AVRCP, pairing window), and the PipeWire filter-chain for the DAC8x: crossover, fader, sub level ([ADR-0014](architecture/adr/0014-multichannel-dac8x.md))
- [ ] 6.2 DAC mute sequencing (H6) and the crash test with the amps on (H5). The amps' remote is on ACC through a delay-on timer, not the Pi ([ADR-0014](architecture/adr/0014-multichannel-dac8x.md)). Wiring design: [wiring/audio.md](wiring/audio.md)
- [ ] 6.3 Volume knob
- [ ] 6.4 GPS
- [ ] 6.5 Offline map, then routing, then the update workflow
- [ ] 6.6 camera-manager and the ADR-0009 spike
- [ ] 6.7 power-manager: the DCDC-USB power key and USB telemetry, the reverse input ([ADR-0013](architecture/adr/0013-dcdc-usb-power-supply.md))

## Phase 7 — Installation and reliability [HW] [HUMAN]

- [ ] 7.1 Wiring diagrams
- [ ] 7.2 Electrical validation
- [ ] 7.3 Thermal validation
- [ ] 7.4 Communication stress tests
- [ ] 7.5 Acceptance checklist and troubleshooting guide
