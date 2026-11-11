# ADR 0010 — flutter_map with offline tiles; Valhalla for routing

- **Status:** Proposed. Prototyped in Phase 6 before committing. Map display
  and position refined by [ADR-0030](0030-navigation-position-and-raster-map.md)
  (2026-11-11): raster tiles in one PMTiles file, because the Flutter
  vector-tile stack needs protobuf 3 and the app's gRPC needs 6. Routing as
  below.
- **Date:** 2026-11-01

## Context

Navigation must work without internet, using OpenStreetMap data, inside a
Flutter app on AGL (Linux, Wayland, flutter-auto).

| Candidate | Fit | Concern |
|---|---|---|
| MapLibre GL (native) | Fast vector rendering | Its Flutter plugin targets mobile and web. Linux/embedder support is unverified |
| Qt Location | Mature | Means a Qt app, against the Flutter decision |
| **flutter_map** | Pure Dart. Works wherever Flutter does. Offline MBTiles and PMTiles through community plugins | Vector-tile rendering performance on the Pi 5 is unverified; raster tiles are the fallback |
| **Valhalla** | C++, offline routing tiles, turn-by-turn narrative, truck costing model | Needs a Yocto recipe, a build and memory checks on the Pi 5 |
| GraphHopper | Good routing | JVM on the target |

## Decision

- **Map display:** `flutter_map` with an offline regional tileset (MBTiles or
  PMTiles) on the SSD.
- **Position:** gpsd with a USB GNSS receiver.
- **Routing:** Valhalla as a local service, prototyped after map display
  works.

## Consequences

- OSM data is ODbL. The UI must show the attribution, and the docs must cover
  the update procedure and storage needs.
- **Routing is not guaranteed safe for heavy vehicles or trailers.** OSM
  restriction data is incomplete. Valhalla's truck costing helps, but doesn't
  guarantee anything. The UI must say this.
