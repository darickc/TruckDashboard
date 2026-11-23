import 'dart:convert';

import 'package:f250_infotainment/nav/online_map.dart';
import 'package:f250_infotainment/nav/route_state.dart';
import 'package:f250_infotainment/network/wifi_state.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

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
  FakeOnlineMap({bool configured = true, this.fail = false})
    : _status = ValueNotifier(
        OnlineMapStatus(
          configured: configured,
          attribution: '© Mapbox © OpenStreetMap',
          detail: configured ? 'Mapbox' : 'no Mapbox token',
        ),
      );

  final ValueNotifier<OnlineMapStatus> _status;
  bool fail;
  final asked = <(int, int, int, bool)>[];

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
