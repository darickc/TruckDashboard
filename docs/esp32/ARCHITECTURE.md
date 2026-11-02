# Architecture

## Design goals

1. One ESP32-WROOM-32 does everything: Bluetooth to the MX+, decoding, data
   model, warnings, display.
2. The display must stay responsive no matter what Bluetooth/OBD is doing.
3. The exact AMOLED is unknown → nothing may depend on a graphics library.
4. Most of the firmware must be testable on a desktop without the truck.

## Module map

```
┌────────────────────────────  src/  ────────────────────────────┐
│ main.cpp        wiring + task startup only                     │
│ ObdTask.cpp     OBD task loop + result handler (decode→store)  │
│ UiTask.cpp      UI tick (derived → warnings → render)          │
│ ConsoleHost.cpp Serial in/out for the console (loopTask)       │
└────────────────────────────────────────────────────────────────┘
          │ uses                                     │ uses
┌─────────▼──────────────  lib/ObdCore  ─────────────▼──────────┐
│ IObdTransport.h   byte-stream interface (connect may block)   │
│ ElmParser         lines, classification, hex, ISO-TP          │
│ ElmClient         non-blocking command state machine          │
│ PidDefs           data-driven PID table (SAE + Ford 22 xxxx)  │
│ Decoders          linear/custom payload decoding              │
│ PidScheduler      per-PID interval/priority/backoff           │
│ VehicleData       channels: value + timestamp + validity      │
│ Derived           boost = MAP − baro, EOT−ECT delta           │
│ Warnings          thresholds + hysteresis + staleness         │
│ Units             unit tags + conversions                     │
│      *** no Arduino.h anywhere in this library ***            │
└───────────────────────────────────────────────────────────────┘
   ▲ implemented by                ▲ consumed by
┌──┴───────────┐  ┌────────────────┴──┐  ┌───────────────────────┐
│ lib/ObdBt    │  │ lib/Display       │  │ lib/Telemetry (stub)  │
│ BtSppTrans-  │  │ IDisplay          │  │ lib/Sensors  (stub)   │
│ port (SPP    │  │ SerialDisplay     │  │ lib/Log (header-only) │
│ master mode) │  │ (AMOLED later)    │  │                       │
└──────────────┘  └───────────────────┘  └───────────────────────┘

┌──────────────────────────  lib/Console  ───────────────────────┐
│ ConsoleParser     line reading + argv tokenization             │
│ ConsoleCommands   grammar, PID/module resolution, deny-list    │
│ CommandMailbox    loopTask → OBD-task handoff (one slot)       │
│ ConsoleExecutor   runs commands against ElmClient/PidScheduler │
│      *** no Arduino.h here either — host-testable ***          │
└────────────────────────────────────────────────────────────────┘
```

## Concurrency model: two FreeRTOS tasks

**Why tasks and not a single cooperative loop:** `BluetoothSerial::connect()` in
master mode blocks for seconds (up to ~30 s with a discovery scan) and has no
non-blocking variant. In a single loop every reconnect would freeze the display.
Everything *else* is cooperative and non-blocking inside its task — tasks exist
only to isolate that one blocking call and decouple render cadence from link
stalls.

| Task | Core | Prio | Job |
|---|---|---|---|
| `obd` (ObdTask) | 1 | 3 | reconnect loop (blocking connect + backoff), `ElmClient::tick()`, console-command execution, scheduler `next()`→`submit()`, decode results into `VehicleData` |
| `loopTask` (UI + console) | 1 | 1 | every 10 ms: drain Serial for console input; every 250 ms: snapshot → `derived::update` → `WarningManager::evaluate` → `IDisplay::render` |

Core 0 is left to the Bluetooth controller/stack tasks. Both tasks call
`vTaskDelay()` every iteration (2 ms / 10 ms), which keeps the idle task fed and
the task watchdog quiet — including between reconnect attempts. The UI keeps its
own 250 ms cadence inside the faster loop rather than being dragged along with it.

## Shared-data protection

Two objects cross a task boundary: `VehicleData` and the console's
`CommandMailbox`.

**`VehicleData`** is guarded by a single FreeRTOS mutex, installed via injected
lock hooks (`setLockHooks`) so the core library stays RTOS-free (tests install
no-ops). Writers (OBD task) hold it for a few stores. The UI takes it once per
frame to copy a `Snapshot` (value copy of all channels), then renders lock-free.
Rendering can never block the OBD task.

**`CommandMailbox`** carries console commands the other way, and takes no lock at
all. It is a single slot with one `std::atomic<State>`; each transition is owned
by exactly one task (producer: Idle→Pending, Done→Idle; consumer:
Pending→Running, Running→Done) and the payload is only touched by whichever task
owns the current state, so acquire/release ordering is sufficient. One command in
flight at a time; a second `post()` is refused rather than dropped.

`ElmClient::state()` is an atomic read (status display only). `PidScheduler` and
`ElmClient` internals stay OBD-task-private — **the console never touches them
directly**, which is the entire reason the mailbox exists. There is no dynamic
allocation after `setup()` and no `String` anywhere in the data path — fixed
buffers throughout.

## Data flow (one RPM sample)

```
scheduler.next() → elm.submit(RPM) → "010C\r" → MX+ → truck PCM
MX+ → "7E804410C1AF8" + ">" → ElmParser (line → frame → ISO-TP) 
    → ElmClient validates echo 41 0C, strips it
    → result handler: decodePid() → 1726 rpm → convertUnit → VehicleData.set(Rpm, …, now)
UI tick: snapshot → warnings → SerialDisplay.render() → "RPM: 1726"
```

## Failure handling ladder

1. **Request timeout** → deliver `Timeout` to the scheduler (per-PID retry/backoff),
   send a bare CR to provoke a prompt (`Recovering`).
2. **3 consecutive timeouts** or recovery failure → full `ATZ` re-init (the STN may
   have gone to sleep; unsolicited `ACT ALERT`/`LV RESET` lines are tolerated).
3. **2 failed resets** → `ElmClient` goes `Offline`; the OBD task drops the
   Bluetooth link entirely and re-runs the connect loop with backoff.
4. **SPP close event** (adapter unplugged, ignition off) → immediate reconnect
   loop; `PidScheduler.resetTiming()` on reconnect.

Per-PID failures (NO DATA, decode errors) never escalate — they back off
exponentially per PID so one dead PID can't starve the rest.

## Why the core is platform-independent

`ElmClient` receives an `IObdTransport&` and a `TimeFn` (function pointer to
`millis` or a virtual test clock). That single decision makes the entire protocol
stack — parser, state machine, scheduler, model, warnings — compile and run under
Apple clang/Unity on the host (`pio test -e native`) against a scripted
`MockTransport`, which is where all the tricky logic is exercised (timeouts,
STOPPED, ISO-TP reassembly, wraparound…). See [TESTING.md](TESTING.md).
