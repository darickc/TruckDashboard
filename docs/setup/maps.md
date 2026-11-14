# Offline map, GPS and routing

The Navigation tab shows a map from one PMTiles file, vector or raster, the
truck's position from services/navigation, and routes from Valhalla
([ADR-0030](../architecture/adr/0030-navigation-position-and-raster-map.md),
[ADR-0032](../architecture/adr/0032-vector-map.md),
[ADR-0035](../architecture/adr/0035-routing-with-valhalla.md)). Status:
**[SIM]**, and **[BENCH]** for routing on the Pi 5 (2026-11-11, with the
simulated receiver). No GPS receiver is chosen yet (H11).

## What the screen shows

| Chip | Meaning |
|---|---|
| `3D FIX` / `2D FIX` | The position is current: a fix younger than the stale limit (3 s, an example) |
| `LAST KNOWN · n S AGO` | The last fix, grey, with its age. The reason is shown under it |
| `NO POSITION` | No fix since the navigation service started |
| `SIMULATED` | The simulated receiver, never the truck's real position |

The map follows the truck until you drag it; the locate button follows
again. With no map file, the screen says why and still shows the position.
Long-press the map, then **Route here**, to route there (next section).

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

A stick with `f250/map.pmtiles` or `f250/routing.tar` is a **map stick**:
the dashboard won't copy dashcam recordings to it. Use another stick for
recordings (Cameras → **Recordings to USB**,
[ADR-0037](../architecture/adr/0037-recordings-to-a-usb-stick.md)).

1. Once: erase a USB stick as **ExFAT** in Disk Utility (FAT32 can't hold a
   file over 4 GB). Any name.
2. Build the map (next section), then write it onto the stick:

   ```bash
   make map-stick STICK=/Volumes/<name>
   ```

   It copies `build/maps/region.pmtiles` (or `MAP=...`) to `f250/map.pmtiles`
   on the stick and writes its checksum, `f250/map.pmtiles.sha256`. To bring
   [routing data](#routing-data) too, add
   `ROUTING=build/routing/valhalla_tiles.tar` (it becomes `f250/routing.tar`
   and its checksum); `MAP=` with nothing after it leaves the map out. Eject
   the stick.
3. In the truck, with the dashboard on (key at ACC or running), plug the stick
   into the Pi. The status bar shows **MAP n%** while it copies (the Nav screen
   says more); leave the stick in. Then it checks the copy (**MAP CHECK**)
   and swaps it in: **MAP UPDATED**, and the Nav screen shows the new map at
   once. Remove the stick. A stick with the map that is already installed
   (one left in the truck, at every start) isn't copied again: **MAP UP TO
   DATE**.

If anything is wrong (no checksum, a bad copy, not a map, the data drive
missing or full, the stick pulled early) it shows **MAP UPDATE FAILED** with
the reason on the Nav screen, and the old map stays. Routing data is checked
and swapped the same way, after the map, with the same chips ("Copying
routing data from USB" on the Nav screen); a bad routing file keeps the old
routing data, and a new map copied before it stays. A stick with neither
`f250/map.pmtiles` nor `f250/routing.tar` is ignored. On the Pi, `journalctl -u 'f250-map-import@*'`
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

The map turns with the truck: the direction of travel is up while it follows
the truck, with a compass for north (ADR-0032, amended 2026-11-12). A vector
map keeps road names right side up on screen (drawn in vector mode with a
patched renderer, `apps/infotainment/third_party/vector_tile_renderer`).
Limits: raster labels turn with the map (they are part of the picture). Raster labels are baked in at the style's size
(about 10–12 px) and night darkens the day tiles; a vector map has a real
night style. The vector styles are simplified for the renderer: labels are one
line (English name, else local), and some places of interest show earlier
than upstream (ADR-0032). Routing data is built separately (`make route-region`, below).

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

## Routing

**Routes are not checked for heavy vehicles or trailers** (ADR-0010).
OpenStreetMap's restriction data is incomplete; the screen says so with
every route.

Long-press the map to drop a pin, then **Route here**. The route comes from
the truck's current position (a route needs a current fix). While driving,
the banner shows the next turn and its distance, and the distance and time
left, in the units chosen in Settings. Leave the route (60 m for 5 s) and a
new one is found from where the truck is. **End route** clears it. If
Valhalla can't route, the banner says why and offers **Retry**. Without a
current fix, or if the navigation service stops answering, guidance pauses:
the line turns grey and no distances are shown. Those limits are examples
in `/etc/default/f250` and `navigation --help`.

To route to an address or a place, use **Search** ([below](#search)), or a
saved place ([Places](#saved-places)). There is no arrival time by the clock
(the Pi has no clock source in the truck). Directions are spoken
([below](#spoken-directions)).

### Routing data

`make route-region` builds Valhalla's routing tiles for one or more
[Geofabrik](https://download.geofabrik.de) regions, from their OpenStreetMap
extracts (ODbL), in Valhalla 3.9.1's Docker image (pinned in
`tools/maps/build-routing.py`). Needs Docker Desktop running.

```bash
make route-region REGION=north-america/us/kansas
make route-region REGION="north-america/us/kansas north-america/us/nebraska"
```

The result is `build/routing/valhalla_tiles.tar`, also copied to
`/tmp/f250/routing/` for `make navigation` and `make sim`. Kansas: 118 MB
downloaded, about 30 s to build on an M-series Mac, a 312 MB file [BENCH].
An extract already downloaded for the same date isn't fetched again. Build
the same region as the map; a route can't leave the routing data.

For many states, build the country: neighbouring Geofabrik extracts overlap at
their borders. Geofabrik's `north-america/us` includes Alaska and Hawaii;
`--bbox` clips it to the map's box first (osmium-tool: `brew install
osmium-tool`; `pmtiles show` prints a map's bounds). The lower 48, to match
the lower-48 map:

```bash
make route-region REGION=north-america/us \
  ROUTE_ARGS="--bbox=-124.85,24.4,-66.88,49.38 --concurrency 8 --late-concurrency 3 --out build/routing/lower48/valhalla_tiles.tar --work build/routing/us-work"
```

From the 12 GB US download that took 72 minutes on an M-series Mac with
Docker's 8 GB and 16 CPUs (3 of them clipping), into a 20.9 GB file of
15,099 tiles [BENCH, 2026-11-12]. The build needs about 70 GB free while it
runs. With 8 GB, the later stages need fewer threads (`--late-concurrency`)
or they run out of memory. If a build fails after its first half,
`ROUTE_ARGS="... --resume enhance"` runs only the second half again.

On the lower-48 data in Docker, Docker's start included: a 65 km route in
0.4 s, Kansas City to Denver (974 km) 0.4 s, Key West to West Quoddy Head
(3,228 km) 0.7 s, Seattle to Miami (5,319 km) 1.9 s with a peak of 690 MB in
the container, page cache counted. Anchorage and Honolulu get "No suitable
edges near location" [BENCH]. A file this size is too big for the map stick
next to the map: a 29 GB stick holds one or the other, and the import takes a
stick with only one of them.

### On the Mac

```bash
make route-region REGION=north-america/us/kansas
make sim
```

navigation runs Valhalla through `tools/dev/valhalla-docker.sh` (Docker, no
network), once per route. The simulated receiver then drives the route, so
guidance runs end to end. Without routing data the screen says "Routing
unavailable: no routing data at …". From a terminal, without the dashboard:

```bash
cargo run -p navigation --example route -- tcp:127.0.0.1:50253 39.8103 -98.5559
```

### On the Pi

The image has Valhalla 3.9.1's `valhalla_service` in `/usr/bin` (meta-f250,
`recipes-navigation/valhalla`), which navigation finds on `PATH`
(`NAV_VALHALLA`). The routing data comes on the map stick:

```bash
make route-region REGION=north-america/us/kansas
make map-stick STICK=/Volumes/<name> ROUTING=build/routing/valhalla_tiles.tar
```

Plug the stick in with the dashboard on. The import puts it at
`/var/lib/f250/storage/routing/valhalla_tiles.tar` (`NAV_ROUTING_TILES`)
and navigation sees it within a second: no restart. Until it is there the
Nav screen says "Routing unavailable: no routing data at … (it comes on the
map stick)". Bench check 18 in [agl.md](agl.md).

On the bench Pi 5 a Kansas route takes 0.13–0.2 s and about 30–40 MB, under
navigation's own sandbox [BENCH, bench-log 2026-11-11]. Bigger regions are
unmeasured. Other settings in `/etc/default/f250`:

| Setting | Default | Meaning |
|---|---|---|
| `NAV_COSTING` | `auto` | `auto` routes as a car; `truck` uses Valhalla's truck model |
| `NAV_TRUCK_HEIGHT_M`, `_WIDTH_M`, `_LENGTH_M`, `_WEIGHT_T`, `_AXLE_LOAD_T` | empty | `truck` only. Empty is Valhalla's default, a large truck's. Set only what you have measured |

## Search

**Search** (the magnifier under the map buttons) finds addresses, streets,
towns and named places offline, nearest first, as you type on the on-screen
keyboard ([ADR-0038](../architecture/adr/0038-offline-address-search.md)).
Each result has **Show** (on the map, then Route here or Cancel) and **Route
here**. Every result says what it is, and OpenStreetMap's house numbers are
sparse outside towns, so often it is only the street or the town:

| Label | Means |
|---|---|
| ADDRESS | The house number you typed, on that street |
| STREET | A street. "Street only: no house number 125 in the map data" when the number isn't there: the route ends on the street |
| TOWN | A town, and "Town only: “elm avenue” not found" when the rest of what you typed isn't there |
| PLACE | A named business, park, school… |
| ESTIMATED | The house number you typed, placed along its street from the US Census Bureau's address ranges ("Estimated from US Census address ranges"): where OSM has no such address. Usually within 100–250 m of the house, on the road; the number may not exist |

Abbreviations work both ways ("n main st" finds "North Main Street"), and the
last word may be unfinished (three letters; two for a town). Add the state's
short name to pick a town ("kansas city mo"), or end with the ZIP code
("elm ave 99001"): the results are then nearest to that ZIP code instead of
the truck, and a ZIP code alone shows its area. Misspellings find nothing.
House numbers that openstreetmap.org's search finds for rural addresses
often come from US Census data it adds, not from OpenStreetMap. In the US the
index carries the same kind of data, the Census's TIGER/Line address ranges
([ADR-0041](../architecture/adr/0041-us-census-address-ranges.md)), so such a
number is ESTIMATED rather than missing; outside the US, or with numbers like
Queens' "10-09", the result is the street.
Typing while moving isn't locked out (owner's decision); the panel asks to
type only when parked.

### Search data

`make search-region` builds the index from the same Geofabrik extract as the
routing data (downloaded once for both), with `tools/search-index`, and with
osmium (`brew install osmium-tool`) the state of every result:

```bash
make search-region REGION=north-america/us/kansas
make search-region REGION=north-america/us SEARCH_ARGS="--bbox=-124.85,24.4,-66.88,49.38 --name='Lower 48 states'"
```

For a US region the build also downloads the Census's address ranges
(TIGER/Line 2026 ADDRFEAT, one zip per county, public domain with credit to
the U.S. Census Bureau) for its states into `build/search/tiger/`, once:
a stopped download carries on next time. `SEARCH_ARGS=--no-tiger` leaves them
out; with `PBF=` name the states, `SEARCH_ARGS=--tiger-states=KS,NE`.

The result is `build/search/search.sqlite`, also copied to
`/tmp/f250/search/` for `make navigation` and `make sim`. Kansas: 63 MB in
3 s with the address ranges (37 MB without). The lower 48: 5.2 GB in about 7 minutes without the
address ranges; with them, 7.2 GB in about 11 minutes, 15–17.5 GB of
memory at the peak either way; the ranges are about 2.7 GB to download
[SIM, 2026-11-13, ADR-0041]. The Census's server refuses requests for a while
when downloaded from too fast; the build then waits, and if it still can't,
stops and says to run it again later (what is downloaded is kept). A single
file it refuses while serving the rest is left out with a warning (Kimble
County, Texas on 2026-11-13); run the same command later to fetch it. On the Mac, from a terminal:

```bash
cargo run --release -p search-index -- query build/search/search.sqlite "120 n main st" --near 39.81,-98.56
cargo run -p navigation --example search -- tcp:127.0.0.1:50253 "main st"
```

On the Pi it comes on the map stick, with or without the map and the routing
data:

```bash
make map-stick STICK=/Volumes/<name> SEARCH=build/search/search.sqlite
```

The import puts it at `/var/lib/f250/storage/search/search.sqlite`
(`NAV_SEARCH_INDEX`), and navigation opens it at the next search: no restart.
Until then the panel says "Search unavailable: no search data at …". Bench
check 20 in [agl.md](agl.md).

## Saved places

**Places** (bottom left, when there's no route) lists Home, the favourites
and the recent destinations ([ADR-0040](../architecture/adr/0040-saved-places-and-spoken-directions.md)).
Each has **Route here** (one tap) and **Edit** (rename, delete, or make a
recent one a favourite or Home). To save a place, tap **Save** on a pin
(long-press the map, or **Show** from search), the star on a search result,
or the star with the route. A favourite needs a name, typed on the on-screen
keyboard; typing while moving works, with a warning.

| | |
|---|---|
| Home | One; saving another replaces it |
| Favourites | At most 50, named (40 characters) |
| Recent | Every destination routed to, newest first, the last 10; one within 50 m of another replaces it |

navigation keeps them in `places.json`, written atomically:

| Where | When |
|---|---|
| `/var/lib/f250/storage/navigation/` | the data drive with `DATA_DRIVE=1`; the SD card with `DATA_DRIVE=0` |
| `/var/lib/f250-nav/` | `DATA_DRIVE=1` but nothing mounted there at start: the panel says so, and places saved then stay on the card |
| `/tmp/f250/navigation/` | `make navigation` and `make sim` on the Mac (`NAV_STATE=`) |

A file that can't be read as places is renamed `places.json.bad` and a new
list starts; the panel says so at the top. The file is plain JSON, readable
on the drive.

## Spoken directions

navigation speaks the next turn from Valhalla's own words: "In half a mile,
turn right onto US 36." as it approaches, "Turn right onto US 36, US 281."
just before, "Continue for 12 miles." after a turn with a long way to the
next, "Off the route. Finding a new one." and "New route." when rerouting,
and the arrival. **Nothing is said without a current position**, and a turn
passed while the fix was stale isn't announced late.

When, by default (examples to tune on the truck, `navigation --help`): the
approaching prompt 30 s ahead at the current speed (between 400 m and
2.5 km), the last one 8 s ahead (50–300 m). Distances in miles and feet;
`NAV_VOICE_UNITS=metric` for metres.

The route's buttons have the mute toggle: **Voice**, **Muted**, or **No
audio** when the prompts can't be heard (audio-manager isn't running or has
no voice). Muting is kept across restarts. audio-manager says the prompts and
**pauses the phone's music** while it does, resuming it 1 s after the last
one (the owner's choice; ADR-0039, ADR-0040 decision 16). A prompt that
can't be said at once is dropped, never said late.

| Where prompts go | |
|---|---|
| The Mac | `make sim`: audio-manager's simulated phone, whose music pauses for them; silent unless `VOICE=say`. `make navigation VOICE=say` alone speaks them with no music to pause. With `SIM_CALL=30` a made-up call rings every 30 s, and directions are skipped during it; `RING=afplay` makes its ring tone heard (ADR-0045) |
| The Pi | audio-manager (`NAV_AUDIO_MANAGER`, `/run/f250-audio/audio.sock`), which says them with Flite. **Not heard on the Pi yet.** With `NAV_AUDIO_MANAGER=` they go to `journalctl -u f250-navigation` only |

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
