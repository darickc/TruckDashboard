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
| 1 | 2026-11-06 09:07 | Not recorded. Key on, engine off by the data (modules awake, every value static) | 120 s | 85 390 (712/s) | 0 | `20261106-090751-candump` |

## Capture 1: key on, engine off (by the data) [TRUCK]

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

## What capture 1 settles

- **500 kbit/s is right** and the adapter, wiring and listen-only setup work
  on the truck: 85 390 frames, no errors, counters at 0.
- The broadcast set at key on, engine off: 14 IDs.

## Still to capture

- Idle and a drive: which IDs change with RPM and speed (Stage B candidates
  against the RPM and speed PIDs).
- The [event captures](../setup/can.md#event-captures-turn-signals-and-reverse)
  for turn signals and reverse (H14).
- The dropout experiment beside the MX+ (Phase 4.7).
- Record the truck state (key position, engine) with each capture.
