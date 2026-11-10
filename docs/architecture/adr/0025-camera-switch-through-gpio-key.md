# ADR 0025 — The camera switch is read through the kernel's `gpio-key` overlay

- **Status:** Accepted. [SIM] only: power-manager's debounce is unit-tested,
  and the reader runs end to end on a Mac with events written into a FIFO.
  The overlay lines haven't booted on the Pi 5 yet
- **Date:** 2026-11-09
- **Refines:** [ADR-0024](0024-camera-selection-switch-and-can-reverse.md)
  decision 3 (power-manager reads the switch) and
  [ADR-0013](0013-dcdc-usb-power-supply.md) (power-manager owns the GPIO)

## Context

The 5-way camera switch closes one of five contacts to ground, each on its
own GPIO ([wiring](../../wiring/power-and-inputs.md#camera-switch)).
power-manager has to see those closures and pass them on. It already reads
the power key from a Linux input device, with no C library: the workspace
forbids `unsafe` code, and it has no `libc` dependency.

## Options

1. **The GPIO character device** (`/dev/gpiochipN`, uAPI v2). Edge events
   come from an ioctl on a line request, which needs `unsafe` code or a
   `gpio-cdev`/`libgpiod` crate, a `char-gpio` device grant in the sandbox,
   and pull-ups set from userspace.
2. **sysfs GPIO** (`/sys/class/gpio`). Deprecated, and has no pull-up
   control.
3. **The `gpio-key` overlay** in `config.txt`: the kernel's `gpio-keys`
   driver turns each pin into a key on an input device, with the pull-up set
   by the overlay and the driver's 5 ms debounce. power-manager reads it as
   it reads the power key.

## Decision

**Option 3.**

1. One `gpio-key` line per contact in `agl/boot/config-f250.txt`, with
   `gpio_pull=2` (pull-up) and the default active low. Both the Stage 1
   script and the meta-f250 image append that file to `config.txt`.
2. **Keys F13–F17** (183–187): left, right, back, forward, press. The
   compositor gives every keyboard's keys to the dashboard, and arrow keys
   would move its focus. Nothing in the dashboard or the compositor acts on
   F13–F17.
3. **Every line names its key.** The overlay's default `keycode` is
   `KEY_POWER` (116): a line without one would turn a camera press into a
   shutdown. `make agl-test` checks this, and that the five keys and pins
   match power-manager and the wiring doc.
4. power-manager finds the devices by their key bitmaps in sysfs, as it
   finds the power key, and **debounces in software**
   (`--switch-debounce-ms`, 30 ms, an example): a contact counts once it has
   been the only one closed for that long, once per closure. Two closed
   together (a diagonal) count as neither.
5. Moves are logged until camera-manager exists (Phase 6.6). Mapping a move
   to a camera and latching it are camera-manager's policy
   ([camera-policy.md](../camera-policy.md)); power-manager only conditions
   the input.

The kernel owns the pins; power-manager is still the only program that acts
on them.

## Consequences

**Gains:**

- No `unsafe`, no new crate, no new device grant: the unit's
  `DeviceAllow=char-input r` already covers it.
- Pull-ups are set at boot, before any service runs, so an unconnected or
  idle line can't float.
- The switch can be checked with `evtest` and without power-manager.

**Costs and risks:**

- **The compositor sees the keys too.** The dashboard receives F13–F17 key
  events and ignores them. A future keyboard shortcut must not use them.
- **A contact held at start-up isn't seen** until it opens and closes again:
  input devices report changes only. Reading the current key state would need
  the `EVIOCGKEY` ioctl.
- **Pins are boot configuration,** not a service option: moving a contact
  means editing `config-f250.txt` and rebooting.
- **Unverified on the Pi 5:** that the `brcm,pull` property the overlay sets
  takes effect on the Pi 5's RP1 GPIO. Check with a meter (wiring check 8)
  and `pinctrl get 6,12,13,16,17` if the image has it.

**What was checked:** the overlay's source and README (raspberrypi/linux
`rpi-6.12.y`, read 2026-11-09): `gpio`, `keycode`, `gpio_pull` (an integer:
0 off, 1 down, 2 up), `active_low` (default 1), `label`, `autorepeat`; the
default key is 116. `gpio-key.dtbo` is in the boot partition of image
`agl-f250-22.0.1-288d091` (1428 bytes, the same overrides). The `gpio-keys`
driver is in that kernel: the Pi 5's own power button uses it (bench-log
2026-11-09).

**Tests:** the debounce (clean press, blip, bounce, hold, diagonal, rolling
from one direction to another, release without a press) and device discovery
by key bitmap, `[SIM]`. Bench: wiring checks 8–9.

## Revisit if

- The overlay's pull-up doesn't take effect on the Pi 5, or the keys reach
  something in the UI. Then option 1, through a `gpio-cdev`-style crate.
- A contact held at boot must count.
