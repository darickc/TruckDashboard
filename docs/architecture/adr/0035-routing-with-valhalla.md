# ADR 0035 — Routing with Valhalla, one request per process, in services/navigation

- **Status:** Accepted. [SIM] and [BENCH]:
  - the guide's transitions are unit-tested;
  - the service is tested end to end against a fake `valhalla_service` that replays Valhalla 3.9.1's real output;
  - it ran against the real Valhalla 3.9.1 (Docker) with routing data for Kansas, the simulated receiver driving the route;
  - **on the Pi 5** (2026-11-11, bench-log): meta-f250's Valhalla 3.9.1 routes under `f250-navigation.service`'s
    sandbox, 0.13–0.2 s and about 30–40 MB a request for Kansas, with the same answers as the Docker image; a route
    showed on the Nav screen. Not yet from a flashed image, a real stick or a multi-state extract (decision 7).
- **Date:** 2026-11-11
- **Refines:** [ADR-0010](0010-offline-maps-routing.md) (routing) and
  [ADR-0030](0030-navigation-position-and-raster-map.md) decision 1 (routing
  joins services/navigation). Phase 6.5.2.

## Context

ADR-0010 chose Valhalla for offline routing, to be prototyped once the map
worked. It now does. Facts checked on 2026-11-11:

- Valhalla's latest release is **3.9.1** (2026-10-06). It needs C++20,
  Boost, Protobuf and zlib; LZ4, curl, GeoTIFF and the HTTP server are
  optional.
- The HTTP service needs **prime_server** (ZeroMQ). Without it
  (`ENABLE_SERVICES=OFF`), `valhalla_service CONFIG ACTION REQUEST` still
  answers one request and exits (`src/valhalla_service.cc` at 3.9.1).
- Routing at run time needs only the **tile extract** (`valhalla_tiles.tar`)
  and a config. It ran with every other data path pointed at nothing: no
  admin, time-zone, traffic or elevation files.
- The official image `ghcr.io/valhalla/valhalla:3.9.1` is multi-arch (amd64,
  arm64) and has every data tool. Homebrew has no Valhalla formula.
- Kansas (a 118 MB Geofabrik extract) builds in 27 s on an M-series Mac into
  a 312 MB extract of 493 tiles. A 24 km route takes 1.3 s from request to
  answer through Docker, startup included [BENCH].
- The project has no Yocto recipe for Valhalla, and none was found to reuse:
  the OpenEmbedded layer index refused the query (HTTP 403), so this is
  **UNVERIFIED**.

## Decision

1. **services/navigation does the routing** and serves
   `f250.nav.v1.RouteService` next to the position. Its calls are
   `SetDestination`, `ClearRoute`, `WatchGuidance` (a stream) and
   `GetRoute`. The dashboard still talks only to this service.
2. **One `valhalla_service` process per route request**, in Valhalla's
   one-shot mode, with a 30 s limit. There's no prime_server, no ZeroMQ and
   no listening port. A crash, a runaway request or its memory ends with the
   process, and a new destination kills a request still running. Requests
   are rare: a destination, or leaving the route. Before each request
   navigation writes the config to `/run/f250-nav/valhalla.json`, from a
   template pinned to Valhalla 3.9.1
   (`services/navigation/valhalla/valhalla-3.9.1.json`, installed under
   `/opt/f250/share/data/valhalla/`), pointed at the tile extract.
3. **The guide decides, and is pure.** `guide.rs` takes time as an argument,
   so every transition is tested. The states are unavailable, idle, routing,
   active, failed and arrived.
   - **Matching:** the fix goes to the nearest point on the route line. Points
     behind the last match cost extra, so a route that doubles back doesn't
     jump.
   - **Progress:** the next maneuver and the distance to it, the distance left,
     and Valhalla's time estimate scaled by how much is left.
   - **Off the route:** farther than 60 m from the line for 5 s.
   - **New routes:** asked for from the current position and course, at most
     one every 15 s.
   - **Arrival:** within 40 m. These four limits are examples to tune on the
     truck (CLAUDE.md rule 10).
   - A first route that fails waits for **Retry**. A failed reroute is retried
     at the same interval, and the old route stays on screen meanwhile.
4. **Stale data is never shown as current** (rule 4). Progress is computed
   and sent only from a current fix. Without one, guidance says it is
   waiting, sends no distances, and the screen greys the route line. The
   dashboard also stops showing progress when guidance messages stop for
   3 s or the link drops.
5. **Costing is `auto`** by default: the F-250 is routed as a car. `truck`
   costing is available (`NAV_COSTING=truck`). Only the dimensions the owner
   sets (`NAV_TRUCK_*`) are sent; the others are Valhalla's defaults, which
   are a large truck's. Either way, **every route on screen says "Not checked
   for heavy vehicles or trailers"** (ADR-0010).
6. **Destinations come from a long-press on the map**, then **Route here**.
   Searching by address needs an offline geocoder, which is a separate job
   and not done. *Since 2026-11-12 also from address search:
   [ADR-0038](0038-offline-address-search.md).*
7. **Packaging, in stages:**
   - **Routing data:** `make route-region REGION=<Geofabrik path>` builds it on
     the Mac in the pinned image. It downloads the region's extract from
     Geofabrik, checks its MD5, and writes `build/routing/valhalla_tiles.tar`
     (a copy goes to `/tmp/f250/routing/` for `make navigation` and
     `make sim`). The Pi reads `/var/lib/f250/storage/routing/valhalla_tiles.tar`.
   - **On the Mac,** navigation runs Valhalla through
     `tools/dev/valhalla-docker.sh`: the same arguments, in the image, with no
     network.
   - **The Pi image** has the config template, the settings and, since
     2026-11-11, Valhalla: `agl/meta-f250/recipes-navigation/valhalla/valhalla_3.9.1.bb`
     builds tag 3.9.1 (gitsm, its vendored submodules at the tag's commits)
     with `ENABLE_SERVICES=OFF`, `ENABLE_DATA_TOOLS=OFF`, `ENABLE_HTTP=OFF`,
     `ENABLE_GEOTIFF=OFF`, `ENABLE_LZ4=OFF` (elevation and PBF only),
     `ENABLE_PYTHON_BINDINGS=OFF`, `ENABLE_TESTS=OFF` and a static
     libvalhalla, and packages only `/usr/bin/valhalla_service` (7.7 MB; it
     links protobuf-lite, abseil, zlib, libstdc++). `valhalla_service` is built
     by `ENABLE_TOOLS`, not `ENABLE_SERVICES`. Two build details: the target
     Protobuf has no compiler, so `protoc-native.cmake` points the
     `protobuf::protoc` target at the host's; and `ENABLE_SINGLE_FILES_WERROR=OFF`,
     because this GCC deprecates `std::atomic_load` on `shared_ptr` in C++20
     and Valhalla builds `graphreader.cc` with `-Werror`.
   - **Routing data on the Pi** comes on the map stick: `make map-stick
     ROUTING=build/routing/valhalla_tiles.tar` adds `f250/routing.tar`, and
     the stick's import checks it and swaps it in at
     `/var/lib/f250/storage/routing/valhalla_tiles.tar`
     ([ADR-0033's amendment](0033-map-updates-by-usb-stick.md#amendment-routing-data-on-the-same-stick-2026-11-11)).
     navigation notices it within a second; no restart.
8. **The simulated receiver drives the route** while there is one, and goes
   back to its loop when the route is cleared. Guidance can then be seen
   working end to end without a receiver. It is labelled simulated all the
   way to the screen.

## Consequences

- Routing works on the Mac (`make route-region`, then `make sim`) and on the
  Pi (the image's Valhalla, the routing data from the map stick).
- `f250-navigation.service` now starts a child process. Its sandbox applies
  to the child too: MemoryDenyWriteExecute, the `@system-service` syscall
  filter, and `ProtectSystem=strict` with only `/run/f250-nav` writable.
  **Verified on the Pi 5** (2026-11-11): Valhalla 3.9.1 routes under it,
  nothing denied.
- Each request loads the tile index again. Kansas (312 MB, 493 tiles) on the
  Pi 5: 0.13–0.2 s a request with the file in the page cache, 0.36–0.92 s
  from the card cold; a peak of 28–37 MB (up to 84 MB cold, page cache
  counted), for routes of 23–653 km [BENCH]. A multi-state extract is **not
  measured on the Pi**; the 30 s limit is far off for one state.
- **The lower 48** (2026-11-12, [BENCH] on the Mac): Geofabrik's
  `north-america/us` (12 GB) includes Alaska and Hawaii, which the owner
  doesn't want, so `build-routing.py --bbox` clips it to the lower-48 map's
  box with osmium first. 72 minutes into a 20.9 GB extract of 15,099 tiles
  (the whole US: 21 GB, 17,178 tiles). In one `valhalla_build_tiles` process
  the US ran out of Docker's 8 GB at the "enhance" stage with 8 threads, so
  the build now runs in two processes: up to "build", then "enhance" to the
  end (`--late-concurrency`, `--resume`). Routes in the Docker image: 65 km
  in 0.4 s, 974 km in 0.4 s, 5,319 km (Seattle to Miami) in 1.9 s with a
  690 MB container peak, page cache counted.
- No voice prompts, lane guidance, ETA by clock (the Pi has no clock source
  in the truck), address search or saved places. Each is a later piece.
- OSM data is ODbL. The map's attribution is already on screen, and the
  routing data comes from the same source.
