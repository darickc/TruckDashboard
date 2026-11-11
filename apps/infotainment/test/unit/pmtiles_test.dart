import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:f250_infotainment/nav/pmtiles.dart';
import 'package:f250_infotainment/nav/pmtiles_file.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtures = 'test/fixtures/maps';

/// Varint, as PMTiles directories use it.
List<int> _varint(int v) {
  final out = <int>[];
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}

Uint8List _directory(List<Entry> entries) {
  final b = <int>[..._varint(entries.length)];
  var last = 0;
  for (final e in entries) {
    b.addAll(_varint(e.tileId - last));
    last = e.tileId;
  }
  for (final e in entries) {
    b.addAll(_varint(e.runLength));
  }
  for (final e in entries) {
    b.addAll(_varint(e.length));
  }
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final contiguous = i > 0 && e.offset == entries[i - 1].offset + entries[i - 1].length;
    b.addAll(_varint(contiguous ? 0 : e.offset + 1));
  }
  return Uint8List.fromList(gzip.encode(b));
}

/// A minimal file: header, root, metadata, leaves, tile data.
Uint8List _file({
  required Uint8List root,
  Uint8List? leaves,
  required Uint8List data,
  int tileType = 2,
  int internal = 2,
  int tileCompression = 1,
  int version = 3,
  int minZoom = 0,
  int maxZoom = 14,
  String metadata = '{}',
}) {
  final meta = Uint8List.fromList(gzip.encode(utf8.encode(metadata)));
  final leaf = leaves ?? Uint8List(0);
  final h = ByteData(127);
  final bytes = h.buffer.asUint8List();
  bytes.setAll(0, ascii.encode('PMTiles'));
  bytes[7] = version;
  var at = 127;
  void section(int field, int length) {
    h.setUint64(field, at, Endian.little);
    h.setUint64(field + 8, length, Endian.little);
    at += length;
  }

  section(8, root.length);
  section(24, meta.length);
  section(40, leaf.length);
  section(56, data.length);
  bytes[97] = internal;
  bytes[98] = tileCompression;
  bytes[99] = tileType;
  bytes[100] = minZoom;
  bytes[101] = maxZoom;
  return Uint8List.fromList([...bytes, ...root, ...meta, ...leaf, ...data]);
}

Future<PmTilesReader> _openBytes(Uint8List file) => PmTilesReader.open(
  (offset, length) async =>
      Uint8List.sublistView(file, offset, (offset + length).clamp(0, file.length)),
  decompress,
);

void main() {
  group('tile ids', () {
    test('the spec\'s first tiles', () {
      expect(tileId(0, 0, 0), 0);
      expect(tileId(1, 0, 0), 1);
      expect(tileId(1, 0, 1), 2);
      expect(tileId(1, 1, 1), 3);
      expect(tileId(1, 1, 0), 4);
      expect(tileId(2, 0, 0), 5);
      // Last tile of zoom 2 and first of zoom 3.
      expect(tileId(2, 3, 0), 20);
      expect(tileId(3, 0, 0), 21);
    });

    test('each zoom\'s ids are a permutation of its range', () {
      for (var z = 0; z <= 5; z++) {
        final n = 1 << z;
        final base = ((1 << (2 * z)) - 1) ~/ 3;
        final ids = {
          for (var x = 0; x < n; x++)
            for (var y = 0; y < n; y++) tileId(z, x, y),
        };
        expect(ids.length, n * n);
        expect(ids.reduce((a, b) => a < b ? a : b), base);
        expect(ids.reduce((a, b) => a > b ? a : b), base + n * n - 1);
      }
    });

    test('outside the zoom is refused', () {
      expect(() => tileId(1, 2, 0), throwsRangeError);
      expect(() => tileId(27, 0, 0), throwsRangeError);
    });
  });

  group('files written by the official pmtiles tool', () {
    test('every tile of id-z0-6 comes back as [z, x, y]', () async {
      final r = await openPmTilesFile('$_fixtures/id-z0-6.pmtiles');
      expect(r.header.minZoom, 0);
      expect(r.header.maxZoom, 6);
      expect(r.header.tileType, TileType.png);
      expect(r.header.internalCompression, Compression.gzip);
      expect(r.header.minLon, closeTo(-98.60, 1e-6));
      expect(r.header.maxLat, closeTo(39.88, 1e-6));
      expect(r.name, 'F-250 test pattern (id)');
      expect(r.attribution, 'Test pattern, not map data');
      for (var z = 0; z <= 6; z++) {
        for (var x = 0; x < 1 << z; x++) {
          for (var y = 0; y < 1 << z; y++) {
            expect(await r.tile(z, x, y), [z, x, y], reason: '$z/$x/$y');
          }
        }
      }
      expect(await r.tile(7, 0, 0), isNull, reason: 'above the max zoom');
    });

    test('solid-z0-3: deduplicated PNG runs', () async {
      final r = await openPmTilesFile('$_fixtures/solid-z0-3.pmtiles');
      const png = [0x89, 0x50, 0x4E, 0x47];
      final byColour = <int, Uint8List>{};
      for (var z = 0; z <= 3; z++) {
        for (var x = 0; x < 1 << z; x++) {
          for (var y = 0; y < 1 << z; y++) {
            final t = (await r.tile(z, x, y))!;
            expect(t.sublist(0, 4), png);
            // Same colour index as test-pattern-map.py → the same bytes.
            final colour = (x * 7 + y * 3 + z) % 5;
            final seen = byColour.putIfAbsent(colour, () => t);
            expect(t, seen, reason: '$z/$x/$y');
          }
        }
      }
      expect(byColour.length, 5);
    });

    test('a missing file says where it looked', () async {
      await expectLater(
        openPmTilesFile('$_fixtures/none.pmtiles'),
        throwsA(
          isA<PmTilesException>().having(
            (e) => e.message,
            'message',
            contains('no offline map at'),
          ),
        ),
      );
    });
  });

  group('built in the test', () {
    test('leaf directories', () async {
      // Tiles at zoom 14: two leaves of three tiles each.
      final ids = [
        for (final (x, y) in [(10, 10), (10, 11), (11, 11), (500, 7), (501, 7), (502, 9)])
          tileId(14, x, y),
      ]..sort();
      final data = <int>[];
      final leafEntries = <List<Entry>>[[], []];
      for (var i = 0; i < ids.length; i++) {
        final bytes = utf8.encode('t${ids[i]}');
        leafEntries[i ~/ 3].add(Entry(ids[i], data.length, bytes.length, 1));
        data.addAll(bytes);
      }
      final leaf0 = _directory(leafEntries[0]);
      final leaf1 = _directory(leafEntries[1]);
      final root = _directory([
        Entry(ids[0], 0, leaf0.length, 0),
        Entry(ids[3], leaf0.length, leaf1.length, 0),
      ]);
      final r = await _openBytes(
        _file(
          root: root,
          leaves: Uint8List.fromList([...leaf0, ...leaf1]),
          data: Uint8List.fromList(data),
        ),
      );
      for (final (x, y) in [(10, 10), (10, 11), (11, 11), (500, 7), (501, 7), (502, 9)]) {
        expect(utf8.decode((await r.tile(14, x, y))!), 't${tileId(14, x, y)}');
      }
      expect(await r.tile(14, 12, 12), isNull);
      expect(await r.tile(14, 0, 0), isNull, reason: 'before the first entry');
    });

    test('a run covers consecutive ids, and no further', () async {
      final first = tileId(2, 0, 0);
      final r = await _openBytes(
        _file(root: _directory([Entry(first, 0, 3, 3)]), data: Uint8List.fromList([1, 2, 3])),
      );
      for (var id = first; id < first + 3; id++) {
        expect(findEntry([Entry(first, 0, 3, 3)], id), isNotNull);
      }
      expect(findEntry([Entry(first, 0, 3, 3)], first + 3), isNull);
      expect(await r.tile(2, 0, 0), [1, 2, 3]);
    });

    test('gzip-compressed tiles are decompressed', () async {
      final tile = gzip.encode([9, 8, 7]);
      final r = await _openBytes(
        _file(
          root: _directory([Entry(0, 0, tile.length, 1)]),
          data: Uint8List.fromList(tile),
          tileCompression: 2,
        ),
      );
      expect(await r.tile(0, 0, 0), [9, 8, 7]);
    });

    Future<String> problemOf(Uint8List file) async {
      try {
        await _openBytes(file);
        return '';
      } on PmTilesException catch (e) {
        return e.message;
      }
    }

    final root = _directory([const Entry(0, 0, 1, 1)]);
    final data = Uint8List.fromList([0]);

    test('vector tiles (MVT) are accepted (ADR-0032)', () async {
      expect(await problemOf(_file(root: root, data: data, tileType: 1)), '');
    });

    test('AVIF and unknown tile types are refused, saying why', () async {
      expect(await problemOf(_file(root: root, data: data, tileType: 5)), contains('AVIF'));
      expect(await problemOf(_file(root: root, data: data, tileType: 0)), contains('unknown'));
    });

    test('brotli and zstd are refused', () async {
      expect(await problemOf(_file(root: root, data: data, internal: 3)), contains('brotli'));
      expect(await problemOf(_file(root: root, data: data, tileCompression: 4)), contains('zstd'));
    });

    test('not PMTiles, or another version', () async {
      final notPm = _file(root: root, data: data)..setAll(0, ascii.encode('MBTiles'));
      expect(await problemOf(notPm), 'not a PMTiles file');
      expect(await problemOf(_file(root: root, data: data, version: 2)), contains('version 2'));
      expect(await problemOf(Uint8List(10)), contains('too short'));
    });

    test('a truncated directory is an error, not a crash', () {
      final good = gzip.decode(_directory([const Entry(5, 0, 1, 1), const Entry(6, 1, 1, 1)]));
      expect(
        () => decodeDirectory(Uint8List.fromList(good.sublist(0, good.length - 1))),
        throwsA(isA<PmTilesException>()),
      );
    });

    test('bad metadata is ignored', () async {
      final r = await _openBytes(_file(root: root, data: data, metadata: 'not json'));
      expect(r.metadata, isEmpty);
      expect(r.attribution, isNull);
    });

    test('HTML in the attribution is stripped', () async {
      final r = await _openBytes(
        _file(
          root: root,
          data: data,
          metadata:
              '{"attribution":"<a href=\\"https://osm.org\\">© OpenStreetMap</a> contributors"}',
        ),
      );
      expect(r.attribution, '© OpenStreetMap contributors');
    });

    test('HTML entities in the attribution are decoded (Protomaps builds)', () async {
      final r = await _openBytes(
        _file(
          root: root,
          data: data,
          metadata:
              '{"attribution":"<a href=\\"https://www.openstreetmap.org/copyright\\">&copy; OpenStreetMap</a> &amp; others"}',
        ),
      );
      expect(r.attribution, '© OpenStreetMap & others');
    });
  });
}
