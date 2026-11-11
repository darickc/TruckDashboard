# PMTiles fixtures

Written by the official `pmtiles` tool (go-pmtiles 1.31.2, `pmtiles convert`)
from MBTiles made by `tools/dev/test-pattern-map.py`. The dashboard's reader
(`lib/nav/pmtiles.dart`) is tested against them, so it isn't only checked
against its own reading of the spec.

| File | Made with | Contents |
|---|---|---|
| `id-z0-6.pmtiles` | `--style id --minzoom 0 --maxzoom 6 --world-below 7` | every tile of zooms 0–6; each tile's bytes are `[z, x, y]` (not images) |
| `solid-z0-3.pmtiles` | `--style solid --minzoom 0 --maxzoom 3 --world-below 4` | zooms 0–3, flat-colour 256 px PNGs; five colours, so the tool deduplicates them into runs |

`pmtiles convert` keeps directories this small in the root, so the reader's
leaf-directory path is tested with a file built in the test itself.
