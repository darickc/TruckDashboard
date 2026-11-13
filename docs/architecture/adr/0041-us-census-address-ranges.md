# ADR 0041 — US Census address ranges place the house numbers OpenStreetMap lacks

- **Status:** Accepted. [SIM] only:
  - the reader, the interpolation, the search, the service and the dashboard are tested with made-up data
    (`make test`);
  - built on the Mac with the Census's real files for Kansas and for the lower 48, and searched there;
  - **not on the Pi**: bench check 20 (search on the Pi) covers it once the index is on a stick.
- **Date:** 2026-11-12
- **Refines:** [ADR-0038](0038-offline-address-search.md) (offline address search; its consequence "no house-number
  interpolation"). Phase 6.5.3.

## Context

On 2026-11-12 the owner searched for their own rural address. OpenStreetMap
has no house numbers on that street, and no interpolation lines, so the
search found only the street ("no such number"). openstreetmap.org's own
search finds it because Nominatim adds the US Census Bureau's TIGER address
ranges (bench-log 2026-11-12). Rural US addresses are mostly like this: OSM
has few house numbers outside towns.

What the Census publishes, checked on 2026-11-12 (V: verified, with the
source; U: unverified):

| Fact | Status | Source |
|---|---|---|
| The **TIGER/Line Shapefiles** carry *potential* address ranges, not individual addresses. Two products have them: **EDGES** (every edge, ranges in `LFROMADD`/`LTOADD`/`RFROMADD`/`RTOADD`) and **ADDRFEAT**, "Address Range-Feature" (only edges with a range, one row per range) | V | catalog.data.gov's ADDRFEAT entries; the 2012 technical documentation's Appendix A (through a web search summary); the files themselves |
| TIGER/Line **2026** is out: `https://www2.census.gov/geo/tiger/TIGER2026/ADDRFEAT/` lists **3,227** county zips `tl_2026_SSCCC_addrfeat.zip` (SS state FIPS, CCC county), dated 2026-10-06, **2.69 GB** in all, **2.66 GB** for the lower 48 and DC (3,109 files). EDGES is 3,235 zips, 10.45 GB | V | the directory listings, read 2026-11-12 |
| Each zip holds a shapefile: `.shp` (polylines, one part each in the counties read), `.dbf` (attributes, UTF-8 by its `.cpg`), `.shx`, `.prj` (GCS North American 1983) and ISO metadata XML | V | three county files (20001 KS, 36081 NY, 55133 WI) |
| The fields: `FULLNAME` (the street's name with its abbreviations, "N Main St", "Co Rd 12"), `LFROMHN`/`LTOHN`/`RFROMHN`/`RTOHN` (left and right side's numbers at the edge's from and to end), `PARITYL`/`PARITYR` (`O`, `E`, `B`), `ZIPL`/`ZIPR`, `PLUS4L`/`PLUS4R`, `OFFSETL`/`OFFSETR`, `LFROMTYP`… (`I` for a number the Census imputed at a split), `EDGE_MTFCC`, `ROAD_MTFCC`, `TLID`, `LINEARID`, `ARIDL`/`ARIDR` | V | the files' own `.shp.ea.iso.xml` |
| **"From" is at the line's first point**: where two pieces of one street meet, the numbers agree that way in 14,162 of 14,205 joins (43 the other way) | V (measured) | the three county files, a script in the session's scratchpad |
| Ranges often run backwards (from > to: 2,822 sides in the Kansas county's 3,994 rows). Some numbers aren't digits: Queens, NY "10-09" (140,411 fields there); Wisconsin's grid "S110W14498" (45,836 in the county read) | V | the same files |
| **Licence**: "The TIGER/Line Shapefile products are not copyrighted however TIGER/Line and Census TIGER are registered trademarks of the U.S. Census Bureau. These products are free to use in a product or publication, however acknowledgement must be given to the U.S. Census Bureau as the source." | V | `useLimitation` in each file's `.shp.iso.xml` |
| The state FIPS codes (01 AL … 56 WY) | V | `https://www2.census.gov/geo/docs/reference/state.txt`, compared with `build-search.py`'s table by a script |
| NAD83 and WGS 84 differ by about a metre in the lower 48 | U (common knowledge, not re-checked) | — |

How **Nominatim** uses TIGER, the reference the owner compared with:

| Fact | Status | Source |
|---|---|---|
| Its TIGER data is prepared by [osm-search/TIGER-data](https://github.com/osm-search/TIGER-data) (GPLv2 scripts, GDAL) from **EDGES**, not ADDRFEAT: `LFROMADD`…`RTOADD`, `ZIPL`/`ZIPR`, `FULLNAME`, the county's name as the city | V | `lib/parse.py`, `convert.sh`, README at master, read 2026-11-12 |
| It draws each side as a line 30 ft beside the road, pulled back 45 ft from the ends, and skips ranges that aren't integers | V | `lib/convert.py` |
| The result is one CSV per county (`from;to;interpolation;street;city;state;postcode;geometry`), published as `tiger2025-nominatim-preprocessed.csv.tar.gz`; `-latest` is 1.9 GB, last modified 2025-11-27 (so TIGER 2025, a year older than the Census's 2026) | V | nominatim.org/data listing and a HEAD request |
| `nominatim add-data --tiger-data` imports it into separate tables, queried at search time; the whole US adds about 10 GB to the database | V (docs, through a web search summary) | Nominatim docs, "Installing TIGER housenumber data for the US" |

## Decision

1. **Source: the Census's own ADDRFEAT files, TIGER/Line 2026**, pinned in
   `tools/maps/build-search.py` (`TIGER_YEAR`). Not Nominatim's preprocessed
   CSV: that is a year older, goes through GPL'd scripts we'd depend on, and
   moves every range 30 ft off the road (a route should end on the road). Not
   EDGES: four times the download for the same ranges.
2. **Download per county, resumable.** `make search-region` does it for a US
   region's states (`north-america/us` is all 50 and DC;
   `north-america/us/kansas` is Kansas), or `--tiger-states KS,NE` for
   `--pbf` input; `--no-tiger` leaves them out. The year's file list is kept
   (`files.txt`); each zip is fetched once, to `.part` then renamed, and one
   already there is kept if it opens as a zip with a `.shp`. Four at a time.
   They stay in `build/search/tiger/TIGER2026/ADDRFEAT/`.
3. **Read without GDAL** (`tools/search-index/src/tiger.rs`): a small zip
   reader (stored and deflate, CRC-checked, with `flate2`, already in the
   lockfile), the shapefile's polylines and the dBASE records. A damaged
   download fails the build and names the file. Only numbers of plain digits
   are kept, as Nominatim does; the others are counted and left out. With
   `--bbox`, only ranges whose line starts in the box.
4. **Keep TIGER's own line; don't match it to an OSM way.** Each street's
   pieces are joined per name and town exactly as OSM's streets are (the
   nearest OSM town to each piece, or a 0.25° cell away from towns; ADR-0038
   decision 1), and each row gets its state from the same OSM boundaries.
   Matching to OSM by name and geometry would be slower, would fail where the
   names differ ("Co Rd 12" against "County Road 12"), and would gain little:
   routing starts from whichever road is nearest the point anyway.
5. **Schema 4** (`crates/geocode/src/index.rs`): `ranges` (one row per
   street and town, with where its pieces are), `range_edges` (each piece:
   both sides' from, to, parity and ZIP code, and its line as zigzag varints
   of 1e-6° steps, `crates/geocode/src/line.rs`) and `range_terms` (FTS5 over
   the name, town, state and cells, like `terms`). A street's pieces have
   consecutive rowids, so no index is needed. `postcodes` gains `source`.
   "co" ↔ "county" and "tpke" ↔ "turnpike" join the word table (TIGER's
   abbreviations). `meta.ranges_source` says "US Census Bureau TIGER/Line
   2026".
6. **ZIP codes OSM lacks** are placed at the median middle of the ranges that
   carry them (`postcodes.source` = Census), so "…, 99001" works where no
   OSM address has that ZIP code. OSM's position wins where both have one.
7. **Search** (`crates/geocode/src/search.rs`): a query with a house number
   also asks `range_terms` for the street, in the same rings (around the
   truck, wider, anywhere), reads the pieces of the nearest 64 streets found,
   and finds a side that holds the number: inside its range (either way
   round), of the right parity. The position is the fraction of the way from
   the "from" end, along the line by length. A side whose ZIP code is the one
   the query ended with comes first and scores +1.0. An estimate scores 2.5
   (a mapped address 3.0), so a real address ranks above an estimate in the
   same place; one with the same number and street in the same town hides
   the estimate, and an estimate hides the OSM street it lies on (the old
   "no such number"). Weights are examples, set by hand.
8. **Labelled honestly.** The result is a new kind, `MATCH_KIND_ESTIMATED_ADDRESS`
   in `search.proto` (`Match::Estimated`): ESTIMATED on the Search panel, with
   "Estimated from US Census address ranges" under it in the advisory colour,
   and its ZIP code in the subtitle. `SearchResponse.address_ranges` carries
   the source, and the footer names it next to OpenStreetMap: the Census's
   required acknowledgement. A dashboard that doesn't know the kind shows it
   as a place name (the least it can claim).

## Consequences

- **Accuracy** (Kansas, against the 4,430 of 5,155 sampled OSM-mapped
  addresses that a range holds): the estimate is a median 58 m from the
  mapped point, 92 m at the 75th percentile, 158 m at the 90th, 276 m at the
  95th; 79 % within 100 m, 94 % within 250 m [SIM]. OSM's point is often the
  building, TIGER's line the road's centre, so part of that is the
  driveway. Enough to route to the right stretch of road, not to the door.
- **Kansas:** 377,809 pieces of street from 105 county files, 603,170 sides
  with a range on 79,370 streets, 250 more ZIP codes; the index grows from
  37 MB to 63 MB and builds in 3 s (download not counted) [SIM].
- **The lower 48:** see the measurements below: +2.0 GB (7.2 GB) and
  +3.5 minutes of build, no more memory, 0–3 ms more per search.
- **The Census's server rate-limits.** At 4 downloads at once (about 5 files
  a second) it began answering every request with a "Request Rejected" page
  (HTTP 200, HTML) after about 2,600 files, and was still refusing 40 minutes
  later [2026-11-12]. The download now runs 2 at a time with a pause,
  recognises that page, waits 1, 2, 5 and 10 minutes, then stops with a
  message; files already there are kept, so the same command carries on.
  By the next morning it served files again, except one: Kimble County,
  Texas (`tl_2026_48267_addrfeat.zip`, the file it was on when the limit
  began) was still refused while every other file came through, and a
  file of the same county from 2025 was served [2026-11-13]. So when the
  server refuses a file but still serves one already downloaded (its first
  four bytes), the file is tried once more and then left out with a
  warning; that county has no ranges until a later run fetches it.
- Ranges are potential numbers: a number inside one may not exist, and the
  estimate can't tell. The label says so.
- Hyphenated (Queens) and grid (Wisconsin) numbers aren't estimated.
- A TIGER name spelt differently from OSM's can list both an estimate and the
  OSM street ("no such number").
- Range streets are kept apart by county file: the same road and town in two
  counties is two rows (both can be listed).
- TIGER is updated yearly. Changing `TIGER_YEAR` fetches a new year into its
  own folder; record it here.
- The index on the Pi is unmeasured, as before (bench check 20).

## Lower-48 measurements

On an M-series Mac (64 GB), 2026-11-12 and 13, from the OSM extract of 2026-11-11
clipped to the lower 48 (the same file as ADR-0038's build) [SIM]:

| | Without ranges (schema 4, like-for-like) | With 2,628 of the 3,109 county files (85 %) | With 3,108 of 3,109 (2026-11-13) |
|---|---|---|---|
| Census files | — | 2,628 zips, about 2.3 GB, downloaded in about 9 minutes before the server refused more | 3,108 zips, 2.66 GB (Kimble County, Texas refused, above) |
| Pieces of street read | — | 19,922,051 (172,743 sides of hyphenated or grid numbers, 110,551 pieces without a name or range left out) | 22,781,436 (419,954 sides of hyphenated or grid numbers, 265,845 pieces without a name or range left out) |
| Range sides / range streets | — | 32,314,202 on 6,024,264 streets | 36,914,592 on 6,871,660 streets |
| ZIP codes | 30,468 (OSM) | 36,457 (5,989 more from the ranges) | 37,347 (6,879 more from the ranges) |
| Index | 5,189 MB | 6,962 MB | 7,224 MB |
| Build (`search-index build`) | 427 s | 621 s | 638 s (700 s for `build-search.py` with the files already downloaded, a minute of it waiting on the refused file) |
| Peak memory (`time -l`) | 17.4 GB | 17.5 GB | 15.4 GB |

ADR-0038's "9.5 GB" was measured differently; built the same way, the index
without ranges peaks at 17.4 GB too, so the ranges add no memory. The last
column's figure was taken around `build-search.py` rather than
`search-index` alone; macOS's peak resident size also moves with what else
is using memory, so read the three as "about the same".
The 85 % build's extrapolation (about 7.3 GB and 11 minutes) was close.

Searches (warm, five runs each; the same queries on both files): queries
without a house number are unchanged (3–4 ms); with one, 9–70 ms against
8–69 ms before, the range lookup itself 1–3 ms. The first search after
opening takes up to 194 ms. On the full index the same queries take
4–73 ms warm.

Accuracy against OSM: of 37,080 sampled OSM addresses with a plain number
and no `addr:city`, 25,612 had a range holding the number on a street of the
same name and town (the rest: no range, or the state wasn't downloaded). The
estimate was a median 41 m from OSM's point, 117 m at the 90th percentile;
87 % within 100 m, 98 % within 250 m [SIM]. On the full index, 33,497 of
37,108 sampled addresses had such a range; median 44 m, 126 m at the 90th
percentile, 85 % within 100 m, 98 % within 250 m [SIM, 2026-11-13].
