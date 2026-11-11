import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';

import 'map_file.dart';
import 'pmtiles.dart';
import 'vector_map.dart';

/// The offline map's state: being opened, ready, or why there is none.
sealed class MapFileState {
  const MapFileState();
}

class MapLoading extends MapFileState {
  const MapLoading();
}

class MapReady extends MapFileState {
  const MapReady(this.reader, {this.vector});
  final PmTilesReader reader;

  /// Set for a vector tileset (ADR-0032): what the screen draws it with.
  final VectorMap? vector;
}

/// A vector tileset's tile provider and the bundled styles to draw it with.
class VectorMap {
  VectorMap(PmTilesReader reader, this.styles) : provider = PmTilesVectorProvider(reader);
  final PmTilesVectorProvider provider;
  final VectorMapStyles styles;
}

class MapUnavailable extends MapFileState {
  const MapUnavailable(this.why);
  final String why;
}

/// The tileset at [path], raster (ADR-0030) or vector (ADR-0032): opened
/// once, read-only. The map update workflow (6.5.3) replaces the file and
/// restarts the dashboard.
class OfflineMap {
  OfflineMap(
    this.path, {
    Future<PmTilesReader> Function(String path)? open,
    Future<VectorMapStyles> Function()? loadStyles,
  }) : _open = open ?? openOfflineMap,
       _loadStyles = loadStyles ?? (() => VectorMapStyles.load(rootBundle)),
       _state = ValueNotifier(
        path.isEmpty
            ? const MapUnavailable('no offline map configured (MAP_FILE)')
            : const MapLoading(),
      );

  /// None configured: the screen says so.
  OfflineMap.none() : this('');

  final String path;
  final Future<PmTilesReader> Function(String path) _open;
  final Future<VectorMapStyles> Function() _loadStyles;
  final ValueNotifier<MapFileState> _state;

  ValueListenable<MapFileState> get state => _state;

  Future<void> load() async {
    if (path.isEmpty) return;
    _state.value = const MapLoading();
    final PmTilesReader reader;
    try {
      reader = await _open(path);
    } on PmTilesException catch (e) {
      _state.value = MapUnavailable(e.message);
      return;
    } catch (e) {
      _state.value = MapUnavailable('$path: $e');
      return;
    }
    if (reader.header.tileType != TileType.mvt) {
      _state.value = MapReady(reader);
      return;
    }
    try {
      _state.value = MapReady(reader, vector: VectorMap(reader, await _loadStyles()));
    } catch (e) {
      _state.value = MapUnavailable('the vector map styles can\'t be read: $e');
    }
  }
}

/// flutter_map tiles from a PMTiles reader. A tile the tileset doesn't have
/// is drawn transparent: outside the region is normal, not an error.
class PmTilesTileProvider extends TileProvider {
  PmTilesTileProvider(this.reader);
  final PmTilesReader reader;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      PmTileImage(reader, coordinates.z, coordinates.x, coordinates.y);
}

@immutable
class PmTileImage extends ImageProvider<PmTileImage> {
  const PmTileImage(this.reader, this.z, this.x, this.y);

  final PmTilesReader reader;
  final int z, x, y;

  @override
  Future<PmTileImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(PmTileImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(_load(decode));

  Future<ImageInfo> _load(ImageDecoderCallback decode) async {
    final bytes = await reader.tile(z, x, y) ?? transparentPng;
    final codec = await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    final frame = await codec.getNextFrame();
    return ImageInfo(image: frame.image);
  }

  @override
  bool operator ==(Object other) =>
      other is PmTileImage &&
      identical(other.reader, reader) &&
      other.z == z &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(identityHashCode(reader), z, x, y);
}

/// A 1×1 transparent PNG (zlib-made, checked with Pillow: RGBA (0, 0, 0, 0)).
final transparentPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00,
  0x00, 0x05, 0x00, 0x01, 0x7A, 0x5E, 0xAB, 0x3F, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
  0xAE, 0x42, 0x60, 0x82,
]);
