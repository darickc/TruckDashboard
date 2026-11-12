# Offline map and GPS

The Navigation tab shows a map from one PMTiles file, vector or raster, and
the truck's position from services/navigation
([ADR-0030](../architecture/adr/0030-navigation-position-and-raster-map.md),
[ADR-0032](../architecture/adr/0032-vector-map.md)). Status: **[SIM]**. No GPS
receiver is chosen yet (H11), and nothing has run on the Pi.

## What the screen shows

| Chip | Meaning |
|---|---|
| `3D FIX` / `2D FIX` | The position is current: a fix younger than the stale limit (3 s, an example) |
| `LAST KNOWN · n S AGO` | The last fix, grey, with its age. The reason is shown under it |
| `NO POSITION` | No fix since the navigation service started |
| `SIMULATED` | The simulated receiver, never the truck's real position |

The map follows the truck until you drag it; the locate button follows
again. With no map file, the screen says why and still shows the position.
Routing isn't implemented yet (6.5.2). **It will not be guaranteed safe for
heavy vehicles or trailers** (ADR-0010).

## The map file

- One **PMTiles v3** file at `/var/lib/f250/storage/maps/map.pmtiles` on the
  Pi, on the data drive ([ADR-0033](../architecture/adr/0033-map-updates-by-usb-stick.md)), of
  **vector** tiles (MVT, the Protomaps basemap schema), which the dashboard
  draws with its bundled styles (day and night), or **raster** tiles (PNG,
  JPEG or WebP). AVIF is refused, saying why.
- Its `attribution` metadata is shown on screen, with the date of its data
  when `make map-region` made it. A map made from OpenStreetMap data must
  carry the OpenStreetMap attribution (ODbL). Without any, the screen shows
  "© OpenStreetMap contributors".
- Install or replace it with a USB stick (below).

## Updating the map in the truck (USB stick)

[ADR-0033](../architecture/adr/0033-map-updates-by-usb-stick.md). Status:
**[SIM]**; not yet tried with a real stick on the Pi (bench check 17 in
[agl.md](agl.md)).

1. Once: erase a USB stick as **ExFAT** in Disk Utility (FAT32 can't hold a
   file over 4 GB). Any name.
2. Build the map (next section), then write it onto the stick:

   ```bash
   make map-stick STICK=/Volumes/<name>
   ```

   It copies `build/maps/region.pmtiles` (or `MAP=...`) to `f250/map.pmtiles`
   on the stick and writes its checksum, `f250/map.pmtiles.sha256`. Eject the
   stick.
3. In the truck, with the dashboard on (key at ACC or running), plug the stick
   into the Pi. The status bar shows **MAP n%** while it copies (the Nav screen
   says more); leave the stick in. Then it checks the copy (**MAP CHECK**)
   and swaps it in: **MAP UPDATED**, and the Nav screen shows the new map at
   once. Remove the stick. A stick with the map that is already installed
   (one left in the truck, at every start) isn't copied again: **MAP UP TO
   DATE**.

If anything is wrong (no checksum, a bad copy, not a map, the data drive
missing or full, the stick pulled early) it shows **MAP UPDATE FAILED** with
the reason on the Nav screen, and the old map stays. A stick without
`f250/map.pmtiles` is ignored. On the Pi, `journalctl -u 'f250-map-import@*'`
shows what happened.

To try it on the Mac, `make map-import-dev STICK=/Volumes/<name>` imports a
stick into `/tmp/f250/maps/` the same way while `make ui` runs.

## Building a real map

`make map-region` builds a map of one region from OpenStreetMap data. It
extracts the region's vector tiles from a
[Protomaps](https://docs.protomaps.com/basemaps/downloads) daily build and sets
the file's attribution to "© OpenStreetMap contributors · Protomaps". Nothing
is downloaded from the OpenStreetMap tile servers. Every input is pinned at
the top of `tools/maps/build-map.py`.

- **Vector (default, [ADR-0032](../architecture/adr/0032-vector-map.md))**: the
  extract is the map; the dashboard draws it. Needs only `pmtiles`
  (`brew install pmtiles`). A small area takes seconds; a large one is a
  download. **How fast the Pi draws it is not measured yet.**
- **Raster (`MAP_ARGS=--format=webp`, [ADR-0031](../architecture/adr/0031-raster-map-build.md))**:
  the extract is rendered on this Mac with tileserver-gl in Docker (listening
  on 127.0.0.1 only) into WebP tiles, a few hundred a second. Needs Docker
  Desktop running and Node.js 18+ with npm. Use it if the Pi is too slow for
  vector.

Status: both built and checked on the Mac for sample areas in Kansas; **not
yet shown on the Pi** (6.5.3's update workflow comes later).

1. Pick a bounding box (west,south,east,north in degrees; e.g. draw one at
   <https://boundingbox.klokantech.com>, CSV format) and a top zoom. Check the
   size first; this uses no network:

   ```bash
   make map-region BBOX=-98.60,39.78,-98.47,39.88 MAXZOOM=15 ESTIMATE=1
   ```

   It prints tiles and size per zoom for a rural and an all-urban area; real
   regions are near the rural figure, plus their towns (the urban figure comes
   from a city centre). Each zoom has 4× the tiles of the one below, so the top
   zoom dominates. Vector data stops at zoom 15 (the screen zooms past it and
   stays sharp), so a vector `MAXZOOM` above 15 becomes 15. For raster, a
   100 km × 100 km area is about 3–50 MB to zoom 14, 10–165 MB to zoom 15,
   37–560 MB to zoom 16; vector is similar. Zoom 15 shows every street with
   its name. Add `MAP_ARGS=--format=webp` to see raster sizes.
2. Build it. Above 100,000 tiles it asks for `YES=1`:

   ```bash
   make map-region BBOX=-98.60,39.78,-98.47,39.88 MAXZOOM=15
   ```

   The result is `build/maps/region.pmtiles` (`MAP_OUT`), also copied to
   `/tmp/f250/maps/map.pmtiles` for `make ui` and `make sim`. The work files,
   kept for a re-run, are in `build/maps/region.work/`. A stopped raster render
   carries on when you run the same command again.
3. Check it with `pmtiles` and the dashboard's own reader:

   ```bash
   make map-check MAP=build/maps/region.pmtiles
   ```

4. Put it on a stick for the truck as above (`make map-stick`).

Options go in `MAP_ARGS`, e.g. `MAP_ARGS="--format=png --minzoom 6"`. See
`python3 tools/maps/build-map.py --help`: `--format vector|webp|png|jpg`,
`--build YYYYMMDD` (a Protomaps build date; only recent ones exist), and for
raster `--quality`, `--flavor light|dark|white|grayscale|black`, `--lang`,
`--keep-server` to look at the render in a browser.

Limits: the map is north-up. Raster labels are baked in at the style's size
(about 10–12 px) and night darkens the day tiles; a vector map has a real
night style. The vector styles are simplified for the renderer: labels are one
line (English name, else local), and some places of interest show earlier
than upstream (ADR-0032). Routing isn't part of this (6.5.2).

### The vector map's styles, icons and fonts

They are app assets in `apps/infotainment/assets/map/` (licences in its
README), written by `make map-assets` from pinned inputs and committed. Run
it again only to change a pin or the style rewrite; the unit test
`test/unit/vector_map_test.dart` then checks every expression is understood,
every font bundled and every icon present.

Updates replace the whole file: download a newer build with `make map-region`
and write a new stick. Every few months is plenty for roads.

### A test pattern for development

```bash
make map-test-pattern
```

This writes `build/maps/test-pattern.pmtiles`, a grid labelled "TEST PATTERN
— NOT A MAP", and copies it to `/tmp/f250/maps/map.pmtiles`, where `make ui`
and `make sim` look (`MAP_FILE`). It covers the simulated receiver's loop in
Kansas at zooms 0–16. It needs Pillow and the `pmtiles` tool
(`brew install pmtiles`). The browser preview (`make ui-web`) can't read
files, so it never shows a map.

## GPS

gpsd owns the receiver. services/navigation reads gpsd's JSON on
127.0.0.1:2947 and serves the position to the dashboard
(`f250-navigation.service`, `/run/f250-nav/nav.sock`). Settings in
`/etc/default/f250`:

| Setting | Default | Meaning |
|---|---|---|
| `NAV_GPSD` | `127.0.0.1:2947` | gpsd's address |
| `NAV_SIMULATE` | `0` | `1`: a simulated receiver instead of gpsd |
| `NAV_STALE_AFTER_MS` | `3000` | A fix older than this is never shown as current. An example value |

On the Mac:

```bash
make navigation
```

That runs the service with a simulated receiver. `make sim` runs it with the
gateway and the macOS app. To try the real gpsd without a receiver, feed it
synthetic NMEA as [crates/gpsd/tests/data/README.md](../../crates/gpsd/tests/data/README.md)
does, then run `cargo run -p navigation -- --listen tcp:127.0.0.1:50253 --gpsd 127.0.0.1:2948`.

### On the Pi, once a receiver is fitted (TODO, H11)

1. `systemctl status gpsd.socket gpsd`: is gpsd listening on 127.0.0.1:2947?
   UNVERIFIED on AGL.
2. Plug in the receiver. `gpspipe -w -n 20` should show TPV reports.
3. `journalctl -u f250-navigation`: the status goes from "NoFix" to "Fix3d,
   current" once it sees the sky.
4. Capture `gpspipe -w` for a minute and add it to `crates/gpsd/tests/data/`
   as the real receiver's test vector.
5. Record the results in [docs/hardware/bench-log.md](../hardware/bench-log.md).
