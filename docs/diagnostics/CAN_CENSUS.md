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
| 2 | 2026-11-07 11:34 | Engine idling, parked. Right turn signal, left turn signal, then P→R→P twice (owner; actions not timestamped) | 242 s, of which **122 s had no frames** | 85 392 | 0 | `20261107-113429-candump` |
| 3 | 2026-11-07 11:38 | Driving (owner) | 120 s | 85 390 (712/s) | 0 | `20261107-113837-candump` |

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

**A 122 s silence.** From +105.0 s to +227.4 s the log has no frames at all,
and the kernel's RX count agrees (85 403 frames in the whole 242 s), so frames
stopped reaching the Pi; candump didn't miss them. The truck didn't go quiet:
the values just before and just after the silence are the same steady idle
(e.g. `201` bytes 0–1 ≈ 780 both sides), with no wake-up pattern. The
interface wasn't reset (its counters continue) and reported no error state.
Cause **unknown**: an adapter or USB stall, or a wiring contact, are the
candidates. The Pi's journal is volatile and the Pi was powered off after the
drive, so its kernel log is gone. `tools/pi/can.sh capture` now records
`kernel.log`, `counters.log` (every 5 s) and a gap report with each capture.
Captures 1 and 3 had no gap over 20 ms. All the actions happened before the
silence.

### Reverse: found (event-matched candidates)

The two P→R→P cycles are at +24.1 → +30.7 s and +35.4 → +39.7 s. Many IDs
change at exactly those moments. The cleanest:

| ID / byte | Park | Reverse | Notes |
|---|---|---|---|
| `230` byte 0 | `F0` | `10` | Changes only at the shifts. In the drive (capture 3) the low nibble steps `01`→`02`→`03`→`05`→`06` while accelerating and back down while slowing (`04` never appears), so it looks like gear position; the high nibble is `F` in P, `1` in R, `0` driving |
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

### Turn signals: not seen

No bit in any ID toggles at a flasher rate (about 1–2 Hz) anywhere in the
capture. Before the first shift (+0 to +22 s), where the turn signals must
have been if they were inside the capture, the only bits that change belong
to values that drift all the time (`105`, `106`, `200`, `201`, `225`, `420`,
`430`). This agrees with the GEM, which runs the turn signals, being on the
K-line. Status: **not seen, one trial**. The actions weren't timestamped and
the turn signals weren't held for a known time, so repeat it the way
[the event captures](../setup/can.md#event-captures-turn-signals-and-reverse)
describe (one capture per action) before settling H14.

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

## What captures 1–3 settle

- **500 kbit/s is right** and the adapter, wiring and listen-only setup work
  on the truck: 85 390 frames, no errors, counters at 0.
- The broadcast set: the same 14 IDs at key on, at idle and driving.
- Reverse is on HS-CAN (candidates above), so the reversing camera can come
  from a broadcast once a decoder is corroborated (Stage B).
- Turn signals: probably not on HS-CAN (one trial).
- The adapter path can drop out silently (capture 2). Each capture now carries
  the evidence needed to say why next time.

## Still to capture

- Stage B corroboration: a drive with the gateway polling RPM, speed and ECT
  (session B, or the MX+ beside the capture) so the candidates above can be
  compared with the PIDs frame by frame.
- The [event captures](../setup/can.md#event-captures-turn-signals-and-reverse),
  one action per capture, to settle the turn signals (H14) and confirm
  reverse and brake.
- The dropout experiment beside the MX+ (Phase 4.7).
- Record the truck state (key position, engine) with each capture.
