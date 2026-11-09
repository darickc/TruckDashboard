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
| Raspberry Pi (Raspberry Pi OS) — `make pi-run` wraps this ([raspberry-pi.md](raspberry-pi.md)) | `--adapter rfcomm:00:04:3E:85:EA:FC` | Build with `--features rfcomm` (needs `libdbus-1-dev`). Pair once with `bluetoothctl` (agent on, confirm the shown passkey; [bench-log](../hardware/bench-log.md)) |
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
- `--traffic-log` keeps every adapter line with millisecond timestamps, in 10
  rotating files of 5 MB each. The rotation carries on across starts: each
  start opens the file after the last one used (named in `current`), so a
  restart never overwrites the session before it.
- Together these are the evidence for the dropout analysis
  ([PROJECT_PLAN](../PROJECT_PLAN.md#what-the-mx-trial-phase-35-can-already-show)).

## With the USB CAN adapter (direct CAN)

`--transport can --can-if can0` sends the gateway's own single-frame ISO-TP
requests on a SocketCAN interface instead of going through an ELM adapter
([ADR-0012](../architecture/adr/0012-direct-can-usb-adapter.md)). The same
`--transmit` opt-in, allow-list, scheduler, recovery, recorder and UI apply.
`--can-window-ms` (default 50) is how long it collects answers to a request
not pinned to one responder. A pinned request (registry `rx_id`) goes to
its owner's physical ID instead of `7DF` (`7E8` → `7E0`, `7E9` → `7E1`),
so the other module never hears it; `--can-pinned functional` keeps it on
`7DF`. The interface itself is set up by
`tools/pi/can.sh`, listen-only unless `active`. The bench and truck
procedure is in [can.md](can.md).

```bash
cargo run -p vehicle-gateway --release -- \
    --transport can --can-if can0 --transmit \
    --listen unix:/tmp/f250/vehicle.sock --traffic-log ./traffic --enable eot
```

Status: `[SIM]` (in-memory bus replaying the truck's captures), compiled and
unit-tested on the Pi 5. Not run against the adapter or the truck yet.

## Poll intervals and the throughput budget

One request is in flight at a time, so the link's throughput is the budget:
10 requests/s for the MX+ (measured 10–11.7), 16/s for the CAN adapter
(measured 15.8–16.8), 15/s for the simulator. `--budget-rps` overrides it.
The registry's intervals are sized so the default enabled set asks for under
80 % of it ([ADR-0019](../architecture/adr/0019-poll-intervals-budgeted.md)):
every signal the simulator polls (all 14) asks 11.7/s; the truck's set
(registry defaults plus `--enable eot`) asks 6.5/s. RPM and MAP are read
every 500 ms, speed, ICP, IPR and load every 1 s, the temperatures and FICM
every 1.5 s. No interval is longer than half its `stale_after_ms`.

The ESP32-era intervals (RPM, MAP and ICP every 100 ms) asked about 54/s of
the simulator and 24/s of the truck's links, so most signals ran on the
scheduler's starvation guard: EOT and ECT were read about every 3 s against
their 4 s `stale_after_ms`, and load flickered `STALE` [SIM]. The retune
fixes that: over the 600 s `drive_cycle` every signal stays `VALID` and is
read at its interval plus a round trip (`tests/gateway_sim.rs`,
`tests/poll_budget.rs`) [SIM]. EOT − ECT's inputs are also read back to back
([ADR-0018](../architecture/adr/0018-computed-inputs-read-together.md)), so the
delta's 2 s skew limit holds even when the link is oversubscribed. Not yet run
on the truck.

Still true:

- Enabling more than the link carries is reported in `LinkStatus.detail`
  ("polling asks … of a … req/s link"), and low priorities stretch. Every
  signal at once fits the CAN adapter but asks 117 % of the MX+.
- The intervals alone would leave about 60 % of the CAN link idle with the
  truck's set, and RPM at ~1.8 Hz (against 5.9 Hz from the oversubscribed
  schedule on 2026-11-07). The scheduler now spends that room on priority 0
  ([ADR-0020](../architecture/adr/0020-spare-budget-to-priority-0.md)):
  while nothing else is due, RPM and MAP are read early, as long as the plan
  stays within 80 % of the budget and no read comes sooner than 250 ms (the
  snapshot period) after the last one. Only healthy (`ACTIVE`) priority-0
  signals get it; with nothing to spare, nothing changes. The registry
  intervals, `stale_after_ms` and `max_input_skew_ms` are unchanged, and
  EOT and ECT are still read back to back.

  | Set | Budget | Asks | Spare | RPM read every |
  |---|---|---|---|---|
  | Truck set, CAN | 16/s | 6.5/s | 2.0/s | 250 ms (the floor) |
  | Truck set, MX+ | 10/s | 6.5/s | 1.5/s | 288 ms |
  | All 14, simulator | 15/s | 11.7/s | 0.3/s | ~470 ms (RPM and MAP) |

  In virtual time with the truck's set at 16/s, RPM is read at 3.45 Hz
  instead of 1.77, the link carries 7.7 requests/s (48 %), and every other
  signal keeps its rate [SIM]. Not yet run on the truck.
