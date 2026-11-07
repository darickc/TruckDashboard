# DLC → USB CAN adapter (Jhoinrch RH-02 Pro)

**Status: NOT VERIFIED. Nothing here has been connected yet.** A person must
check every line against the truck and the adapter, and sign it off in
[bench-log.md](../hardware/bench-log.md), before it touches the truck
([safety gates](../safety/assumptions.md#human-verification-gates)).

Temporary diagnostic hookup at the OBD-II connector (DLC), for the direct-CAN
trial ([ADR-0012](../architecture/adr/0012-direct-can-usb-adapter.md)). No
change to the truck's wiring. Not the permanent installation.

## What you need

- The RH-02 Pro, its USB-C cable, and its 3.81 mm terminal block.
- **A way to reach DLC pins 6, 14 and 5** without cutting anything: an OBD-II
  male breakout/pigtail (male J1962 plug to bare wires or screw terminals),
  ideally an OBD-II Y-splitter too, so the MX+ can stay plugged in beside it
  ([shopping list](../hardware/shopping-list.md)). The owner has one
  (2026-11-03). Its pinout is unchecked: do the continuity row in the
  sign-off table first.
- A multimeter.

## Connections

| DLC pin (SAE J1962) | Signal | RH-02 Pro terminal | Notes |
|---|---|---|---|
| 6 | HS-CAN high | **CAN H** | This truck's HS-CAN is on 6/14 at 500 kbit/s (protocol 6, verified 2026-08-09) |
| 14 | HS-CAN low | **CAN L** | |
| 5 | Signal ground | **GND** | The adapter's isolated-side ground. Gives the transceiver its common-mode reference |
| — | — | **5V** | **Leave unconnected.** It is an output from the adapter's isolated supply |
| 16 (battery +) | — | — | **Not connected.** The adapter is powered from the Pi's USB |
| 4 (chassis ground) | — | — | Not connected |

The adapter is galvanically isolated (1.5 kV power, 5.7 kV signal, per the
manufacturer's manual), so the Pi's USB ground and the truck's ground are not
tied together through it. That is a manufacturer claim, not something this
project has measured.

## Termination: switch OFF

The truck's HS-CAN is already terminated at both ends. Adding the adapter's
120 Ω in parallel would bring the bus to about 40 Ω.

- **120Ω Resistor Switch: UP = off.** (Manual: up turns the resistor off, down
  turns it on.)
- Bench check, adapter unplugged from everything: with the switch up, the
  meter across the CAN H and CAN L terminals must **not** read about 120 Ω.
  With it down it should. Record both readings.
- Truck check, **ignition off**: across DLC pins 6 and 14, expect about
  **60 Ω** (two 120 Ω terminators in parallel). Then with the adapter
  connected (switch up), it must still read about 60 Ω. About 40 Ω means the
  adapter's terminator is on: stop and fix it.

## Boot switch: UP

Up is working mode. Down is DFU (firmware update), where it isn't a CAN
adapter at all.

## Sign-off

| Check | Reading / result | By | Date |
|---|---|---|---|
| Pinout of the breakout matches the table (continuity: plug pin → wire) | Confirmed: 6 → CAN H wire, 14 → CAN L, 5 → GND | Owner | 2026-11-05 |
| Adapter terminator, switch up (expect not 120 Ω) | Confirmed (not ≈ 120 Ω; value not recorded) | Owner | 2026-11-05 |
| Adapter terminator, switch down (expect ≈ 120 Ω) | Confirmed ≈ 120 Ω (value not recorded). Switch left **up** | Owner | 2026-11-05 |
| DLC 6–14, ignition off, adapter disconnected (expect ≈ 60 Ω) | ≈ 62 Ω | Owner | 2026-11-06 |
| DLC 6–14, ignition off, adapter connected, switch up (expect ≈ 60 Ω) | | | |
| 5V terminal unconnected | | | |
