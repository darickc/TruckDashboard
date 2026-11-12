# ADR 0032 — The dashboard draws vector maps itself

- **Status:** Accepted. [SIM] and [BENCH]. Built and tested on the development Mac on
  2026-11-11: unit and widget tests, a vector map of the simulator's area,
  and pictures of the Navigation tab by day and night rendered by
  `flutter test`. The macOS app started with a vector map without errors,
  but its Navigation tab wasn't opened. [BENCH] on the Pi 5 by day,
  2026-11-11 (bench-log): the map fills 1.7 s after Nav opens and keeps up
  with zooming and dragging, at up to three of four cores while it moves
- **Date:** 2026-11-11
- **Refines:** [ADR-0030](0030-navigation-position-and-raster-map.md) (decision 5,
  raster only, and 8, night by darkening) and
  [ADR-0031](0031-raster-map-build.md) (raster rendering becomes optional)

## Context

ADR-0030 chose raster tiles because the Flutter vector-map packages couldn't
share the app with gRPC: `vector_map_tiles` → `vector_tile_renderer` →
`vector_tile` 2.x needs `protobuf ^3`, and the app's `grpc` 5.2 needs
`protobuf ^6`. Raster maps work (ADR-0031), but need Docker and a long render
for a large region, bake the style in (no real night style, no bigger
labels), and can't turn with the truck.

On 2026-11-11 pub.dev showed that `vector_tile` 4.0.0 (March 2026) decodes
the same tiles on `protobuf ^6`; only `vector_tile_renderer` 6.1.0 still asks
for `vector_tile ^2.0.0`. Overriding it to 4.0.0 resolves with the app's
packages, compiles, and draws correctly (a spike, then the tests below).

Going back to `protobuf` 3 instead (`grpc` 4.1.0, `protoc_plugin` 22.0.0)
would also resolve, but would hold the gRPC client a year back. The gateway
needs no change either way: every protobuf version reads the same messages.

## Decision

1. **The map file may be vector (MVT) or raster.** The reader accepts
   `TileType.mvt`; the Navigation tab draws a vector tileset with
   `vector_map_tiles` and a raster one as before. AVIF and unknown types are
   still refused, saying why.
2. **Packages:** `vector_map_tiles` 9.0.0-beta.13 (the stable 8.0.0 needs
   `flutter_map` 7; the app has 8.3), `vector_tile_renderer` 6.1.0, and
   `dependency_overrides: vector_tile: 4.0.0`. Pinned exactly: the override
   is only known to work with these versions.
3. **Tiles come from the dashboard's own PMTiles reader** through
   `PmTilesVectorProvider` (`lib/nav/vector_map.dart`), not the `pmtiles`
   package (its 2.x needs Dart 3.11; the AGL engine pin has 3.10.1). A tile
   outside the region is reported missing, not retried.
4. **The style, icons and fonts are app assets** (`assets/map/`), so the map
   stays one file. `tools/maps/map-assets.py` (`make map-assets`) writes them
   from pinned inputs and the output is committed:

   | Asset | Source | Licence |
   |---|---|---|
   | `styles/light.json`, `styles/dark.json` | `@protomaps/basemaps` 5.7.2, flavors `light` and `dark`, language `en` | BSD-3-Clause code; the design CC0 |
   | `sprites/light@2x.*`, `sprites/dark@2x.*` | `protomaps/basemaps-assets` commit `028c18f713baecad011301ff7a69acc39bcc2ae7`, sprites v4 | as ADR-0031 |
   | `fonts/NotoSans-{Regular,Medium,Italic}.ttf` | `notofonts/notofonts.github.io` commit `4cf78353cd1668040ba8efa13029cd910fcdf9e2`, unhinted TTF | SIL OFL 1.1 (`fonts/OFL.txt`) |

   About 1.4 MB in all. The pubspec names each font family as the styles do
   (`Noto Sans Regular`, …).
5. **The style is rewritten for `vector_tile_renderer` 6.1.0**, which can't
   parse parts of the upstream style. Rules, in `map-assets.py`:
   - `["in", x, ["literal", [...]]]` → `["match", x, [...], true, false]`.
   - Labels built with `format` (several scripts on two lines) →
     `["coalesce", ["get", "name:en"], ["get", "name"]]`.
   - A shield width from `["length", text]` → the digits of a numeric route,
     else 3.
   - A filter's per-feature zoom test (`["zoom"]` in a filter) is dropped;
     those features show from their layer's own minzoom.
   - A `text-font` chosen by an expression → its default choice.

   `test/unit/vector_map_test.dart` fails if any expression in either style
   is reported unsupported, if a layer other than `roads_oneway` (a zoom-16
   arrow layer with no paint) isn't read, if a font isn't bundled, or if a
   named icon is missing.
6. **Night is the `dark` style**, not darkened tiles; raster maps keep
   ADR-0030's darkening.
7. **The layer's cache** of drawn tiles goes in a per-run folder under the
   system temporary directory (on the truck the dashboard's `PrivateTmp`),
   emptied on first use and capped at 16 MB, so a tile half-written at power
   loss is never read back and nothing is written next to the map.
8. **`make map-region` builds vector by default** (`tools/maps/build-map.py`,
   renamed from `build-raster-map.py`): the Protomaps extract with metadata
   set (plain-text attribution "© OpenStreetMap contributors · Protomaps",
   the build date, the ODbL notice, a centre at zoom 12). It needs only
   `pmtiles` and curl. `--format webp|png|jpg` still renders raster
   (ADR-0031). The vector data stops at zoom 15; the screen zooms past it
   (overzoom) and stays sharp.
9. The reader decodes the common HTML entities in an attribution
   (`&copy;` → ©), as Protomaps builds use them.

## Consequences

- Building a large region is a download: the simulator's area took 4 s.
  Sizes are close to WebP's, not much smaller: measured per-tile averages put
  Washington–Idaho–Utah's bounding box to zoom 15 at about 1.4 GB if it were
  all rural (WebP: 1.7 GB). The estimate's urban column is far too high for
  real regions; it comes from one city-centre sample.
- **Pi performance, measured on the bench (2026-11-11, bench-log):** the
  map fills about 1.7 s after the Nav tab opens; while zooming or dragging,
  undrawn patches fill within about a second, and the dashboard uses up to
  three of the Pi 5's four cores, back to 3–5% when the map stops. Night
  style and a moving fix not yet seen on the Pi. If it ever can't keep up,
  rebuild the region as raster (`MAP_ARGS=--format=webp`): the dashboard
  draws both.
- What the rewrite loses: labels are one line in English or the local name;
  some places of interest show earlier than the upstream style intends; town
  and city labels use one weight. A newer `vector_tile_renderer` may parse
  more; the style test shows what changes.
- `vector_map_tiles` 9.x is a beta and the override is outside pub's
  constraints: any update of these three packages needs the tests above and
  a look at a rendered map.
- The map is still north-up. Turning it with the truck is now possible
  (labels stay along roads when rotated, seen in the spike) but not built.
- Third-party notices: the fonts' OFL and the style and icon licences are in
  `assets/map/README.md`. The map data's ODbL attribution is on screen.
