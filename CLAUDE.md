# CLAUDE.md

Guidance for Claude Code sessions in this repository. Read this first, then
[docs/PROJECT_PLAN.md](docs/PROJECT_PLAN.md) for the phase you are in and
[docs/ROADMAP.md](docs/ROADMAP.md) for what is done.

## What this project is

A Raspberry Pi 5 head unit running Automotive Grade Linux (AGL), built for one
truck: a **2007 Ford F-250 with the 6.0L Power Stroke**. It replaces the
aftermarket radio. It provides telemetry, media, navigation, cameras and logging.
The factory cluster and every safety system stay independent of it.

The ESP32 firmware in `firmware/esp32/` came first. It is now the auxiliary I/O
controller. Its on-truck findings are the most trustworthy vehicle data the
project has.

## Non-negotiable rules

### Vehicle data

1. **Never invent Ford CAN IDs, DIDs, formulas, response formats, device-tree
   settings or hardware compatibility claims.** If something is unknown, write
   **TODO** or **UNVERIFIED** and say how to verify it.
2. **Keep three claims apart:**

   | Claim | Meaning |
   |---|---|
   | `SAE` | Published J1979 formula |
   | `IMPORTED_UNVERIFIED` | From the Torque export, so the formula is untrusted |
   | `VERIFIED_ON_TRUCK` | Has an entry in [docs/diagnostics/VERIFICATION_LOG.md](docs/diagnostics/VERIFICATION_LOG.md) |

   Agreement with Torque proves the transport works, not the scaling.
3. **Read-only vehicle access (ADR-007).**
   - Nothing transmits on the vehicle bus at boot.
   - Passive or listen-only is the default.
   - Diagnostic transmit needs an explicit config opt-in.
   - Write, control, flash, routine and DTC-clear services are refused in code.
   - Never implement ECU programming, immobilizer bypass or actuator control.
4. **Stale data is never shown as current.** Show the last good value, its age,
   and a visible stale warning. Computed signals (EOT−ECT delta, boost) are only
   valid while every input is valid.
5. **The UI never talks to CAN or adapters.** All vehicle I/O goes through
   `services/vehicle-gateway` and its versioned API.
6. **Never connect 12 V vehicle signals to Pi GPIO.** Use protected or
   opto-isolated inputs. Any wiring change is documented in `docs/wiring/` and
   needs a person to verify it before installation.

### Honesty about testing

7. **Never claim hardware testing that didn't happen.**
   - Mark results `[SIM]` (simulated), `[BENCH]` or `[TRUCK]`.
   - A feature is "hardware-tested" only with a log entry in `docs/hardware/` or
     `docs/diagnostics/`.
8. **No placeholders that look like working code.** Unimplemented screens and
   services say so on screen or in the log.
9. **Keep the simulator working.** The default test suite never needs the truck
   or any hardware.

### Thresholds

10. **Warning thresholds are configuration, labelled as examples.** Never encode
    a threshold as universally correct.

## Layout

```
firmware/esp32/      PlatformIO firmware (C++17); auxiliary controller, ELM reference implementation
shared/signals/      signal registry (YAML); imports/torque/exportedPIDs.csv
shared/proto/        versioned gRPC/protobuf API (f250.<domain>.v1); `make proto` regenerates Dart
crates/              Rust libraries: elm (MX+ client), telemetry, powerstroke-sim, proto, sd-notify, camera-policy
services/            Rust daemons: vehicle-gateway, recorder, power-manager, camera-manager (audio in Phase 6)
apps/infotainment/   Flutter UI, 800×480 (simulated data source today)
simulator/           Power Stroke scenarios (f250.scenario.v1) + Dart engine; Rust transport in Phase 3
agl/                 AGL Stage 1: release pin, boot config, rootfs files, target scripts; meta-f250 in 5.4
tools/               pid-importer, can-monitor, diagnostics, dev/ helpers
docs/                architecture/ (ADRs), hardware/, wiring/, setup/, safety/, diagnostics/, esp32/
```

Libraries go in `crates/` and daemons in `services/` (ADR-008).

## Commands

| Command | What it does |
|---|---|
| `make help` | List targets |
| `make setup` | Install and check development tools on macOS (Homebrew) |
| `make test` | Every test available in this environment |
| `make lint` | Link check, plus Rust/Flutter/proto lint once those exist |
| `make fw-test` | ESP32 host tests (`pio test -e native`) |
| `make fw-build` | ESP32 firmware build |
| `make sim-test` | Scenario simulator tests (Dart) |
| `make ui-test` / `make ui-lint` | Flutter tests / analyzer |
| `make ui-web` | Dashboard in a browser at http://127.0.0.1:8250. Add `SCENARIO=<id> START=<s>` to jump into a scenario |
| `make sim` | Rust gateway (simulated) + macOS app over gRPC. `make gateway` / `make console` run the gateway or `obd-console` alone |
| `make rust-test` / `make rust-lint` | Cargo workspace tests / fmt + clippy (needs `protoc`) |
| `make pi-setup` / `pi-build` / `pi-run` | On the Pi (Raspberry Pi OS, Phase 3.5): install the tools, release-build, run gateway + recorder + app. `pi-run` uses the simulator unless `TRANSPORT=obdlink` or `TRANSPORT=can`, and polls only with `TRANSMIT=1`. `CAPTURE=1` also candumps `can0` into the session. See [docs/setup/raspberry-pi.md](docs/setup/raspberry-pi.md) |
| `make pi-start` / `pi-stop` / `pi-status` | On the Pi, over SSH: `pi-run` as a transient systemd service on tty7 (an SSH login has no seat, so `cage` can't take the screen from it) |
| `make pi-can CMD=status\|listen\|active\|down\|capture\|flash` | On the Pi: the USB CAN adapter (`tools/pi/can.sh`; listen-only unless `active`). Then `TRANSPORT=can` for `pi-run`/`pi-start`. See [docs/setup/can.md](docs/setup/can.md) |
| `cargo run --release -p can-monitor -- census\|pids\|correlate LOG` | Analyse a `candump` log offline: census, PID answers decoded with the registry, broadcast-vs-PID fits. See [docs/setup/can.md](docs/setup/can.md#analysing-a-capture) |
| `make ui` / `make ui-macos-build` | Dashboard as a macOS window / just build it (needs Xcode; the Makefile sets `DEVELOPER_DIR` if `xcode-select` points at the Command Line Tools) |

Also: `make proto` (regenerate the Dart gRPC client) and `make linux-test` (Rust
in Docker, including the RFCOMM build). AGL: `make agl-image`, `make deploy PI=<host>`
(`deploy-build` to build only), `make logs PI=<host>`, `make agl-test`; see
[docs/setup/agl.md](docs/setup/agl.md). Yocto builds: `make build-vm` (a Lima VM
kept entirely in `~/agl-build-vm`) and `make agl-build`;
see [docs/setup/linux-build-host.md](docs/setup/linux-build-host.md).
How to run the gateway, the MX+ flags and the recorder: [docs/setup/gateway.md](docs/setup/gateway.md).

Test and lint targets for components that don't exist yet print `skip:` and exit 0.
Run targets exit non-zero until their phase lands, or when their inputs are
missing (`deploy` and `logs` without `PI=`). No target pretends to have run.

## Toolchain pins

| Tool | Pin | Why |
|---|---|---|
| Flutter | **3.38.3** (`.fvmrc`) | Matches the engine in the AGL Vimba 22.0.0 Pi 5 image |
| Rust | `rust-toolchain.toml` | |
| AGL | Vibrant Vimba 22.0.x, Yocto 6.0 "Wrynose" | ADR-001 |

Yocto builds need a Linux x86_64 host (ADR-004), not the Mac.

## Testing expectations

- Run the relevant tests after every meaningful change. Run `make test` before
  committing.
- New logic ships with tests:
  - parsers and decoders: test vectors, using verified captures where they exist
  - state machines: every transition
  - UI: 800×480 layout, touch targets ≥ 60 px, alerts visible on every screen
- Simulate faults rather than skipping them: stale PIDs, link loss, invalid
  frames.

## Working conventions

- Inspect before changing. Verify external facts against current official
  documentation, and record the source and status (verified, forum, unverified,
  conflicting) in `docs/hardware/compatibility-matrix.md` or an ADR.
- Record significant decisions as ADRs in `docs/architecture/adr/`.
- Update `README.md`, `docs/ROADMAP.md` and the relevant docs when the
  architecture or status changes.
- Use conventional commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`,
  `build:`, `ci:`).
- Commit when a step is complete and tested. Never push unless asked.
- Ask the owner only about real hardware details or irreversible decisions.
  Decide routine software choices and document them.
