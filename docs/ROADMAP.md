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
      Mac (2026-11-01). **Xcode and CocoaPods are not installed yet.** They are needed
      for `make ui` (the macOS desktop window) in Phase 2, but not for `make ui-test`
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
- [x] 2.8 Tests: 81 app tests (unit, scenario playback, 800×480 layout across
      5 situations × 2 themes, touch targets, navigation, alert visibility, stale
      rendering) and 27 simulator tests
- [x] Fuel level (`22 16 C1` from the Torque export, **unverified**) on Home and in the
      towing profile. Computed values now inherit UNVERIFIED from their inputs, and
      compact rows show the badge
- [~] Checked by eye in a browser (`make ui-web`). **The macOS window target
      has not been run, because Xcode is not installed.** Nothing has run on the Pi

## Phase 3 — Vehicle-data backend [SIM]

- [ ] 3.1 Protos (`f250.vehicle.v1`) and buf
- [ ] 3.2 `crates/telemetry`: registry, units, formula grammar, staleness, computed signals, warnings
- [ ] 3.3 Seed `shared/signals/`
- [ ] 3.4 `tools/pid-importer`
- [ ] 3.5 `crates/elm`, ported from the C++ with its test vectors
- [ ] 3.6 Gateway transports: simulated, SocketCAN, OBDLink
- [ ] 3.7 Scheduler
- [ ] 3.8 Recovery state machines (per PID, per link)
- [ ] 3.9 Event history and the health API
- [ ] 3.10 Recorder
- [ ] 3.11 UI driven by the gateway (`make sim`)
- [ ] 3.12 Tests, plus the vcan CI job

## Phase 4 — Hardware communication [HW] [HUMAN]

- [ ] 4.1 Bench bring-up. **Resolve the CAN termination** (H1)
- [ ] 4.2 `tools/can-monitor`
- [ ] 4.3 Stage A: passive census on the truck
- [ ] 4.4 Stage B: corroborated broadcast decoders
- [ ] 4.5 Stage C: ISO-TP diagnostics (opt-in)
- [ ] 4.6 Stage D: OBDLink transport
- [ ] 4.7 Dropout experiment
- [ ] 4.8 Finish `TRUCK_SESSION.md` and promote the verified PIDs

## Phase 5 — AGL deployment [HW]

- [ ] 5.1 Confirm the build host and the release
- [ ] 5.2 Prebuilt Vimba image plus the overlays. `diagnose-display.sh`
- [ ] 5.3 HDMI / Raspberry Pi OS fallback procedure
- [ ] 5.4 `agl/meta-f250`
- [ ] 5.5 `make deploy`, flashing docs, log collection

## Phase 6 — Infotainment

- [ ] 6.1 audio-manager (A2DP sink, AVRCP, pairing window)
- [ ] 6.2 Amplifier remote and mute sequencing (H5, H6)
- [ ] 6.3 Volume knob
- [ ] 6.4 GPS
- [ ] 6.5 Offline map, then routing, then the update workflow
- [ ] 6.6 camera-manager and the ADR-0009 spike
- [ ] 6.7 power-manager

## Phase 7 — Installation and reliability [HW] [HUMAN]

- [ ] 7.1 Wiring diagrams
- [ ] 7.2 Electrical validation
- [ ] 7.3 Thermal validation
- [ ] 7.4 Communication stress tests
- [ ] 7.5 Acceptance checklist and troubleshooting guide
