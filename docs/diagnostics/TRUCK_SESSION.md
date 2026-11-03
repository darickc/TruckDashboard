# Truck verification session

A prepared script for the driveway session (roadmap 3.5.4). It exists because
the open questions in [VERIFICATION_LOG.md](VERIFICATION_LOG.md) interlock:
question 4 is only meaningful if question 2 says yes, and working out the order
while the engine idles wastes the expensive resource.

Everything here runs on the Pi through the vehicle gateway and `obd-console`,
against the OBDLink MX+. Nothing needs rebuilding. The ESP32 version of this
script (serial console) is in git history at `6bc9f25`, for when the ESP32 is
the only adapter at hand.

**Rule for the whole session:** paste every transcript into
[VERIFICATION_LOG.md](VERIFICATION_LOG.md), including the ones that fail. A
recorded negative result closes a question; an unrecorded one gets re-asked next
time.

**Already known** (2026-11-02, two MX+ sessions,
[bench-log](../hardware/bench-log.md)): `ATDPN` answers `6`; on `7DF` both
`7E8` and `7E9` answer `010C`, within a few rpm of each other; `221674` comes
from `7E9` while `7E8` answers `7F 22 31`; with the seven default signals
polled the link delivers about 11–13 requests/s at idle.

---

## Setup

**Disconnect the phone (Torque) and the ESP32 first.** The MX+ takes one
Bluetooth master at a time.

Two ways to run it. The first avoids the truck's Wi-Fi, which dropped out on
2026-11-02.

**A. On the Pi's own keyboard and screen** (no dashboard):

```bash
cd ~/TruckDashboard && make pi-run TRANSPORT=obdlink TRANSMIT=1 UI=0
```

Then press Alt+F2, log in, and start the console:

```bash
cd ~/TruckDashboard && target/release/obd-console --gateway unix:/tmp/f250/vehicle.sock
```

Alt+F1 goes back to the first console; Ctrl-C there stops the gateway.

**B. Over SSH** (dashboard on the screen):

```bash
ssh -t darick@192.168.1.190 'cd ~/TruckDashboard && make pi-start TRANSPORT=obdlink TRANSMIT=1'
```

```bash
ssh -t darick@192.168.1.190 'cd ~/TruckDashboard && target/release/obd-console --gateway unix:/tmp/f250/vehicle.sock'
```

`make pi-stop` stops it.

`TRANSMIT=1` is the ADR-0007 opt-in: read-only services `01 03 07 09 22` only,
checked by the registry and again by the ELM client. Every `raw` line goes
through the same guard. Write, control, routine and clear-DTC services, and
`ATCAF0`, `ATPP…` and `ST…` commands are refused before they reach the wire.

**What gets saved, with no extra steps:**

- the console transcript, `~/TruckDashboard/obd-console-<epoch>.log`, one per
  console start
- every adapter line with millisecond timestamps,
  `~/f250-data/<date>-obdlink/traffic/`
- the gateway's events (`events 30` in the console), and the recorder database

Paste from the console transcript; the traffic log is the tiebreaker when a
transcript is ambiguous.

---

## Part 0 — Quiesce the scheduler

*Key on, engine off.*

```
off rpm
off speed
off ect
off baro
off iat
off load
off trans_temp
pids
```

In `pids`, the poll state (the column after the provenance) must read **`OFF`**
for every signal with a request; the computed and aux rows leave it blank. Do
not continue until it does. The `*` in the first column means "enabled in the
registry", not "being polled", so it stays.

```
stats reset
stats
```

Wait 10 s and run `stats` again: it must show `0.0 requests/s`. It counts
signal requests only, not the gateway's own `ATRV`.

With nothing polled, the gateway still sends `ATRV` every 10 s, which talks
only to the adapter and doesn't touch its header or filter. Its link health
check only acts when something is being polled, so it won't step in with a
reset (`ATZ`) while you work. `off` lasts until the gateway restarts.

### Why this part is not optional

After any `raw` command the ELM client treats the adapter's header and filter
as unknown (`mark_addressing_unknown` in
[client.rs](../../crates/elm/src/client.rs)). The next scheduled request then
sends `ATSH7DF`, and `ATCRA` if needed, before its own line. If rpm (every
100 ms) fires between `raw ATSH 7E1` and `raw 010C`, the second line goes out
on `7DF` and the test measures the scheduler instead of the truck.

That is how an earlier ESP32 session lost question 2: the console didn't hold
the scheduler off between two typed lines, and `RpmSae` re-sent `ATSH7DF`.

`probe` (Part 3) is fine at any time: it sets its own addressing.

---

## Part 1 — Does `ATSH` work? (open question 2, blocking)

*Key on, engine off. This gates questions 4 and 5, and whether signals can use
physical headers.*

```
raw ATDPN
```

Expect **`6`**, not `A6`. The gateway's init pins `ATSP6`. `A6` means
auto-detection is still in play: stop and work that out first.

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

`raw` prints every reply line with its CAN header (`ATH1` is on), then the
latency.

### What each outcome licenses

| Result | Conclusion | Action |
|---|---|---|
| One responder each, both answer on 7DF | Physical addressing works | A signal owned by one module can set `request.tx_id: "0x7E1"` (TCM) or `"0x7E0"` (PCM) in `shared/signals/*.yaml`. The gateway then sends `ATSH` with that header ([core.rs](../../services/vehicle-gateway/src/core.rs) `obd_request`). Cite this transcript. Questions 4 and 5 go live |
| Both answer every time, with nothing polling | Physical addressing is unusable on this adapter/truck pair | Record it as a settled finding. Keep `tx_id: "0x7DF"` and pin the owner with `rx_id`, as `trans_temp` already does. Skip the first block of Part 2 |
| Nobody answers on 7E0/7E1 | The header format is wrong, not the mechanism | Try `raw ATSH 07E1` (leading zero). Record either way |

---

## Part 2 — Adapter capabilities

*Key on, engine off. Scheduler still quiesced.*

### Response-count digit (question 4)

Only meaningful if Part 1 succeeded. The digit is only safe with physical
addressing: on a functional header the adapter can't know how many modules will
answer, and the ELM client refuses it there.

```
raw ATSH 7E1
raw 221674
raw 2216741
```

The same payload from the second, with **lower latency**, means supported: the
adapter returns as soon as one reply arrives instead of waiting out its P2
timeout. A `?` means the feature is out.

The ELM client supports it (`ObdRequest::with_expected_responses`), but the
signal registry has no field for it yet. If it works, add one: TODO, with this
transcript as the evidence.

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

**This is a correctness check, not an optimization.** The Rust client sends a
bare `ATCRA` to clear the filter when a request needs none
([client.rs](../../crates/elm/src/client.rs), the `ATCRA` prep). If the bare
form returns `?`, the filter is never actually cleared and any signal polled
after a filtered one is silently constrained: a live bug. Record the result
even though you expect `OK`.

### Multi-DID batching (question 6)

```
raw 2213101446
```

If both DIDs come back in one response, that is roughly 3× the throughput and
rewrites every poll interval in the registry. Implementing it is a later
milestone; **proving or disproving it now** is what makes the throughput
budget trustworthy.

### `2211BD` on `C410F1` (question 7)

```
raw ATSH C410F1
raw 2211BD
```

Expected to fail: it is a KWP-style header on a CAN truck. The DID exists only
because it was in the Torque export. Run it, record the failure, and note it as
dead so it stops looking like an untried option. It is not in the gateway's
registry.

### Restore before moving on

```
raw ATSH 7DF
raw ATCRA
raw ATDPN
```

The next `probe` or scheduled request sets the addressing it needs anyway.

---

## Part 3 — Ford enhanced PIDs

*Engine running and warmed up.*

**The MX+ accepts one Bluetooth master at a time**, so the reference tool and
the gateway can't both be connected. Cross-checks are sequential: probe on the
Pi, note the value and the clock, stop the gateway (Ctrl-C in method A,
`make pi-stop` in method B), read the same parameter in FORScan or Torque,
compare. Values on a warming truck drift between the two readings; that is
expected, and is exactly how the `trans_temp` entry reads (130.4 °F vs Torque's
132.1 °F minutes later). Batch the Pi side of Part 3 first, then do one
reference pass, rather than swapping per PID.

FORScan is the better reference for Ford DIDs: Torque uses the same definitions
the registry imported, so agreeing with Torque checks the transport, not the
formula.

For each signal in the registry:

```
probe <id> 5
```

`probe` works on signals the registry leaves disabled; it doesn't start polling
them. Each attempt prints the outcome, the latency, and every responder's CAN
ID, payload and decoded value. Read three things:

1. **Who answered.** A PCM `7F 22 31` alongside a positive answer from `7E9` is
   the `221674` pattern: it identifies the owning module and justifies pinning
   `rx_id`.
2. **The spread**, not the byte difference. Two ECUs sampling a live signal
   milliseconds apart differ in bytes constantly; a few rpm at idle is
   agreement (2026-11-02: median under 1 rpm). A spread the size of the value
   means the modules disagree about what the DID *is*.
3. **The decoded value against the reference** on the later pass, allowing for
   drift between the two readings.

Order: the ones that need no driving first. Formulas are the registry's,
imported from Torque (`IMPORTED_UNVERIFIED`).

| Signal | Request | Expect | Note |
|---|---|---|---|
| `eot` | `22 1310` | near ECT on a warm engine, drifting above it under load | On a cold-soaked engine EOT ≈ ECT ≈ IAT ≈ outside air: the cross-check in [FORD_6_0_PIDS.md](FORD_6_0_PIDS.md) |
| `ficm_main` | `22 09D0` | **≈ 48 V** | Strongest self-check in the set: a wrong scale factor is obvious, since only ~48 V is a plausible answer |
| `battery` | `22 1172` | ~14.0–14.4 V running, ~12.6 V key on, engine off | Cross-check against a multimeter at the battery, and against `raw ATRV` (the adapter's own reading at DLC pin 16) |
| `map` | `22 1440` | ≈ baro at idle (it is **absolute**) | Compare with `probe baro 5`. Boost is computed as MAP − baro; verify MAP alone here |
| `icp` | `22 1446` | ~500–700 psi at idle, thousands under load | |
| `ipr_duty` | `22 1434` | ~10–20 % at idle | Should track inversely with ICP |
| `fuel_level` | `22 16C1` | roughly the fuel gauge, as a percentage | Note who answers (7E8, 7E9 or both). Read it at two clearly different tank levels (before and after a fill-up): one reading can't confirm a scale factor. Also `raw 0120` and record whether SAE PID 2F (fuel tank level) is in the supported bitmap |

Not in the registry, so `raw` and decode by hand with the Torque export's
formula ([exportedPIDs.csv](../../shared/signals/imports/torque/exportedPIDs.csv),
`IMPORTED_UNVERIFIED`). With `ATH1` and `ATS0` a reply line has no spaces:
`7E805621445AABB` is CAN ID `7E8`, length `05`, `62`, DID `1445`, then A = `AA`,
B = `BB`.

| DID | Line | Torque formula | Expect |
|---|---|---|---|
| EBP | `raw 221445` | `(((A*256)+B)*0.03625)` psi | slightly above baro at idle, climbing hard under load |
| VGT duty | `raw 22096D` | `((A*256)+B)*(100/32767)` % | varies with load |
| Gear | `raw 2211B3` | `A/2` | see below |

### Gear gets its own step

```
raw 2211B3
```

first: does the PCM reject it while the TCM answers, as with `221674`? Torque
lists it twice, once on `Auto` and once on the TCM; one owner makes the second
row redundant.

Then, **foot on the brake, engine idling**, shift P → R → N → D and run
`raw 2211B3` at each position. The value must track. This is the only DID in
the set whose decode can be confirmed without a reference tool, because you are
the one setting the input. If it does, it earns a registry entry.

### What a match does and does not prove

Per [FORD_6_0_PIDS.md](FORD_6_0_PIDS.md), agreement with Torque confirms that the
request reaches the right module and that ISO-TP parsing, echo stripping and the
linear decode are correct. It does **not** independently confirm the scaling
constant: both tools use the same Torque formula, so a wrong constant makes both
wrong together. Only promote a signal to `VERIFIED_ON_TRUCK` where you can say
which of the two claims the evidence supports, exactly as the `trans_temp` entry
does.

---

## Part 4 — Measurements

### Throughput

Restart the gateway with the signals that earned verification opted in (until
the registry is updated, `ENABLE=` does that; they still show as UNVERIFIED):

```bash
make pi-run TRANSPORT=obdlink TRANSMIT=1 UI=0 ENABLE=eot,ficm_main
```

```
stats reset
```

Drive or idle for a full 60 s, then:

```
stats
```

`stats` gives requests/s and each signal's p50/p95 latency. The gateway's
budget defaults to 10 requests/s for the MX+ (`--budget-rps`,
[config.rs](../../services/vehicle-gateway/src/config.rs); `BUDGET_RPS=` in
`make pi-run`). The poll intervals in `shared/signals/*.yaml` ask for more than
that ([gateway.md](../setup/gateway.md#known-issue-the-poll-intervals-ask-too-much-of-the-mx));
retune them from this measurement. **Re-measure after any addressing change
from Part 1**: physical addressing and the response-count digit both change
what a request costs.

### Warning thresholds

Every rule in
[warning_rules.json](../../apps/infotainment/assets/config/warning_rules.json)
(shared by the gateway and the app) is labelled
`EXAMPLE THRESHOLDS — VERIFY BEFORE TRUSTING`. They are commonly cited 6.0L
community numbers, not measurements from this truck.

During the drive, note the observed range of each warned channel (ECT, EOT, the
EOT−ECT delta, FICM main power, trans temp, battery voltage) at idle, cruise and
under load. The recorder keeps every sample, so the ranges can be read from the
database afterwards (`recorder export --db …`). A threshold set just above a
measured normal range is worth something; one copied off a forum is not.

---

## After the session

- One [VERIFICATION_LOG.md](VERIFICATION_LOG.md) entry per question, with its raw
  transcript, in the existing entry format.
- In `shared/signals/*.yaml`, set `provenance: VERIFIED_ON_TRUCK` and
  `enabled: true` **only** for signals with such an entry. Set `tx_id` only if
  Part 1 says so; pin `rx_id` where Part 3 found one owner.
- Mirror the changes in the app's
  [signal_catalog.dart](../../apps/infotainment/lib/model/signal_catalog.dart)
  until it is generated from the registry.
- [FORD_6_0_PIDS.md](FORD_6_0_PIDS.md) Verified column.
- `make test`: the registry loader refuses an `IMPORTED_UNVERIFIED` signal
  enabled without `allow_unverified: true`.
