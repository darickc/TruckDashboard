import 'package:f250_infotainment/core/clock.dart';
import 'package:f250_infotainment/nav/places_state.dart';
import 'package:f250_infotainment/nav/position_state.dart';
import 'package:f250_infotainment/nav/route_state.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/theme.dart';
import 'package:f250_infotainment/ui/widgets/tap_target.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../harness.dart';
import 'navigation_route_test.dart' show FakeRouteSource, destination, progress, route7, view;
import 'navigation_screen_test.dart' show FakePositionSource, textOf;
import 'navigation_search_test.dart' show FakeSearchSource, address, answers, type;

/// Saved places kept in memory, as services/navigation would keep them;
/// records every change and can be told to refuse.
class FakePlacesSource implements PlacesSource {
  FakePlacesSource(PlacesView initial) : _state = ValueNotifier(initial);

  final ValueNotifier<PlacesView> _state;
  final calls = <String>[];
  var refreshes = 0;

  /// The next change fails with this, once.
  String? refuse;
  var _nextId = 100;

  @override
  ValueListenable<PlacesView> get state => _state;
  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<void> refresh() async => refreshes++;

  PlacesView get v => _state.value;

  PlacesView _copy({Place? home, bool dropHome = false, List<Place>? favourites, List<Place>? recents}) => PlacesView(
    link: v.link,
    home: dropHome ? null : (home ?? v.home),
    favourites: favourites ?? v.favourites,
    recents: recents ?? v.recents,
    writable: v.writable,
    location: v.location,
    problem: v.problem,
  );

  String? _refused() {
    final r = refuse;
    refuse = null;
    return r;
  }

  @override
  Future<String?> save(PlaceKind kind, String name, LatLng at, {String detail = ''}) async {
    calls.add('save ${kind.name} "$name" "$detail" ${at.latitude},${at.longitude}');
    if (_refused() case final r?) return r;
    final p = Place(id: _nextId++, kind: kind, name: name, detail: detail, location: at);
    _state.value = kind == PlaceKind.home ? _copy(home: p) : _copy(favourites: [...v.favourites, p]);
    return null;
  }

  @override
  Future<String?> rename(int id, String name) async {
    calls.add('rename $id "$name"');
    if (_refused() case final r?) return r;
    Place re(Place p) =>
        p.id == id ? Place(id: id, kind: p.kind, name: name, detail: p.detail, location: p.location) : p;
    _state.value = _copy(
      home: v.home == null ? null : re(v.home!),
      favourites: v.favourites.map(re).toList(),
      recents: v.recents.map(re).toList(),
    );
    return null;
  }

  @override
  Future<String?> delete(int id) async {
    calls.add('delete $id');
    if (_refused() case final r?) return r;
    _state.value = _copy(
      dropHome: v.home?.id == id,
      favourites: v.favourites.where((p) => p.id != id).toList(),
      recents: v.recents.where((p) => p.id != id).toList(),
    );
    return null;
  }
}

const home = Place(id: 1, kind: PlaceKind.home, name: 'Home', detail: 'Fairview', location: LatLng(39.84, -98.54));
const feed = Place(
  id: 2,
  kind: PlaceKind.favourite,
  name: 'Feed store',
  detail: 'Hiawatha',
  location: LatLng(39.85, -95.53),
);
const casey = Place(id: 3, kind: PlaceKind.recent, name: "Casey's", location: LatLng(39.83, -98.53));
const pin = Place(id: 4, kind: PlaceKind.recent, name: '', location: LatLng(39.81, -98.5));

PlacesView saved({String problem = ''}) => PlacesView(
  link: PlacesLink.connected,
  home: home,
  favourites: const [feed],
  recents: const [casey, pin],
  writable: true,
  location: 'the data drive',
  problem: problem,
);

/// A current fix with the truck stopped: no moving warning.
FakePositionSource parked() {
  final clock = FakeMonotonicClock();
  return FakePositionSource(
    clock,
    PositionState(
      link: PositionLink.connected,
      report: PositionReport(
        status: FixStatus.fix3d,
        receivedAt: clock.now(),
        current: true,
        staleAfter: const Duration(seconds: 3),
        fix: const FixReport(lat: 39.83, lon: -98.53, ageAtReceipt: Duration.zero, speedMps: 0),
      ),
    ),
  );
}

Future<(Harness, FakeRouteSource, FakePlacesSource)> open(
  WidgetTester tester, {
  PlacesView? places,
  RouteView Function(FakeRouteSource)? route,
  PositionSource? position,
  FakeSearchSource? search,
  String scenario = 'drive_cycle',
  Duration run = Duration.zero,
}) async {
  final r = FakeRouteSource(const RouteView(link: RouteLink.connecting));
  r.value = (route ?? (s) => view(s, RouteState.idle, route: null))(r);
  final p = FakePlacesSource(places ?? saved());
  final h = await Harness.start(
    tester,
    route: r,
    places: p,
    position: position ?? parked(),
    search: search,
    scenario: scenario,
  );
  if (run > Duration.zero) await h.advance(run);
  await h.goTo(AppScreen.navigation);
  return (h, r, p);
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump();
}

/// Scrolls the places list until [key] is built and on screen.
Future<void> reveal(WidgetTester tester, String key) => tester.scrollUntilVisible(
  find.byKey(ValueKey(key)),
  80,
  scrollable: find.descendant(of: find.byKey(const ValueKey('nav-places-list')), matching: find.byType(Scrollable)),
);

Finder inRow(int id, String key) =>
    find.descendant(of: find.byKey(ValueKey('nav-place-$id')), matching: find.byKey(ValueKey(key)));

String? nameText() => textOf('nav-place-name');

void main() {
  setUpAll(loadTestAssets);

  testWidgets('Places lists Home, favourites and recents; Route here routes in one tap', (tester) async {
    final (_, route, places) = await open(tester);
    await tapKey(tester, 'nav-places-open');
    expect(find.byKey(const ValueKey('nav-places')), findsOneWidget);
    expect(places.refreshes, 1, reason: 'asked again on opening: routes add recents');
    for (final id in [1, 2, 3, 4]) {
      expect(find.byKey(ValueKey('nav-place-$id')), findsOneWidget);
    }
    expect(
      find.descendant(of: find.byKey(const ValueKey('nav-place-4')), matching: find.text('Dropped pin')),
      findsOneWidget,
      reason: 'an unnamed recent is a dropped pin',
    );
    expect(find.text('39.8100, -98.5000'), findsOneWidget, reason: 'with where it is underneath');
    await reveal(tester, 'nav-places-footer');
    expect(textOf('nav-places-footer'), 'Kept on the data drive.');

    await tester.tap(inRow(2, 'nav-place-route'));
    await tester.pump();
    expect(route.destinations, [feed.location]);
    expect(route.names, ['Feed store'], reason: 'named, so it shows with the route and in recents');
    expect(find.byKey(const ValueKey('nav-places')), findsNothing, reason: 'back to the map');
  });

  String? inRowText(int id, String key) => (find
      .descendant(of: find.byKey(ValueKey('nav-place-$id')), matching: find.byKey(ValueKey(key)))
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .firstOrNull);

  testWidgets('each place shows its straight-line distance and direction from the truck', (tester) async {
    await open(tester);
    await tapKey(tester, 'nav-places-open');
    expect(textOf('nav-places-distances'), 'Distances in a straight line from the truck');
    // Parked at 39.83, -98.53: Home is about 1.4 km north-west.
    expect(inRowText(1, 'nav-place-distance'), '0.9 mi');
    expect(inRowText(1, 'nav-place-direction'), 'NW');
    // The feed store is about 256 km east: whole miles from 10 up.
    expect(inRowText(2, 'nav-place-distance'), matches(RegExp(r'^1[56]\d mi$')));
    expect(inRowText(2, 'nav-place-direction'), 'E');
    // Casey's is where the truck is.
    expect(inRowText(3, 'nav-place-direction'), 'here');
    expect(find.text('RECENT · 2'), findsOneWidget);
  });

  testWidgets('no current position: a dash, never a distance from an old fix', (tester) async {
    final clock = FakeMonotonicClock();
    final position = FakePositionSource(
      clock,
      PositionState(
        link: PositionLink.lost,
        detail: 'navigation stopped',
        report: PositionReport(
          status: FixStatus.fix3d,
          receivedAt: clock.now(),
          current: true,
          staleAfter: const Duration(seconds: 3),
          fix: const FixReport(lat: 39.83, lon: -98.53, ageAtReceipt: Duration.zero, speedMps: 0),
        ),
      ),
    );
    await open(tester, position: position);
    await tapKey(tester, 'nav-places-open');
    expect(textOf('nav-places-distances'), 'No current position: no distances');
    for (final id in [1, 2, 3, 4]) {
      expect(inRowText(id, 'nav-place-distance'), '—', reason: 'place $id');
      expect(inRowText(id, 'nav-place-direction'), isNull, reason: 'place $id');
    }
  });

  testWidgets('a fix that goes stale with the list open turns the distances to dashes', (tester) async {
    final position = parked();
    await open(tester, position: position);
    await tapKey(tester, 'nav-places-open');
    expect(inRowText(1, 'nav-place-distance'), '0.9 mi');
    (position.clock as FakeMonotonicClock).advance(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    expect(textOf('nav-places-distances'), 'No current position: no distances');
    expect(inRowText(1, 'nav-place-distance'), '—');
  });

  testWidgets('Route is the one filled button on a row; Home sits on a tinted card', (tester) async {
    await open(tester);
    await tapKey(tester, 'nav-places-open');
    final route = tester.widget<TapTarget>(inRow(2, 'nav-place-route'));
    expect(route.fill, isNotNull);
    expect(route.label, 'Route here: Feed store');
    expect(tester.widget<TapTarget>(inRow(2, 'nav-place-edit')).fill, isNull);
    expect(tester.widget<TapTarget>(inRow(4, 'nav-place-route')).label, 'Route here: Dropped pin');
    final home = tester.widget<Container>(find.byKey(const ValueKey('nav-place-1')));
    expect((home.decoration! as BoxDecoration).color, isNotNull);
    final feedRow = tester.widget<Container>(find.byKey(const ValueKey('nav-place-2')));
    expect((feedRow.decoration! as BoxDecoration).color, isNull);
  });

  testWidgets('delete in two taps: Edit, Delete', (tester) async {
    final (_, _, places) = await open(tester);
    await tapKey(tester, 'nav-places-open');
    await tester.tap(inRow(3, 'nav-place-edit'));
    await tester.pump();
    expect(find.byKey(const ValueKey('nav-place-editor')), findsOneWidget);
    expect(nameText(), "Casey's");
    await tapKey(tester, 'nav-place-delete');
    expect(places.calls, ['delete 3']);
    expect(find.byKey(const ValueKey('nav-place-editor')), findsNothing);
    expect(find.byKey(const ValueKey('nav-place-3')), findsNothing);
    expect(find.byKey(const ValueKey('nav-places')), findsOneWidget, reason: 'back to the list');
  });

  testWidgets('rename a favourite on the keyboard', (tester) async {
    final (_, _, places) = await open(tester);
    await tapKey(tester, 'nav-places-open');
    await tester.tap(inRow(2, 'nav-place-edit'));
    await tester.pump();
    expect(find.byKey(const ValueKey('nav-place-home')), findsNothing, reason: 'rename or delete only');
    for (var i = 0; i < 'Feed store'.length; i++) {
      await tapKey(tester, 'osk-backspace');
    }
    expect(nameText(), 'Name');
    await type(tester, 'coop');
    await tapKey(tester, 'nav-place-save');
    expect(places.calls, ['rename 2 "coop"']);
    expect(find.byKey(const ValueKey('nav-place-editor')), findsNothing);
  });

  testWidgets('a recent destination becomes a favourite or Home', (tester) async {
    final (_, _, places) = await open(tester);
    await tapKey(tester, 'nav-places-open');
    await tester.tap(inRow(3, 'nav-place-edit'));
    await tester.pump();
    await tapKey(tester, 'nav-place-save');
    expect(places.calls, ['save favourite "Casey\'s" "" 39.83,-98.53']);
    await reveal(tester, 'nav-place-4');
    await tester.tap(inRow(4, 'nav-place-edit'));
    await tester.pump();
    await tapKey(tester, 'nav-place-home');
    expect(places.calls.last, 'save home "Home" "" 39.81,-98.5');
  });

  testWidgets('save a long-pressed point: a favourite needs a name', (tester) async {
    final (_, route, places) = await open(tester, places: const PlacesView(link: PlacesLink.connected, writable: true));
    await tester.longPressAt(tester.getRect(find.byType(FlutterMap)).center + const Offset(-60, -40));
    await tester.pump();
    await tapKey(tester, 'nav-pending-save');
    expect(find.byKey(const ValueKey('nav-place-editor')), findsOneWidget);
    expect(find.byKey(const ValueKey('osk')), findsOneWidget, reason: 'ready to type a name');
    await tapKey(tester, 'nav-place-save');
    expect(places.calls, isEmpty, reason: 'no name yet');
    expect(nameText(), 'Type a name first');
    await type(tester, 'gate');
    await tapKey(tester, 'nav-place-save');
    expect(places.calls.single, startsWith('save favourite "gate" ""'));
    expect(find.byKey(const ValueKey('nav-place-editor')), findsNothing);
    expect(find.byKey(const ValueKey('nav-pending-panel')), findsOneWidget, reason: 'the point stays, to route to');
    expect(route.destinations, isEmpty);
  });

  testWidgets('save a search result: named after it, Home in one tap', (tester) async {
    final (_, _, places) = await open(tester, search: FakeSearchSource(answers));
    await tapKey(tester, 'nav-search-open');
    await type(tester, '120 main');
    await tapKey(tester, 'osk-done');
    final row = find.byKey(const ValueKey('nav-search-result-120 North Main Street|Fairview'));
    await tester.tap(find.descendant(of: row, matching: find.byKey(const ValueKey('nav-search-save'))));
    await tester.pump();
    expect(nameText(), '120 North Main Street');
    await tapKey(tester, 'nav-place-home');
    expect(places.calls, ['save home "Home" "Fairview" ${address.location.latitude},${address.location.longitude}']);
    expect(find.byKey(const ValueKey('nav-search')), findsOneWidget, reason: 'back to the results');
  });

  testWidgets('save the route\'s destination, named as it was routed', (tester) async {
    final (_, _, places) = await open(
      tester,
      route: (s) => RouteView(
        link: RouteLink.connected,
        guidance: Guidance(
          state: RouteState.active,
          receivedAt: s.clock.now(),
          routeId: 7,
          destination: destination,
          progress: progress,
          destinationName: 'Grain elevator',
          voice: const VoiceState(audible: true),
        ),
        route: route7,
      ),
    );
    await tapKey(tester, 'nav-save-destination');
    expect(nameText(), 'Grain elevator');
    await tapKey(tester, 'nav-place-save');
    expect(places.calls.single, 'save favourite "Grain elevator" "" ${destination.latitude},${destination.longitude}');
  });

  testWidgets('a refused change says why, with the keyboard out of the way', (tester) async {
    final (_, _, places) = await open(tester);
    places.refuse = '50 favourites already: delete one first';
    await tapKey(tester, 'nav-places-open');
    await tester.tap(inRow(3, 'nav-place-edit'));
    await tester.pump();
    await tapKey(tester, 'nav-place-save');
    expect(textOf('nav-place-error'), 'Not saved: 50 favourites already: delete one first');
    expect(find.byKey(const ValueKey('osk')), findsNothing);
    expect(find.byKey(const ValueKey('nav-place-editor')), findsOneWidget, reason: 'still open, to try again');
    await tapKey(tester, 'nav-place-cancel');
    expect(find.byKey(const ValueKey('nav-place-editor')), findsNothing);
  });

  testWidgets('naming while moving: a warning, typing still works (owner decision)', (tester) async {
    // The harness's simulated receiver drives at 80 km/h.
    final h = await Harness.start(tester, places: FakePlacesSource(saved()));
    await h.goTo(AppScreen.navigation);
    await tapKey(tester, 'nav-places-open');
    await tester.tap(inRow(2, 'nav-place-edit'));
    await tester.pump();
    expect(textOf('nav-place-moving'), 'The truck is moving: type only when parked');
    await type(tester, 's');
    expect(nameText(), 'Feed stores');
  });

  testWidgets('a problem with the file is the first thing in the list', (tester) async {
    await open(tester, places: saved(problem: 'The saved places file was unreadable (not JSON); it was kept as places.json.bad'));
    await tapKey(tester, 'nav-places-open');
    expect(textOf('nav-places-problem'), contains('places.json.bad'));
    final problem = tester.getRect(find.byKey(const ValueKey('nav-places-problem')));
    expect(problem.top, lessThan(tester.getRect(find.byKey(const ValueKey('nav-place-1'))).top));
  });

  testWidgets('without the navigation service: unavailable, and why', (tester) async {
    final h = await Harness.start(tester); // the default: UnavailablePlacesSource
    await h.goTo(AppScreen.navigation);
    await tapKey(tester, 'nav-places-open');
    expect(textOf('nav-places-unavailable'), 'Saved places unavailable: needs services/navigation (make sim)');
  });

  testWidgets('empty: says how to add them; no Route here without routing', (tester) async {
    await open(
      tester,
      places: const PlacesView(link: PlacesLink.connected, writable: true, location: 'the SD card: the data drive isn\'t mounted'),
      route: (s) => view(s, RouteState.unavailable, route: null),
    );
    await tapKey(tester, 'nav-places-open');
    expect(find.byKey(const ValueKey('nav-places-no-home')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-places-no-favourites')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-places-no-recents')), findsOneWidget);
    await reveal(tester, 'nav-places-footer');
    expect(textOf('nav-places-footer'), contains('the SD card'));
    expect(textOf('nav-places-footer'), contains('Routing is unavailable'));
  });

  group('the voice toggle', () {
    RouteView Function(FakeRouteSource) withVoice(VoiceState? voice) => (s) => RouteView(
      link: RouteLink.connected,
      guidance: Guidance(
        state: RouteState.active,
        receivedAt: s.clock.now(),
        routeId: 7,
        destination: destination,
        progress: progress,
        voice: voice,
      ),
      route: route7,
    );

    testWidgets('on: one tap mutes; muted: one tap unmutes', (tester) async {
      final (_, route, _) = await open(tester, route: withVoice(const VoiceState(audible: true, detail: 'say')));
      final button = find.byKey(const ValueKey('nav-voice'));
      expect(tester.widget<TapTarget>(button).label, 'Voice');
      await tapKey(tester, 'nav-voice');
      expect(route.mutes, [true]);
      route.value = withVoice(const VoiceState(muted: true, audible: true))(route);
      await tester.pump();
      expect(tester.widget<TapTarget>(button).label, 'Muted');
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
      await tapKey(tester, 'nav-voice');
      expect(route.mutes, [true, false]);
    });

    testWidgets('prompts that only reach the log say so', (tester) async {
      await open(tester, route: withVoice(const VoiceState(detail: 'the log only: no speech output configured')));
      expect(tester.widget<TapTarget>(find.byKey(const ValueKey('nav-voice'))).label, 'No audio');
    });

    testWidgets('a service without spoken directions: no toggle', (tester) async {
      await open(tester, route: withVoice(null));
      expect(find.byKey(const ValueKey('nav-voice')), findsNothing);
      expect(find.byKey(const ValueKey('nav-end-route')), findsOneWidget);
    });
  });

  for (final alert in [false, true]) {
    testWidgets('800×480: 60 px targets, nothing overflows, the alert stays${alert ? ', under an alert' : ''}', (
      tester,
    ) async {
      await open(
        tester,
        scenario: alert ? 'link_loss' : 'drive_cycle',
        run: alert ? const Duration(seconds: 100) : Duration.zero,
        route: (s) => RouteView(
          link: RouteLink.connected,
          guidance: Guidance(
            state: RouteState.failed,
            receivedAt: s.clock.now(),
            routeId: 7,
            destination: destination,
            detail: 'no road near the destination',
            destinationName: 'Grain elevator',
            voice: const VoiceState(audible: false, detail: 'the log only'),
          ),
          route: route7,
        ),
      );
      final banner = find.byKey(const ValueKey('alert-banner'));
      expect(banner, alert ? findsOneWidget : findsNothing);
      void check(String where, Finder within) {
        expect(tester.takeException(), isNull, reason: where);
        final targets = find.descendant(of: within, matching: find.byType(TapTarget));
        expect(targets, findsWidgets, reason: where);
        for (final e in targets.evaluate()) {
          final size = (e.renderObject! as RenderBox).size;
          final label = (e.widget as TapTarget).label;
          expect(size.width, greaterThanOrEqualTo(kMinTouch - 0.01), reason: '$where $label');
          expect(size.height, greaterThanOrEqualTo(kMinTouch - 0.01), reason: '$where $label');
          expect(tester.getRect(find.byWidget(e.widget)).bottom, lessThanOrEqualTo(480.01), reason: '$where $label');
        }
        if (alert) expect(tester.getRect(banner).top, greaterThanOrEqualTo(0), reason: '$where: the alert shows');
      }

      // The route's row: Retry, Save, the voice, End route, side by side.
      final row = find.ancestor(of: find.byKey(const ValueKey('nav-end-route')), matching: find.byType(Row)).first;
      check('route row', row);
      expect(find.byKey(const ValueKey('nav-heavy-warning')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-retry')), findsOneWidget);
      await tapKey(tester, 'nav-save-destination');
      check('editor', find.byKey(const ValueKey('nav-place-editor')));
      expect(tester.getRect(find.byKey(const ValueKey('osk'))).bottom, lessThanOrEqualTo(480));
      await tapKey(tester, 'osk-layer');
      check('editor digits', find.byKey(const ValueKey('nav-place-editor')));
      await tapKey(tester, 'nav-place-cancel');
      expect(find.byKey(const ValueKey('nav-place-editor')), findsNothing);
    });
  }

  for (final alert in [false, true]) {
    testWidgets('800×480: the places list and the editor fit${alert ? ', under an alert' : ''}', (tester) async {
      await open(
        tester,
        scenario: alert ? 'link_loss' : 'drive_cycle',
        run: alert ? const Duration(seconds: 100) : Duration.zero,
      );
      expect(find.byKey(const ValueKey('alert-banner')), alert ? findsOneWidget : findsNothing);
      await tapKey(tester, 'nav-places-open');
      void check(String where) {
        expect(tester.takeException(), isNull, reason: where);
        for (final e in find.byType(TapTarget).hitTestable().evaluate()) {
          final size = (e.renderObject! as RenderBox).size;
          final label = (e.widget as TapTarget).label;
          expect(size.width, greaterThanOrEqualTo(kMinTouch - 0.01), reason: '$where $label');
          expect(size.height, greaterThanOrEqualTo(kMinTouch - 0.01), reason: '$where $label');
        }
        if (alert) expect(find.byKey(const ValueKey('alert-banner')).hitTestable(), findsOneWidget, reason: where);
      }

      check('list');
      expect(find.byKey(const ValueKey('nav-place-1')).hitTestable(), findsOneWidget, reason: 'Home is on screen');
      await tester.tap(inRow(2, 'nav-place-edit'));
      await tester.pump();
      check('editor');
      expect(tester.getRect(find.byKey(const ValueKey('osk'))).bottom, lessThanOrEqualTo(480));
      expect(find.byKey(const ValueKey('nav-place-delete')).hitTestable(), findsOneWidget);
    });
  }
}
