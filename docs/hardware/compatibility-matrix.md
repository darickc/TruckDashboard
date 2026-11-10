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
| Pi 5 + AGL Vimba 22.0.1 (pinned) | **Supported.** Official prebuilt images (V). Its demo CAN defaults must be overridden before the adapter meets the truck ([ADR-0015](../architecture/adr/0015-agl-can-defaults.md)) |
| Pi 5 + original 7" DSI display under AGL | **Expected to work with configuration.** The driver and overlay ship, but the display isn't turned on by default (V). Not tested |
| Pi 5 + mini-box DCDC-USB (automotive mode, PSW → J2) | **Plausible.** It can be set to 5 V, and J2 takes a normally-open momentary closure (V). Whether PSW is such a closure, the pulse timing, and the current at 5 V are not documented (U) |
| Pi 5 + HiFiBerry DAC8x | **Supported on Raspberry Pi OS** (overlay in the Raspberry Pi kernel tree; V). The overlay and codec modules are in the AGL 22.0.1 image (V); not tested there; mute at boot undocumented (U) |
| Pi 5 + CarPiHAT PRO 5 | **Not used** ([ADR-0013](../architecture/adr/0013-dcdc-usb-power-supply.md)). Kept below as a research record |

## AGL / OS

| Item | Finding | Status | Source |
|---|---|---|---|
| Latest stable | Vibrant Vimba **22.0.1** (directory 2026-11-02, images 2026-10-28), after 22.0.0 (2026-09-18). Yocto 6.0 "Wrynose". Pinned in `agl/configurations/vimba.env` (2026-11-06) | V | [announcement](https://www.automotivelinux.org/blog/automotive-grade-linux-announces-vibrant-vimba-v22-0-0/), [downloads](https://download.automotivelinux.org/AGL/release/vimba/) |
| Previous / LTS | Ultimate Unagi 21.0.x (21.0.4). Reportedly LTS on Scarthgap, to 2028 | V / C | [unagi](https://download.automotivelinux.org/AGL/release/unagi/), [AMM Tokyo slides](https://hosted-files.sched.co/aglammjapan2026/23/AGL%20Update%20AMM%20Tokyo%20Miner.pdf) |
| Pi 5 machine and images | `raspberrypi5`. Flutter and Qt demo `.wic.zst` images. Kernel 6.18.33. U-Boot 2026.01 | V | [images](https://download.automotivelinux.org/AGL/release/vimba/22.0.0/raspberrypi5/deploy/images/raspberrypi5/), [local.conf](https://download.automotivelinux.org/AGL/release/vimba/22.0.0/raspberrypi5/local.conf) |
| Flutter | 3.38.3, flutter-auto 2.0, applaunchd app template | V | [manifest](https://download.automotivelinux.org/AGL/release/vimba/22.0.0/raspberrypi5/deploy/images/raspberrypi5/agl-ivi-demo-flutter-raspberrypi5.manifest) |
| Compositor | agl-compositor 0.0.24 (libweston, agl-shell) | V | [docs](https://docs.automotivelinux.org/en/unagi/06_Component_Documentation/01_Graphics_Service/01_agl_compositor/) |
| One homescreen client per compositor run | agl-compositor 0.0.24 aborts (SIGABRT) when a second `homescreen` background client connects; a client leaving is fine. The image's unit has no `Restart=`, so the panel drops to the text console. Which assertion fires: unknown (no debug symbols) | T | [bench-log](bench-log.md) 2026-11-06 |
| Audio and Bluetooth | PipeWire 1.6.6, WirePlumber 0.5.14, BlueZ 5.86, bluez5 SPA, ofono 2.19 | V | manifest |
| A2DP sink working | Not documented | U | [AGL audio docs](https://docs.automotivelinux.org/en/unagi/06_Component_Documentation/02_Sound_Service/01_pipewire_wireplumber/) |
| CAN | can-utils 2025.01. Modules: can-raw, can-isotp, can-j1939, mcp251x, mcp251xfd, gs-usb, peak-usb, slcan. kuksa-databroker 0.7.1. Confirmed in the 22.0.1 manifest | V | manifest |
| Video | GStreamer 1.28.2 with the V4L2 plugin, libcamera 0.6.0 (the demo image) | V | manifest |
| Video on our `agl-f250` image | From `6114c52`, both images carry GStreamer 1.28.5 `video4linux2` (`v4l2src`), `jpeg` (`jpegdec`), `videoconvertscale`, `app` (`appsink`) and the `bad` `waylandsink`; the dev image adds `v4l-utils` 1.32.0 (`v4l2-ctl`), `videotestsrc` and `debugutilsbad` (`fpsdisplaysink`). Image `288d091` had only the GStreamer core. A UVC webcam streams 640×480 at ~30 fps through `uvcvideo` (read with raw V4L2 ioctls on `288d091`). On `6114c52`, `v4l2src ! jpegdec ! videoconvert` runs at ~29 fps and `waylandsink` shows the picture full-screen over the dashboard, hiding its alerts. Latency and CPU unmeasured | T | `agl-f250-22.0.1-6114c52.manifest`, `agl-f250-release-22.0.1-6114c52.manifest`; [bench-log](bench-log.md) 2026-11-09 (two entries) |
| meta-raspberrypi switches | `ENABLE_SPI_BUS`, `ENABLE_CAN`, `ENABLE_DUAL_CAN`, `RPI_EXTRA_CONFIG` | V | [extra-build-config](https://raw.githubusercontent.com/agherzan/meta-raspberrypi/master/docs/extra-build-config.md) |
| Build host | Native Linux. At least 300 GB for Flutter images. Yocto 6.0: 32 GB RAM example. No macOS. aarch64 not documented | V / U | [AGL](https://docs.automotivelinux.org/en/master/01_Getting_Started/02_Building_AGL_Image/02_Preparing_Your_Build_Host/), [Yocto](https://docs.yoctoproject.org/6.0/ref-manual/system-requirements.html) |
| 22.0.1 Pi 5 image contents (2026-11-06) | Same kernel 6.18.33, Flutter 3.38.3, flutter-auto 2.0, agl-compositor 0.0.24 as 22.0.0. glibc 2.43, systemd 259, OpenSSH 10.3, rsync, bash 5.3, sqlite 3.51.3, gpsd 3.27.5, avahi, alsa-utils, pipewire-tools. No `sudo`, no `i2c-tools`, no `dfu-util` | V | [manifest](https://download.automotivelinux.org/AGL/release/vimba/22.0.1/raspberrypi5/deploy/images/raspberrypi5/agl-ivi-demo-flutter-raspberrypi5.manifest) |
| 22.0.1 on the Pi 5 | Boots; `uname -r` 6.18.33-v8-16k; `/etc/default/flutter` 3.38.3 release; root SSH over Ethernet | T | [bench-log](bench-log.md), 2026-11-06 |
| Journal | Volatile as shipped: `/var/log` is a link to `/var/volatile/log` (tmpfs), `RuntimeMaxUse=64M`. We bind-mount `/var/lib/journal` there and set `Storage=persistent`, `SystemMaxUse=50M`: `journalctl -b -1` works after a reboot | T | [bench-log](bench-log.md) 2026-11-06 |
| Login and security | `agl-devel` features: root login, empty root password, SSH. SELinux `targeted`, **permissive** by default | V | `meta-agl-core/conf/include/agl-devel.inc`, `agl-selinux.inc` (branch `vimba`) |
| Network managers | connman manages IP; systemd-networkd is also installed, enabled, and configures CAN (`60-canbus-can.network`: every `can*` at 500k, normal mode) | V (source); enabled on the image: T, [bench-log](bench-log.md) 2026-11-06 | `meta-agl-core/recipes-core/systemd/systemd-conf-canbus`, [ADR-0015](../architecture/adr/0015-agl-can-defaults.md) |
| Demo CAN services | `kuksa-can-provider` (reads `can0` with the AGL demo DBC) and `can-dev-helper` (creates a virtual `can0` when none exists), both enabled. We mask them | V (source); enabled on the image: T, [bench-log](bench-log.md) 2026-11-06 | `meta-agl-demo/recipes-connectivity/kuksa-val/`, ADR-0015 |
| Flutter app layout | Bundle in `/usr/share/flutter/<app>/<version>/release/` (`data/flutter_assets`, `lib/libapp.so`, engine links); started by `flutter-auto -b <bundle>`; `config.toml` in the bundle sets the window (the demo homescreen: `window_type = "BG"`). `/etc/default/flutter` gives the version and runtime | V (source) | meta-flutter `conf/include/flutter-app.inc`; `meta-agl-demo/recipes-demo/flutter-ics-homescreen` |
| Our arm64 build on this glibc | Gateway, recorder and `obd-console` (Debian bookworm build) need glibc ≤ 2.34 symbols and only libc, libm, libgcc_s. Ran against each other in an arm64 container | V (readelf) / [SIM] | `make deploy-build`, 2026-11-06 |
| A `flutter build linux` AOT bundle under the image's flutter-auto | Works: fullscreen at 800×480 as the background surface (`window_type = "BG"`, app id `homescreen`), touch works ([H30](open-questions.md)) | T | [bench-log](bench-log.md) 2026-11-06 |
| flutter-auto on the Pi 5: renderer, textures, plugins | Draws with Vulkan (AGL's `flutter-auto_aglflutter.inc` drops the EGL backend on raspberrypi5). External textures are GL only, so a Flutter camera texture needs the EGL backend back. Plugins built in: audioplayers_linux, go_router, nav_render_view, desktop_window_linux, secure_storage; not video_player_linux, camera or comp_surf | T | [bench-log](bench-log.md) 2026-11-09 (rendering spike) |
| App windows in a `window_activation_area` | agl-compositor places other apps' windows inside the area the background client sets in `config.toml`; a `waylandsink` camera there leaves the status bar and alert banner visible | T | [bench-log](bench-log.md) 2026-11-09 (rendering spike) |
| Pi 5 quickstart docs | The ready-made-images guide still covers only the Pi 4 | V | [docs](https://docs.automotivelinux.org/en/master/01_Getting_Started/01_Quickstart/01_Using_Ready_Made_Images/) |

## NVMe on the Pi 5 (AGL 22.0.1)

Checked in the 22.0.1 image files on 2026-11-06 (the kernel `Image`, the base
device tree, `boot.scr`, `u-boot.bin`, the manifest). Nothing here has run on
our Pi. The HAT and the drive aren't chosen yet: **TODO** (owner).

| Item | Finding | Status | Source |
|---|---|---|---|
| Kernel drivers | NVMe (`nvme`, `nvme_core`) and the Pi 5 PCIe controller (`pcie-brcmstb`, `brcm,bcm2712-pcie`) are built into the kernel, not modules | V (strings in `Image`) | [22.0.1 images](https://download.automotivelinux.org/AGL/release/vimba/22.0.1/raspberrypi5/deploy/images/raspberrypi5/) |
| `config.txt` switch | `bcm2712-rpi-5-b.dtb` has the `pciex1`, `pciex1_gen` and `pciex1_no_l0s` parameters. `agl/boot/config-f250.txt` has `dtparam=pciex1`, commented until the HAT is fitted | V (dtb) / U (link up on our Pi) | same |
| Firmware turns PCIe on by itself for HAT+ boards | Reported for boards with a HAT+ ID EEPROM. Not checked here; uncommenting our line makes it moot | U | — |
| Does the firmware's DT reach the kernel? | `boot.scr` boots the kernel with `${fdt_addr}`, the device tree the firmware built from `config.txt`, so `dtparam`/`dtoverlay` lines apply | V (`boot.scr`) / U (on the Pi) | `boot.scr` |
| Boot path | U-Boot 2026.01 (`RPI_USE_U_BOOT = "1"`, `meta-agl-bsp/conf/include/agl_raspberrypi.inc`). `boot.scr`: `fatload mmc 0:1 ${kernel_addr_r} Image`. `cmdline.txt`: `root=/dev/mmcblk0p2`. **So this image can't boot from NVMe** | V | `boot.scr`, `bootfiles/cmdline.txt` |
| U-Boot on the Pi 5's PCIe | `u-boot.bin` has NVMe code and `brcm,bcm2711-pcie` (the Pi 4's), but no `bcm2712` PCIe string | U (string search only) | `u-boot.bin` |
| Tools in the image | `fdisk`, `mkfs.ext4`, `lsblk`, `blkid`, `findmnt`, `mountpoint`, `fstrim`, `lspci` (pciutils), `smartctl` (smartmontools 7.5). No `sfdisk`, `wipefs`, `parted` or `nvme-cli` | V | manifest |
| `f250-storage format` | GPT, one partition, ext4 labelled `f250-data`, with the image's `fdisk` (util-linux 2.41.5) | [SIM] (loop device, Debian trixie container, util-linux 2.41.5) | `agl/scripts/storage.sh` |
| Drive temperature range, power-loss protection | From the chosen drive's datasheet. Consumer drives are commonly 0–70 °C and rely on a clean shutdown | TODO | — |
| Stacking with the DAC8x, power | [H4](open-questions.md), [H25](open-questions.md) | U | — |

## Original Raspberry Pi 7" touchscreen (800×480, DSI) on the Pi 5

| Item | Finding | Status | Source |
|---|---|---|---|
| Cable | A **22-way to 15-way** FFC, the display type. A camera-type cable ties the I2C clock low and leaves the screen dark | V | [RPi display docs](https://www.raspberrypi.com/documentation/accessories/display.html), [linux#5813](https://github.com/raspberrypi/linux/issues/5813) |
| Overlay | `dtoverlay=vc4-kms-dsi-7inch`. Defaults to DSI1; add `,dsi0` for port 0. Includes the edt-ft5406 touch driver. Parameters: `sizex`, `sizey`, `invx`, `invy`, `swapxy`, `disable_touch`. Needs `vc4-kms-v3d` | V | [overlays README](https://raw.githubusercontent.com/raspberrypi/linux/rpi-6.12.y/arch/arm/boot/dts/overlays/README) |
| Pi 5 port mapping | DSI0 is the RP1's `dsi@110000` (registers `1f00118000`) with I2C bus 10 (`rp1/i2c@88000`, i2c6); DSI1 is `dsi@128000` (`1f00130000`) with I2C bus 11 (`rp1/i2c@80000`, i2c4). That these are the CAM/DISP 0 and 1 connectors is inferred from the names | V (rp1.dtsi, the Pi's `/sys`) / inferred | [rp1.dtsi](https://raw.githubusercontent.com/raspberrypi/linux/rpi-6.18.y/arch/arm64/boot/dts/broadcom/rp1.dtsi), [bench-log](bench-log.md) 2026-11-06 |
| Backlight | Regulator-based (`raspberrypi,7inch-touchscreen-panel-regulator`, I2C 0x45). The Pi 5 uses i2c-4/i2c-6 for the display ports | V | [overlay dts](https://raw.githubusercontent.com/raspberrypi/linux/rpi-6.12.y/arch/arm/boot/dts/overlays/vc4-kms-dsi-7inch-overlay.dts), linux#5813 |
| In the AGL image | The `vc4-kms-dsi-7inch.dtbo` overlay and the edt-ft5x06, tc358762, rpi-panel-attiny-regulator, rpi-backlight, panel-simple and drm-rp1-dsi modules. Rechecked in 22.0.1 | V | manifest |
| Turned on by us | `dtoverlay=vc4-kms-dsi-7inch,dsi0` in `agl/boot/config-f250.txt`, appended by `stage1-setup.sh`: picture and touch on AGL 22.0.1. Without `,dsi0` it drives DSI1 and the panel stays dark | T | [bench-log](bench-log.md) 2026-11-06 |
| Enabled in AGL `config.txt` | **No.** Only `vc4-kms-v3d-pi5,cma-256`. No `display_auto_detect`. `rpi-ft5406` is commented out | V | [AGL config.txt](https://download.automotivelinux.org/AGL/release/vimba/22.0.0/raspberrypi5/deploy/images/raspberrypi5/bootfiles/config.txt) |
| On Raspberry Pi OS Lite (trixie, kernel 6.18) | **Works with no `config.txt` change** on DSI0 (the 2026-11-02 entry said DSI1; its `dmesg` shows DSI0): picture, backlight, touch (edt_ft5x06 at I2C 10-0038), and the app fullscreen under `cage` | T | [bench-log](bench-log.md), 2026-11-02 |
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
| In the AGL image | `util-linux-hwclock` is in the 22.0.1 image; the Pi 5 RTC driver isn't a separate module package, so whether it is built in and honours `rtc_bbat_vchg` is not known. Our boot block sets the charging; check on the image: `ls /sys/class/rtc/`, `cat /sys/class/rtc/rtc0/charging_voltage`, `hwclock -r` ([agl.md](../setup/agl.md#5-bring-up-checks-phase-52)) | U | manifest |
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
| USB telemetry on Linux | mini-box links a Linux tool, [mini-box/dcdc-usb](https://github.com/mini-box/dcdc-usb). Not checked, and not needed: the USB port isn't connected (pulse-only, 2026-11-09) | U | — ([H24](open-questions.md), moot) |

## Raspberry Pi 5 power button and 5 V input

Source: [RPi docs](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html),
sections "Power button", "Power supply", "Universal Serial Bus (USB)" and
"Raspberry Pi bootloader configuration". Read 2026-11-04.

| Item | Finding | Status | Source |
|---|---|---|---|
| J2 | "Located between the RTC battery connector and the board edge." Takes a **normally-open momentary switch bridging the two pads**. Briefly closing it does the same as the onboard power button | V | Power button |
| J2 pad polarity, debounce | Not documented | U | — measure ([H21](open-questions.md)) |
| Press while running | Raspberry Pi OS Lite: one press starts a shutdown. With the desktop, a menu appears (press again, or press twice quickly). On AGL, logind's `HandlePowerKey` decides; power-manager sets it to `ignore` and handles the key itself | V (RPi OS) / T (AGL) | Power button; bench-log 2026-11-09 |
| Input device on AGL 22.0.1 | `pwr_button` (`/dev/input/event4` on the bench), `KEY_POWER`. The HDMI ports' CEC inputs (`vc4-hdmi-0/1`) report `KEY_POWER` too | T | bench-log 2026-11-09 |
| Press while halted but powered | "Restarts the board" | V | Power button |
| Press and hold | Forces a hard shutdown. **No duration is given** | V / U (duration) | Power button |
| Boots when power is applied | Stated for the first power-up. The docs don't say so for later power-ups. `WAIT_FOR_POWER_BUTTON` (default 0) with `POWER_OFF_ON_HALT=1` would instead wait for the button | V / U | Power button, bootloader config |
| Halted draw | About 1–1.4 W by default. About 0.01 W with `POWER_OFF_ON_HALT=1` | V | Power supply |
| USB current on a non-5 A supply | Downstream USB is limited to 600 mA (1.6 A on a 5 A supply). The budget is shared with the fan header | V | Power supply, USB |
| Telling the Pi it has a 5 A supply | `PSU_MAX_CURRENT=5000` in the EEPROM skips USB-PD negotiation and assumes that rating. The docs don't spell out its effect on the 600 mA limit; check with `vcgencmd get_config usb_max_current_enable` | V / U (effect) | Bootloader config, USB |
| `usb_max_current_enable=1` | Documented for **USB boot** on a 3 A supply. Not documented as a way to raise the peripheral current | V | Boot sequence |
| 5 V into the GPIO header | Bypasses the PMIC: USB current isn't visible. The docs don't present it as a supported way to power the board. **Use the USB-C input** | V / U | Power supplies and Raspberry Pi OS |

## 5-way navigation button module (camera switch candidate)

The owner's bench candidate for the camera switch, 2026-11-09
([ADR-0024](../architecture/adr/0024-camera-selection-switch-and-can-reverse.md),
[H32](open-questions.md)): an "EC Buying" five-way navigation button module,
Amazon ASIN `B0D8T4YQ3Y`. **The Amazon listing itself wasn't read** (Amazon
refuses automated readers). The rows below come from other sellers' listings
of this generic module, read 2026-11-09, so the exact board must be checked
against its own pin labels when it arrives.

| Item | Finding | Status | Source |
|---|---|---|---|
| Signal type | Digital, one contact per direction (up, down, left, right, centre), no potentiometers, so no ADC is needed | F | [Little Bird](https://littlebirdelectronics.com.au/products/five-direction-navigation-button-rocker-joystick-module) |
| Output | Active low: pressed reads LOW | F | Little Bird |
| Supply | 3.3–5 V compatible | F | Little Bird |
| Pins | Varies by seller: up, down, left, right, centre plus GND and VCC (Little Bird); other listings describe seven switches (adding SET and RST buttons) sharing one COM pin | C | Little Bird; search summaries of other sellers |
| On-board pull-ups | Unknown. If the board has a VCC pin it probably has them: then VCC goes to the Pi's **3.3 V**, never 5 V | U | — |
| Mounting | Bare PCB with pin headers, for breadboards. Needs an enclosure or panel mount and a cap for the dash; Dupont leads work loose with vibration | V (by its form) / U (in a truck) | listings |
| Temperature, durability | Not stated | U | — |
| Bench check | Pin labels, a meter on each line at the Pi (wiring checks 8–9), feel by hand | — | [wiring](../wiring/power-and-inputs.md#camera-switch) |

How the Pi reads it ([ADR-0025](../architecture/adr/0025-camera-switch-through-gpio-key.md)):

| Item | Finding | Status | Source |
|---|---|---|---|
| `gpio-key` overlay | Parameters `gpio`, `keycode`, `gpio_pull` (integer: 0 off, 1 down, 2 up; default up), `active_low` (default 1), `label`, `autorepeat`. **Default key 116, `KEY_POWER`** | V | [overlay README and source](https://github.com/raspberrypi/linux/tree/rpi-6.12.y/arch/arm/boot/dts/overlays), `rpi-6.12.y`, read 2026-11-09 |
| In the AGL image | `overlays/gpio-key.dtbo` in the boot partition of `agl-f250-22.0.1-288d091`, 1428 bytes, the same overrides | V | image files, 2026-11-09 |
| `gpio-keys` driver | In the AGL kernel: the Pi 5's power button uses it | T | bench-log 2026-11-09 |
| Pull-up on the Pi 5 (RP1) | The overlay sets `brcm,pull`; that it takes effect on RP1 isn't confirmed | U | — wiring check 8 |

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

## HiFiBerry DAC8x

Chosen 2026-11-04, not bought yet
([ADR-0014](../architecture/adr/0014-multichannel-dac8x.md)). Wiring:
[wiring/audio.md](../wiring/audio.md).

| Item | Finding | Status | Source |
|---|---|---|---|
| Compatibility | "Compatible with all Raspberry Pi 5". The datasheet doesn't mention older boards; retailers say Pi 5 only | V (Pi 5) / F (Pi 5 only) | [HiFiBerry datasheet](https://www.hifiberry.com/?p=201764), [PiShop](https://www.pishop.us/product/hifiberry-dac8x-for-raspberry-pi-5/) |
| Channels | 8 output channels from four Burr-Brown 192 kHz/24-bit DACs | V | datasheet |
| Connectors | 4 × 3.5 mm TRS (stereo pairs). The datasheet shows only a photo | F (retailer) | [Audiophonics](https://audiophonics.fr/en/dac-and-interface-modules/hifiberry-dac8x-p-19621.html) |
| Output level | 2.1 Vrms maximum | V | datasheet |
| SNR / THD+N / response | 112 dB, −93 dB (typical), 10 Hz–70 kHz (−3 dB) | V | datasheet |
| Power | From the Pi, under 0.3 W | V | datasheet |
| Overlay | `dtoverlay=hifiberry-dac8x` | V | datasheet |
| GPIO used | The overlay puts **BCM18–27** in `i2s0` mode and reads **BCM5** as `hasadc-gpio` (active-low, detects the ADC8x add-on). Whether the board itself routes BCM5: not documented | V (overlay source) | [`hifiberry-dac8x-overlay.dts`, rpi-6.12.y](https://github.com/raspberrypi/linux/blob/rpi-6.12.y/arch/arm/boot/dts/overlays/hifiberry-dac8x-overlay.dts) |
| Header pass-through | Not documented (H27) | U | — |
| Mute at boot, pop behaviour | Not documented (H6) | U | — |
| Jack-to-channel mapping | Not documented | U | — find with a test tone |
| AGL kernel support | The Vimba 22.0.1 image ships `hifiberry-dac8x.dtbo` and the modules the overlay uses (`snd-soc-rpi-simple-soundcard`, `snd-soc-pcm5102a`), plus `snd-soc-hifiberry-studio-dac8x`. Not tested; which driver binds is checked on the image with `aplay -l` | V (manifest) / U (works) | [22.0.1 manifest](https://download.automotivelinux.org/AGL/release/vimba/22.0.1/raspberrypi5/deploy/images/raspberrypi5/agl-ivi-demo-flutter-raspberrypi5.manifest), 2026-11-06 |

## Cameras and video

Researched 2026-11-10 for front and rear recording
([ADR-0027](../architecture/adr/0027-front-and-rear-recording.md)).

| Item | Finding | Status | Source |
|---|---|---|---|
| H.264 encoding on the Pi 5 | No hardware H.264 encoder (and no H.264 decoder; HEVC decode only). libx264 in software on the four A76 cores does 1080p30 in real time, per Raspberry Pi's white paper: one stream, nothing else said about the load. Not measured here | V | [Raspberry Pi white paper RP-010033-WP](https://pip-assets.raspberrypi.com/categories/685-app-notes-guides-whitepapers/documents/RP-010033-WP-1-H.264%20encoding%20performance%20on%20Raspberry%20Pi%205_series%20computers.pdf) |
| USB layout of the Pi 5 | RP1 has two xHCI controllers, each with one USB 3 and one USB 2 port (5 Gbit/s per controller) | V | [Raspberry Pi docs: I/O controllers](https://www.raspberrypi.com/documentation/computers/io-controllers.html) |
| Several UVC cameras on one USB 2 bus | Isochronous video gets at most about 80 % of a Hi-Speed bus (≈384 Mbit/s), and `uvcvideo` reserves by each camera's declared maximum payload, so two cameras can fail to start ("No space left on device") even when their real traffic fits | F | [The Good Penguin](https://www.thegoodpenguin.co.uk/?p=251) |
| Recording plugins on our image | `matroska` and `multifile` (`splitmuxsink`) are not in the `6114c52` manifest; no `x264enc` either | V | `agl-f250-22.0.1-6114c52.manifest` |

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
| Turn signal / reverse on HS-CAN | **Turn signals: not on HS-CAN**, an analogue flasher-relay circuit under the dash (owner, 2026-11-07); none seen in the census either. Reverse: broadcast candidates (`230`, `420`) | T (census) / owner | — check with a listen-only [event capture](../setup/can.md#event-captures-reverse-and-brake) |

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
| Factory firmware | **slcan**: the CANable 2.0 firmware, normaldotcom canable2-fw `b158aa7`. USB `16d0:117e`, "Openlight Labs CANable2". (The manual contradicted itself.) | T | [bench-log 2026-11-05](bench-log.md#2026-11-05--usb-can-adapter-factory-firmware-is-slcan-bench) |
| Listen-only with the factory firmware | **Not possible.** `O` (open) resets the mode to normal after `M1` (silent) set it, and there is no `L` command, which the kernel's slcan driver sends for listen-only. Read from the source at that commit, not measured | U (source read) | [canable2-fw `src/can.c`, `src/slcan.c` @ b158aa7](https://github.com/normaldotcom/canable2-fw/tree/b158aa7ab106bc018715cd4d5f02f544f9de1830/src) |
| Mainline candleLight_fw on the STM32G431 | **Not supported** ("STM32G431-based devices … are not supported by this project yet"). The canable.io claim of candleLight for CANable 2.0 conflicts | C | [candleLight_fw README](https://github.com/candle-usb/candleLight_fw), [canable.io](https://canable.io/index.html) |
| Candlelight 2.5 (Elmue, MIT) | gs_usb-compatible firmware for STM32G431 CANables, with prebuilt DFU files including a "Jhoinrch" build. Enumerates as `1d50:606f` (mainline `gs_usb`). Maps gs_usb listen-only to FDCAN bus-monitoring (no ACKs). Its manual says Jhoinrch ships it as stock firmware since 2026, and that RH-02 boards have a 25 MHz crystal "since 2026" | F (read from source and manual) / T (flashed: `gs_usb` `can0`, listen-only accepted; no-ACK not yet shown) | [bench-log 2026-11-05](bench-log.md#2026-11-05--usb-can-adapter-flashed-with-candlelight-25-bench); [Elmue/CANable-2.5-firmware-Slcan-and-Candlelight @ 12aa9fa](https://github.com/Elmue/CANable-2.5-firmware-Slcan-and-Candlelight/tree/12aa9fa1210757923507f6d390f7f909049f4e84): `Firmware/Candlelight/control.c`, `usb_class.c`, the manual |
| Listen-only | Listed as a mode by the manual. Under `gs_usb`, set with `ip link … listen-only on` | V (manual, kernel docs) / U (this board) | `can.sh listen` refuses if the driver doesn't accept it |
| Pi 5 kernel (Raspberry Pi OS, 6.18.50) | Ships `gs_usb`, `slcan`, `vcan`, `can-isotp` modules | T | `ls /lib/modules/…` on the Pi, 2026-11-03 |
| macOS (Apple silicon) | "Not temporarily supported" per the manual | V (manual) | manual — irrelevant here, it runs on the Pi |

## Linux CAN facts

| Item | Finding | Status | Source |
|---|---|---|---|
| Listen-only | `ip link set can0 type can bitrate 500000 listen-only on` | V | [kernel CAN docs](https://docs.kernel.org/networking/can.html) |
| Listen-only on the mcp251x driver | Driver support to be confirmed on the bench | U | — |
| ISO-TP | Mainline since 5.10. `socket(PF_CAN, SOCK_DGRAM, CAN_ISOTP)`. `isotp*` tools in can-utils | V | [iso15765-2 docs](https://docs.kernel.org/networking/iso15765-2.html) |
| USB CAN (candleLight) | Mainline `gs_usb` | V | [candleLight_fw](https://github.com/candle-usb/candleLight_fw) |
| Listen-only on the slcan driver | The kernel's slcan driver (ip-configured, since 2022) sends `L` instead of `O` when listen-only is set. The firmware gives no ACK/NACK, so a firmware without `L` fails silently | F | [LKML patch "can: slcan: send the listen-only command to the adapter"](https://lkml.iu.edu/hypermail/linux/kernel/2207.2/06317.html) |

## Alternatives

| If… | Then |
|---|---|
| PSW is a driven voltage, not a contact ([H21](open-questions.md)) | Put a small reed relay or optocoupler between PSW and J2 |
| The DCDC-USB can't hold 5 V at the Pi's load ([H25](open-questions.md)) | Run it at 12 V into a dedicated 5 V / 5 A converter, and keep it for the ignition logic and PSW |
| The turn signals aren't on HS-CAN (settled 2026-11-07: they aren't) | Not used: a 5-way switch picks the side cameras ([ADR-0024](../architecture/adr/0024-camera-selection-switch-and-can-reverse.md)) |
| A CAN HAT is wanted instead of USB | Waveshare 2-CH CAN HAT: isolated, jumper termination, 16 MHz, INT GPIO23/25 ([wiki](https://www.waveshare.com/wiki/2-CH_CAN_HAT)). Check its pins against the DAC HAT and the camera switch |
