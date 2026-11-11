# ADR 0030 — Position from gpsd through services/navigation; a raster PMTiles map

- **Status:** Accepted. [SIM] only. The gpsd parser and tracker are tested
  against gpsd 3.27.5's own output, fed synthetic NMEA on the Mac. The service
  is tested end to end against a fake gpsd and ran against the real gpsd. The
  dashboard's PMTiles reader is tested against files written by the official
  `pmtiles` tool. No receiver is chosen yet (H11), and nothing has run on the Pi
- **Date:** 2026-11-11
- **Refines:** [ADR-0010](0010-offline-maps-routing.md) (map display and
  position; routing stays as decided there)

## Context

Phase 6.4 needs the truck's position and 6.5.1 an offline map. ADR-0010
chose `flutter_map` with an offline MBTiles/PMTiles tileset and gpsd. It
named raster tiles as the fallback if vector rendering didn't work out.

Two findings on 2026-11-11:

- **The Flutter vector-tile stack can't share the app.** `vector_map_tiles`
  (every 8.x and 9.x release) needs `vector_tile_renderer` → `vector_tile`
  → `protobuf ^3`. The app's gRPC client needs `protobuf ^6`, so pub can't
  resolve both. The `pmtiles` package's 2.x needs Dart 3.11; Flutter 3.38.3
  (pinned to the AGL engine) has Dart 3.10.1. Its 1.x needs `protobuf ^3`.
- **gpsd's output is uneven.** With an NMEA receiver, gpsd sends one TPV per
  sentence, each with what it knows so far. Some lack the course; once the
  fix is lost there is no position at all
  ([test vectors](../../../crates/gpsd/tests/data/README.md)).

## Decision

1. **A service owns the position: `services/navigation`.** It is gpsd's
   client on 127.0.0.1:2947 and serves `f250.nav.v1.PositionService` on
   `/run/f250-nav/nav.sock`. The dashboard never talks to gpsd (the pattern
   of CLAUDE.md rule 5). 6.5.2 adds routing to the same service and package.
2. **The tracker never shows a stale fix as current** (rule 4). The status
   comes from the newest TPV younger than the stale limit: gpsd unavailable,
   no receiver, receiver silent, no fix, 2D, 3D. The last good fix is always
   kept and reported with its age. It is *current* only while the status is a
   fix and the fix is within the limit (3 s, an example to tune once a
   receiver is fitted). A field missing from one TPV (the course, say) keeps
   its previous value only while that value is itself within the limit, and
   keeps its own age.
3. **The dashboard checks again.** Each message carries the stale limit; a
   fix stops being current when the stream stalls longer than that, or when
   the link drops. The screen then shows "LAST KNOWN · n S AGO", a grey
   marker, and the reason.
4. **A simulated receiver** (`navigation --simulate`, and the app's own for
   the browser preview) drives a loop near Lebanon, Kansas. It is labelled
   simulated in the API and on the screen. It can lose its fix on a schedule
   to exercise the stale path.
5. **The map is raster tiles in one PMTiles v3 file**, read by the dashboard
   itself at `/var/lib/f250/maps/map.pmtiles` (`MAP_FILE`). Raster, because
   of the conflict above, and because rendering raster tiles costs the Pi
   little. PMTiles, because one file is easy to copy and replace (the 6.5.3
   update workflow), and its format is small enough to read in pure Dart
   without new dependencies (`lib/nav/pmtiles.dart`). PNG, JPEG and WebP
   tiles; gzip or no compression. Vector tiles, AVIF, brotli and zstd are
   refused, with the reason on screen.
6. **The map is never needed for the position.** With no file, a bad file or
   the browser preview, the screen says why and still shows the fix and its
   status.
7. **Attribution is always on screen** while a map is shown: the tileset's
   own `attribution` metadata, else "© OpenStreetMap contributors".
8. **Night mode** darkens the raster tiles with flutter_map's
   `darkModeTileBuilder` rather than shipping a second tileset.
9. **gpsd comes back into the images** (`gpsd`, `gpsd-conf`, `gpsd-udev`,
   names from the 22.0.1 demo image's manifest). `f250-navigation.service`
   pulls in `gpsd.socket`. Its sandbox allows AF_INET/AF_INET6 to localhost
   only, since gpsd's client protocol is TCP.

## Consequences

- Making a raster tileset for the truck's region is its own job (6.5.3),
  decided in [ADR-0031](0031-raster-map-build.md): `make map-region` renders
  one locally from OpenStreetMap data. Nothing downloads tiles from the OSM
  tile servers; their policy forbids bulk downloads. `make map-test-pattern`
  still writes a test pattern that plainly says it isn't a map.
- Raster tiles are bigger than vector tiles for the same area and zooms, and
  labels can't be restyled or rotated. North-up only.
- The macOS app gained its first plugin (`path_provider`, through
  flutter_map). It builds with Swift Package Manager (pubspec
  `enable-swift-package-manager`), so CocoaPods is still not needed. The
  Debug build may read `/tmp/f250/maps/` (a sandbox exception) for the
  development map.
- UNVERIFIED on the Pi: that `gpsd.socket` listens on 127.0.0.1:2947 in the
  AGL image, that gpsd-udev starts gpsd for a USB receiver, and how the map
  performs on the Pi 5. Each needs a bench check once a receiver is
  fitted (H11).
- power-manager still takes its location from `DISPLAY_LATITUDE` and
  `DISPLAY_LONGITUDE`. Feeding it the GPS position and time (ADR-0028) is a
  follow-up.
