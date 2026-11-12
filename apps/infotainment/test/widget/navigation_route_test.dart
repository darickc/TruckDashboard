import 'package:f250_infotainment/core/clock.dart';
import 'package:f250_infotainment/model/units.dart';
import 'package:f250_infotainment/nav/offline_map.dart';
import 'package:f250_infotainment/nav/pmtiles_file.dart';
import 'package:f250_infotainment/nav/position_state.dart';
import 'package:f250_infotainment/nav/route_state.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../harness.dart';
import 'navigation_screen_test.dart' show FakePositionSource, textOf;

/// A route source the test sets by hand; records what the screen asks.
class FakeRouteSource implements RouteSource {
  FakeRouteSource(RouteView initial) : _state = ValueNotifier(initial);

  @override
  final FakeMonotonicClock clock = FakeMonotonicClock(const Duration(seconds: 100));
  final ValueNotifier<RouteView> _state;
  final destinations = <LatLng>[];
  var clears = 0;

  @override
  ValueListenable<RouteView> get state => _state;
  set value(RouteView v) => _state.value = v;

  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<void> setDestination(LatLng to) async => destinations.add(to);
  @override
  Future<void> clearRoute() async => clears++;
}

const destination = LatLng(39.8103, -98.5559);

const route7 = NavRoute(
  id: 7,
  shape: [LatLng(39.83, -98.53), LatLng(39.83, -98.54), LatLng(39.8103, -98.5559)],
  maneuvers: [
    Maneuver(type: 2, instruction: 'Drive west.'),
    Maneuver(type: 10, instruction: 'Turn right onto US 36/US 281.', startM: 900),
    Maneuver(type: 4, instruction: 'You have arrived at your destination.', startM: 3000),
  ],
  lengthM: 3000,
  timeS: 240,
  destination: destination,
  costing: 'auto',
);

RouteView view(
  FakeRouteSource src,
  RouteState state, {
  RouteProgress? progress,
  NavRoute? route = route7,
  String detail = '',
  int reroutes = 0,
  RouteLink link = RouteLink.connected,
}) => RouteView(
  link: link,
  guidance: Guidance(
    state: state,
    receivedAt: src.clock.now(),
    routeId: route?.id ?? 0,
    destination: state == RouteState.idle ? null : destination,
    progress: progress,
    detail: detail,
    reroutes: reroutes,
  ),
  route: route,
);

const progress = RouteProgress(
  maneuverIndex: 1,
  toManeuverM: 412.5,
  remainingM: 19876,
  remainingS: 845,
);

Future<(Harness, FakeRouteSource)> open(
  WidgetTester tester,
  RouteView Function(FakeRouteSource) initial, {
  PositionSource? position,
  OfflineMap? map,
}) async {
  final src = FakeRouteSource(const RouteView(link: RouteLink.connecting));
  src.value = initial(src);
  final h = await Harness.start(tester, route: src, position: position, map: map);
  await h.goTo(AppScreen.navigation);
  return (h, src);
}

void main() {
  setUpAll(loadTestAssets);

  testWidgets('idle: a hint; long-press, Route here asks for that point', (tester) async {
    final (_, src) = await open(tester, (s) => view(s, RouteState.idle, route: null));
    expect(textOf('nav-routing'), 'Long-press the map to route');
    expect(find.byKey(const ValueKey('nav-guidance')), findsNothing);

    final map = tester.getRect(find.byType(FlutterMap));
    await tester.longPressAt(map.center + const Offset(-120, 60));
    await tester.pump();
    expect(find.byKey(const ValueKey('nav-pending')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-pending-panel')), findsOneWidget);
    // The point is south-west of the truck (the map is centred on it).
    final at = tester.widget<Text>(find.byKey(const ValueKey('nav-pending-text'))).data!;
    final [lat, lon] = at.split(', ').map(double.parse).toList();
    expect(lat, lessThan(39.83));
    expect(lon, lessThan(-98.53));

    await tester.tap(find.byKey(const ValueKey('nav-route-here')));
    await tester.pump();
    expect(src.destinations, hasLength(1));
    expect(src.destinations.single.latitude, closeTo(lat, 1e-4));
    expect(find.byKey(const ValueKey('nav-pending-panel')), findsNothing);
  });

  testWidgets('Cancel drops the chosen point', (tester) async {
    final (_, src) = await open(tester, (s) => view(s, RouteState.idle, route: null));
    await tester.longPressAt(tester.getRect(find.byType(FlutterMap)).center);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('nav-route-cancel')));
    await tester.pump();
    expect(find.byKey(const ValueKey('nav-pending')), findsNothing);
    expect(src.destinations, isEmpty);
  });

  testWidgets('routing unavailable: says why, and a long-press does nothing', (tester) async {
    final h = await Harness.start(tester); // the default: UnavailableRouteSource
    await h.goTo(AppScreen.navigation);
    expect(textOf('nav-routing'), 'Routing unavailable: needs services/navigation (make sim)');
    await tester.longPressAt(tester.getRect(find.byType(FlutterMap)).center);
    await tester.pump();
    expect(find.byKey(const ValueKey('nav-pending-panel')), findsNothing);
  });

  for (final (units, toManeuver, remaining) in [
    (UnitSystem.imperial, '0.3 mi', '12.4 mi · 14 min left'),
    (UnitSystem.metric, '410 m', '19.9 km · 14 min left'),
  ]) {
    testWidgets('active: next maneuver, distances in ${units.name}, the route, the caveat', (
      tester,
    ) async {
      final (h, _) = await open(tester, (s) => view(s, RouteState.active, progress: progress));
      h.services.settings.units = units;
      await tester.pump();
      expect(find.byKey(const ValueKey('nav-guidance-active')), findsOneWidget);
      expect(textOf('nav-to-maneuver'), toManeuver);
      expect(textOf('nav-instruction'), 'Turn right onto US 36/US 281.');
      expect(textOf('nav-remaining'), remaining);
      expect(textOf('nav-heavy-warning'), 'Not checked for heavy vehicles or trailers');
      expect(find.byKey(const ValueKey('nav-route-line')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-destination')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-end-route')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-routing')), findsNothing, reason: 'the banner says it');
      expect(find.byIcon(Icons.turn_right), findsOneWidget);
    });
  }

  testWidgets('a map stick while routing is one line, below the banner\'s warning (ADR-0033)', (
    tester,
  ) async {
    // Seen on the Pi (2026-11-11): the stick's card covered "Not checked for
    // heavy vehicles or trailers".
    final answers = <String?>[
      null,
      '{"state":"current","percent":100,"message":"The routing data on this stick is already installed. '
          'You can remove the stick.","id":"c","device":"/dev/sda1","item":"routing","changed":[],'
          '"at":"${DateTime.now().toUtc().toIso8601String()}"}',
    ];
    final map = OfflineMap(
      'test/fixtures/maps/solid-z0-3.pmtiles',
      statusPath: '/run/f250-maps/status.json',
      open: openPmTilesFile,
      readStatus: (_) async => answers.isEmpty ? null : answers.removeAt(0),
    );
    await tester.runAsync(map.load);
    await tester.runAsync(map.checkUpdate);
    await open(tester, (s) => view(s, RouteState.active, progress: progress), map: map);
    await tester.runAsync(map.checkUpdate);
    await tester.pump();
    final notice = find.byKey(const ValueKey('nav-map-update'));
    expect(tester.widget<Text>(notice).maxLines, 1);
    final warning = tester.getRect(find.byKey(const ValueKey('nav-heavy-warning')));
    final line = tester.getRect(notice);
    expect(line.top, greaterThan(warning.bottom), reason: 'the warning stays visible');
    expect(line.bottom, lessThanOrEqualTo(tester.getRect(find.byKey(const ValueKey('nav-end-route'))).top));
  });

  testWidgets('guidance that stops arriving pauses: no distances, and why', (tester) async {
    final (_, src) = await open(tester, (s) => view(s, RouteState.active, progress: progress));
    expect(find.byKey(const ValueKey('nav-to-maneuver')), findsOneWidget);
    src.clock.advance(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('nav-to-maneuver')), findsNothing);
    expect(find.byKey(const ValueKey('nav-remaining')), findsNothing);
    expect(
      textOf('nav-guidance-text'),
      'Guidance paused: no update from the navigation service for 4 s',
    );
    expect(textOf('nav-heavy-warning'), isNotNull, reason: 'the route is still on screen');
  });

  testWidgets('no current position: guidance paused, whatever the service sent', (tester) async {
    final position = FakePositionSource(
      FakeMonotonicClock(),
      const PositionState(link: PositionLink.lost, detail: 'connection refused'),
    );
    await open(
      tester,
      (s) => view(s, RouteState.active, progress: progress),
      position: position,
    );
    expect(find.byKey(const ValueKey('nav-to-maneuver')), findsNothing);
    expect(textOf('nav-guidance-text'), 'Guidance paused: no current position');
  });

  testWidgets('the route line is grey unless guidance is current', (tester) async {
    final (h, src) = await open(tester, (s) => view(s, RouteState.active, progress: progress));
    Color lineColour() => tester
        .widget<PolylineLayer>(find.byKey(const ValueKey('nav-route-line')))
        .polylines
        .single
        .color;
    final live = lineColour();
    src.value = view(src, RouteState.routing, reroutes: 1);
    await tester.pump();
    expect(lineColour(), isNot(live), reason: 'the old route while finding a new one');
    expect(textOf('nav-guidance-text'), 'Off the route: finding a new one');
    expect(h.services.route, same(src));
  });

  testWidgets('finding the first route', (tester) async {
    await open(tester, (s) => view(s, RouteState.routing, route: null));
    expect(textOf('nav-guidance-text'), 'Finding a route…');
    expect(find.byKey(const ValueKey('nav-route-line')), findsNothing);
    expect(find.byKey(const ValueKey('nav-destination')), findsOneWidget);
    expect(textOf('nav-heavy-warning'), isNotNull);
  });

  testWidgets('waiting for a position to route from says so', (tester) async {
    await open(
      tester,
      (s) => view(
        s,
        RouteState.routing,
        route: null,
        detail: 'Waiting for a current position to route from',
      ),
    );
    expect(textOf('nav-guidance-text'), 'Waiting for a current position to route from');
  });

  testWidgets('failed: the reason, Retry asks again, End route clears', (tester) async {
    final (_, src) = await open(
      tester,
      (s) => view(s, RouteState.failed, route: null, detail: 'no road near the destination'),
    );
    expect(textOf('nav-guidance-text'), 'No route: no road near the destination');
    await tester.tap(find.byKey(const ValueKey('nav-retry')));
    await tester.pump();
    expect(src.destinations, [destination]);
    await tester.tap(find.byKey(const ValueKey('nav-end-route')));
    await tester.pump();
    expect(src.clears, 1);
  });

  testWidgets('arrived, with End route', (tester) async {
    await open(tester, (s) => view(s, RouteState.arrived));
    expect(textOf('nav-guidance-text'), 'Arrived');
    expect(find.byKey(const ValueKey('nav-end-route')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-retry')), findsNothing);
  });

  testWidgets('a failed command shows', (tester) async {
    final (_, src) = await open(tester, (s) => view(s, RouteState.idle, route: null));
    src.value = src.state.value.copyWith(commandError: "Couldn't set the destination: unavailable");
    await tester.pump();
    expect(textOf('nav-route-error'), "Couldn't set the destination: unavailable");
  });

  testWidgets('the navigation service down before any guidance', (tester) async {
    await open(tester, (s) => const RouteView(link: RouteLink.lost, detail: 'connection refused'));
    expect(
      textOf('nav-routing'),
      'Routing unavailable: navigation service unavailable: connection refused',
    );
  });
}
