import 'dart:math';
import 'dart:ui';

import 'package:flutter/painting.dart' show MatrixUtils, TextAlign, TextStyle;
import 'package:flutter_test/flutter_test.dart';
// The patched layer lives in vector_map_tiles' src (F250_PATCH.md).
// ignore: implementation_imports
import 'package:vector_map_tiles/src/grid/label_layer.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

/// Labels near a tile's edge (third_party/vector_map_tiles/F250_PATCH.md):
/// every visible tile's labels are placed together, so a label may reach
/// into the next tile, labels of neighbouring tiles don't overlap, and a
/// feature in two tiles' data (the tile buffer) is labelled once. `[SIM]`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const extent = 4096;

  // Two symbol layers: roads under towns, as in a style.
  final theme = ThemeReader().read({
    'version': 8,
    'sources': {
      's': {'type': 'vector'},
    },
    'layers': [
      for (final id in ['road', 'town'])
        {
          'id': id,
          'type': 'symbol',
          'source': 's',
          'source-layer': id,
          'layout': {
            'text-field': ['get', 'name'],
            'text-size': 14,
            'text-font': ['Noto Sans Regular'],
          },
          'paint': {'text-color': '#ffffff'},
        },
    ],
  });

  /// A tile with points: (layer, name, x, y) in tile units.
  TileSource tile(List<(String, String, double, double)> points) => TileSource(
    tileset: Tileset({
      's': Tile(
        layers: [
          for (final layer in ['road', 'town'])
            TileLayer(
              name: layer,
              extent: extent,
              features: [
                for (final (l, name, x, y) in points)
                  if (l == layer)
                    TileFeature(
                      type: TileFeatureType.point,
                      properties: {'name': name},
                      points: [Point(x, y)],
                      lines: null,
                      polygons: null,
                    ),
              ],
            ),
        ],
      ),
    }),
  );

  /// Tiles side by side at 1:1, the first at the canvas's origin.
  List<SymbolTile> row(List<TileSource> sources) => [
    for (var i = 0; i < sources.length; ++i)
      SymbolTile(
        source: sources[i],
        origin: Offset(256.0 * i, 0),
        scale: 1,
        clip: const Rect.fromLTWH(0, 0, 256, 256),
      ),
  ];

  SharedLabelSpace place(List<SymbolTile> tiles, {bool Function(Offset)? visible}) {
    final labels = SharedLabelSpace(isVisible: visible ?? (_) => true);
    final recorder = PictureRecorder();
    Renderer(theme: theme).renderSymbols(
      Canvas(recorder),
      tiles,
      labels: labels,
      zoom: 12,
      rotation: 0,
    );
    recorder.endRecording().dispose();
    return labels;
  }

  // 4000 of 4096 is 250 of the tile's 256 pixels: a label centred there
  // reaches past the edge, so upstream dropped it.
  const nearEdge = 4000.0;
  const middle = 2048.0;

  test('a name near the edge is drawn, reaching into the next tile', () {
    final labels = place(
      row([
        tile([('town', 'Lebanon', nearEdge, middle)]),
        tile([]),
      ]),
    );
    expect(labels.placed.keys, ['Lebanon']);
    expect(labels.placed['Lebanon']!.single.dx, closeTo(250, 0.5));
  });

  test('a feature in both tiles\' data is labelled once, by its own tile', () {
    // The next tile carries it in its buffer, left of its own edge.
    final labels = place(
      row([
        tile([('town', 'Lebanon', nearEdge, middle)]),
        tile([('town', 'Lebanon', nearEdge - extent, middle)]),
      ]),
    );
    expect(labels.count, 1);
    expect(labels.placed['Lebanon']!.single.dx, closeTo(250, 0.5));

    // The same from the other side: only the tile that owns it draws it.
    final other = place(
      row([
        tile([('town', 'Lebanon', nearEdge - extent, middle)]),
        tile([('town', 'Lebanon', nearEdge, middle)]),
      ]),
    );
    expect(other.count, 1);
    expect(other.placed['Lebanon']!.single.dx, closeTo(256 + 250, 0.5));
  });

  test('labels from neighbouring tiles don\'t overlap', () {
    final labels = place(
      row([
        tile([('town', 'Alpha', nearEdge, middle)]),
        tile([('town', 'Beta', 100, middle)]),
      ]),
    );
    expect(labels.count, 1);
    expect(labels.placed.keys, ['Alpha']);
  });

  test('tiles go in the order given: the first wins a collision', () {
    final tiles = row([
      tile([('town', 'Alpha', nearEdge, middle)]),
      tile([('town', 'Beta', 100, middle)]),
    ]);
    final labels = place(tiles.reversed.toList());
    expect(labels.placed.keys, ['Beta']);
  });

  test('the top layer is placed first: a town wins over a road', () {
    final labels = place(
      row([
        tile([
          ('road', 'Mill Road', middle, middle),
          ('town', 'Lebanon', middle, middle),
        ]),
      ]),
    );
    expect(labels.placed.keys, ['Lebanon']);
  });

  test('a name repeats only far from where it already is', () {
    final labels = place(
      row([
        for (var i = 0; i < 3; ++i) tile([('road', 'Main', middle, middle)]),
      ]),
    );
    // 256 apart is too close; 512 apart (past 400) is a second label.
    expect(labels.placed['Main']!.map((c) => c.dx.round()), [128, 640]);
  });

  test('a label whose centre is off the screen is not placed', () {
    final labels = place(
      row([
        tile([('town', 'Alpha', middle, middle)]),
        tile([('town', 'Beta', middle, middle)]),
      ]),
      visible: (c) => c.dx < 256,
    );
    expect(labels.placed.keys, ['Alpha']);
  });

  test('a stretched lower zoom tile labels only its own quarter', () {
    // The right half of a tile shown at twice its size: its left half is
    // another tile's.
    final source = tile([
      ('town', 'Left', 1000, middle),
      ('town', 'Right', 3000, middle),
    ]);
    final labels = place([
      SymbolTile(
        source: source,
        origin: const Offset(-256, 0),
        scale: 2,
        clip: const Rect.fromLTWH(128, 0, 128, 256),
      ),
    ]);
    expect(labels.placed.keys, ['Right']);
    expect(labels.placed['Right']!.single.dx, closeTo(-256 + 2 * 3000 / 16, 1));
  });

  group('icons', () {
    // A town's icon alone (top layer) and a road's name with a shield.
    final iconTheme = ThemeReader().read({
      'version': 8,
      'sources': {
        's': {'type': 'vector'},
      },
      'layers': [
        {
          'id': 'road',
          'type': 'symbol',
          'source': 's',
          'source-layer': 'road',
          'layout': {
            'text-field': ['get', 'name'],
            'text-size': 14,
            'text-font': ['Noto Sans Regular'],
            'icon-image': 'wide',
          },
          'paint': {'text-color': '#ffffff'},
        },
        {
          'id': 'town',
          'type': 'symbol',
          'source': 's',
          'source-layer': 'town',
          'layout': {'icon-image': 'big'},
          // The renderer drops a symbol layer without a paint.
          'paint': {'text-color': '#ffffff'},
        },
      ],
    });
    final sprites = SpriteIndexReader().read({
      'big': {'x': 0, 'y': 0, 'width': 100, 'height': 100, 'pixelRatio': 1},
      'wide': {'x': 0, 'y': 100, 'width': 200, 'height': 30, 'pixelRatio': 1},
    });
    late Image atlas;

    setUpAll(() async {
      final recorder = PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 200, 130),
        Paint()..color = const Color(0xffffffff),
      );
      atlas = await recorder.endRecording().toImage(200, 130);
    });
    tearDownAll(() => atlas.dispose());

    SharedLabelSpace placeWithIcons(List<(String, String, double, double)> points) {
      final labels = SharedLabelSpace(isVisible: (_) => true);
      final source = tile(points);
      final recorder = PictureRecorder();
      Renderer(theme: iconTheme).renderSymbols(
        Canvas(recorder),
        [
          SymbolTile(
            source: TileSource(
              tileset: source.tileset,
              spriteIndex: sprites,
              spriteAtlas: atlas,
            ),
            origin: Offset.zero,
            scale: 1,
            clip: const Rect.fromLTWH(0, 0, 256, 256),
          ),
        ],
        labels: labels,
        zoom: 12,
        rotation: 0,
      );
      recorder.endRecording().dispose();
      return labels;
    }

    // 16 tile units to a pixel. The town's icon covers 78 to 178 down.
    test('an icon takes its space, and a label clear of it is drawn', () {
      final labels = placeWithIcons([
        ('town', '', middle, middle),
        ('road', 'Main', middle, middle + 16 * 100.0),
      ]);
      // The icon, then the name and its shield.
      expect(labels.count, 3);
      expect(labels.placed.keys, ['Main']);
    });

    test('a shield that would cover an icon: the label isn\'t drawn', () {
      // The name (180 to 196 down) is clear of the town's icon, its 30 high
      // shield (173 to 203) isn't: the name is taken back too.
      final labels = placeWithIcons([
        ('town', '', middle, middle),
        ('road', 'Main', middle, middle + 16 * 60.0),
      ]);
      expect(labels.count, 1);
      expect(labels.placed, isEmpty);
    });
  });

  group('LabelView', () {
    LabelView view({
      double zoom = 10,
      double rotation = 0,
      Size size = const Size(800, 480),
      Size visible = const Size(800, 480),
      Offset pixelOrigin = Offset.zero,
    }) => LabelView.of(
      zoom: zoom,
      rotation: rotation,
      size: size,
      visible: visible,
      pixelOrigin: pixelOrigin,
    );

    test('not turned: the screen is the stack', () {
      final v = view();
      expect(v.isVisible(const Offset(1, 1)), isTrue);
      expect(v.isVisible(const Offset(799, 479)), isTrue);
      expect(v.isVisible(const Offset(801, 240)), isFalse);
      expect(v.isVisible(const Offset(400, -1)), isFalse);
    });

    test('turned a quarter: the screen is across the taller stack', () {
      // MobileLayerTransformer turns the 480 x 800 stack clockwise about
      // its centre to fill the 800 x 480 screen.
      final v = view(rotation: pi / 2, size: const Size(480, 800));
      const centre = Offset(240, 400);
      // Along the stack's height is across the screen: 800 wide.
      expect(v.isVisible(centre + const Offset(0, 390)), isTrue);
      expect(v.isVisible(centre + const Offset(0, -390)), isTrue);
      // Along the stack's width is up and down the screen: 480 high.
      expect(v.isVisible(centre + const Offset(230, 0)), isTrue);
      expect(v.isVisible(centre + const Offset(250, 0)), isFalse);
    });

    test('what was placed moves and scales with the map', () {
      final then = view(pixelOrigin: const Offset(1000, 2000));
      final now = view(zoom: 11, pixelOrigin: const Offset(2050, 4010));
      // A point whose pixel at zoom 10 is (1100, 2100) was at (100, 100);
      // at zoom 11 its pixel is (2200, 4200), now at (150, 190).
      final m = then.to(now);
      final moved = MatrixUtils.transformPoint(m, const Offset(100, 100));
      expect(moved.dx, closeTo(150, 1e-9));
      expect(moved.dy, closeTo(190, 1e-9));
      expect(then.to(then).isIdentity(), isTrue);
    });
  });

  test('texts are laid out after the first paint, then kept', () async {
    final painters = LabelTextPainters(keep: 1);
    final a = StyledSymbol(
      style: SymbolStyle(
        textStyle: const TextStyle(fontSize: 14),
        textAlign: TextAlign.center,
      ),
      text: 'A',
    );
    final b = StyledSymbol(style: a.style, text: 'B');
    painters.startPaint();
    expect(painters.provide(a), isNull);
    painters.endPaint();
    expect(painters.hasMissing, isTrue);
    expect(await painters.createMissing(), isTrue);
    expect(painters.hasMissing, isFalse);
    painters.startPaint();
    expect(painters.provide(a), isNotNull);
    painters.endPaint();

    // Past [keep], texts not drawn last time are let go.
    painters.startPaint();
    painters.provide(b);
    painters.endPaint();
    await painters.createMissing();
    painters.startPaint();
    painters.provide(b);
    painters.endPaint();
    expect(painters.length, 1);
    painters.dispose();
  });
}
