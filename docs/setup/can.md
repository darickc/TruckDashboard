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
- **Adapter, bench and truck:** not done. The adapter hasn't arrived.

The order is the point of this page: bench first, then listen-only on the
truck, and only then polling.

## 0. Once: tools

```bash
make pi-setup        # now also installs can-utils (candump, cansend, ...)
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
| `can0: driver gs_usb` | candleLight firmware | Go to step 2 |
| `No can0`, and a serial port like `/dev/serial/by-id/usb-…CANable…` | slcan firmware (what the manual's setup page says it ships with) | Flash candleLight (below) |
| Neither, but `lsusb` lists `0483:df11` | It's in DFU mode | Boot switch up, replug |

Write what you saw in [bench-log.md](../hardware/bench-log.md), with the
`lsusb` line. The manual contradicts itself on the factory firmware, so this
closes that question.

### Flashing candleLight (only if it came with slcan)

UNVERIFIED for this board: the RH-02 Pro is sold as a CANable 2.0 design,
and the CANable project offers candleLight firmware for the CANable 2.0, but
nobody has flashed this particular board here yet.

1. Boot switch **down** (DFU), plug it in. `lsusb` should show an STM DFU
   device.
2. Flash with the CANable project's web updater (canable.io, Chrome) or with
   `dfu-util`, choosing the **candleLight** build for the **CANable 2.0**.
3. Boot switch **up**, replug, run `tools/pi/can.sh status` again: expect
   `driver gs_usb`.

The candleLight build for the CANable 2.0 does not do CAN FD. The truck is
classic CAN at 500 kbit/s, so nothing is lost.

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
- **The broadcast census** (Phase 4.3): which IDs the modules send without
  being asked, and how often.

**With the MX+ on a Y-splitter and the gateway polling through it** (`make
pi-start TRANSPORT=obdlink TRANSMIT=1 ENABLE=eot`), the same capture also
records the MX+'s requests and every module's answers on the wire. That is
the dropout experiment (Phase 4.7). For each EOT window the MX+ cut short,
the capture says whether the PCM's answer was on the bus. It also shows what
the MX+ pads its requests with.

## 4. Truck, session B: the gateway polls over CAN

*Prerequisite:* session A looked right: frames, no error counters climbing.

```bash
tools/pi/can.sh active               # asks you to type 'active'
make pi-start TRANSPORT=can TRANSMIT=1 ENABLE=eot
```

`active` switches the interface to normal mode. It now ACKs frames, and the
gateway may transmit. `pi-start`/`pi-run` refuse `TRANSMIT=1` while the
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
