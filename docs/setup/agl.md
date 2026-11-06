# AGL on the Pi 5: Stage 1 (prebuilt image plus our services)

Phase 5.2–5.5, [ADR-0005](../architecture/adr/0005-staged-agl-bringup.md)
Stage 1. Flash the pinned AGL image, then `make deploy` installs our gateway,
recorder and dashboard on it. No Yocto build.

> **Status (2026-11-06):** nothing on this page has run on the AGL image yet.
> The scripts are tested in simulation (`make agl-test`), and the arm64
> binaries ran in a container: the gateway, recorder and `obd-console` against
> each other over `/run/f250/vehicle.sock`. Record each step that works on the
> Pi in [bench-log.md](../hardware/bench-log.md), and turn the checks below
> into ticks.

> **⚠ Vehicle bus:** the stock AGL image puts any CAN interface in normal mode
> at 500 kbit/s, so the adapter would ACK on the truck's bus, and it runs a
> CAN provider on `can0` ([ADR-0015](../architecture/adr/0015-agl-can-defaults.md)).
> **Keep the CAN adapter unplugged until `make deploy` has run and
> `stage1-setup.sh --check` passes.**

| What | Where |
|---|---|
| Release pin | [`agl/configurations/vimba.env`](../../agl/configurations/vimba.env): Vimba 22.0.1, Flutter engine 3.38.3 |
| Boot config we add | [`agl/boot/config-f250.txt`](../../agl/boot/config-f250.txt) |
| Files installed on the Pi | [`agl/rootfs/`](../../agl/rootfs/) |
| Setup, check, undo | [`agl/scripts/stage1-setup.sh`](../../agl/scripts/stage1-setup.sh) |
| Layout and users | [ADR-0016](../architecture/adr/0016-stage1-sideload-layout.md) |

## 1. What you need

- **A second microSD card, 16 GB or larger.** The image is 8.05 GB once
  decompressed. Keep the Raspberry Pi OS card as it is: it is the fallback
  ([section 6](#6-fallback-is-it-the-hardware-or-agl)).
- Ethernet to the Pi for the first boot (the image gets an address by DHCP
  through connman). Wi-Fi setup on AGL is not covered here.
- Optional: an HDMI monitor on HDMI0. AGL's own `config.txt` doesn't turn the
  7" panel on; our boot config does, after the first deploy.
- On the Mac: Docker Desktop running (`make deploy-build` uses it) and `zstd`
  (`brew install zstd`).

## 2. Download and flash

```bash
make agl-image
```

This downloads the image (1.3 GB) into `build/agl/`, checks its SHA-256
against the pin, and decompresses it to `build/agl/agl-ivi-demo-flutter-raspberrypi5.wic`.
It never writes to a disk.

Flash the `.wic` with **Raspberry Pi Imager**: *Choose OS → Use custom*, pick
the `.wic`, choose the new card, and **skip OS customisation** (it is for
Raspberry Pi OS). A `.wic` is a raw disk image like an `.img`; if Imager
doesn't list it, rename it to `.img`.

Command-line alternative: find the card with `diskutil list` (check its size
twice; `dd` overwrites whatever disk you name), then `diskutil unmountDisk
/dev/diskN` and `sudo dd if=build/agl/agl-ivi-demo-flutter-raspberrypi5.wic of=/dev/rdiskN bs=4m`.

## 3. First boot and SSH

1. CAN adapter **unplugged**. Card in, Ethernet in, power on.
2. Find the Pi. The image has avahi, so try `ping raspberrypi5.local`
   (UNVERIFIED: the hostname should be the machine name). Otherwise look in
   the router's DHCP list.
3. `ssh root@raspberrypi5.local`. The AGL development image has an **empty
   root password**: press Enter. Put your key on it so `make deploy` doesn't
   ask each time:
   ```bash
   ssh-copy-id root@raspberrypi5.local
   ```
   This image is for the bench. It is not locked down; `meta-f250`
   (Phase 5.4) will be.
4. Before deploying, look at the image as it comes (bench-log entry):
   `cat /etc/os-release`, `uname -r`, `cat /etc/default/flutter`,
   `systemctl is-enabled systemd-networkd kuksa-can-provider can-dev-helper`.

## 4. Deploy

```bash
make deploy PI=raspberrypi5.local
```

1. Builds the gateway, recorder and `obd-console` for aarch64, and the
   dashboard's AOT bundle with Flutter 3.38.3, in an arm64 container. The
   first run builds the container and takes a while. The output goes to
   `build/agl-arm64/`.
2. Refuses a Pi whose Flutter engine (from `/etc/default/flutter`) isn't the
   version the bundle was built with.
3. Copies everything to the Pi ([ADR-0016](../architecture/adr/0016-stage1-sideload-layout.md)):
   `/opt/f250/bin/`, `/opt/f250/share/{agl,data}/`, and the bundle in
   `/usr/share/flutter/f250_infotainment/3.38.3/release/`.
4. Runs `stage1-setup.sh` on the Pi. CAN safety comes first: it masks the KUKSA
   CAN units, installs the networkd override, and takes `can0` down if it is up
   in normal mode. Then it appends our block to `config.txt`, adds the `f250`
   user, installs the units, swaps the demo homescreen for the dashboard, and
   starts the services.

Then **reboot** (`ssh root@raspberrypi5.local reboot`), since `config.txt` and
the logind change apply at boot, and check:

```bash
ssh root@raspberrypi5.local /opt/f250/share/agl/scripts/stage1-setup.sh --check
```

Later deploys: `make deploy PI=…` again; it is idempotent.
`SKIP_BUILD=1` reuses the last build. Your settings in `/etc/default/f250` are
never overwritten.

## 5. Bring-up checks (Phase 5.2)

Each line is a bench-log entry when it passes. Mark results **[BENCH]**.

| # | Check | How | Answers |
|---|---|---|---|
| 1 | CAN safety | `stage1-setup.sh --check`: both KUKSA units masked, override in place, `can0` absent or down | ADR-0015 |
| 2 | Display | Picture on the 7" panel after the reboot. If not: [section 6](#6-fallback-is-it-the-hardware-or-agl) | — |
| 3 | Touch | Tap the dashboard's nav bar | — |
| 4 | Backlight | `cat /sys/class/backlight/*/max_brightness`; write a lower value to `brightness` and back | Phase 6.7 dimming |
| 5 | Dashboard | Runs fullscreen at 800×480, shows the simulator's data with the SIMULATED badge. `journalctl -u f250-dashboard -b` | H30 |
| 6 | Gateway and recorder | `systemctl status f250-gateway f250-recorder`; `obd-console` (an alias for the AGL socket) shows live values; `ls -l /var/lib/f250/` | — |
| 7 | Power button | Dashboard *Power* → the Pi powers off cleanly (`journalctl -b -1 -u f250-dashboard` after the next boot shows "power off: requested") | ADR-0016 |
| 8 | CAN, listen-only | Plug in the adapter, then `f250-can status` (still down), `f250-can listen`, `ip -details link show can0` shows `LISTEN-ONLY`. With a second node on a bench bus: no ACKs | H7 on the AGL kernel |
| 9 | RTC | `ls /sys/class/rtc/`, `cat /sys/class/rtc/rtc0/charging_voltage` (3000000 with our block), `hwclock -r` | H20 on AGL |
| 10 | Audio (once the DAC8x is fitted) | Uncomment `dtoverlay=hifiberry-dac8x` in `agl/boot/config-f250.txt`, deploy, reboot; `aplay -l` lists it; `pw-cli ls Node` shows its sink | ADR-0014 on AGL |

If something fails, collect the evidence before changing anything:

```bash
make logs PI=raspberrypi5.local
ssh root@raspberrypi5.local /opt/f250/share/agl/scripts/diagnose-display.sh
```

`make logs` copies an archive into `build/logs/`. `diagnose-display.sh` (for
display, touch and backlight problems) prints the archive's path on the Pi;
copy it with `scp`.

### Settings

`/etc/default/f250` has the same options as `make pi-run`:
`TRANSPORT=sim|obdlink|can`, `TRANSMIT=0|1`, `ADAPTER`, `CAN_IF`, `ENABLE`,
`BUDGET_RPS`. Edit it on the Pi, then `systemctl restart f250-gateway`. The
same rules as on Raspberry Pi OS apply: without `TRANSMIT=1` the gateway never
opens the adapter (ADR-0007), and `TRANSPORT=can TRANSMIT=1` needs
`f250-can active` first ([can.md](can.md)).

`f250-can` is `tools/pi/can.sh`; everything in [can.md](can.md) applies, run
as root on the Pi (no `sudo` on AGL). The firmware `flash` command needs
`dfu-util`, which the image doesn't have: flash from Raspberry Pi OS.

## 6. Fallback: is it the hardware or AGL?

Phase 5.3. When the display, touch, CAN or audio fails on AGL, find out which
side the fault is on before changing anything. The Raspberry Pi OS card is the
known-good reference: the panel, touch and dashboard worked on it on
2026-11-02 ([bench-log](../hardware/bench-log.md)).

1. **Collect on AGL first:** `make logs PI=…` and `diagnose-display.sh` (above).
   Keep the archives.
2. **Swap to the Raspberry Pi OS card**, same Pi, same cables, nothing else
   changed, and run `agl/scripts/diagnose-display.sh` there too (the same
   script, from the repo).
3. Compare:

   | Raspberry Pi OS | AGL | Then |
   |---|---|---|
   | Works | Fails | **AGL side.** Compare the two archives: is the overlay applied (`drm-connectors.txt` has a DSI connector), are the modules loaded (`modules.txt`: `tc358762`, `edt_ft5x06`, `rpi_panel_attiny_regulator`), is the right I2C bus there (`i2c.txt`)? Check our block is in `config.txt` (`boot-config.txt`). Try the port: `dtoverlay=vc4-kms-dsi-7inch,dsi0` with the ribbon on DISP 0. Record the result in the [compatibility matrix](../hardware/compatibility-matrix.md) |
   | Fails | Fails | **Hardware or cabling.** Reseat the ribbon at both ends (contacts facing the right way), try the other DISP port, check the panel's 5 V. HDMI0 with a monitor tells whether the Pi itself boots and draws |
   | Works | Works | The fault was transient: note what changed (cables, power) in the bench log |

4. **Display dark, but you need the Pi:** plug HDMI0. Raspberry Pi OS's
   console uses it; AGL's compositor should too (UNVERIFIED).
   Over SSH, `stage1-setup.sh --restore-demo` brings the AGL demo homescreen
   back (to tell our dashboard apart from the platform). Undo our boot block by
   copying `config.txt.agl-orig` over `config.txt` on the boot partition
   (readable from the Mac, it's FAT).
5. **CAN:** the same comparison with `f250-can status` and `listen` on both
   cards. Same result on both points at the adapter or wiring
   ([can.md](can.md)); a difference points at the AGL kernel's `gs_usb` (H7).

## What's not here yet

- `meta-f250`, the custom image (Phase 5.4). It needs the Linux build host
  ([ADR-0004](../architecture/adr/0004-linux-build-host.md),
  [linux-build-host.md](linux-build-host.md)).
- Watchdogs: the units have none, because the gateway doesn't send systemd
  keep-alives yet (power-manager, Phase 6.7).
- The power key does nothing on AGL (logind ignores it, as planned for the
  DCDC-USB); shut down with the dashboard's *Power* button or `systemctl poweroff`.
