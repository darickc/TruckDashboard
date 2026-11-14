# ADR 0044 — The knob display: a round gauge and the volume knob on one USB cable

- **Status:** Accepted (owner asked, 2026-11-13). [SIM] only:
  - the frame format, the dial's staleness and layout, and the tap rules are
    host-tested in `firmware/knob-display` (`pio test -e native`); the S3
    firmware builds; `services/knob-link` is tested against the simulated gateway
    and a pseudo-terminal;
  - **no board yet** (not bought). The display, touch and encoder drivers are not
    written: their pins and the ST77916 panel's start-up come from Waveshare's
    demo, which hasn't been read. Until then the firmware runs the USB link and
    the model only, and says so in its log. Bench check 25.
- **Date:** 2026-11-13
- **Refines:** [ADR-0043](0043-master-volume-and-the-volume-knob.md) (the knob
  as Linux input). Phase 6.3.

## Context

The owner wants Waveshare's ESP32-S3-Knob-Touch-LCD-1.8 in the truck: the
speed in the middle, fuel as a gauge along the bottom, EOT, ECT and EOT − ECT
along the top edge; the knob turns the volume, and a push or tap plays and
pauses the phone (ADR-0043).

| Fact | Source | Status |
|---|---|---|
| 1.8″ round IPS, 360 × 360, 600 cd/m², QSPI ST77916, capacitive touch CST816 over I2C | Waveshare product page, read 2026-11-13 | From the maker |
| ESP32-S3R8 (8 MB PSRAM, 16 MB flash) and a second ESP32 (ESP32-U4WDH); a knob encoder for each; vibration motor (DRV2605); PCM5100A DAC | product page | From the maker |
| The USB-C connects the S3's own USB or the second ESP32's UART, by the plug's orientation | product page ("Switching ESP32-S3 USB or ESP32 UART based on Type-C plug orientation") | From the maker; how is UNVERIFIED (schematic not read) |
| Waveshare's demo: Arduino (esp32 core ≥ 3.2.0) and ESP-IDF, LVGL 8.4, an encoder test | wiki, read 2026-11-13 | From the maker; not downloaded |
| As shipped, the second ESP32 advertises Bluetooth audio (`TAIJI_KNOB_AUDIO`) and a Bluetooth HID knob (`TAIJI_KNOB_HID`) | wiki | From the maker |
| Whether the knob has a push switch | — | UNVERIFIED |
| The S3's USB can be a composite device: CDC serial and HID Consumer Control at once (arduino-esp32's `USB`, `USBCDC`, `USBHIDConsumerControl`, TinyUSB) | arduino-esp32 2.x `libraries/USB` | Builds here; not run on a board |
| The gateway's snapshots carry each sample's validity, last good value and its age, and the alerts by signal | `shared/proto/f250/vehicle/v1/vehicle.proto` | Verified (our API) |

The signals' standing, from the registry (2026-11-13): `speed` SAE, its
truck calibration not measured yet; `ect` SAE; `eot` and `fuel_level`
`IMPORTED_UNVERIFIED` and disabled by default; `eot_ect_delta` computed,
valid only while both are.

## Decision

1. **One USB cable to the Pi**, on the S3's own USB. The S3 is a composite
   device named "F-250 knob": a serial port for the gauge data and a USB HID
   knob (Consumer Control: volume up/down a detent, mute, play/pause), which
   audio-manager already reads (ADR-0043). Power comes the same way. The
   second ESP32 is reflashed to an empty program so it never advertises
   Bluetooth. Buy the version without the battery (`-EN`/`-B-EN`): no lithium
   cell in a hot cab.
2. **The dial never talks to the truck** (CLAUDE.md rule 5). A Pi daemon,
   `services/knob-link`, reads vehicle-gateway's snapshots and writes frames
   to the serial port. The dial decides nothing about the data but one thing:
   with no data frame for 2 s, everything on it is stale.
3. **Frames** are ASCII lines, at most 255 characters, ending in an NMEA-style
   checksum (`*` and the XOR of the characters before it, two hex digits). A
   line with a bad checksum, an unknown kind or an unknown version is
   dropped and counted.
   - `C1 <slot>:<unit>:<min>:<max>:<trust> …` — what each slot shows; every
     5 s and on connect. Slots: `spd fuel eot ect dlt`. `trust` is `v` (SAE,
     verified on the truck, or computed from those) or `u` (imported,
     unverified: the dial marks it).
   - `N1 …` and `M1 …` — the navigation and media pages (decision 9).
   - `D1 <seq> <mode> <slot>:<state>[:<value>[:<age_s>]] …` — every 250 ms.
     `mode` is `live` or `sim` (shown as SIMULATED). `state`: `c` current,
     `a` current with an advisory alert, `k` with a critical alert, `s` stale
     (the last good value and its age in seconds), `n` nothing to show.
     Values are already in the display's units (the Pi converts).
   - From the dial: `H1 <name> <version>` on connect and every 10 s, for the
     Pi's log.
4. **Honest on the dial** (rule 4): a stale value is drawn dim in amber with
   its age; `n` draws a dash; an alert colours its arc (amber advisory, red
   critical: the gateway's rules, which are configuration, rule 10); a `u`
   slot has a small "unverified" mark; a lost link makes everything stale with
   the ages counting on from the last frame, and a ring says "no data".
5. **Layout** (360 × 360): speed in the middle (large); fuel an arc across the
   bottom from 122° to 238° (0° up, clockwise) with E and F; EOT, ECT and
   EOT − ECT three arcs across the top (−72°…−28°, −21°…21°, 28°…72°), each
   with its value under it. Arc ranges are examples from knob-link's
   defaults, not limits.
6. **Push and tap.** The knob's push (if it has a switch) sends play/pause. A
   tap on the screen sends play/pause only if it is short (under 400 ms),
   doesn't move (under 20 px) and comes at least 600 ms after the knob last
   turned, so a finger resting on the screen while turning doesn't pause the
   music. Examples, in the firmware's configuration.
7. **knob-link:** `--gateway` (the gateway's `/run/f250/vehicle.sock`) and
   `--device` (the dial's serial port, found by
   `/dev/serial/by-id/*F-250_knob*`), imperial or metric (`KNOB_UNITS`),
   reopened every 2 s when it goes; it logs the dial's hello and every
   opening. A dial that isn't plugged in is normal, not an error. It sends
   the config frame again as soon as the gateway's definitions arrive, and
   no data frame from a snapshot older than 2 s (the dial then goes stale by
   itself). `f250-knob-link.service`: user f250, group dialout, only
   `char-ttyACM` devices. `--plain-file` opens a pseudo-terminal that is
   already raw, for testing on the Mac without the dial.
8. **Firmware layout:** `firmware/knob-display/`, its own PlatformIO project
   (ESP32-S3, not the existing firmware's ESP32): `lib/KnobCore` is plain C++
   (frames, the model, the layout, the tap rules), host-tested; the display,
   touch and encoder drivers go in `lib/KnobHw` when the board is here.

9. **Pages** (owner, 2026-11-13): gauges, navigation, media, in that order.
   A swipe left goes to the next, right to the previous, stopping at the ends
   (at least 60 px sideways, twice as far sideways as up or down, within
   800 ms: examples). The knob is the volume and a tap play/pause on every
   page, so neither changes meaning under the driver's thumb.
   - `N1` (navigation's guidance and its route): `go <turn> <dist> <dunit>
     <left> <lunit> <min> [<street>]`, or `none`, `route`, `wait` (a route but
     no current position: no distance is ever shown from an old one),
     `arr [<destination>]`. The turn is one of 19 arrows knob-link maps from
     Valhalla's maneuver type, the dashboard's grouping; distances are text
     already in the display's units (feet to 0.1 mi, then miles).
   - `M1` (audio-manager): `<play|pause|stop> <vol> <pos_s|-> <dur_s|->
     <title>\t<artist>\t<source>` or `none <vol>`; `<vol>` is
     `level/steps`, `m…` when muted, or `-`. Text has no tabs, stars or
     control characters and is cut on a character boundary.
   - knob-link sends each once per data period while its source answered in
     the last 3 s; the dial shows a page's data only while its frames keep
     coming (3 s), otherwise "no data", never an old turn or track.
   - `P1` (audio-manager, a phone call; ADR-0045 decision 6): `<ring|wait|
     dial|call|hold> <active_s> <caller>\t<number>` or `none`. The caller is
     the dashboard's words (the name, the number, "Number withheld", "Unknown
     caller"); the number only under a name. A call takes over the dial on
     any page while its frames keep coming (3 s, as above): the caller and
     "Push to answer", "Push to hang up" or "Answer on the phone". During a
     call touches do nothing (a tap is too easy by accident; the page stays
     put); the push is still the HID play/pause key, and audio-manager makes
     it answer a ringing call or hang up the one in progress. The turn stays
     the volume.
   - Not decided: jumping to the navigation page by itself near a turn; cover
     art on the dial (too heavy for the line protocol).

## Alternatives considered

- **Wi-Fi or Bluetooth to the Pi:** pairing, another radio near the phone,
  and the dial still needs power on a cable. Rejected for USB.
- **The dial reading CAN or the MX+ itself:** against rule 5 and ADR-0007.
- **The Pi drawing the dial** (a second display output): the S3 is on the
  board anyway, and a line protocol keeps the dial dumb.
- **Protobuf over the serial port:** the dial would need nanopb and framing
  for five numbers; the lines are readable in a terminal on the bench.

## Consequences

- Units on the dial follow `KNOB_UNITS`, not the dashboard's setting (the
  dashboard keeps its own). One place to change if that bothers the owner.
- The dial can't show a signal the gateway doesn't poll: EOT and fuel need the
  owner's enable list on the truck card.
- Two more processes: knob-link on the Pi, and USB enumeration of a
  composite device that has never run.

## To verify (bench check 25)

1. The board: which way the USB-C plug connects the S3 (`lsusb` shows
   "F-250 knob" with a CDC and a HID interface); its HID device's events
   ([agl.md, input events](../../setup/agl.md#input-events))
   shows `KEY_VOLUMEUP`/`KEY_VOLUMEDOWN` a detent and `KEY_PLAYPAUSE`.
2. The second ESP32 reflashed: no `TAIJI_*` in a phone's Bluetooth list.
3. `journalctl -u f250-knob-link`: "dial: knob-display …" hello lines.
   The dial shows the simulated gateway's speed and temperatures, SIMULATED;
   unplug the gateway (stop it): everything goes stale within 2 s.
4. Daylight readability at 600 cd/m² in the truck.
