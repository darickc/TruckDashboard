import 'dart:ui';

import 'constants.dart';
import 'context.dart';
import 'features/feature_renderer.dart';
import 'features/label_space.dart';
import 'logger.dart';
import 'optimizations.dart';
import 'profiling.dart';
import 'symbols/text_painter.dart';
import 'themes/theme.dart';
import 'tile_source.dart';

class Renderer {
  final Theme theme;
  final Logger logger;
  final FeatureDispatcher featureRenderer;
  final TextPainterProvider painterProvider;
  Renderer({
    required this.theme,
    this.painterProvider = const DefaultTextPainterProvider(),
    Logger? logger,
  }) : logger = logger ?? const Logger.noop(),
       featureRenderer = FeatureDispatcher(logger ?? const Logger.noop());

  /// renders the given tile to the canvas
  ///
  /// [zoomScaleFactor] the 1-dimensional scale at which the tile is being
  ///        rendered. If the tile is being rendered at twice it's normal size
  ///        along the x-axis, the zoomScaleFactor would be 2. 1.0 indicates that
  ///        no scaling is being applied.
  /// [zoom] the current zoom level, which is used to filter theme layers
  ///        via `minzoom` and `maxzoom`. Value must be >= 0 and <= 24
  /// [tile] the tile to render
  /// [clip] the optional clip to constrain tile rendering, used to limit drawing
  ///        so that a portion of a tile can be rendered to a canvas
  void render(
    Canvas canvas,
    TileSource tile, {
    Rect? clip,
    required double zoomScaleFactor,
    required double zoom,
    required double rotation,
  }) {
    profileSync('Render', () {
      final tileSpace = Rect.fromLTWH(
        0,
        0,
        tileSize.toDouble(),
        tileSize.toDouble(),
      );
      canvas.save();
      canvas.clipRect(tileSpace);
      final tileClip = clip ?? tileSpace;
      final optimizations = Optimizations(
        skipInBoundsChecks:
            clip == null ||
            (tileClip.width - tileSpace.width).abs() < (tileSpace.width / 2),
      );
      final context = Context(
        logger: logger,
        canvas: canvas,
        featureRenderer: featureRenderer,
        tileSource: tile,
        zoomScaleFactor: zoomScaleFactor,
        zoom: zoom,
        rotation: rotation,
        tileSpace: tileSpace,
        tileClip: tileClip,
        optimizations: optimizations,
        textPainterProvider: painterProvider,
      );
      final effectiveTheme = theme.atZoom(zoom);
      for (final themeLayer in effectiveTheme.layers) {
        logger.log(() => 'rendering theme layer ${themeLayer.id}');
        themeLayer.render(context);
      }
      canvas.restore();
    });
  }

  /// F-250 patch: draws the symbol layers (labels, shields, icons) of
  /// several tiles at once, with one [labels] space, so a label near a
  /// tile's edge can reach into the next tile and labels of neighbouring
  /// tiles don't overlap. [render] keeps each label inside its own tile and
  /// drops the rest.
  ///
  /// Layers are placed from the top of the style down, as Mapbox GL places
  /// them, so a town's name wins over a road's. Within a layer, [tiles] go
  /// in the order given (put the most important first). Nothing is clipped.
  void renderSymbols(
    Canvas canvas,
    List<SymbolTile> tiles, {
    required SharedLabelSpace labels,
    required double zoom,
    required double rotation,
  }) {
    profileSync('RenderSymbols', () {
      final tileSpace = Rect.fromLTWH(
        0,
        0,
        tileSize.toDouble(),
        tileSize.toDouble(),
      );
      final contexts = [
        for (final tile in tiles)
          Context(
            logger: logger,
            canvas: canvas,
            featureRenderer: featureRenderer,
            tileSource: tile.source,
            zoomScaleFactor: tile.scale,
            zoom: zoom,
            rotation: rotation,
            tileSpace: tileSpace,
            tileClip: tile.clip,
            optimizations: Optimizations(
              skipInBoundsChecks:
                  (tile.clip.width - tileSpace.width).abs() <
                  (tileSpace.width / 2),
            ),
            textPainterProvider: painterProvider,
            labelSpace: TileLabelSpace(
              labels,
              own: tile.clip,
              origin: tile.origin,
              scale: tile.scale,
            ),
          ),
      ];
      final layers = theme
          .atZoom(zoom)
          .layers
          .where((layer) => layer.type == ThemeLayerType.symbol)
          .toList()
          .reversed;
      for (final themeLayer in layers) {
        for (var i = 0; i < tiles.length; ++i) {
          final tile = tiles[i];
          canvas.save();
          canvas.translate(tile.origin.dx, tile.origin.dy);
          canvas.scale(tile.scale);
          themeLayer.render(contexts[i]);
          canvas.restore();
        }
      }
    });
  }
}

/// F-250 patch: one tile for [Renderer.renderSymbols].
class SymbolTile {
  SymbolTile({
    required this.source,
    required this.origin,
    required this.scale,
    required this.clip,
  });

  final TileSource source;

  /// Where the tile's top-left corner (its pixel 0,0) is on the canvas.
  final Offset origin;

  /// Canvas pixels per tile pixel (a tile is 256 pixels across).
  final double scale;

  /// The part of the tile that is this tile, in the tile's pixels: all of
  /// it, or the quarter (and so on) when a lower zoom's tile is stretched.
  final Rect clip;
}
