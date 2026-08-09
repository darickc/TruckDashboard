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

*(none yet — Phase 1 and the console landed first so that the first session
produces evidence instead of anecdotes)*

## Open questions for the next session

1. **Who is 7E9?** It answers `010C` alongside 7E8. Plausibly the TCM on a 2007
   5R110, but that is a lead, not a conclusion. Test: `raw ATSH 7E1` then
   `raw 221674` — if 7E9 alone answers, the `ObdModule::Tcm` TODO closes with
   evidence. Do this before anything else; it decides whether `221674` and
   `2211B3` need `expectedResponder` pinning.
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
