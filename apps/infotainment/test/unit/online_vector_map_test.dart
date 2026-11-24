// The online map as Mapbox vector tiles (ADR-0052 decision 6, amended
// 2026-11-24): the style as navigation hands it on, its fonts, its sources.
import 'dart:convert';
import 'dart:io';

import 'package:f250_infotainment/nav/online_map.dart';
import 'package:f250_infotainment/nav/online_vector_map.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

const styleFixture = 'test/fixtures/maps/online-style-handwritten.json';

/// A 1×1 PNG.
final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _Source implements OnlineMapSource {
  bool fail = false;
  final asked = <String>[];

  @override
  ValueListenable<OnlineMapStatus> get status => ValueNotifier(const OnlineMapStatus(configured: true, vector: true));
  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<Uint8List> tile(int z, int x, int y, {required bool night}) => throw UnimplementedError();
  @override
  Future<OnlineMapStyleData> style({required bool night, required int pixelRatio}) async => OnlineMapStyleData(
    styleJson: File(styleFixture).readAsStringSync(),
    spriteJson: '{"us-highway-3":{"x":0,"y":0,"width":1,"height":1,"pixelRatio":2,"placeholder":[0,0,1,1]}}',
    spritePng: Uint8List.fromList(png),
    sources: const [OnlineMapSourceZooms('composite', 0, 16), OnlineMapSourceZooms('mapbox-traffic', 6, 16)],
  );
  @override
  Future<Uint8List> vectorTile(String source, int z, int x, int y, {required bool night}) async {
    asked.add('$source $z/$x/$y ${night ? 'night' : 'day'}');
    if (fail) throw StateError('Mapbox unreachable: curl: (6) Could not resolve host');
    return Uint8List(0);
  }
}

void main() {
  test("Mapbox's fonts become the bundled ones, keeping weight and slant", () {
    expect(bundledFontFor('DIN Pro Regular'), 'Noto Sans Regular');
    expect(bundledFontFor('Arial Unicode MS Regular'), 'Noto Sans Regular');
    expect(bundledFontFor('DIN Pro Medium'), 'Noto Sans Medium');
    expect(bundledFontFor('DIN Pro Bold'), 'Noto Sans Medium');
    expect(bundledFontFor('Arial Unicode MS Bold'), 'Noto Sans Medium');
    expect(bundledFontFor('DIN Pro Italic'), 'Noto Sans Italic');
  });

  test('only font names are swapped, inside expressions too', () {
    final style = jsonDecode(File(styleFixture).readAsStringSync()) as Map<String, dynamic>;
    useBundledFonts(style);
    final layers = {for (final l in style['layers'] as List) l['id']: l};
    expect(layers['road-label']['layout']['text-font'], [
      'step',
      ['zoom'],
      ['literal', ['Noto Sans Regular', 'Noto Sans Regular']],
      15,
      ['literal', ['Noto Sans Medium', 'Noto Sans Medium']],
    ]);
    expect(layers['shield']['layout']['text-font'], ['Noto Sans Italic', 'Noto Sans Regular']);
    expect(layers['road']['paint'], isNot(contains('text-font')), reason: 'other layers untouched');
  });

  test("the style is read with every layer, and a provider for each of navigation's sources", () async {
    final source = _Source();
    final warnings = <String>[];
    final m = await OnlineVectorMap.load(source, night: true, pixelRatio: 2, onResult: (_, _) {}, warnings: warnings);
    expect(warnings, isEmpty);
    expect(m.theme.layers.map((l) => l.id), ['background', 'road', 'traffic', 'road-label', 'shield']);
    final composite = m.providers.get('composite');
    final traffic = m.providers.get('mapbox-traffic');
    expect((composite.minimumZoom, composite.maximumZoom), (0, 16));
    expect((traffic.minimumZoom, traffic.maximumZoom), (6, 16));
    expect(await m.sprites.atlasProvider(), png);
    expect(m.sprites.index.spriteByName['us-highway-3']!.content, isNull);
  });

  test("tiles come from navigation by source and look, and each outcome is reported", () async {
    final source = _Source();
    final results = <(bool, String)>[];
    final m = await OnlineVectorMap.load(source, night: false, pixelRatio: 2, onResult: (ok, why) => results.add((ok, why)));
    final bytes = await m.providers.get('mapbox-traffic').provide(TileIdentity(14, 3, 4));
    expect(bytes, isEmpty, reason: 'nothing there: an empty tile, not a failure');
    expect(source.asked, ['mapbox-traffic 14/3/4 day']);
    source.fail = true;
    await expectLater(
      m.providers.get('composite').provide(TileIdentity(14, 3, 4)),
      throwsA(
        isA<ProviderException>()
            .having((e) => e.retryable, 'retryable', Retryable.none)
            // Shown empty and asked again later, not an uncaught error.
            .having((e) => e.statusCode, 'statusCode', 204),
      ),
    );
    expect(results, [(true, ''), (false, 'Mapbox unreachable: curl: (6) Could not resolve host')]);
  });

  test('1x sprites for a 1:1 screen like the bench Pi\'s, 2x for sharper ones', () {
    expect(spritePixelRatio(1), 1);
    expect(spritePixelRatio(1.25), 1);
    expect(spritePixelRatio(2), 2);
    expect(spritePixelRatio(3), 2);
  });
}
