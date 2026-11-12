import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';

import 'map_file.dart';
import 'map_update.dart';
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
  VectorMap(PmTilesReader reader, this.styles)
    : provider = PmTilesVectorProvider(reader),
      generation = ++_opened;
  final PmTilesVectorProvider provider;
  final VectorMapStyles styles;

  /// Which map this is since the dashboard started: a replaced map gets a
  /// new layer and a new tile cache.
  final int generation;
  static int _opened = 0;
}

class MapUnavailable extends MapFileState {
  const MapUnavailable(this.why);
  final String why;
}

/// The tileset at [path], raster (ADR-0030) or vector (ADR-0032), read-only.
/// A map stick (ADR-0033) replaces the file; [watch] follows the import's
/// status file at [statusPath] and opens the new map when it is in place.
class OfflineMap {
  OfflineMap(
    this.path, {
    this.statusPath = '',
    Future<PmTilesReader> Function(String path)? open,
    Future<VectorMapStyles> Function()? loadStyles,
    Future<String?> Function(String path)? readStatus,
  }) : _open = open ?? openOfflineMap,
       _loadStyles = loadStyles ?? (() => VectorMapStyles.load(rootBundle)),
       _readStatus = readStatus ?? readMapStatus,
       _state = ValueNotifier(
        path.isEmpty
            ? const MapUnavailable('no offline map configured (MAP_FILE)')
            : const MapLoading(),
      );

  /// None configured: the screen says so.
  OfflineMap.none() : this('');

  final String path;

  /// The map import's status file (`/run/f250-maps/status.json` on the Pi);
  /// empty: none.
  final String statusPath;
  final Future<PmTilesReader> Function(String path) _open;
  final Future<VectorMapStyles> Function() _loadStyles;
  final Future<String?> Function(String path) _readStatus;
  final ValueNotifier<MapFileState> _state;
  final _update = ValueNotifier<MapUpdateStatus?>(null);
  Timer? _watch;
  String? _installedId;
  bool _checkedOnce = false;
  VectorMapStyles? _styles;

  ValueListenable<MapFileState> get state => _state;

  /// The latest map import, or null if none since the dashboard started.
  ValueListenable<MapUpdateStatus?> get update => _update;

  /// Checks the import status every [every]. Without [statusPath], nothing.
  void watch({Duration every = const Duration(seconds: 1)}) {
    if (statusPath.isEmpty || _watch != null) return;
    _watch = Timer.periodic(every, (_) => checkUpdate());
    unawaited(checkUpdate());
  }

  void dispose() {
    _watch?.cancel();
    _watch = null;
  }

  bool _checking = false;

  /// Reads the import status once. A new finished import that replaced the
  /// map reopens it (one that brought only routing data doesn't); one that
  /// finished before the dashboard started is already the map it opened.
  Future<void> checkUpdate() async {
    if (statusPath.isEmpty || _checking) return;
    _checking = true;
    try {
      final text = await _readStatus(statusPath);
      final status = text == null ? null : MapUpdateStatus.parse(text);
      final first = !_checkedOnce;
      _checkedOnce = true;
      if (status == null) return;
      if (status.mapChanged && status.id != _installedId) {
        _installedId = status.id;
        if (!first) await load();
      }
      // An import that finished before the dashboard started isn't news.
      if (first && !status.inProgress) return;
      _update.value = status;
    } finally {
      _checking = false;
    }
  }

  Future<void> load() async {
    if (path.isEmpty) return;
    final old = _state.value;
    _state.value = const MapLoading();
    if (old is MapReady) await old.reader.close();
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
      _state.value = MapReady(reader, vector: VectorMap(reader, _styles ??= await _loadStyles()));
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
