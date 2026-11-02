# Open hardware questions

Each question blocks something specific. Close it with evidence (a datasheet,
a vendor answer, a measurement or a photo), recorded in
[bench-log.md](bench-log.md) or the
[compatibility matrix](compatibility-matrix.md).

| # | Question | Blocks | How to answer | Owner |
|---|---|---|---|---|
| H1 | Can the CarPiHAT PRO 5's 120 Ω CAN terminator be disabled (jumper, solder bridge) or removed? | **Any connection to the truck's DLC** | Ask TJD. On arrival, measure CANH–CANL with the HAT unpowered: about 120 Ω means it's fitted | owner |
| H2 | What are the HAT's input voltage range, load-dump/TVS rating and reverse-polarity protection? | Permanent installation | Ask TJD. Until answered, plan an external fuse, TVS and reverse-polarity protection | owner |
| H3 | Does the DSI ribbon (22→15) clear the HAT on a Pi 5, and on which port? | Display mounting | Test fit, then photo | bench |
| H4 | Can an NVMe base or SSD be stacked with the HAT, or should storage be a USB SSD? | Storage design (Phase 5) | Test fit; check PCIe FFC routing | bench |
| H5 | What state does OUT_0/OUT_1 take on reset, panic and watchdog reboot? | Amplifier safety | Scope or meter during forced crashes | bench |
| H6 | What is the DAC's line-out level, and does it mute while booting? | Amplifier gain staging | 0 dBFS tone into the meter; scope at power-up | bench |
| H7 | Does the mcp251x driver honour `listen-only` on the Pi 5 / AGL kernel 6.18? | Stage A on the truck | `ip -details link show can0`; confirm no ACKs on a bench bus with a second node | bench |
| H8 | Which amplifiers are installed now (channels, inputs, remote turn-on)? | The audio plan | Inspect when the radio comes out | owner |
| H9 | Are reverse and turn-signal wires accessible, and at what voltage and behaviour (incandescent flasher vs. module)? | Camera triggers | Identify wires with the wiring diagram; meter them | owner |
| H10 | Which cameras and capture hardware (UVC first)? | Phase 6 cameras | Bench latency test | bench |
| H11 | Which GNSS receiver? It must work with gpsd | Phase 6 navigation | Pick a u-blox receiver; test with gpsd | owner |
| H12 | Physical addressing on this truck: does `ATSH 7E0`/`7E1` reach only one module? | Throughput plan; ISO-TP IDs | [TRUCK_SESSION Part 1](../diagnostics/TRUCK_SESSION.md), in the MX+ trial (3.5.4) | truck |
| H13 | Which Ford DIDs (EOT, FICM, ICP, IPR, MAP, EBP, gear, battery, fuel level) are valid, and who owns each? | Gauges beyond RPM and trans temp | [TRUCK_SESSION Part 3](../diagnostics/TRUCK_SESSION.md), in the MX+ trial (3.5.4) | truck |
| H14 | What is broadcast on HS-CAN without any request? | Stage B decoders | Stage A listen-only census | truck |
| H15 | Is the MX+ Bluetooth link reliable alongside A2DP on the Pi 5's one radio? | Using the OBDLink transport in the car | Bench test both together; fall back to a USB BT dongle or the ESP32 bridge | bench |
| H16 | Low-battery protection: where does the voltage measurement come from? | Low-voltage shutdown | Choose an ESP32 ADC or I2C ADC with a divider | design |
| H17 | Does Flutter 3.38.3 build a Linux desktop app on the Pi 5 (arm64 host)? | MX+ trial UI (3.14) | **Answered 2026-11-01: yes.** It builds on the Pi and runs under `cage` ([bench-log](bench-log.md)) | bench |
| H18 | Does the Pi 5 run stably from the truck-trial USB-C supply (undervoltage warnings, throttling)? | MX+ trial (3.5.3) | `vcgencmd get_throttled` before and after a drive | truck |
| H19 | Does a gateway-side recovery (soft reset, then `ATZ`, then reconnect) restore a frozen PID without unplugging the MX+? | The core reliability claim | Phase 3.5.6 drive logs | truck |
