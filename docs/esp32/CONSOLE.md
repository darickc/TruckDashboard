# Serial console

An interactive console on the USB serial port (115200 baud, same port as the
log). It exists because the bottleneck in verifying Ford PIDs was never the
protocol — it was the edit-flash-walk-to-the-truck loop. Enabling one PID used
to cost a reflash; now it costs typing `on eot`.

```bash
pio device monitor
```

Type `help` for the command list. Everything is case-insensitive, and what you
type is echoed back — `pio device monitor` does not echo locally, so the console
does it.

**The serial port is shared** between the console, the log, and the text gauge
display. The firmware boots quiet (log level Info, raw OBD logging off) and the
display **pauses automatically the first time you type**, with a notice. `display
on` brings it back. Without that, ~11 requests/s of log traffic scrolls a reply
away before it can be read.

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
| `display on\|off` | Pause/resume the text gauge display (it shares this port) |
| `log raw on\|off` | Mirror raw OBD traffic at INFO |
| `log level <0-5>` | 0=off 1=error 2=warn 3=info 4=debug 5=trace |
| `unsafe on\|off` | Lift the `raw` deny-list for this session |

PIDs can be named by table index (`on 7`), `PidKey` (`on Icp`), or the table's
short name (`on hpop`).

## `probe` — the verification workhorse

`probe` runs the procedure from [FORD_6_0_PIDS.md](../diagnostics/FORD_6_0_PIDS.md) for one PID
without a reflash, and prints the thing the old flow could not produce: what
**every** module that answered said, decoded, side by side.

```
> probe rpmsae 3
probe RpmSae  (Engine RPM, 01 0C, module Auto -> 7DF)
  #1    75ms   7E9 0AC4     =   689.00 rpm    7E8 0AC2     =   688.50 rpm
  #2    62ms   7E9 0AB8     =   686.00 rpm    7E8 0ABA     =   686.50 rpm
  #3    71ms   7E9 0ACC     =   691.00 rpm    7E8 0AD0     =   692.00 rpm
3/3 ok, avg latency 69ms; 2 ECUs answered, max spread 1.00 rpm
```

**Read the spread, not the difference in bytes.** Two ECUs answering a live
signal will differ in bytes on nearly every request — the readings above are one
crank sensor sampled a few milliseconds apart, and "max spread 1.00 rpm" at a
690 rpm idle says so. The same line reading `max spread 326.00 F` would mean the
two modules disagree about what the DID *is*, and that is when
`expectedResponder` needs pinning.

Spread statistics come from the scheduler, so they accumulate across every poll,
not just probes — enable the PID with `on` first to get the figure in the probe
summary and in `stats`.

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
  #1    88ms   7E9 0A2C     =   325.50 F
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
[`CommandMailbox`](../../firmware/esp32/lib/Console/src/CommandMailbox.h); the OBD task claims the
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
