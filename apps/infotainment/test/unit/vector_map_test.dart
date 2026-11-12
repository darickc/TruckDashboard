// The vector map's bundled styles and its tile provider (ADR-0032).
import 'dart:convert';
import 'dart:io';

import 'package:executor_lib/executor_lib.dart' show CancellationException;
import 'package:f250_infotainment/nav/offline_map.dart';
import 'package:f250_infotainment/nav/pmtiles.dart';
import 'package:f250_infotainment/nav/pmtiles_file.dart';
import 'package:f250_infotainment/nav/vector_map.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

const fixture = 'test/fixtures/maps/vector-z12-15.pmtiles';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bundled styles', () {
    late VectorMapStyles styles;
    final warnings = <String>[];

    setUpAll(() async {
      styles = await VectorMapStyles.load(rootBundle, warnings: warnings);
    });

    test('both read with every expression understood', () {
      // tools/maps/map-assets.py rewrites what vector_tile_renderer can't
      // parse; anything it misses shows up here.
      expect(warnings.where((w) => w.contains('Unsupported')), isEmpty);
      expect(styles.day.theme.id, 'protomaps-light');
      expect(styles.night.theme.id, 'protomaps-dark');
    });

    for (final flavor in ['light', 'dark']) {
      test('$flavor: every layer is drawn, fonts are bundled, icons exist', () async {
        final json =
            jsonDecode(await rootBundle.loadString('assets/map/styles/$flavor.json'))
                as Map<String, dynamic>;
        final layers = (json['layers'] as List).cast<Map<String, dynamic>>();
        final theme = flavor == 'light' ? styles.day.theme : styles.night.theme;
        // The renderer skips only the one-way arrows, a symbol layer with
        // no paint that starts at zoom 16 (past the data's zoom 15).
        final read = theme.layers.map((l) => l.id).toSet();
        expect(
          layers.map((l) => l['id']).where((id) => !read.contains(id)),
          ['roads_oneway'],
        );

        final pubspec = File('pubspec.yaml').readAsStringSync();
        final fonts = {
          for (final l in layers)
            ...((l['layout'] as Map?)?['text-font'] as List? ?? const []).cast<String>(),
        };
        expect(fonts, isNotEmpty);
        for (final f in fonts) {
          expect(pubspec, contains('family: $f'), reason: 'font $f is not bundled');
        }

        final sprites =
            jsonDecode(await rootBundle.loadString('assets/map/sprites/$flavor@2x.json'))
                as Map<String, dynamic>;
        for (final l in layers) {
          final icon = (l['layout'] as Map?)?['icon-image'];
          if (icon is String) expect(sprites, contains(icon), reason: '${l['id']}: $icon');
        }
      });
    }
  });

  group('ignoreDroppedTiles', () {
    test("a dropped tile's cancellation is handled; anything else isn't", () {
      final handler = ignoreDroppedTiles(null);
      expect(handler(CancellationException(), StackTrace.empty), isTrue);
      expect(handler(StateError('a real bug'), StackTrace.empty), isFalse);
      expect(handler('Cancelled', StackTrace.empty), isFalse, reason: 'only the type, not the text');
    });

    test('everything else still reaches the handler that was there', () {
      final seen = <Object>[];
      final handler = ignoreDroppedTiles((e, _) {
        seen.add(e);
        return true;
      });
      expect(handler(CancellationException(), StackTrace.empty), isTrue);
      final bug = StateError('a real bug');
      expect(handler(bug, StackTrace.empty), isTrue);
      expect(seen, [bug]);
    });
  });

  group('PmTilesVectorProvider', () {
    late PmTilesReader reader;
    setUpAll(() async => reader = await openPmTilesFile(fixture));

    test('serves the tileset\'s vector tiles', () async {
      final p = PmTilesVectorProvider(reader);
      expect((p.minimumZoom, p.maximumZoom), (12, 15));
      // The fixture's zoom-15 tiles around Lebanon, Kansas.
      final bytes = await p.provide(TileIdentity(15, 7413, 12427));
      final tile = vtr.VectorTileReader().read(bytes);
      expect(tile.layers.map((l) => l.name), containsAll(['earth', 'roads']));
    });

    test('a tile outside the region is missing, not retried', () async {
      final p = PmTilesVectorProvider(reader);
      expect(
        () => p.provide(TileIdentity(15, 0, 0)),
        throwsA(
          isA<ProviderException>().having((e) => e.retryable, 'retryable', Retryable.none),
        ),
      );
    });
  });

  group('OfflineMap', () {
    test('a vector tileset is ready with its styles', () async {
      final map = OfflineMap(fixture, open: openPmTilesFile);
      await map.load();
      final state = map.state.value;
      expect(state, isA<MapReady>());
      expect((state as MapReady).vector, isNotNull);
      expect(state.reader.attribution, '© OpenStreetMap', reason: 'the Protomaps &copy; decoded');
    });

    test('a raster tileset has no vector part', () async {
      final map = OfflineMap('test/fixtures/maps/solid-z0-3.pmtiles', open: openPmTilesFile);
      await map.load();
      expect((map.state.value as MapReady).vector, isNull);
    });

    test('styles that can\'t be read say so', () async {
      final map = OfflineMap(
        fixture,
        open: openPmTilesFile,
        loadStyles: () async => throw const FormatException('bad style'),
      );
      await map.load();
      expect(
        (map.state.value as MapUnavailable).why,
        allOf(contains('vector map styles'), contains('bad style')),
      );
    });
  });

  test('the fixture is what the README says', () async {
    final r = await openPmTilesFile(fixture);
    expect(r.header.tileType, TileType.mvt);
    expect(r.header.tileCompression, Compression.gzip);
    expect(await r.tile(12, 926, 1553), isA<Uint8List>());
  });
}
