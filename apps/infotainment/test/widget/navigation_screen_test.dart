import 'package:f250_infotainment/core/clock.dart';
import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/nav/offline_map.dart';
import 'package:f250_infotainment/nav/pmtiles.dart';
import 'package:f250_infotainment/nav/pmtiles_file.dart';
import 'package:f250_infotainment/nav/position_state.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../harness.dart';

/// A position source the test sets by hand.
class FakePositionSource implements PositionSource {
  FakePositionSource(this.clock, PositionState initial) : _status = ValueNotifier(initial);

  @override
  final MonotonicClock clock;
  final ValueNotifier<PositionState> _status;

  @override
  ValueListenable<PositionState> get status => _status;
  set value(PositionState s) => _status.value = s;

  @override
  void start() {}
  @override
  void stop() {}
}

PositionReport report(
  Duration at, {
  FixStatus status = FixStatus.fix3d,
  bool current = true,
  bool withFix = true,
  bool simulated = false,
  String detail = '',
}) => PositionReport(
  status: status,
  receivedAt: at,
  current: current,
  staleAfter: const Duration(seconds: 3),
  fix: withFix
      ? const FixReport(
          lat: 39.83,
          lon: -98.53,
          ageAtReceipt: Duration.zero,
          speedMps: 20,
          trackDeg: 90,
          errorM: 6,
        )
      : null,
  satellitesUsed: 9,
  source: 'gpsd 3.27.5: /dev/ttyACM0',
  simulated: simulated,
  detail: detail,
);

String? textOf(String key) {
  final f = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(Text),
    matchRoot: true,
  );
  if (f.evaluate().isEmpty) return null;
  return f.evaluate().map((e) => (e.widget as Text).data).join(' | ');
}

void main() {
  setUpAll(loadTestAssets);

  testWidgets('the simulated receiver: a current 3D fix, labelled simulated', (tester) async {
    final h = await Harness.start(tester);
    await h.goTo(AppTab.navigation);
    expect(
      textOf('nav-status'),
      allOf(contains('3D FIX'), contains('SIMULATED'), contains('9 SATS')),
    );
    expect(find.byKey(const ValueKey('nav-marker-current')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-why')), findsNothing);
    expect(textOf('nav-map-problem'), contains('no offline map configured'));
    expect(textOf('nav-routing'), 'Routing: not implemented yet (6.5.2)');
  });

  testWidgets('a fix that stops updating becomes "last known", with its age', (tester) async {
    final h = await Harness.start(tester);
    await h.goTo(AppTab.navigation);
    expect(find.byKey(const ValueKey('nav-marker-current')), findsOneWidget);
    // No step: the simulated receiver says nothing for 4 s.
    h.clock.advance(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    expect(textOf('nav-status'), contains('LAST KNOWN · 4 S AGO'));
    expect(textOf('nav-status'), isNot(contains('3D FIX')));
    expect(find.byKey(const ValueKey('nav-marker-stale')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-marker-current')), findsNothing);
    expect(textOf('nav-why'), contains('No update from the navigation service'));
  });

  testWidgets('no fix from navigation: its reason, and the last fix grey', (tester) async {
    final clock = FakeMonotonicClock(const Duration(seconds: 50));
    final src = FakePositionSource(
      clock,
      PositionState(
        link: PositionLink.connected,
        report: PositionReport(
          status: FixStatus.noFix,
          receivedAt: clock.now(),
          current: false,
          staleAfter: const Duration(seconds: 3),
          fix: const FixReport(lat: 39.83, lon: -98.53, ageAtReceipt: Duration(seconds: 20)),
          detail: 'no GPS fix yet (needs a view of the sky)',
        ),
      ),
    );
    final h = await Harness.start(tester, position: src);
    await h.goTo(AppTab.navigation);
    expect(textOf('nav-status'), contains('LAST KNOWN · 20 S AGO'));
    expect(textOf('nav-why'), 'No GPS fix yet (needs a view of the sky)');
    expect(find.byKey(const ValueKey('nav-marker-stale')), findsOneWidget);
  });

  testWidgets('navigation down and never a fix: no position, and why', (tester) async {
    final clock = FakeMonotonicClock();
    final src = FakePositionSource(
      clock,
      const PositionState(link: PositionLink.lost, detail: 'connection refused'),
    );
    final h = await Harness.start(tester, position: src);
    await h.goTo(AppTab.navigation);
    expect(textOf('nav-status'), contains('NO POSITION'));
    expect(textOf('nav-why'), 'Navigation service unavailable: connection refused');
    expect(find.byKey(const ValueKey('nav-marker-current')), findsNothing);
    expect(find.byKey(const ValueKey('nav-marker-stale')), findsNothing);
  });

  testWidgets('a link that drops while current turns the marker grey at once', (tester) async {
    final clock = FakeMonotonicClock(const Duration(seconds: 5));
    final src = FakePositionSource(
      clock,
      PositionState(link: PositionLink.connected, report: report(clock.now())),
    );
    final h = await Harness.start(tester, position: src);
    await h.goTo(AppTab.navigation);
    expect(find.byKey(const ValueKey('nav-marker-current')), findsOneWidget);
    src.value = PositionState(
      link: PositionLink.lost,
      report: src.status.value.report,
      detail: 'stream ended',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('nav-marker-stale')), findsOneWidget);
    expect(textOf('nav-status'), contains('LAST KNOWN'));
  });

  testWidgets('a tileset the dashboard can\'t show says why', (tester) async {
    final map = OfflineMap(
      '/var/lib/f250/maps/map.pmtiles',
      open: (path) async => throw PmTilesException(
        '$path: AVIF tiles can\'t be decoded; use vector (MVT), PNG, JPEG or WebP',
      ),
    );
    await map.load();
    final h = await Harness.start(tester, map: map);
    await h.goTo(AppTab.navigation);
    expect(textOf('nav-map-problem'), contains('AVIF tiles can\'t be decoded'));
    expect(textOf('nav-map-problem'), contains('The position is still shown'));
  });

  for (final theme in [DayNight.day, DayNight.night]) {
    testWidgets('a raster tileset draws, with its attribution (${theme.name})', (tester) async {
      final map = OfflineMap('test/fixtures/maps/solid-z0-3.pmtiles', open: openPmTilesFile);
      await tester.runAsync(map.load);
      expect(map.state.value, isA<MapReady>());
      final h = await Harness.start(tester, map: map, theme: theme);
      await h.goTo(AppTab.navigation);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(find.byKey(const ValueKey('nav-map-problem')), findsNothing);
      expect(textOf('nav-attribution'), 'Test pattern, not map data');
      expect(find.byType(RawImage), findsWidgets, reason: 'tiles drawn');
    });
  }

  for (final theme in [DayNight.day, DayNight.night]) {
    testWidgets('a vector tileset draws with the ${theme.name} style (ADR-0032)', (tester) async {
      final map = OfflineMap('test/fixtures/maps/vector-z12-15.pmtiles', open: openPmTilesFile);
      await tester.runAsync(map.load);
      expect((map.state.value as MapReady).vector, isNotNull);
      // The fixture covers Lebanon, Kansas; the simulated fix is beside it.
      final h = await Harness.start(tester, map: map, theme: theme);
      await h.goTo(AppTab.navigation);
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const ValueKey('nav-map-problem')), findsNothing);
      expect(textOf('nav-attribution'), '© OpenStreetMap');
      final layer = tester.widget<VectorTileLayer>(find.byType(VectorTileLayer));
      expect(
        layer.theme.id,
        theme == DayNight.night ? 'protomaps-dark' : 'protomaps-light',
      );
      expect(
        find.byWidgetPredicate((w) => w is TileLayer && w.tileProvider is PmTilesTileProvider),
        findsNothing,
        reason: 'no raster layer for a vector map',
      );
      expect(
        find.descendant(of: find.byType(VectorTileLayer), matching: find.byType(RawImage)),
        findsWidgets,
        reason: 'vector tiles drawn',
      );
      // Let the layer's own timers finish.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  }

  testWidgets('dragging stops following; the locate button follows again', (tester) async {
    final h = await Harness.start(tester);
    await h.goTo(AppTab.navigation);
    Semantics follow() => tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const ValueKey('nav-follow')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(follow().properties.label, 'Following the truck');
    await tester.drag(find.byKey(const ValueKey('nav-marker-current')), const Offset(-150, 40));
    await tester.pump();
    expect(follow().properties.label, 'Follow the truck');
    await tester.tap(find.byKey(const ValueKey('nav-follow')));
    await tester.pump();
    expect(follow().properties.label, 'Following the truck');
    // Zoom buttons work without throwing.
    await tester.tap(find.byKey(const ValueKey('nav-zoom-in')));
    await tester.tap(find.byKey(const ValueKey('nav-zoom-out')));
    await tester.pump();
  });
}
