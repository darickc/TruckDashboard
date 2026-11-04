# Architecture overview

Status: **design.** Phase 1 wrote this design. Components are marked with the
phase that implements them. Nothing here is hardware-tested unless it says so.

Related:

- [telemetry model](telemetry-model.md)
- [diagnostic recovery](diagnostic-recovery.md)
- [power states](power-states.md)
- [camera policy](camera-policy.md)
- [audio routing](audio-routing.md)
- [ADRs](adr/)

## Principles

1. **Hardware, services and UI are separate layers.** The UI renders data and
   sends user intents. It never opens a CAN socket, a serial port or a GPIO line.
2. **One owner per hardware resource.**
   - `vehicle-gateway` owns the vehicle bus and adapters.
   - `power-manager` owns the GPIO inputs and outputs, the power key and the
     DCDC-USB's USB link.
   - `camera-manager` owns the V4L2 devices.
   - `audio-manager` owns the BlueZ policy.
3. **Versioned interfaces.** Protobuf packages are named `f250.<domain>.v1`.
   Breaking changes create `v2` alongside `v1`, and `buf breaking` enforces this
   in CI.
4. **The vehicle is untrusted input.** Every frame is length-checked, queues are
   bounded and logging is rate-limited (see the [trust boundaries](#trust-boundaries)).
5. **Degrade, don't die.** A failed service shows up as a status in the UI. The
   rest keeps running.

## Components

```mermaid
flowchart TB
  subgraph HW[Hardware]
    CAN[CAN controller<br/>USB gs_usb adapter]
    MX[OBDLink MX+<br/>Bluetooth SPP]
    PSU[mini-box DCDC-USB<br/>ignition · PSW → J2 · USB telemetry]
    GPIO[opto input board → GPIO<br/>REV · turn signals if not on CAN · amp remote out]
    V4L[USB/UVC cameras]
    GNSS[USB GNSS]
    BT[Bluetooth radio]
    DAC[I2S DAC → line out → amplifiers]
    ESP[ESP32 aux controller]
  end

  subgraph SVC[Rust services · systemd]
    GW[vehicle-gateway<br/>transports · scheduler · decode · health]
    REC[recorder<br/>SQLite · CSV export]
    PWR[power-manager<br/>power key · ignition telemetry · amp remote · backlight]
    CAMM[camera-manager<br/>policy · pipelines]
    AUDM[audio-manager<br/>BlueZ · PipeWire policy]
    NAV[navigation backend<br/>gpsd · Valhalla]
  end

  subgraph APP[Flutter app · agl-compositor]
    UI[infotainment<br/>Home · Gauges · Media · Nav · Cameras · Diagnostics]
  end

  CAN --> GW
  MX --> GW
  ESP --> GW
  GPIO --> PWR
  PSU --> PWR
  V4L --> CAMM
  GNSS --> NAV
  BT --> AUDM
  AUDM --> DAC

  GW -- f250.vehicle.v1 --> UI
  GW -- f250.vehicle.v1 --> REC
  PWR -- f250.power.v1 --> UI
  PWR -- inputs stream --> CAMM
  CAMM -- f250.camera.v1 --> UI
  AUDM -- f250.audio.v1 --> UI
  NAV -- f250.nav.v1 --> UI
  REC -- f250.history.v1 --> UI
```

| Component | Language | Phase | Responsibility |
|---|---|---|---|
| `crates/telemetry` | Rust | 3 | Signal model, units, registry loader, safe formula grammar, staleness, computed signals, warnings |
| `crates/elm` | Rust | 3 | ELM327/STN client, a port of the tested C++ `ElmParser`/`ElmClient` |
| `services/vehicle-gateway` | Rust | 3–4 | Transports (simulated, SocketCAN, OBDLink), scheduler, recovery, health, API |
| `services/recorder` | Rust | 3 | Telemetry and event persistence, retention, export |
| `services/power-manager` | Rust | 6 | Power state machine, GPIO ownership, amplifier remote, backlight, day/night |
| `services/camera-manager` | Rust | 6 | Camera selection policy, capture pipelines |
| `services/audio-manager` | Rust | 6 | Pairing window, A2DP sink policy, AVRCP, volume limits |
| navigation backend | Rust + Valhalla | 6 | Position, routing (ADR-010) |
| `apps/infotainment` | Flutter 3.38.3 | 2 | The 800×480 UI, using simulated data first |
| `firmware/esp32` | C++ | existing | Auxiliary I/O: EGT, volume encoder, optional MX+ bridge |

## Data flow: one sensor reading

```mermaid
sequenceDiagram
  participant S as Scheduler
  participant T as Transport (SocketCAN ISO-TP / OBDLink)
  participant D as Decoder (registry formula)
  participant M as Telemetry model
  participant U as UI
  participant R as Recorder
  S->>T: request 22 1310 (if transmit enabled)
  T-->>S: response or timeout (with responder ID, latency)
  S->>D: payload bytes
  D->>M: value + unit + provenance
  M->>M: validity, staleness, computed signals, warnings
  M-->>U: Sample stream (value, validity, age, last good)
  M-->>R: sampled at the recording interval
  Note over S,M: A timeout updates per-PID health,<br/>not the value. The age keeps growing.
```

## Processes on the target

Each service is a systemd unit. The unit names are proposed and are implemented
in Phase 5.

| Unit | User | Notes |
|---|---|---|
| `f250-power-manager.service` | dedicated, `gpio` and `input` groups, plus a udev rule for the DCDC-USB | Starts first. Handles the power key (logind `HandlePowerKey=ignore`). `WatchdogSec` |
| `f250-vehicle-gateway.service` | dedicated, CAN access | Socket at `/run/f250/vehicle.sock`. Transmit is disabled unless config opts in |
| `f250-recorder.service` | dedicated | Writes `/var/lib/f250/` only |
| `f250-camera-manager.service` | dedicated, `video` group | |
| `f250-audio-manager.service` | dedicated, `bluetooth`/`audio` | |
| `can0` setup | systemd-networkd `.network` or a oneshot unit | Brings the interface up **listen-only** by default |
| Flutter app | AGL applaunchd template | Launched by agl-compositor / applaunchd |

Every service unit gets the same hardening:

- `ProtectSystem=strict`
- `ProtectHome=yes`
- `NoNewPrivileges=yes`
- `PrivateTmp=yes`
- the minimum `CapabilityBoundingSet`
- `RestrictAddressFamilies` limited to what the service needs (`AF_UNIX`, plus
  `AF_CAN` for the gateway, `AF_BLUETOOTH` for audio)

## API transport

gRPC over **Unix domain sockets** in `/run/f250/`. Access is controlled by the
socket file mode and group (ADR-002).

During development on macOS, the same services listen on a local socket or
loopback TCP. The Flutter app picks its data source from configuration:
simulated in-process, or gRPC.

## Trust boundaries

```mermaid
flowchart LR
  subgraph Untrusted
    BUS[Vehicle CAN / K-line]
    PHONE[Paired phones · AVRCP metadata]
    USB[USB devices · map files · imported CSV]
  end
  subgraph Validated[Validation layer]
    V1[frame length/DLC checks<br/>bounded queues<br/>rate-limited logs]
    V2[pairing window<br/>metadata length limits]
    V3[schema validation<br/>formula grammar, no eval]
  end
  subgraph Core[Services + UI]
    C[telemetry model · policy · UI]
  end
  BUS --> V1 --> C
  PHONE --> V2 --> C
  USB --> V3 --> C
  C -. "transmit only if opted in<br/>read-only services only" .-> BUS
```

The only path back to the vehicle is the diagnostic request path. It is
disabled by default, restricted to read services, and rate-budgeted. See
[ADR-007](adr/0007-read-only-vehicle-access.md).

## Development and deployment topology

| Where | What runs |
|---|---|
| Mac | Flutter app (macOS desktop, 800×480 window) + Rust services with the simulated transport + firmware host tests |
| Linux CI / Docker | Same, plus Linux-only code (SocketCAN against `vcan`) |
| Linux x86_64 build host | Yocto / AGL image builds (ADR-004) |
| Pi 5 | Stage 1: the prebuilt AGL Vimba image with sideloaded binaries. Stage 2: the `meta-f250` image (ADR-005) |
