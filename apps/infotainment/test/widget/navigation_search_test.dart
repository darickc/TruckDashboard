import 'package:f250_infotainment/core/clock.dart';
import 'package:f250_infotainment/nav/position_state.dart';
import 'package:f250_infotainment/nav/route_state.dart';
import 'package:f250_infotainment/nav/search_state.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/theme.dart';
import 'package:f250_infotainment/ui/widgets/tap_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../harness.dart';
import 'navigation_route_test.dart' show FakeRouteSource, view;
import 'navigation_screen_test.dart' show FakePositionSource, textOf;

/// Answers from a table, recording every query, as services/navigation
/// would answer them.
class FakeSearchSource implements SearchSource {
  FakeSearchSource(this.answers, {this.available = true, this.detail = ''});

  final Map<String, List<SearchResult>> answers;
  final bool available;
  final String detail;
  final queries = <String>[];

  @override
  void start() {}
  @override
  void stop() {}

  @override
  Future<SearchAnswer> search(String query, {int limit = 8}) async {
    queries.add(query);
    return SearchAnswer(
      query: query,
      available: available,
      detail: detail,
      results: answers[query.trim()] ?? const [],
      regions: const ['Testland'],
      dataDate: '2026-11-11',
      rankedFrom: RankedFrom.current,
    );
  }
}

const mainStreet = SearchResult(
  kind: SearchMatch.street,
  title: 'North Main Street',
  subtitle: 'near Fairview',
  location: LatLng(39.84, -98.54),
  distanceM: 1500,
  houseNumberMissing: true,
);

const address = SearchResult(
  kind: SearchMatch.address,
  title: '120 North Main Street',
  subtitle: 'Fairview',
  location: LatLng(39.841, -98.541),
  distanceM: 1600,
);

const fairview = SearchResult(
  kind: SearchMatch.locality,
  title: 'Fairview',
  subtitle: 'Town',
  location: LatLng(39.85, -98.55),
  distanceM: 2500,
  unmatchedWords: ['elm', 'avenue'],
);

final answers = {
  '125 main': [mainStreet],
  '120 main': [address, mainStreet],
  'elm avenue fairview': [fairview],
};

Future<(Harness, FakeRouteSource, FakeSearchSource)> open(
  WidgetTester tester, {
  FakeSearchSource? search,
  RouteState routeState = RouteState.idle,
  PositionSource? position,
  String scenario = 'drive_cycle',
  Duration run = Duration.zero,
}) async {
  final route = FakeRouteSource(const RouteView(link: RouteLink.connecting));
  route.value = view(route, routeState, route: null);
  final s = search ?? FakeSearchSource(answers);
  final h = await Harness.start(tester, route: route, search: s, position: position, scenario: scenario);
  if (run > Duration.zero) await h.advance(run);
  await h.goTo(AppScreen.navigation);
  return (h, route, s);
}

Future<void> type(WidgetTester tester, String text) async {
  for (final c in text.split('')) {
    final key = switch (c) {
      ' ' => 'osk-space',
      _ => 'osk-key-$c',
    };
    if (RegExp(r'\d').hasMatch(c) && find.byKey(ValueKey(key)).evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('osk-layer')));
      await tester.pump();
    } else if (RegExp('[a-z]').hasMatch(c) && find.byKey(ValueKey(key)).evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('osk-layer')));
      await tester.pump();
    }
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
  }
  // Past the debounce, and the answer's microtask.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump();
}

Future<void> openSearch(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nav-search-open')));
  await tester.pump();
}

void main() {
  setUpAll(loadTestAssets);

  testWidgets('type on the keyboard; a street only is labelled so; Route here routes', (tester) async {
    final (_, route, search) = await open(tester);
    await openSearch(tester);
    expect(find.byKey(const ValueKey('osk')), findsOneWidget);
    expect(textOf('nav-search-hint'), contains('Type an address'));

    await type(tester, '125 main');
    expect(textOf('nav-search-text'), '125 main');
    // One search after typing stops, not one per key.
    expect(search.queries, ['125 main']);

    await tester.tap(find.byKey(const ValueKey('osk-done')));
    await tester.pump();
    expect(find.byKey(const ValueKey('osk')), findsNothing);
    final row = find.byKey(const ValueKey('nav-search-result-North Main Street|near Fairview'));
    expect(row, findsOneWidget);
    expect(textOf('nav-search-note'), 'Street only: no house number 125 in the map data');
    expect(textOf('nav-search-footer'), contains('Testland · OpenStreetMap 2026-11-11'));
    expect(textOf('nav-search-footer'), contains('House numbers are sparse outside towns'));

    await tester.tap(find.descendant(of: row, matching: find.byKey(const ValueKey('nav-search-route'))));
    await tester.pump();
    expect(route.destinations, [mainStreet.location]);
    expect(find.byKey(const ValueKey('nav-search')), findsNothing);
  });

  testWidgets('an address comes back as one, with no note', (tester) async {
    await open(tester);
    await openSearch(tester);
    await type(tester, '120 main');
    final row = find.byKey(const ValueKey('nav-search-result-120 North Main Street|Fairview'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.byKey(const ValueKey('nav-search-note'))), findsNothing);
    expect(textOf('nav-search-result-120 North Main Street|Fairview'), contains('ADDRESS · Fairview · 1.0 mi away'));
  });

  testWidgets('a town found for a street that is not there says so', (tester) async {
    await open(tester);
    await openSearch(tester);
    await type(tester, 'elm avenue fairview');
    expect(textOf('nav-search-note'), 'Town only: “elm avenue” not found');
  });

  testWidgets('Show puts a result on the map with its name, then Route here', (tester) async {
    final (_, route, _) = await open(tester);
    await openSearch(tester);
    await type(tester, '120 main');
    await tester.tap(find.byKey(const ValueKey('osk-done')));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('nav-search-result-120 North Main Street|Fairview')),
        matching: find.byKey(const ValueKey('nav-search-show')),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('nav-search')), findsNothing);
    expect(textOf('nav-pending-text'), '120 North Main Street');
    expect(find.byKey(const ValueKey('nav-pending')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-route-here')));
    await tester.pump();
    expect(route.destinations, [address.location]);
  });

  testWidgets('the query is kept when search is closed and opened again', (tester) async {
    final (_, _, search) = await open(tester);
    await openSearch(tester);
    await type(tester, '120 main');
    await tester.tap(find.byKey(const ValueKey('nav-search-close')));
    await tester.pump();
    expect(find.byKey(const ValueKey('nav-search')), findsNothing);
    await openSearch(tester);
    await tester.pump();
    expect(textOf('nav-search-text'), '120 main');
    expect(search.queries.last, '120 main');
    await tester.tap(find.byKey(const ValueKey('nav-search-clear')));
    await tester.pump();
    expect(textOf('nav-search-text'), 'Address, street, town or place');
    await tester.tap(find.byKey(const ValueKey('osk-backspace')));
    await tester.pump();
  });

  testWidgets('nothing found, and no search data, are said', (tester) async {
    await open(tester);
    await openSearch(tester);
    await type(tester, 'zzz');
    expect(textOf('nav-search-none'), 'Nothing found for “zzz” in Testland');
  });

  testWidgets('without search data the panel says why', (tester) async {
    await open(
      tester,
      search: FakeSearchSource(
        answers,
        available: false,
        detail: 'no search data at /var/lib/f250/storage/search/search.sqlite',
      ),
    );
    await openSearch(tester);
    await type(tester, 'main');
    expect(
      textOf('nav-search-unavailable'),
      'Search unavailable: no search data at /var/lib/f250/storage/search/search.sqlite',
    );
  });

  testWidgets('moving: a warning, but typing still works (owner decision)', (tester) async {
    // The harness's simulated receiver drives at 80 km/h.
    final (_, _, search) = await open(tester);
    await openSearch(tester);
    expect(textOf('nav-search-moving'), 'The truck is moving: type only when parked');
    await type(tester, '125 main');
    expect(search.queries, ['125 main']);
  });

  testWidgets('parked: no warning', (tester) async {
    final clock = FakeMonotonicClock();
    final parked = FakePositionSource(
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
    await open(tester, position: parked);
    await openSearch(tester);
    expect(find.byKey(const ValueKey('nav-search-moving')), findsNothing);
  });

  testWidgets('routing unavailable: no Route here, Show still works', (tester) async {
    await open(tester, routeState: RouteState.unavailable);
    await openSearch(tester);
    await type(tester, '120 main');
    await tester.tap(find.byKey(const ValueKey('osk-done')));
    await tester.pump();
    expect(find.byKey(const ValueKey('nav-search-route')), findsNothing);
    expect(find.byKey(const ValueKey('nav-search-show')), findsWidgets);
    expect(textOf('nav-search-footer'), contains('Routing is unavailable'));
  });

  for (final alert in [false, true]) {
    testWidgets('800×480: keys and buttons are 60 px, nothing overflows${alert ? ', under an alert' : ''}', (
      tester,
    ) async {
      await open(
        tester,
        scenario: alert ? 'link_loss' : 'drive_cycle',
        run: alert ? const Duration(seconds: 100) : Duration.zero,
      );
      expect(find.byKey(const ValueKey('alert-banner')), alert ? findsOneWidget : findsNothing);
      await openSearch(tester);
      await type(tester, '120 main');
      void check(String where) {
        expect(tester.takeException(), isNull, reason: where);
        final targets = find.descendant(of: find.byKey(const ValueKey('nav-search')), matching: find.byType(TapTarget));
        expect(targets, findsWidgets);
        for (final e in targets.evaluate()) {
          final size = (e.renderObject! as RenderBox).size;
          expect(size.width, greaterThanOrEqualTo(kMinTouch - 0.01), reason: '$where ${(e.widget as TapTarget).label}');
          expect(
            size.height,
            greaterThanOrEqualTo(kMinTouch - 0.01),
            reason: '$where ${(e.widget as TapTarget).label}',
          );
        }
        // The keyboard fits on screen.
        final osk = find.byKey(const ValueKey('osk'));
        if (osk.evaluate().isNotEmpty) {
          expect(tester.getRect(osk).bottom, lessThanOrEqualTo(480));
        }
      }

      check('keyboard');
      await tester.tap(find.byKey(const ValueKey('osk-layer')));
      await tester.pump();
      check('digits');
      await tester.tap(find.byKey(const ValueKey('osk-done')));
      await tester.pump();
      check('results');
    });
  }
}
