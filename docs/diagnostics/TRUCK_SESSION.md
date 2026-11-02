# Truck verification session

A prepared script for the next session with the truck. It exists because the
seven open questions in [VERIFICATION_LOG.md](VERIFICATION_LOG.md) interlock —
question 4 is only meaningful if question 2 says yes — and working out the order
while the engine idles wastes the expensive resource.

Everything here uses commands the [console](CONSOLE.md) already has. No reflash.

**Before you go out:** `pio run -e esp32dev -t upload`, confirm the truck
connects, then `pio device monitor` and leave the laptop on the seat.

**Rule for the whole session:** paste every transcript into
[VERIFICATION_LOG.md](VERIFICATION_LOG.md), including the ones that fail. A
recorded negative result closes a question; an unrecorded one gets re-asked next
time.

---

## Part 0 — Quiesce the scheduler

*Key on, engine off.*

```
display off
log level 4
off rpmsae
off barosae
off transtemp1
pids
stats reset
```

`pids` must show **no `*`** on any row. Do not continue until it does.

### Why this part is not optional

The previous session's `ATSH` result is uninterpretable without it, and that is
almost certainly why question 2 is still open. What happened:

1. `raw ATSH 7E1` finished. `ElmClient::finishRequest` saw `rawMode_` and called
   `markAddressingUnknown()` ([ElmClient.cpp:131](../lib/ObdCore/src/ElmClient.cpp)),
   setting the header cache to the `"?"` sentinel.
2. The operator was typing the next line, so `console->busy()` was false and
   [ObdTask.cpp:100](../src/ObdTask.cpp) let the scheduler submit a due PID.
3. `ElmClient::submit` compared that PID's header to the cache. `RpmSae` is
   `ObdModule::Auto` → `7DF`, and `strcmp("7DF", "?") != 0`, so it sent
   **`ATSH7DF`**.
4. The typed `ATSH 7E1` was gone. `raw 010C` then went out functionally —
   `submitRaw` sets `prepCount_ = 0` and sends the line verbatim
   ([ElmClient.cpp:70](../lib/ObdCore/src/ElmClient.cpp)), on whatever header the
   adapter actually has.

`RpmSae` polls at 100 ms. The odds of it *not* firing between two typed lines
were poor. With nothing enabled, nothing re-sends `ATSH`, and Part 1 measures the
truck instead of the scheduler.

---

## Part 1 — Does `ATSH` work? (open question 2 — blocking)

*Key on, engine off. This gates questions 4 and 5 and both `ObdModule` headers.*

```
raw ATSP6
raw ATDPN
```

Expect **`6`**, not `A6`. `A6` means auto-detection is still in play and
`config::kElmInitCommands` did not take — stop and work that out first.

```
raw ATSH 7E1
raw 010C
```
→ expect **only `7E9`**

```
raw ATSH 7E0
raw 010C
```
→ expect **only `7E8`**

```
raw ATSH 7DF
raw 010C
```
→ expect **both**

The 7DF control is the point of the sequence. Without it, "only one answered"
could equally mean physical addressing works or that one module went quiet.

### What each outcome licenses

| Result | Conclusion | Action |
|---|---|---|
| One responder each, both answer on 7DF | Physical addressing works | Fill `ObdModule::Tcm` = `7E1`, `Pcm` = `7E0` in `moduleAtshHeader()` ([PidDefs.cpp](../lib/ObdCore/src/PidDefs.cpp)), with this transcript as the evidence. Questions 4 and 5 go live. |
| Both answer every time, with nothing polling | Physical addressing is genuinely unusable on this adapter/truck pair | Record it as a settled finding. Leave the module headers `nullptr` **permanently** and rely on `expectedResponder`, which already works — that is how `TransTemp1` is pinned. Skip the first block of Part 2. |
| Nobody answers on 7E0/7E1 | The header format is wrong, not the mechanism | Try `raw ATSH 07E1` (leading zero). Record either way. |

---

## Part 2 — Adapter capabilities

*Key on, engine off.*

### Response-count digit (question 4)

Only meaningful if Part 1 succeeded — the digit is only safe with physical
addressing, because on a functional header the adapter cannot know how many
modules will answer.

```
raw ATSH 7E1
raw 221674
raw 2216741
```

Same payload from the second, with **lower latency**, means supported: the
adapter returns as soon as one reply arrives instead of waiting out its P2
timeout. A `?` means the feature is out. Either way, set `expectedResponses` in
the PID table accordingly — it is already plumbed through
`ElmClient::sendPidRequest`.

### Bare `ATCRA` clears the filter (question 5)

```
raw ATCRA7E9
raw 010C
```
→ only `7E9`

```
raw ATCRA
raw 010C
```
→ both

**This is a correctness check, not an optimization.** `ElmClient::submit`
already sends a bare `ATCRA` to clear the filter when a PID needs no `rxFilter`.
If the bare form returns `?`, the filter is never actually cleared and any PID
polled after a filtered one is silently constrained — a live bug. Record the
result even though you expect `OK`.

### Multi-DID batching (question 6)

```
raw 2213101446
```

If both DIDs come back in one response, that is roughly 3× the throughput and
rewrites every poll interval in the PID table. Implementing it is a later
milestone; **proving or disproving it now** is what makes the budget in
[OBD_PROTOCOL.md](OBD_PROTOCOL.md#throughput-budget) trustworthy.

### `2211BD` on `C410F1` (question 7)

```
raw ATSH C410F1
raw 2211BD
```

Expected to fail — it is a KWP-style header on a CAN truck. `TransTemp3` exists
in the table only because it was in the Torque export. Run it, record the
failure, and mark the row dead so it stops looking like an untried option.

### Restore before moving on

```
raw ATSH 7DF
raw ATCRA
raw ATDPN
```

---

## Part 3 — Ford enhanced PIDs

*Engine running and warmed up.*

**The MX+ accepts one Bluetooth master at a time**, so the reference tool and this
firmware cannot both be connected. Cross-checks are sequential: probe with the
firmware, note the value and the clock, disconnect (power the ESP32 down), read
the same parameter in Torque/FORScan, compare. Values on a warming truck drift
between the two readings — that is expected and is exactly how the `TransTemp1`
entry reads (130.4 °F vs Torque's 132.1 °F minutes later). Batch the firmware side
of Part 3 first, then do one reference pass, rather than swapping per PID.

For each PID:

```
on <key>
probe <key> 5
```

and read three things:

1. **Who answered.** A PCM `7F 22 31` alongside a positive answer from `7E9` is
   the `221674` pattern — it identifies the owning module and justifies pinning
   `expectedResponder`.
2. **The spread**, not the byte difference. Two ECUs sampling a live signal
   milliseconds apart differ in bytes constantly; `max spread 1.00 rpm` at idle
   is agreement. A spread the size of the value means the modules disagree about
   what the DID *is*.
3. **The decoded value against the reference tool** on the later pass, allowing
   for drift between the two readings.

Order — the ones that need no driving first:

| Key | Request | Expect | Note |
|---|---|---|---|
| `eot` | `22 1310` | near ECT on a warm engine, drifting above it under load | |
| `ficmmainpower` | `22 09D0` | **≈ 48 V** | strongest self-check in the set: a wrong scale factor is obvious, since only ~48 V is a plausible answer |
| `batteryvoltage` | `22 1172` | ~14.0–14.4 V running, ~12.6 V key-on-engine-off | cross-check against a multimeter at the battery if one is handy |
| `map` | `22 1440` | ≈ baro at idle (it is **absolute**) | boost is derived as MAP − baro in `Derived.cpp`; verify MAP alone here |
| `ebp` | `22 1445` | slightly above baro at idle, climbing hard under load | |
| `icp` | `22 1446` | ~500–700 psi at idle, thousands under load | |
| `iprduty` | `22 1434` | ~10–20 % at idle | should track inversely with ICP |
| `vgtduty` | `22 096D` | varies with load | |
| `gear1` | `22 11B3` | see below | |

### Gear gets its own step

```
raw 2211B3
```

first — does the PCM reject it while the TCM answers, as with `221674`? If so,
pin `Gear1` to `7E9` the same way and the `Gear2`/`ObdModule::Tcm` row becomes
redundant.

Then, **foot on the brake, engine idling**, shift P → R → N → D and
`probe gear1 1` at each position. The value must track. This is the only PID in
the set whose decode can be confirmed without a reference tool, because you are
the one setting the input.

### What a match does and does not prove

Per [FORD_6_0_PIDS.md](FORD_6_0_PIDS.md), agreement with Torque confirms that the
request reaches the right module and that ISO-TP parsing, echo stripping and the
linear decode are correct. It does **not** independently confirm the scaling
constant — both tools use the same Torque formula, so a wrong constant makes both
wrong together. Only mark `verified = true` where you can say which of the two
claims the evidence supports, exactly as the `TransTemp1` entry does.

---

## Part 4 — Measurements

### Throughput

```
raw ATSH 7DF
on <each PID that earned verified=true>
stats reset
```

Drive or idle for a full 60 s, then:

```
stats
```

Update `config::kMeasuredRequestsPerSec` (currently `10.0f`, derived from a single
96 ms round trip) from the measured average. **Re-measure after any addressing
change from Part 1** — physical addressing and the response-count digit both
change what a request costs, and the poll intervals in the PID table are all spent
from this number.

### Warning thresholds

All six rules at [Config.h:138-151](../include/Config.h) are labelled
`*** EXAMPLE DEFAULTS ONLY — VERIFY BEFORE TRUSTING ***`. They are commonly cited
6.0L community numbers, not measurements from this truck.

During the drive, note the observed range of each warned channel — ECT, EOT, the
ECT/EOT delta, FICM main power, transmission temp, battery voltage — at idle,
cruise, and under load. A threshold set just above a measured normal range is
worth something; one copied off a forum is not.

---

## After the session

- One [VERIFICATION_LOG.md](VERIFICATION_LOG.md) entry per question, with its raw
  transcript, in the existing entry format.
- `config::kEnabledPids` uncomments **only** PIDs that earned `verified = true`.
- `moduleAtshHeader()` gains real headers only if Part 1 says so.
- [FORD_6_0_PIDS.md](FORD_6_0_PIDS.md) Verified column: Torque → VERIFIED.
- `pio test -e native` — the PID table is covered by `test_pid_defs`.
