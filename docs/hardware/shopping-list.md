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

**Purchase decision:**

- The USB CAN adapter was bought on 2026-11-03, ahead of the trial report
  ([ADR-0012](../architecture/adr/0012-direct-can-usb-adapter.md)).
- **2026-11-04:** power comes from a **mini-box DCDC-USB**, and the
  **CarPiHAT PRO 5 is not bought**
  ([ADR-0013](../architecture/adr/0013-dcdc-usb-power-supply.md)). Its other
  jobs are listed below as separate parts.
- The rest of Stage 1 follows the trial report,
  `docs/diagnostics/mx-plus-trial.md`.

## Stage 1 — CAN bench bring-up (Phases 4–5), decided by the trial

| Item | Why | Notes / alternatives |
|---|---|---|
| mini-box DCDC-USB | Ignition-aware 6–34 V supply; VOUT about 5 V to the Pi; PSW pulse to J2 | **Chosen 2026-11-04, not bought yet.** Bench it before the truck: [H21, H23–H25](open-questions.md). [Matrix](compatibility-matrix.md#mini-box-dcdc-usb) |
| USB-C power lead (bare wires to a USB-C plug), heavy enough for 5 A | DCDC-USB VOUT into the Pi 5's USB-C input | Short, to keep the voltage drop low. Not into the GPIO header ([matrix](compatibility-matrix.md#raspberry-pi-5-power-button-and-5-v-input)) |
| 2-pin lead to the Pi 5's J2 pads | PSW → J2 | Needs a header or wires soldered to J2 |
| Opto-isolated input board, at least 4 channels, 12 V automotive inputs | Reverse now; turn signals later if CAN doesn't carry them | Output side powered from the Pi's 3.3 V ([H26](open-questions.md)) |
| Display FFC, **22-way to 15-way, display type** | Pi 5 ↔ original display | A camera-type cable leaves the screen dark |
| USB candleLight/CANable CAN adapter (`gs_usb`) | Direct CAN from the Pi; listen-only capture | **Bought 2026-11-03:** Jhoinrch RH-02 Pro (CANable 2.0, isolated, switchable 120 Ω). [Matrix](compatibility-matrix.md#usb-can-adapter-jhoinrch-rh-02-pro) |
| OBD-II Y-splitter plus a DLC breakout (male J1962 to wires/terminals) | **Needed to connect the RH-02 Pro**: its CAN side is a screw terminal block. The splitter lets the MX+ and the Pi share the DLC for the dropout experiment; the breakout gives CANH/CANL access for a meter | **Owned** (owner, 2026-11-03). Check its pinout by continuity before use: [wiring](../wiring/dlc-can-adapter.md) |
| Bench 12 V supply (current-limited) | Powers the DCDC-USB without the truck; a switch on its IGN lead stands in for the key | |
| microSD (for Raspberry Pi OS and the AGL prebuilt image) | Staged bring-up (ADR-0005) | |
| USB SSD | Production storage | Or NVMe, once [H4](open-questions.md) is answered |

## Stage 2 — installation (Phase 7)

| Item | Why |
|---|---|
| Inline fuse holders and fuses (constant and ignition feeds) | Protection near the source |
| Automotive TVS (SMBJ/SMCJ class) | On the reverse tap, ahead of the opto board, unless the board's input protection is documented |
| Wiring, ferrules, grommets, a remote-turn-on lead | Install |
| Rotary encoder (volume knob) | Into the ESP32, or into Pi GPIO |
| USB GNSS receiver (u-blox, gpsd-compatible) | Navigation |

## Stage 3 — chosen after measurement (Phase 6)

| Item | Decided by |
|---|---|
| Cameras and capture hardware | UVC first; latency and driver checks ([camera policy](../architecture/camera-policy.md)) |
| HiFiBerry DAC8x | **Chosen 2026-11-04** ([ADR-0014](../architecture/adr/0014-multichannel-dac8x.md)), not bought. Pi 5 only. Check header access first ([H27](open-questions.md)) |
| 3 × 3.5 mm TRS (stereo) → 2 × RCA male leads | Front, rear and sub from the DAC8x. Short ones if they meet longer RCA runs behind the dash; strain-relieve the jacks |
| New 4-channel amplifier (replaces the Pioneer's built-in amp) | Owner's choice against these criteria: RCA inputs with a 4-channel input mode; about 50–75 W RMS × 4 at 4 Ω; stable at 2 Ω, in case the factory speakers are about 3 Ω ([H29](open-questions.md)); a REM input; small enough for behind the dash or under the rear seat. Crossovers can be flat (the Pi does them) |
| Amplifier power kit for the new amp | Power wire, a fuse holder within about 18 in of the battery, ground lead, ring terminals. Gauge and fuse from the chosen amp's manual. Or a distribution block with one fuse per amp, if the R150-2's feed is big enough ([H28](open-questions.md)) |
| RCA ground-loop isolator | Only if the engine-running whine test fails ([wiring](../wiring/audio.md#alternator-whine-and-ground-loops)) |
| 12 V delay-on timer relay (adjustable delay, normally-open contact) and a small inline fuse | Switches both amps' REM from ACC, so they come on after the Pi has booted and go off at key-off ([wiring](../wiring/audio.md#remote-turn-on-acc-through-a-delay-on-timer)). Needs an adjustable delay above the Pi's measured boot time, and a contact rated for both REM inputs. Replaces the GPIO-driven remote switch ([ADR-0014](../architecture/adr/0014-multichannel-dac8x.md)) |
| USB Bluetooth dongle | Only if the MX+ and A2DP conflict on the onboard radio ([H15](open-questions.md)) |
| EGT thermocouple and amplifier (for example MAX31856) | Optional auxiliary sensor through the ESP32 |
