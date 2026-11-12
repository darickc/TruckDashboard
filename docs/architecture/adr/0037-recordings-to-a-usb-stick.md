# ADR 0037 — Dashcam recordings are copied to a USB stick from the dashboard, by a small service of their own

- **Status:** Accepted (asked for by the owner, 2026-11-11). [SIM]: cargo
  tests with a directory standing in for the stick, widget tests at 800×480
  against a simulated service, `make agl-test` for the unit and packaging.
  Not yet on the Pi with a real stick (bench check 19 in
  [agl.md](../../setup/agl.md)).
- **Date:** 2026-11-11
- **Refines:** [ADR-0027](0027-front-and-rear-recording.md) (what happens to
  the recordings), [ADR-0033](0033-map-updates-by-usb-stick.md) (USB sticks),
  [ADR-0034](0034-home-buttons-and-back.md) (the first screen not on Home:
  it is opened from Cameras)

## Context

camera-manager records front and rear into one-minute Matroska segments on
the data drive (`/var/lib/f250/storage/video/{front,rear,protected}/`,
ADR-0027). The owner needs to get them off the truck, after an incident or
to keep a trip, without a laptop and SSH. A USB stick plugged into the Pi is
the obvious carrier: the map update already uses one (ADR-0033).

Constraints:

- The dashboard never touches devices or the data drive (CLAUDE.md rule 5):
  it lists, chooses and shows progress through a service API.
- Mounting a stick takes `CAP_SYS_ADMIN`. camera-manager runs as
  `agl-driver` with no capabilities at all, in a sandbox that can only reach
  cameras; it also draws the camera on screen and records. Loosening that
  sandbox for a copy is the wrong trade.
- The map import (`f250-map-import@`, ADR-0033) already starts for every
  exFAT or FAT USB stick, mounts it read-only in its own namespace, and
  quietly ignores sticks without `f250/map.pmtiles` or `f250/routing.tar`.
  Exporting needs a writable mount, and the two must not fight over a stick.
- A stick can be pulled at any moment, can be full, read-only (a switch, or
  a damaged filesystem), FAT32 (4 GiB file limit) or not FAT at all.

Options considered for where the copy runs:

| Option | For | Against |
|---|---|---|
| A. camera-manager (`f250.camera.v1`) | Owns the recordings | Needs `CAP_SYS_ADMIN` and block devices in the sandbox that runs the cameras; a stuck stick would sit in the process that records |
| B. A udev-started script like `map-import`, with a status file | Same shape as the map stick | The dashboard has to choose which recordings: that's a request, not a file it can read. A status file plus a request file is an API in disguise |
| **C. A small daemon, `services/usb-export`, serving `f250.export.v1`** (chosen) | Its own tight sandbox (root for `mount(2)` only); a real API for list/choose/progress; testable without a stick | One more service and unit |

Options considered for how the map stick and the export stick coexist:

| Option | For | Against |
|---|---|---|
| **A. A stick with `f250/map.pmtiles` or `f250/routing.tar` is a map stick; any other exFAT/FAT stick can take recordings** (chosen) | No setup: any stick works; the map import is unchanged | A map stick can't also carry recordings |
| B. Mark export sticks (a label or a folder) | Explicit | One more thing to get right before an incident |
| C. One stick for both | One stick | Two services writing and reading the same stick; the map import mounts read-only and would race a writable mount |

## Decision

1. **`services/usb-export`** (binary `usb-export`, unit
   `f250-usb-export.service`) copies recordings to a USB stick and serves
   **`f250.export.v1`** on `/run/f250-export/export.sock`:
   `ListRecordings`, `WatchExport` (the sticks and the copy, streamed),
   `StartCopy`, `CancelCopy`. **Copy only**: nothing in the API moves or
   deletes anything on the data drive, and the service's view of the drive
   is read-only (`ProtectSystem=strict`, no `ReadWritePaths`).
2. **Finding sticks: polled, no udev rule.** Every 2 s it reads
   `/sys/class/block` (block devices whose sysfs path runs through a USB
   controller) and udev's database `/run/udev/data/b<maj>:<min>` (`ID_FS_TYPE`,
   label, vendor and model). Each filesystem on a stick is listed; a stick
   with none is listed as unusable so the screen can say why. Polling keeps
   the map import's udev rule the only one that reacts to a stick.
3. **What a stick is** (`StickRole`), decided when it appears:
   - not exFAT or FAT, or no filesystem → **unusable**, "format the stick as
     exFAT on a computer";
   - exFAT or FAT: mounted **read-only** for a moment
     (`ro,nosuid,nodev,noexec,noatime`) in the service's own mount namespace;
     with `f250/map.pmtiles` or `f250/routing.tar` it is a **map stick**,
     left to the map import and never written; otherwise an **export stick**,
     with its free space. Then it is unmounted again.
   - The kernel's read-only flag (a write-protect switch) is shown and
     refuses a copy.
4. **The copy** (`StartCopy` with the stick and the recordings, named as the
   list named them):
   - Each recording is looked up in the service's own scan of the drive; a
     name it doesn't find, or the newest segment of a camera changed in the
     last 15 s (still being written), is refused by name. Nothing from the
     request is used as a path.
   - Refused while another copy runs, while the map import's lock
     (`/run/f250-maps/import.lock`) exists, or on a stick that isn't an
     export stick.
   - The stick is mounted **read-write only for the copy**, in the service's
     namespace. If it comes up read-only anyway (`mount` falls back on a
     write-protected stick), the copy fails as read-only.
   - Files go to **`F250-recordings/`** on the stick, in the drive's layout:
     `front/`, `rear/`, `protected/<camera>/` for saved clips. A file already
     there with the same size is skipped, so copying again after a pulled or
     full stick finishes the job.
   - Before writing: room for what isn't there yet plus 16 MB, and FAT's 4 GiB
     limit per file. A full stick fails before anything is written.
   - Each file is written as `<name>.part`, `fsync`ed, then renamed: a file
     with its real name on the stick is always complete. Oldest first.
     Progress (files, bytes, the file being copied) is published at most 4
     times a second.
   - A recording deleted by retention (or moved by Save clip, which is then
     followed into `protected/`) after the list was read is counted as
     missing, not an error.
   - **However it ends** (done, cancelled, failed) the partial file is
     removed, the stick is synced (`syncfs`) and unmounted, and only then
     does the copy say **`safe_to_unplug`**. If unmounting fails it says so
     ("wait a minute before pulling it out").
   - Failures say what happened and how far it got: no stick, not enough
     room, the stick filled up, read-only, a file too big for FAT, removed
     during the copy (sysfs drops the device, or writes fail with EIO,
     ENODEV or ENXIO), a read error on the drive.
5. **The unit**: `User=root`, `Group=f250` (the socket is `root:f250` 0770
   for the dashboard; the recordings are readable through group f250 without
   `CAP_DAC_OVERRIDE`), `CapabilityBoundingSet=CAP_SYS_ADMIN`,
   `PrivateMounts=yes`, `DevicePolicy=closed` with `DeviceAllow=block-sd rw`,
   no network, `SystemCallFilter=@system-service @mount`, mount points in its
   runtime directory. `Nice=10` and best-effort I/O priority 7, below
   recording. The exFAT module is loaded before it starts, as for the map
   import.
6. **The dashboard**: Cameras has **Recordings to USB**, which opens a
   Recordings screen (Back returns to Cameras). On the left the recordings by
   run (the boot counter), camera and time (or "#n · no time" when the clock
   wasn't trusted, ADR-0027 decision 10), saved clips marked **SAVED**, the
   one being written marked and not selectable; filters All / Front / Rear /
   Saved. Tap to choose, **Range** then two taps for everything between,
   **All shown**, **Clear**. On the right the stick (name, filesystem, free
   space), the chosen size against it, **Copy n to stick**, then a progress
   bar with files and bytes, **Cancel copy**, the result, and **"Safe to
   unplug the stick."** only when the service says so. A tap on Copy that
   can't start says why. Without usb-export the screen says it isn't
   reachable; the in-app simulation is labelled SIMULATED.

## Consequences

- To get recordings off the truck: plug in any exFAT stick (FAT for small
  copies), Cameras → **Recordings to USB**, choose, **Copy**, wait for
  "Safe to unplug". On a computer the files are in `F250-recordings/`,
  Matroska segments that VLC and mpv play.
- A map stick can't carry recordings; that is on purpose (decision 3).
- Recording keeps running during a copy. The copy reads at low priority;
  how fast a copy runs, and whether it disturbs a recording, is
  **unmeasured** on the Pi.
- **UNVERIFIED on the Pi** until bench check 19: that `mount` works in the
  sandbox with `DeviceAllow=block-sd` and `@mount`, that udev's database
  lists a stick as described, that `syncfs` and the read-only fallback
  behave as decided, and the copy speed. Until then the feature is [SIM].
- If camera-manager ever writes segments over 4 GiB, FAT sticks refuse them
  by name; exFAT has no such limit.
