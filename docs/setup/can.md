# Direct CAN with the USB adapter

How to bring up the **Jhoinrch RH-02 Pro** USB CAN adapter on the Pi and use
it on the truck instead of the MX+
([ADR-0012](../architecture/adr/0012-direct-can-usb-adapter.md)).

Status:

- **Gateway transport** (`--transport can`): `[SIM]`. Tested against an
  in-memory bus replaying this truck's captured replies
  (`services/vehicle-gateway/tests/gateway_can.rs`). Compiled, linted and
  unit-tested on the Pi 5 (Linux arm64). With no adapter plugged in, the
  gateway reports `can0: No such device` and backs off (Pi, 2026-11-03).
- **Adapter:** arrived with the slcan firmware, which can't do listen-only
  (`[BENCH]` 2026-11-05, [bench-log](../hardware/bench-log.md)). Flashed
  with Candlelight 2.5 the same day: `can0`, `driver gs_usb` `[BENCH]`.
  Listen-only accepted at 500 kbit/s `[BENCH]`. Terminator and the truck:
  not done.

The order is the point of this page: bench first, then listen-only on the
truck, and only then polling.

**On AGL** the script is installed as `f250-can` and runs as root (no `sudo`).
The stock AGL image puts the adapter in normal mode by itself. Don't plug the
adapter in under AGL until `make deploy` has run and
`stage1-setup.sh --check` passes ([agl.md](agl.md), [ADR-0015](../architecture/adr/0015-agl-can-defaults.md)).

## 0. Once: tools

```bash
make pi-setup        # now also installs can-utils (candump, cansend, ...) and dfu-util
make pi-build        # the gateway now includes the CAN transport
```

## 1. Bench: what firmware is it running?

Plug the adapter into the Pi (Boot switch **up**, not DFU). Nothing else
connected to its terminals.

```bash
tools/pi/can.sh status
```

| You see | It means | Next |
|---|---|---|
| `can0: driver gs_usb` | candleLight-type firmware | Go to step 2 |
| `No can0`, and a serial port like `/dev/serial/by-id/usb-…CANable2…` | slcan firmware. **Ours came like this** (canable2-fw `b158aa7`, 2026-11-05) | Flash Candlelight 2.5 (below) |
| Neither, but `lsusb` lists `0483:df11` | It's in DFU mode | Boot switch up, replug |

### Flashing Candlelight 2.5 (if it came with slcan)

Why: the factory slcan firmware can't do listen-only. Its open command resets
the silent mode, and it has no `L` command
([bench-log 2026-11-05](../hardware/bench-log.md)). Mainline candleLight_fw
doesn't support the STM32G431. **Candlelight 2.5** (Elmue, MIT) does, and
shows up as a normal `gs_usb` device
([matrix](../hardware/compatibility-matrix.md#usb-can-adapter-jhoinrch-rh-02-pro)).

The STM32's ROM bootloader can't be overwritten. If anything goes wrong, Boot
switch down and flash again.

1. Unplug the adapter. Boot switch **down** (DFU). Plug it into the Pi.
   `tools/pi/can.sh status` should say it's in DFU mode.
2. Flash:

   ```bash
   tools/pi/can.sh flash
   ```

   It downloads the firmware from a pinned commit, checks its SHA-256, checks
   that the adapter is in DFU mode, asks you to type `flash`, then runs
   `sudo dfu-util`.
3. Unplug. Boot switch **up**. Plug it back in.
   `tools/pi/can.sh status`: expect `can0: driver gs_usb`.
4. Write the `status` output in [bench-log.md](../hardware/bench-log.md).

Which build: `flash` uses the **Multiboard** build (internal RC oscillator,
the same clock source as the factory firmware), which runs on any STM32G431
CANable. The firmware's manual says RH-02 boards have a 25 MHz crystal "since
2026". If you can see a crystal on the board (a small metal can marked
25.000), `BOARD=jhoinrch tools/pi/can.sh flash` uses it instead. The
Jhoinrch build on a board **without** the crystal probably won't start; DFU
and the Multiboard build fix that.

Candlelight 2.5 does CAN FD, but the truck is classic CAN at 500 kbit/s and
the gateway only uses classic frames.

## 2. Bench: listen-only comes up

```bash
tools/pi/can.sh listen
```

It sets 500 kbit/s and listen-only, brings `can0` up, and **refuses** (and
takes the interface back down) if the driver didn't accept listen-only.
Expect `LISTEN-ONLY` in the printed details. Record the output.

Also do the terminator checks on the wiring sheet's bench rows now
([dlc-can-adapter.md](../wiring/dlc-can-adapter.md)).

## 3. Truck, session A: listen-only capture

*Prerequisite:* the [wiring sheet](../wiring/dlc-can-adapter.md) is signed
off, including **termination off** and the ≈ 60 Ω reading.

Nothing in this session transmits: the interface is listen-only and the
gateway isn't running.

```bash
tools/pi/can.sh listen
tools/pi/can.sh capture 120          # KOEO: 2 minutes
tools/pi/can.sh capture 120          # idle
tools/pi/can.sh capture              # a drive; Ctrl-C to stop
```

Each capture goes to `~/f250-data/<date>-candump/`: the `candump` log of every
frame and error frame, and the interface's error counters before and after
(`session.txt`).

What it answers:

- **Is 500 kbit/s right?** Frames and no climbing error counters say yes. A
  wrong bitrate shows as no frames and errors (listen-only can't disturb the
  bus while you find out).
- **The broadcast census** (Phase 4.3, results in
  [CAN_CENSUS.md](../diagnostics/CAN_CENSUS.md)): which IDs the modules send without
  being asked, and how often.

### Event captures: turn signals and reverse

These decide whether the turn signals can come from HS-CAN, or need two more
opto inputs ([ADR-0013](../architecture/adr/0013-dcdc-usb-power-supply.md),
[H14](../hardware/open-questions.md)). They are still listen-only.

Take **one capture per action**, so each file holds one event. Key on, engine
off (KOEO), parked, with the parking brake set. Write the action and the
folder name in `bench-log.md` as you go: the folder name is the only label.

```bash
tools/pi/can.sh capture 30           # 1. baseline: nothing touched
tools/pi/can.sh capture 30           # 2. left turn signal on for the whole capture
tools/pi/can.sh capture 30           # 3. right turn signal
tools/pi/can.sh capture 30           # 4. hazards
tools/pi/can.sh capture 30           # 5. in reverse, reverse lamps on (brake/clutch held)
tools/pi/can.sh capture 30           # 6. headlights on (a spare data point)
```

How to read them:

- A **turn signal** shows as bytes in one ID that toggle at the flasher rate
  (roughly 1–2 Hz) in capture 2. A different bit toggles in capture 3. Both
  toggle in capture 4. **None of it** toggles in capture 1.
- **Reverse** shows as a byte that changes when R is selected in capture 5 and
  stays steady otherwise. On this truck it may come from the TCM's gear
  position.
- **Nothing found** means the turn signals are not on HS-CAN. The GEM is
  reportedly on the K-line, so that is the expected answer. It is then settled:
  wire two more opto-board channels ([wiring](../wiring/power-and-inputs.md)).
- **Something found** is only a candidate. Repeat it on another day, check
  that the toggle tracks the stalk and the flasher, and record it in
  `VERIFICATION_LOG.md`. It becomes a Stage B decoder (Phase 4.4) with its
  provenance. **Until then the camera doesn't use it.**

`can-monitor census` lists, per ID, which bytes change in one capture (see
[Analysing a capture](#analysing-a-capture)). Comparing two captures directly
(a diff of the IDs and bytes that change) is still TODO; until then, run
`census` on each and compare.

**With the MX+ on a Y-splitter and the gateway polling through it** (`make
pi-start TRANSPORT=obdlink TRANSMIT=1 ENABLE=eot CAPTURE=1`), the capture also
records the MX+'s requests and every module's answers on the wire. That is
the dropout experiment (Phase 4.7). For each EOT window the MX+ cut short,
the capture says whether the PCM's answer was on the bus. It also shows what
the MX+ pads its requests with.

### Analysing a capture

`tools/can-monitor` reads a `candump` log offline, on the Pi or on the Mac
after copying the folder over. It decodes PID answers with the signal
registry (`shared/signals`) and never touches a bus.

```bash
cargo build --release -p can-monitor          # make pi-build also builds it
target/release/can-monitor census  ~/f250-data/<date>-candump/candump-*.log
target/release/can-monitor pids    ~/f250-data/<date>-candump/candump-*.log
target/release/can-monitor correlate ~/f250-data/<date>-candump/candump-*.log --signal rpm
```

- `census`: every ID's rate, period, jitter, length and which bytes change,
  plus any silence over 1 s.
- `pids`: the tester's requests (and what it pads them with) and every
  module's answers, decoded with the registry, per responder, with each
  definition's provenance. Negative responses and multi-frame answers are
  counted, not decoded.
- `correlate --signal ID`: tries every 8- and 16-bit field of every broadcast
  ID against that PID and lists the best fits as `pid ≈ slope × raw +
  intercept` with the correlation `r`. `--field 215:0:u16be` fits only the
  fields you name; `--responder 7E8` picks one module when two answer.

Correlation needs PID answers **in the same log**. Record them with the MX+
on the Y-splitter, polling, while the CAN adapter listens:

```bash
tools/pi/can.sh listen                                  # once per boot; needs sudo
make pi-start TRANSPORT=obdlink TRANSMIT=1 CAPTURE=1    # MX+ polls; can0 is captured
make pi-stop                                            # after the drive
```

`CAPTURE=1` runs `can.sh capture` alongside the gateway, starting before it
and stopping after it, into the session's own folder:
`~/f250-data/<date>-obdlink/candump/` holds the `candump` log, `kernel.log`,
`counters.log` and the gap report, next to the gateway's traffic log and the
recorder database. It refuses to start unless `can0` is already up, because
bringing it up needs `sudo`, which `pi-start` can't ask for.

Drive with stops, idling and several gears: RPM and road speed are nearly
proportional within one gear, so a steady cruise can't tell them apart. A
good fit is a **candidate**: Stage B (Phase 4.4) and a
`VERIFICATION_LOG.md` entry come before any decoder.

## 4. Truck, session B: the gateway polls over CAN

*Prerequisite:* session A looked right: frames, no error counters climbing.

```bash
tools/pi/can.sh active               # asks you to type 'active'
make pi-start TRANSPORT=can TRANSMIT=1 ENABLE=eot CAPTURE=1
make pi-stop                         # when done
tools/pi/can.sh listen               # back to listen-only
```

`active` switches the interface to normal mode. It now ACKs frames, and the
gateway may transmit. With `CAPTURE=1` the session's `candump/` folder holds
the gateway's own requests (the kernel loops a socket's frames back to the
other sockets on the Pi) and every answer, so `can-monitor pids` can check
them against what the gateway recorded. `pi-start`/`pi-run` refuse `TRANSMIT=1` while the
interface is still listen-only. The MX+ must be unplugged or idle: one
transport polls at a time.

`obd-console` works the same way. Only `raw` differs: there is no ELM, so
lines are `[ID] HEX` instead of AT commands.

```
obd> pids
obd> probe eot 5
obd> raw 221310            # functional (7DF): every module's answer, with its time
obd> raw 7E1 010C          # physical, to the TCM: only 7E9 should answer
obd> raw 7E0 010C          # physical, to the PCM: only 7E8 should answer
obd> stats
```

The `raw` output shows the exact frame sent and every frame received, with
milliseconds since the request:

```
TX 7DF 03 22 13 10 00 00 00 00
+ 18 ms 7E9 03 7F 22 12 00 00 00 00
+ 40 ms 7E8 05 62 13 10 26 91 00 00
```

(That example is the fake bus's replay of the 2026-11-03 capture, not a
truck reading.)

The two `raw 7E1/7E0 010C` lines answer TRUCK_SESSION question 2 (does
physical addressing work?) without any `ATSH` subtleties. Paste them into
[VERIFICATION_LOG.md](../diagnostics/VERIFICATION_LOG.md).

When you're done:

```bash
make pi-stop
tools/pi/can.sh listen               # or: tools/pi/can.sh down
```

### What to look at afterwards

- `~/f250-data/<date>-can/traffic/adapter-traffic.1.log`: every frame sent
  and received, with millisecond times. `ER` lines are CAN error frames.
- `session.txt`: the interface's error counters at start and at stop.
- `stats`: requests per second. The CAN budget starts at 20/s (unmeasured;
  `BUDGET_RPS=` overrides it).
- EOT should never go `QUARANTINED` here: the gateway waits its own 50 ms
  window, so the PCM's answer can't be cut off the way the MX+ cut it.
