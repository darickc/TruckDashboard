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

- Fixed: the ESP32-era poll intervals asked ~54 requests/s of a ~16/s link, so most signals ran on the starvation guard. They are now budgeted from the 3.5.4 throughput measurement: the default enabled set asks under 80 % of each transport's budget ([ADR-0019](architecture/adr/0019-poll-intervals-budgeted.md), [setup/gateway.md](setup/gateway.md#poll-intervals-and-the-throughput-budget)) **[SIM]**
- Fixed: a disabled watched signal marked the link degraded (Rust and Dart)
- Fixed: after a timeout the ELM client sent a bare CR, which the adapter answers by repeating the last command, so later replies paired with the wrong request (seen on the truck 2026-11-02; [bench-log](hardware/bench-log.md)). It now waits for the late prompt, then probes with `ATI` **[SIM]**. The ESP32 firmware still sends the bare CR
- Fixed: the browser build's simulated values differed from the VM's (32-bit hashing)

## Phase 3.5 — MX+ truck trial (nothing to buy) [HW] [HUMAN]

- [x] 3.5.1 Raspberry Pi OS on the Pi 5. Display, touch and ribbon confirmed. `tools/pi/setup-raspios.sh`, `make pi-run`.
      The scripts and `make pi-setup` / `pi-build` / `pi-run` exist ([setup/raspberry-pi.md](setup/raspberry-pi.md)).
      On the Pi (Raspberry Pi OS Lite, no display yet): setup, build and the whole stack under `cage` on a virtual display
      work **[BENCH]** ([bench-log](hardware/bench-log.md)). The original 7" display shows the console on DSI0 with stock
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

Parked (the MX+ isn't in the final build, which uses the USB CAN adapter; owner, 2026-11-07):

- MX+ EOT misses, about 1 in 100 polls: the ELM closes its window after the TCM's early refusal, before the
  PCM's answer (seen on the wire, [CAN_CENSUS](diagnostics/CAN_CENSUS.md) capture 6). Untried fix: send an
  `ATCRA` receive filter (e.g. `ATCRA7E8`) for requests whose signal pins an `rx_id`, so the adapter ignores
  other modules and waits for the owner. `crates/elm` already sends `ATSH`/`ATCRA` from a request's
  `Addressing`; the gateway would set `rx_filter` from `rx_id`. Costs an extra AT command when the filter
  changes. Needs a truck test. Until then the 7E8 pin makes each miss one `SUSPECT` reading

## Phase 4 — CAN hardware communication [HW] [HUMAN]

Starts after the purchase decision in 3.5.7. The USB CAN adapter was bought
early (2026-11-03, [ADR-0012](architecture/adr/0012-direct-can-usb-adapter.md)),
so 4.1, 4.3, 4.5 and 4.7 can run with it.

- [ ] 4.1 Bench bring-up plus the gateway's SocketCAN transport. **Resolve the CAN termination** (the adapter's switch)
      Done `[SIM]`: `--transport can` (single-frame ISO-TP on a raw SocketCAN socket), `tools/pi/can.sh`
      (listen-only by default, `active` on request, capture), tests against an in-memory bus replaying
      the truck's captures; compiled and unit-tested on the Pi 5. Adapter arrived with slcan firmware,
      which can't do listen-only; flashed with Candlelight 2.5, now `can0` under `gs_usb`, listen-only accepted `[BENCH]`. Terminator and
      breakout checked on the bench; DLC 6–14 ≈ 62 Ω; 6–14 still ≈ 60 Ω with the adapter connected; listen-only captures on the truck `[TRUCK]`.
      The "dropouts" were the Pi's wall clock jumping forward after boot (no RTC battery), not lost frames;
      capture now checks the wall clock against the monotonic one. Wiring signed off (5V terminal
      unconnected, 2026-11-07). Still open: the loopback test, [docs/setup/can.md](setup/can.md)
- [ ] 4.2 `tools/can-monitor`
      Capture side is `tools/pi/can.sh` (listen-only, bitrate, candump with error frames, counters, gap report).
      Analysis `[SIM]`: `tools/can-monitor census|pids|correlate` reads candump logs, decodes PID answers with
      the signal registry and fits broadcast fields against them; tested on synthetic logs and run on the truck
      captures. Still open: bounded capture files, CSV export, a two-capture diff
- [ ] 4.3 Stage A: passive census on the truck, plus the reverse/brake event captures (H14)
      Captures at key on, idle and driving `[TRUCK]`: the same 14 IDs, 712 frames/s, no errors; `4FF`
      carries the VIN (check digit validates). Candidates: reverse/gear (`230`, `420`), brake (`440`), RPM
      (`201`), wheel speeds (`215`). Turn signals: not on the bus, an analogue flasher-relay circuit (owner): opto inputs. Reverse/brake captures still to do. [CAN_CENSUS.md](diagnostics/CAN_CENSUS.md)
- [ ] 4.4 Stage B: corroborated broadcast decoders
      First corroboration drive `[TRUCK]` (MX+ beside a listen-only capture, 2026-11-07): RPM (`201`), speed
      (`201`), ECT (`420`), load (`106`) and trans temp (`225`) match the PIDs with exact scalings. Needs a second
      drive and VERIFICATION_LOG entries before any decoder. [CAN_CENSUS.md](diagnostics/CAN_CENSUS.md)
- [ ] 4.5 Stage C: ISO-TP diagnostics (opt-in). Our own single-frame ISO-TP instead of kernel `can-isotp` (ADR-0012)
      First truck session `[TRUCK]` 2026-11-07: the gateway polled over `can0` alone, 97 s idle, 16.2 req/s
      (MX+: 11.7), no transmit or bus errors, EOT 173 of 173. One IAT miss: the PCM skips a request sent while it
      is still answering the previous one (after an early-returning pinned request; ADR-0012).
      First drives `[TRUCK]` 2026-11-07 (2 × ~8 min, up to 79 km/h): no bus errors, but EOT and trans temp were
      quarantined 9 times for 60 s each. A late refusal meant for one pinned request was read as the next one's
      answer. Fixed `[SIM]`: pinned requests wait for every module's answer, and one stray refusal no longer
      quarantines a PID that has answered. Still open: a drive with the fix, physical addressing
      (`7E0`/`7E1`), `obd-console raw` over CAN
- [ ] 4.6 Stage D: transport switching and the no-simultaneous-transmit rule, MX+ and CAN both present
- [x] 4.7 Dropout experiment (listen-only CAN capture while the MX+ polls) `[TRUCK]` 2026-11-07: the PCM's EOT answer
      was on the bus (+39.5 ms); the MX+ closed its window after the TCM's refusal (+6.4 ms). 1 of 104. Possible MX+
      fix (`ATCRA` for pinned requests) untested. [CAN_CENSUS.md](diagnostics/CAN_CENSUS.md)
- [ ] 4.8 Finish whatever 3.5 left open in `TRUCK_SESSION.md`, over direct CAN

## Phase 5 — AGL deployment [HW]

Guide: [setup/agl.md](setup/agl.md). Stage 1 runs on the Pi with AGL 22.0.1
**[BENCH]** (2026-11-06). The build host is a VM on the Mac, kept in `~/agl-build-vm` (moved
off the external hard disk on 2026-11-07; ADR-0004 amendment); it built AGL 22.0.1 from source on 2026-11-07, and that image boots and runs Stage 1 **[BENCH]**.

- [~] 5.1 Release confirmed: **Vimba 22.0.1** (2026-11-02), pinned with its SHA-256 in
      `agl/configurations/vimba.env`, `make agl-image` fetches and checks it ([ADR-0001](architecture/adr/0001-agl-release.md)).
      Build host (ADR-0004, needed for 5.4 only): `make build-vm` makes an aarch64 Ubuntu VM on the Mac with its disk
      in `~/agl-build-vm`; `make agl-build` fetches the pinned 22.0.1 layers and runs BitBake. First full build
      `[BENCH]` 2026-11-07: `agl-ivi-demo-flutter` built from source (about 12¾ h on a 5,400 rpm USB disk, 116 GB
      used); it boots on the Pi and passes `stage1-setup.sh --check` ([linux-build-host.md](setup/linux-build-host.md), [bench log](hardware/bench-log.md))
- [~] 5.2 Done `[SIM]`: `agl/boot/config-f250.txt` (DSI panel; RTC charging, NVMe PCIe and
      DAC8x lines commented until the cell and those HATs are fitted; no CAN overlay: the adapter is USB), the logind
      power-key drop-in, and `agl/scripts/stage1-setup.sh` (apply, `--check`, `--restore-demo`;
      130 tests in `make agl-test`). Optional data drive (`DATA_DRIVE=1`, `f250-storage`): the
      telemetry database and traffic logs on an NVMe HAT or USB SSD; no NVMe boot on this image.
      `agl/scripts/diagnose-display.sh` collects DRM connectors, dmesg, the I2C devices, input,
      backlight sysfs and the compositor's logs. Found in the image's sources: its networkd
      config would put the CAN adapter in normal mode, and a KUKSA provider reads `can0`; both are
      overridden first ([ADR-0015](architecture/adr/0015-agl-can-defaults.md)).
      **On the Pi [BENCH] (2026-11-06):** 22.0.1 boots, `make deploy` and `--check` pass, and the dashboard
      runs fullscreen on the 7" panel with touch (checks 1, 2, 3, 5; the overlay needed `,dsi0`). The dashboard
      and agl-compositor restart as a pair: the compositor aborts on a second homescreen client (ADR-0016 addendum).
      Also passed: 7 (Power button), 8 (CAN listen-only with the adapter), 9 (RTC, no cell yet).
      The journal is now kept on the SD card (50 MB cap), so `journalctl -b -1` works after a reboot.
      Checks 4 (backlight) and 6 (gateway, recorder) pass too. Still open: 10–11 once those HATs arrive
      ([agl.md](setup/agl.md#5-bring-up-checks-phase-52))
- [~] 5.3 Fallback procedure written ([agl.md §6](setup/agl.md#6-fallback-is-it-the-hardware-or-agl)): the same
      diagnose script on both cards, a fault table, HDMI0, `--restore-demo`. Not exercised
- [~] 5.4 `agl/meta-f250` ([ADR-0017](architecture/adr/0017-meta-f250-layer.md)): image `agl-f250` = the Flutter demo
      image without its homescreen, plus `f250-system` (Stage 1's steps as files: units, CAN masks, user, journal,
      `config.txt` block), `f250-services` (Rust 1.96.1 from the AGL tree; crate list from `Cargo.lock`) and
      `f250-dashboard` (meta-flutter's `flutter-app`). Same paths as Stage 1, built from a commit. `[BENCH]` 2026-11-08: built
      from f16fc60, boots, `--check` passes with nothing sideloaded ([bench log](hardware/bench-log.md)). Then
      ([ADR-0021](architecture/adr/0021-trimmed-dev-and-release-images.md)): two trimmed images on AGL's compositor
      image, `agl-f250` (development) and `agl-f250-release` (root locked, SSH by key only), root's key built in,
      `make build-vm CMD=image`. Both built from 33d8324. `[BENCH]` 2026-11-08: the development image boots,
      `--check` passes, gateway/recorder/dashboard/avahi run, oFono is off. Units sandboxed (ADR-0021 §10;
      `systemd-analyze security` gateway 6.8 → 1.6, recorder 5.3 → 0.2, dashboard 9.2 → 0.6, sim transport).
      The release image boots too: root by key only, every password login refused, no debug tools.
      Still to do: boot the sandboxed release image (759f807); the gateway's sandbox with the `obdlink` and
      `can` transports; Bluetooth is off under connman (the MX+ needs it on).
      No kernel fragment or udev rules yet: each comes with its feature.
      Done ahead of it: the service watchdogs. `crates/sd-notify` (systemd's notify protocol, no `unsafe`); the
      gateway and recorder are `Type=notify` with `WatchdogSec=60` / `30`, and send keep-alives only while their loops
      make progress ([diagnostic-recovery.md](architecture/diagnostic-recovery.md)). The recorder's waits on the gateway
      are bounded, so a stuck gateway makes it reconnect instead of hang. On the Pi **[BENCH]** (2026-11-06): a frozen
      gateway was killed and restarted by systemd in under a minute, and the dashboard and recorder recovered
      ([bench-log](hardware/bench-log.md))
- [~] 5.5 `make deploy PI=` (arm64 Docker build, engine-version check, copy, setup), `make deploy-build`,
      `make logs PI=`, `make agl-image`, flashing docs. The arm64 build works on the Mac; the gateway,
      recorder and `obd-console` ran against each other in an arm64 container `[SIM]`
      ([ADR-0016](architecture/adr/0016-stage1-sideload-layout.md)). `make deploy` works against the Pi with AGL 22.0.1
      **[BENCH]** (2026-11-06, several deploys), and so does `make logs`

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
