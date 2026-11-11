# Offline map and GPS

The Navigation tab shows a raster map from one PMTiles file and the truck's
position from services/navigation ([ADR-0030](../architecture/adr/0030-navigation-position-and-raster-map.md)).
Status: **[SIM]**. No GPS receiver is chosen yet (H11), and nothing has run
on the Pi.

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

- One **PMTiles v3** file of **raster** tiles (PNG, JPEG or WebP), at
  `/var/lib/f250/maps/map.pmtiles` on the Pi. Vector tiles (MVT) are refused:
  see ADR-0030 for why.
- Its `attribution` metadata is shown on screen. A map made from OpenStreetMap
  data must carry the OpenStreetMap attribution (ODbL). Without any, the
  screen shows "© OpenStreetMap contributors".
- To install or replace it:

  ```bash
  ssh root@<pi> mkdir -p /var/lib/f250/maps
  ```

  ```bash
  scp map.pmtiles root@<pi>:/var/lib/f250/maps/map.pmtiles
  ```

  ```bash
  ssh root@<pi> systemctl restart f250-dashboard
  ```

## Building a real map

`make map-region` builds a raster map of one region from OpenStreetMap data
([ADR-0031](../architecture/adr/0031-raster-map-build.md)). It extracts the
region's vector tiles from a [Protomaps](https://docs.protomaps.com/basemaps/downloads)
daily build, renders them on this Mac with tileserver-gl in Docker (listening on
127.0.0.1 only), and writes WebP tiles into one PMTiles file whose attribution
is "© OpenStreetMap contributors · Protomaps". Nothing is downloaded from the
OpenStreetMap tile servers. Every input is pinned at the top of
`tools/maps/build-raster-map.py`.

Needs `pmtiles` (`brew install pmtiles`), Docker Desktop running, and Node.js
18+ with npm. Status: built and checked on the Mac for sample areas in Kansas;
**not yet shown on the Pi** (6.5.3's update workflow comes later).

1. Pick a bounding box (west,south,east,north in degrees; e.g. draw one at
   <https://boundingbox.klokantech.com>, CSV format) and a top zoom. Check the
   size first; this uses no network:

   ```bash
   make map-region BBOX=-98.60,39.78,-98.47,39.88 MAXZOOM=16 ESTIMATE=1
   ```

   It prints tiles and size per zoom for a rural and an all-urban area; most
   regions fall between. Each zoom has 4× the tiles of the one below, so the
   top zoom dominates. For a 100 km × 100 km area: about 3–50 MB to zoom 14,
   10–165 MB to zoom 15, 37–560 MB to zoom 16. In the Kansas City sample,
   zoom 15 already showed every street with its name.
2. Build it. Above 100,000 tiles it asks for `YES=1`:

   ```bash
   make map-region BBOX=-98.60,39.78,-98.47,39.88 MAXZOOM=16
   ```

   The result is `build/maps/region.pmtiles` (`MAP_OUT`), also copied to
   `/tmp/f250/maps/map.pmtiles` for `make ui` and `make sim`. The work files,
   kept for a re-run, are in `build/maps/region.work/`. A stopped render
   carries on when you run the same command again. The Mac renders a few
   hundred tiles a second.
3. Check it with `pmtiles` and the dashboard's own reader:

   ```bash
   make map-check MAP=build/maps/region.pmtiles
   ```

4. Copy it to the Pi as above.

Options go in `MAP_ARGS`, e.g. `MAP_ARGS="--format png --minzoom 6"`. See
`python3 tools/maps/build-raster-map.py --help`: `--format webp|png|jpg`,
`--quality`, `--flavor light|dark|white|grayscale|black`, `--lang`, `--build
YYYYMMDD` (a Protomaps build date; only recent ones exist), `--keep-server` to
look at the render in a browser.

Limits: labels are baked in at the style's size (about 10–12 px) and the map
is north-up. Protomaps' data stops at zoom 15; higher zooms are rendered from
it, so they enlarge rather than add detail. Routing isn't part of this
(6.5.2).

**TODO (6.5.3):** a workflow that updates the map on the Pi over Wi-Fi or USB.

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
