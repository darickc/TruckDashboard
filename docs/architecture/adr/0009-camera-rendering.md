# ADR 0009 — Camera rendering chosen by a measured spike

- **Status:** Accepted (owner, 2026-11-09): option B, a camera window in an
  activation area. Measured [BENCH] with a USB webcam; no truck camera yet
- **Date:** 2026-11-01, decided 2026-11-09

## Context

Critical engine alerts must stay visible on every screen, including a
full-screen reverse camera. On AGL there are two credible ways to show video:

- a Flutter texture fed by GStreamer
- a separate GStreamer `waylandsink` surface raised through agl-compositor's
  `agl-shell` roles

GStreamer with V4L2 is in our images from meta-f250 `6114c52` (1.28.5,
[BENCH]). The plan was to build both on the Pi 5 with one UVC camera, measure
glass-to-glass latency, CPU and GPU load, startup time and whether alerts
stay visible, and pick the option that keeps alerts visible with latency the
owner accepts. The camera *policy* is independent of this and is
implemented first (`crates/camera-policy`).

## Decision

**Option B** (findings below): camera-manager shows each camera in its own
`waylandsink` window, and the dashboard confines app windows to an area below
its status bar and alert-banner strip, with `[window_activation_area]` in its
`config.toml`.

1. **Alerts stay visible by layout.** The status bar and the alert banner's
   strip (y 0–96 at 800×480 today) are never covered. The camera is never
   drawn over them, and they are never drawn over the camera.
2. **The camera runs in camera-manager's process,** not the dashboard's. A
   camera or pipeline crash can't take the dashboard down.
3. **flutter-auto stays as AGL ships it** (Vulkan, no extra plugins).
4. **Latency accepted:** about 90 ms glass to glass with the webcam (owner,
   2026-11-09). Each new camera or capture device is measured again with
   [`tools/dev/latency-clock.html`](../../../tools/dev/latency-clock.html).

Option A was not built: it would switch the dashboard's renderer from Vulkan
to GL and add ffmpeg, for an in-process copy of every frame. Option C wasn't
needed.

## Consequences

**To build (Phase 6.6):**

- The activation area in `agl/flutter/config.toml`, sized from the dashboard's
  layout constants, and a test that the two agree. Changing it needs a
  compositor restart (the dashboard never restarts alone). *Done 2026-11-10
  (`make agl-test`), [SIM] until the next image or deploy.*
- While a camera shows, the dashboard keeps the alert banner's strip
  reserved even with no alert, and says on screen which camera is showing
  and why (reverse, the switch).
- camera-manager hides and shows its window with agl-shell's gRPC
  `DeactivateApp`/`ActivateApp` (127.0.0.1:14005) or by closing it, without
  restarting the camera if that is fast enough. Not built or measured yet.
- camera-manager's window must set an app id the compositor can address;
  plain `gst-launch` sets none.
- camera-manager needs the `video` group and the Wayland socket of the
  compositor's user (`agl-driver`), like the dashboard. *Done 2026-11-10 in
  its unit ([ADR-0026](0026-camera-manager-interfaces.md) decision 7), [SIM].*

**Accepted costs:**

- The picture is limited to the area: 800×320 if the nav bar stays (a 4:3
  camera shows at 427×320), more if the camera covers the nav bar.
- Touches on the camera window go to camera-manager, not the dashboard.
  Leaving a camera view is the switch (Forward/Press), reverse ending, or
  the dashboard's own controls outside the area.
- Alerts can only be drawn around the camera, never on top of it.

**Not measured:** GPU load, three cameras at once, the show/hide time, a
truck camera or capture device, and latency in daylight.

## Revisit if

- A truck camera's latency through this path isn't acceptable to the owner.
- The dashboard needs to draw over the camera (guide lines, alerts on top):
  then option C (a `comp_surf` subsurface) or A.
- A future AGL release changes the activation-area behaviour.

## Spike findings (2026-11-09)

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

**B's costs** (accepted above):

- The area is fixed when the dashboard starts. The dashboard must keep the
  alert banner's strip reserved while a camera shows, and the picture is
  limited to the area (800×320 with the nav bar kept, 427×320 for a 4:3
  camera).
- Alerts can only be drawn around the camera, never on top of it.
- Showing and hiding without restarting the pipeline needs a gRPC client
  for `DeactivateApp`/`ActivateApp` (127.0.0.1:14005), not built yet.
- Touches on the camera window go to camera-manager, not the dashboard.

**Latency:** about 90 ms glass to glass with the webcam (two readable
photos of five, 70–110 ms; all five under about 155 ms; the webcam's long
auto exposure in a dim room blurs the rest), measured with
`tools/dev/latency-clock.html` (bench-log 2026-11-09, "glass-to-glass
latency").
