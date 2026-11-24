// F-250 patch: the whole layer's labels in one painter (F250_PATCH.md).
//
// Upstream paints each tile's labels in that tile's own painter, clipped to
// the tile, and the renderer drops every label that doesn't fit inside its
// tile: names and shields near a tile's edge were missing or cut in half.
// Here every visible tile's symbol layers are placed together
// (Renderer.renderSymbols, one SharedLabelSpace) over the tiles, unclipped.
//
// Placing labels costs more than moving a picture, so it is done at most
// every [_interval]. In between, the last placement is moved and scaled with
// the map (the stack's coordinates are the map's pixels less its pixel
// origin), as upstream's delayed tile labels were.

import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

import 'grid_tile_positioner.dart';
import 'tile_model.dart';

const _interval = Duration(milliseconds: 250);

/// A tile with data, where the layer draws it.
class LabelTile {
  LabelTile(this.model, this.rect, this.zoomScale);

  final VectorTileModel model;

  /// The tile's place in the layer's stack (GridTilePositioner.tileRect).
  final Rect rect;
  final double zoomScale;

  SymbolTile? toSymbolTile() {
    final tileset = model.tileset;
    final translation = model.translation;
    if (tileset == null || translation == null) {
      return null;
    }
    final sizer = GridTileSizer(translation, zoomScale, rect.size);
    final scale = sizer.effectiveScale;
    return SymbolTile(
        source: TileSource(
            tileset: tileset,
            spriteAtlas: model.spriteImage,
            spriteIndex: model.sprites?.index),
        origin: rect.topLeft + sizer.translationDelta,
        scale: scale,
        clip: sizer.tileClip(rect.size, scale));
  }
}

class LabelLayer extends StatefulWidget {
  const LabelLayer(
      {super.key,
      required this.theme,
      required this.tiles,
      required this.camera,
      required this.zoom});

  /// The style's symbol layers.
  final Theme theme;
  final List<LabelTile> tiles;
  final MapCamera camera;

  /// The zoom the theme's layers are chosen for (the tiles' detail zoom).
  final double zoom;

  @override
  State<LabelLayer> createState() => _LabelLayerState();
}

class _LabelLayerState extends State<LabelLayer> {
  final _painters = LabelTextPainters();
  _LabelPainter? _painter;
  final _sincePlaced = Stopwatch();
  Timer? _timer;
  var _textsMade = false;

  @override
  void dispose() {
    _timer?.cancel();
    _painters.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = LabelView(widget.camera);
    final signature = _signature(widget.tiles);
    final placed = _painter;
    final stale = placed == null ||
        placed.signature != signature ||
        placed.view != view ||
        placed.theme != widget.theme ||
        _textsMade;
    if (stale) {
      final wait = _interval - _sincePlaced.elapsed;
      if (placed == null || wait <= Duration.zero) {
        _place(view, signature);
      } else {
        _timer ??= Timer(wait, () {
          _timer = null;
          if (mounted) {
            setState(() {});
          }
        });
      }
    }
    final painter = _painter!;
    return IgnorePointer(
        child: Transform(
            transform: painter.view.to(view),
            child: RepaintBoundary(child: CustomPaint(painter: painter))));
  }

  void _place(LabelView view, int signature) {
    final centre = view.size.center(Offset.zero);
    final tiles = widget.tiles.toList()
      ..sort((a, b) => (a.rect.center - centre)
          .distanceSquared
          .compareTo((b.rect.center - centre).distanceSquared));
    _painter = _LabelPainter(
        theme: widget.theme,
        tiles: tiles.map((t) => t.toSymbolTile()).whereType<SymbolTile>().toList(),
        view: view,
        zoom: widget.zoom,
        signature: signature,
        painters: _painters,
        onMissingTexts: _makeTexts);
    _sincePlaced
      ..reset()
      ..start();
    _textsMade = false;
  }

  void _makeTexts() {
    Timer.run(() async {
      if (await _painters.createMissing() && mounted) {
        setState(() => _textsMade = true);
      }
    });
  }
}

int _signature(List<LabelTile> tiles) => Object.hashAll(tiles.map((t) =>
    Object.hash(t.model.tile, identityHashCode(t.model.tileset),
        t.model.translation?.translated, t.model.spriteImage)));

/// The map as the layer's stack shows it.
class LabelView {
  LabelView(MapCamera camera)
      : zoom = camera.zoom,
        rotation = camera.rotationRad,
        size = camera.size,
        visible = camera.nonRotatedSize,
        pixelOrigin = _rounded(
            camera.getNewPixelOrigin(camera.center, camera.zoom));

  LabelView.of(
      {required this.zoom,
      required this.rotation,
      required this.size,
      required this.visible,
      required this.pixelOrigin});

  final double zoom;
  final double rotation;

  /// The stack's size: the box around the turned screen.
  final Size size;

  /// The screen's size.
  final Size visible;

  /// As GridTilePositioner uses it: a point's place in the stack is its
  /// pixel at [zoom] less this.
  final Offset pixelOrigin;

  static Offset _rounded(Offset o) =>
      Offset(o.dx.roundToDouble(), o.dy.roundToDouble());

  /// Whether [point] in the stack is on the screen. The stack is turned by
  /// [rotation] about its centre (MobileLayerTransformer).
  bool isVisible(Offset point) {
    final d = point - size.center(Offset.zero);
    final c = cos(rotation);
    final s = sin(rotation);
    final x = d.dx * c - d.dy * s;
    final y = d.dx * s + d.dy * c;
    return x.abs() <= visible.width / 2 && y.abs() <= visible.height / 2;
  }

  /// Moves what was drawn for this view to where it is in [now].
  Matrix4 to(LabelView now) {
    if (now == this) {
      return Matrix4.identity();
    }
    final s = pow(2, now.zoom - zoom).toDouble();
    return Matrix4.translationValues(-now.pixelOrigin.dx, -now.pixelOrigin.dy, 0)
      ..multiply(Matrix4.diagonal3Values(s, s, 1))
      ..multiply(Matrix4.translationValues(pixelOrigin.dx, pixelOrigin.dy, 0));
  }

  @override
  bool operator ==(Object other) =>
      other is LabelView &&
      other.zoom == zoom &&
      other.rotation == rotation &&
      other.size == size &&
      other.visible == visible &&
      other.pixelOrigin == pixelOrigin;

  @override
  int get hashCode => Object.hash(zoom, rotation, size, visible, pixelOrigin);
}

class _LabelPainter extends CustomPainter {
  _LabelPainter(
      {required this.theme,
      required this.tiles,
      required this.view,
      required this.zoom,
      required this.signature,
      required this.painters,
      required this.onMissingTexts});

  final Theme theme;
  final List<SymbolTile> tiles;
  final LabelView view;
  final double zoom;
  final int signature;
  final LabelTextPainters painters;
  final VoidCallback onMissingTexts;

  @override
  void paint(Canvas canvas, Size size) {
    painters.startPaint();
    Renderer(theme: theme, painterProvider: painters).renderSymbols(
        canvas, tiles,
        labels: SharedLabelSpace(isVisible: view.isVisible),
        zoom: zoom,
        rotation: view.rotation);
    painters.endPaint();
    if (painters.hasMissing) {
      onMissingTexts();
    }
  }

  @override
  bool shouldRepaint(covariant _LabelPainter oldDelegate) =>
      !identical(oldDelegate, this);
}

/// Laid-out label texts for the layer. A text not laid out yet isn't drawn
/// that time; [createMissing] lays them out a few milliseconds at a time
/// (as upstream does for each tile) and the labels are placed again.
class LabelTextPainters extends TextPainterProvider {
  LabelTextPainters({this.keep = 600});

  /// How many texts to keep laid out; past that, those not drawn last time
  /// are let go.
  final int keep;
  final _painters = <StyledSymbol, TextPainter>{};
  final _missing = <StyledSymbol>{};
  final _used = <StyledSymbol>{};
  var _creating = false;
  var _disposed = false;

  int get length => _painters.length;
  bool get hasMissing => _missing.isNotEmpty;

  @override
  TextPainter? provide(StyledSymbol symbol) {
    _used.add(symbol);
    final painter = _painters[symbol];
    if (painter == null) {
      _missing.add(symbol);
    }
    return painter;
  }

  void startPaint() => _used.clear();

  void endPaint() {
    if (_painters.length > keep) {
      final unused =
          _painters.keys.where((s) => !_used.contains(s)).toList();
      for (final s in unused) {
        _painters.remove(s)?.dispose();
      }
    }
  }

  /// True when it laid out any.
  Future<bool> createMissing() async {
    if (_creating) {
      return false;
    }
    _creating = true;
    var made = false;
    try {
      while (_missing.isNotEmpty && !_disposed) {
        final watch = Stopwatch()..start();
        while (_missing.isNotEmpty && watch.elapsedMicroseconds < 4000) {
          final symbol = _missing.first;
          _missing.remove(symbol);
          _painters[symbol] ??=
              const DefaultTextPainterProvider().provide(symbol);
          made = true;
        }
        await Future.delayed(const Duration(milliseconds: 2));
      }
    } finally {
      _creating = false;
    }
    return made && !_disposed;
  }

  void dispose() {
    _disposed = true;
    for (final p in _painters.values) {
      p.dispose();
    }
    _painters.clear();
    _missing.clear();
  }
}
