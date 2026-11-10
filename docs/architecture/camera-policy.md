# Camera policy

Status: **design**. The policy logic is pure and tested in simulation in Phase
6. Capture hardware, pipelines and latency are unverified until measured on the
Pi 5.

> **Not a safety system.** This camera system can be unavailable while booting,
> after a crash, or when the camera fails. The mirrors and normal reversing
> procedure stay mandatory. The UI says so on first use and in the manual.

## Inputs

How the view is chosen: [ADR-0024](adr/0024-camera-selection-switch-and-can-reverse.md)
(owner, 2026-11-09).

| Input | Source | Never |
|---|---|---|
| Camera switch | A 5-way switch in the cab (left, right, back, forward, press) on Pi GPIO, read by the power-manager ([wiring](../wiring/power-and-inputs.md#camera-switch)). Part TBD ([H32](../hardware/open-questions.md)) | — |
| Reverse | The gateway, from HS-CAN broadcast `230` byte 0 (`10` in R), listen-only. A **candidate** decoder until its truck check ([CAN_CENSUS](../diagnostics/CAN_CENSUS.md#reverse-found-event-matched-candidates)) | A reverse-lamp tap; asking the gateway to transmit |
| Speed | Gateway signal, only if the optional `manual_max_speed` is set | — |

There are no turn-signal inputs: the turn signals aren't on HS-CAN, and side
views are picked with the switch instead.

The camera manager **never** asks the gateway to transmit anything.

## Policy (pure function plus timers; fully unit-tested)

Priority, highest first:

1. **Reverse** shows the rear camera.
   - Activates when reverse has been reported for at least `rev_debounce_ms`
     (default 150 ms, an example).
   - Stays up for `rev_hold_ms` after reverse clears (default 2000 ms, an
     example).
   - If the reverse signal is **stale or unknown** (no CAN adapter, gateway
     down, decoder not yet verified), there is no automatic rear view, and the
     UI shows that reverse is unknown. It is never treated as "not in reverse"
     silently.
2. **The switch's choice**, latched until the next move:

   | Switch | Default (configuration) |
   |---|---|
   | Left / Right | That side's camera |
   | Back | Rear camera |
   | Forward / Press | No camera: back to the previous screen |

   - Allowed at any speed (owner). `manual_max_speed` is an optional limit,
     off by default.
   - A contact must be the only one closed for `switch_debounce_ms` (default
     30 ms, an example) to count, once per closure. power-manager does this
     before passing the move on
     ([ADR-0025](adr/0025-camera-switch-through-gpio-key.md)); camera-manager
     maps it to a camera and latches it.
   - Moving the switch during reverse records the choice; it shows once
     reverse ends.

When reverse ends, the UI shows the switch's choice if there is one, otherwise
the screen or app that was showing before reverse.

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
