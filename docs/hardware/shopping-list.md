# Shopping list

Owned: the Pi 5, the original 7" display, the OBDLink MX+, the ESP32
(2026-11-01) and, from 2026-11-03, a USB CAN adapter (Stage 1 below). Buy in
the order below. Each stage answers questions before money goes on the next.

## Stage 0 — MX+ truck trial (Phase 3.5): nothing to buy

The trial uses what's already owned ([ADR-0011](../architecture/adr/0011-mx-plus-trial-first.md)).
At most:

| Item | Why | Notes |
|---|---|---|
| USB-C PD supply for the Pi in the truck | Temporary power for the trial | Prefer 5 V / 5 A (for example the official 27 W supply, through a 12 V inverter or a USB-C PD car adapter that does 5 A). A 3 A supply works with reduced USB current. **Not** the permanent install |
| microSD card | Raspberry Pi OS | Probably on hand |
| Raspberry Pi 5 RTC battery (official, rechargeable Li-Mn coin cell, JST-SH plug) | Keeps the Pi's onboard RTC running while the power is cut, so logs have the right time after a cold start | Plugs into J5 (BAT). **Not** a CR2032 or other primary cell. Turn on charging: see [Clock](../setup/raspberry-pi.md#clock) |

**Purchase decision after the trial:** _not made yet_ for the CarPiHAT and
the rest of Stage 1. Record it here, with a link to
`docs/diagnostics/mx-plus-trial.md`. The USB CAN adapter was bought ahead of
it, on 2026-11-03 ([ADR-0012](../architecture/adr/0012-direct-can-usb-adapter.md)).

## Stage 1 — CAN bench bring-up (Phases 4–5), decided by the trial

| Item | Why | Notes / alternatives |
|---|---|---|
| CarPiHAT PRO 5 | Power latch, opto inputs, 12 V outputs, CAN, DAC, RTC | **First ask TJD about the CAN terminator and the input protection** ([H1, H2](open-questions.md)) |
| Display FFC, **22-way to 15-way, display type** | Pi 5 ↔ original display | A camera-type cable leaves the screen dark |
| USB candleLight/CANable CAN adapter (`gs_usb`) | Direct CAN from the Pi; listen-only capture; fallback if the HAT's terminator can't be removed | **Bought 2026-11-03:** Jhoinrch RH-02 Pro (CANable 2.0, isolated, switchable 120 Ω). [Matrix](compatibility-matrix.md#usb-can-adapter-jhoinrch-rh-02-pro) |
| OBD-II Y-splitter plus a DLC breakout (male J1962 to wires/terminals) | **Needed to connect the RH-02 Pro**: its CAN side is a screw terminal block. The splitter lets the MX+ and the Pi share the DLC for the dropout experiment; the breakout gives CANH/CANL access for a meter | [Wiring](../wiring/dlc-can-adapter.md) |
| Bench 12 V supply (current-limited) | Powers the HAT without the truck | |
| microSD (for Raspberry Pi OS and the AGL prebuilt image) | Staged bring-up (ADR-0005) | |
| USB SSD | Production storage | Or NVMe, once [H4](open-questions.md) is answered |

## Stage 2 — installation (Phase 7)

| Item | Why |
|---|---|
| Inline fuse holders and fuses (constant and ignition feeds) | Protection near the source |
| Automotive TVS (SMBJ/SMCJ class) and reverse-polarity protection | Until the HAT's protection is confirmed |
| Wiring, ferrules, grommets, a remote-turn-on lead | Install |
| Rotary encoder (volume knob) | Into the ESP32, or into Pi GPIO through the HAT's breakout |
| USB GNSS receiver (u-blox, gpsd-compatible) | Navigation |

## Stage 3 — chosen after measurement (Phase 6)

| Item | Decided by |
|---|---|
| Cameras and capture hardware | UVC first; latency and driver checks ([camera policy](../architecture/camera-policy.md)) |
| Amplifier(s) | Only after the existing amplifiers are inspected ([H8](open-questions.md)) |
| USB Bluetooth dongle | Only if the MX+ and A2DP conflict on the onboard radio ([H15](open-questions.md)) |
| EGT thermocouple and amplifier (for example MAX31856) | Optional auxiliary sensor through the ESP32 |
