# HS-CAN broadcast census

What this truck's HS-CAN (DLC pins 6/14, 500 kbit/s) carries with no
diagnostic request: Phase 4.3, Stage A
([PROJECT_PLAN](../PROJECT_PLAN.md), [H14](../hardware/open-questions.md)).

Rules for this page:

- An ID's **meaning stays "unknown"** until a decoder is corroborated against
  something independent, like a PID, the gauge, or an action (Stage B). Byte
  behaviour is observation, not a definition.
- Captures are listen-only (`tools/pi/can.sh capture`). Raw logs stay on the
  Pi under `~/f250-data/<date>-candump/`, not in the repo: they contain the
  VIN.
- The VIN is redacted here.

## Captures

| # | When | Truck state | Length | Frames | Errors | Log |
|---|---|---|---|---|---|---|
| 1 | 2026-11-06 09:07 | Key on, engine off (owner) | 120 s | 85 390 (712/s) | 0 | `20261106-090751-candump` |
| 2 | 2026-11-07 11:34 | Engine idling, parked. Right turn signal, left turn signal, then P→R→P twice (owner; actions not timestamped) | 120 s (wall clock: 242 s, a 122 s clock jump) | 85 392 | 0 | `20261107-113429-candump` |
| 3 | 2026-11-07 11:38 | Driving (owner) | 120 s | 85 390 (712/s) | 0 | `20261107-113837-candump` |
| 4 | 2026-11-07 13:01 | Driving, the MX+ polling on a Y-splitter (`make pi-start TRANSPORT=obdlink TRANSMIT=1 CAPTURE=1`) | 345 s | 258 551 (749/s) | 0 | `20261107-130116-obdlink/candump` |
| 5 | 2026-11-07 13:18 | Idle, MX+ polling, no EOT | 32 s (wall clock: 424 s, a 391.6 s clock jump) | 23 994 | 0 | `20261107-131852-obdlink/candump` |
| 6 | 2026-11-07 13:27 | Idle in the driveway, MX+ polling with EOT (`… CAPTURE=1 ENABLE=eot`) | 74 s | 55 488 (749/s) | 0 | `20261107-132726-obdlink/candump` |

## Capture 1: key on, engine off [TRUCK]

Interface: listen-only, 500 kbit/s, sample point 87.5 %, error-active before
and after, every error counter 0, no error frames, no gap over 50 ms. The
kernel's RX count rose by 85 403 while candump logged 85 390 frames; RX
"dropped" rose by only 12 (dropped counts frames arriving with no socket open,
i.e. before and around candump's start). No 11-bit IDs above `4FF`, no 29-bit
IDs, no diagnostic traffic (`7DF`, `7E0`–`7EF`): nobody was polling.

Rough bus load, without bit stuffing: 16 %.

| ID | Rate (Hz) | Period (ms) | Jitter σ (ms) | DLC | Distinct payloads | Bytes that changed | Payload (first) | Meaning |
|---|---|---|---|---|---|---|---|---|
| `105` | 62.4 | 16 | 0.05 | 8 | 1 | — | `00450045C8276C80` | unknown |
| `106` | 62.4 | 16 | 0.06 | 8 | 1 | — | `62000200019D0000` | unknown |
| `200` | 124.9 | 8 | 0.06 | 8 | 1 | — | `0200019D03B10000` | unknown |
| `201` | 124.9 | 8 | 0.06 | 8 | 2 | 7 | `00003FFF00000080` | unknown. Byte 7 flickers `80`↔`7F` (140 of 14 984 frames), like an analogue value at a step boundary |
| `212` | 41.7 | 24 | 0.14 | 8 | 1 | — | `0000FFFE00000000` | unknown |
| `215` | 41.7 | 24 | 0.10 | 8 | 1 | — | `277A277A277A0000` | unknown |
| `217` | 41.7 | 24 | 0.19 | 8 | 1 | — | `0000000000000000` | unknown |
| `225` | 124.9 | 8 | 0.30 | 8 | 1 | — | `00FF00000000002D` | unknown |
| `230` | 31.2 | 32 | 0.13 | 8 | 1 | — | `F0018F0000000000` | unknown |
| `420` | 10.4 | 96 | 0.06 | 8 | 1 | — | `2E000040400000FF` | unknown |
| `430` | 33.3 | 30 | 0.29 | 8 | 7 | 1 | `FDE9FF0000004000` | unknown. Byte 1 wanders `E5`–`EB`, changing every few frames, like a noisy sensor |
| `440` | 10.1 | 99 | 0.26 | 8 | 1 | — | `0000000000000000` | unknown |
| `4D0` | 1.0 | 1001 | 0.37 | 8 | 1 | — | `3C44038C00000000` | unknown |
| `4FF` | 1.0 | 1057 | 0.27 | 8 | 3 | 0–6 | (VIN) | **VIN**, in three frames, see below |

### `4FF`: the VIN

Three payloads, sent in turn at about 1 Hz. Byte 0 is an ASCII index (`'0'`,
`'1'`, `'2'`). Bytes 1–6 are VIN characters, null-padded, byte 7 is `00`:

| Byte 0 | Bytes 1–6 (ASCII) |
|---|---|
| `'0'` | `1FTSW` + `00` (VIN 1–5) |
| `'1'` | `21PX7E` (VIN 6–11) |
| `'2'` | 6-character serial (VIN 12–17), redacted |

Joined, they make a 17-character VIN, `1FTSW21PX7E` + serial, whose ISO 3779
check digit (position 9, `X`) **validates**. That a random byte pattern would
pass the check, read as ASCII and fit a 2007 Ford truck is not plausible, so
this layout is taken as established. Still open: which module sends `4FF`,
and that the VIN matches the one on the truck's door and dash (the owner can
check it against the full value in the raw log).

## Capture 2: idle, with turn signals and reverse [TRUCK]

Same 14 IDs at the same rates; error-active before and after, counters at 0,
no error frames.

**A 122 s jump in the frame times, not a dropout.** From +105.0 s to
+227.4 s the log has no frames, but none were lost: the capture holds exactly
120 s of frames (85 392 at 712/s, the length `capture 120` records), and the
values either side of the jump are the same steady idle. The Pi's **wall
clock jumped forward** 122 s while candump ran, and candump stamps frames with
the wall clock. Shown on 2026-11-07 13:18 (capture 5): the same kind of
"silence", 391.6 s, while `counters.log` (5 s samples) jumped from 13:19:02
straight to 13:25:39 with only about 5 s of frames counted in between. The
Pi's RTC has no working battery (it boots at 1970, systemd sets the last
shutdown time, and NTP then jumps the clock forward by however long the Pi
was off: [bench-log](../hardware/bench-log.md), H20). `can.sh capture` now
records the uptime in `counters.log` and compares the wall clock with the
monotonic clock at the end. All the actions happened before the jump.

### Reverse: found (event-matched candidates)

The two P→R→P cycles are at +24.1 → +30.7 s and +35.4 → +39.7 s. Many IDs
change at exactly those moments. The cleanest:

| ID / byte | Park | Reverse | Notes |
|---|---|---|---|
| `230` byte 0 | `F0` | `10` | Changes only at the shifts. In the drive (capture 3) the low nibble steps `01`→`02`→`03`→`05`→`06` while accelerating and back down while slowing (`04` never appears), so it looks like gear position; the high nibble is `F` in P, `1` in R, `0` driving. 2026-11-08 (VERIFICATION_LOG): P `F0`, R `10`, N `F1`, D `01` at the lever, and while moving the low nibble is exactly half the TCM's gear DID `22 11 B3` |
| `420` byte 3 | `40` | `01` | One bit per lever position? Pulling out of P at the start of the drive it goes `40` → `01` → `80` → `10` within 0.4 s, which would fit P → R → N → D, then stays `10` while driving |
| `105` byte 7, `106` bytes 2–3 | | | Also change at each shift |

These match an action the owner did, twice, to within the 32 ms frame
period, but nobody timed the shifts independently. Status: **candidate**, not
a decoder.

### Brake pedal: candidate

`440` byte 0 bit 4 (`00`→`10`) sets about 1.3 s **before** each shift out of
P and clears about 0.4 s **after** each shift back, with a few short drops in
between during the second cycle. That is what the brake-shift interlock
needs: brake on, shift, shift back, brake off. In the drive it is set from
+58.4 to +63.9 s, while the wheel-speed-like values (below) fall nearly to
standstill, and again at +116.8 s. `201` byte 0 bit 7 changes within 0.1–0.2 s
of it. Status: **candidate**; the owner didn't report pressing the brake, and
the stoplamps weren't checked.

### Turn signals: not on the bus

No bit in any ID toggles at a flasher rate (about 1–2 Hz) anywhere in the
capture. Before the first shift (+0 to +22 s), where the turn signals must
have been if they were inside the capture, the only bits that change belong
to values that drift all the time (`105`, `106`, `200`, `201`, `225`, `420`,
`430`). **Settled** by the owner (2026-11-07): the turn signals are an
analogue circuit switched by a flasher relay under the dash, not by a module,
so nothing on HS-CAN carries them. They need opto inputs (H14).

## Capture 3: driving [TRUCK]

Same 14 IDs, 712 frames/s, no gaps over 20 ms, no errors. Values that track
the drive. All **candidates** with no scaling claimed until checked against
the PIDs in the same session (Stage B):

| ID / bytes | KOEO | Idle | Drive | Looks like |
|---|---|---|---|---|
| `201` bytes 0–1, top bit masked | 0 | 743–857 (median 786) | 669–2327 | Engine RPM at 1 rpm per count. To check against PID `0C` |
| `215` bytes 0–1, 2–3, 4–5 | 10106 each | 10106 (byte 4–5 blips at each shift into P) | 10106–15789, the three moving together | Three wheel or axle speeds, with 10106 (`277A`) at standstill. To check against PID `0D` |
| `420` byte 0 | `2E` | `2F`→`3A` | `3B`→`49` | Rises steadily as the engine warms, like a temperature. To check against ECT, PID `05` |
| `230` byte 0 | `F0` | `F0` / `10` | `01`…`06` | Gear position (see capture 2) |
| `105` bytes 0–1, `225` bytes 2–3 | | | | Also track the drive. Unidentified |

### Against the MX+ sessions (different days: supporting only)

The MX+ drive on 2026-11-03 (`20261103-154423-obdlink`) can't be lined up
with these captures frame by frame, but its ranges can be compared:

| | MX+ PID (2026-11-03) | CAN candidate (2026-11-07) |
|---|---|---|
| Idle RPM, cold (MX+: ECT < 20 °C, speed 0) | avg 787, 755–927 | `201` idle: median 786, 743–857 |
| Idle RPM, warm (MX+: ECT ≥ 40 °C) | avg 689, 657–749 | not captured warm |
| Drive RPM max | 2372 | `201`: 2327 |

The cold-idle match supports `201` bytes 0–1 being RPM at 1 rpm per count.
If `420` byte 0 is a temperature with the SAE offset of 40, the idle capture
was at 7–18 °C, which is the MX+'s cold band. Both are consistent stories, not
proof. Speed can't be compared this way: the drives were different.

Rates: the MX+ refreshed RPM at 4.1 Hz, speed at 2.7 Hz and ECT at 1.3 Hz
(11.7 requests/s in all, about 85 ms per answer). The broadcast candidates
arrive at 125 Hz (`201`), 41.7 Hz (`215`) and 10 Hz (`420`).

## Capture 4: driving beside the MX+, PID answers in the same log [TRUCK]

The MX+ polled through a Y-splitter while the adapter listened, so the MX+'s
requests (`7DF`) and the PCM's and TCM's answers (`7E8`, `7E9`) are frames in
the same log as the broadcasts, timed by the same clock. The gateway polled
from 13:01:24 to the end with no failure on any signal (after two connection
attempts at start-up, while the MX+ woke up). No silence over 1 s, no error
frames, kernel log quiet. The same 14 broadcast IDs, plus `7DF`, `7E8`, `7E9`.

### Broadcast fields against the PIDs

Analysed with `can-monitor` (`pids`, then `correlate` per signal). The PID
side is decoded with the registry: SAE formulas, and `trans_temp`
(VERIFIED_ON_TRUCK). Each row then checks an exact scaling against every PID
answer (the latest broadcast frame at or before the answer):

| Broadcast field | Scaling tested | PID | n | r (fit) | PID − broadcast | Status |
|---|---|---|---|---|---|---|
| `201` bytes 0–1, top bit masked | rpm = raw | `0C` RPM (652–2223) | 1608 | 1.0000 (slope 0.9998, +0.6) | median \|d\| 0.75 rpm, p95 5.8, max 21.8 while revving | **corroborated, one drive** |
| `201` bytes 4–5 | km/h = raw / 100 | `0D` speed (0–43) | 1033 | 0.9996 | mean −0.52, p95 \|d\| 1.2: the PID is whole km/h, the broadcast hundredths | **corroborated, one drive** |
| `420` byte 0 | °C = raw − 40 | `05` ECT (46–54) | 524 | 0.9955 (slope 0.995, −39.5) | 93 % exact, never more than 1 | **corroborated, one drive** (8 °C span only) |
| `106` byte 7 | % = raw × 100/255 | `04` load (7–73 %) | 514 | 0.9996 (slope 0.394) | 79 % exact, median 0 | **corroborated, one drive** |
| `225` byte 7 | °C = raw − 40 | TCM `22 16 74` trans temp (37–46 °C) | 525 | 0.9946 (slope 0.97, −37.3) | mean +0.50, max 1.1: whole degrees against the PID's 1/8 °F | **corroborated, one drive** (9 °C span only) |
| `215` bytes 0–1, 2–3, 4–5 | km/h ≈ (raw − 10106) / 100 | `0D` speed | 1033 | 0.9989–0.9994 (slope 0.0101) | mean +0.30, p95 \|d\| 1.0 | candidate: speed-like (three wheels?), scaling not settled |
| `225` bytes 4–5 | — | `0D` speed | 1033 | 0.9992 (slope 0.0387) | — | candidate: another speed-like value, unit unknown |
| IAT | no field fits (best \|r\| 0.90, a temperature drifting the other way) | `0F` IAT | 141 | — | — | not found |

"Corroborated, one drive" is Stage B evidence, not a decoder: it needs a
repeat on another day (a cold start, a longer drive, so the temperatures span
more than 8–9 °C) and then a `VERIFICATION_LOG.md` entry, before the gateway
may decode it (`BROADCAST_DECODED`). The broadcasts arrive far faster than the
MX+ polls: RPM and speed at 125 Hz against 4.8 Hz and 3.1 Hz, load at 62 Hz,
ECT at 10 Hz and trans temp at 125 Hz against about 1.5 Hz each.

### Answer timing on the wire

From each `7DF` request to the first frame of each answer, 4408 requests:

| Responder | Median | p95 | Max |
|---|---|---|---|
| PCM `7E8` | 21 ms | 39 ms | 40.7 ms |
| TCM `7E9` | 16 ms | 28 ms | 31.8 ms |

Either module may answer first: on `01 0C` the TCM led 1037 times and the PCM
570. On `22 16 74` (PCM refuses with NRC 31, TCM answers) the TCM led 325
times and the PCM 200. Three answers were missing (of about 8800), around the
end of the capture. So the CAN transport's 50 ms window
([ADR-0012](../architecture/adr/0012-direct-can-usb-adapter.md)) covers
every answer seen, with about 9 ms to spare.

The MX+ pads its requests with `00`, like the gateway's CAN transport.

EOT wasn't polled (no `ENABLE=eot`), so the EOT dropout experiment (Phase
4.7) is still to do; this drive had no dropouts on `trans_temp`, the other
signal that two modules answer and that is pinned to one of them.

## Capture 6: the EOT dropout, seen on the wire [TRUCK]

Idle, warm (ECT 52 °C, EOT 53.7–53.8 °C, trans 44.9 °C), the MX+ polling
everything including EOT (`22 13 10`). 970 requests, all matched one for one
between the gateway's traffic log and the wire. On the wire **every one of the
104 EOT requests got the PCM's answer** (`7E8 62 13 10 …`), and the TCM's
refusal (`7E9 7F 22 12`). The gateway logged one miss (`eot: ACTIVE → SUSPECT
(NoResponse ×1)`). That request, #189:

```
MX+ (gateway clock, includes Bluetooth)      wire (candump)
  18677 TX 221310                              +0.0 ms  7DF 03 22 13 10 …
  +12 ms RX 7E9037F2212                        +6.4 ms  7E9 03 7F 22 12 …
  +42 ms RX >      (window closed)             +39.5 ms 7E8 05 62 13 10 24 A0 …
```

The PCM answered at +39.5 ms, within its usual time (capture 4: up to
40.7 ms), but the MX+ had already closed its window after the TCM's early
refusal (adaptive timing, `ATAT1`). So the 2026-11-03 explanation
(VERIFICATION_LOG) is confirmed on the wire: the answer was on the bus, the
ELM cut it off. One miss in 104, the same rate as on 11-03. Since EOT is
pinned to 7E8 it costs one reading (`SUSPECT`), not a 60 s quarantine.

Not fixed on the MX+: an ELM receive filter (`ATCRA 7E8`) for pinned
requests should make the adapter ignore the TCM's refusal and wait for the
PCM. UNVERIFIED until tried on the truck. The CAN transport doesn't have the
problem: it waits its own 50 ms window.

EOT against the broadcasts: idle at a steady temperature, so no field can be
fitted. That needs a warm-up drive.

## What captures 1–6 settle

- **500 kbit/s is right** and the adapter, wiring and listen-only setup work
  on the truck: 85 390 frames, no errors, counters at 0.
- The broadcast set: the same 14 IDs at key on, at idle and driving.
- Reverse is on HS-CAN (candidates above), so the reversing camera can come
  from a broadcast once a decoder is corroborated (Stage B).
- Turn signals: not on HS-CAN. They are an analogue flasher-relay circuit (owner); they need opto inputs.
- The adapter path didn't drop out: both "silences" (captures 2 and 5) were
  the Pi's wall clock jumping forward after boot. No capture lost frames.
- The MX+'s EOT misses are the ELM closing its window early; the PCM's answer
  was on the bus (capture 6).
- RPM, speed, ECT, load and trans temp are broadcast, and their scaling agrees
  with the PIDs on one drive (capture 4).
- Every module answered within 41 ms: the 50 ms CAN window is enough.

## Still to capture

- A second corroboration drive on another day, from a cold start and longer,
  so ECT and trans temp span more than 8–9 °C; then `VERIFICATION_LOG.md`
  entries for the fields above. Add `ENABLE=eot` and check EOT against the
  broadcasts too.
- The [event captures](../setup/can.md#event-captures-reverse-and-brake),
  one action per capture, to confirm reverse and brake.
- A warm-up drive with `ENABLE=eot`, to look for EOT among the broadcasts.
- Record the truck state (key position, engine) with each capture.
