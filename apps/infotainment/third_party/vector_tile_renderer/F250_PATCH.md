# vector_tile_renderer 6.1.0, patched for the F-250 dashboard

Upstream: <https://pub.dev/packages/vector_tile_renderer> 6.1.0 (BSD 3-clause,
`LICENSE`), copied from pub's cache on 2026-11-13. Only `lib/`, the licence,
README and changelog are kept; `pubspec.yaml` drops the dev dependencies. The
app uses this copy through `dependency_overrides` in `apps/infotainment/pubspec.yaml`.

## The patch

`lib/src/features/symbol_line_renderer.dart`: line labels (road names) were
kept right side up from their angle **on the tile**. The map is turned for
heading up (ADR-0032, amended 2026-11-12), and vector_map_tiles draws the layer
turned by the map's rotation, which it passes in as `Context.rotation`. So a
north-south road's name read upside down whenever east was up (seen on the
bench Pi, bench-log 2026-11-13). Now the flip uses the angle **on the screen**
(the tile angle minus the map's rotation), for drawing and for the label's
collision box: `rightSideUpAngle(radians, mapRotation)`. With the map not
turned (rotation 0) it does exactly what upstream did.

Tested by `test/unit/line_label_angle_test.dart` (every heading in 5°
steps, every road angle in 3° steps, the ±93° boundary at rotation 0) and the
dashboard's map tests.

The patch only matters in vector_map_tiles' **vector** layer mode: its
default raster mode draws tiles with rotation 0 and turns the pictures, so the
renderer is never told the rotation. The dashboard uses vector mode for this
reason (`navigation_screen.dart`; ADR-0032, amended 2026-11-13).

## Updating

Copy the new version's `lib/` over this one, apply the patch again (search
for "F-250 patch"), and run `make ui-test`. Drop this copy once upstream
keeps line labels upright on a rotated map.
