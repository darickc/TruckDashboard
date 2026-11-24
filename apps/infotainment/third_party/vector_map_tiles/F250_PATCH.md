# vector_map_tiles 9.0.0-beta.13, patched for the F-250 dashboard

Upstream: <https://pub.dev/packages/vector_map_tiles> 9.0.0-beta.13 (BSD
3-clause, `LICENSE`), copied from pub's cache on 2026-11-24. Only `lib/`, the
licence, README and changelog are kept (the README's links to files not
copied point at the upstream repository); `pubspec.yaml` drops the dev
dependencies. The app uses this copy through `dependency_overrides` in
`apps/infotainment/pubspec.yaml`. It goes with the patched
`third_party/vector_tile_renderer` (its third patch, `renderSymbols`).

## The patch: labels placed across tiles

In vector layer mode upstream paints each tile's labels in that tile's own
painter, clipped to the tile, and the renderer keeps a label only if it fits
completely inside its tile. Names and route shields near a tile's edge were
missing, or cut in half where an icon reached past the edge (seen on the
Mapbox vector map on the Mac and the bench Pi, 2026-11-24; the offline map
has the same tiles and the same flaw).

Now:

- `grid/grid_layer.dart`: the tiles get no symbol theme, so they draw no
  labels. Over the tiles, one `LabelLayer` draws every visible tile's
  labels.
- `grid/label_layer.dart` (new): places all the tiles' symbol layers in one
  pass (`Renderer.renderSymbols`, one `SharedLabelSpace`), unclipped:
  - a label may reach into the next tile;
  - labels of neighbouring tiles don't overlap;
  - a feature in two tiles' data (the tile buffer) is labelled once, by the
    tile its label's centre is in;
  - a label is placed only if its centre is on the screen, and its icon
    must not overlap another label either;
  - the same name is placed again only 400 pixels or more from where it
    already is;
  - layers are placed from the top of the style down, as Mapbox GL does, so a
    town's name wins over a road's; tiles nearest the screen's centre go
    first.
  
  Placing labels is done at most every 250 ms. In between, the last placement
  is moved and scaled with the map (the stack's coordinates are the map's
  pixels less its pixel origin), and turns with it until it is placed again,
  as upstream's delayed tile labels did. Texts are laid out a few
  milliseconds at a time after the paint that first needs them, as upstream
  does per tile, and the labels are placed again.
- `grid/grid_tile_positioner.dart`: `tileRect`, where a tile is put, for the
  label layer.

Tested by `test/unit/edge_labels_test.dart` (placement across tiles, the
buffer, collisions, order, repeats, the screen, a stretched lower zoom tile,
the view's transform and rotation, laying out texts) and the dashboard's map
tests. Seen on the Mac and the bench Pi (bench-log 2026-11-24).

## Updating

Copy the new version's `lib/` over this one, apply the patch again (search
for "F-250 patch"), and run `make ui-test`. Drop this copy once upstream
places labels across tiles.
