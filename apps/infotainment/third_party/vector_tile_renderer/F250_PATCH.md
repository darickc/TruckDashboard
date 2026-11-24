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

## The second patch: Mapbox's `placeholder` isn't `content`

`lib/src/themes/sprite_reader.dart`: a sprite's `content` box (the style
spec's, for `icon-text-fit`) was read from `content`, else from
`placeholder`, which Mapbox's sprites carry on every shield (237 in
`navigation-night-v1`'s, none with `content`). With a content box the icon
renderer stretches the icon so the label fits inside it with a margin, so a
US-route shield whose placeholder is 12 pixels tall was drawn several times
its size, past the roads it labels (ADR-0052, the vector online map). Now
only `content` is read; with none the label is centred on the icon, as
Mapbox GL draws a shield without `icon-text-fit`. The offline map's sprites
have neither field, so it is unchanged.

Tested by `test/unit/sprite_content_test.dart`.

## The third patch: labels shared across tiles

`lib/src/features/label_space.dart`, `lib/src/context.dart`,
`lib/src/renderer.dart`: `Renderer.renderSymbols` draws the symbol layers of
several tiles at once, each moved and scaled onto the canvas, with one
`SharedLabelSpace`. Each tile sees it through a `TileLabelSpace`, which puts
the tile's label boxes on the canvas and lets the tile place only labels whose
centre is in its own area. Labels may then reach past a tile's edge, which
`render` (unchanged) doesn't allow. Layers are placed from the top of the
style down, as Mapbox GL does.

Icons take space too (`symbol_icon.dart`, `icon_renderer.dart`, the point
and line symbol renderers): upstream checked only a label's text, so with
the top layer placed first a lower layer's icon could be drawn over a
shield. A label whose icon doesn't fit isn't drawn, and its text is taken
back (`LabelSpace.vacate`). The patched vector_map_tiles
(`third_party/vector_map_tiles/F250_PATCH.md`) uses it for the whole map's
labels.

Tested by `test/unit/edge_labels_test.dart`.

## Updating

Copy the new version's `lib/` over this one, apply the patches again (search
for "F-250 patch"), and run `make ui-test`. Drop this copy once upstream
keeps line labels upright on a rotated map.
