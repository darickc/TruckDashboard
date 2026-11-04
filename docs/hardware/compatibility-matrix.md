# Hardware compatibility matrix

Researched **2026-11-01**. Nothing here has been tested on hardware yet. The
only head-unit purchase so far is the USB CAN adapter (2026-11-03, below). The
mini-box DCDC-USB was chosen for power on 2026-11-04 and has not been bought yet
([ADR-0013](../architecture/adr/0013-dcdc-usb-power-supply.md)).

Status key:

- **V**: verified in an official or manufacturer source
- **F**: forum or secondary source
- **U**: unverified
- **C**: sources conflict
- **T**: tested on this truck or bench, with a log entry

Update a row whenever a source or a test changes it, and keep the citation.

## Summary verdict

| Combination | Verdict |
|---|---|
| Pi 5 + AGL Vimba 22.0.0 | **Supported.** Official prebuilt images (V) |
| Pi 5 + original 7" DSI display under AGL | **Expected to work with configuration.** The driver and overlay ship, but the display isn't turned on by default (V). Not tested |
| Pi 5 + mini-box DCDC-USB (automotive mode, PSW → J2) | **Plausible.** It can be set to 5 V, and J2 takes a normally-open momentary closure (V). Whether PSW is such a closure, the pulse timing, and the current at 5 V are not documented (U) |
| Pi 5 + CarPiHAT PRO 5 | **Not used** ([ADR-0013](../architecture/adr/0013-dcdc-usb-power-supply.md)). Kept below as a research record |

## AGL / OS

| Item | Finding | Status | Source |
|---|---|---|---|
| Latest stable | Vibrant Vimba 22.0.0, Yocto 6.0 "Wrynose". The release directory is dated 2026-09-18 | V | [announcement](https://www.automotivelinux.org/blog/automotive-grade-linux-announces-vibrant-vimba-v22-0-0/), [downloads](https://download.automotivelinux.org/AGL/release/vimba/) |
| Previous / LTS | Ultimate Unagi 21.0.x (21.0.4). Reportedly LTS on Scarthgap, to 2028 | V / C | [unagi](https://download.automotivelinux.org/AGL/release/unagi/), [AMM Tokyo slides](https://hosted-files.sched.co/aglammjapan2026/23/AGL%20Update%20AMM%20Tokyo%20Miner.pdf) |
| Pi 5 machine and images | `raspberrypi5`. Flutter and Qt demo `.wic.zst` images. Kernel 6.18.33. U-Boot 2026.01 | V | [images](https://download.automotivelinux.org/AGL/release/vimba/22.0.0/raspberrypi5/deploy/images/raspberrypi5/), [local.conf](https://download.automotivelinux.org/AGL/release/vimba/22.0.0/raspberrypi5/local.conf) |
| Flutter | 3.38.3, flutter-auto 2.0, applaunchd app template | V | [manifest](https://download.automotivelinux.org/AGL/release/vimba/22.0.0/raspberrypi5/deploy/images/raspberrypi5/agl-ivi-demo-flutter-raspberrypi5.manifest) |
| Compositor | agl-compositor 0.0.24 (libweston, agl-shell) | V | [docs](https://docs.automotivelinux.org/en/unagi/06_Component_Documentation/01_Graphics_Service/01_agl_compositor/) |
| Audio and Bluetooth | PipeWire 1.6.6, WirePlumber 0.5.14, BlueZ 5.86, bluez5 SPA, ofono 2.19 | V | manifest |
| A2DP sink working | Not documented | U | [AGL audio docs](https://docs.automotivelinux.org/en/unagi/06_Component_Documentation/02_Sound_Service/01_pipewire_wireplumber/) |
| CAN | can-utils 2025.01. Modules: can-raw, can-isotp, can-j1939, mcp251x, mcp251xfd, gs-usb, peak-usb. kuksa-databroker 0.7.1 | V | manifest |
| Video | GStreamer 1.28.2 with the V4L2 plugin, libcamera 0.6.0 | V | manifest |
| meta-raspberrypi switches | `ENABLE_SPI_BUS`, `ENABLE_CAN`, `ENABLE_DUAL_CAN`, `RPI_EXTRA_CONFIG` | V | [extra-build-config](https://raw.githubusercontent.com/agherzan/meta-raspberrypi/master/docs/extra-build-config.md) |
| Build host | Native Linux. At least 300 GB for Flutter images. Yocto 6.0: 32 GB RAM example. No macOS. aarch64 not documented | V / U | [AGL](https://docs.automotivelinux.org/en/master/01_Getting_Started/02_Building_AGL_Image/02_Preparing_Your_Build_Host/), [Yocto](https://docs.yoctoproject.org/6.0/ref-manual/system-requirements.html) |
| Pi 5 quickstart docs | The ready-made-images guide still covers only the Pi 4 | V | [docs](https://docs.automotivelinux.org/en/master/01_Getting_Started/01_Quickstart/01_Using_Ready_Made_Images/) |

## Original Raspberry Pi 7" touchscreen (800×480, DSI) on the Pi 5

| Item | Finding | Status | Source |
|---|---|---|---|
| Cable | A **22-way to 15-way** FFC, the display type. A camera-type cable ties the I2C clock low and leaves the screen dark | V | [RPi display docs](https://www.raspberrypi.com/documentation/accessories/display.html), [linux#5813](https://github.com/raspberrypi/linux/issues/5813) |
| Overlay | `dtoverlay=vc4-kms-dsi-7inch`. Defaults to DSI1; add `,dsi0` for port 0. Includes the edt-ft5406 touch driver. Parameters: `sizex`, `sizey`, `invx`, `invy`, `swapxy`, `disable_touch`. Needs `vc4-kms-v3d` | V | [overlays README](https://raw.githubusercontent.com/raspberrypi/linux/rpi-6.12.y/arch/arm/boot/dts/overlays/README) |
| Pi 5 port mapping | DSI0/DSI1 correspond to the CAM/DISP 0 and CAM/DISP 1 connectors | inferred | — |
| Backlight | Regulator-based (`raspberrypi,7inch-touchscreen-panel-regulator`, I2C 0x45). The Pi 5 uses i2c-4/i2c-6 for the display ports | V | [overlay dts](https://raw.githubusercontent.com/raspberrypi/linux/rpi-6.12.y/arch/arm/boot/dts/overlays/vc4-kms-dsi-7inch-overlay.dts), linux#5813 |
| In the AGL image | The `vc4-kms-dsi-7inch.dtbo` overlay and the edt-ft5x06, tc358762, rpi-panel-attiny-regulator and rpi-backlight modules | V | manifest |
| Enabled in AGL `config.txt` | **No.** Only `vc4-kms-v3d-pi5,cma-256`. No `display_auto_detect`. `rpi-ft5406` is commented out | V | [AGL config.txt](https://download.automotivelinux.org/AGL/release/vimba/22.0.0/raspberrypi5/deploy/images/raspberrypi5/bootfiles/config.txt) |
| On Raspberry Pi OS Lite (trixie, kernel 6.18) | **Works with no `config.txt` change** on DSI1: picture, backlight, touch (edt_ft5x06 at I2C 10-0038), and the app fullscreen under `cage` | T | [bench-log](bench-log.md), 2026-11-02 |
| Legacy `rpi-ft5406` needed | It shouldn't be with the KMS overlay | U | — |

## Raspberry Pi 5 onboard RTC

The head unit keeps time while parked with this RTC and a battery on J5. No
separate RTC is needed. Researched 2026-11-03. Source for the `V` rows:
[RPi docs, Real Time Clock](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#real-time-clock-rtc).

| Item | Finding | Status | Source |
|---|---|---|---|
| RTC on the board | Yes. It runs from a backup battery on the **J5 (BAT)** connector. It works without a battery while the board has power | V | RPi docs |
| Battery | Official cell: rechargeable lithium-manganese coin cell, pre-fitted 2-pin JST-SH plug | V | RPi docs |
| Wrong cells | Not a primary (non-rechargeable) lithium cell such as a CR2032: the backup draw is higher than a dedicated RTC chip's, so it would not last. Not Li-ion | V | RPi docs |
| Charging | Off by default. Turn it on with `dtparam=rtc_bbat_vchg=3000000` in `config.txt` (sysfs range 1300000–4400000, presumably µV) | V | RPi docs |
| Retention | Single-digit µA when powered down, so months | V | RPi docs |
| Wake alarm | `POWER_OFF_ON_HALT=1` and `WAKE_ON_GPIO=0` in the EEPROM config, then write `/sys/class/rtc/rtc0/wakealarm`. About 3 mA while waiting | V | RPi docs |
| Without a battery | Time is presumably lost whenever the power supply cuts 5 V. The docs imply this but don't say it | inferred | — |
| In the AGL image | Whether the AGL kernel enables the Pi 5 RTC driver and honours `rtc_bbat_vchg` is not checked. Verify on the image: `ls /sys/class/rtc/`, `cat /sys/class/rtc/rtc0/charging_voltage`, `hwclock -r` | U | — |
| Holds time across a parked night | Not tested ([H20](open-questions.md)) | U | — |

## mini-box DCDC-USB

Chosen for power on 2026-11-04
([ADR-0013](../architecture/adr/0013-dcdc-usb-power-supply.md)). Sources:

- the [product page](https://www.mini-box.com/DCDC-USB)
- the [Quick Installation Guide](https://resources.mini-box.com/online/PWR-DCDC-USB/PWR-DCDC-USB-manual.pdf), v1.0c ("QIG")
- the [Advanced USB configuration manual](https://resources.mini-box.com/online/PWR-DCDC-USB/PWR-DCDC-USB-Advanced-USB-configuration-manual.pdf) ("USB manual")

All read 2026-11-04.

| Item | Finding | Status | Source |
|---|---|---|---|
| Input | 6–34 V. Electronic shutdown at 34 V; clamping at 35–37 V | V | QIG p. 5 |
| Output | 12 V by default. Jumpers give 5, 6, 9, 12, 13.5, 16, 19 or 24 V; USB gives 5–24 V in fine steps. A jumper change needs a power cycle | V | QIG p. 3, product page |
| Output current | Up to 10 A, 100 W, limited by the 10 A input fuse. The current chart covers **only the 12 V output** (8 A from 10 V in). **The limit at 5 V is not stated** | V / U (5 V) | QIG p. 5 |
| Regulation | ±2.5 % | V | QIG p. 5 |
| Cooling | Forced air above 40 W, or above 65 °C | V | QIG p. 5 |
| Connectors | Mini-Fit Jr 4-pin input (VIN, GND, IGN; harness red, black, white) and output (VOUT, GND; harness yellow, black) | V | QIG p. 2, 5 |
| Modes | DUMB, AUTOMOTIVE, SCRIPT, UPS, set by jumpers | V | QIG p. 3–4 |
| Automotive mode | Reads the ignition wire and sends ON/OFF pulses to the motherboard | V | QIG p. 3 |
| OFFDELAY | Time from ignition off to the ON/OFF pulse | V | QIG p. 4 |
| HARDOFF | Time from the pulse to output off. Can be "Never" | V | QIG p. 4 |
| Timer presets (jumpers) | 0/0, 5 s/60 s, 5 s/never, 1 min/1 min, 15 min/1 min, 15 min/never, 30 min/1 min, 2 h/never | V | QIG p. 4 |
| Timers over USB | Each preset's off-delay and hard-off values can be changed (max 17:59:59 or Never). Takes effect at the next power cycle | V | USB manual p. 4–6 |
| Deep-discharge cutoff | Below 11.2 V **during HARDOFF**, power is cut | V | QIG p. 4–5 |
| Shutdown sensing | None documented. The sequence is purely timer-based | V (by omission) | QIG p. 4 |
| Standby draw | "Well under 1 mA" in automotive mode | V (claim) / U (not measured) | product page |
| PSW header | 2 pins. "Soft ON/OFF control for motherboard. Connect this to motherboard ON/OFF pins" | V | QIG p. 2 |
| PSW electrical form | Not documented: open-collector, relay contact or driven voltage. Polarity unknown | U | — ([H21](open-questions.md)) |
| PSW pulse length and the ON pulse's timing | Not documented. The SCRIPT-mode example uses a 500 ms PSW pulse | U | USB manual p. 7 (example only) |
| Ignition returns during HARDOFF | Not documented | U | — ([H23](open-questions.md)) |
| Vaux | "Unregulated switched input" for peripherals in automotive modes. When it switches is not documented | V / U | QIG p. 2 |
| USB telemetry | The Windows tool shows input, ignition and output voltages, the PSW and output state, and the off-delay and hard-off timers | V | USB manual p. 2–3 |
| USB telemetry on Linux | mini-box links a Linux tool, [mini-box/dcdc-usb](https://github.com/mini-box/dcdc-usb). Not checked: whether it reads these values in automotive mode on the Pi | U | — ([H24](open-questions.md)) |

## Raspberry Pi 5 power button and 5 V input

Source: [RPi docs](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html),
sections "Power button", "Power supply", "Universal Serial Bus (USB)" and
"Raspberry Pi bootloader configuration". Read 2026-11-04.

| Item | Finding | Status | Source |
|---|---|---|---|
| J2 | "Located between the RTC battery connector and the board edge." Takes a **normally-open momentary switch bridging the two pads**. Briefly closing it does the same as the onboard power button | V | Power button |
| J2 pad polarity, debounce | Not documented | U | — measure ([H21](open-questions.md)) |
| Press while running | Raspberry Pi OS Lite: one press starts a shutdown. With the desktop, a menu appears (press again, or press twice quickly). On AGL, logind's `HandlePowerKey` decides; power-manager sets it to `ignore` and handles the key itself | V (RPi OS) / U (AGL) | Power button |
| Press while halted but powered | "Restarts the board" | V | Power button |
| Press and hold | Forces a hard shutdown. **No duration is given** | V / U (duration) | Power button |
| Boots when power is applied | Stated for the first power-up. The docs don't say so for later power-ups. `WAIT_FOR_POWER_BUTTON` (default 0) with `POWER_OFF_ON_HALT=1` would instead wait for the button | V / U | Power button, bootloader config |
| Halted draw | About 1–1.4 W by default. About 0.01 W with `POWER_OFF_ON_HALT=1` | V | Power supply |
| USB current on a non-5 A supply | Downstream USB is limited to 600 mA (1.6 A on a 5 A supply). The budget is shared with the fan header | V | Power supply, USB |
| Telling the Pi it has a 5 A supply | `PSU_MAX_CURRENT=5000` in the EEPROM skips USB-PD negotiation and assumes that rating. The docs don't spell out its effect on the 600 mA limit; check with `vcgencmd get_config usb_max_current_enable` | V / U (effect) | Bootloader config, USB |
| `usb_max_current_enable=1` | Documented for **USB boot** on a 3 A supply. Not documented as a way to raise the peripheral current | V | Boot sequence |
| 5 V into the GPIO header | Bypasses the PMIC: USB current isn't visible. The docs don't present it as a supported way to power the board. **Use the USB-C input** | V / U | Power supplies and Raspberry Pi OS |

## CarPiHAT PRO 5 (TJD; sold by The Pi Hut, TPH-106064, and Core Electronics)

> **Not used** ([ADR-0013](../architecture/adr/0013-dcdc-usb-power-supply.md),
> 2026-11-04). This section is kept as a research record.

Documentation is the [CarPiHat wiki](https://github.com/gecko242/CarPiHat/wiki).
**It is not specific to the PRO 5.** The Pi Hut says the pinout hasn't changed
from the previous model; that came from a search snippet only.

| Item | Finding | Status | Source |
|---|---|---|---|
| Power stage | 12 V→5 V buck, up to 5 A, fused and filtered. Under 1 mA when off. Has a 5 V output for the display | V | [Core Electronics](https://core-electronics.com.au/carpihat-pro-5-car-interface-dac.html) |
| Input range, load-dump/TVS, reverse polarity | Not published | U | — ask TJD |
| Ignition and latch | IGN on BCM12, latch on BCM25. `dtoverlay=gpio-poweroff,gpiopin=25,active_low`. The example script shuts down after more than 10 s with ignition low. Needs `rpi-lgpio` on the Pi 5 | V | wiki Quick Start |
| CAN controller | MCP2515 with an MCP2558(FD?) transceiver. **8 MHz** crystal. SPI0 CE0 (BCM8). **INT BCM23** | V (wiki, not PRO 5-specific) | wiki |
| CAN termination | **120 Ω fitted across CANH/CANL. No jumper documented** | V (fitted) / U (switchable) | wiki |
| CAN isolation | None documented | inferred | — |
| CAN overlay | `dtparam=spi=on`, `dtoverlay=mcp2515-can0,oscillator=8000000,interrupt=23` | V | wiki, overlays README |
| Pi 5 MCP2515 gotchas | Check the INT pin is an input with a pull (`pinctrl`). The interrupt is level-triggered | F (GitHub) | [linux#6106](https://github.com/raspberrypi/linux/issues/6106), [commit](https://github.com/raspberrypi/linux/commit/62e7aa59a616c370a3a614d735805e969caf771a) |
| DAC | Burr-Brown, 192 kHz/24-bit, 3.5 mm jack. `dtoverlay=hifiberry-dacplus-std` plus `vc4-kms-v3d,noaudio`. Exact chip not named (PCM512x inferred). Line level not documented | V / C (config location) | wiki, Core Electronics |
| 12 V inputs (opto, 12–18 V) | IGN BCM12, REV BCM7, ILLUM BCM13, IN_1 BCM14, IN_2 BCM17 | V | wiki |
| 12 V outputs | OUT_0 BCM27, OUT_1 BCM22. High-side, 1 A each | V | wiki |
| RTC | DS1307, `dtoverlay=i2c-rtc,ds1307`. No battery; uses the permanent 12 V feed | V | wiki |
| RTC choice | Not needed: the plan uses the [Pi 5 onboard RTC](#raspberry-pi-5-onboard-rtc). If this overlay is also enabled there are two RTCs; pick one as `rtc0` for `hwclock`/systemd | decision | — |
| Breakouts | I2C, 1-Wire. Fan and shroud included. No room for the Active Cooler | V | wiki |
| Pin conflicts | SPI CE1 = BCM7 = REV input (fix: `dtoverlay=spi0-cs,cs1_pin=24`). IN_1 (BCM14) = UART TX, so don't enable a GPIO-header serial console; the Pi 5 has a dedicated debug UART connector | V / inferred | wiki |
| Camera input | None | V (absent) | — |
| DSI ribbon routing with the HAT fitted | Not documented | U | — |

### Published `config.txt` lines (Raspberry Pi OS; adapt for AGL with `RPI_EXTRA_CONFIG`)

```
usb_max_current_enable=1
dtparam=spi=on
dtoverlay=mcp2515-can0,oscillator=8000000,interrupt=23
dtoverlay=spi0-cs,cs1_pin=24
dtoverlay=i2c-rtc,ds1307
dtoverlay=hifiberry-dacplus-std
dtoverlay=vc4-kms-v3d,noaudio
dtoverlay=gpio-poweroff,gpiopin=25,active_low
```

Not yet reconciled with AGL: AGL uses `vc4-kms-v3d-pi5,cma-256`. Whether `noaudio`
applies to the Pi 5 variant must be checked when the HAT is fitted.

## 2007 F-250 6.0L diagnostic network

| Item | Finding | Status | Source |
|---|---|---|---|
| Diagnostic protocol | ISO 15765-4, CAN 11-bit, 500 kbaud (ELM protocol 6) | **T** | [VERIFICATION_LOG](../diagnostics/VERIFICATION_LOG.md) 2026-08-09 |
| Responders to `7DF` | `7E8` (PCM) and `7E9` (TCM) | **T** | VERIFICATION_LOG |
| TCM owns `22 1674` | The PCM answers `7F 22 31` | **T** | VERIFICATION_LOG |
| Physical request IDs `7E0`/`7E1` | Expected per ISO 15765-4. Untested; the previous test was confounded | U | [TRUCK_SESSION](../diagnostics/TRUCK_SESSION.md) Part 1 |
| HS-CAN module list | PCM, TCM, OBDII, ABS, TBC, IC | F | [FORScan forum](https://forum.forscan.org/viewtopic.php?t=2794) |
| K-line (ISO 9141, pin 7) | RCM, GEM. **Not reachable with the MCP2515** | F | same |
| MS-CAN (pins 3/11) | The 2008 manual lists it. 2006–07 scans show no MS-CAN modules | C | [Ford 418-00 copy](https://www.scribd.com/document/492204330), forum |
| J1850 PWM | Not present in 2006/07 scans. 2004 trucks used it | F / U | forum |
| FICM | Not a separate module. Its voltages appear as PCM PIDs | F | forum |
| Turn signal / reverse on HS-CAN | Unknown. The GEM is on K-line, so turn signals are probably not on HS-CAN | U | — check with a listen-only [event capture](../setup/can.md#event-captures-turn-signals-and-reverse) |

## USB CAN adapter: Jhoinrch RH-02 Pro

Bought 2026-11-03 (Amazon B0FSVNBKQ4). Source: the manufacturer's manual
(Manuals+ copy, "Jhoinrch RH-02 Pro Isolation USB to CAN FD Adapter User
Manual", model RH-02 Pro-1), unless noted.
[ADR-0012](../architecture/adr/0012-direct-can-usb-adapter.md).

| Item | Finding | Status | Source |
|---|---|---|---|
| Design | CANable 2.0, STM32G431CBT6 | V (manual) | manual |
| Isolation | 1.5 kV power, 5.7 kV RMS signal. TVS/ESD/GDT protection | V (manual) / U (not measured) | manual |
| Terminals | CAN H, GND, CAN L, 5V (3.81 mm block). 5V is an output | V (manual) | manual |
| Termination | 120 Ω, switchable: **up = off**, down = on | V (manual) / U (not measured) | manual; check on the bench ([wiring](../wiring/dlc-can-adapter.md)) |
| Boot switch | Up = working, down = DFU | V (manual) | manual |
| Factory firmware | The manual says **slcan** in its setup section and **candleLight** in its firmware section | **C** | manual; `tools/pi/can.sh status` settles it |
| candleLight on CANable 2.0 | Available; enumerates as native SocketCAN (`gs_usb`); no CAN FD | F | [canable.io](https://canable.io/index.html), [Makerbase CANable 2.0 manual](https://download.kamami.pl/p1192913-Makerbase%20CANable%20V2.0%20Use%20Manual.pdf) |
| Listen-only | Listed as a mode by the manual. Under `gs_usb`, set with `ip link … listen-only on` | V (manual, kernel docs) / U (this board) | `can.sh listen` refuses if the driver doesn't accept it |
| Listen-only over `slcand` | Unknown | U | — |
| Pi 5 kernel (Raspberry Pi OS, 6.18.50) | Ships `gs_usb`, `slcan`, `vcan`, `can-isotp` modules | T | `ls /lib/modules/…` on the Pi, 2026-11-03 |
| macOS (Apple silicon) | "Not temporarily supported" per the manual | V (manual) | manual — irrelevant here, it runs on the Pi |

## Linux CAN facts

| Item | Finding | Status | Source |
|---|---|---|---|
| Listen-only | `ip link set can0 type can bitrate 500000 listen-only on` | V | [kernel CAN docs](https://docs.kernel.org/networking/can.html) |
| Listen-only on the mcp251x driver | Driver support to be confirmed on the bench | U | — |
| ISO-TP | Mainline since 5.10. `socket(PF_CAN, SOCK_DGRAM, CAN_ISOTP)`. `isotp*` tools in can-utils | V | [iso15765-2 docs](https://docs.kernel.org/networking/iso15765-2.html) |
| USB CAN (candleLight) | Mainline `gs_usb` | V | [candleLight_fw](https://github.com/candle-usb/candleLight_fw) |

## Alternatives

| If… | Then |
|---|---|
| PSW is a driven voltage, not a contact ([H21](open-questions.md)) | Put a small reed relay or optocoupler between PSW and J2 |
| The DCDC-USB can't hold 5 V at the Pi's load ([H25](open-questions.md)) | Run it at 12 V into a dedicated 5 V / 5 A converter, and keep it for the ignition logic and PSW |
| The turn signals aren't on HS-CAN | Two more channels on the reverse input's opto board |
| A CAN HAT is wanted instead of USB | Waveshare 2-CH CAN HAT: isolated, jumper termination, 16 MHz, INT GPIO23/25 ([wiki](https://www.waveshare.com/wiki/2-CH_CAN_HAT)). Check its pins against the DAC HAT and the opto inputs |
