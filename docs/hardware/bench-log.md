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
