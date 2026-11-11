# ADR 0031 — Building the raster map: Protomaps extract, rendered locally by tileserver-gl

- **Status:** Accepted. The tool ran on the development Mac on 2026-11-11 for
  sample areas in Kansas (the simulator's loop near Lebanon, rural Smith
  County, central Kansas City), and its output passed `pmtiles verify` and
  the dashboard's own reader with every sampled tile decoded. No map has been
  shown on the Pi, and the owner's region isn't built yet
- **Date:** 2026-11-11
- **Refines:** [ADR-0030](0030-navigation-position-and-raster-map.md) (the
  raster PMTiles map the Navigation tab reads); part of Phase 6.5.3

## Context

ADR-0030 settled that the dashboard shows **raster** tiles from one PMTiles v3
file (PNG, JPEG or WebP; gzip or no compression), because Flutter's vector
renderers can't share the app with gRPC. Until now only a test pattern
existed. A real map needs map data, a style, and a renderer, and must:

- never bulk-download from tile.openstreetmap.org (its tile usage policy
  forbids it);
- carry the OpenStreetMap attribution (ODbL) in its metadata, which the
  screen shows;
- be reproducible: every input pinned, so the same command makes the same map;
- run on the development Mac, and keep `make test` free of network and Docker.

## Options

| Option | For | Against |
|---|---|---|
| **Protomaps daily build → `pmtiles extract` → tileserver-gl in Docker → crawl → `pmtiles convert`** (chosen) | Only the region's vector tiles are downloaded (HTTP range requests; 0.65 MB for the 120 km² sample). Renders on this machine, so no tile server is loaded. tileserver-gl reads PMTiles directly and renders with MapLibre Native. Multi-arch image (native on Apple Silicon). The basemap style, fonts and sprites are published, open and versioned. | Needs Docker and Node.js on the Mac. Raster labels are fixed at render time |
| Download raster tiles from a public server | Simplest | tile.openstreetmap.org forbids bulk downloads; commercial raster APIs have terms and keys. Rejected |
| Build our own vector tiles with Planetiler from a Geofabrik extract | Full control of the schema | Java, a much larger download (a state's `.osm.pbf`), and we would still need a style for that schema. More moving parts for no gain today |
| Render with the `@maplibre/maplibre-gl-native` Node bindings on macOS | No Docker | Native module per platform; less tested headless path; tileserver-gl already wraps the same renderer with PMTiles, fonts and sprites solved |
| Mapnik/OpenStreetMap Carto | The familiar OSM look | Needs PostGIS and an osm2pgsql import: far heavier than one container |

## Decision

1. **`tools/maps/build-raster-map.py`** (Python 3 standard library) builds one
   region's map; `make map-region BBOX=w,s,e,n MAXZOOM=n` runs it and copies
   the result to `MAP_FILE` for `make ui`/`make sim`. Steps:
   1. `pmtiles extract https://build.protomaps.com/<YYYYMMDD>.pmtiles` with the
      bbox, up to zoom 15 (the builds' top zoom; higher raster zooms overzoom
      it). The build date defaults to the newest of the last week and is
      recorded in the output.
   2. A style written by `@protomaps/basemaps` (`tools/maps/style.mjs`), with
      the fonts and sprites from `protomaps/basemaps-assets`, served locally.
   3. tileserver-gl in Docker, published on **127.0.0.1 only**, renders 256 px
      tiles, which the script crawls for every zoom into an MBTiles file. The
      render resumes if stopped.
   4. `pmtiles convert` (deduplicates identical tiles) and `pmtiles verify`.
2. **Pins** (constants at the top of the script; change them here too):

   | Input | Pin | Licence |
   |---|---|---|
   | Renderer | `maptiler/tileserver-gl:v5.7.0@sha256:24d0364e1d40da0ae3fb3269f617c26e36a883ad4b7454e5c4064a8795bfc807` (amd64 + arm64) | BSD-2-Clause |
   | Style | `@protomaps/basemaps@5.7.2` (npm), flavor `light`, language `en` | BSD-3-Clause code; the visual design is CC0 |
   | Fonts and sprites | `protomaps/basemaps-assets` commit `028c18f713baecad011301ff7a69acc39bcc2ae7`, sprites `v4` | Noto Sans: SIL OFL; sprites derived from MIT-licensed tangrams/icons |
   | Map data | a Protomaps daily build, by date (the 2026-11-10 and -11 builds were used; tiles schema 4.15.2, Planetiler 0.10.2) | OpenStreetMap data, **ODbL**; Natural Earth (public domain) at low zooms |
   | Tools | go-pmtiles 1.31.2 (Homebrew), Docker 28.3.2, Node.js 18+ | |

   Basemap 5.x styles match tiles schema 4.x. A new major schema version
   needs a matching style version.
3. **Format: WebP, quality 90, 256 px tiles**, the default. Measured on the
   samples, WebP was 4–5× smaller than PNG and smaller than JPEG at quality 85
   (urban 8.7 MB WebP, 9.4 MB JPEG, 41 MB PNG for the same 957 tiles). PNG and
   JPEG remain options (`--format`). Tile compression is none (images are
   already compressed); directories are gzip.
4. **Labels across tile edges**: tileserver-gl's `tileMargin` is 128 px, so
   each tile is rendered with its surroundings and labels near an edge come
   out the same in both neighbours. No cut labels were seen in the samples.
5. **Metadata**: `attribution` is "© OpenStreetMap contributors · Protomaps"
   (plain text; the screen strips HTML anyway). `description` and
   `f250:*` keys record the build date, style, assets commit, renderer
   digest, the ODbL notice, and the parameters, so a map file says how it
   was made.
6. **Size before building.** `--estimate` (`ESTIMATE=1`) prints tiles and
   size per zoom with no network, from per-tile averages measured on the
   rural and urban samples. A build over 100,000 tiles needs `--yes`
   (`YES=1`), so a large region is a deliberate choice.
7. **Tests stay offline.** `test/unit/map_file_check_test.dart` checks a
   built map with the dashboard's reader (header, attribution, the centre
   and corner tiles at every zoom decode to 256 × 256 images). It is skipped
   unless `MAP_CHECK` names a file; `make map-check` runs it. `make test` needs
   no network, Docker or map.

## Consequences

- Real maps are now possible. Measured on the Mac: a few hundred tiles a
  second, so zoom 16 for a 100 km × 100 km area (about 62,000 tiles) takes
  minutes. Size is dominated by the top zoom: each zoom has 4× the tiles of
  the one below. For that area, WebP, cumulative: about 3–50 MB to zoom 14,
  10–165 MB to zoom 15, 37–560 MB to zoom 16 (rural – all-urban).
- Labels are at the style's nominal size (about 10–12 px). Whether they read
  well on the 800 × 480 screen in the cab is UNVERIFIED until it runs on the
  Pi. A larger-text style is a possible follow-up.
- The map is north-up and fixed; restyling means rebuilding.
- Night mode stays the darkened light tiles (ADR-0030). The `dark` flavor can
  be built (`--flavor dark`) but the dashboard reads one file today.
- The update workflow (copy over Wi-Fi or USB) and the ODbL documentation of
  6.5.4 remain to do. Protomaps keeps only recent daily builds (on
  2026-11-11 the 2026-11-01 build was already gone), so rebuilding an old map
  means a newer build; the script keeps each extract in its work directory.
- Docker Hub, npm, GitHub and build.protomaps.com are needed at build time,
  never on the truck.
