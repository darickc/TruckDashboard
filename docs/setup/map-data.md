# Map data: licences, storage and limits

What the navigation data is, where it comes from, what its licences ask,
how much room it takes, and what it **can't** be trusted for (Phase 6.5.4,
[ADR-0010](../architecture/adr/0010-offline-maps-routing.md)). How to build
and install it: [maps.md](maps.md).

**Routes are not checked for heavy vehicles or trailers.** See
[Limits](#limits).

## Where the data comes from

Four files, all built on the Mac and brought to the Pi on the map stick
([maps.md](maps.md#updating-the-map-in-the-truck-usb-stick)). Each is a
*Derivative Database* of OpenStreetMap in the ODbL's terms, plus the other
sources named.

| File on the Pi | Built by | Sources | Licence of the data | Credited on screen |
|---|---|---|---|---|
| `maps/map.pmtiles` | `make map-region` ([ADR-0031](../architecture/adr/0031-raster-map-build.md), [ADR-0032](../architecture/adr/0032-vector-map.md)) | A [Protomaps](https://docs.protomaps.com/basemaps/downloads) daily build: OpenStreetMap, and Natural Earth at low zooms | OSM: **ODbL**. Natural Earth: public domain | Bottom right of the Nav map, from the file's own metadata: "© OpenStreetMap contributors · Protomaps · data *date*". A map file without attribution shows "© OpenStreetMap contributors" |
| `routing/valhalla_tiles.tar` | `make route-region` ([ADR-0035](../architecture/adr/0035-routing-with-valhalla.md)) | Geofabrik's OpenStreetMap extracts; time zones from [timezone-boundary-builder](https://github.com/evansiroky/timezone-boundary-builder) release 2026d, downloaded by Valhalla 3.9.1's `valhalla_build_timezones` during the build | Both **ODbL** | By the map's credit: routes are only shown on the Nav map. See [the gap](#gaps-against-the-osmf-guideline) for a route with no map file |
| `search/search.sqlite` | `make search-region` ([ADR-0038](../architecture/adr/0038-offline-address-search.md), [ADR-0041](../architecture/adr/0041-us-census-address-ranges.md)) | Geofabrik's OpenStreetMap extracts; in the US, the Census Bureau's TIGER/Line address ranges (ADDRFEAT) | OSM: **ODbL**. TIGER/Line: not copyrighted, free to use, with acknowledgement of the U.S. Census Bureau as the source (each file's `useLimitation`, ADR-0041) | The search panel's footer: "Search data: *regions* · OpenStreetMap *date* · US Census Bureau TIGER/Line 2026 address ranges" |
| The map's styles, icons and fonts | `make map-assets`, committed in the app | Protomaps basemaps styles and sprites; Noto Sans | BSD-3-Clause (the visual design CC0), MIT-derived icons, SIL OFL 1.1: [assets/map/README.md](../../apps/infotainment/assets/map/README.md) | Not needed on screen |

Nothing is fetched from openstreetmap.org's tile servers, at build time or
in the truck ([maps.md](maps.md#building-a-real-map)). The time-zone source
was checked against Valhalla's 3.9.1 script on GitHub (2026-11-16), not
inside the pinned Docker image.

## What the licences ask of this project

From the [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/), the
[OSM copyright page](https://www.openstreetmap.org/copyright) and the
[OSMF Attribution Guideline](https://osmfoundation.org/wiki/Licence/Attribution_Guidelines)
(adopted 2021-06-25), all read 2026-11-16. This is a summary for this
project, not legal advice; the licence's text decides.

- **Showing the map in the truck.** The screen is a *Produced Work*. The
  ODbL asks for a notice only when a Produced Work is *used Publicly*, which
  it defines as use by people other than you or those under your control
  (section 1, 4.3). Rather than decide whether passengers make it public,
  the dashboard credits OpenStreetMap anyway, in the corner of the map, the
  place the guideline names for interactive maps. "© OpenStreetMap
  contributors" is one of the forms the guideline accepts.
- **Search and routing.** The guideline's safe harbour: an application that
  uses an OSM-based geocoder or routing engine credits OpenStreetMap; single
  results and turn instructions needn't carry it. The search footer and the
  Nav map do that.
- **Census data.** Acknowledge the U.S. Census Bureau as the source. The
  search footer does.
- **Sharing screenshots, photos or video of the screen** publicly: keep the
  map's credit in the picture (don't crop the corner). Credit OpenStreetMap
  and link to `https://www.openstreetmap.org/copyright` in the post or
  description.
- **Sharing the built files** (a map stick, `map.pmtiles`,
  `valhalla_tiles.tar`, `search.sqlite`) with anyone else makes them
  *publicly used* Derivative Databases. Then the ODbL asks for them to be
  under the ODbL (4.4), with a notice in or beside the data (the map file
  carries one in its metadata; the others need a README beside them), and
  for the recipients to be offered the files or the method that made them
  (4.6): here, the build tools in `tools/maps/` and `tools/search-index/`
  with their pinned inputs.
- **Building them for this truck** is not public use: no notice or offer is
  needed for the files themselves.

### Gaps against the OSMF guideline

The guideline's safe harbour also asks that the credit makes clear the data
is under the ODbL, for example by linking "OpenStreetMap" to
`openstreetmap.org/copyright`, and that where a link isn't possible, the
licence information can be found somewhere easy, such as a "Data licences"
item in a menu. Today:

| Gap | Where | Status |
|---|---|---|
| Nothing on the head unit names the ODbL or `openstreetmap.org/copyright`. The screen can't open links, so the fix is a **Data licences** page (for example in Settings) listing each source in the table above, its licence and that URL | Dashboard | **TODO** |
| With routing data but **no map file**, the Nav screen shows routes and no OSM credit at all (the credit comes from the map file) | `navigation_screen.dart` | **TODO**: show "© OpenStreetMap contributors" whenever routing or search data is in use |
| The routing and search files have no licence notice inside or beside them | `make route-region`, `make search-region` | Only matters if they are shared (above) |

## Storage

Everything lives on the data drive (`DATA_DRIVE=1`, the 500 GB NVMe since
2026-11-11), under `/var/lib/f250/storage/`. The import refuses if the data
drive isn't mounted, and keeps the old file on any failure
([ADR-0033](../architecture/adr/0033-map-updates-by-usb-stick.md)).

| Data | Path | Kansas | Lower 48 states |
|---|---|---|---|
| Map (vector, to zoom 15) | `maps/map.pmtiles` | A 100 km × 100 km area is roughly 10–165 MB at zoom 15, mostly by how urban it is ([maps.md](maps.md#building-a-real-map)) | 18.8 GB, on the Pi since 2026-11-11 `[BENCH]` |
| Routing | `routing/valhalla_tiles.tar` | 312 MB `[BENCH]` | 20.9 GB, on the Pi since 2026-11-11 `[BENCH]` |
| Search | `search/search.sqlite` | 63 MB with the Census ranges, 37 MB without `[SIM]` | 7.2 GB with the ranges (5.2 GB without); about 7 GB copied to the Pi 2026-11-13 `[BENCH]` |
| Saved places | `navigation/places.json` | A few kB | — |

- **The drive:** the lower 48 takes about 47 GB. An import writes the new
  file beside the old one before swapping it in, so it needs room for both
  at once: the map's import checks for the new map's size plus 64 MB
  (ADR-0033). The 500 GB drive has room for that.
- **The stick:** exFAT (FAT32 can't hold a file over 4 GB). A 29 GB stick
  holds the lower-48 map or its routing data, not both
  ([maps.md](maps.md#routing-data)); use one stick per file, or a bigger
  stick.
- **Without the data drive** (`DATA_DRIVE=0`, the SD card only): no map,
  routing or search data can be imported. Saved places stay on the card.
- **Building them** on the Mac needs much more: the lower-48 routing build
  needs about 70 GB free while it runs and the search build 15–17.5 GB of
  memory ([maps.md](maps.md#routing-data), [maps.md](maps.md#search-data)).

## Limits

**This is not a commercial navigation system, and not a safety system.**
Road signs, the road itself and the driver's judgement come first.

### Heavy vehicles and trailers

**No route is checked for heavy vehicles or trailers, and none is
guaranteed safe for them.** Every route on screen says "Not checked for
heavy vehicles or trailers" (ADR-0010, ADR-0035).

- By default the truck is routed **as a car** (`NAV_COSTING=auto`).
  Low bridges, weight limits, length limits, trailer and hazardous-cargo
  restrictions are not considered.
- `NAV_COSTING=truck` uses Valhalla's truck model, which does consider the
  restrictions OpenStreetMap has. Set only dimensions you have measured
  (`NAV_TRUCK_HEIGHT_M` and the rest, [maps.md](maps.md#on-the-pi)); the ones
  left empty are Valhalla's defaults, which are a large truck's, not this
  F-250's.
- Either way, **OpenStreetMap's restriction data is incomplete**: a bridge
  or road with no height or weight tag in the data is treated as
  unrestricted. With a trailer, check the route yourself.

### Data age and coverage

- **Offline and as of its date.** No traffic, closures, construction or
  detours. The map's date is in its credit and the search data's in the
  search footer. The map, routing and search files are built separately,
  so they can be from different days: rebuild them together. Protomaps
  keeps only recent daily builds, so an old map can't be rebuilt as it was
  ([ADR-0031](../architecture/adr/0031-raster-map-build.md)).
- **Only the region built.** A route can't leave the routing data; outside
  it Valhalla answers "No suitable edges near location". The map and search
  stop at their regions too. Build all three for the same area.
- **Travel times** are Valhalla's estimates from its own speed
  assumptions, not measured against this truck. There is no arrival time
  by the clock: the Pi has no clock source in the truck.

### Position

- **No GPS receiver is fitted yet** (H11). In the truck the Nav screen runs
  on the simulated receiver (`NAV_SIMULATE=1`) and says **SIMULATED**: its
  position is not the truck's.
- With a receiver: a route needs a current fix; when the fix goes stale
  (3 s, an example) guidance pauses, the route line greys and no distances
  are shown or spoken ([maps.md](maps.md#what-the-screen-shows)).

### Search

- OpenStreetMap's house numbers are sparse outside towns, so a result is
  often only the street or the town, and says so.
- **ESTIMATED** house numbers come from the Census ranges, placed along the
  street: on the lower-48 index a median 44 m from where OpenStreetMap maps
  the same address, 126 m at the 90th percentile `[SIM]`
  ([ADR-0041](../architecture/adr/0041-us-census-address-ranges.md)). The
  number may not exist.
- Misspellings find nothing.

### Spoken directions

- Nothing is said without a current position, and a prompt that can't be
  said at once is dropped, never said late
  ([maps.md](maps.md#spoken-directions)).
- Heard from audio-manager on the bench Pi (Piper, 2026-11-15); not yet
  from a route on the Pi (bench check 22).
