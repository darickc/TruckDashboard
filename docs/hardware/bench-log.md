# Bench and installation log

Hardware evidence goes here: measurements, photos, `dmesg` and command output.
A feature is "hardware-tested" only when it has an entry here or in
[../diagnostics/VERIFICATION_LOG.md](../diagnostics/VERIFICATION_LOG.md).

## Entry template

```
## YYYY-MM-DD — <what was tested>

Hardware: <Pi 5 rev, HAT rev, cables, adapters>
Image: <Raspberry Pi OS / AGL 22.0.x prebuilt / meta-f250 @ git rev>
Setup: <config.txt lines, commands>

Result:
    <output / measurement>

Verdict: works | fails | partial — <what this does and does not prove>
Closes: <open-questions.md item, if any>
```

## Entries

## 2026-11-01 — OBDLink MX+ pairing method (reported by the owner)

Hardware: OBDLink MX+ `00:04:3E:85:EA:FC`
Setup: Bluetooth pairing with the MX+ from the owner's phone (the device used with Torque Pro)

Result:
    A pairing passkey was displayed. It was not 1234, and nothing had to be
    entered to complete pairing.

Verdict: the MX+ uses Secure Simple Pairing (passkey shown / confirmed), not
the legacy fixed PIN commonly documented as 1234. This doesn't yet show which
SSP variant the Pi's BlueZ will negotiate; record the `bluetoothctl` transcript
in Phase 3.5.2.
Closes: nothing; it corrects the pairing step in PROJECT_PLAN.md 3.5.2.

## 2026-11-01 — Pi 5 software bring-up on Raspberry Pi OS Lite, no display [BENCH]

Hardware: Raspberry Pi 5 Model B Rev 1.0, 8 GB, 128 GB SD card. **No display
attached** (the DSI cable has not arrived). No MX+ in range, no vehicle.
Image: Raspberry Pi OS Lite 64-bit, Debian 13 (trixie), kernel
`6.18.50+rpt-rpi-2712`. Repo at `3b27c69` plus the uncommitted `tools/pi` changes, copied with rsync.
Setup: `make pi-setup`, `make pi-build`, then `tools/pi/run.sh` over SSH.

Result:
    pi-setup   apt packages, rustup (1.99.1), fvm, Flutter 3.38.3 with the
               linux-arm64 Dart 3.10.1 SDK; BlueZ 5.82, bluetooth.service active;
               cage 0.3.1, grim 1.4.0
    pi-build   EXIT=0. Gateway (--features rfcomm), recorder, obd-console, and
               build/linux/arm64/release/bundle/f250_infotainment
    UI=0       sim gateway + recorder for 15 s; recorder rows VALID (rpm, ect,
               trans_temp); clean stop, no leftover processes
    UI=headless  app under cage on a 1280x720 virtual output (WLR_BACKENDS=headless).
               GLES2 renderer on V3D 7.1.7.0 (Mesa 26.2.2). grim screenshot shows
               the Home screen: SIMULATED badge, "Link up", values arriving over gRPC
               from the gateway, UNVERIFIED badges, 800x480 layout letterboxed
    shutdown   SIGTERM to run.sh stops app, recorder and gateway (exit 130);
               the app exiting stops the rest (exit 0). The first version
               ignored SIGTERM while the app ran; fixed in run.sh
    obdlink    TRANSPORT=obdlink without TRANSMIT: gateway PASSIVE_ONLY,
               obd-console stats 0.0 requests/s, `raw ATRV` REFUSED
               ("transmit disabled (--transmit not given)")

Verdict: partial. This shows the toolchain installs, everything builds natively
on the Pi 5 and the stack runs end to end on it [BENCH, simulated data]. It does
**not** show the display, touch or ribbon (3.5.1 stays open), `cage` on the
physical screen when started over SSH, Bluetooth to the MX+ (3.5.2) or anything
on the truck.
Closes: H17 (Flutter 3.38.3 builds and runs the Linux desktop app on the Pi 5).

## 2026-11-02 — Original 7" DSI display on the Pi 5, console only [BENCH]

Hardware: the Pi 5 from the 2026-11-01 entry, Raspberry Pi OS Lite (trixie).
Original Raspberry Pi 7" touchscreen on **DSI1** (the connector next to the
USB ports) with the 22-way to 15-way display cable. **No CarPiHAT fitted.**
`/boot/firmware/config.txt` unchanged (stock auto-detect, no overlay added).
Picture reported by the owner; `dmesg` below, no photo.

Result:
    picture    Boot messages and the Linux console show on the panel
    backlight  On (the console is readable)
    touch      Controller found (edt_ft5x06 at I2C 10-0038, see dmesg). Input not
               tested: Lite has no GUI, so nothing on screen reacts to touch
    app        Not run on the physical screen (`make pi-run` not tried yet)

`dmesg | grep -i -E 'dsi|panel|ft5406|edt|touch'`, the lines that matter (the
rest are `Fixed dependency cycle(s)` notices and IOMMU setup; no errors):

    [4.196174] drm-rp1-dsi 1f00118000.dsi: rp1dsi_host_attach: Attach DSI device name=tc358762 channel=0 lanes=1 format=0 flags=0x815 hs_rate=0 lp_rate=0
    [4.202758] [drm] Initialized drm-rp1-dsi 1.0.0 for 1f00118000.dsi on minor 0
    [4.318295] edt_ft5x06 10-0038: supply iovcc not found, using dummy regulator
    [4.324396] drm-rp1-dsi 1f00118000.dsi: [drm] rp1dsi: Nominal Byte clock 90000000 DPI clock 30000000 (parent rate 90000000)
    [4.707531] drm-rp1-dsi 1f00118000.dsi: [drm] fb0: drm-rp1-dsidrmf frame buffer device
    [4.723097] drm-rp1-dsi 1f00118000.dsi: rp1dsi_bind succeeded

So the RP1 DSI host bound the display's TC358762 bridge (1 lane) as DRM minor 0
(`/dev/dri/card0`), and the FT5x06 touch driver probed at I2C address 0x38.
The touch controller shows up on I2C bus 10 here, not the i2c-4/i2c-6 the
compatibility matrix lists for the display ports. **UNVERIFIED** why (bus
numbering or a mux on this kernel); check with `i2cdetect -l` if it matters
for AGL. The dummy `iovcc` regulator warning did not stop the driver probing.

Verdict: partial. The panel, cable and DSI1 work with stock Raspberry Pi OS
configuration, and the touch controller probes [BENCH]. This does **not** show
touch input, the dashboard under `cage` on the physical screen, or the ribbon clearing the HAT (H3).
Closes: nothing. 3.5.1 stays open (touch, app on screen, HAT fit).

Next, on the Pi's own console (not SSH), to finish 3.5.1:

```bash
sudo apt install libinput-tools && sudo libinput list-devices | grep -A2 -i touch
make pi-run                                        # app fullscreen under cage; tap the tabs
```

## 2026-11-02 — Dashboard and touch on the 7" display [BENCH]

Hardware and image as in the previous entry: original 7" display on DSI1,
22-way to 15-way display cable, no CarPiHAT, stock `config.txt`. No MX+, no
vehicle. Reported by the owner; no photo or screenshot.
Run: `make pi-run` (simulator, transmits nothing), started on the Pi itself
as the previous entry's next steps say.

Result:
    app        The dashboard runs fullscreen under `cage` and fills the 800x480 panel
    touch      Taps work in the app

Verdict: pass for ADR-0005 stage 0 on Raspberry Pi OS [BENCH, simulated data].
Display, touch and the ribbon work, and the stack runs fullscreen on the
physical screen. Still not shown: the ribbon with the HAT fitted (H3), `cage`
on the physical screen when `make pi-run` is started over SSH, and any of this
under AGL (the AGL `config.txt` doesn't enable the display).
Closes: roadmap 3.5.1.
