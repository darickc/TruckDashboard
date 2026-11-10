# ADR 0026 — camera-manager runs one `gst-launch` pipeline at a time and serves `f250.camera.v1`

- **Status:** Accepted. [BENCH] 2026-11-10 on the Pi with two webcams
  ([bench-log](../../hardware/bench-log.md)): the unit and its sandbox
  (decision 7), frame counting through `identity` (decision 3, one line per
  frame on GStreamer 1.28.5), the no-frozen-frame rule (decision 4), and
  a stop with a camera live (fixed that day: it hung until SIGKILL).
  [ADR-0027](0027-front-and-rear-recording.md) (accepted 2026-11-10) will
  supersede decision 3 and narrow decision 2 to unrecorded cameras once
  recording is built
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

1. **An API, `f250.camera.v1`,** on `unix:/run/f250-camera/camera.sock`
   ([camera.proto](../../../shared/proto/f250/camera/v1/camera.proto)). Not
   in the gateway's `/run/f250`: only the `f250` user writes there, and
   camera-manager runs as `agl-driver` (decision 7):
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
6. **power-manager passes each switch move to `Move`** (added 2026-11-10,
   `services/power-manager/src/camera_link.rs`). The power key comes first,
   so the link can never hold up power-manager's loop:
   - Sending never waits: moves go into a queue of four, and a move that
     finds it full is dropped and logged.
   - One task makes the calls, each with a timeout (`--camera-call-timeout-ms`,
     1000 ms, an example).
   - A move that waited longer than `--camera-move-max-age-ms` (1000 ms, an
     example) is dropped, not sent, so the camera never changes long after
     the switch moved.
   - A failed move isn't retried: the driver moves the switch again.
   - The connection is lazy, so either service can start first or restart.
   - power-manager logs what became of each move: the view camera-manager
     answered with, or why it wasn't taken.
   - `CAMERA_MANAGER` in the unit (default `unix:/run/f250-camera/camera.sock`) says
     where; set it empty to only log the moves.

7. **Packaged like the other services** (added 2026-11-10):
   `f250-camera-manager.service`, in `make deploy` and both images.
   - User `agl-driver`, as the dashboard: its windows need the compositor's
     Wayland socket in `/run/user/1001`. Group `f250`, so the API socket
     (mode 0770) is open to power-manager. `video` for the cameras.
   - Not bound to the compositor: a compositor restart ends the pipeline,
     and decision 4 restarts it.
   - Cameras come from `CAMERA_FRONT` (added 2026-11-10, ADR-0024 amended),
     `CAMERA_LEFT`, `CAMERA_RIGHT` and `CAMERA_REAR` in
     `/etc/default/f250` (`camera-start`), all empty by default: no truck
     camera is chosen yet.
   - Sandboxed like the dashboard (ADR-0021), with two exceptions said in
     the unit: no `MemoryDenyWriteExecute` (GStreamer's orc compiles code
     at run time) and no `ProcSubset=pid` (orc reads `/proc/cpuinfo`).
     Devices: `char-video4linux` only.
   - The dashboard bundle's `config.toml` sets the activation area
     (ADR-0009): y 96–416, from the dashboard's layout constants; `make
     agl-test` checks the two agree.
   - `camera-ctl` (`move back`, `view`, `watch`) sends moves and shows the
     view by hand, for the bench before the switch is wired.

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
- Not in this step: the dashboard's camera view and indicators (Phase 6.6).
  Until a camera device is set in `/etc/default/f250`, every camera shows
  as unavailable when chosen.
- Decision 7 is `[SIM]`: `make agl-test` checks the unit, `camera-start`
  and the activation area; nothing has run on the Pi. To check on the
  bench ([agl.md](../../setup/agl.md) check 14): the socket's owner and
  mode, power-manager reaching it, a `waylandsink` window from inside the
  sandbox, the GStreamer registry in `/var/cache/f250-camera`, and whether
  orc works with `MemoryDenyWriteExecute=yes` after all.
- Decision 6 is `[SIM]`: six tests against a fake camera-manager on a unix
  socket (delivery, absent, restart, slow, old moves, a full queue), and
  both real binaries end to end on the Mac with switch events written into
  a FIFO and a fake `gst-launch`.

## Revisit if

- The `identity` output can't be relied on, or `gst-launch` misbehaves on
  the Pi: gstreamer-rs.
- The start time on a camera switch is too slow: warm pipelines with
  hide/show.
