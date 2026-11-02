# Running the vehicle gateway

`services/vehicle-gateway` is the only process that talks to the truck
([architecture](../architecture/overview.md)). The UI, the recorder and
`obd-console` all reach the vehicle through its gRPC API (`f250.vehicle.v1`).

Status:

- **Simulator:** tested `[SIM]` (unit, fake-adapter and app integration tests).
- **MX+:** tested against a **fake** ELM adapter that replays this truck's
  real captures. **It has not run against the real MX+ or the truck yet**;
  that is the Phase 3.5 trial.

## Quick start (simulator, on the Mac)

```bash
make sim                                           # gateway + macOS app connected over gRPC
make sim SCENARIO=eot_ect_freeze START=110         # jump into the EOT/ECT freeze
make gateway SCENARIO=link_loss                    # gateway only, on tcp:127.0.0.1:50251
make console                                       # obd-console against it
```

The simulator polls every signal its scenario models, including unverified
Ford PIDs. Nothing is transmitted anywhere, and those signals still show as
UNVERIFIED.

## With the OBDLink MX+

Disconnect the phone (Torque) and the ESP32 first. The MX+ takes one Bluetooth
master at a time.

| Host | Adapter flag | Notes |
|---|---|---|
| Raspberry Pi (Raspberry Pi OS) | `--adapter rfcomm:00:04:3E:85:EA:FC` | Build with `--features rfcomm` (needs `libdbus-1-dev`). Pair once with `bluetoothctl` (agent on, confirm the shown passkey; [bench-log](../hardware/bench-log.md)) |
| macOS | `--adapter serial:/dev/cu.<name>` | Pair the MX+ in System Settings; it appears as a `/dev/cu.*` serial port. Unverified |
| ESP32 as a USB bridge | `--adapter serial:/dev/cu.usbserial-…@115200` | Future: needs bridge firmware |
| Emulator / TCP | `--adapter tcp:host:port` | Used by the tests |

```bash
cargo run -p vehicle-gateway --release --features rfcomm -- \
    --transport obdlink --adapter rfcomm:00:04:3E:85:EA:FC \
    --transmit \
    --listen unix:/tmp/f250/vehicle.sock \
    --traffic-log ./traffic \
    --enable eot,ficm_main,battery        # opt in unverified PIDs, only if you want them polled
```

### Safety flags (ADR-0007)

| Flag | Effect |
|---|---|
| *(no `--transmit`)* | **PASSIVE_ONLY.** The adapter is never opened. Nothing reaches the vehicle. This is the default |
| `--transmit` | Polling is allowed. The gateway can only send services `01 03 07 09 22`, and it checks that in two places: the registry and the ELM client. Raw lines are checked too. Write, control, routine, clear-DTC and `ATCAF0`/`ATPP`/`ST…` commands are refused before they reach the wire |
| `--enable a,b` | Also polls these unverified signals. They stay marked UNVERIFIED in the UI and the API |

### Diagnosing with `obd-console`

```bash
make console GATEWAY=unix:/tmp/f250/vehicle.sock
obd> pids                 # every signal: provenance, poll state, validity, value
obd> raw ATDPN            # adapter protocol
obd> probe trans_temp 5   # every responder, payload, decoded value, latency
obd> raw 221310           # one allow-listed request, verbatim adapter lines
obd> stats                # per-signal success/failure, p50/p95 latency, requests/s
obd> events 30
```

Every session is also saved as `obd-console-<epoch>.log`, ready to paste into
[VERIFICATION_LOG.md](../diagnostics/VERIFICATION_LOG.md).

### Recording a drive

```bash
cargo run -p recorder --release -- run --gateway unix:/tmp/f250/vehicle.sock --db drive.sqlite
cargo run -p recorder --release -- export --db drive.sqlite --signals eot,ect > drive.csv
cargo run -p recorder --release -- export --db drive.sqlite --events > events.csv
```

There are three kinds of output:

- The recorder keeps every signal's validity, value, last-good value and age,
  poll state, responder, latency and counters at 1 Hz. It also keeps the link
  state (including `ATRV` adapter voltage) and every gateway event. Retention
  is bounded at 30 days or 2 M sample rows.
- `--traffic-log` keeps every adapter line with millisecond timestamps, in 5
  rotating files of 10 MB each.
- Together these are the evidence for the dropout analysis
  ([PROJECT_PLAN](../PROJECT_PLAN.md#what-the-mx-trial-phase-35-can-already-show)).

## Known issue: the poll intervals ask too much of the MX+

The registry's poll intervals came from the ESP32 table (MAP and ICP every
100 ms, and so on). With every signal enabled, they ask for more requests per
second than the link delivers. The MX+ measured about 10 per second on `7DF`
with two responders. The simulator budget is 15 per second.

The scheduler stretches the low priorities and reports this in
`LinkStatus.detail`. As a result, slow signals like engine load can flicker
between VALID and STALE. That is the honest behaviour: a gauge must not claim
a rate the link can't deliver. The fix is to retune the intervals from the
throughput measured in Phase 3.5.4.
