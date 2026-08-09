# Testing

Most of the firmware is testable on a desktop, without the truck, because the
entire protocol stack (`lib/ObdCore`) is platform-independent: `ElmClient` talks
to an `IObdTransport` and gets time from an injected function pointer.

## Running the tests

```bash
pio test -e native            # all suites
pio test -e native -f test_elm_client   # one suite
```

No hardware needed. The `native` env compiles `lib/ObdCore` (+ header-only Log)
with Apple clang and Unity; Arduino-dependent libs are excluded.

## Suites

| Suite | Covers |
|---|---|
| `test_elm_parser` | line accumulation (`\r`, CRLF, `>` prompt), response classification (OK/NO DATA/STOPPED/SEARCHING/errors/STN chatter), hex parsing, header vs headerless data lines, ISO-TP single-frame, multi-frame, interleaved-ECU isolation, sequence errors |
| `test_decoders` | every enabled PID's actual table entry against hand-computed frames (RPM 1A F8 → 1726, EOT, FICM, ICP, IPR, VGT, MAP, trans temp, signed decode, gear, battery), truncated-payload rejection, unit conversions, channel display units |
| `test_scheduler` | due/priority selection, interval independence, failure→exponential backoff→recovery, unverified-header refusal, `millis()` wraparound |
| `test_vehicle_data` | set/snapshot, freshness windows, never-valid channels, error counting, derived values (delta, boost = MAP − baro), derived values refusing stale/missing inputs, lock-hook balance |
| `test_warnings` | Normal→Caution→Critical escalation, hysteresis (no flapping at a threshold), low-side rules (FICM), stale channels report Stale (old data is never judged), connection flag |
| `test_elm_client` | the full state machine over a scripted transport: init sequence order, request happy path (echo strip, payload delivery), NO DATA, STOPPED, negative response (`7F`), timeout → CR recovery → Idle, transport loss mid-request → Offline → clean re-init, refusal of unverified-header PIDs, no-double-submit. Plus responder identity (id/count reported, agreement vs conflict, pinned responder preferred even when it answers second, `NoResponder` when it stays silent, pinned multi-frame surviving interleaving), latency measurement, ATSH/ATCRA sequencing, the ATZ addressing-cache regression, and the response-count digit |
| `test_pid_defs` | table invariants that otherwise live only in comments: no duplicate `PidKey`, every row resolvable, decode widths, service/DID shape, every `kEnabledPids` entry present, `expectedResponder` inside 7E8..7EF, `expectedResponses` never on a functional header, `Pcm`/`Tcm`/`Abs` still unverified by default, and the runtime addressing-override lifecycle |
| `test_console` | line reading (CR/LF/CRLF, backspace, overflow discarding the whole line), tokenization (extra whitespace, tabs, argument-count truncation reported), scalar parsing (`5x` rejected rather than half-parsed), PID resolution by index/key/short name, the whole command grammar with its error messages, the `raw` deny-list and the `unsafe on` gate, and the mailbox handshake (post-while-busy, reply cleared between commands, truncation announced) |
| `test_console_executor` | the console driving a real `ElmClient` over `MockTransport`: `probe` reporting responder/value/latency and surfacing two ECUs disagreeing, `probe` refusing an unverified module and saying how to proceed, `raw` echoing reply lines verbatim and invalidating the addressing cache, `hdr` making a refused PID probeable with a candidate header, and a typed command preempting the poll rotation |

## MockTransport

`test/mocks/MockTransport.h` implements `IObdTransport` as a scripted step
machine:

```cpp
static const MockTransport::Step steps[] = {
    {"ATZ",  "\r\rELM327 v1.4b\r\r>", 50},   // expect write, reply after 50 virtual ms
    {"010C", "SEARCHING...\r7E804410C1AF8\r\r>", 300},
    {"010C", "NO DATA\r\r>", 20},
    {"",     "\r>", 20},                      // bare-CR recovery
};
```

Time is virtual (`MockTransport::nowFn` is injected into `ElmClient`), so
timeout tests take milliseconds of wall clock. `dropLink()` simulates the SPP
connection dying. `injectLater(data, inMs)` pushes bytes in off-script, which is
how a straggler ECU reply landing mid-way through the *next* request gets
modelled. Any unexpected or mismatched write is recorded and asserted against —
the scripts double as a golden log of exactly what the firmware sends, so
"did NOT send an ATSH" is as assertable as "did".

Multiple ECUs answering one request are just several `\r`-separated lines in a
single `response` string, in whatever order the truck produced them:

```cpp
{"010C", "7E904410C0AE0\r7E804410C0AE0\r\r>", 20},   // 7E9 first, as on the truck
```

To replay a new scenario (e.g. a weird response captured from the truck), paste
the raw lines into a script's `response` string — `\r` separators, `>` for
prompts — and assert on the delivered `ElmResult`/payload.

## On-target smoke test (bench)

1. `pio run -e esp32dev -t upload && pio device monitor`
2. Expect Bluetooth startup, connect attempts, and — with the MX+ powered —
   the init sequence and `RPM:` output (see README "First bench test").
3. Pull adapter power → verify `SPP link closed` → automatic reconnect.

## What is intentionally NOT unit-tested

- `BtSppTransport` (thin wrapper over BluetoothSerial; exercised on target)
- `SerialDisplay` rendering (visual, on target)
- FreeRTOS task wiring in `src/` (integration, on target)
