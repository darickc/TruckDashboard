# ADR 0052 — Online navigation with Mapbox when there is a network; Wi-Fi set from the dashboard

- **Status:** Accepted (owner asked, 2026-11-23). [SIM], and against the
  real Mapbox from the Mac (2026-11-23, the owner's token):
  - a real Directions answer is recorded (`tools/dev/mapbox-record.sh`) and
    parsed in a test: the joined line within 1 % of Mapbox's length, every
    maneuver within 2 % of where Mapbox puts it.
  - the navigation program itself (`tests/mapbox_live.rs`, opt-in) got a
    route marked `mapbox`, day and night tiles, and kept the token out of
    its log.
  - `mapbox/navigation-day-v1` and `navigation-night-v1` serve 512 px PNG
    tiles from the Static Tiles API.
  - search (decision 11, added the same day after the owner found Search
    unavailable on the Mac without an index): the live test's search came
    from Mapbox. Its test vector is hand-written to the fields seen in real
    answers, which say they "may not be retained" and so aren't kept.
  - the hand-written vector stays for a toll and a motorway, which the
    recorded route lacks.
  - the network service's connman backend is not tested against connman.
    Its parsing is unit-tested; its D-Bus calls have not run on the Pi.
  - the dashboard's Wi-Fi settings and online map are tested against
    simulated services.
- **Date:** 2026-11-23
- **Refines:** [ADR-0035](0035-routing-with-valhalla.md) (routing),
  [ADR-0032](0032-vector-map.md) (the map),
  [ADR-0040](0040-saved-places-and-spoken-directions.md) (spoken directions),
  [ADR-0029](0029-settings-screen.md) (Settings),
  [ADR-0023](0023-bluetooth-belongs-to-bluez.md) (connman keeps Wi-Fi)

## Context

Navigation is offline: Valhalla routes from a tile extract, the dashboard
draws a PMTiles map, and both come on the map stick. The owner wants Mapbox
when the Pi is on a network (the phone's hotspot), for traffic and fresher
data, and the offline navigation as it is when there is none. The owner also
wants to join Wi-Fi from the dashboard: today it takes `connmanctl` over SSH
(docs/setup/agl.md).

Facts checked on 2026-11-23:

- **Mapbox's Flutter SDK (`mapbox_maps_flutter`) runs on Android and iOS,
  and on the web in its 3.0 alpha. Not on Linux** (pub.dev and its
  documentation). The dashboard runs under flutter-auto on Linux, so the
  SDK can't be used. Mapbox's Navigation SDKs are Android and iOS only.
- **The dashboard has no network**: `f250-dashboard.service` has
  `PrivateNetwork=yes`, `RestrictAddressFamilies=AF_UNIX`. navigation has
  `IPAddressAllow=localhost`, `IPAddressDeny=any`.
- **Mapbox Directions API** (docs.mapbox.com/api/navigation/directions,
  read 2026-11-23): `GET /directions/v5/mapbox/driving-traffic/{lon,lat;lon,lat}`
  with `geometries=polyline6`, `steps=true`, `voice_instructions=true`,
  `voice_units`, `banner_instructions`, `language`, `bearings` (`angle,range`
  per coordinate, empty to skip), and `max_height`/`max_width` (m) and
  `max_weight` (metric t) on the driving profiles. The answer's `code` is
  `Ok`, `NoRoute` or `NoSegment` (HTTP 200); 401 for a missing or invalid
  token, 403, 404 `ProfileNotFound`, 422 `InvalidInput`. A step's
  `voiceInstructions` announce the **next** step's maneuver, each with
  `distanceAlongGeometry`, metres before that maneuver. Maneuver `type` is
  one of 16 strings (`turn`, `new name`, `depart`, `arrive`, `merge`,
  `on ramp`, `off ramp`, `fork`, `end of road`, `continue`, `roundabout`,
  `rotary`, `roundabout turn`, `notification`, `exit roundabout`,
  `exit rotary`), `modifier` one of 8. Intersection `classes` include
  `toll`, `motorway`, `ferry`. The page has no complete example answer.
- **Mapbox Static Tiles API** (docs.mapbox.com/api/maps/static-tiles):
  `GET /styles/v1/{user}/{style}/tiles/{512|256}/{z}/{x}/{y}`, 512 px tiles
  one zoom level behind 256 px ones, `Cache-Control: max-age=43200` (12 h).
  The page names no navigation styles; `mapbox/navigation-day-v1` and
  `mapbox/navigation-night-v1` were checked by hand (2026-11-23): both
  answer with 512 px PNG tiles. Both are configuration.
- **Pricing** (mapbox.com/pricing, 2026-11-23): Directions free up to
  100,000 requests a month; Temporary Geocoding free up to 100,000 requests
  a month; Search Box API sessions (`/suggest` + `/retrieve`) free up to 500
  or 2,500 a month (two tables); the page doesn't list Search Box's
  `/forward`.
- **Mapbox Geocoding API v6** (docs.mapbox.com/api/search/geocoding,
  2026-11-23): `GET /search/geocode/v6/forward?q=` with `limit` (at most
  10), `proximity` (`lon,lat`), `country`, `language`, `autocomplete`
  (default true), `types`; `q` at most 20 words and 256 characters, no
  semicolons. "The Geocoding v6 API no longer provides POI data (use the
  Search Box API for POI search)." Results are temporary unless
  `permanent=true` (paid): "Temporary results are not allowed to be
  cached". Real answers (checked 2026-11-23) carry `feature_type`, `name`,
  `name_preferred`, `place_formatted`, `full_address`, `coordinates`
  (`latitude`, `longitude`, and for an address `routable_points`) and an
  `attribution` ending "This response and the information it contains may
  not be retained." A bad token is HTTP 401 `INVALID_TOKEN`.
- **Mapbox's Terms of Service** say: "If your Licensed Application is
  related to vehicle usage, you must purchase a separate development
  license." The owner was told, and decided: this is for the owner's own
  truck, not a product. Recorded here; it is the owner's account.
- **connman 2.0** keeps Wi-Fi (ADR-0023). Its D-Bus API is `net.connman`:
  `Manager.GetServices`/`GetTechnologies`/`GetProperties` (`State`:
  `offline`, `idle`, `ready`, `online`), `Technology.Scan`/`SetProperty
  Powered`, `Service.Connect`/`Disconnect`/`Remove`, and an agent
  (`net.connman.Agent.RequestInput`) for passphrases (connman's
  doc/*-api.txt; not read on the Pi's version, **UNVERIFIED** there).

## Decision

1. **Mapbox through its web APIs, from services/navigation.** Not the
   Flutter SDK, which can't run on the Pi. The dashboard stays without a
   network: navigation fetches routes and map tiles and serves them over
   its socket, as it serves everything else.
2. **The token** is a systemd credential: `/etc/credstore/mapbox-token`
   (root's, mode 0600), imported by `f250-navigation.service`
   (`ImportCredential=mapbox-token`), so only navigation reads it;
   `/etc/default/f250` is world-readable and doesn't hold it. On the Mac,
   `MAPBOX_ACCESS_TOKEN` in the environment. Without a token, nothing goes
   to Mapbox and navigation is offline as before. It is never logged and never on a
   command line: each request is one `curl` process (like ADR-0035's one
   Valhalla per request) that reads the URL from its standard input
   (`curl --config -`). No TLS code in the services; the image gets `curl`
   and `ca-certificates`.
3. **Routing tries Mapbox first, then Valhalla.** With a token, a route
   request goes to `mapbox/driving-traffic` (10 s limit). Any failure
   (no network, a timeout, an error answer) falls back to Valhalla at once,
   and Mapbox is skipped for 60 s after a failure that wasn't the route
   itself (an example; no network then shouldn't delay every reroute). The
   guide, off-route detection, rerouting and arrival are unchanged
   (ADR-0035): they don't care where a route came from. **Every route says
   which made it** (`Route.provider`: `mapbox` or `valhalla`), and the
   screen shows "Mapbox · traffic" or "Offline route".
4. **Truck costing** sends only the configured dimensions, as
   `max_height`, `max_width` and `max_weight`. "Not checked for heavy
   vehicles or trailers" stays on every route (ADR-0010).
5. **Mapbox's answer becomes the same Route.** The line is the steps'
   geometries joined; each step is a maneuver, its type mapped onto
   Valhalla's numbers for the icons (`mapbox.rs`, every pair tested). Spoken
   directions (ADR-0040) take Mapbox's words: a maneuver's approaching
   prompt is its instruction, its at-the-maneuver prompt the previous
   step's last announcement (the one with the smallest
   `distanceAlongGeometry`), and so is its approaching prompt, after
   "In half a mile,": the announcements are written for speech ("U.S.
   Highway 2 81"), the instructions for the eye ("US Highway 281/US 281.
   Continue on US 281.", seen in a recorded answer). Mapbox has no
   "continue for" words, so the voice says its own. When to speak is still navigation's (ADR-0040), not
   Mapbox's distances.
6. **The online map is Mapbox's raster tiles**, 512 px, through
   navigation's new `f250.nav.v1.OnlineMapService` (`GetStatus`,
   `GetTile`). Day and night are two styles (`MAPBOX_STYLE_DAY`,
   `MAPBOX_STYLE_NIGHT`). navigation keeps up to 300 tiles in memory for
   at most Mapbox's 12 h. Raster, not vector: vector_map_tiles would need
   Mapbox's styles rewritten for its renderer, and raster costs the Pi
   less.
7. **The Nav screen picks its map**: Mapbox's when the Wi-Fi service says
   the Pi is on a network (connman's `ready` or `online`: its own internet
   check may be off on the image, UNVERIFIED) and navigation says Mapbox is
   configured, the offline map otherwise. A hotspot without signal is
   caught by the tile failures below. Three tile failures within 30 s switch it to the offline
   map for 60 s (examples). The screen says which ("Mapbox" with Mapbox's
   attribution, © Mapbox © OpenStreetMap; or the offline map's). Without a
   map stick, the online map still works.
8. **Wi-Fi belongs to a new service, `services/network`**
   (`f250-network.service`, user f250), which talks to connman on the system
   bus and serves `f250.network.v1.WifiService`: Wi-Fi on or off, a scan,
   the networks seen (name, strength, secured, saved, connected), connect
   with a passphrase, disconnect, forget, and whether the Pi is online.
   Passphrases go to connman through the service's agent and are kept by
   connman, never by the service or the dashboard. A D-Bus policy lets user
   f250 talk to `net.connman`. `--simulate` gives made-up networks for the
   Mac and the browser.
9. **Settings › Wi-Fi** (ADR-0029): the networks with their strength,
   connect (the passphrase typed on the on-screen keyboard), disconnect,
   forget, scan and on/off, and the state.
10. **navigation's sandbox opens to the internet** (`IPAddressDeny` goes;
    `RestrictAddressFamilies` already allowed IP). The dashboard's stays
    closed. navigation never reaches the vehicle bus, so this doesn't touch
    ADR-0007.
11. **Search asks Mapbox first** (Geocoding v6 `forward`, the truck's
    position as `proximity`, `country=us` by default:
    `MAPBOX_SEARCH_COUNTRY`), with the same 60 s rest after a failure as
    routing, then the offline index (ADR-0038) as before. Geocoding, not the
    Search Box API: its free tier and per-request billing are stated, the
    Search Box's `/forward` isn't on the pricing page. So online search finds
    addresses, streets, towns and ZIP codes, **not businesses**; the offline
    index finds them only when Mapbox doesn't answer. The answer says who gave it
    (`SearchResponse.provider`), keeps Mapbox's order, and the footer says
    "Search: Mapbox, online". Mapbox's 3 s limit leaves the offline index
    time inside the dashboard's 5 s. Nothing is cached. Each pause in typing
    (150 ms) is one request.

## Consequences

- While online, the truck's position, destinations and what is typed in
  Search go to Mapbox.
- Saving a place found by Mapbox's search, or routing to one (Recent),
  keeps its name and position on the Pi, which Mapbox's temporary results
  say not to do. The owner was told and decided to keep it as is
  (2026-11-23), like the licence above.
  Without a token, nothing does.
- Routes over the hotspot use its data: a route is one request; each map
  tile is one request, and panning makes more. Both count against Mapbox's
  free tiers.
- A route started online keeps its Mapbox line when the network goes; a
  reroute then comes from Valhalla. Traffic isn't refreshed along a route
  (a later change, if wanted).
- Until checked on the Pi: `ImportCredential=` with systemd 259 (and no
  file: the unit must still start), connman's
  D-Bus API on the image, the D-Bus policy, and curl in the image.
