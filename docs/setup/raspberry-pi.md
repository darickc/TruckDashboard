# Raspberry Pi OS for the MX+ trial

How to run the head-unit stack on the Pi 5 under Raspberry Pi OS for the
[Phase 3.5 trial](../PROJECT_PLAN.md#phase-35--mx-truck-trial-nothing-to-buy-hw-human).
This is a temporary setup. AGL replaces it in Phase 5.

Status:

- **On the Pi, without a display** `[BENCH]`, 2026-11-01
  ([bench-log](../hardware/bench-log.md)):
  - `make pi-setup` and `make pi-build` work on Raspberry Pi OS Lite (trixie).
  - The whole stack runs with `UI=headless`, and with `UI=0`.
  - The MX+ transport stays PASSIVE_ONLY without `TRANSMIT=1`.
- **On the original 7" display** `[BENCH]`, 2026-11-02: DSI1, stock
  `config.txt` (no overlay), HAT not fitted. `make pi-run` started on the Pi
  fills the screen under `cage`, and touch works.
- **Doesn't work yet:** `make pi-run` started over SSH. An SSH login has no seat,
  so `cage` times out after 10 s ("Timeout waiting session to become active").
  Start it from the Pi's own console, and stop it from SSH with
  `pkill -TERM -f '^bash tools/pi/run.sh'`.
- **Not tested yet:**
  - the ribbon with the CarPiHAT fitted (H3)
  - Bluetooth to the MX+, and anything on the truck

## 1. Install (once)

On the Pi, with 64-bit Raspberry Pi OS and a network connection. The truck's
Pi runs **Raspberry Pi OS Lite**, which has no desktop. The app runs fullscreen
under the [cage](https://github.com/cage-kiosk/cage) kiosk compositor instead,
which is closer to the finished head unit: one app, no desktop.

```bash
git clone https://github.com/darickc/TruckDashboard.git && cd TruckDashboard
git switch feat/agl-pivot     # until the branch is merged
make pi-setup
```

`make pi-setup` runs [tools/pi/setup-raspios.sh](../../tools/pi/setup-raspios.sh).
It installs:

- the apt packages: build tools, `protoc`, `libdbus-1-dev` for RFCOMM, and
  Flutter's Linux desktop packages
- `cage` (kiosk compositor) and `grim` (screenshots)
- a udev rule, [90-f250-kiosk-input.rules](../../tools/pi/udev/90-f250-kiosk-input.rules),
  so that `cage` draws no mouse cursor (see [No mouse cursor](#no-mouse-cursor))
- the Rust toolchain pinned in `rust-toolchain.toml`, using rustup
- Flutter 3.38.3 from `.fvmrc`, using fvm

It is safe to re-run. It only checks BlueZ, which ships with the OS.

### No mouse cursor

`cage` draws a cursor whenever any input device can act as a pointer. Two kinds
did on the bench Pi (2026-11-02, [bench-log](../hardware/bench-log.md)):

- The HDMI-CEC remote inputs `vc4-hdmi-0` and `vc4-hdmi-1`. They exist with
  nothing plugged in, so they would show a cursor in the truck too. The udev
  rule tells libinput to ignore them. Restart `make pi-run` after `make pi-setup`.
- A keyboard's extra USB interfaces. The ROCCAT Suora has a "Mouse" and a
  "Consumer Control" interface that both count as pointers. The rule leaves
  these alone, so the cursor stays while such a keyboard is plugged in. The
  truck has no keyboard.

To see which devices are pointers:

```bash
sudo libinput list-devices | grep -E '^Device:|^Capabilities:'
```

Checked on the Pi `[BENCH]`, 2026-11-02: after `make pi-setup`, `vc4-hdmi-0`
and `vc4-hdmi-1` are gone, and with the keyboard unplugged there is no cursor.

## 2. Build

```bash
make pi-build
```

This release-builds four things:

- the gateway, with the `rfcomm` feature
- the recorder
- `obd-console`
- the Linux app, which reads from the gateway at `unix:/tmp/f250/vehicle.sock`

Expect the first build to take a while on the Pi.

## 3. Run

`make pi-run` builds anything that changed, then starts the gateway, the
recorder and the fullscreen app. Closing the app or pressing Ctrl-C stops all
three.

| Command | What it does |
|---|---|
| `make pi-run` | Simulator. For the bench: display, touch and the whole stack. Transmits nothing |
| `make pi-run TRANSPORT=obdlink` | MX+ in **PASSIVE_ONLY** mode. The adapter is never opened |
| `make pi-run TRANSPORT=obdlink TRANSMIT=1` | MX+ polling. Only read-only services (ADR-0007). This is the explicit opt-in |
| `… UI=0` | Gateway and recorder only, no app. Useful for a logged drive |
| `… UI=headless` | The app runs under `cage` on a virtual display. Tests the whole stack without a screen |

Where the app draws, with `UI=1` (the default):

1. In this shell's desktop session, if there is one.
2. Otherwise in the desktop session on the Pi's screen (`wayland-0`, then X11 `:0`).
3. Otherwise (Lite) fullscreen under `cage`.

Other options:

- `ADAPTER=rfcomm:AA:BB:…`. The default is the truck's MX+, `00:04:3E:85:EA:FC`.
- `ENABLE=eot,ficm_main` polls unverified signals. They stay marked UNVERIFIED.
- `BUDGET_RPS=8` overrides the scheduler's 10 requests/s.
- `SCENARIO=` and `START=` choose the simulator scenario and start time.
- `DATA_DIR=` sets where sessions are saved. The default is `~/f250-data`.

`run.sh` refuses to start if a `vehicle-gateway` is already running, because
the new one would take over its socket.

Before you use the MX+, pair it once (step 3.5.2 in the plan). Disconnect the
phone and the ESP32 first.

```bash
bluetoothctl
# agent on / default-agent / scan on / pair 00:04:3E:85:EA:FC / trust 00:04:3E:85:EA:FC
```

Pairing is Secure Simple Pairing. Confirm the passkey it shows. Don't enter
`1234` ([bench-log](../hardware/bench-log.md)).

## What each run saves

Each run gets its own directory, `~/f250-data/<YYYYMMDD-HHMMSS>-<transport>/`:

| File | Contents |
|---|---|
| `session.txt` | Start and stop time, git commit, host, transport, whether transmit was on, and the exact gateway command |
| `telemetry.sqlite` | Recorder database ([gateway.md](gateway.md#recording-a-drive) shows how to export it) |
| `traffic/` | Every adapter line with timestamps. MX+ only |
| `gateway.log`, `recorder.log`, `app.log` | Process output. `app.log` includes `cage`'s output |

Copy the directory off the Pi after each drive. The dropout analysis in 3.5.7
is built from these files.

## Diagnosing

While `make pi-run` is running, open a second SSH session:

```bash
make console GATEWAY=unix:/tmp/f250/vehicle.sock
```

See [gateway.md](gateway.md#diagnosing-with-obd-console) for the commands.

## Power

There is no ignition sensing yet. Before key-off, shut down over SSH or from
the desktop:

```bash
sudo shutdown -h now
```

The recorder uses SQLite WAL, so a power cut loses at most the last few
seconds. SD-card corruption is still a risk, so keep a spare image.
