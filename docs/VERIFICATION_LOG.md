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

## Open questions for the next session

1. **Who is 7E9?** It answers `010C` alongside 7E8 with matching engine speed
   (see above), which is consistent with the TCM on a 2007 5R110 but does not
   prove it. Test: `raw ATSH 7E1` then `raw 221674` — if 7E9 alone answers, the
   `ObdModule::Tcm` TODO closes with evidence. Do this before anything else; it
   decides whether `221674` and `2211B3` need `expectedResponder` pinning.
2. **Does the PCM answer on `7E0`?** `hdr pcm 7E0` + `probe icp` — and does
   `ATCRA 7E8` add anything, or does ATSH already narrow the responses?
3. **Is the response-count digit supported?** `raw 2213101` should return the
   same payload as `raw 221310`, faster. A `?` means the feature is out.
   Only meaningful once physical addressing works.
4. **Does bare `ATCRA` clear the filter?** `OK` vs `?`. The firmware relies on it.
5. **Multi-DID batching.** `raw 2213101446` — if both DIDs come back in one
   response, that is roughly 3× the throughput and changes the whole poll-interval
   budget. Worth proving or disproving even though implementing it is a later
   milestone.
6. **`2211BD` on header `C410F1`** is expected to fail on CAN. Record the
   negative result explicitly rather than leaving the row in limbo.
7. **Measured latency** before/after each change (`stats reset`, run, `stats`), so
   `config::kMeasuredRequestsPerSec` and the poll intervals come from data.
