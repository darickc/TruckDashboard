import 'dart:convert';
import 'dart:io';

import 'package:f250_infotainment/nav/online_map.dart';
import 'package:f250_infotainment/nav/online_vector_map.dart';
import 'package:f250_infotainment/nav/route_state.dart';
import 'package:f250_infotainment/network/wifi_state.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../harness.dart';
import 'navigation_route_test.dart' show FakeRouteSource, progress, route7, view;
import 'navigation_screen_test.dart' show textOf;

/// A 1×1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// navigation's online map, set by the test: a token or not, tiles that
/// load or fail.
class FakeOnlineMap implements OnlineMapSource {
  FakeOnlineMap({bool configured = true, this.fail = false, bool vector = false, this.failStyle = false})
    : _status = ValueNotifier(
        OnlineMapStatus(
          configured: configured,
          attribution: '© Mapbox © OpenStreetMap',
          detail: configured ? 'Mapbox' : 'no Mapbox token',
          vector: vector,
        ),
      );

  final ValueNotifier<OnlineMapStatus> _status;
  bool fail;
  bool failStyle;
  final asked = <(int, int, int, bool)>[];
  final stylesAsked = <bool>[];
  final ratiosAsked = <int>[];
  final vectorAsked = <String>[];

  @override
  Future<OnlineMapStyleData> style({required bool night, required int pixelRatio}) async {
    stylesAsked.add(night);
    ratiosAsked.add(pixelRatio);
    if (failStyle) throw StateError('Mapbox style HTTP 401 Not Authorized - Invalid Token');
    return OnlineMapStyleData(
      styleJson: File('test/fixtures/maps/online-style-handwritten.json').readAsStringSync(),
      spriteJson: '{}',
      spritePng: Uint8List.fromList(_png),
      sources: const [OnlineMapSourceZooms('composite', 0, 16), OnlineMapSourceZooms('mapbox-traffic', 6, 16)],
    );
  }

  @override
  Future<Uint8List> vectorTile(String source, int z, int x, int y, {required bool night}) async {
    vectorAsked.add(source);
    if (fail) throw StateError('Mapbox unreachable: curl: (6) Could not resolve host');
    return Uint8List(0);
  }

  @override
  ValueListenable<OnlineMapStatus> get status => _status;
  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<Uint8List> tile(int z, int x, int y, {required bool night}) async {
    asked.add((z, x, y, night));
    if (fail) throw StateError('Mapbox unreachable: curl: (6) Could not resolve host');
    return Uint8List.fromList(_png);
  }
}

bool _onlineVectorShown(WidgetTester tester) => tester
    .widgetList<VectorTileLayer>(find.byType(VectorTileLayer))
    .any((l) => l.tileProviders.tileProviderBySource.values.any((p) => p is OnlineVectorProvider));

bool _onlineLayerShown(WidgetTester tester) =>
    tester.widgetList<TileLayer>(find.byType(TileLayer)).any((l) => l.tileProvider is OnlineTileProvider);

void main() {
  setUpAll(loadTestAssets);

  Future<Harness> open(WidgetTester tester, {required WifiSource wifi, required OnlineMapSource online, FakeRouteSource? route}) async {
    final h = await Harness.start(tester, wifi: wifi, onlineMap: online, route: route);
    await h.goTo(AppScreen.navigation);
    return h;
  }

  testWidgets('on a network with a token: Mapbox\'s map, said so, no "no map" notice', (tester) async {
    final online = FakeOnlineMap();
    await open(tester, wifi: SimulatedWifiSource()..start(), online: online);
    expect(_onlineLayerShown(tester), isTrue);
    final layer = tester.widgetList<TileLayer>(find.byType(TileLayer)).single;
    expect(layer.tileDimension, 512);
    expect(layer.zoomOffset, -1);
    expect(textOf('nav-attribution'), 'Mapbox · © Mapbox © OpenStreetMap');
    expect(find.byKey(const ValueKey('nav-map-problem')), findsNothing, reason: 'no map stick is needed online');
  });

  testWidgets('Wi-Fi off, or no token: the offline map as before', (tester) async {
    final wifi = SimulatedWifiSource()..start();
    final h = await open(tester, wifi: wifi, online: FakeOnlineMap());
    expect(_onlineLayerShown(tester), isTrue);
    await wifi.setEnabled(false);
    await tester.pump();
    expect(_onlineLayerShown(tester), isFalse);
    expect(find.byKey(const ValueKey('nav-map-problem')), findsOneWidget, reason: 'no offline map in this test');
    expect(textOf('nav-attribution'), isNot(startsWith('Mapbox')));
    expect(h.services.wifi.view.value.onNetwork, isFalse);
  });

  testWidgets('no token: offline even on a network', (tester) async {
    await open(tester, wifi: SimulatedWifiSource()..start(), online: FakeOnlineMap(configured: false));
    expect(_onlineLayerShown(tester), isFalse);
  });

  testWidgets('tiles that keep failing: the offline map, saying why', (tester) async {
    final online = FakeOnlineMap(fail: true);
    await open(tester, wifi: SimulatedWifiSource()..start(), online: online);
    for (var i = 0; i < 10 && _onlineLayerShown(tester); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(online.asked.length, greaterThanOrEqualTo(3));
    expect(_onlineLayerShown(tester), isFalse);
    expect(textOf('nav-online-failing'), startsWith('Online map not loading'));
    // The backoff's timer comes back on its own; let it run out.
    await tester.pump(const Duration(seconds: 61));
  });

  // The vector map (ADR-0052 decision 6, amended 2026-11-24). Its tiles are
  // empty here: vector_map_tiles' label queue outlives a test's fake-time
  // zone once tiles are drawn (navigation_screen_test.dart).
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 75 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // Failed tiles reaching the chooser: online_vector_map_test.dart (the
  // provider reports each outcome) and the raster tests above (the chooser).
  // Not here: a vector layer removed while its tiles load throws vector_map_tiles'
  // CancellationException, which the app drops (ignoreDroppedTiles, main.dart)
  // and a widget test can't.
  testWidgets("vector: Mapbox's style drawn by the dashboard, at Mapbox's 512 pixels", (tester) async {
    final online = FakeOnlineMap(vector: true);
    await open(tester, wifi: SimulatedWifiSource()..start(), online: online);
    await settle(tester, () => _onlineVectorShown(tester));
    expect(_onlineVectorShown(tester), isTrue);
    expect(_onlineLayerShown(tester), isFalse, reason: 'no raster layer');
    final layer = tester.widget<VectorTileLayer>(find.byType(VectorTileLayer));
    expect(layer.theme.id, 'test-online');
    expect(layer.tileOffset, TileOffset.mapbox);
    expect(layer.layerMode, VectorTileLayerMode.vector, reason: 'labels upright on a turned map');
    expect(layer.tileProviders.tileProviderBySource.keys, unorderedEquals(['composite', 'mapbox-traffic']));
    expect(online.stylesAsked, hasLength(1), reason: 'read once');
    // The panel is 1:1 (800 x 480 at 1): Mapbox's 1x sprites.
    expect(tester.view.devicePixelRatio, 1);
    expect(online.ratiosAsked, [1]);
    expect(textOf('nav-attribution'), 'Mapbox · © Mapbox © OpenStreetMap');
    expect(find.byKey(const ValueKey('nav-map-problem')), findsNothing);
    // Let the layer's own timers finish.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets("vector: a style that can't be read: the offline map, saying why, then tried again", (tester) async {
    final online = FakeOnlineMap(vector: true, failStyle: true);
    await open(tester, wifi: SimulatedWifiSource()..start(), online: online);
    await settle(tester, () => find.byKey(const ValueKey('nav-online-failing')).evaluate().isNotEmpty);
    expect(_onlineVectorShown(tester), isFalse);
    expect(textOf('nav-online-failing'), 'Online map not loading (Mapbox style HTTP 401 Not Authorized - Invalid Token): the offline map for now');
    expect(find.byKey(const ValueKey('nav-map-problem')), findsOneWidget, reason: 'no offline map in this test');
    expect(online.stylesAsked, hasLength(1));
    await tester.pump(const Duration(seconds: 29));
    expect(online.stylesAsked, hasLength(1), reason: 'not before 30 s');
    online.failStyle = false;
    await tester.pump(const Duration(seconds: 2));
    await settle(tester, () => _onlineVectorShown(tester));
    expect(online.stylesAsked, hasLength(2));
    expect(_onlineVectorShown(tester), isTrue);
    expect(find.byKey(const ValueKey('nav-online-failing')), findsNothing);
    // Let the layer's own timers finish.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  for (final (provider, words) in [('mapbox', 'Mapbox route · live traffic'), ('valhalla', 'Offline route'), ('', 'Offline route')]) {
    testWidgets('a route says where it came from: "$provider"', (tester) async {
      final src = FakeRouteSource(const RouteView(link: RouteLink.connecting));
      final r = NavRoute(
        id: route7.id,
        shape: route7.shape,
        maneuvers: route7.maneuvers,
        lengthM: route7.lengthM,
        timeS: route7.timeS,
        destination: route7.destination,
        costing: 'auto',
        provider: provider,
      );
      src.value = view(src, RouteState.active, progress: progress, route: r);
      await open(tester, wifi: UnavailableWifiSource(), online: FakeOnlineMap(configured: false), route: src);
      expect(textOf('nav-route-source'), words);
      expect(textOf('nav-heavy-warning'), 'Not checked for heavy vehicles or trailers');
    });
  }
}
