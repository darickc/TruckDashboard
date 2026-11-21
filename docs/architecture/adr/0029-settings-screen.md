# ADR 0029 — A Settings tab; camera assignment and recording set through camera-manager

- **Status:** Accepted. [SIM] only: camera-manager's settings file, device
  scan and restart are tested on the Mac against a fake `/dev`, and the
  screen against a simulated and a fake camera-manager. Nothing has been
  assigned on the Pi yet
- **Date:** 2026-11-11
- **Amended by:** [ADR-0051](0051-five-way-switch-media-and-cameras.md)
  (2026-11-21): Settings › System › 5-way switch learns which of the
  switch's wires is which direction, through power-manager
- **Refines:** [ADR-0027](0027-front-and-rear-recording.md) decision 11
  ("a settings screen, through camera-manager's API, as camera assignment
  will, comes later"), [ADR-0026](0026-camera-manager-interfaces.md),
  [ADR-0028](0028-day-night-and-backlight.md)

> **Amended by [ADR-0034](0034-home-buttons-and-back.md) (2026-11-11):** there
> are no tabs any more. Settings is a screen opened from Home, with Back at
> its top left, and Power and Restart at the right of its section buttons.

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


## Amendment: Units inside Display; theme and brightness controls (2026-11-18)

From the design review (owner, 2026-11-18: "Settings Display"). Display and
Units were both mostly empty sections, so decision 1 changes:

- **Units moves into the Display section**, under a divider; Settings has
  three sections (Display, Cameras, Speakers), then Diagnostics, Restart and
  Power ([ADR-0034](0034-home-buttons-and-back.md) amendment, 2026-11-14).
  Units is still the dashboard's own, kept in its settings file.
- **Each setting is a row**: its name (and a dim line) on the left, its
  controls on the right.
- **Theme: Auto, Day, Night.** Auto is always shown; while power-manager
  isn't connected it is dim and not tappable, and the line under the
  choices says why (as before). It used to be left out, which hid that it
  exists.
- **Brightness: − and + around a ten-step bar** (one step per 10 %), the
  level under it and "Night · min 10 %" under its name; the same
  10 % steps and floor as before (ADR-0028).

[SIM]: `test/widget/display_test.dart` (Auto unavailable and connected, the
bar's steps, the section under an alert in both themes) and
`settings_test.dart`; checked in the browser at 800×480.


## Amendment: a System section (2026-11-18)

From the design review (owner, 2026-11-18: "Do the System page"). Settings
gains a fourth section, **System**: what the head unit says about itself on
the left, every service's link on the right. Nothing on it is vehicle data,
and nothing is checked anew: it gathers what the dashboard already reads.

| Line | From | When it can't be read |
|---|---|---|
| Dashboard | The commit this dashboard was built from: `F250_COMMIT`, set by `make deploy` ("+changes" for uncommitted files) and by the image's recipe (`F250_SRCREV`) | "not available: not recorded in this build" (the browser, `make ui`) |
| Image built from | `F250_SRCREV` in `/etc/f250-release` (f250-system writes it at image build), shown as the short commit. Older than Dashboard after a `make deploy` | "not available: no /etc/f250-release" (the Mac window, a Raspberry Pi OS install) |
| Image | `PRETTY_NAME` in `/etc/os-release` | "not available: …", naming the file |
| Up for | `/proc/uptime` | "not available: …", naming the file |
| CPU temperature | `/sys/class/thermal/thermal_zone0/temp` (and its `type`), in the driver's units; a zone whose type isn't a CPU's is named | "not available: …", naming the file |
| Data drive | camera-manager's recording report (free space and video) | "not reported (needs camera-manager)"; "not reported while recording is off" (camera-manager says nothing of the drive then) |

The facts are read when the section opens and every 5 s while it shows
(`lib/core/system_info.dart`; the browser preview has none and says so:
"not available: the browser preview has none").
No temperature limit is shown or warned about: that would be a threshold,
and thresholds are configuration (CLAUDE.md rule 10).

Services, each a dot and a word or two from the link the dashboard already
follows: vehicle data, cameras, audio and phone, power manager, GPS
position, routing, saved places, USB export, map. Simulated sources say
"simulated" (vehicle data: "in-app simulator").

Restart and Power stay at the right of the section row (ADR-0034); the
mockup's place for them on this page wasn't taken.

**On the Pi** ([BENCH], bench log 2026-11-19): the dashboard's service
(User=agl-driver, ProtectSystem=strict, ProtectProc=invisible) reads
`/etc/f250-release`, `/etc/os-release`, `/proc/uptime` and
`/sys/class/thermal/thermal_zone0`; zone 0's type is `cpu-thermal`. The
first deploy showed two mistakes, fixed the same day: "Software" was the
image's commit while a newer dashboard ran (now Dashboard and Image built
from, apart), and "Data drive: not mounted" while the drive was mounted
and recording off (now "not reported while recording is off").

[SIM]: `test/unit/system_info_test.dart` (each file's parser, every file
present, a missing or garbled file) and `test/widget/system_settings_test.dart`
(the facts in both unit systems, unknown facts, the data drive, every
service, under an alert in both themes); checked in the browser at 800×480.

## Amendment: the Cameras section as cards (2026-11-19)

From the design review (owner, 2026-11-19: "Do the next screen", after the
Settings › Cameras proposal). Decisions 3–6 stand (a draft until Apply,
which restarts camera-manager; the source shown; Use /etc/default/f250;
only front and rear record); the layout changes:

- **A card per camera**, front and rear (the two that can record, ADR-0027
  decision 1) on top, left and right under them. Each says whether its
  device is plugged in ("plugged in", "not plugged in", "no camera").
- **The USB port is a 150 px button** with the port on one line and the
  camera's model (or "not plugged in") under it; it opens the picker as
  before.
- **Record | Live only** for front and rear, two 60 px buttons like
  Display's choices, instead of one "Record: on/off" toggle. Left and right
  say "Live only · only front and rear record" where the choice would be.
- **Why nothing records** (decision 5) sits under the cards, across the
  width.
- **One bottom row**: what Apply would do (or what it did) and where the
  settings come from on the left, then Use /etc/default/f250 (when set on
  this screen), Rescan, Undo and Apply. Apply is filled once something
  changed, dim and unfilled until then.
- Under an alert banner the section scrolls instead of squeezing the 60 px
  controls.

[SIM]: `test/widget/settings_test.dart` (the cameras tests through the new
controls; the layout: front and rear on top, Record | Live only, every
button ≥ 60 px inside 800×480, the reason under the cards, Apply filled once
changed) and the 800×480 states in both themes; checked in the browser at
800×480.
