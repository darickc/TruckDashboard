# Verification log

Raw evidence for every claim in [FORD_6_0_PIDS.md](FORD_6_0_PIDS.md). A row is
marked `verified=true` in `PidDefs.cpp` only when there is an entry here.

Each entry records:

- **(a)** the raw excerpt, including which CAN ID answered
- **(b)** the decoded value and unit
- **(c)** the independent reference it was checked against, and the reasoning
- **(d)** date and conditions (cold/warm, KOEO/idle/driving)

The procedure is in [FORD_6_0_PIDS.md](FORD_6_0_PIDS.md#verification-procedure-benchdriveway-engine-running);
the tooling is in [CONSOLE.md](CONSOLE.md).

> **A note on what counts as evidence.** Torque Pro uses the same definitions
> imported into `PidDefs.cpp` from `exportedPIDs.csv`. Agreement with Torque
> proves the request reaches the module and comes back intact — it says nothing
> about whether the scaling is right, because both sides would be wrong
> together. Prefer a multimeter, a cross-check against an already-verified SAE
> PID, or a value so distinctive that a scaling error is unmissable.

---

## Session template

Copy this per session.

```
## YYYY-MM-DD — <conditions: ambient temp, cold/warm, KOEO/idle/driving>

Adapter: OBDLink MX+ 00:04:3E:85:EA:FC
Protocol (`raw ATDPN`): <n>
Firmware: <git rev>

### Responder census

<paste `probe` output for 010C and each Ford DID — which CAN IDs answer what>

### <PidKey> — <request bytes>

Raw:
    <paste the TX>/RX< lines and the probe output>

Decoded: <value> <unit>
Reference: <multimeter reading / verified SAE PID it was compared to /
            plausibility argument>
Verdict: verified | not verified | unsupported on this truck
```

---

## Sessions

## 2026-08-09 — idle, warm, driveway (captured from the serial log, not a probe)

Adapter: OBDLink MX+ `00:04:3E:85:EA:FC`
Firmware: `6a8b38e` (before the console was usable — this is log output)

### 7E8 and 7E9 both answer `010C`, and they agree

Raw (representative, ~11 requests/s over about two seconds):

```
TX> 010C
RX< 7E904410C0AC4      RSP Engine RPM <- 7E9 : 0AC4
RX< 7E804410C0AC2      RSP Engine RPM <- 7E8 : 0AC2
TX> 010C
RX< 7E904410C0AB8      RSP Engine RPM <- 7E9 : 0AB8
RX< 7E804410C0ABA      RSP Engine RPM <- 7E8 : 0ABA
TX> 010C
RX< 7E904410C0AC8      RSP Engine RPM <- 7E9 : 0AC8
RX< 7E804410C0AC3      RSP Engine RPM <- 7E8 : 0AC3
TX> 010C
RX< 7E904410C0AD0      RSP Engine RPM <- 7E9 : 0AD0
RX< 7E804410C0AD0      RSP Engine RPM <- 7E8 : 0AD0   (identical)
```

Decoded (`((A·256)+B)/4`):

| 7E9 | 7E8 | Δ |
|---|---|---|
| `0AC4` = 689.00 | `0AC2` = 688.50 | 0.50 rpm |
| `0AB8` = 686.00 | `0ABA` = 686.50 | 0.50 rpm |
| `0AC8` = 690.00 | `0AC3` = 688.75 | 1.25 rpm |
| `0AD0` = 692.00 | `0AD0` = 692.00 | 0.00 rpm |

**Reference:** cross-check between the two responders themselves, plus physical
plausibility — a warm 6.0L idles around 650–700 rpm.

**Verdict:** two modules reporting the same engine-speed signal, sampled a few
milliseconds apart. Maximum divergence 1.25 rpm out of ~690 (0.2%), and they
land on identical bytes when the sampling happens to line up. This is agreement,
not conflict.

**Consequences recorded:**

- 7E9 knows engine speed to within a rounding error, which is **consistent with
  it being the TCM** on the 5R110 — but consistency is not proof. Still a lead;
  test it with `raw ATSH 7E1` (open question 1 below).
- 7E9 consistently answers *first*, so first-wins currently feeds the dashboard
  from 7E9 rather than the PCM. Harmless for RPM. Revisit `expectedResponder`
  for the SAE rows once the census identifies both modules.
- Latency, measured TX → `>` prompt: 42–115 ms, typically 60–80. Consistent with
  the ~96 ms figure in `OBD_PROTOCOL.md`; re-measure properly with `stats reset`
  → run → `stats` and update `config::kMeasuredRequestsPerSec`.
- This session is also what showed the byte-equality conflict check to be a false
  alarm. Fixed: divergence is now judged on decoded values
  (`PidStats::maxResponderSpread`), not bytes.

**Not yet verified:** which module is which, and every Ford Mode 22 DID.

## 2026-08-09 (later) — idle, warm, driveway. Console session.

Adapter: OBDLink MX+ `00:04:3E:85:EA:FC`
Firmware: `de32e52`

### Protocol

```
raw ATDPN
  A6
```

Protocol **6** (ISO 15765-4, CAN 11-bit/500 kbaud). The `A` prefix means it was
reached by auto-detection rather than pinned.

**Consequence:** `kElmInitCommands` changed `ATSP0` → `ATSP6`, which skips the
`SEARCHING...` round on every reconnect. Revert if the adapter is ever moved to
a different vehicle.

### TransTemp1 — `22 1674` — **VERIFIED**

```
raw 221674
TX> 221674
  7E8037F2231           7F 22 31  — negative response, NRC 0x31 requestOutOfRange
  7E9056216740413       62 16 74 04 13  — positive response
```

Decoded: payload `0413` = 1043; Torque formula `((A·256)+B)/8` → **130.4 °F**.

**Reference:** Torque Pro read **132.1 °F** for transmission temperature a few
minutes later. The two tools cannot run at once (the MX+ takes one Bluetooth
master), so the readings are minutes apart on a transmission that was still
warming — a value that moved 1.7 °F in the right direction over that interval is
better evidence than an exact match, which would have suggested a frozen reading.

**What this does and does not prove.** Torque uses the same definition imported
into `PidDefs.cpp` from `exportedPIDs.csv`, so agreement confirms the request
reaches the right module and that the ISO-TP parsing, echo stripping and linear
decode are implemented correctly — it does not independently confirm the `/8`
scaling constant, because a wrong constant would make both tools wrong together.
What raises this to verified is the pair of responses: **the PCM explicitly
rejects the DID** (`requestOutOfRange`) while the TCM services it with a value
that is physically plausible for a warm transmission and tracks over time. Short
of an inline temperature probe, this is as far as verification goes.

**Consequences:**

- `verified = true`, and `expectedResponder = 0x7E9` — 7E9 owns the DID, and
  pinning also stops the PCM's negative response being parsed and logged on every
  poll.
- Enabled in `kEnabledPids`. First Ford PID live on the dashboard.

### 7E9 is the transmission controller

Established by the above: 7E9 owns transmission fluid temperature, and 7E8
explicitly does not have it. Combined with 7E9 reporting engine speed to within
~1 rpm of the PCM (previous entry), the identification is as solid as this method
allows.

**Still open:** the TCM's *request* header. See below — `ATSH` did not behave as
expected, so `ObdModule::Tcm` stays `nullptr`.

### `ATSH` appears not to take effect under AUTO protocol

```
raw ATSH 7E1
  OK
raw 010C
  7E804410C0ABC        both modules answered a request addressed to 7E1
  7E904410C0ABC        (identical bytes: 0x0ABC = 687 rpm)
raw 221674
  7E8037F2231          the PCM received it too — it answered, negatively
```

A request physically addressed to `7E1` should reach only the TCM. Both modules
received it, and the PCM's negative response proves it was not merely a stale
frame. Working hypothesis: with the protocol left on **AUTO** (`ATDPN` → `A6`),
the STN firmware is re-sending on the functional header rather than honouring
`ATSH`.

**Not yet retested** with the protocol pinned. This blocks two things: the
`ObdModule::Tcm` header, and the response-count digit (which is only safe with
physical addressing).

## Open questions for the next session

1. ~~**Who is 7E9?**~~ **ANSWERED: the TCM.** It owns `22 1674` (transmission
   fluid temp) and the PCM rejects that DID outright.
2. **Does `ATSH` work at all once the protocol is pinned?** This is now the
   blocking question. Retest:
   ```
   raw ATSP6
   raw ATDPN        expect plain "6", not "A6"
   raw ATSH 7E1
   raw 010C         only 7E9 should answer
   raw ATSH 7E0
   raw 010C         only 7E8 should answer
   ```
   - If only one module answers each time, physical addressing works: fill in
     `ObdModule::Tcm` = `7E1` and `ObdModule::Pcm` = `7E0` with this evidence,
     and the response-count digit becomes usable.
   - If both still answer, `ATSH` is not usable on this adapter/truck pair.
     Record that as a finding, leave the module headers `nullptr` forever, and
     rely on `expectedResponder` for module selection — it already works.
3. **Does `2211B3` (gear) behave like `221674`?** Try `raw 2211B3` and see
   whether the PCM rejects it while the TCM answers. If so, pin `Gear1` to 7E9
   the same way. Confirm the decode by shifting P→R→N→D with the brake on.
4. **Is the response-count digit supported?** `raw 2213101` should return the
   same payload as `raw 221310`, faster. A `?` means the feature is out.
   Only meaningful if question 2 says physical addressing works.
4. **Does bare `ATCRA` clear the filter?** `OK` vs `?`. The firmware relies on it.
5. **Multi-DID batching.** `raw 2213101446` — if both DIDs come back in one
   response, that is roughly 3× the throughput and changes the whole poll-interval
   budget. Worth proving or disproving even though implementing it is a later
   milestone.
6. **`2211BD` on header `C410F1`** is expected to fail on CAN. Record the
   negative result explicitly rather than leaving the row in limbo.
7. **Measured latency** before/after each change (`stats reset`, run, `stats`), so
   `config::kMeasuredRequestsPerSec` and the poll intervals come from data.
