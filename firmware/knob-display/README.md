# Knob display firmware

The round gauge and volume knob on Waveshare's ESP32-S3-Knob-Touch-LCD-1.8
([ADR-0044](../../docs/architecture/adr/0044-knob-display.md)): speed in the
middle, fuel along the bottom, EOT, ECT and EOT − ECT along the top; swipe for
the next turn and what's playing. One USB
cable to the Pi: the S3 is "F-250 knob", a serial port that receives
`services/knob-link`'s frames and a USB HID knob (volume, mute, play/pause)
that audio-manager reads ([ADR-0043](../../docs/architecture/adr/0043-master-volume-and-the-volume-knob.md)).

**Status `[SIM]`: no board yet.** The frames, the dial's model (stale data, a
lost link), the layout and the tap rules are host-tested; the firmware builds
for the S3 and has never run. The display (ST77916, QSPI), touch (CST816) and
encoder drivers aren't written: their pins and the panel's start-up come from
Waveshare's demo, which hasn't been read. Until then the firmware parses
frames, draws nothing, and prints what it would show on its serial port as
`# ...` lines (knob-link logs them).

| Path | What |
|---|---|
| `lib/KnobCore/src/Frame.*` | The line protocol (`C1`, `D1`, `H1`, NMEA checksum) |
| `lib/KnobCore/src/Dial.*` | What each slot shows: current, alert, stale with its age, nothing; everything stale after 2 s without a frame |
| `lib/KnobCore/src/Layout.*` | Where the arcs and the text go on the 360 × 360 screen |
| `lib/KnobCore/src/Tap.*` | Gestures: a tap plays/pauses only if short, still, and not just after a turn; a swipe changes the page |
| `lib/KnobCore/src/Pages.*` | Gauges, navigation, media: the page shown, and the nav and media frames while they keep coming |
| `src/main.cpp` | USB (TinyUSB composite: CDC + HID Consumer Control), the frame reader, the log |
| `test/` | Host tests (Unity); `test_frame` parses the exact lines knob-link's tests produce (gauges, nav, media) |

```bash
make knob-test
```

```bash
make knob-build
```

When the board arrives: buy the version without the battery (`-EN`/`-B-EN`),
check which way the USB-C plug connects the S3, reflash the second ESP32 so it
stops advertising Bluetooth, and write `lib/KnobHw` from Waveshare's demo.
Bench check 25 in [docs/setup/agl.md](../../docs/setup/agl.md).
