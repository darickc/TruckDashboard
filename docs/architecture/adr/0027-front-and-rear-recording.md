# ADR 0027 — Front and rear cameras record like a dashcam, kept by retention settings

- **Status:** Proposed (2026-11-10). Nothing built or measured: every figure
  below is an estimate to check on the bench first (see "To measure")
- **Date:** 2026-11-10
- **Builds on:** [ADR-0026](0026-camera-manager-interfaces.md) (camera-manager),
  [ADR-0024](0024-camera-selection-switch-and-can-reverse.md) (the front
  camera, amended 2026-11-10), [ADR-0009](0009-camera-rendering.md) (a
  camera window in an activation area), [ADR-0016](0016-stage1-sideload-layout.md)
  and [ADR-0022](0022-grow-root-on-first-boot.md) (the `f250-data` drive)
- **Amends:** ADR-0026 decisions 2 and 3, if accepted (below)

## Context

The owner wants the front and rear cameras recorded while driving, like a
dashcam, keeping only so much: so many days, so many recordings, so much
space (2026-11-10). Left and right are only for looking, not recording.

What constrains it:

- **The Pi 5 has no hardware H.264 encoder** (or H.264 decoder). Raspberry
  Pi's white paper says its software encoder (libx264 on the four A76
  cores) does 1080p30 in real time: one stream, measured on an otherwise
  idle Pi ([compatibility matrix](../../hardware/compatibility-matrix.md#cameras-and-video)).
  The dashboard and the gateway share those cores.
- **A V4L2 camera is normally streamed by one process at a time.** Today
  camera-manager runs a `gst-launch-1.0` child only for the camera on screen
  (ADR-0026 decisions 2 and 3). A camera that records all the time and is
  sometimes shown must have both from one capture.
- **USB.** RP1 has two USB controllers, each with one USB 3 and one USB 2
  port (V, Raspberry Pi docs). A USB 2 bus budgets about 384 Mbit/s for
  video, and `uvcvideo` reserves bandwidth by a camera's declared maximum,
  so two cameras on one bus can refuse to start even when their real
  traffic would fit (F).
- **Storage.** Continuous video would wear out the SD card and could fill
  it. The project already has a data drive (`f250-data`, NVMe HAT or USB
  SSD, `DATA_DRIVE=1`), and the recorder refuses to write to the SD card
  without it.
- **Power.** Ignition off → OFFDELAY (1 min) → the PSW pulse → power-manager
  shuts down → the supply cuts power later
  ([power-states.md](../power-states.md)). A crash or a blown fuse cuts power
  with no warning.
- **Time.** The RTC battery isn't fitted yet (H20): until it is, the clock
  starts each boot at the last shutdown time and jumps when NTP answers, if
  it ever does in the truck.

## Decision

1. **Front and rear record continuously while the head unit runs**, which is
   while the ignition is on plus OFFDELAY. Each is a setting, on by default
   once that camera has a device. Left and right are never recorded. No
   audio, ever.
2. **Each recorded camera is captured once and feeds two branches**:
   `v4l2src ! tee`, with a recording branch that always runs and a display
   branch (decode, `waylandsink`) linked only while that camera is on
   screen. This needs GStreamer **in camera-manager's process**
   (gstreamer-rs), the fallback ADR-0026 already names:
   - It replaces the `gst-launch` children for every camera, so there is one
     way to run a pipeline. A camera that isn't recorded still runs only
     while shown (ADR-0026 decision 2 stays for left and right).
   - Frames are counted with a pad probe, not by parsing `gst-launch -v`
     output, which also settles ADR-0026's UNVERIFIED frame count.
   - The no-frozen-frame rule stays: no frames for `--frame-timeout-ms` →
     the display branch is removed, its window closes, and the view says
     unavailable. A recording branch that stops getting frames marks the
     recording failed (decision 8) and the pipeline restarts with backoff.
   - What is lost: a GStreamer crash now takes camera-manager down with it.
     systemd restarts it (`Restart=on-failure`, the watchdog), and the
     dashboard already shows no camera while it is gone (rule 4).
3. **Record what the camera sends; don't re-encode by default.**

   | Camera sends | Recorded as | Pi CPU |
   |---|---|---|
   | H.264 (a UVC H.264 camera) | H.264 as it comes | parsing only |
   | MJPEG | MJPEG as it comes | muxing only |
   | Raw (YUYV) | not recorded; MJPEG or H.264 required | — |

   Re-encoding MJPEG to H.264 (`x264enc`) is a per-camera option, off,
   allowed only after the bench shows the headroom. Resolution and frame
   rate are per-camera settings; 1280×720 at 30 fps is the example default.
   Showing an H.264 camera needs a software H.264 decoder on the Pi; whether
   the image has one, and what it costs, is UNVERIFIED. Many H.264 UVC
   cameras also offer MJPEG on a second stream, which the display branch can
   use instead.
4. **One-minute segments in Matroska** (`splitmuxsink`, `matroskamux`).
   Segment length is a setting (60 s, an example). A power cut loses at most
   the segment being written, and Matroska stays playable up to its last
   complete cluster; both are to be shown by pulling the power on the bench.
   On a clean stop (SIGTERM at shutdown) each pipeline gets an end-of-stream
   so the last segment is finished.
5. **Recordings live only on the data drive**, in
   `/var/lib/f250/storage/video/<camera>/`. With no drive mounted, nothing
   records, the Cameras tab says why, and the SD card is never used, as the
   recorder already does with `DATA_DRIVE=1`.
6. **Retention: oldest first, by settings that are examples, not
   recommendations.** A pass runs before each new segment and once a minute:

   | Setting | Example | Meaning |
   |---|---|---|
   | `RECORD_MAX_AGE_DAYS` | 7 | Delete segments older than this |
   | `RECORD_MAX_GB` | 200 | Video (front and rear together) may use at most this |
   | `RECORD_MIN_FREE_GB` | 20 | Always leave this much free on the drive (telemetry shares it) |
   | `RECORD_MAX_SEGMENTS` | 0 (off) | At most this many segments per camera |
   | `RECORD_SEGMENT_S` | 60 | Segment length |

   Whichever limit bites first wins. The segment being written is never
   deleted. Deleting is whole segments, never a truncation.
7. **Protected clips.** "Save clip" (a dashboard button; a switch gesture
   later, if the switch allows one) protects the current segment and the
   ones around it (2 minutes before and 1 after, examples) by moving them to
   `video/protected/`. Retention never deletes protected clips; they have
   their own cap (`RECORD_PROTECTED_MAX_GB`, example 20). When the cap is
   full, a new save is refused and says so, rather than deleting an older
   saved clip.
8. **Recording state is visible and never claimed.** `f250.camera.v1` gains a
   recording status per camera (recording, not recording and why, drive
   free space), and later the settings and "save clip" calls. The dashboard
   shows a REC indicator per camera only while camera-manager reports it.
   A recorded camera that stops recording raises an advisory alert ("Front
   camera not recording: no frames"), so a dead dashcam isn't discovered
   after the incident it missed.
9. **Timestamps are labelled by what the clock knows.** Each segment's name
   carries the boot number and a sequence (`b0042-s00317`), and the wall
   time only when the clock is trusted (`timedatectl` says synchronized, or
   the RTC is set: H20). An index file per camera records both. A segment
   recorded on an untrusted clock is never named with a wrong date as if it
   were right (CLAUDE.md rule 4, applied to time).
10. **Settings live in `/etc/default/f250` for now** (`RECORD_CAMERAS=front,rear`
    and the table above), read by `camera-start`. A settings screen (the
    dashboard, through camera-manager's API, as camera assignment will) comes
    later.

## Options considered

1. **gstreamer-rs in camera-manager, one capture per camera with a `tee`**
   (chosen). One process owns each camera, so display and recording can't
   fight over it, and frame counting is a real API.
2. **A recorder process per camera, plus a second consumer for display.**
   Needs the camera shared between processes: PipeWire's camera nodes or
   `v4l2loopback`. PipeWire camera sharing on this image and the
   `v4l2loopback` module (out of tree) are both UNVERIFIED, and either adds
   a moving part between the camera and the screen.
3. **Keep `gst-launch`, with the display window always open and hidden.**
   Hiding needs agl-shell to address the window, and `waylandsink` sets no
   app id (ADR-0009). Not possible today.
4. **Re-encode everything to H.264 on the Pi.** Smallest files from any
   camera, but at least one core per 1080p stream on a Pi that also draws
   the dashboard. Kept as an option, not the default.

## Consequences

- ADR-0026 decision 3 (`gst-launch` children) is superseded once this is
  built, and decision 2 holds only for cameras that aren't recorded.
- **The image needs more GStreamer:** the `matroska` and `multifile`
  (`splitmuxsink`) plugins from gst-plugins-good; neither is in the
  `6114c52` manifest. Package names to take from the build's package list,
  not guessed. The build needs GStreamer's headers for gstreamer-rs, and
  `f250-services-crates.inc` grows.
- **Camera choice (new question H33):** H.264 UVC cameras for front and rear
  would keep the Pi's CPU free and the files small; MJPEG cameras work but
  need much more drive. One camera per USB controller.
- **The data drive becomes a requirement** for recording, and its size
  decides the retention that's possible. At 2 hours of driving a day, about
  10 GB/hour writes roughly 7 TB a year, within a normal NVMe drive's
  rating.
- **Heat:** two cameras recording all the time, in a truck cab, need the
  Pi's active cooler.

### Estimates, front and rear together (UNVERIFIED)

| Recorded as | Bitrate per camera (est.) | Per hour, both | 200 GB holds |
|---|---|---|---|
| H.264 1080p30 from the camera | 4–8 Mbit/s | 3.5–7 GB | 28–57 h |
| MJPEG 720p30 as it comes | 15–30 Mbit/s | 13–27 GB | 7–15 h |
| MJPEG 1080p30 as it comes | 30–60 Mbit/s | 27–54 GB | 4–7 h |

MJPEG bitrates depend heavily on the scene and the camera's quality setting.

### To measure on the bench before building (webcam first, then the chosen cameras)

1. CPU and write rate: MJPEG as it comes into Matroska segments, 640×480 and
   the camera's highest MJPEG mode, with and without the display branch.
2. `x264enc` at 720p30 and 1080p30 (`ultrafast`, `superfast`): CPU while the
   dashboard runs.
3. Two cameras at once, on one USB controller and on two.
4. Pull the power mid-segment: is the cut segment playable, and up to where?
5. A clean shutdown: is the last segment finished within the shutdown time?

## Open for the owner

- Accept the move to gstreamer-rs (decision 2)?
- The retention examples (7 days, 200 GB, 20 GB free): replace with your
  numbers, or keep as examples until the drive is chosen (H31).
- Should "save clip" also have a switch gesture (e.g. a long press), once
  the switch is chosen (H32)?

## Revisit if

- The bench shows `x264enc` fits two 720p streams with room to spare: make
  H.264 the default for MJPEG cameras.
- gstreamer-rs proves hard to build in meta-f250: option 2, with whichever
  camera sharing the image supports.
- A camera's H.264 can't be shown without an expensive software decode: use
  its MJPEG stream for display, or record MJPEG.
