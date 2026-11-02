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
