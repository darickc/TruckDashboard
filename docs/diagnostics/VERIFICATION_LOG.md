# Verification log

Raw evidence for every claim in [FORD_6_0_PIDS.md](FORD_6_0_PIDS.md). A row is
marked `verified=true` in `PidDefs.cpp` only when there is an entry here.

Each entry records:

- **(a)** the raw excerpt, including which CAN ID answered
- **(b)** the decoded value and unit
- **(c)** the independent reference it was checked against, and the reasoning
- **(d)** date and conditions (cold/warm, KOEO/idle/driving)

The procedure is in [FORD_6_0_PIDS.md](FORD_6_0_PIDS.md#verification-procedure-benchdriveway-engine-running);
the tooling is in [CONSOLE.md](../esp32/CONSOLE.md).

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
frame. Working hypothesis at the time: with the protocol left on **AUTO**
(`ATDPN` → `A6`), the STN firmware is re-sending on the functional header rather
than honouring `ATSH`.

**Not yet retested** with the protocol pinned. This blocks two things: the
`ObdModule::Tcm` header, and the response-count digit (which is only safe with
physical addressing).

#### Correction (2026-08-09, from code inspection — the hypothesis above is probably wrong)

This session ran with `RpmSae`, `BaroSae` and `TransTemp1` polling. **The
scheduler almost certainly overwrote the typed `ATSH` before the next line was
typed**, which explains the observation without involving the STN at all:

1. `raw ATSH 7E1` finished. `ElmClient::finishRequest` saw `rawMode_` and called
   `markAddressingUnknown()` (`ElmClient.cpp:131`), putting the `"?"` sentinel in
   the header cache.
2. The operator was typing the next line, so `console->busy()` was false and
   `ObdTask.cpp:100` let the scheduler submit a due PID.
3. `ElmClient::submit` compared that PID's header to the cache. `RpmSae` is
   `ObdModule::Auto` → `7DF`, and `strcmp("7DF", "?") != 0`, so it sent
   **`ATSH7DF`** (`ElmClient.cpp:530`).
4. `raw 010C` then went out on `7DF`, because `submitRaw` sets `prepCount_ = 0`
   and sends the line verbatim (`ElmClient.cpp:70`) on whatever header the
   adapter actually has.

`RpmSae` polls at 100 ms, so this would have happened nearly every time.

**The observation stands; the conclusion drawn from it does not.** Nothing here
says `ATSH` works — only that this session could not have shown either way. The
retest must disable every PID first (`off rpmsae`, `off barosae`,
`off transtemp1`, then `pids` to confirm no `*` remains). See
[TRUCK_SESSION.md](TRUCK_SESSION.md) Part 1, which also adds a `7DF` control so
"only one answered" cannot be confused with "one module went quiet".

## 2026-11-03 — EOT: cold soak (KOEO), then a 16-minute drive and idle

Adapter: OBDLink MX+ `00:04:3E:85:EA:FC`, on the Pi through the vehicle gateway
Protocol: 6 (pinned by the gateway's `ATSP6`)
Gateway: `eacb081`, `make pi-start TRANSPORT=obdlink TRANSMIT=1 ENABLE=eot`
Data: `~/f250-data/20261103-143123-obdlink/` (KOEO) and
`~/f250-data/20261103-154423-obdlink/` (drive) on the Pi: adapter traffic log,
recorder database, gateway log; console transcripts `obd-console-1793741529.log`
and `obd-console-1793745942.log`.

### Responder census for `22 1310`

`probe` prints positive answers only, so the TCM's refusal is not in the
transcripts below. The traffic log has every line:

```
  760753 TX 221310
  760793 RX 7E9037F2212           7F 22 12 — TCM: negative, NRC 0x12
  760796 RX 7E8056213102691       62 13 10 26 91 — PCM: positive
  760837 RX >
```

| Session | `221310` requests | PCM value + TCM refusal | TCM refusal only | `NO DATA` |
|---|---|---|---|---|
| KOEO (14:31) | 412 | 407 | 2 | 3 (at the end, when every signal stopped answering) |
| Drive (15:44) | 738 | 731 | 7 | 0 |

The PCM (7E8) owns EOT; the TCM (7E9) answers every request with `7F 22 12`.
The TCM answered first in 459 of the 738 drive windows.

### EOT — `22 1310` — cold soak

KOEO, engine cold-soaked:

```
> probe eot 5
  #1 ok 89 ms
      7E8 : 12 FF = 8.630
  ... (5 of 5 identical)
> probe ect 5
  #1 ok 65 ms
      7E9 : 31 = 9.000
      7E8 : 31 = 9.000
  ... (5 of 5 identical)
> pids
  * eot_ect_delta              Computed                          Valid        -0.37 degC
  * eot            22 13 10    ImportedUnverified   ACTIVE       Valid        8.63 degC
  * trans_temp     22 16 74    VerifiedOnTruck      ACTIVE       Valid        8.96 degC
  * ect            01 05       Sae                  ACTIVE       Valid        9.00 degC
  * iat            01 0F       Sae                  ACTIVE       Valid        10.00 degC
```

Decoded: `12FF` = 4863; 4863/100 − 40 = **8.63 °C**.
Reference: on a cold-soaked engine, oil, coolant, transmission fluid and intake
air all sit at ambient. ECT (SAE) 9.0 °C, trans_temp (verified) 8.96 °C, IAT
10.0 °C. EOT is within 0.4 °C of ECT. This rules out the gross errors (byte
order, 0.1 instead of 0.01 °C/bit, °F, a wrong offset). A single point cannot
confirm the slope.

### EOT — `22 1310` — warm-up on the drive

Recorder samples, last value in each minute (°C; speed km/h):

| Time | EOT | ECT | Trans | Speed | rpm |
|---|---|---|---|---|---|
| 15:44 | 9.4 | 9.0 | 9.7 | 0 | 910 |
| 15:46 | 14.7 | 20.0 | 12.4 | 0 | 927 |
| 15:48 | 24.4 | 32.0 | 18.3 | 41 | 2305 |
| 15:50 | 41.1 | 44.0 | 27.6 | 72 | 1736 |
| 15:52 | 49.6 | 50.0 | 36.6 | 74 | 1979 |
| 15:53 | 53.7 | 52.0 | 39.4 | 76 | 1861 |
| 15:56 | 58.6 | 56.0 | 48.2 | 52 | 1813 |
| 15:58 | 58.7 | 56.0 | 49.7 | 0 | 697 |

At idle after the drive:

```
> probe eot 5
  #1 ok 120 ms
      7E8 : 26 91 = 58.730
  ... (5 of 5 identical)
> probe ect 5
  #1 ok 104 ms
      7E9 : 60 = 56.000
      7E8 : 60 = 56.000
  ... (5 of 5 identical)
```

Decoded: `2691` = 9873; 9873/100 − 40 = **58.73 °C**.
Reference: ECT (SAE) over a 50 °C span. EOT trails ECT while warming (oil heats
more slowly than coolant), crosses it around 52 °C and settles 2.7 °C above it
at idle. A wrong scale factor or offset could not follow ECT across this span
from both ends. Not reached: full operating temperature (ECT only got to
56 °C), and no FORScan reading.

Verdict: **not yet verified.** The transport, the owning module and the decode
are consistent with SAE ECT at 9 °C and across 9–59 °C. Promote it after a
fully warm reading and a FORScan cross-check.

### EOT dropped out about once a minute: one refusal read as "unsupported"

In 7 of 738 drive windows the adapter closed the response after the TCM's
refusal, before the PCM answered (adaptive timing, `ATAT1`):

```
   31112 TX 221310
   31130 RX 7E9037F2212
   31160 RX >                     no 7E8 line in this window
```

With no `rx_id`, the gateway saw only NRC 0x12, which
`nrc_means_unsupported` treats as "unsupported": `ACTIVE → QUARANTINED`
on one miss, then one probe every 60 s. The gateway log has
`eot: ACTIVE → QUARANTINED (Unsupported ×1)` at 15:44:54, 15:48:38,
15:49:47, 15:52:44 and so on. Each one recovered about 60 s later
(`QUARANTINED → ACTIVE (answered)`). The dashboard showed EOT and EOT−ECT as
STALE meanwhile, not as a frozen value. The same truncation hits `trans_temp`
in reverse (19 of 1250 windows missed the PCM's `7F 22 31`), harmlessly,
because that row is pinned to 7E9.

**Fix:** `eot` now pins `rx_id: "0x7E8"` (`shared/signals/ford_enhanced.yaml`).
The ELM client drops 7E9's frames before parsing them, so a truncated window
is `NoResponder`, one ordinary miss, instead of a quarantine. Test vectors
from this session are in `crates/elm/tests/captures.rs`
(`eot_capture_pinned_to_pcm`, `eot_capture_tcm_negative_only`). `[SIM]` only:
not yet re-run on the truck.

## 2026-11-07 — EOT dropout seen on the wire; the pin works [TRUCK]

Idle in the driveway, warm, 74 s. The MX+ polled with EOT enabled while the
USB CAN adapter captured the bus listen-only through a Y-splitter
([CAN_CENSUS](CAN_CENSUS.md), capture 6). Pi at `eebd9fd`.

- All 104 EOT requests were answered by the PCM on the wire (`7E8 05 62 13 10
  …`), each after the TCM's refusal (`7E9 03 7F 22 12`).
- The MX+ relayed one of them without the PCM's line: TCM refusal at +6.4 ms
  on the wire, PCM answer at +39.5 ms, but the adapter had already printed
  its prompt. **The answer was on the bus; the ELM's window closed early.**
  This confirms the explanation above.
- The pin worked: the gateway logged `eot: ACTIVE → SUSPECT (NoResponse ×1)`,
  one ordinary miss, no quarantine. EOT read 53.71–53.83 °C, ECT 52 °C.

EOT stays `IMPORTED_UNVERIFIED`: this checks the transport and the responder,
not the scaling.

## 2026-11-07 — Direct CAN: the gateway polls the truck over the USB adapter [TRUCK]

Idle in the driveway, warming up, 97 s. The MX+ unplugged. `can.sh active`,
then `make pi-start TRANSPORT=can TRANSMIT=1 ENABLE=eot CAPTURE=1` (Pi at
`162f109`, session `20261107-143822-can`). First time this project's own code
transmits on the truck's bus.

| | Result |
|---|---|
| Link | `SocketCAN can0` up in 1 s, polling to the end; no reconnects |
| Requests | 1672 frames sent (`7DF`, padded `00`), all read-only (`01`, `22`); TX errors 0, bus errors 0, error-active throughout |
| Rate | 16.2 requests/s average, 17.6 peak (the MX+ managed 11.7) |
| EOT `22 13 10` | 173 requests, 173 PCM answers, 0 gateway failures; 44.9 → 48.3 °C while ECT went 42 → 46 °C. Returned in 23.6 ms on average (pinned: no need to wait out the window) |
| Trans temp `22 16 74` | 173 of 173 from the TCM, 34.9 → 37.3 °C, 16.8 ms |
| Unpinned SAE PIDs | RPM 5.9 Hz, speed 3.6 Hz, ECT/load 1.8 Hz: each waits the 50 ms window; no answer arrived later than 40.6 ms |
| Misses | one: IAT (`01 0F`), `iat: ACTIVE → SUSPECT (NoResponse ×1)`, recovered at the next poll |

The IAT miss, on the wire: the gateway sent it 7 ms after `22 16 74`, as soon
as the TCM had answered that one (pinned to 7E9). The PCM, which usually sends
its refusal to `22 16 74` at ~24 ms, sent neither the refusal nor the IAT
answer. The same happened to one RPM request (covered by the TCM's answer).
Two in 92 requests that followed an early-returning `22 16 74`; none in about
1300 others. Noted in ADR-0012 with the possible fixes; not acted on.

Verdict: the direct-CAN transport works on the truck, and EOT doesn't drop
out over it. EOT stays `IMPORTED_UNVERIFIED` (this tests the transport, not
the scaling). Still to do over CAN: a drive, physical addressing
(`obd-console raw 7E0 010C` / `raw 7E1 010C`).

## 2026-11-07 — First drives over direct CAN: EOT and trans temp drop out [TRUCK]

The owner drove with the USB CAN adapter alone (MX+ unplugged), `make pi-start
TRANSPORT=can TRANSMIT=1 ENABLE=eot CAPTURE=1`, Pi at `162f109`. Three
sessions: `20261107-151859-can` (74 s, parked), `-152131-can` (454 s) and
`-153625-can` (515 s), up to 79 km/h. 16.8 and 15.8 requests/s; TX errors 0,
bus errors 0, error-active throughout. EOT 44 → 66 °C, trans temp 34 → 61 °C
over the drives. The owner saw EOT and trans temp drop out several times.

| Session | EOT quarantined | Trans temp quarantined |
|---|---|---|
| 151859 | 1 (at 25 s; not probed again before the stop at 74 s) | 0 |
| 152131 | 0 | 2 |
| 153625 | 5 (gone ~250 of 515 s) | 1 |

Each one is `ACTIVE → QUARANTINED (Unsupported ×1)` in `gateway.log`, then
60 s without a request (the quarantine probe interval). On the wire, each is
the same thing (9 of 9):

1. The gateway sends trans temp (`7DF 22 16 74`, pinned to 7E9). The TCM
   answers in a few ms and the exchange ends there.
2. The gateway sends the next request 1–7 ms later: EOT (`22 13 10`, pinned
   to 7E8).
3. The PCM's refusal of trans temp (`7E8 7F 22 31`) arrives 12–26 ms into the
   EOT exchange, before the PCM's EOT answer. A refusal carries only the
   service byte, so it reads as the PCM refusing EOT: NRC 0x31,
   "unsupported", quarantine.

Trans temp is the mirror image: the TCM's late `7E9 7F 22 12` (refusing EOT)
lands in the next trans temp exchange. In 4 of the 6 EOT cases the PCM also
never answered the EOT request, as in session B: a module that is still
answering skips a request.

Refusals are later while driving than idle: the TCM's to EOT 12 ms median
(max 32), the PCM's to trans temp 27–32 ms median (max 49), against ~24 ms
idle in session B. Per session, 13–29 % of the TCM's refusals of EOT and
19–51 % of the PCM's refusals of trans temp arrived after their own exchange
had ended. Most landed harmlessly (in an unpinned exchange, or after the owner's
answer). These 9 did not.

Not a dropout: the 9–15 s of no answers at the start of sessions 151859 and
153625 (`link POLLING → DEGRADED`). The candump shows only our own requests
for the first ~8 s (0–17 frames/s, then ~730/s): the modules were not on the
bus yet.

Also seen, not acted on: two PCM speed answers of `0xCC` (204 km/h) about
15 s after the engine started in 153625, while the TCM answered 0. A start-up
artifact to watch for; the speed decoder is not changed.

Fix `[SIM]` (gateway, same day):
- A pinned functional request also waits, up to the 50 ms window, for the
  final answer of every other module heard on the bus, so each refusal lands
  in its own exchange. Trans temp now takes ~30 ms instead of ~7 ms.
- A PID that has answered this session is never quarantined by one
  "unsupported" refusal. It counts as an ordinary miss and backs off the
  usual way.
- Frames still queued when a request is about to go out are read first.

Tests replay the drive's timing (`gateway_can.rs`,
`a_late_refusal_is_never_read_as_the_next_requests_answer`). Without the fix
the test fails exactly as the truck did: `Negative { nrc: 0x31 }` at 23 ms.
The fix is not yet tested on the truck. Physical addressing (`7E0`/`7E1`)
would avoid the refusals altogether and is still untested.

## 2026-11-08 — Drive on AGL: the pinned-request fix holds [TRUCK]

The owner drove with the USB CAN adapter alone on the AGL release image
`e82719f` (contains the fix `ddb96b1`), cold start. `/etc/default/f250`:
`TRANSPORT=can TRANSMIT=1 ENABLE=eot`; `f250-can active`, then
`systemctl restart f250-gateway` (can.md, On the AGL image). This is also
the first run of the gateway's systemd sandbox on a real `can0`.
Logs: `build/logs/f250-logs-raspberrypi5-20261108-233128.tar.gz` and the
capture `20261108-212651-candump` (not in git).

- Gateway on CAN 21:25:40–21:34:39 (539 s), no restarts. **Not one state
  transition** in its journal for any PID: no SUSPECT, BACKOFF or
  QUARANTINED. At 21:34:39 `can0` went down (`f250-can listen` after the
  capture); everything after that is the gateway polling an interface that
  can't send, as expected.
- Capture 21:26:51–21:33:40 (409 s), ~736 frames/s, gs_usb, normal mode
  (not listen-only). ERROR-ACTIVE throughout, berr-counter tx 0 rx 0, bus
  errors 0, no gaps over 1 s, no wall-clock jump. `rx_dropped` 9239 at the
  start and at the stop: none dropped during the capture.
- `can-monitor pids`: 3339 requests, 8.2/s. Speed 0–41 km/h, rpm 652–2194,
  ECT 17 → 46 °C, IAT 10–17 °C. EOT (7E8, `IMPORTED_UNVERIFIED`) 11.7 →
  45.7 °C, trans temp (7E9, verified) 10.8 → 31.0 °C.

| DID | requests | answered | other module's refusal | refusals after the next request went out |
|---|---|---|---|---|
| `22 13 10` EOT, pinned 7E8 | 266 | 266, median 27 ms (max 41) | 7E9 NRC 12, median 19 ms (max 32) | 0 |
| `22 16 74` trans temp, pinned 7E9 | 267 | 267, median 19 ms (max 31) | 7E8 NRC 31, median 27 ms (max 40) | 0 |

The 2026-11-07 drives lost EOT 6 times and trans temp 3 times in 454 s and
515 s sessions, each to one late refusal. Here every pinned request drew
the other module's refusal (533), the next request went out only after it
(EOT's next request: median 29 ms), and nothing was quarantined.

Verdict: the fix works on the truck. Shorter and slower than 2026-11-07
(9 min, up to 41 km/h, cold); a longer warm drive would add margin. Still
open: physical addressing (`7E0`/`7E1`), which would avoid the refusals.

Lost: the gateway's own traffic log for this drive. The gateway truncates
`adapter-traffic.1.log` at every start, and on AGL the folder is fixed
(`/var/lib/f250/traffic`), so the next boot at the desk overwrote it. The
candump has every frame. Fixed: each start now opens the next file
(`services/vehicle-gateway/src/transport/traffic.rs`).

## 2026-11-08 — Physical addressing over direct CAN: each module answers only its own ID [TRUCK]

Parked, engine idling (~725 rpm), USB CAN adapter alone, AGL release image
`df61324`. `/etc/default/f250`: `TRANSPORT=can TRANSMIT=1 ENABLE=eot`;
`can0` in normal mode; gateway restarted 02:37:09 UTC (2026-11-09 UTC, the
evening of 2026-11-08 local). `obd-console` sent the requests through the
gateway, between its own polls. Logs: `build/logs/obd-console-1794191864.log`,
the capture `20261109-023729-candump` and
`f250-logs-raspberrypi5-20261109-024056.tar.gz` (not in git).

There is no ELM here: the gateway writes the frame itself, so none of the
`ATSH` questions (the scheduler re-sending `ATSH7DF`, question 2 below) can
confound it. Every frame below is from the candump, which also holds the
gateway's own requests (loopback); each window runs until the next request.

| Request | Answers before the next request | Next request |
|---|---|---|
| `7E0 02 01 0C` (PCM) | `7E8 04 41 0C 0B 52` at 32 ms | `7DF 01 04` at 51 ms |
| `7E1 02 01 0C` (TCM) | `7E9 04 41 0C 0B 54` at 17 ms | `7DF 01 0C` at 51 ms |
| `7E0 02 01 0C` (PCM) | `7E8 04 41 0C 0B 51` at 32 ms | `7E1 01 0C` at 85 ms |
| `7E1 02 01 0C` (TCM) | `7E9 04 41 0C 0B 54` at 9 ms | `7DF 22 13 10` at 52 ms |

After the second request the gateway's next poll was functional `7DF 01 0C`,
and each module answered it once (7E8 at 72 ms, 7E9 at 78 ms after the
`7E1` request): no extra 7E8 answer to the `7E1` request turned up later
either. The functional `raw 221310` right after drew the usual pair (7E9
`7F 22 12` at 29 ms, 7E8 `62 13 10` at 30 ms). In the 3 min capture the only
`7E0`/`7E1` frames are these four; 1569 `7DF` requests. Capture: ERROR-ACTIVE,
berr-counter 0/0, no gaps over 1 s, `rx_dropped` unchanged (68431 at start
and stop).

Verdict: on this truck, 11-bit physical requests to `7E0` reach only the PCM
and to `7E1` only the TCM, each answering on `7E8`/`7E9` (H12, over direct
CAN). Tested with `01 0C` only, 2 requests each, parked. Not yet tested:
Mode 22 DIDs addressed physically (`7E0 22 13 10`, `7E1 22 16 74`), which is
what the pinned requests would send; and the MX+'s `ATSH` path (question 2),
which is an adapter question now, not a truck one.

## 2026-11-08 — Mode 22 by physical address: only the addressed module answers [TRUCK]

Same evening, same setup as the entry above: parked, engine idling, AGL
release `df61324`, `can0` in normal mode, gateway restarted 03:09 UTC
(2026-11-09 UTC). `obd-console` sent the pinned DIDs straight to each
module, then to the wrong module, twice over. Logs:
`build/logs/obd-console-1794193793.log`, the capture
`20261109-030914-candump` and `f250-logs-raspberrypi5-20261109-031008.tar.gz`
(not in git).

| Request | Answer (both rounds) | From the other module, within 200 ms |
|---|---|---|
| `7E0 22 13 10` EOT → PCM | `7E8 05 62 13 10 22 11` / `22 12`, at 39 / 14 ms | nothing |
| `7E1 22 16 74` trans temp → TCM | `7E9 05 62 16 74 02 F6`, at 13 / 20 ms | nothing |
| `7E1 22 13 10` EOT → TCM | `7E9 03 7F 22 12`, at 20 / 26 ms | nothing |
| `7E0 22 16 74` trans temp → PCM | `7E8 03 7F 22 31`, at 32 / 10 ms | nothing |

From the candump (it holds the gateway's own requests too): every 7E8/7E9
frame up to 200 ms after each request is the answer to one specific
request, and each request has exactly one. The next request went out 51–53
ms later; nothing arrived after it for the earlier one. Capture
03:09:14–03:10:03, 8 physical requests and 391 `7DF` polls, ERROR-ACTIVE,
berr-counter 0/0, no drops, no gaps. Trans temp `02 F6` = 94.75 °F with the
verified formula; the EOT bytes are not decoded here (its formula is
`IMPORTED_UNVERIFIED`).

Verdict: physical addressing works for the pinned DIDs on this truck.
Sent to `7E0`, `22 13 10` gets only the PCM's answer; sent to `7E1`,
`22 16 74` gets only the TCM's, and no refusal from the other module. The
gateway's pinned requests could go out this way and stop drawing a refusal
on every read (ADR-0012 §3). Not done: the gateway still sends them to
`7DF`; nothing has run this way over a drive.

## 2026-11-08 — Ford DIDs: owners, parked readings, gear; a drive on physical pinning [TRUCK]

AGL release `df61324` with the gateway `38af731` sideloaded (pinned requests
to the owner's physical ID, `/etc/f250-overrides`). `can0` normal mode,
`TRANSPORT=can TRANSMIT=1 ENABLE=eot`, PINNED unset (physical). Probes with
`obd-console` through the gateway. The truck had run until ~03:10 UTC, so
none of this is a cold soak. Logs: `build/logs/20261109-drive/` (traffic
log, obd-console transcripts, battery loops), the capture
`20261109-035531-candump` (03:55–04:27 UTC, ERROR-ACTIVE, berr-counter 0/0,
no drops, no gaps) and `f250-logs-raspberrypi5-20261109-042732.tar.gz`
(not in git). Decoded values use the registry's imported formulas.

**Owners** (capture; every probe went to `7DF`):

| DID | Signal | Answers | Refuses |
|---|---|---|---|
| `22 14 40` | map | PCM | TCM `7F 22 12` |
| `22 14 46` | icp | PCM | TCM `7F 22 12` |
| `22 14 34` | ipr_duty | PCM | TCM `7F 22 12` |
| `22 09 D0` | ficm_main | PCM | TCM `7F 22 12` |
| `22 16 C1` | fuel_level | PCM | TCM `7F 22 12` |
| `22 14 45` | EBP (not in the registry) | PCM | TCM `7F 22 12` |
| `22 11 B3` | gear (not in the registry) | TCM | PCM `7F 22 31` |
| `22 11 72` | battery | PCM and TCM, within 1–2 counts | — |

The five PCM signals are now pinned to `7E8` in the registry. A third module
answered `01 00` from **`7ED`** with an empty bitmap (`41 00 00 00 00 00`);
which module it is is unknown (TODO).

**Readings, key on engine off (KOEO) and at idle (~690 rpm):**

| Signal | KOEO | Idle | Reference | What it shows |
|---|---|---|---|---|
| map | 84.98 kPa (`01 54`) | 86.0–86.5 kPa | SAE baro 85 kPa (both) | Matches baro to within baro's 1 kPa step at one pressure. The formula is a pure scale; one point can't rule out an offset, and nothing here checks it under boost |
| eot | 54.05 °C | 52.8 °C | SAE ECT 54 / 52–53 °C | Matches ECT with the engine heat-soaked. Not the cold-soak check (on 2026-11-08's cold start EOT read 11.7 °C against ECT 17 °C) |
| ficm_main | 47.0 V | 47.5 V | ≈ 48 V nominal | Plausible; a wrong scale would be obvious. Not a measurement |
| fuel_level | 98.9 % | 98.9 % | SAE `01 2F` (supported by the PCM, `A·100/255`) 99.2 %; dash gauge full (owner) | Matches at one level. A second, lower level is needed |
| icp | 1.1 psi | ~640 psi | none | Plausible only |
| ipr_duty | 14.7 % | 24.0 % | none | Plausible only |
| battery | 11.6–11.8 V | 13.4–13.9 V | owner's meter at the battery: 12.5 V KOEO, "about 14 V" idling, read during the same loops | **Does not match the terminals:** 0.7–0.9 V low with the engine off, ~0.4 V low running. Not a constant offset or a scale error that one constant fixes; it fits a module-supply reading (behind the PCM's own wiring), which this can't confirm |

EBP KOEO 86.5 kPa, idle 103.5 kPa (Torque formula, `IMPORTED_UNVERIFIED`).

**Gear, `22 11 B3`.** Foot on the brake, P → R → N → D → P twice: the DID
stayed `02`. The broadcast `230` byte 0 tracked the lever: **P `F0`, R `10`,
N `F1`, D `01`** (P and R were in CAN_CENSUS; N and D are new). Driving, the
DID changed with speed, and each value had its own rpm-per-km/h ratio
(medians, speed ≥ 15 km/h): `02` 97, `04` 67, `06` 45, `0A` 32, `0C` 18.4.
In all 231 samples while moving it was exactly twice `230`'s low nibble
(`02`/`04`/`06`/`0A`/`0C` ↔ `1`/`2`/`3`/`5`/`6`); `08` and nibble `4` never
appeared, here or in the census drive. So the DID is the transmission's
current gear (1st while stopped, whatever the lever), not the selector.
Torque's `A/2` gives 1, 2, 3, 5, 6; whether the five values are gears 1–5
is UNVERIFIED (a gear-ratio comparison or FORScan would show it).

**Drive on physical pinning**, 03:56–04:21 UTC (25.6 min, 0–89 km/h, ECT
50 → 59 °C, 8.7 requests/s; gateway traffic log `adapter-traffic.8.log`):

| | EOT → `7E0` | Trans temp → `7E1` |
|---|---|---|
| sent | 1001 | 998 |
| answered by the owner | 1001 | 998 |
| frames from the other module, refusals, duplicates | 0 | 0 |
| answer, median / p95 / max | 28 / 36 / 123 ms | 22 / 31 / 101 ms |
| longest gap between values (poll 1.5 s) | 2.4 s | 3.4 s |

No pinned request went to `7DF`. The gateway journal has no state
transition after the start: nothing stale, suspect or quarantined. EOT
52 → 66 °C, above ECT under load; trans temp 41 → 61 °C. The capture holds
1244 `7E0 22 13 10` and 1236 `7E1 22 16 74` answers over the whole session,
every one from the owner.

Verdict:
- Physical pinning works on the truck over a drive (ADR-0012).
- No signal is promoted. MAP, EOT and fuel level each match an independent
  reference at one point; FICM, ICP and IPR are plausible only; the battery
  DID reads below the battery terminals and stays unverified as "battery
  voltage". Not recorded under load: MAP, ICP, IPR, FICM, battery (they
  were not enabled for the drive).
- Next: enable them for a drive (`ENABLE=eot,map,icp,ipr_duty,ficm_main,
  battery,fuel_level`), a cold-soak EOT reading before a morning start, a
  fuel reading at a clearly lower level, and the gear labels.

## Open questions for the next session

1. ~~**Who is 7E9?**~~ **ANSWERED: the TCM.** It owns `22 1674` (transmission
   fluid temp) and the PCM rejects that DID outright.
2. **Does `ATSH` work at all once the protocol is pinned?** The truck side
   is answered (2026-11-08, direct CAN: `7E0` reaches only the PCM, `7E1`
   only the TCM, for `01 0C` and the pinned Mode 22 DIDs); what remains is
   whether the MX+ sends them. This was the
   blocking question. **First disable every PID** — see the correction above; the
   previous attempt was confounded by the scheduler re-sending `ATSH7DF` between
   the two typed lines. Retest:
   ```
   off rpmsae
   off barosae
   off transtemp1
   pids             confirm no `*` remains
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
