# USB devices, camera power and the display's power

**Status: DESIGN, NOT VERIFIED.** The cameras (H10, H33), the GNSS receiver
(H11), the knob display (ADR-0044) and the microphone (ADR-0045, spike S4)
aren't chosen or bought yet. A person must check this sheet against the
chosen parts and sign it off in [bench-log.md](../hardware/bench-log.md)
before installation ([safety gates](../safety/assumptions.md#human-verification-gates)).

## No 12 V camera power

The cameras are **USB (UVC) cameras**, powered from the USB cable
([ADR-0009](../architecture/adr/0009-camera-rendering.md),
[ADR-0027](../architecture/adr/0027-front-and-rear-recording.md)). There is
no 12 V camera feed and no camera power wire into the truck's electrics.
If an analogue camera (12 V power, composite video) is ever chosen instead,
it needs a capture device and its own fused, switched feed: that is a new
design and an update to this sheet.

## Port plan

From [ADR-0047](../architecture/adr/0047-head-unit-enclosure.md) decision 6.
Which of the Pi's ports sits on which USB controller, and splitting the
cameras across them: [ADR-0027](../architecture/adr/0027-front-and-rear-recording.md).

| Devices fitted | Pi's own ports | USB 2.0 hub (one Pi port) |
|---|---|---|
| One camera | CAN adapter, GNSS receiver, knob display, the camera | None |
| Two to four cameras | The cameras, split across both controllers | CAN adapter, GNSS receiver, knob display; a fourth camera if the ports run out |
| A USB microphone (if S4 rules out the knob display's) | — | On the hub. With one camera that means fitting the hub anyway: the four ports are full |

- The hub is **USB 2.0**: none of these devices needs USB 3, and USB 3 links
  add noise in the 2.4 GHz band used by the Pi's Bluetooth (music, calls)
  near the GNSS antenna (ADR-0047).
- The DCDC-USB's mini-USB port is **not connected** (pulse-only, ADR-0013).
- The NVMe drive is on PCIe, not USB.

## Camera power

Every camera, and the hub's devices, draw from the Pi's USB current:

| Fact | Status |
|---|---|
| The Pi 5's downstream USB is limited to 600 mA in total, or 1.6 A on a 5 A supply, shared with the fan header | V ([matrix](../hardware/compatibility-matrix.md)) |
| Whether `PSU_MAX_CURRENT=5000` with the DCDC-USB's 5 V lifts the 600 mA limit | U (H25) |
| Each camera's current | U, from its datasheet, then measured (H33) |

**Rule:** add up every USB device's current (cameras, CAN adapter, GNSS,
knob display, microphone). If the total is more than the Pi supplies (H25),
the cameras get power from outside the Pi, one of:

- a **powered USB 2.0 hub** for the cameras, its 5 V taken from the
  DCDC-USB's VOUT if the DCDC-USB has the margin (H25), or
- a **separate 12 V → 5 V converter** on ACC, through its own fuse, feeding
  the hub.

Which one: decided once the cameras and H25 are measured. Either way the
5 V for the cameras comes on and off with the key, never from the battery
directly.

**Cable length.** Passive USB 2 reaches about 5 m (H33). The rear camera's
run from the dash to the back of the truck, and the side cameras' runs:
**TODO**, measured in the truck. Past 5 m: an active USB extension, or a
camera mounted closer with a longer cable of its own. Route camera cables
away from the amp power wire and the RCA runs.

## Display power

The original 7" display takes 5 V and GND from the Pi's GPIO header
through its supplied jumper wires (V, RPi display docs; [matrix](../hardware/compatibility-matrix.md)).
With the 8xOUT on the header, those pins must still be reachable: a
pass-through header, a stacking header or a breakout (H27). The display's
current then comes out of the Pi's 5 V budget too (H25).

## Checks before sign-off

| # | Check | Expected | Result |
|---|---|---|---|
| 1 | Every USB device's current, from its datasheet, added up | Recorded, against the Pi's limit | |
| 2 | Pi at full load with every device and camera streaming: `vcgencmd get_throttled` | `0x0` (H25) | |
| 3 | `lsusb -t`: which controller each camera is on | As ADR-0027 | |
| 4 | Each camera cable's length | ≤ 5 m passive, or an active extension | |
| 5 | Display 5 V at its connector with the Pi under load | Record it | |
| 6 | Bluetooth music and a call with every USB device connected | No dropouts | |

Signed off by: _____ Date: _____
