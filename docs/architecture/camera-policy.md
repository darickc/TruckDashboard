# Camera policy

Status: **design**. The policy logic is pure and tested in simulation in Phase
6. Capture hardware, pipelines and latency are unverified until measured on the
Pi 5.

> **Not a safety system.** This camera system can be unavailable while booting,
> after a crash, or when the camera fails. The mirrors and normal reversing
> procedure stay mandatory. The UI says so on first use and in the manual.

## Inputs

| Input | Source | Never |
|---|---|---|
| Reverse | Opto-isolated input board → Pi GPIO (proposed BCM6, a config value), via the power-manager ([wiring](../wiring/power-and-inputs.md)) | A raw 12 V line on GPIO |
| Left / right turn | Two more channels on the same opto board (proposed BCM12 and BCM13). They are an analogue flasher-relay circuit, not on HS-CAN (owner, 2026-11-07) | Same. Never by polling a module |
| Gear and speed | Gateway signals, used **only** to decide whether manual selection is allowed | — |

Turn signals are **not** on HS-CAN: they are an analogue circuit switched by a
flasher relay under the dash (owner, 2026-11-07), and the listen-only census
found no flasher-rate bit ([H14](../hardware/open-questions.md)). They come
from the opto board, like reverse. Reverse stays on its hardware input; the
CAN reverse candidates ([event captures](../setup/can.md#event-captures-reverse-and-brake))
would only cross-check it after Stage B.

The camera manager **never** asks the gateway to transmit anything.

## Policy (pure function plus timers; fully unit-tested)

Priority, highest first:

1. **Reverse** shows the rear camera.
   - Activates when REV is asserted for at least `rev_debounce_ms` (default
     150 ms).
   - Stays up for `rev_hold_ms` after REV clears (default 2000 ms).
2. **Turn signal**, if enabled, shows that side's camera.
   - A flasher blinks at roughly 1–2 Hz. Treat any edge within
     `turn_hold_ms` (default 1500 ms) as still active, so the display doesn't
     flicker.
   - Activates on the first edge.
   - Releases `turn_hold_ms` after the last edge.
3. **Hazards.** Left and right flash together, edges within
   `hazard_window_ms`. Do **not** switch cameras. Keep the current screen and
   show a small indicator.
4. **Manual selection** is allowed while parked or below `manual_max_speed`.
   Reverse and turn activation override it.

When automatic activation ends, the UI returns to the screen or app that was
showing before it.

| Situation | Result |
|---|---|
| A camera is missing or has failed | Show a "Camera unavailable" panel in its slot, never a frozen frame, and log it |
| A frame is stale (no new frame for more than `frame_timeout_ms`) | Same panel. Freezing the last frame is not allowed |

## Rendering (ADR-009, a spike in Phase 6)

| Option | Pro | Con |
|---|---|---|
| Flutter texture fed by GStreamer | Critical alerts stay overlaid. One app | Embedder plugin support on flutter-auto must be confirmed. Copy cost |
| GStreamer `waylandsink` surface raised through `agl-shell` | Lowest latency. Independent of the UI process | Alerts must be drawn by the camera surface or the compositor |

Measure glass-to-glass latency and CPU on the Pi 5 for both. Choose the one
that keeps alerts visible with acceptable latency.

## Hardware selection criteria (Phase 6)

- **Start with UVC USB cameras or UVC capture devices.** They use V4L2 with no
  vendor driver.
- CVBS and AHD need capture hardware whose Linux driver works on the AGL kernel
  (6.18). Choose by working driver support, **not** advertised resolution.
- Up to three cameras at once means checking USB bandwidth. MJPEG or H.264
  output is preferred.
