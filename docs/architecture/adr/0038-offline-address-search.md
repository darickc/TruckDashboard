# ADR 0038 — Offline address search: a SQLite FTS5 index of OSM addresses, streets, towns and places

- **Status:** Accepted. [SIM] only:
  - the index builder, the search and its ranking, the service and the dashboard are tested (`make test`);
  - built on the Mac from Geofabrik's Kansas extract and from the lower 48, and searched there through the real
    service over gRPC;
  - **not yet on the Pi**: the bench Pi didn't answer on 2026-11-12. Bench check 20 in
    [agl.md](../../setup/agl.md#5-bring-up-checks-phase-52) is the next step.
- **Date:** 2026-11-12
- **Refines:** [ADR-0035](0035-routing-with-valhalla.md) decision 6 (destinations only by long-press) and
  [ADR-0033](0033-map-updates-by-usb-stick.md) (what the map stick carries). Phase 6.5.3.

## Context

The Nav screen sets a destination only by a long-press on the map. The owner
wants to type an address or a place and route to it, with no network: the
truck has none to count on.

Geocoders that run offline, checked 2026-11-12:

| Option | What it needs | Fit for the Pi 5 (8 GB, NVMe) |
|---|---|---|
| Nominatim | PostgreSQL + PostGIS server and an import. At least 2 GB RAM; a planet import wants 128 GB+ RAM and 1 TB disk, on NVMe | A database server on the head unit, kept up to date by imports. Too heavy |
| Photon | Java 21, an embedded OpenSearch 3; a planet index is about 95 GB. Built from a Nominatim database | A JVM and a search engine for one screen. Too heavy |
| Pelias | Elasticsearch plus several Node services; about 8 GB RAM to build a region | More RAM than the Pi has to spare |
| **SQLite FTS5 index** | SQLite with FTS5. The image's SQLite has it: OE-core's `sqlite3_3.51.3` in the Vimba 22.0.1 tree builds with `PACKAGECONFIG ?= "fts4 fts5 rtree dyn_ext"`; the Mac's `rusqlite` bundles it | One read-only file. No server, no JVM, nothing running between searches |

The figures for the first three come from their documentation (Nominatim's
installation guide, Photon's README, Pelias's documentation), read through a
web search on 2026-11-12. They are listed with their status in the
[compatibility matrix](../../hardware/compatibility-matrix.md).

## Decision

1. **The index is one SQLite file of FTS5 tables**, built on the Mac from the
   same Geofabrik extract as the routing data (`make search-region`,
   `tools/maps/build-search.py`, which reuses `build-routing.py`'s download and
   clip). `tools/search-index` (Rust, `osmpbf`) reads the extract in two
   passes and writes `build/search/search.sqlite`.
   - **What goes in** (`tools/search-index/src/extract.rs`): towns
     (`place=city|town|village|hamlet|suburb|quarter|neighbourhood|locality`),
     named road ways (not links, paths or footways), named places (`amenity`,
     `shop`, `tourism`, `leisure`, `office`, …, without street furniture) and
     addresses (`addr:housenumber` + `addr:street`). Relations and address
     interpolation lines are not read.
   - **Towns for everything:** an address's own `addr:city`, else the nearest
     city, town, village or hamlet within its reach (30, 15, 8, 4 km), shown
     as "near …". A street's pieces become one row per name and town.
   - **States:** with osmium, the extract's state boundaries (`admin_level=4`)
     are exported and every row gets its state, so "Kansas City · KS" and
     "Kansas City · MO" differ. Only the short name is searchable ("main st
     lebanon ks"): the full name would make "kansas city" match everything
     named "City" in Kansas.
   - **Words** (`crates/geocode/src/text.rs`): lowercase, Latin accents
     dropped, apostrophes removed. The index also holds each word's other US
     form ("street" ↔ "st", "north" ↔ "n", "saint" ↔ "st", "first" ↔
     "1st"), so the search needs no rewriting of its own.
   - **Three FTS5 tables**, contentless, so no question pays for what it
     doesn't ask: streets and named places (`terms`), towns (`towns`), and
     anything with a house number (`addrs`). Rows carry their 1° and 5° cell
     as tokens.
   - The file says what it is: `PRAGMA application_id` "F250" and
     `user_version` 1. The search refuses anything else.
2. **It comes on the map stick** as `f250/search.sqlite`, with its checksum,
   next to the map and the routing data (`make map-stick SEARCH=...`). The
   import checks it (checksum, SQLite header, application id) and swaps it in
   at `/var/lib/f250/storage/search/search.sqlite`. `usb-export` counts a
   stick with it as a map stick ([ADR-0037](0037-recordings-to-a-usb-stick.md)).
3. **services/navigation serves it** as `f250.nav.v1.SearchService.Search`
   (`shared/proto/f250/nav/v1/search.proto`). It opens the file read-only
   (immutable) on the first search and reopens it when the stick's import
   renames a new one in. No index, or a bad one, is an answer that says why,
   never an error. The dashboard only talks to the service (CLAUDE.md rule 5).
4. **Ranked near the truck**, from the latest fix, current or last known (the
   answer says which, and how old). Every word must match; the last one may be
   unfinished while typing (a prefix from three letters, two for town names;
   never for words of their own like "st"). Candidates come in rings: the 1°
   cells around the truck, then the 5° cells, then anywhere, each only while
   too few were found. The score (`crates/geocode/src/search.rs`) puts an
   address with the asked house number first, then a name spelled out in full
   (much more for a town: "fairview" is the town, not Fairview Road), a town's
   size, and subtracts 1.5 per tenfold distance. These weights are examples,
   tuned by hand on Kansas data.
5. **Honest about coverage.** OSM's house numbers are sparse outside towns.
   Every result says what it is: ADDRESS, STREET, TOWN or PLACE. A street
   found for "125 main st" says "Street only: no house number 125 in the map
   data"; a town found when its street isn't there says "Town only: “elm
   avenue” not found". The footer names the data (region, OSM date) and says
   house numbers are sparse.
6. **The Nav screen** gets a Search button. The panel has a field, an
   on-screen keyboard (letters, and digits and address punctuation; every key
   at least 60 px), results as they come (150 ms after typing stops), and on
   each result **Show** (on the map, then Route here or Cancel) and **Route
   here** (the existing `SetDestination`). It fits at 800×480 under the alert
   banner too.
7. **Typing while moving is not locked out** (owner's decision, 2026-11-12,
   [assumptions](../../safety/assumptions.md#driver-distraction)). Above
   8 km/h (5 mph, an example) by a current vehicle speed, else a current GPS
   speed, the panel says "The truck is moving: type only when parked".

## Consequences

- Kansas: 204,083 addresses, 79,807 streets, 1,770 towns and 29,058 named
  places; 37 MB; built in 2 s. Searches take 0.1–2.4 ms on an M-series Mac
  [SIM].
- The lower 48 (Geofabrik's US clipped to its box): 35.2 million addresses,
  7.0 million streets, 206,106 towns and 2.9 million named places; 4.9 GB;
  built in about 8 minutes with 9.5 GB of memory at its peak. Warm searches
  take 1–75 ms on the Mac, the first after opening up to 185 ms [SIM]. An
  earlier layout (one table, `ORDER BY rank`, two-letter prefixes) took up to
  1.9 s; that is why there are three tables and no rank ordering. **The Pi 5
  is unmeasured.**
- A US-sized index, routing data and map don't fit one 29 GB stick together;
  the import takes any subset.
- No fuzzy matching (a misspelt word finds nothing), no house-number
  interpolation along a street, no places mapped only as relations, no saved
  places and no recent searches. Each is a later piece.
- Same-named towns in a state are told apart only by distance.
- OSM data is ODbL. The footer names OpenStreetMap; the map's attribution is
  on screen as before.
