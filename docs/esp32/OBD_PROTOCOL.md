# OBD / ELM327 / OBDLink protocol notes

How this firmware talks to the OBDLink MX+, and why each choice was made.

## Transport

Bluetooth Classic **SPP** (Serial Port Profile). The ESP32 runs as SPP *master*
(`BluetoothSerial::begin(name, /*isMaster=*/true)`) and initiates the connection.
`1234` is the commonly documented legacy PIN. When the owner paired this MX+
on 2026-11-01, though, it used **Secure Simple Pairing**: a one-time passkey
was displayed and nothing had to be entered (see
[bench-log.md](../hardware/bench-log.md)). The firmware's `kObdPin` only
matters if a legacy-PIN exchange is ever requested.

- `connect(name)` runs a discovery scan first: **10–30 s, blocking**.
- `connect(mac)` skips discovery: a few seconds. The firmware logs the adapter's
  MAC on every successful connection so it can be pinned in `Config.h`.
- `ESP_SPP_CLOSE_EVT` from the BT stack is treated as the authoritative
  disconnect signal (polling `connected()` reacts late).
- The MX+ accepts **one** SPP master at a time — a phone still paired/connected
  (Torque, OBDLink app) blocks the ESP32.

## Initialization sequence

Sent after every (re)connect and after every full reset:

| Command | Effect | Why |
|---|---|---|
| `ATZ` | full reset | known state; also wakes a sleeping STN. Ident banner captured. |
| `ATE0` | echo off | echo wastes throughput. Until it takes effect, echoed lines are filtered by comparing against the last sent command. |
| `ATL0` | linefeeds off | responses are `\r`-delimited only |
| `ATS0` | spaces off | halves response byte count (parser tolerates spaces anyway) |
| `ATH1` | **headers on** | responses carry the CAN ID + ISO-TP PCI, which the parser needs to attribute frames to ECUs and reassemble multi-frame messages |
| `ATAT1` | adaptive timing | adapter tunes its own response timeout |
| `ATSP0` | protocol auto | first data request triggers `SEARCHING...`; expected to land on ISO 15765-4 CAN 11-bit/500k for this truck. Pin to `ATSP6` in `Config.h` once confirmed. |

The list lives in `Config.h` (`kElmInitCommands`) — it is data, not code. A
command answering `?` is retried once, then skipped with an ERROR log (some
settings may be unsupported; real damage surfaces in the request path).

## Request/response lifecycle

The ELM is half-duplex with an explicit turn marker: after a command, the
adapter emits response lines and then the **`>` prompt**. The state machine
(`ElmClient`) enforces one command in flight:

```
Idle ──submit──► AwaitingResponse ──'>'──► Idle (result delivered)
  ▲                    │ timeout
  │                    ▼
  └──'>'── Recovering (bare CR to provoke a prompt)
```

- Requests are `01 xx` (SAE Mode 01) or `22 xxxx` (Ford enhanced read-by-DID),
  written as e.g. `010C\r` / `221310\r`.
- The **first** data request after init gets a long deadline (10 s default)
  because `SEARCHING...` may run; later requests use the per-PID timeout
  (500 ms default) under `ATAT1`.
- If a PID's module needs a different header, `ATSH <hdr>` is sent first and its
  `OK` awaited before the actual request. Modules with unverified headers are
  refused, never guessed.

## Response parsing (with ATH1 + ATS0, 11-bit CAN)

```
7E8 04 41 0C 1A F8            (shown with spaces for clarity; ATS0 removes them)
└┬┘ └┬┘ └───────┬──────┘
CAN  PCI  data: 41 0C = positive response echo (0x01+0x40, PID 0x0C)
ID   SF,          1A F8 = payload → (0x1A·256+0xF8)/4 = 1726 rpm
     4 bytes
```

- Odd-length hex lines ⇒ first 3 chars are an 11-bit CAN ID; even-length lines
  are treated as headerless payload (works if someone runs ATH0).
- **ISO-TP**: payloads >7 bytes arrive as a first frame (`10 LL`, 6 bytes) plus
  consecutive frames (`21`, `22`, …). Frames are grouped by CAN ID because a
  functional (7DF) query can make several ECUs answer interleaved. Single frames
  complete immediately.
- The positive-response echo (`41 xx` / `62 xx xx`) is validated against the
  in-flight request and stripped; decoders see pure payload.
- `7F <svc> <NRC>` negative responses are surfaced as errors with the NRC logged.

### Several ECUs answering one request

On this truck **two modules answer every functional request**, in varying order:

```
TX> 010C
RX< 7E904410C0AE0
RX< 7E804410C0AE0
```

That is normal for `7DF` — it is a broadcast. What matters is what the firmware
does with it:

- **Every** answer is kept, in arrival order, with its CAN ID
  (`ElmResponse::responders`, up to `kMaxRecordedResponders`; `responderCount`
  stays honest even beyond that). The first one is the reported value, because
  "we do not yet know which module owns this DID" is the honest default.
- `ElmClient` states a fact — `respondersDiffer`, meaning the bytes are not
  identical — and passes no judgement. That distinction matters:

> **Differing bytes are not a disagreement.** On this truck 7E8 and 7E9 both
> answer `010C`, and at a 690 rpm idle they return values like `0AC4` (689.00)
> and `0AC2` (688.50). The bytes differ on nearly every request; the *meaning*
> does not. It is one crank signal sampled a few milliseconds apart. An earlier
> build compared bytes and logged `RESPONDER CONFLICT` at WARN roughly once per
> request — a false alarm that buried everything else on the port.

- The real question — do these modules mean the same thing by this DID? — is
  answered by **decoded** values across several samples.
  `PidStats::maxResponderSpread` tracks the largest gap between responders'
  decoded values in channel units, and the console's `probe` prints every
  responder side by side. ~1 rpm means agreement; a spread the size of the value
  means two different quantities.
- Once a session proves ownership, `PidDefinition::expectedResponder` pins the
  PID to that CAN ID; other modules' frames are then dropped *before* ISO-TP
  reassembly, and a silent owner yields `NoResponder` rather than looking like a
  dead PID.

## Adapter status lines handled

| Line | Meaning | Action |
|---|---|---|
| `NO DATA` | no ECU answered | per-PID failure → scheduler backoff (may just mean ignition off) |
| `STOPPED` | adapter aborted (a char arrived mid-request) | result `Stopped`; scheduler retries. The state machine's one-in-flight rule prevents self-inflicted cases. |
| `SEARCHING...` | protocol auto-detect | extend deadline |
| `CAN ERROR`, `BUFFER FULL`, `UNABLE TO CONNECT`, `?` | various faults | result `Error` |
| `ACT ALERT`, `LV RESET`, `SLEEPING`, `WAKE` | unsolicited STN power-management chatter | logged, ignored — never mistaken for a response |

## Recovery ladder

1. Timeout → bare CR, wait for `>` (`Recovering`).
2. 3 consecutive timeouts, or recovery fails → full `ATZ` re-init (STN likely slept).
3. 2 failed resets → `Offline`; the OBD task tears down Bluetooth and reconnects
   from scratch with exponential backoff (2 s → 30 s).

## Throughput budget

**Measured on the truck: ~96 ms per round trip ⇒ ~10 requests/s.** From the log,
a `010C` written at t=89607 ms saw its `>` prompt at t=89703 ms, with both ECU
replies arriving at 89625 and 89655 — most of the time is the adapter waiting out
its P2 timeout for stragglers, not the Bluetooth link.

That figure lives in `config::kMeasuredRequestsPerSec`. Poll intervals in the PID
table are *targets* spent from it; the scheduler's priority field decides who
wins when oversubscribed (RPM/MAP = 0 … battery/baro = 4–5), and it now logs a
warning when the enabled set asks for more than 80 % of the budget. A table that
promises 10 Hz while delivering 2 Hz is a lie told to the driver — measure with
the console's `stats`, then set the intervals to what the link can actually do.

Two levers, to be tried in this order (see [CONSOLE.md](CONSOLE.md)):

1. **Physical addressing** (`ATSH 7E0` instead of `7DF`) so only one module
   answers. On 11-bit CAN the ELM derives the expected response ID from ATSH on
   its own, so `ATCRA` is opt-in and only needed if something still gets through.
2. **The response-count digit** (`010C1`, `2213101`), which makes the adapter
   return as soon as N replies arrive. Only safe *with* physical addressing:
   on `7DF`, asking for fewer responses than the bus produces leaves a straggler
   to land mid-way through the next request and desync the adapter (`STOPPED`).
   The firmware enforces this — `expectedResponses` must be 0 on a functional
   header, asserted over the whole table in `test_pid_defs`.

Raw-traffic logging (`kLogRawObdTraffic`) costs real throughput — turn it off
when not verifying PIDs (`log raw off` does it without a reflash).
