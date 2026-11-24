# Knob display firmware

The round gauge and volume knob on Waveshare's ESP32-S3-Knob-Touch-LCD-1.8
([ADR-0044](../../docs/architecture/adr/0044-knob-display.md)): speed in the
middle, fuel along the bottom, EOT, ECT and EOT − ECT along the top; swipe for
the next turn and what's playing (the phone's cover behind it). Until the
Pi's first frame it shows a boot screen. One USB
cable to the Pi: the S3 is "F-250 knob", a serial port that receives
`services/knob-link`'s frames and a USB HID knob (volume, mute, play/pause)
that audio-manager reads ([ADR-0043](../../docs/architecture/adr/0043-master-volume-and-the-volume-knob.md)).

**Status: on the bench.** The frames, the dial's model (stale data, a lost
link), the layout, the tap rules and the knob's decoding are host-tested
`[SIM]`. On the board, from the Mac `[BENCH]`
([bench log 2026-11-22](../../docs/hardware/bench-log.md)): the composite USB
device, the display, touch and the knob work, the knob sends volume keys, and
the dial (gauges, navigation, media, a call over them) is drawn with LVGL
from knob-link's frames. What the dial shows also goes to the serial port as
`# ...` lines (knob-link logs them). Not yet on the Pi.

arduino-esp32 **3.x** (pioarduino 55.03.311), not the 2.x of
`firmware/esp32`: the panel is QSPI, which 2.x's `esp_lcd` can't drive
([ADR-0044 amendment](../../docs/architecture/adr/0044-knob-display.md#amendment-2026-11-22-the-board-on-the-bench)).

| Path | What |
|---|---|
| `lib/KnobCore/src/Frame.*` | The line protocol (`C1`, `D1`, `N1`, `M1`, `P1`, `A1`, `H1`, NMEA checksum) |
| `lib/KnobCore/src/Boot.*` | The boot screen's stages: waiting for the Pi, starting, done at the first frame; what is missing after 3 minutes ([ADR-0044 amendment 3](../../docs/architecture/adr/0044-knob-display.md#amendment-2026-11-23-a-boot-screen-and-the-cover-behind-the-media-page)) |
| `lib/KnobCore/src/Art.*` | The media page's cover: `A1` lines put together in order and checked by CRC-32, base64, the bilinear scale from 180 to 360 |
| `lib/KnobCore/src/Dial.*` | What each slot shows: current, alert, stale with its age, nothing; everything stale after 2 s without a frame |
| `lib/KnobCore/src/Layout.*` | Where the arcs and the text go on the 360 × 360 screen |
| `lib/KnobCore/src/Tap.*` | Gestures: a tap plays/pauses only if short, still, and not just after a turn; a swipe changes the page |
| `lib/KnobCore/src/PulseKnob.*` | The knob: a low pulse on A is a step clockwise, on B anticlockwise (not quadrature), sampled every 3 ms |
| `lib/KnobCore/src/Pages.*` | Gauges, navigation, media: the page shown, and the nav and media frames while they keep coming; a phone call (`P1`) over every page, touches ignored during it (ADR-0045) |
| `lib/KnobHw/src/Pins.h` | The S3's pins, from Waveshare's schematic and demo |
| `lib/KnobHw/src/Panel.*`, `PanelInit.inc` | The 360 × 360 QSPI panel (esp_lcd, 40 MHz quad) and its backlight; the 185 start-up commands generated from the demo's `lcd_bsp.c` |
| `lib/KnobHw/src/Touch.*` | The CST816, polled over I2C |
| `src/DialUi.*` | The dial drawn with LVGL 8.4.0 from Dial and Pages: the boot screen, gauges, navigation, media (over the cover), and a call over them ([ADR-0044 amendment 2](../../docs/architecture/adr/0044-knob-display.md#amendment-2026-11-22-2-the-dial-drawn)) |
| `include/lv_conf.h` | LVGL's settings: the package's template, changed where its header says |
| `src/fonts/`, `tools/make_fonts.sh` | Montserrat Medium and SemiBold in eight sizes, generated with `lv_font_conv` (`make knob-fonts`; don't edit by hand) |
| `src/main.cpp` | USB (TinyUSB composite: CDC + HID Consumer Control), the frame reader, the knob and touch, the log |
| `esp32-off/main.cpp` | The board's second ESP32 (env `esp32-off`): no Wi-Fi, no Bluetooth, deep sleep. `make knob-esp32-off PORT=/dev/cu.usbserial-…` with the USB-C plug turned over |
| `test/` | Host tests (Unity); `test_frame` parses the exact lines knob-link's tests produce (gauges, nav, media, call); `test_art` checks base64 and CRC-32 against the same vectors as knob-link's `art.rs` |

```bash
make knob-test
```

```bash
make knob-build
```

Flashing from the Mac: a USB-C to USB-A cable that carries data (two that
only charge lit the screen and showed nothing), with the plug the way round
that shows up as Espressif's "USB JTAG/serial debug unit" or, once this
firmware runs, "F-250 knob". `make knob-build`, then
`cd firmware/knob-display && pio run -e knob -t upload`: it resets the S3
into its loader at 1200 baud; if the first try says the port is busy, run it
again. Hold BOOT at power-on if nothing else works. The stock firmware's
backup and restore command are in `build/knob/` on the Mac that read it.

On the Pi: bench check 25 in [docs/setup/agl.md](../../docs/setup/agl.md)
passed on the bench (bench log 2026-11-22) except readability in daylight,
which needs the truck. Firmware 0.3.0's boot screen and cover work on the
Pi with the owner's phone (bench log 2026-11-23).
The knob has no push switch (schematic), so answering a call from the knob
needs another gesture (ADR-0044 amendment, open).
