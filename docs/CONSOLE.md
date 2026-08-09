# Serial console

An interactive console on the USB serial port (115200 baud, same port as the
log). It exists because the bottleneck in verifying Ford PIDs was never the
protocol — it was the edit-flash-walk-to-the-truck loop. Enabling one PID used
to cost a reflash; now it costs typing `on eot`.

```bash
pio device monitor
```

Type `help` for the command list. Everything is case-insensitive.

## Commands

| Command | What it does |
|---|---|
| `pids` | The whole PID table: index, key, request bytes, module, resolved ATSH header, poll interval, priority, verified/unverified, and `*` for currently polling |
| `on <idx\|key>` | Start polling a PID, and report what the enabled set now asks of the link |
| `off <idx\|key>` | Stop polling it |
| `probe <idx\|key> [n]` | Request it n times (1–50) and print, per attempt: which CAN ID answered, the raw payload, the decoded value, and the latency |
| `snap` | Every channel: value, age in ms, error count |
| `stats` | Per-PID requests/ok/nodata/noresponder/timeouts/errors/conflicts and min/avg/max latency, plus ATSH/ATCRA overhead and the requested request rate |
| `stats reset` | Zero the counters (do this before a measurement run) |
| `raw <text>` | Send a verbatim line to the adapter and print every reply line uninterpreted |
| `hdr <module> <tx> [rx]` | Set a **candidate** ATSH (and optional ATCRA) for a module at runtime |
| `hdr clear` | Drop all runtime addressing overrides |
| `log raw on\|off` | Mirror raw OBD traffic at INFO |
| `log level <0-5>` | 0=off 1=error 2=warn 3=info 4=debug 5=trace |
| `unsafe on\|off` | Lift the `raw` deny-list for this session |

PIDs can be named by table index (`on 7`), `PidKey` (`on Icp`), or the table's
short name (`on hpop`).

## `probe` — the verification workhorse

`probe` runs the procedure from [FORD_6_0_PIDS.md](FORD_6_0_PIDS.md) for one PID
without a reflash, and prints the one thing the old flow could not produce: the
responder ID.

```
> probe transtemp1 3
probe TransTemp1  (Trans Fluid Temp (Method 1) 22 1674, module Auto -> 7DF)
  [UNVERIFIED definition — compare against an independent reference before trusting it]
  #1  <-7E8  0A2C        326.00 F        94ms  (2+ ECUs answered)  *** THEY DISAGREE ***
  #2  <-7E8  0A2C        326.00 F        91ms  (2+ ECUs answered)  *** THEY DISAGREE ***
  #3  <-7E8  0A2C        326.00 F        96ms  (2+ ECUs answered)  *** THEY DISAGREE ***
3/3 ok, avg latency 93ms
```

That output is evidence: it names the module, shows the bytes, shows the
decode, and says out loud that a second ECU answered with something different —
the case where "the value looked plausible" would otherwise have been recorded
as a successful verification.

A probe's readings are real: they flow into `VehicleData` like any other poll.

## `hdr` — trying a candidate without guessing

`Pcm`, `Tcm` and `Abs` ship with `nullptr` headers, so any PID on them is
refused rather than sent to an address nobody verified. `hdr` is how the
documented "try `ATSH 7E0` (+ `ATCRA 7E8`) for the PCM" experiment gets run:

```
> probe transtemp2 1
  #1  refused (module 'TCM' header unverified — use `hdr` to try a candidate)
> hdr tcm 7E1 7E9
TCM -> ATSH7E1 + ATCRA7E9
this is a CANDIDATE, not a verified value. It dies on reboot. Probe a PID on
this module and check what answers; if it holds up, commit it to
moduleAddressing() with the evidence.
> probe transtemp2 1
  #1  <-7E9  0A2C        326.00 F        88ms
```

This is not a backdoor around the no-guessing rule. The compiled-in default
stays `nullptr`, the override is never persisted, it dies on reboot, and it is
logged at WARN while active. An operator types a *candidate*; the truck answers;
only then does a value get committed to `moduleAddressing()` with its evidence.

## `raw` and the deny-list

`raw` sends anything, which on a live truck includes services that write, clear
or actuate. Those are refused unless `unsafe on` has been typed this session:

| Service | |
|---|---|
| `04` | clear DTCs |
| `14` | clear diagnostic information |
| `2E` | write data by identifier |
| `2F` | input/output control by identifier |
| `31` | routine control |
| `3B` | write data by PID |

```
> raw 04
refused: service 04 writes/clears/actuates. This is a live truck — type
`unsafe on` first if you mean it.
```

`AT`/`ST` commands configure the adapter, not the vehicle, and are never gated.
The gate resets on reboot.

After **any** `raw` command the adapter's addressing is treated as unknown — note
that `raw ATSH 7E0` leaves it on 7E0, not on the ATZ default — so the next
scheduled request re-sends both its ATSH and its ATCRA. One redundant pair of
commands is far cheaper than a desynced cache quietly mislabelling readings.

## Threading

The console runs on `loopTask`; `ElmClient` and `PidScheduler` are private to the
OBD task and their state machines assume single-threaded access. The console
therefore never touches them. It posts into a single-slot
[`CommandMailbox`](../lib/Console/src/CommandMailbox.h); the OBD task claims the
request at a point where it already knows the adapter is idle, executes it,
appends reply lines, and marks it done. One command in flight at a time — a
second `post()` is refused with "busy" rather than dropped silently.

Typed commands take the next request slot ahead of the poll rotation: during a
verification session the operator's question matters more than keeping a gauge
on schedule.

## Layout

| File | |
|---|---|
| `lib/Console/src/ConsoleParser.*` | line reading + argv tokenization (pure) |
| `lib/Console/src/ConsoleCommands.*` | the grammar, PID/module resolution, deny-list (pure) |
| `lib/Console/src/CommandMailbox.*` | the loopTask ↔ OBD-task handoff (pure) |
| `lib/Console/src/ConsoleExecutor.*` | runs commands against ElmClient/PidScheduler (needs ObdCore only, so still host-testable) |
| `src/ConsoleHost.cpp` | the only Arduino-dependent part: `Serial` in, `Serial` out |

No dynamic allocation, no `String`. Covered by `test_console` and
`test_console_executor` (see [TESTING.md](TESTING.md)).
