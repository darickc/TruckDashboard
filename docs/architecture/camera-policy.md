# Camera policy

Status: the policy is implemented in `crates/camera-policy` and unit-tested
**[SIM]** (Phase 6.6). Rendering is decided ([ADR-0009](adr/0009-camera-rendering.md)):
a camera window in an activation area, about 90 ms with a USB webcam
**[BENCH]**. `services/camera-manager` runs it **[SIM]**
([ADR-0026](adr/0026-camera-manager-interfaces.md)). No truck camera exists yet, and the
reverse decoder isn't verified.

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
   - **Off by default** (`auto_reverse`) until the `230` decoder has its
     VERIFICATION_LOG entry (ADR-0024 decision 4). Off, the indicator says so,
     and the switch's Back is the way to see the rear camera.
   - Activates when reverse has been reported for at least `rev_debounce_ms`
     (default 150 ms, an example).
   - Stays up for `rev_hold_ms` after reverse clears (default 2000 ms, an
     example).
   - If the reverse signal is **stale or unknown** (no CAN adapter, gateway
     down, the gateway marks it invalid, or no sample for `rev_stale_ms`,
     default 500 ms, an example: the broadcast comes about 31 times a second),
     there is no automatic rear view, and the UI shows that reverse is
     unknown. It is never treated as "not in reverse" silently.
   - If reverse goes unknown **while the rear view is up**, and the last
     sample said reverse, the rear view stays (owner, 2026-11-09), with the
     unknown warning,
     until the signal comes back or the switch moves. Any move then takes
     over at once. Dropping the rear camera mid-reverse on a CAN glitch would
     be worse than keeping it, and the switch is the way out. If the last
     sample said reverse had ended, the hold runs out as usual.
2. **The switch's choice**, latched until the next move:

   | Switch | Default (configuration) |
   |---|---|
   | Left / Right | That side's camera |
   | Back | Rear camera |
   | Forward / Press | No camera: back to the previous screen |

   - Allowed at any speed (owner). `manual_max_speed` is an optional limit,
     off by default. Set, it hides a chosen camera while the speed is above
     it **or unknown**, and the UI says why; the choice stays latched and
     shows again when slow. It never hides reverse, and never blocks "no
     camera".
   - A contact must be the only one closed for `switch_debounce_ms` (default
     30 ms, an example) to count, once per closure. power-manager does this
     before passing the move to camera-manager's `Move` call
     ([ADR-0025](adr/0025-camera-switch-through-gpio-key.md),
     [ADR-0026](adr/0026-camera-manager-interfaces.md) decision 6), which maps
     it to a camera and latches it. A move that can't be delivered within
     about a second is dropped, never applied late.
   - Moving the switch during reverse records the choice; it shows once
     reverse ends.

When reverse ends, the UI shows the switch's choice if there is one, otherwise
the screen or app that was showing before reverse.

| Situation | Result |
|---|---|
| A camera is missing or has failed | Show a "Camera unavailable" panel in its slot, never a frozen frame, and log it. A camera counts as unavailable until its pipeline reports frames |
| A frame is stale (no new frame for `--frame-timeout-ms`, 1000 ms, an example) | Same panel. camera-manager kills the pipeline, which closes its window: freezing the last frame is not allowed |

## Rendering ([ADR-0009](adr/0009-camera-rendering.md), accepted 2026-11-09)

camera-manager shows the camera in its own `waylandsink` window. The
dashboard's `config.toml` sets an activation area below its status bar and
alert-banner strip, and agl-compositor keeps every app window inside it, so
alerts stay visible above the camera. About 90 ms glass to glass with a USB
webcam, 5 % of one core [BENCH]. The dashboard keeps the banner strip
reserved while a camera shows, and the "Camera unavailable" panel is the
dashboard's, drawn in the same area when camera-manager reports no frames.

## Hardware selection criteria (Phase 6)

- **Start with UVC USB cameras or UVC capture devices.** They use V4L2 with no
  vendor driver.
- CVBS and AHD need capture hardware whose Linux driver works on the AGL kernel
  (6.18). Choose by working driver support, **not** advertised resolution.
- Up to three cameras at once means checking USB bandwidth. MJPEG or H.264
  output is preferred.
- **A UVC webcam works on the AGL image** (Logitech C250, 640×480 at ~30 fps
  in YUYV and MJPEG; [bench-log](../hardware/bench-log.md) 2026-11-09). The
  images from `6114c52` carry `v4l2src`, `jpegdec`, `appsink` and
  `waylandsink`. On them the webcam decodes at ~29 fps. Without an
  activation area, a `waylandsink` window goes full-screen over the dashboard
  and hides its alerts (bench-log 2026-11-09), which is why ADR-0009 confines
  it.
