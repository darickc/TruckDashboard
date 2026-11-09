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
USB ports) with the 22-way to 15-way display cable. *Correction 2026-11-06:*
the `dmesg` below shows the RP1's DSI0 (`1f00118000.dsi`) and touch on I2C
bus 10 (`rp1/i2c@88000`, the DSI0 port's bus), so the panel is on DSI0
(CAM/DISP 0). See the 2026-11-06 AGL display entry. **No CarPiHAT fitted.**
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

Verdict: partial. The panel, cable and DSI0 (corrected, see above) work with stock Raspberry Pi OS
configuration, and the touch controller probes [BENCH]. This does **not** show
touch input, the dashboard under `cage` on the physical screen, or the ribbon clearing the HAT (H3).
Closes: nothing. 3.5.1 stays open (touch, app on screen, HAT fit).

Next, on the Pi's own console (not SSH), to finish 3.5.1:

```bash
sudo apt install libinput-tools && sudo libinput list-devices | grep -A2 -i touch
make pi-run                                        # app fullscreen under cage; tap the tabs
```

## 2026-11-02 — Dashboard and touch on the 7" display [BENCH]

Hardware and image as in the previous entry: original 7" display on DSI0 (corrected),
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

## 2026-11-02 — Mouse cursor on the dashboard under cage [BENCH]

Hardware and image as in the previous entry, plus a ROCCAT Suora USB keyboard.
No mouse or trackpad. Symptom: a mouse cursor drawn over the dashboard.

`sudo libinput list-devices | grep -E '^Device:|^Capabilities:'`:

    Device:  10-0038 generic ft5x06 (79)        Capabilities: touch
    Device:  ROCCAT ROCCAT Suora                Capabilities: keyboard
    Device:  ROCCAT ROCCAT Suora Mouse          Capabilities: pointer
    Device:  ROCCAT ROCCAT Suora System Control Capabilities: keyboard
    Device:  ROCCAT ROCCAT Suora Consumer Control Capabilities: keyboard pointer
    Device:  pwr_button                         Capabilities: keyboard
    Device:  vc4-hdmi-0                         Capabilities: keyboard pointer
    Device:  vc4-hdmi-1                         Capabilities: keyboard pointer

Cause: cage 0.3.1 shows a cursor whenever the seat has a pointer, and hides it
only when none exists (`seat.c`, "Hide cursor if the seat doesn't have pointer
capability"). The `vc4-hdmi-*` devices are the HDMI ports' CEC remote inputs.
They are there with no HDMI connected, so the cursor would appear in the truck
as well, not only with this keyboard.

Fix (not yet run on the Pi): `tools/pi/udev/90-f250-kiosk-input.rules` sets
`LIBINPUT_IGNORE_DEVICE=1` on `vc4-hdmi-[0-9]`, installed by `make pi-setup`.
The keyboard's pointer interfaces are left alone (bench only).
To verify: after `make pi-setup`, the command above no longer lists
`vc4-hdmi-0/1`; with the keyboard unplugged, `make pi-run` shows no cursor and
touch still works.
Closes: nothing until verified (see the next entry).

## 2026-11-02 — Cursor fix verified; `make pi-run` over SSH fails [BENCH]

Same Pi. `tools/pi` copied from `4e462a3` with rsync (the Pi's checkout is
`3b27c69` plus the copied files); `make pi-setup` run on the Pi by the owner.
The rule is at `/etc/udev/rules.d/90-f250-kiosk-input.rules`.

Cursor: `make pi-run` started on the Pi's console with the keyboard in shows the
cursor (the keyboard's own pointer interfaces). Unplugging the keyboard removes
it, and the dashboard stays up. With the keyboard out, libinput lists only:

    Device:  10-0038 generic ft5x06 (79)   Capabilities: touch
    Device:  pwr_button                    Capabilities: keyboard

`Gdk-Message: Unable to load  from the cursor theme` in `app.log` is the
app's GTK cursor lookup and had no visible effect.

SSH: `make pi-run` started over SSH fails after 10 s (two tries, 18:57 and
18:58). `app.log`:

    [libseat] [seatd/seat.c:80] Could not open terminal for VT 0: Permission denied
    [libseat] [libseat/libseat.c:73] Seat opened with backend 'builtin'
    [backend/backend.c:105] Timeout waiting session to become active
    [../cage.c:335] Unable to create the wlroots backend

Cause: `loginctl list-sessions` shows the console login on `tty1` with
`seat0` and the SSH sessions with no seat. libseat cannot use logind for a
session without a seat, so it falls back to its built-in seatd. That
needs to open the VT, which the user can't (`seatd` the daemon isn't
installed; `libseat1` 0.9.1).
Fix: TODO. The cage wiki's way is a systemd unit with its own VT and a PAM
session (`PAMName=`, `TTYPath=`), which gets a logind session on `seat0`
([Starting Cage on boot with systemd](https://github.com/cage-kiosk/cage/wiki/Starting-Cage-on-boot-with-systemd)).
Closes: the cursor fix (verified). Not the SSH start (see the next entry).

## 2026-11-02 — `make pi-start` / `pi-stop` over SSH [BENCH]

Same Pi, display and image; keyboard unplugged. `tools/pi` and `Makefile`
copied from the working tree with rsync. Simulator only, transmits nothing.
Run over SSH from the Mac: `make pi-start`, `make pi-status`, a `grim`
screenshot, then `tools/pi/service.sh stop`. Two cycles, 19:11 and 19:12.

Result:
    start      systemd-run unit f250-dashboard (transient), PAMName=login on tty7.
               loginctl: new session on seat0, tty7 (SSH sessions have no seat).
               cage: "connector DSI-1: Modesetting with 800x480 @ 60.029 Hz".
               Gateway, recorder and app running; processes in session-N.scope
    screen     grim screenshot: Home, SIMULATED, "Link up", 14/14 current,
               800x480, no letterboxing
    stop       systemctl stop signals run.sh only (KillMode=mixed); run.sh stops
               app, recorder, gateway: "Session saved in …", `stopped:` in
               session.txt, no processes left, tty7 session closed, chvt back to 1
    logs       first cycle: `journalctl -u f250-dashboard` had only systemd's own
               lines, because PAM moves the processes to the session scope. Fixed
               with SyslogIdentifier; second cycle: `journalctl -t f250-dashboard`
               has run.sh, cage and app output

Verdict: pass [BENCH, simulated data]. The dashboard can be started and stopped
over SSH. Not shown: starting it at boot (not set up), the owner looking at the
screen during the run (the screenshot is cage's output), the MX+.
Closes: the SSH start from the previous entry.

## 2026-11-02 — First MX+ session on the Pi: key on, then idle [TRUCK]

Hardware: the Pi 5 and display from the entries above, in the truck; OBDLink
MX+ `00:04:3E:85:EA:FC` in the DLC over Bluetooth (RFCOMM). No added wiring.
Run by the owner: `make pi-start TRANSPORT=obdlink TRANSMIT=1` at `4b586ac`,
19:50:05–19:56:17 (6 min 12 s), then `make pi-stop`. `obd-console` in a second
SSH session. Session: `~/f250-data/20261102-195005-obdlink/` on the Pi
(`traffic/adapter-traffic.1.log`, 12 838 lines; `obd-console-1793674333.log`).
Transmit opt-in (ADR-0007): `TRANSMIT=1`, read-only services only; nothing
outside `01 03 07 09 22` and the init `AT` commands appears in the traffic log.
Pairing itself was not logged (no `bluetoothctl` transcript).

Result:
    connect    one RFCOMM connect failure ("Connection reset by peer", os error 104),
               then connected; the first ATZ got no answer for 7.5 s, the second
               did: "ELM327 v1.4b". Init ATE0 ATL0 ATS0 ATH1 ATAT1 ATSP6 all OK
    adapter    raw ATRV 12.2V key on, 13.5–13.6V later (engine running);
               raw ATDPN 6 (matches the ESP32's protocol 6 on this truck)
    responders 7E8 and 7E9 both answer the 01 PIDs; 221674: 7E9 62 16 74 …, 7E8 7F 22 31
    values     at idle (console `pids`, 310 s): rpm 689.75, speed 0, ect 50 °C,
               iat 18 °C, load 38.8 %, baro 85 kPa, trans_temp 49.72 °C. Only
               trans_temp is VERIFIED_ON_TRUCK; the SAE PIDs use published
               formulas but have no verification-log entry for this session
    throughput 13.3 requests/s over 310 s (console `stats`); p50 65–84 ms,
               p95 96–127 ms. Failures: rpm 1/834, speed 5/533, load 2/361,
               trans_temp 1/268, ect/baro/iat 0
    run.sh     `make pi-stop` stopped it cleanly, but systemd marks the unit
               `failed` because run.sh exits 130 on SIGTERM (cosmetic, see below)

**A dropout, and its cause in the traffic log.** Times are ms since connect.

    17860 TX 010C ... 18084 / 18226 RX      replies slow from ~30 ms to 200–360 ms
    18294 TX 010D
    18795 TX (bare CR)                      500 ms timeout → client sends CR to provoke a prompt
    18925 RX >                              the LATE prompt of 010D; the client takes it
                                            as the answer to the CR and goes Idle
    18996 TX 010D
    18999 RX 7E803410D00                    3 ms later: the ELM's REPEAT of 010D (a bare CR
                                            repeats the last command), paired with the new request
    ...                                     replies stay one request behind; commands are sent
                                            before the prompt
    20855 TX ATRV → RX 7E803410D00          an ATRV "answered" with a speed reply
    21770 RX STOPPED                        the ELM aborted a command (a byte arrived mid-request)

What followed (gateway.log, which has no timestamps; times from the traffic log):
link DEGRADED ↔ RECOVERING_SOFT about ten times; from 24.8 s to 78.8 s only
ATRV went out (every 2–6 s), so the dashboard had no fresh PID data for 54 s.
From 80 s to ~145 s rpm, speed, ect and trans_temp were barely polled
(backed off; load and iat were), then full polling resumed without any
intervention and stayed clean to the end (≈13 requests/s, 140–370 s).

Interpretation (from this log; not yet reproduced on the bench):
- The recovery step is wrong for an ELM327. A bare CR means "repeat the last
  command", and the client treats the first `>` after it as the CR's answer,
  even when it is the timed-out request's own late prompt. One latency spike
  above 500 ms is enough to put replies out of step. The ESP32 firmware has
  the same step (`docs/esp32/OBD_PROTOCOL.md`, "Timeout → bare CR").
- Values were not mis-assigned across PIDs here: the positive-response echo
  check rejected mismatched replies (gateway: "speed: … Invalid ×1"), and a
  same-PID repeat carries that PID's own, one-cycle-old value.
- Why the latency spiked at 17.9 s is unknown (key on, engine off; Bluetooth?).
- Whether this is how the ESP32-era "frozen PID" started is a hypothesis for
  3.5.7, not shown.

Verdict: partial pass. The Pi drives the MX+ end to end: connect, init,
read-only polling at ≈13 requests/s, live values on the dashboard [TRUCK]. It
also shows a recovery bug that turns one slow reply into ~2 minutes of
degraded data. Not shown: a logged pairing transcript (3.5.2), recovery from a
real adapter freeze (H19), a drive.
Closes: nothing. 3.5.2 still needs the `bluetoothctl` transcript.
Follow-ups: fix the timeout recovery in `crates/elm` (and note it for the
ESP32); timestamps in gateway.log; `SuccessExitStatus=130` for the pi-start unit.
Update, same day: the recovery is fixed in `crates/elm` [SIM]. After a timeout
the client sends nothing and waits up to 1 s for the late prompt, then probes
with `ATI`. A test replays the 18294–18999 ms sequence above. Not yet run on the
truck. The ESP32 firmware still sends the bare CR (noted in
`docs/esp32/OBD_PROTOCOL.md`).

## 2026-11-02 — Second MX+ session, with the timeout-recovery fix: idle [TRUCK]

Same Pi, display and MX+, in the truck. Owner ran `make pi-start
TRANSPORT=obdlink TRANSMIT=1` at `d74f9af` (the ELM client waits for the late
prompt, then probes with `ATI`; no bare CR), 20:29:01–20:32:33 (3 min 32 s),
engine running at idle. No `obd-console` this time. Session:
`~/f250-data/20261102-202901-obdlink/` (`traffic/adapter-traffic.1.log`,
9 789 lines). Values below were decoded from the traffic log on the Mac
(SAE J1979 formulas; trans_temp with the registry's `((A*256)+B)/8` °F from
7E9), not read from the dashboard.

Result:
    connect    first try; ATZ answered in 881 ms ("ELM327 v1.4b"), init all OK
    gateway    gateway.log has only "listening on unix:/tmp/f250/vehicle.sock":
               no disconnect, no DEGRADED, no recovery
    timeouts   none. 2 488 request→prompt times: 51 under 50 ms, 2 010 at
               50–99 ms, 424 at 100–199 ms, 2 at 200–499 ms, none ≥ 500 ms;
               mean 82 ms. No bare CR, no ATI probe, no STOPPED
    throughput 222–258 requests per 20 s window (≈ 11–13/s) for all 210 s
    adapter    ATRV 13.8–13.9 V
    values     rpm 662.75–1281.50 (idle ≈ 690, one blip), speed 0, ect 54 °C
               throughout, iat 25 °C, load 7–46 %, baro 85 kPa,
               trans_temp 46.3–46.5 °C
    responders 7E8 and 7E9 both answer 010C: |difference| median 0.75 rpm,
               p95 3.75, max 58 (897 pairs). Run 1: median 0.25, p95 2.75

Same decode of the first session (19:50, `20261102-195005-obdlink`): rpm 0
until ≈ 215 s (key on, engine off), then ≈ 690 at idle, max 1084.75; ect
55 → 50 °C; iat 47 → 18 °C after the engine started; trans_temp 48.6–50.8 °C.

Verdict: pass for a clean session [TRUCK]: polling steady at ≈ 12 requests/s
for 3.5 min with no link events. It does **not** test the recovery fix: no
request timed out, so the new path never ran. That evidence needs a run where
a reply goes past 500 ms (longer sessions, a drive).
ECT reads flat at 54 °C for the whole run while being answered fresh
(different request each time), so this is not a transport freeze; whether
54 °C is right needs the cluster gauge or a scan tool beside it. ECT falling
55 → 50 °C at idle in the first session is unexplained (cold evening?), also
unchecked against the gauge.
Closes: nothing.

## 2026-11-02 — Dashboard Power button shuts the Pi down [BENCH]

Same Pi and display, indoors, simulator (transmits nothing). Pi at `eacb081`.
The owner started the dashboard (session `20261102-212819-sim`), tapped Power,
then Cancel, then Power and Shut down; the screen went dark. After the green
light stopped, they unplugged and replugged the Pi.

Result:
    offered    session.txt "power btn: offered": logind's CanPowerOff was "yes"
               in the kiosk session (polkit allow_active; no sudo, which needs a
               password on this Pi)
    shutdown   session.txt, in order: "power off: requested from the dashboard",
               then "stopped: 2026-11-02T21:28:47-07:00" (written by run.sh's
               ordered stop: app, recorder, gateway), then `systemctl poweroff`
    data       recorder export of a copy of the session database: 408 samples,
               32 events, last sample 26.9 s into the 28 s run; reads cleanly
    earlier    over SSH, `make pi-run` correctly said "No Power button" (no seat),
               then cage timed out; run.sh now refuses that case at once

Verdict: pass [BENCH, simulated data]. The button appears in a session that
owns the screen and runs the clean stop before powering off. Not shown from
logs: the OS shutdown itself (this Pi keeps no persistent journal and no
wtmp), only the owner seeing the screen go dark; how the run was started
(console or `make pi-start`) isn't recorded; Cancel was seen by the owner, not
logged; nothing in the truck yet.
Closes: the shutdown part of roadmap 3.5.3 on the bench.

## 2026-11-05 — USB CAN adapter: factory firmware is slcan [BENCH]

Jhoinrch RH-02 Pro plugged into the Pi 5 (Raspberry Pi OS, kernel
6.18.50+rpt-rpi-2712), Boot switch up, nothing on its terminals. The owner ran
`tools/pi/can.sh status`:

    No can0.
    slcan-looking serial ports:
      /dev/serial/by-id/usb-Openlight_Labs_CANable2_b158aa7_github.com_normaldotcom_canable2.git_206C34844546-if00
    Bus 001 Device 002: ID 16d0:117e MCS CANable2 b158aa7 github.com/normaldotcom/canable2.git

Result: the factory firmware is the CANable 2.0 **slcan** firmware,
normaldotcom/canable2-fw at commit `b158aa7` (its latest, 2022-07-07). This
settles the manual's contradiction.

Read from the firmware's source at that commit (not measured):

- `M1` (silent) sets `FDCAN_MODE_BUS_MONITORING` only while closed, and `O`
  (open, `can_enable()`) then sets `FDCAN_MODE_NORMAL` unconditionally. So the
  silent mode never takes effect.
- There is no `L` command (it falls to "invalid command"). `L` is what the
  kernel's slcan driver sends for `listen-only on`, and the firmware sends no
  ACK/NACK, so the kernel would not know it failed.

So with the factory firmware the adapter always ACKs frames on the bus, and the
listen-only first session (ADR-0007, ADR-0012) can't be done with it.

Mainline candleLight_fw doesn't support the STM32G431. Decision: flash
**Candlelight 2.5** (Elmue, MIT), which does, maps gs_usb listen-only to
bus-monitoring mode, and enumerates as `1d50:606f` for mainline `gs_usb`.
`tools/pi/can.sh flash` does it from a pinned commit (`12aa9fa`) with SHA-256
checks. Default build: "Multiboard" (internal RC oscillator, like the factory
firmware), because this unit shipped with old firmware and may predate the
25 MHz crystal its manual says RH-02 boards have "since 2026".

Also checked on the Pi [BENCH, adapter not flashed]: `can.sh flash` downloads
both builds and verifies their checksums, deletes a tampered file and refuses,
and stops when the adapter isn't in DFU mode; `can.sh listen` refuses with the
slcan firmware. `dfu-util` 0.11-3 is in the Pi's apt sources (now in
`make pi-setup`).

Closes: the factory-firmware question (compatibility matrix). Open: flashing
and `driver gs_usb` + `LISTEN-ONLY` on the bench.

## 2026-11-05 — USB CAN adapter flashed with Candlelight 2.5 [BENCH]

Same adapter and Pi, Pi at `5ca173a`. The owner ran `tools/pi/can.sh flash`
(default Multiboard build) with the Boot switch down, then switched it up and
replugged. The firmware file on the Pi (`~/f250-data/firmware/`) passed the
script's SHA-256 check. Kernel log and `lsusb -v` (read over SSH):

    20:00:08 usb 1-1: Product: DFU in FS Mode
    20:01:51 usb 1-1: New USB device found, idVendor=1d50, idProduct=606f, bcdDevice=26.10
    20:01:51 usb 1-1: Product: Candlelight 2.5 - Multiboard
    20:01:51 gs_usb 1-1:1.0: Configuring for 1 interfaces
    iManufacturer ElmueSoft (netcult.ch/elmue)

`tools/pi/can.sh status`:

    can0: driver gs_usb, state down
    can state STOPPED (berr-counter tx 0 rx 0) restart-ms 0
    gs_usb: tseg1 1..256 tseg2 1..128 sjw 1..128 brp 1..512 brp_inc 1
    gs_usb: dtseg1 1..32 dtseg2 1..16 dsjw 1..16 dbrp 1..32 dbrp_inc 1
    clock 160000000

Verdict: pass. The adapter enumerates as `can0` under mainline `gs_usb` with
no daemon; 160 MHz CAN clock; FD timing ranges present. Not yet shown:
listen-only (`can.sh listen`, needs sudo), the terminator readings, and any
frame on a bus.
Closes: flashing (roadmap 4.1).

## 2026-11-05 — USB CAN adapter: listen-only accepted [BENCH]

Same adapter (Candlelight 2.5 Multiboard), nothing on its terminals. The owner
ran `tools/pi/can.sh listen`:

    can0: <NOARP,UP,LOWER_UP,ECHO> ... state UP
    can <LISTEN-ONLY> state ERROR-ACTIVE (berr-counter tx 0 rx 0) restart-ms 0
    bitrate 500000 sample-point 0.875
    tq 12 prop-seg 69 phase-seg1 70 phase-seg2 20 sjw 10 brp 2
    clock 160000000
    bus-errors 0, error-warn 0, error-pass 0, bus-off 0; RX 0 packets, TX 0 packets

Verdict: pass for what a bench with no bus can show. The driver and firmware
accept listen-only at 500 kbit/s and the interface comes up error-active with
zero counters. Not shown: that the adapter really sends no ACKs. That needs a
second CAN node transmitting with the adapter as the only receiver (its frames
should then go unacknowledged); the firmware source maps listen-only to the
FDCAN's bus-monitoring mode, which is the evidence for now. The 87.5 % sample
point is the kernel's default for 500 kbit/s; the truck's own sample point is
unknown, and the listen-only capture's error counters will show whether it
matters.
Closes: listen-only on the bench (roadmap 4.1), except the no-ACK proof.
Open: the terminator readings and the breakout's continuity
([wiring sign-off](../wiring/dlc-can-adapter.md#sign-off)).

## 2026-11-05 — CAN adapter terminator and DLC breakout checks [BENCH]

Multimeter, adapter unplugged from everything. The owner confirmed:

- termination switch up: CAN H–CAN L does not read ≈ 120 Ω (terminator off)
- switch down: ≈ 120 Ω (terminator on); switch then left up
- the DLC breakout's continuity: plug pin 6, 14 and 5 to the wires that go to
  CAN H, CAN L and GND

Exact readings weren't recorded. Verdict: pass. Signed off in the
[wiring sheet](../wiring/dlc-can-adapter.md#sign-off).
Open (need the truck): DLC 6–14 ≈ 60 Ω with ignition off, adapter
disconnected and then connected; the 5V terminal left unconnected.

## 2026-11-06 — AGL 22.0.1 image as it comes, before deploy [BENCH]

Hardware: Raspberry Pi 5 Model B Rev 1.0, 8 GB. Ethernet. CAN adapter
unplugged. No HATs.
Image: AGL Vimba 22.0.1 `agl-ivi-demo-flutter-raspberrypi5`, flashed to SD,
first boot, nothing deployed.
Setup: on the Pi over SSH as root (agl.md §3 step 4):
`cat /etc/os-release; uname -r; cat /etc/default/flutter;
systemctl is-enabled systemd-networkd kuksa-can-provider can-dev-helper`

Result:
    ID=agl
    NAME="Automotive Grade Linux"
    VERSION="22.0.1 (vimba)"
    VERSION_ID=22.0.1
    VERSION_CODENAME="vimba"
    PRETTY_NAME="Automotive Grade Linux 22.0.1 (vimba)"
    CPE_NAME="cpe:/o:openembedded:agl:22.0.1"
    6.18.33-v8-16k
    FLUTTER_VERSION=3.38.3
    FLUTTER_RUNTIME=release
    LIBCAMERA_LOG_LEVELS=*:ERROR
    enabled          (systemd-networkd)
    enabled          (kuksa-can-provider)
    enabled          (can-dev-helper)

Verdict: works. The Pi 5 boots the 22.0.1 image and takes a root SSH login
over Ethernet. Release, kernel 6.18.33 and Flutter 3.38.3 match what the
manifest and our pins say, so `make deploy`'s engine check should pass. Both
KUKSA CAN units and systemd-networkd are enabled out of the box, as ADR-0015
expected from the source: masking them is the first thing `stage1-setup.sh`
does. The `-v8-16k` suffix is the kernel's local version (by its name, a
16 KB page-size build; not checked further). Not recorded: which hostname
reached the Pi, and what HDMI0 showed.
Closes: the "(on the image)" half of the systemd-networkd and demo CAN rows
in the compatibility matrix.

## 2026-11-06 — 7" panel dark under AGL: the overlay was on the wrong DSI port [BENCH]

Hardware: as in the previous entry, plus the original 7" display and the
22-way to 15-way cable, as on Raspberry Pi OS. CAN adapter unplugged.
Image: AGL 22.0.1 with Stage 1 deployed (`make deploy`, `--check` all ok),
`dtoverlay=vc4-kms-dsi-7inch` (no port parameter, so DSI1).
Read over SSH from the dev Mac.

Result, before the fix (owner: the panel stays dark after the reboot):
    card1 drm-rp1-dsi 1f00130000.dsi (DSI1), DSI-2 "connected", CRTC active
    with agl-compositor's 800x480 XR24 framebuffer; the dashboard renders
    (agl-screenshooter of DSI-2 shows the Home screen, simulated data)
    backlight 11-0045: brightness 255, bl_power 0
    edt_ft5x06 11-0038: touchscreen probe failed ... error -121
    I2C bus 11 = rp1/i2c@80000; bus 10 = rp1/i2c@88000 (DT aliases)

The backlight number proves nothing: the rpi-panel-attiny-regulator probe
(rpi-6.18.y) only writes registers and never reads one back, so it binds
with no panel on the bus. The touch controller's -121 (no ACK) shows nothing
is on DSI1's I2C. The Raspberry Pi OS entry's `dmesg` (2026-11-02) has
`1f00118000.dsi` and `edt_ft5x06 10-0038`: DSI0 and its bus.

Fix: `dtoverlay=vc4-kms-dsi-7inch,dsi0` in `agl/boot/config-f250.txt`,
installed with `stage1-setup.sh`, reboot. After:
    drm-rp1-dsi 1f00118000.dsi: Attach DSI device name=tc358762 ... lanes=1
    edt_ft5x06 10-0038 probes, no -121; input "10-0038 generic ft5x06 (79)"
    card1-DSI-1 connected; agl-compositor, f250-dashboard, -gateway and
    -recorder active; agl-screenshooter of DSI-1 shows the Home screen

Owner, after the fix: the dashboard shows on the panel and taps work.

Verdict: works. Under AGL 22.0.1 with Stage 1, the 7" panel on DSI0 shows
the dashboard fullscreen at 800x480 (flutter-auto, the compositor's
background surface, simulated data with the SIMULATED badge), and touch
works. Not shown: backlight dimming (check 4), the ribbon with a HAT fitted
(H3).
Closes: agl.md bring-up checks 1 (CAN safety, `--check`), 2 (display),
3 (touch), 5 (dashboard); H30.

## 2026-11-06 — Compositor abort after a deploy; the dashboard and compositor restart as a pair [BENCH]

Hardware and image as in the previous entry, Stage 1 deployed.

Owner: after a second `make deploy` (the obd-console fix), the panel is on but
black with a blinking cursor at the top (the text console).

Result:
    02:14:03  setup restarts f250-dashboard; the new flutter-auto logs
              "Wayland Dispatch Error: Connection reset by peer";
              agl-compositor: "code=dumped, status=6/ABRT"; no restart
              (the image's unit has no Restart=), so tty7 shows the console
    reproduced: `systemctl stop f250-dashboard` leaves the compositor running;
              `systemctl start f250-dashboard` then aborts it (core dump
              02:21:28). A second homescreen client per compositor run is
              what crashes it. Which assertion: unknown, no debug symbols

Fix (ADR-0016 addendum): the dashboard is BindsTo/PartOf/WantedBy the
compositor with no Restart= of its own, OnFailure= restarts the compositor,
the compositor gets Restart=on-failure (drop-in), and stage1-setup swaps
homescreen apps around a compositor restart. After deploying it:

    make deploy     setup restarts the pair; no new core dump; --check passes
                    (the drop-in and "agl-compositor.service running" are checked)
    kill -ABRT agl-compositor  02:23:39 dumped; 02:23:41 compositor and
                    dashboard started again (restart counter 1)
    kill -KILL flutter-auto    02:23:48 dashboard failed; OnFailure restarted
                    the compositor; 02:23:49 both running
    agl-screenshooter          the Home screen on DSI-1 afterwards

Verdict: works. A crash of either one, or a deploy, no longer leaves the
panel on the console. Not tested: a dashboard that crashes repeatedly (the
recover unit allows 5 restarts a minute, then stops).
Closes: nothing; check 7 (Power button) is still to do.

## 2026-11-06 — AGL bring-up checks 7, 8 and 9: Power button, CAN listen-only, RTC [BENCH]

Hardware and image as in the previous entry. USB CAN adapter (Candlelight
2.5, gs_usb) plugged in after `--check` passed; no CAN bus attached. No RTC
cell on J5.

Result:
    7 Power    The dashboard's Power button shut the Pi down (owner). The
               "power off: requested" journal line couldn't be read: the
               image's journal is volatile ("no persistent journal was found")
    8 CAN      f250-can status: can0, driver gs_usb, DOWN (nothing brought it
               up at boot). f250-can listen: <LISTEN-ONLY> ERROR-ACTIVE,
               500000 bit/s, sample point 0.875, berr-counter tx 0 rx 0,
               TX 0 packets
    9 RTC      rtc0 = rpi-rtc; dmesg "trickle charging enabled at 3000000uV"
               (our dtparam at the time); charging_voltage 3000000; at boot
               "setting system clock to 1970-01-01T00:00:08" (no cell, power
               was off); later hwclock -r and the system clock agree, synced
               from the network

Verdict: works, within what the bench shows. 7: the Power path powers off
(exit 42 → dashboard-stopped). 8: the AGL kernel and our override leave the
adapter down at boot and accept listen-only, as on Raspberry Pi OS; the
no-ACK proof still needs a second node. 9: the RTC and the charging
parameter work on AGL; holding time (H20) needs the cell. The charging line
is now commented until the rechargeable cell is fitted.
Closes: agl.md checks 7, 8 and 9 (H20 stays open).

## 2026-11-06 — Persistent journal on the AGL image [BENCH]

Hardware and image as in the previous entry.

Before: `journalctl -b -1` → "no persistent journal was found". `/var/log`
is a link to `volatile/log` on the `/var/volatile` tmpfs; journald has only
`RuntimeMaxUse=64M`. SELinux: disabled (`sestatus`).

Setup: `make deploy` with the journald drop-in (`Storage=persistent`,
`SystemMaxUse=50M`) and `var-volatile-log-journal.mount` (bind
`/var/lib/journal` → `/var/volatile/log/journal`, before
systemd-journal-flush). A `logger -t f250-test` marker, then a reboot.

Result:
    before reboot  findmnt: /dev/mmcblk0p2[/var/lib/journal] on
                   /var/volatile/log/journal; journal files under it;
                   --check: journal drop-in, mount enabled, mounted: ok
    after reboot   journalctl --list-boots: two boots; journalctl -b -1 shows
                   the marker and the shutdown through "Journal stopped";
                   the mount is back; compositor, dashboard, gateway and
                   recorder active
    unrelated      bthelper@hci0.service failed on this boot (Raspberry Pi
                   Bluetooth helper); not looked at yet

Verdict: works. Logs from before a reboot or a power-off can now be read.
Note the previous boot's first entry is dated 2026-10-27 (the image's build
time): no RTC cell, so early boot timestamps are wrong until network time.

## 2026-11-06 — AGL bring-up checks 4 and 6: backlight, gateway and recorder [BENCH]

Hardware and image as in the previous entry. Simulated data (TRANSPORT=sim).

Result:
    4 Backlight  The owner ran `echo 60 > /sys/class/backlight/10-0045/brightness`
                 and back to 255; no problem reported. Afterwards brightness,
                 actual_brightness 255, bl_power 0. systemd-backlight@backlight:10-0045
                 saves and restores the level across boots
    6 Gateway    f250-gateway and f250-recorder active. obd-console (no
                 options, finds /run/f250/vehicle.sock) lists the signals
                 with live simulated values (seen earlier the same day).
                 /var/lib/f250/: telemetry.sqlite 7.7 MB, -wal 4.3 MB,
                 f250:f250 0640, updated 02:40 (the recorder writes).
                 No sqlite3 on the image to count rows

Verdict: works. Check 6: the gateway serves the API on the AGL socket and
the recorder writes to the SD card. Check 4: the sysfs path takes writes; the
dimming itself was reported by the owner, not measured. Note for Phase 6.7
dimming: systemd-backlight restores the last level at boot, so a level the
dashboard sets at night comes back on the next start.
Closes: agl.md checks 4 and 6. With 1, 2, 3, 5, 7, 8 and 9 earlier today,
every bring-up check that needs no extra hardware passes; 10 (DAC8x) and
11 (NVMe) wait for the HATs.

## 2026-11-06 — systemd watchdog for the gateway and recorder on AGL [BENCH]

Hardware and image as in the previous entry. Simulated data (TRANSPORT=sim).
Setup: `make deploy` with `crates/sd-notify`: both units `Type=notify`,
`WatchdogSec=60` (gateway) and `30` (recorder). Then, over SSH,
`kill -STOP` on the gateway's main PID to freeze it, polling `systemctl show`
every 5 s. Times are the Pi's journal (UTC).

Result:
    after deploy  both Type=notify, active; StatusText "listening on
                  unix:/run/f250/vehicle.sock" and "session 9, recording from
                  unix:/run/f250/vehicle.sock"; WatchdogUSec 1min / 30s;
                  WatchdogTimestamp advancing; --check: all passed
    02:53:32      kill -STOP 1283 (gateway)
    02:53:41      recorder: "no snapshot from the gateway in 10 s; reconnecting"
    02:53:48–54:23 recorder: "the gateway did not start the snapshot stream",
                  every 7 s (5 s timeout + 2 s pause); still running
    02:54:27      systemd: "f250-gateway.service: Watchdog timeout (limit 1min)!",
                  SIGABRT, core dumped, "Failed with result 'watchdog'"
    02:54:29      restart counter 1; new gateway 1626 READY; the recorder is
                  stopped and started with it (Requires=), session 10
    02:55:22      agl-screenshooter: Home screen, "Link up · 49 s", simulated
                  values; the dashboard reconnected by itself

Verdict: works. A frozen gateway is killed and restarted by systemd within
WatchdogSec, and the dashboard and recorder recover without help. While the
gateway was frozen the recorder kept looping on its bounded waits instead of
hanging. What this does not show: the progress gate itself (a gateway whose
watchdog task runs while its control loop is stuck); SIGSTOP freezes both.
That logic is covered by tests `[SIM]` (`crates/sd-notify`). Each watchdog
kill leaves a core dump (`coredumpctl list`); systemd-coredump's limits apply.

## 2026-11-06 — `make logs` against the AGL Pi [BENCH]

Hardware and image as in the previous entry, right after the watchdog test.
Setup: `make logs PI=raspberrypi5.local` from the dev Mac.

Result:
    build/logs/f250-logs-raspberrypi5-20261107-025718.tar.gz, 34 KB:
    journals (f250-gateway, -recorder, -dashboard, agl-compositor, the masked
    KUKSA units, networkd, logind; two boots), kernel logs of both boots,
    setup-check.txt (--check, all ok), services.txt (systemctl status),
    can.txt (can0 DOWN, gs_usb, STOPPED), recorder.txt (telemetry.sqlite
    9.3 MB, f250:f250), storage.txt, system.txt, /etc/default/f250.
    journal-f250-gateway.txt has the watchdog kill from the previous entry

Verdict: works. The collection script runs on the AGL image and the archive
comes back with every section filled. Nothing on the Pi was changed.

## 2026-11-07 — First AGL source build in the build VM stops at task 9,758 [BENCH]

Hardware: the dev Mac (Apple Silicon); the `agl-build` Lima VM (Ubuntu 24.04
aarch64, 12 CPUs, 32 GiB RAM) with its disk on the External drive, which is a
Seagate ST9500325AS, a 5,400 rpm 500 GB laptop hard disk on USB.
Image: AGL 22.0.1 `agl-ivi-demo-flutter`, `raspberrypi5`, from source, at commit 47b7a2f.
Setup: `make agl-build`, started 2026-11-06 22:23.

Result:
    Sstate summary: Wanted 7098 ... Missed 7098 (from scratch)
    07:01  "Timeout while waiting for a reply from the bitbake server (60s)"
           at task 9,758 of 13,261. No ERROR lines; 4 warnings
           (shared sstate, a hash-equivalence timeout in ncurses, two QA notes)
    sar, 22:30–07:00: %iowait 20–80 % (about 52 % average after midnight);
           vda 86–96 % busy at 80–110 operations/s, await 90–330 ms
    06:56–07:13: Ubuntu's unattended-upgrades upgraded 14 packages in the VM
    No out-of-memory kills, swap almost unused. Disk used: 116 GB
    (downloads 41 GB, sstate-cache 9.8 GB)

    Resumed 09:36 (same tree): "Sstate summary: Wanted 2391 Local 502
    Missed 1889 Current 4707 (73% complete)"

Verdict: partial. The aarch64 build host gets through three quarters of a
from-scratch build with no build errors, so the host itself is not the
problem so far. The disk is the bottleneck. The BitBake client gave up when
its server stopped answering, and that happened while the automatic upgrades
added load to an already saturated disk; the timing points to that, but it is
not proven. Since then `setup-build-host.sh` turns off automatic apt updates.
Still unknown: whether the remaining 27 % (the Flutter engine and image
assembly among it) builds on aarch64, and whether the image boots.

## 2026-11-06 — CAN adapter on the truck: DLC resistance and first listen-only capture [TRUCK]

The owner measured DLC pins 6–14 with the ignition off and the adapter
disconnected: **≈ 62 Ω**, the two HS-CAN terminators in parallel (expected
≈ 60 Ω). Then connected the adapter through the DLC breakout (switch up, per
the bench check) and ran `tools/pi/can.sh listen` and `tools/pi/can.sh capture
120` (Pi still at `5ca173a`; session `20261106-090751-candump`).

Result: 85 390 frames in 120 s (712/s), 14 IDs, all 11-bit; no error frames;
error-active before and after with every error counter at 0; no gap over
50 ms. Census and analysis: [CAN_CENSUS.md](../diagnostics/CAN_CENSUS.md).

Verdict: pass. 500 kbit/s is right, and the adapter, breakout and listen-only
setup work on the truck. The truck's state wasn't recorded; the data looks
like key on, engine off.
Closes: the DLC resistance check with the adapter disconnected.
Open: the 6–14 reading with the adapter connected (a clean capture says the
bus is healthy but doesn't prove the adapter's terminator is off); the 5V
terminal check.

## 2026-11-07 — CAN adapter on the truck: idle and drive captures, one dropout [TRUCK]

The owner confirmed DLC 6–14 still reads ≈ 60 Ω with the adapter connected
(switch up). Two listen-only captures: idle with turn signals and two P→R→P
cycles (`20261107-113429-candump`, 242 s), then a drive
(`20261107-113837-candump`, 120 s). Analysis:
[CAN_CENSUS.md](../diagnostics/CAN_CENSUS.md).

Result: no error frames and every error counter at 0 in both. The drive has
no gap over 20 ms. **The idle capture has a 122 s silence** (+105.0 s to
+227.4 s): no frames in the log, and the kernel's RX count agrees. The bus
values on both sides of it are the same steady idle, so the truck didn't go
quiet; the interface wasn't reset and reported no error state. Cause unknown:
adapter or USB stall, or a wiring contact. The Pi's journal is volatile and
the Pi was powered off after the drive, so no kernel log survived.

Verdict: the adapter path works on the truck, but it can drop out silently.
`tools/pi/can.sh capture` now saves `kernel.log` (kernel messages during the
capture), `counters.log` (RX counts and CAN state every 5 s) and a gap
report in `session.txt`, and warns when frames stopped. Tested piecewise on
the Pi; not yet in a real capture.
Closes: the DLC 6–14 check with the adapter connected.
Open: the cause of the dropout; the 5V terminal check.

## 2026-11-07 — Correction: the CAN "dropouts" were wall-clock jumps [TRUCK]

The 122 s "silence" in the idle capture (entry above) was not a dropout.
Session `20261107-131852-obdlink` (MX+ polling, `CAPTURE=1`) showed the same
thing, a 391.6 s gap in the frame times, while the capture's `counters.log`
jumped from 13:19:02 straight to 13:25:39 with only about 5 s of frames
counted in between. Nothing stopped: the Pi's wall clock jumped forward, and
candump stamps frames with the wall clock. The idle capture likewise holds
exactly 120 s of frames, the length `capture 120` records.

Why the clock jumps, from this boot's journal:

    rpi-rtc: setting system clock to 1970-01-01T00:00:09 UTC (9)
    systemd: System time advanced to timestamp on /var/lib/systemd/timesync/clock: 13:28:41
    systemd-timesyncd: Initial clock synchronization to 13:32:09

`/sys/class/rtc/rtc0/battery_voltage` reads 0 and `charging_voltage` 0: no
working RTC battery, charging not enabled. So each boot starts at the last
shutdown time, and the clock jumps forward by however long the Pi was off
when NTP answers (here, on home Wi-Fi in the driveway). Away from Wi-Fi the
clock stays behind for the whole drive.

Verdict: the adapter, USB and wiring path have not lost frames in any
capture. `can.sh capture` now records the uptime in `counters.log` and
compares the wall clock with the monotonic clock at the end, so a jump is
labelled as one. Fix for the clock itself: the RTC battery and
`dtparam=rtc_bbat_vchg=3000000` ([Clock](../setup/raspberry-pi.md#clock),
H20).
Closes: the "unexplained dropout" from the entry above.

## 2026-11-07 — First AGL source build completes in the build VM [BENCH]

Hardware: as in the previous entry (the `agl-build` VM on the 5,400 rpm External drive).
Image: AGL 22.0.1 `agl-ivi-demo-flutter`, `raspberrypi5`, from source, at commit f0ca844.
Setup: after the stop in the previous entry, `make agl-build` again. The
Flutter engine's fetch had been cut off at 07:01 and its half-made checkout
made the retry fail ("remote origin already exists"); deleting
`tmp/work/aarch64-agl-linux/flutter-engine/3.38.3/sources/gn` let it fetch again.

Result:
    09:51  Sstate summary: Wanted 2130 Local 251 Missed 1879 Current 4968 (73% complete)
    14:01  Tasks Summary: Attempted 13261 tasks of which 9790 didn't need to be
           rerun and all succeeded. 1 warning (hash-equivalence database inside
           the build directory; now set beside sstate)
           bitbake exit 0 after 247 min
    BitBake time over both runs: about 12 h 45 min (8 h 38 min + 4 h 7 min)
    agl-ivi-demo-flutter-raspberrypi5.rootfs-20261107165116.wic.zst, 620 MB,
      sha256 20733e4691a58963f120a9a1077b04785b47b19a2d1433ad8417677a3ce771ed,
      with .wic.bmap and .manifest, copied to /Volumes/External/agl-images/
    Manifest: kernel 6.18.33-v8-16k, flutter-engine 3.38.3, agl-compositor
      0.0.24, flutter-ics-homescreen (the same kernel and Flutter as the
      prebuilt image in the 2026-11-06 entry)
    Disk at the end: VM 116 GB used (downloads 49 GB, sstate-cache 15 GB);
      the VM's disk file on External 103 GB. Peak during the build not measured

Verdict: works, for the build. An aarch64 Ubuntu VM on the Mac builds AGL
22.0.1 for the Pi 5 from source, Flutter engine included. Not shown: that the
image boots, or that it behaves like the prebuilt image. The next step is to
flash it to a spare card and run the agl.md bring-up checks.

## 2026-11-07 — CAN adapter in active mode on the truck (session B) [TRUCK]

The owner confirmed the adapter's 5V terminal is unconnected (the last row of
the [wiring sign-off](../wiring/dlc-can-adapter.md#sign-off)), unplugged the
MX+, switched `can0` to normal mode (`can.sh active`) and ran the gateway over
it (session `20261107-143822-can`, 97 s idle).

Result: 1672 frames transmitted, TX errors 0, bus errors 0, error-active with
both error counters at 0 from start to stop; 74 013 frames received (762/s,
the broadcasts plus the answers), no silence, no clock jump. Signal results:
[VERIFICATION_LOG](../diagnostics/VERIFICATION_LOG.md).

Also in the capture's `kernel.log`: `hwmon hwmon2: Voltage normalised` at
14:38:25, three seconds after the start: the Pi's supply had dipped below its
undervoltage threshold just before. The Pi rebooted before it could be checked
(`vcgencmd get_throttled` was 0 on the next boot). The temporary truck power
(roadmap 3.5.3) needs watching; next time run `vcgencmd get_throttled` before
powering off.

Verdict: pass. The adapter transmits on the truck cleanly. The wiring
sign-off is complete.
Closes: the 5V terminal check; active mode on the truck.

## 2026-11-07 — The source-built AGL image boots on the Pi and runs Stage 1 [BENCH]

Hardware: the bench Pi 5 and 7" DSI panel, on the SD card the prebuilt demo
image had been on (that card was re-flashed).
Image: `agl-f250-source-22.0.1-20261107.wic`, the image from the previous
build entry decompressed with `zstd -d` (3,037,933,568 bytes, as in its `.bmap`).
Setup: flashed from the Mac; `ssh root@raspberrypi5.local` (empty root password,
from `agl-devel`); key installed; `make deploy PI=raspberrypi5.local`; reboot.

Result:
    first boot     joins the network as raspberrypi5.local; kernel
                   6.18.33-v8-16k; os-release "Automotive Grade Linux 22.0.1 (vimba)"
    ssh-copy-id    hangs: its probe login succeeds with no password and waits
                   at a shell. Ctrl-C, then append the key by hand (agl.md)
    make deploy    ran through all seven stage1-setup.sh steps, no errors
    after reboot   systemd-analyze: 0.86 s kernel + 9.8 s userspace;
                   stage1-setup.sh --check: all checks passed (0 warnings)
    check 1        both KUKSA CAN units masked, networkd override, can0 absent
    check 2        card1-DSI-1 connected; agl-compositor active; the dashboard
                   loaded its AOT at 800×480 fullscreen; the owner sees the
                   dashboard on the panel
    check 3        "generic ft5x06" touch input present; the owner tapped the
                   nav bar and it responds
    check 4        backlight max_brightness 255
    check 6        gateway (sim, drive_cycle) and recorder active; obd-console
                   pids: eot 93.16 degC, trans_temp 58.65 degC, eot_ect_delta
                   5.17 degC Valid; recorder session 2 writing telemetry.sqlite
    check 7        dashboard Power: the Pi powered off; on the next boot
                   journalctl -b -1 shows "power off: requested from the
                   dashboard" at 02:37:53 and "Journal stopped" at 02:37:56
    unrelated      bthelper@hci0.service failed: "Can't init device hci0:
                   Operation not possible due to RF-kill". Also failed on the
                   prebuilt image (2026-11-06, persistent journal entry); not looked at yet

Verdict: works. The image built in the aarch64 VM boots and behaves like the
prebuilt 22.0.1 image for Stage 1. The VM stays the build host (ADR-0004).
Still to do on this card: check 8 (CAN listen-only), when the adapter is back.

## 2026-11-08 — The agl-f250 image (meta-f250) boots and passes Stage 1's check [BENCH]

Hardware: the bench Pi 5 and 7" DSI panel; the USB CAN adapter (gs_usb,
`1d50:606f`) was plugged in, not connected to any bus.
Image: `agl-f250-22.0.1-f16fc60.wic`, built in the build VM (now in
`~/agl-build-vm` on the Mac's SSD) from commit f16fc60 with `make agl-build`,
2,901,618,688 bytes, sha256 `486c3990…14ce90`. Before flashing, the image was
mounted read-only in the VM: `/etc/f250-release`, the five tools in
`/opt/f250/bin`, the `config.txt` block, the dashboard bundle, IDs 950, the
masks, the `00-f250.preset`, the wants links and `libsqlite3.so.0` all present.
Setup: flashed from the Mac; key installed by hand; **no `make deploy`**:
everything checked below came from the image.

Build fixes on the way (all [SIM] in `make agl-test`, then this build):
`CLEANBROKEN` (the repo's Makefile has no `clean`), `DEPENDS += "sqlite3"` (the
cargo class unbundles rusqlite), and the disable preset (`preset-all` fails on
a masked unit that a package presets enabled).

Result:
    first boot     raspberrypi5.local; os-release "Automotive Grade Linux 22.0.1
                   (vimba)"; kernel 6.18.33-v8-16k; /etc/f250-release
                   F250_SRCREV=f16fc60…; rpm: f250-system, f250-services and
                   f250-dashboard 0.1+git0+f16fc60bd0-r0
    boot time      systemd-analyze: 0.82 s kernel + 11.1 s userspace
    --check        /opt/f250/share/agl/scripts/stage1-setup.sh --check: all
                   checks passed (0 warnings)
    check 1        both KUKSA CAN units masked (is-enabled: masked), networkd
                   override present; can0 (the adapter) present, STOPPED, down
    check 2        card1-DSI-1 connected; agl-compositor active; the dashboard
                   loaded its AOT at 800 x 480 fullscreen; the owner sees the
                   dashboard on the panel
    check 3        ft5x06 touch input present; the owner confirms touch works
    check 6        gateway (sim, drive_cycle), recorder and dashboard active;
                   /run/f250/vehicle.sock f250:f250 0770; agl-driver in group
                   f250 (950); recorder session 1 writing telemetry.sqlite
                   (linked against the image's libsqlite3 3.51.3);
                   obd-console pids: eot 93.86 degC, ect 88.43 degC, trans_temp
                   61.03 degC, boost 32.98 kPa
    check 7        dashboard Power: the Pi powered off; on the next boot
                   journalctl -b -1 shows "power off: requested from the
                   dashboard" (dashboard-stopped) at 05:56:50 and "Journal
                   stopped" at 05:56:53, so the persistent journal works too
    failed units   none (bthelper@hci0 active this time; it failed on RF-kill
                   on the 2026-11-07 card)
    clock          journal times read Oct 27 until NTP synced (the image's
                   build-time clock floor); NTPSynchronized=yes by 05:50 UTC

Observed: EOT − ECT read STALE in four of five samples, VALID 5.38 degC in one.
`stats`: 15.8 requests/s; EOT and ECT were each read 41 times in 128 s (about
every 3 s, not their 500 ms), so the two inputs were often more than the
delta's 2 s skew limit apart. The scheduler stretching low priorities is the
known issue in [gateway.md](../setup/gateway.md#poll-intervals-and-the-throughput-budget);
nothing about the image.

Verdict: works. The image built from the layer gives the same head unit as
the prebuilt image plus Stage 1, with no sideload.
Still to do on this card: check 8 (CAN listen-only with the adapter on a bus).

## 2026-11-08 — The trimmed agl-f250 development image passes the bench checks; units sandboxed [BENCH]

Hardware: the bench Pi 5 and 7" DSI panel; the USB CAN adapter (gs_usb,
`1d50:606f`) plugged in, not on any bus. Ethernet.
Image: `agl-f250-22.0.1-33d8324.wic` (ADR-0021: AGL's compositor image plus
the head unit, no demo), built in the build VM from commit 33d8324,
1,718,406,144 bytes, sha256 `6a5b9b1b…4c01c0`. Flashed from the Mac; root's
key came from the image (`F250_AUTHORIZED_KEYS`), nothing installed by hand,
no `make deploy`.

Result:
    first boot     on the network about 55 s after power-on;
                   `ssh root@raspberrypi5.local` with the built-in key;
                   /etc/f250-release F250_SRCREV=33d8324…; rpm: f250-system,
                   f250-services, f250-dashboard 0.1+git0+33d8324979-r0
    boot time      systemd-analyze: 0.77 s kernel + 8.3 s userspace
                   (11.1 s userspace on the demo-based f16fc60 image)
    --check        all checks passed (0 warnings); flutter-ics-homescreen
                   "not installed"
    services       f250-gateway, f250-recorder, f250-dashboard,
                   agl-compositor, avahi-daemon, connman, bluetooth active;
                   ofono inactive and disabled; no failed units;
                   graphical.target
    CAN            gs_usb loaded; can-raw and can-isotp present as modules;
                   can0 STOPPED, down
    gateway        sim (drive_cycle); obd-console pids all Valid
    disk           / 785 MB used of 1.4 GB
    Bluetooth      hci0 present, but **Powered: no**: connman's settings have
                   `[Bluetooth] Enable=false` and the controller is rfkill
                   soft-blocked (bthelper: "Failed to set power on"). The MX+
                   over RFCOMM would need it on; not fixed here (ADR-0021).

Sandbox (ADR-0021 §10). Tried first as runtime drop-ins in
`/run/systemd/system`, then the edited unit files copied over the image's in
`/etc/systemd/system` (`systemd-analyze verify`: clean), all four services
restarted. After 75 s: all active, NRestarts 0 (past both watchdogs), no
errors in their journals, obd-console still reading live values.

    systemd-analyze security    before   after
    f250-gateway                 6.8      1.6
    f250-recorder                5.3      0.2
    f250-dashboard               9.2      0.6

With the sandbox on, the owner confirms: the gauges move on the panel, touch
works, and the dashboard's Power button turned the Pi off (it then stopped
answering on the network).

Not covered: the gateway's sandbox with the `obdlink` (serial, RFCOMM, TCP)
and `can` transports; only the simulator ran.

Verdict: works. The trimmed development image replaces the demo-based one on
the bench. The sandboxed units go into the next build.
Still to do: boot `agl-f250-release` (key-only SSH, password refused); CAN
check 8.

## 2026-11-08 — The agl-f250-release image boots; root by key only [BENCH]

Hardware: as above. Image: `agl-f250-release-22.0.1-33d8324.wic` (ADR-0021),
1,085,904,896 bytes, sha256 `61c45d8e…8cd5e5`. Built from the same commit as
the development image above, so **without** the 759f807 sandboxes. Flashed by
the owner; nothing installed by hand.

Result:
    login          `ssh root@raspberrypi5.local` with the built-in key: works
    passwords      /etc/shadow: no account has a usable password (root `*`).
                   sshd -T: permitrootlogin prohibit-password,
                   permitemptypasswords no. An empty-password login with no
                   key is refused for root, agl-driver and f250 ("Permission
                   denied (publickey,password)")
    --check        all checks passed (0 warnings)
    services       f250-gateway, f250-recorder, f250-dashboard,
                   agl-compositor, avahi-daemon, bluetooth active; ofono
                   inactive; no failed units
    tools          absent: gdb, strace, perf, screen, mc, rpm, opkg, dnf,
                   systemd-analyze. Present: candump, lsusb, blkid, mkfs.ext4,
                   rsync
    disk           / 525 MB used of 851 MB

`systemd-analyze` isn't on the release image, so exposure scores are measured
on the development image; the units are the same files.

Verdict: works. The release image locks root to the built-in key.
Still to do: boot `agl-f250-release-22.0.1-759f807.wic` (the sandboxed
units) and check its services run.

## 2026-11-08 — Sandboxed release image (759f807): no dashboard on a fresh card; fixed [BENCH]

Image: `agl-f250-release-22.0.1-759f807.wic`, flashed by the owner. The
panel stayed empty.

    cause          flutter-auto aborted (SIGABRT, core dump) at start:
                   "filesystem error: in create_directories: Read-only file
                   system [/home/agl-driver/.flutter-auto]". ProtectHome=
                   read-only allowed writes only to ~/.cache and
                   ~/.flutter-auto, and only if they already existed; on a
                   fresh card ~/.flutter-auto doesn't. Three crashes, then
                   agl-compositor hit its start limit, so the panel stayed empty.
    missed because on the development image the directory was already there
                   from earlier runs without the sandbox.
    tried          ProtectHome=yes with private directories: "Failed to
                   connect to Wayland display. Permission denied" (it also
                   hides /run/user).
    fix            StateDirectory= and CacheDirectory= f250-dashboard (systemd
                   creates them, owned by agl-driver, 0700),
                   HOME=/var/lib/f250-dashboard,
                   XDG_CACHE_HOME=/var/cache/f250-dashboard; home read-only,
                   nothing written there.
    test           the fixed unit copied to /etc/systemd/system, both
                   directories deleted, reboot: compositor and dashboard
                   active, no restarts; flutter-auto, Mesa's shader cache,
                   fontconfig and GStreamer write only in the new
                   directories; --check passes. bthelper@hci0 failed this
                   boot (rfkill; see the Bluetooth note above).
    owner          with the fixed unit on the 759f807 release card: the
                   dashboard shows on the panel, touch works, and Power turns
                   the Pi off.

Verdict: works. The sandboxed release image needs the fixed unit, so 0233cca
is the release image for the truck (`agl-f250-release-22.0.1-0233cca.wic`).

## 2026-11-08 — Gateway's CAN transport inside its sandbox, on vcan [BENCH]

Card: the 759f807 release card with the fixed dashboard unit. Every file
from `agl/rootfs/` matches 0233cca, and the binaries are the same (0233cca
changed only the dashboard unit). The Pi's USB CAN adapter was plugged in,
but not used: the test ran on a virtual interface, so nothing went on a bus.

    setup          modprobe vcan; ip link add vcan0 type vcan; up.
                   /etc/default/f250: TRANSPORT=can TRANSMIT=1 CAN_IF=vcan0
                   ENABLE=eot; systemctl restart f250-gateway
    transmit       requests on 7DF at the scheduled rate (candump); no
                   system-call or address-family denial, NRestarts=0. With
                   nothing answering: SUSPECT → BACKOFF → QUARANTINED and
                   link DEGRADED ⇄ RECOVERING_SOFT, as designed.
    receive        a shell responder (candump | cansend) answered SAE 01 0C
                   and 01 05 from 7E8 with arbitrary values. Both PIDs stayed
                   ACTIVE at ~4 Hz; the traffic log in /var/lib/f250/traffic
                   records each TX/RX pair.
    reverted       /etc/default/f250 restored (TRANSPORT=sim), vcan0 deleted.

Verdict: the gateway's sandbox allows the SocketCAN transport. Not tested:
`f250-can active` on a real `can0` with the sandboxed gateway (the truck
drive will be the first), the obdlink serial and RFCOMM transports.

## 2026-11-08 — Wi-Fi never comes up after boot on AGL: connman loses wlan0; patched [BENCH]

Same card. `connmanctl enable wifi` worked, but `connmanctl scan wifi`
answered "Not implemented" and `connmanctl services` listed only Ethernet.
The radio is fine: brcmfmac loads firmware 7.45.265, rfkill shows wlan
unblocked, wpa_supplicant runs.

    symptom        connman logs lo, eth0 and can0 at start, never wlan0.
                   `ip link set wlan0 down; up` makes it appear ("Adding
                   interface wlan0 [ wifi ]"), and the scan then lists the
                   nearby networks. After a reboot, with WiFi Enable=true in
                   /var/lib/connman/settings, it is missing again.
    cause          connmand -n -d: the startup link dump returns three
                   NEWLINK messages (lo, eth0, can0: 1468 + 1528 + 1008
                   bytes) and DONE; wlan0 only arrives later as an event.
                   connman 2.0's netlink_event() (src/rtnl.c) reads into
                   `unsigned char buf[4096]` and ignores truncation. This
                   kernel has CONFIG_PAGE_SIZE_16KB=y, so NLMSG_GOODSIZE is
                   8 KiB less overhead and a dump packs more than 4096 bytes
                   into one message: wlan0's record was cut off. (Kernel
                   source of this build: include/linux/netlink.h,
                   net/netlink/af_netlink.c.)
    not the cause  systemd-networkd lists wlan0 as unmanaged; connman's
                   NetworkInterfaceBlacklist doesn't match it.
    fix            meta-f250 patches connman to read 32768 bytes, the most
                   the kernel puts in one message
                   (recipes-connectivity/connman). Both images need a
                   rebuild.

Verdict: on 759f807/0233cca, Wi-Fi works only after something toggles wlan0,
so the Pi can't join a phone hotspot on its own.

## 2026-11-08 — Release image e82719f: connman sees wlan0 at boot [BENCH]

Image: `agl-f250-release-22.0.1-e82719f.wic` (sha `e01ec7ec812ab724…`),
flashed by the owner, booted on Ethernet. `/etc/f250-release`: e82719f.

    boot           gateway, recorder, dashboard active. connman's log:
                   "wlan0 {create}", "Adding interface wlan0 [ wifi ]" at
                   start, with nothing toggling the link.
    scan           connmanctl enable wifi; scan wifi: "Scan completed",
                   the nearby networks listed.

Verdict: the connman patch works. Not yet tested: joining the phone hotspot,
and rejoining it after a reboot without Ethernet.

## 2026-11-08 — Release image 7f9fa37: root fills the card on the first boot [BENCH]

Image: `agl-f250-release-22.0.1-7f9fa37.wic` (sha `bb9da0e574ddef93…`),
flashed by the owner to the 7.3 GB bench card (15333376 sectors).
`/etc/f250-release`: 7f9fa37. Checked over SSH as root ([ADR-0022](../architecture/adr/0022-grow-root-on-first-boot.md)).

    first boot     f250-grow-root: "/ is /dev/mmcblk0p2, partition 2 of
                   /dev/mmcblk0: 899 MiB, 6451 MiB after it". sfdisk moved
                   p2's end from sector 2120907 to 15333375 (start 278528
                   unchanged, p1 untouched); its own re-read failed ("Device
                   or resource busy"), as in the loop test, and partx gave
                   the kernel the new size. systemd-growfs: "Successfully
                   resized "/" to 7.1G bytes". About 2 s in all.
                   lsblk: mmcblk0p2 7.2G. df -h /: 7.0G, 527M used, 6.2G
                   free (was 851M with about 250M free on e82719f).
                   gateway, recorder, dashboard active; stage1-setup.sh
                   --check: all checks passed (0 warnings).
    second boot    after `systemctl reboot`: "7351 MiB, 0 MiB after it",
                   no table write (sfdisk -d identical before and after),
                   growfs a no-op; df -h / unchanged; all services active.

Verdict: works on the Pi. At ~120 MB an hour, a candump capture now has
about 50 hours of room. The card has a new SSH host key (re-flashed).
