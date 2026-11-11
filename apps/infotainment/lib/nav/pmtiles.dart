import 'dart:convert';
import 'dart:typed_data';

/// A reader for PMTiles version 3 (https://github.com/protomaps/PMTiles,
/// spec v3): one file holding a whole tileset, addressed by byte ranges.
/// Pure Dart: the bytes and the decompressor come from the caller
/// (pmtiles_file.dart on the Pi and the Mac), so the format is tested
/// without a file.
///
/// The dashboard shows raster tiles only (ADR-0030): Flutter's vector-tile
/// renderers need protobuf 3 and the app's gRPC needs 6.

/// The file isn't a tileset the dashboard can show; [message] says why, for
/// the screen.
class PmTilesException implements Exception {
  PmTilesException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum Compression { unknown, none, gzip, brotli, zstd }

enum TileType { unknown, mvt, png, jpeg, webp, avif }

/// Reads `length` bytes at `offset`.
typedef ReadRange = Future<Uint8List> Function(int offset, int length);

/// Undoes [Compression] (gzip only is needed; others are refused at open).
typedef Decompress = Uint8List Function(Uint8List data, Compression c);

class PmTilesHeader {
  PmTilesHeader._({
    required this.rootOffset,
    required this.rootLength,
    required this.metadataOffset,
    required this.metadataLength,
    required this.leafOffset,
    required this.leafLength,
    required this.tileDataOffset,
    required this.tileDataLength,
    required this.addressedTiles,
    required this.internalCompression,
    required this.tileCompression,
    required this.tileType,
    required this.minZoom,
    required this.maxZoom,
    required this.minLon,
    required this.minLat,
    required this.maxLon,
    required this.maxLat,
    required this.centerZoom,
    required this.centerLon,
    required this.centerLat,
  });

  static const length = 127;

  final int rootOffset, rootLength, metadataOffset, metadataLength, leafOffset, leafLength;
  final int tileDataOffset, tileDataLength, addressedTiles;
  final Compression internalCompression, tileCompression;
  final TileType tileType;
  final int minZoom, maxZoom, centerZoom;
  final double minLon, minLat, maxLon, maxLat, centerLon, centerLat;

  /// Parses the first 127 bytes. Throws [PmTilesException] for anything
  /// that isn't a PMTiles v3 header.
  static PmTilesHeader parse(Uint8List b) {
    if (b.length < length) throw PmTilesException('not a PMTiles file (too short)');
    if (ascii.decode(b.sublist(0, 7), allowInvalid: true) != 'PMTiles') {
      throw PmTilesException('not a PMTiles file');
    }
    if (b[7] != 3) throw PmTilesException('PMTiles version ${b[7]}; only version 3 is supported');
    final d = ByteData.sublistView(b);
    int u64(int at) => d.getUint64(at, Endian.little);
    double e7(int at) => d.getInt32(at, Endian.little) / 1e7;
    Compression comp(int v) =>
        v < Compression.values.length ? Compression.values[v] : Compression.unknown;
    return PmTilesHeader._(
      rootOffset: u64(8),
      rootLength: u64(16),
      metadataOffset: u64(24),
      metadataLength: u64(32),
      leafOffset: u64(40),
      leafLength: u64(48),
      tileDataOffset: u64(56),
      tileDataLength: u64(64),
      addressedTiles: u64(72),
      internalCompression: comp(b[97]),
      tileCompression: comp(b[98]),
      tileType: b[99] < TileType.values.length ? TileType.values[b[99]] : TileType.unknown,
      minZoom: b[100],
      maxZoom: b[101],
      minLon: e7(102),
      minLat: e7(106),
      maxLon: e7(110),
      maxLat: e7(114),
      centerZoom: b[118],
      centerLon: e7(119),
      centerLat: e7(123),
    );
  }

  /// Why the dashboard can't show this tileset, or null if it can.
  String? problem() {
    switch (tileType) {
      case TileType.png || TileType.jpeg || TileType.webp:
        break;
      case TileType.mvt:
        return 'vector tiles (MVT) can\'t be shown: the map needs a raster tileset (ADR-0030)';
      case TileType.avif:
        return 'AVIF tiles can\'t be decoded; use PNG, JPEG or WebP';
      case TileType.unknown:
        return 'the tile type is unknown; use PNG, JPEG or WebP';
    }
    for (final (what, c) in [('directories', internalCompression), ('tiles', tileCompression)]) {
      if (c == Compression.brotli || c == Compression.zstd) {
        return 'its $what are ${c.name}-compressed; only gzip or none is supported';
      }
    }
    if (minZoom > maxZoom || maxZoom > 26) return 'bad zoom range $minZoom–$maxZoom';
    return null;
  }
}

/// One directory entry: a run of tiles, or (runLength 0) a leaf directory.
class Entry {
  const Entry(this.tileId, this.offset, this.length, this.runLength);
  final int tileId, offset, length, runLength;
}

/// (4^z − 1) / 3: how many tiles all the zooms below z hold.
int _zoomBase(int z) => ((1 << (2 * z)) - 1) ~/ 3;

/// The tile's id: its zoom's base plus its position on the Hilbert curve.
int tileId(int z, int x, int y) {
  if (z < 0 || z > 26) throw RangeError.range(z, 0, 26, 'z');
  final n = 1 << z;
  if (x < 0 || y < 0 || x >= n || y >= n) throw RangeError('tile $z/$x/$y is outside zoom $z');
  var d = 0;
  var tx = x, ty = y;
  for (var s = n >> 1; s > 0; s >>= 1) {
    final rx = (tx & s) > 0 ? 1 : 0;
    final ry = (ty & s) > 0 ? 1 : 0;
    d += s * s * ((3 * rx) ^ ry);
    if (ry == 0) {
      if (rx == 1) {
        tx = n - 1 - tx;
        ty = n - 1 - ty;
      }
      final t = tx;
      tx = ty;
      ty = t;
    }
  }
  return _zoomBase(z) + d;
}

class _Bytes {
  _Bytes(this.b);
  final Uint8List b;
  int at = 0;

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (at >= b.length) throw PmTilesException('a directory ends early');
      final byte = b[at++];
      result += (byte & 0x7f) * (1 << shift);
      if (byte < 0x80) return result;
      shift += 7;
      if (shift > 63) throw PmTilesException('a directory has a bad number');
    }
  }
}

/// Decodes a (decompressed) directory.
List<Entry> decodeDirectory(Uint8List bytes) {
  final r = _Bytes(bytes);
  final n = r.varint();
  if (n > bytes.length) throw PmTilesException('a directory claims $n entries');
  final ids = List<int>.filled(n, 0);
  var last = 0;
  for (var i = 0; i < n; i++) {
    last += r.varint();
    ids[i] = last;
  }
  final runs = [for (var i = 0; i < n; i++) r.varint()];
  final lengths = [for (var i = 0; i < n; i++) r.varint()];
  final offsets = List<int>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final v = r.varint();
    if (v == 0 && i > 0) {
      offsets[i] = offsets[i - 1] + lengths[i - 1];
    } else {
      offsets[i] = v - 1;
    }
  }
  return [for (var i = 0; i < n; i++) Entry(ids[i], offsets[i], lengths[i], runs[i])];
}

/// The entry covering [id]: the last with tileId ≤ id, if it's a leaf
/// pointer or its run reaches [id].
Entry? findEntry(List<Entry> entries, int id) {
  var lo = 0, hi = entries.length - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final c = entries[mid].tileId;
    if (c == id) return entries[mid];
    if (c < id) {
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  if (hi >= 0) {
    final e = entries[hi];
    if (e.runLength == 0) return e;
    if (id - e.tileId < e.runLength) return e;
  }
  return null;
}

class PmTilesReader {
  PmTilesReader._(this.header, this._root, this._read, this._decompress, this.metadata);

  final PmTilesHeader header;
  final List<Entry> _root;
  final ReadRange _read;
  final Decompress _decompress;

  /// The tileset's JSON metadata (name, attribution, ...); empty if none.
  final Map<String, dynamic> metadata;

  final _leaves = <int, List<Entry>>{};
  static const _maxLeaves = 64;

  /// Opens a tileset. Throws [PmTilesException] for one the dashboard can't
  /// show, saying why.
  static Future<PmTilesReader> open(ReadRange read, Decompress decompress) async {
    final header = PmTilesHeader.parse(await read(0, PmTilesHeader.length));
    final problem = header.problem();
    if (problem != null) throw PmTilesException(problem);
    final root = decodeDirectory(
      decompress(await read(header.rootOffset, header.rootLength), header.internalCompression),
    );
    var metadata = <String, dynamic>{};
    if (header.metadataLength > 0) {
      try {
        final raw = decompress(
          await read(header.metadataOffset, header.metadataLength),
          header.internalCompression,
        );
        final j = jsonDecode(utf8.decode(raw));
        if (j is Map<String, dynamic>) metadata = j;
      } on FormatException {
        // Metadata is optional; a bad one doesn't stop the map.
      }
    }
    return PmTilesReader._(header, root, read, decompress, metadata);
  }

  /// The attribution the tileset carries, if any (HTML stripped).
  String? get attribution {
    final a = metadata['attribution'];
    if (a is! String || a.trim().isEmpty) return null;
    return a.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  String? get name => metadata['name'] is String ? metadata['name'] as String : null;

  /// The tile's bytes, or null if the tileset doesn't have it.
  Future<Uint8List?> tile(int z, int x, int y) async {
    if (z < header.minZoom || z > header.maxZoom) return null;
    final id = tileId(z, x, y);
    var dir = _root;
    for (var depth = 0; depth < 4; depth++) {
      final e = findEntry(dir, id);
      if (e == null) return null;
      if (e.runLength > 0) {
        final data = await _read(header.tileDataOffset + e.offset, e.length);
        return header.tileCompression == Compression.gzip
            ? _decompress(data, Compression.gzip)
            : data;
      }
      dir = await _leaf(e.offset, e.length);
    }
    throw PmTilesException('directories nest too deep');
  }

  Future<List<Entry>> _leaf(int offset, int length) async {
    final hit = _leaves.remove(offset);
    if (hit != null) return _leaves[offset] = hit; // most recent last
    final dir = decodeDirectory(
      _decompress(await _read(header.leafOffset + offset, length), header.internalCompression),
    );
    if (_leaves.length >= _maxLeaves) _leaves.remove(_leaves.keys.first);
    return _leaves[offset] = dir;
  }
}
