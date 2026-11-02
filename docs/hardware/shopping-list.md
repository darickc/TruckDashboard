# Shopping list

Nothing beyond the Pi 5, the original 7" display, the OBDLink MX+ and the
ESP32 is owned yet (2026-11-01). Buy in the order below. Each stage answers
questions before money goes on the next.

## Stage 1 — bench bring-up (Phases 4–5)

| Item | Why | Notes / alternatives |
|---|---|---|
| CarPiHAT PRO 5 | Power latch, opto inputs, 12 V outputs, CAN, DAC, RTC | **First ask TJD about the CAN terminator and the input protection** ([H1, H2](open-questions.md)) |
| Display FFC, **22-way to 15-way, display type** | Pi 5 ↔ original display | A camera-type cable leaves the screen dark |
| USB candleLight/CANable CAN adapter (`gs_usb`) | A second bus node on the bench; listen-only capture; fallback if the HAT's terminator can't be removed | Choose one with switchable termination |
| OBD-II Y-splitter plus a DLC breakout | Lets the MX+ and the Pi share the DLC for the dropout experiment; easy CANH/CANL access for a meter | |
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
