import 'dart:convert';
import 'dart:typed_data';

import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import 'online_map.dart';

/// The online map as vector tiles (ADR-0052 decision 6, amended 2026-11-24):
/// Mapbox's navigation style, its sprites and its vector tiles, all through
/// services/navigation, drawn by the same renderer as the offline map. Its
/// labels then stay upright when the map turns with the heading, which the
/// raster tiles couldn't do (bench-log 2026-11-23).
class OnlineVectorMap {
  const OnlineVectorMap({required this.theme, required this.sprites, required this.providers});

  final vtr.Theme theme;
  final SpriteStyle sprites;
  final TileProviders providers;

  /// Reads the style for day or night from [source], with the sprites for
  /// [pixelRatio] (see [spritePixelRatio]). Each tile's outcome
  /// goes to [onResult] (for `OnlineMapChooser.report`). [warnings] collects
  /// what the renderer couldn't read (none, for navigation-night-v1 and
  /// navigation-day-v1 when checked, 2026-11-24).
  static Future<OnlineVectorMap> load(
    OnlineMapSource source, {
    required bool night,
    required int pixelRatio,
    required void Function(bool ok, String why) onResult,
    List<String>? warnings,
  }) async {
    final data = await source.style(night: night, pixelRatio: pixelRatio);
    final json = jsonDecode(data.styleJson) as Map<String, dynamic>;
    useBundledFonts(json);
    final logger = _Collecting(warnings);
    final theme = vtr.ThemeReader(logger: logger).read(json);
    final index = vtr.SpriteIndexReader(logger: logger).read(
      jsonDecode(data.spriteJson) as Map<String, dynamic>,
    );
    final png = data.spritePng;
    return OnlineVectorMap(
      theme: theme,
      sprites: SpriteStyle(atlasProvider: () async => png, index: index),
      providers: TileProviders({
        for (final s in data.sources)
          s.id: OnlineVectorProvider(source, s, night: night, onResult: onResult),
      }),
    );
  }
}

/// Mapbox's sprites for a screen of [devicePixelRatio]: 1x up to 1.5, else
/// 2x. The bench Pi's panel is 1; its GPU can't hold the 2x sheet (4416
/// pixels wide), and the engine shrinks a sheet it can't hold, which put
/// every icon in the wrong place (bench-log 2026-11-24).
int spritePixelRatio(double devicePixelRatio) => devicePixelRatio <= 1.5 ? 1 : 2;

/// The bundled font for one of Mapbox's (DIN Pro, Arial Unicode MS): the
/// dashboard has no network to fetch Mapbox's glyphs, and the renderer uses
/// the app's fonts by family name. Weight and slant are kept.
String bundledFontFor(String mapboxFont) {
  final f = mapboxFont.toLowerCase();
  if (f.contains('italic')) return 'Noto Sans Italic';
  if (f.contains('bold') || f.contains('medium') || f.contains('heavy') || f.contains('black')) {
    return 'Noto Sans Medium';
  }
  return 'Noto Sans Regular';
}

/// Replaces every font name in [style]'s `text-font`s with a bundled one.
/// Font names have spaces; the expressions' operators ("step", "literal")
/// don't, so only names are touched.
void useBundledFonts(Map<String, dynamic> style) {
  Object? swap(Object? v) => switch (v) {
    String s when s.contains(' ') => bundledFontFor(s),
    List<dynamic> l => [for (final x in l) swap(x)],
    _ => v,
  };
  for (final layer in (style['layers'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
    final layout = layer['layout'];
    if (layout is Map<String, dynamic> && layout.containsKey('text-font')) {
      layout['text-font'] = swap(layout['text-font']);
    }
  }
}

/// One of the style's vector sources, fetched by navigation.
class OnlineVectorProvider extends VectorTileProvider {
  OnlineVectorProvider(this.source, this.zooms, {required this.night, required this.onResult});

  final OnlineMapSource source;
  final OnlineMapSourceZooms zooms;
  final bool night;
  final void Function(bool ok, String why) onResult;

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    try {
      final bytes = await source.vectorTile(zooms.id, tile.z, tile.x, tile.y, night: night);
      onResult(true, '');
      return bytes;
    } catch (e) {
      final why = e is StateError ? e.message : '$e';
      onResult(false, why);
      // 204: vector_map_tiles shows an empty tile and keeps nothing, so
      // the tile is asked for again when next needed; any other failure it
      // rethrows as an uncaught error. The chooser counts the failures and
      // goes offline (ADR-0052 decision 7).
      throw ProviderException(message: why, retryable: Retryable.none, statusCode: 204);
    }
  }

  @override
  int get maximumZoom => zooms.maxZoom;

  @override
  int get minimumZoom => zooms.minZoom;

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;
}

class _Collecting implements vtr.Logger {
  _Collecting(this.warnings);
  final List<String>? warnings;

  @override
  void log(vtr.MessageFunction message) {}

  @override
  void warn(vtr.MessageFunction message) => warnings?.add(message());
}
