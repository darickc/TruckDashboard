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

**TODO (6.5.3):** a workflow that builds a raster tileset for the truck's
region and updates it over Wi-Fi or USB. Don't bulk-download tiles from the
OpenStreetMap tile servers: their usage policy forbids it.

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
