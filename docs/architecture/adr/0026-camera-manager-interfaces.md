# ADR 0026 — camera-manager runs one `gst-launch` pipeline at a time and serves `f250.camera.v1`

- **Status:** Accepted. [SIM] only: the daemon runs on the Mac against a fake
  `gst-launch`. Frame counting through `identity` (decision 3) is
  UNVERIFIED on the Pi
- **Date:** 2026-11-09
- **Builds on:** [ADR-0009](0009-camera-rendering.md) (a camera window in an
  activation area), [ADR-0024](0024-camera-selection-switch-and-can-reverse.md)
  (reverse and the switch), [ADR-0025](0025-camera-switch-through-gpio-key.md)
  (power-manager reads the switch)

## Context

`crates/camera-policy` decides which camera shows. Something has to feed it
(switch moves, reverse, speed, whether a camera has frames), run the
pipelines, and tell the dashboard what is on screen, so it can draw the
banner strip, the "Camera unavailable" panel and the reverse indicator. The
dashboard never touches cameras, and camera-manager owns the V4L2 devices
([overview](../overview.md)).

## Decision

1. **An API, `f250.camera.v1`,** on `unix:/run/f250/camera.sock`
   ([camera.proto](../../../shared/proto/f250/camera/v1/camera.proto)):
   - `WatchView`: the view now, then again on every change: which camera and
     why, the feed's state (starting, live, unavailable and why), the
     reverse status and whether the speed limit hides the choice.
   - `Move`: a switch move. power-manager calls it with each debounced move;
     the dashboard may call it too (on-screen buttons).
2. **One pipeline at a time, only for the camera on screen.** camera-manager
   starts it when the view picks a camera and stops it when the view moves
   on. Starting the pipeline opens the camera's window; stopping it closes
   the window. The first frame took 0.62 s on the bench (bench-log
   2026-11-09), so the dashboard shows "Starting" until frames arrive.
3. **The pipeline is a `gst-launch-1.0` child process**, built from the
   camera's device:

   ```
   gst-launch-1.0 -v v4l2src device=DEV ! CAPS ! videoconvert
     ! identity name=f250_frames silent=false ! waylandsink
   ```

   `CAPS` defaults to `image/jpeg,width=640,height=480,framerate=30/1 !
   jpegdec`, the bench pipeline. With `-v`, `identity` reports every buffer
   on stdout, and camera-manager counts those lines as frames (UNVERIFIED:
   to check on the Pi). `--gst-launch` replaces the program, which is how
   the tests run without GStreamer.
4. **No frozen frames.** No frame for `--frame-timeout-ms` (1000 ms, an
   example) or the process ending marks the camera unavailable and **kills
   the pipeline**, which closes its window. waylandsink would otherwise keep
   the last frame on screen over the dashboard's panel. It is restarted after
   a backoff (1 s doubling to 10 s, examples) for as long as the view wants
   that camera.
5. **Reverse and speed are not read yet.** Automatic reverse is off until the
   `230` decoder is verified (ADR-0024), and the speed limit is off by
   default, so camera-manager doesn't connect to the gateway. When either is
   switched on, it subscribes to the gateway's snapshots; it never asks the
   gateway to transmit.

## Options considered for the pipeline

1. **`gst-launch-1.0` as a child process** (chosen). Exactly the pipeline
   measured on the bench. A crash in GStreamer or a driver ends the child,
   not camera-manager. No new Rust dependencies and no GStreamer headers in
   the cross build.
2. **gstreamer-rs in-process.** Proper bus messages and pad probes instead
   of parsing text, but a large binding to cross-compile in Yocto, and a
   pipeline crash takes the daemon down.
3. **A small C helper.** Nothing that option 1 lacks today.

## Consequences

- GStreamer calls `gst-launch-1.0` a debugging tool; its `-v` output isn't a
  stable interface. The frame count depends on the line
  `f250_frames: last-message = chain` and is checked on the bench before
  being trusted. If it changes or proves unreliable: option 2.
- Every switch to a camera costs a pipeline start (about 0.6 s). Keeping
  pipelines warm and hiding windows needs an app id on the window
  (`waylandsink` sets none) and agl-shell's gRPC; revisit if the start time
  bothers the owner.
- One camera at a time. A split view would need more.
- Not in this step: power-manager calling `Move`, the dashboard's camera
  view, the activation area in the dashboard's `config.toml`, the systemd
  unit and the image. They follow in Phase 6.6.

## Revisit if

- The `identity` output can't be relied on, or `gst-launch` misbehaves on
  the Pi: gstreamer-rs.
- The start time on a camera switch is too slow: warm pipelines with
  hide/show.
