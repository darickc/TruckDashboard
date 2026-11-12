import 'dart:convert';
import 'dart:ui' show ErrorCallback;

import 'package:executor_lib/executor_lib.dart' show CancellationException;
import 'package:flutter/services.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import 'pmtiles.dart';

/// The vector map's source name in the bundled styles (ADR-0032).
const vectorSource = 'protomaps';

/// An uncaught-error handler for `PlatformDispatcher.instance.onError` that
/// treats a dropped map tile as handled and passes everything else to
/// [previous] (or leaves it unhandled, so the engine logs it as before).
///
/// vector_map_tiles 9.0.0-beta.13 cancels a tile that is no longer needed
/// (while zooming or dragging) with executor_lib's CancellationException. In
/// two places (`CachesTileProvider._retrieve` and `_createTiles`) it starts
/// the work, checks for cancellation and leaves before awaiting it, so that
/// work's own cancellation is never caught: "Unhandled Exception: Cancelled"
/// in the log, a few times a minute on the Pi (bench-log 2026-11-11).
/// Nothing is wrong when it happens; the tile simply isn't drawn.
ErrorCallback ignoreDroppedTiles(ErrorCallback? previous) =>
    (error, stack) => error is CancellationException || (previous?.call(error, stack) ?? false);

/// Vector tiles (MVT) for vector_map_tiles from the dashboard's own PMTiles
/// reader. A tile the tileset doesn't have (outside the region) is reported
/// as missing, not retried: the layer leaves that square empty.
class PmTilesVectorProvider extends VectorTileProvider {
  PmTilesVectorProvider(this.reader);
  final PmTilesReader reader;

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    final bytes = await reader.tile(tile.z, tile.x, tile.y);
    if (bytes == null) {
      throw ProviderException(
        message: 'no tile ${tile.z}/${tile.x}/${tile.y} in the offline map',
        retryable: Retryable.none,
        statusCode: 404,
      );
    }
    return bytes;
  }

  @override
  int get maximumZoom => reader.header.maxZoom;

  @override
  int get minimumZoom => reader.header.minZoom;

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;
}

/// One look for the vector map: a style and its icons.
class VectorMapStyle {
  const VectorMapStyle(this.theme, this.sprites);
  final vtr.Theme theme;
  final SpriteStyle sprites;
}

/// The bundled day and night styles (`assets/map/`, made by
/// `tools/maps/map-assets.py` from @protomaps/basemaps). Read once.
class VectorMapStyles {
  const VectorMapStyles({required this.day, required this.night});
  final VectorMapStyle day, night;

  VectorMapStyle forNight(bool night) => night ? this.night : day;

  /// Reads both styles from [bundle]. [warnings] collects what the renderer
  /// can't use (the style test expects none of its "Unsupported" kind).
  static Future<VectorMapStyles> load(AssetBundle bundle, {List<String>? warnings}) async {
    final logger = _CollectingLogger(warnings);
    Future<VectorMapStyle> one(String flavor) async {
      final json = jsonDecode(await bundle.loadString('assets/map/styles/$flavor.json'));
      final theme = vtr.ThemeReader(logger: logger).read(json as Map<String, dynamic>);
      final index = vtr.SpriteIndexReader(logger: logger).read(
        jsonDecode(await bundle.loadString('assets/map/sprites/$flavor@2x.json'))
            as Map<String, dynamic>,
      );
      final atlas = await bundle.load('assets/map/sprites/$flavor@2x.png');
      return VectorMapStyle(
        theme,
        SpriteStyle(
          atlasProvider: () async => atlas.buffer.asUint8List(atlas.offsetInBytes, atlas.lengthInBytes),
          index: index,
        ),
      );
    }

    return VectorMapStyles(day: await one('light'), night: await one('dark'));
  }
}

class _CollectingLogger implements vtr.Logger {
  _CollectingLogger(this.warnings);
  final List<String>? warnings;

  @override
  void log(vtr.MessageFunction message) {}

  @override
  void warn(vtr.MessageFunction message) => warnings?.add(message());
}
