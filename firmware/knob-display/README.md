# Knob display firmware

The round gauge and volume knob on Waveshare's ESP32-S3-Knob-Touch-LCD-1.8
([ADR-0044](../../docs/architecture/adr/0044-knob-display.md)): speed in the
middle, fuel along the bottom, EOT, ECT and EOT − ECT along the top; swipe for
the next turn and what's playing. One USB
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
| `lib/KnobCore/src/Frame.*` | The line protocol (`C1`, `D1`, `H1`, NMEA checksum) |
| `lib/KnobCore/src/Dial.*` | What each slot shows: current, alert, stale with its age, nothing; everything stale after 2 s without a frame |
| `lib/KnobCore/src/Layout.*` | Where the arcs and the text go on the 360 × 360 screen |
| `lib/KnobCore/src/Tap.*` | Gestures: a tap plays/pauses only if short, still, and not just after a turn; a swipe changes the page |
| `lib/KnobCore/src/PulseKnob.*` | The knob: a low pulse on A is a step clockwise, on B anticlockwise (not quadrature), sampled every 3 ms |
| `lib/KnobCore/src/Pages.*` | Gauges, navigation, media: the page shown, and the nav and media frames while they keep coming; a phone call (`P1`) over every page, touches ignored during it (ADR-0045) |
| `lib/KnobHw/src/Pins.h` | The S3's pins, from Waveshare's schematic and demo |
| `lib/KnobHw/src/Panel.*`, `PanelInit.inc` | The 360 × 360 QSPI panel (esp_lcd, 40 MHz quad) and its backlight; the 185 start-up commands generated from the demo's `lcd_bsp.c` |
| `lib/KnobHw/src/Touch.*` | The CST816, polled over I2C |
| `src/DialUi.*` | The dial drawn with LVGL 8.4.0 from Dial and Pages: gauges, navigation, media, and a call over them ([ADR-0044 amendment 2](../../docs/architecture/adr/0044-knob-display.md#amendment-2026-11-22-2-the-dial-drawn)) |
| `include/lv_conf.h` | LVGL's settings: the package's template, changed where its header says |
| `src/fonts/`, `tools/make_fonts.sh` | Montserrat Medium and SemiBold in eight sizes, generated with `lv_font_conv` (`make knob-fonts`; don't edit by hand) |
| `src/main.cpp` | USB (TinyUSB composite: CDC + HID Consumer Control), the frame reader, the knob and touch, the log |
| `test/` | Host tests (Unity); `test_frame` parses the exact lines knob-link's tests produce (gauges, nav, media, call) |

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

Still to do: reflash the second ESP32 so it stops advertising Bluetooth (the plug turned over), and
bench check 25 on the Pi in [docs/setup/agl.md](../../docs/setup/agl.md).
The knob has no push switch (schematic), so answering a call from the knob
needs another gesture (ADR-0044 amendment, open).
