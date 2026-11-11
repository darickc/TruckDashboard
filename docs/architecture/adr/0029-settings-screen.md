# ADR 0029 — A Settings tab; camera assignment and recording set through camera-manager

- **Status:** Accepted. [SIM] only: camera-manager's settings file, device
  scan and restart are tested on the Mac against a fake `/dev`, and the
  screen against a simulated and a fake camera-manager. Nothing has been
  assigned on the Pi yet
- **Date:** 2026-11-11
- **Refines:** [ADR-0027](0027-front-and-rear-recording.md) decision 11
  ("a settings screen, through camera-manager's API, as camera assignment
  will, comes later"), [ADR-0026](0026-camera-manager-interfaces.md),
  [ADR-0028](0028-day-night-and-backlight.md)

## Context

The driver's settings were scattered: day/night and units under
Diagnostics → Developer, which is a developer's page, and camera assignment
and recording only in `/etc/default/f250`, which needs SSH. Assigning
cameras by USB port is a job done in the truck with the screen in front of
you: plug a camera in, see which port it is on, say what it is.

The dashboard runs sandboxed as `agl-driver` and must never write system
files; `/etc/default/f250` is root's and a conffile. camera-manager runs as
`agl-driver` too, reads the cameras once at start, and builds its pipelines
(and recording) from them.

## Decision

1. **A Settings tab** (gear icon, between Cameras and Diagnostics) with
   three sections: **Display** (moved from Developer; ADR-0028), **Cameras**
   (assignment and recording), **Units** (moved from Developer). Developer
   keeps the simulator and the speed-calibration procedure: those are
   procedures, not preferences.
2. **The dashboard's own preferences** (units, the gauge profile) are kept
   in a JSON file named by `F250_SETTINGS_FILE`
   (`/var/lib/f250-dashboard/settings.json`, its state directory, on AGL).
   Without the variable (the browser, the Mac window, tests) they last until
   the app stops. A damaged file is ignored, with the defaults.
3. **Camera assignment and recording go through camera-manager**
   (`f250.camera.v1`, two new calls):
   - `GetCameraSettings`: the four cameras' devices, the cameras recorded,
     where those came from, whether recording is possible, and the cameras
     plugged in now: each `/dev/v4l/by-path/*-video-index0` (the USB port),
     labelled with its `/dev/v4l/by-id` name (the camera's model) when one
     points at the same device.
   - `SetCameraSettings`: saves them to camera-manager's state directory
     (`/var/lib/f250-camera/settings`), then camera-manager **restarts
     itself in place**: a clean stop (recordings finished, the clean-stop
     marker written), then `exec` of itself with the same arguments. Same
     PID, so systemd sees no failure and no start limit applies. The cameras
     are off for a few seconds and the screen says so before you apply.
   - **Refused while a camera is on screen**, so a rear view never vanishes
     because of a settings change.
   - A device must be an absolute path under `/dev` with no spaces; the four
     cameras can't share one.
4. **Precedence: the screen's file, once saved, replaces the
   `/etc/default/f250` cameras and `RECORD_CAMERAS` as a whole.** The
   screen says which applies ("Set on this screen" or "From
   /etc/default/f250") and offers **Use /etc/default/f250**, which deletes
   the file. camera-manager logs which it used at every start.
5. **Recording still needs the data drive** (ADR-0027 decision 6):
   `camera-start` passes `--recording-allowed` only with `DATA_DRIVE=1`.
   Without it, or on a build that can't record, the screen shows why and
   the record switches are off. Only front and rear can record, and only
   with a device (ADR-0027 decision 1).
6. Retention numbers stay in `/etc/default/f250`: they are set once for the
   drive that is fitted (H31), not adjusted from the driver's seat. The
   Cameras section shows nothing it can't change.

## Consequences

- Editing `CAMERA_*` in `/etc/default/f250` has no effect once settings were
  saved on screen; the journal and the screen both say so.
- camera-manager needs a state directory (`StateDirectory=f250-camera`).
- Which physical camera sits on which USB port still has to be checked by
  looking at the picture: assign, then show it with the camera buttons.

## To verify on the Pi

- `/dev/v4l/by-path` and `/dev/v4l/by-id` are visible inside
  camera-manager's sandbox (`DevicePolicy=closed` hides nothing in `/dev`'s
  directory listing, only access to devices)
- the in-place restart: READY again, no watchdog kill, the socket back
  within seconds, a recording stopped cleanly (no protected minutes)
- the dashboard's settings file survives a reboot
