# ADR 0033 — Map updates by USB stick, onto the data drive

- **Status:** Accepted (owner, 2026-11-11). [SIM] only: `make agl-test` runs
  the import against folders, `map-stick.py` against a folder, and the
  dashboard's tests cover the status. Not run on the Pi, with a real stick,
  or with the NVMe drive yet
- **Date:** 2026-11-11
- **Refines:** [ADR-0030](0030-navigation-position-and-raster-map.md) (where the
  map file lives); part of Phase 6.5.3

## Context

A map is one PMTiles file, replaced whole: there are no partial updates. The
lower 48 states to zoom 15 are about 19 GB (a `pmtiles extract --dry-run` of
the 2026-11-11 Protomaps build), so a map belongs on the data drive (a
500 GB NVMe, owner 2026-11-11), not the SD card. Until now the dashboard read
`/var/lib/f250/maps/map.pmtiles` on the card, and replacing it meant `scp` and
restarting the dashboard.

Options considered for the update workflow:

| Option | For | Against |
|---|---|---|
| A. The Pi downloads the map itself on home Wi-Fi | No Mac, no copying | The truck stays on for the whole download; the Wi-Fi where it is parked is weak (owner) |
| B. The Mac pushes the file over Wi-Fi | Uses what exists | 19 GB over the same weak Wi-Fi |
| **C. A USB stick** (chosen, owner) | Fast (minutes), no network | Someone walks the stick to the truck |

## Decision

1. **The map lives on the data drive:** `/var/lib/f250/storage/maps/map.pmtiles`
   (`MAP_FILE` in the image and `deploy.sh`). Without the drive the screen says
   there's no map and still shows the position.
2. **The Mac writes the stick:** `make map-stick STICK=/Volumes/<name>`
   (`tools/maps/map-stick.py`) copies the map to `f250/map.pmtiles` and then
   writes `f250/map.pmtiles.sha256` (SHA-256 computed while copying). The
   checksum file is written last, so a stick pulled early is refused. The
   stick must be **exFAT** (FAT32 can't hold a file over 4 GB); FAT is
   accepted for a small map, anything else is refused.
3. **The Pi imports it when it is plugged in:**
   - `80-f250-map-stick.rules`: a USB block device with an exFAT or FAT
     filesystem starts `f250-map-import@<node>.service`.
   - `/opt/f250/libexec/map-import` mounts it **read-only, nosuid, nodev,
     noexec** in the unit's own mount namespace, and reads only
     `f250/map.pmtiles` and its checksum. Nothing on the stick is run. A
     stick without `f250/map.pmtiles` is left alone and nothing is shown.
   - Before copying: the checksum file is well-formed, the file is a PMTiles
     v3 map of vector, PNG, JPEG or WebP tiles, the data drive is mounted, and
     it has room for the map plus 64 MB.
   - It copies to `map.pmtiles.part` beside the old map, checks the copy's
     SHA-256 and header again, and only then renames it over `map.pmtiles`.
     Any failure, a full drive, a pulled stick or a power cut leaves the old
     map. A leftover `.part` is removed by the next import.
   - One import at a time (a lock in `/run/f250-maps`). The unit is bound to
     the stick: pulling it stops the unit, and `ExecStopPost` marks that
     stick's import failed.
   - The unit is sandboxed: it writes only `/var/lib/f250/storage` and its
     runtime directory, has no network, and may take an hour.
4. **The dashboard shows it and opens the new map without a restart.** The
   import writes `/run/f250-maps/status.json` (state `checking`, `copying`
   with a percentage, `updated` or `failed`, a message, an id). The dashboard
   reads it every second (`MAP_STATUS`): a chip in the status bar on every tab
   ("MAP 43%", "MAP UPDATED", "MAP UPDATE FAILED") and the message on the Nav
   tab. A finished import shows for 10 minutes. A new `updated` id reopens the
   map; the old file is closed, so its space is freed, and the vector layer
   gets a new tile cache, so no tile of the old map shows. An import that
   finished before the dashboard started isn't shown.
5. **The map's data date** (`f250:protomaps_build`, written by
   `make map-region`) shows beside its attribution, so you can tell which map
   is installed.
6. **On the Mac**, `make map-import-dev STICK=...` runs the same import into
   `/tmp/f250/maps/` with the status at `/tmp/f250/maps/status.json`, which
   `make ui` and `make sim` watch.

## Consequences

- An update is: `make map-region`, `make map-stick`, then plug the stick into
  the truck with the dashboard on (key at ACC or running) and wait for "MAP
  UPDATED". A 19 GB map takes minutes from a USB 3 stick and about ten from
  USB 2 (estimates from typical stick speeds, not measured). The checksum is
  computed on the Pi after the copy; how long that takes for 19 GB is
  unmeasured.
- The drive needs room for the old and the new map during an import (38 GB for
  the lower 48), which the 500 GB drive has.
- **UNVERIFIED on the Pi:** that the udev rule fires for a stick, that exFAT
  mounts in the unit (`kernel-module-exfat` is in the image; the unit loads it
  first), that `agl-driver` can read `/run/f250-maps/status.json`, and the
  copy and checksum times. Bench check 17 in [agl.md](../../setup/agl.md).
- macOS writes `._*` files on exFAT sticks; the import ignores them.
- Any USB stick with an exFAT or FAT filesystem starts the unit, which only
  looks for `f250/map.pmtiles`. A stick with that file is treated as a map
  update whoever made it, but is refused unless its checksum and header
  check out, and can only replace the map.
