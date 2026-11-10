# ADR 0009 — Camera rendering chosen by a measured spike

- **Status:** Proposed. Decided in Phase 6 after measurement. The spike has
  started: option B measured on the bench (2026-11-09, below), about 90 ms
  glass to glass; the owner's verdict on that, and option A, still to do
- **Date:** 2026-11-01

## Context

Critical engine alerts must stay visible on every screen, including a
full-screen reverse camera. On AGL there are two credible ways to show video:

- a Flutter texture fed by GStreamer
- a separate GStreamer `waylandsink` surface raised through agl-compositor's
  `agl-shell` roles

GStreamer with V4L2 is in our images from meta-f250 `6114c52` (1.28.5,
[BENCH]). Flutter video and texture plugin support on flutter-auto: see the
findings below.

## Decision

Build both on the Pi 5 with one UVC camera. Measure:

- glass-to-glass latency (LED and phone-camera method)
- CPU and GPU load
- startup time
- whether alerts stay visible

Pick the option that keeps alerts visible with latency the owner accepts. The
camera *policy* (reverse priority, debounce, restore the previous screen) is
independent of this decision and is implemented first.

## Consequences

The camera UI may stay simulated until Phase 6 measures this.

## Spike findings so far (2026-11-09)

[bench-log](../../hardware/bench-log.md) 2026-11-09, "Camera rendering spike".

**Three candidates, not two.**

| | How | What it needs on our image |
|---|---|---|
| A. Flutter texture | `video_player_linux` (GStreamer `playbin` into a `fakesink`, frames copied into a GL texture) and the `video_player` package in the dashboard | flutter-auto rebuilt with the **EGL** backend: on the Pi 5 it draws with Vulkan, and its external textures are GL only. Plus the `video-player` PACKAGECONFIG (pulls ffmpeg and gst-libav). The camera then runs inside the dashboard's process |
| B. A camera window in an activation area | camera-manager runs its own `waylandsink` window; the dashboard's `config.toml` sets `[window_activation_area]` below the status bar and alert banner, and agl-compositor confines app windows to it | Nothing: works on image `6114c52` today |
| C. A `comp_surf` subsurface | The dashboard asks flutter-auto for a Wayland subsurface above or below its own, at a position it chooses, with a native module rendering into it | flutter-auto rebuilt with the `comp_surf` plugin, and a native module (C or C++) that drives GStreamer |

The `camera` plugin is out: upstream marks it work in progress, with no
frames yet.

**Option B, measured [BENCH]:** the camera shows inside the area, and the
critical banner and status bar stay visible above it. First frame 0.62 s
after GStreamer starts. 5 % of one core for the pipeline and 0.8 % more for
the compositor. It needs no rebuild, keeps the camera in its own process (a
camera crash can't take the dashboard down), and fits the planned
camera-manager daemon.

**B's costs, still to settle:**

- The area is fixed when the dashboard starts. The dashboard must keep the
  alert banner's strip reserved while a camera shows, and the picture is
  limited to the area (800×320 with the nav bar kept, 427×320 for a 4:3
  camera).
- Alerts can only be drawn around the camera, never on top of it.
- Showing and hiding without restarting the pipeline needs a gRPC client
  for `DeactivateApp`/`ActivateApp` (127.0.0.1:14005), not built yet.
- Touches on the camera window go to camera-manager, not the dashboard.

**Still to do before deciding:**

1. ~~Glass-to-glass latency for B.~~ About 90 ms with the webcam (one
   readable photo of three; all three under about 145 ms), measured with
   [`tools/dev/latency-clock.html`](../../../tools/dev/latency-clock.html)
   (bench-log 2026-11-09, "glass-to-glass latency"). Whether that is
   acceptable is the owner's call.
2. Whether A is worth building for comparison: it changes the dashboard's
   renderer from Vulkan to GL.
