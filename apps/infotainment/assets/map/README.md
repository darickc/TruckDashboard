# Vector map assets

What the dashboard draws a vector (MVT) map with ([ADR-0032](../../../../docs/architecture/adr/0032-vector-map.md)).
Written by `tools/maps/map-assets.py` (`make map-assets`) from pinned inputs;
don't edit by hand.

| Files | Source | Licence |
|---|---|---|
| `styles/light.json`, `styles/dark.json` | [`@protomaps/basemaps`](https://github.com/protomaps/basemaps) 5.7.2, flavors `light` and `dark`, rewritten for vector_tile_renderer 6.1.0 (rules in ADR-0032) | BSD-3-Clause; the visual design is CC0 |
| `sprites/*@2x.json`, `sprites/*@2x.png` | [`protomaps/basemaps-assets`](https://github.com/protomaps/basemaps-assets) commit `028c18f713baecad011301ff7a69acc39bcc2ae7`, sprites v4 | see that repository (derived from MIT-licensed tangrams icons) |
| `fonts/NotoSans-Regular.ttf`, `-Medium.ttf`, `-Italic.ttf` | [`notofonts/notofonts.github.io`](https://github.com/notofonts/notofonts.github.io) commit `4cf78353cd1668040ba8efa13029cd910fcdf9e2`, unhinted TTF | SIL Open Font License 1.1, [`fonts/OFL.txt`](fonts/OFL.txt) |

The map data itself is OpenStreetMap (ODbL) and comes in the map file, whose
attribution the screen shows.
