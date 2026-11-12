# ADR 0033 — Map updates by USB stick, onto the data drive

- **Status:** Accepted (owner, 2026-11-11). [SIM]: `make agl-test` runs
  the import against folders, `map-stick.py` against a folder, and the
  dashboard's tests cover the status. [BENCH] 2026-11-11 (bench-log): a
  real exFAT stick on the Pi imported onto the card and the dashboard
  reopened the map. Not yet with the NVMe drive. **Amended** 2026-11-11:
  the stick can carry routing data too (end of this ADR)
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
   - The installed map's SHA-256 is kept in `map.pmtiles.sha256` beside it
     (removed before the swap, written after). A stick whose checksum and
     size match is not copied again: state `current`, "This map is already
     installed". Otherwise a stick left in the truck would copy the whole
     map at every start (found on the bench, 2026-11-11).
   - One import at a time (a lock in `/run/f250-maps`). The unit is bound to
     the stick: pulling it stops the unit, and `ExecStopPost` marks that
     stick's import failed.
   - The unit is sandboxed: it writes only `/var/lib/f250/storage` and its
     runtime directory, has no network, and may take an hour.
4. **The dashboard shows it and opens the new map without a restart.** The
   import writes `/run/f250-maps/status.json` (state `checking`, `copying`
   with a percentage, `updated`, `current` or `failed`, a message, an id).
   The percentage is the copy's size so far; it reads 100% while the copy
   is flushed to the drive, which on the bench card was most of the time.
   The dashboard reads it every second (`MAP_STATUS`): a chip in the status
   bar on every tab ("MAP 43%", "MAP UPDATED", "MAP UP TO DATE", "MAP UPDATE
   FAILED") and the message on the Nav tab. A finished import shows for 10
   minutes. A new `updated` id reopens the map (the view stays where it
   was); the old file is closed, so its space is freed, and the vector layer
   gets a new tile cache, so no tile of the old map shows. `current` reopens
   nothing. An import that finished before the dashboard started isn't
   shown.
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
  looks for `f250/map.pmtiles`. Any other stick can take dashcam recordings
  instead ([ADR-0037](0037-recordings-to-a-usb-stick.md)): usb-export never
  writes to a stick with map or routing data. A stick with that file is treated as a map
  update whoever made it, but is refused unless its checksum and header
  check out, and can only replace the map.

## Amendment: routing data on the same stick (2026-11-11)

Routing (ADR-0035) needs one more file on the data drive:
`/var/lib/f250/storage/routing/valhalla_tiles.tar`, Valhalla's tile extract
(312 MB for Kansas; a multi-state region is gigabytes). It has the same
shape of problem as the map: one file, replaced whole, built on the Mac, too
big for the weak Wi-Fi. ADR-0035 suggested the map stick.

Options considered:

| Option | For | Against |
|---|---|---|
| **A. The same stick and import, a second file** (chosen) | One workflow, one unit, one status the dashboard already shows; map and routing data of one region travel together | The import script grows from one file to two |
| B. A second import unit and stick layout for routing | Kept apart | Two udev rules racing for the same stick, two status files, a second thing to explain |
| C. Copy it over SSH | Nothing new | Needs the Mac and the network at the truck; not a workflow for the owner |

Decision (refines decisions 2–4):

1. **A stick carries `f250/map.pmtiles`, `f250/routing.tar`, or both**, each
   with its `.sha256`. `make map-stick STICK=... ROUTING=build/routing/valhalla_tiles.tar`
   adds the routing data (`MAP=` alone leaves the map out). `map-stick.py`
   refuses routing data that isn't a Valhalla tile extract: a ustar file whose
   first entry is `index.bin`, as `valhalla_build_extract` 3.9.1 writes it
   (seen in the Kansas build).
2. **The Pi imports each file the same way**: checksum, a content check
   (PMTiles header for the map; the tar header and `index.bin` first for the
   routing data), room for it plus 64 MB, a copy to `<name>.part`, the copy's
   checksum and content checked again, then a rename over the old file. The
   installed file's SHA-256 is kept beside it, so a stick left in is
   `current` and not copied again. The routing data goes to
   `<storage>/routing/valhalla_tiles.tar`. A stick with neither file is
   still ignored.
3. **Map first, then routing data, in one import.** A failure stops the import
   where it is: a bad map means the routing data isn't tried; a bad routing
   file leaves the new map in place (it was already checked and swapped).
   Either way the old file of the one that failed is kept. A `failed` status
   still lists what was already replaced (`changed: ["map"]`) and says "The
   map was updated", and the dashboard reopens the map on it, so a new map
   on disk is never left unshown behind a routing failure.
4. **One status file**, with two more fields: `item` (`map` or `routing`, the
   file being checked or copied) and `changed` (what an `updated` import
   replaced, also in a `failed` status). The dashboard says "Copying routing data from USB: n%" for
   `routing` and keeps the same chips ("MAP n%", "MAP UPDATED"): the stick
   is still the map stick. It reopens the map only when `changed` has `map`
   (or, for `updated`, the field is missing, from an older import). The messages name what
   changed: "Map and routing data updated", "Routing data updated. The map
   was already installed", "The routing data on this stick is already
   installed".
5. **navigation needs no signal.** It checks the routing file every second
   and writes Valhalla's config before each request, and each request is a
   new `valhalla_service` process, which opens the file afresh. A request
   running during the rename keeps the old file open and finishes on it.

Consequences: [SIM] `make agl-test` covers both files, routing alone,
`current`, each refusal and a pull during the routing copy; the dashboard's
tests cover the new fields. [BENCH] 2026-11-11: the script imported Kansas's
routing data on the bench Pi from a folder (no stick: not yet with a real
stick or the NVMe), see the bench log. The map's limits apply: the drive needs
room for the old and new routing data during an import.

## Amendment: search data on the same stick (2026-11-12)

A stick may also carry `f250/search.sqlite`, navigation's offline search
index ([ADR-0038](0038-offline-address-search.md)), with its `.sha256`:
`make map-stick SEARCH=build/search/search.sqlite`. The import takes it after
the map and the routing data, checks its checksum, its SQLite header and its
application id ("F250"), and swaps it in at
`/var/lib/f250/storage/search/search.sqlite`. The status file's `item` can be
`search`; the dashboard shows "Copying search data from USB" and doesn't
reopen the map for it. navigation opens the new file at the next search.
`usb-export` treats a stick with only search data as a map stick. [SIM]
(`make agl-test`); not yet with a real stick.
