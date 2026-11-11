// Checks a built map file with the dashboard's own reader (ADR-0031, ADR-0032):
//
//   cd apps/infotainment && MAP_CHECK=/path/to/map.pmtiles fvm flutter test test/unit/map_file_check_test.dart
//
// `make map-check MAP=...` runs it. Without MAP_CHECK it is skipped, so the
// default suite needs no map, network or Docker.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:f250_infotainment/nav/pmtiles.dart';
import 'package:f250_infotainment/nav/pmtiles_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

(int, int) _tileAt(int z, double lon, double lat) {
  final n = 1 << z;
  final r = lat.clamp(-85.0511, 85.0511) * math.pi / 180;
  final x = ((lon + 180) / 360 * n).floor().clamp(0, n - 1);
  final y = ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n).floor().clamp(
    0,
    n - 1,
  );
  return (x, y);
}

bool _magic(TileType t, Uint8List b) => switch (t) {
  TileType.png => b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47,
  TileType.jpeg => b.length > 3 && b[0] == 0xFF && b[1] == 0xD8,
  TileType.webp =>
    b.length > 12 &&
        String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(b.sublist(8, 12)) == 'WEBP',
  TileType.mvt => b.isNotEmpty, // decoded below
  _ => false,
};

void main() {
  final path = Platform.environment['MAP_CHECK'];

  testWidgets(
    'a built map opens, carries the OSM attribution, and its tiles decode',
    (tester) async {
      await tester.runAsync(() async {
        final r = await openPmTilesFile(path!);
        final h = r.header;
        expect([TileType.mvt, TileType.png, TileType.jpeg, TileType.webp], contains(h.tileType));
        expect(r.attribution, contains('OpenStreetMap'));
        expect(h.minLon, lessThan(h.maxLon));
        expect(h.minLat, lessThan(h.maxLat));

        // At every zoom: the tiles at the bounds' centre and four corners
        // (pulled 1% inside) exist, are the declared format, and decode:
        // raster to 256 × 256 images, vector to tiles with the Protomaps
        // layers the bundled styles draw.
        final dx = (h.maxLon - h.minLon) * 0.01, dy = (h.maxLat - h.minLat) * 0.01;
        final points = [
          ((h.minLon + h.maxLon) / 2, (h.minLat + h.maxLat) / 2),
          (h.minLon + dx, h.minLat + dy),
          (h.minLon + dx, h.maxLat - dy),
          (h.maxLon - dx, h.minLat + dy),
          (h.maxLon - dx, h.maxLat - dy),
        ];
        var decoded = 0;
        for (var z = h.minZoom; z <= h.maxZoom; z++) {
          for (final (lon, lat) in points) {
            final (x, y) = _tileAt(z, lon, lat);
            final bytes = await r.tile(z, x, y);
            expect(bytes, isNotNull, reason: 'tile $z/$x/$y');
            expect(_magic(h.tileType, bytes!), isTrue, reason: '$z/$x/$y is not ${h.tileType}');
            if (h.tileType == TileType.mvt) {
              final tile = vtr.VectorTileReader().read(bytes);
              expect(tile.layers.map((l) => l.name), contains('earth'), reason: '$z/$x/$y');
              decoded++;
              continue;
            }
            final codec = await ui.instantiateImageCodec(bytes);
            final frame = await codec.getNextFrame();
            expect((frame.image.width, frame.image.height), (256, 256), reason: '$z/$x/$y');
            frame.image.dispose();
            codec.dispose();
            decoded++;
          }
        }
        // Outside the bounds at the top zoom there are no tiles.
        final (ox, oy) = _tileAt(h.maxZoom, h.maxLon + (h.maxLon - h.minLon), h.maxLat);
        expect(await r.tile(h.maxZoom, ox, oy), isNull);

        // ignore: avoid_print
        print(
          '$path: ${h.tileType.name}, zooms ${h.minZoom}-${h.maxZoom}, '
          '${h.addressedTiles} tiles, $decoded decoded; "${r.attribution}"',
        );
      });
    },
    skip: path == null,
  );
}
