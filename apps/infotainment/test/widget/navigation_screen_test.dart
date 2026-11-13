import 'dart:math' as math;

import 'package:f250_infotainment/core/clock.dart';
import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/display/display_state.dart';
import 'package:f250_infotainment/nav/offline_map.dart';
import 'package:f250_infotainment/nav/pmtiles.dart';
import 'package:f250_infotainment/nav/pmtiles_file.dart';
import 'package:f250_infotainment/nav/position_state.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/screens/navigation_screen.dart';
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
    await h.goTo(AppScreen.navigation);
    expect(
      textOf('nav-status'),
      allOf(contains('3D FIX'), contains('SIMULATED'), contains('9 SATS')),
    );
    expect(find.byKey(const ValueKey('nav-marker-current')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-why')), findsNothing);
    expect(textOf('nav-map-problem'), contains('no offline map configured'));
    expect(textOf('nav-routing'), 'Routing unavailable: needs services/navigation (make sim)');
  });

  testWidgets('a fix that stops updating becomes "last known", with its age', (tester) async {
    final h = await Harness.start(tester);
    await h.goTo(AppScreen.navigation);
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
    await h.goTo(AppScreen.navigation);
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
    await h.goTo(AppScreen.navigation);
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
    await h.goTo(AppScreen.navigation);
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
    await h.goTo(AppScreen.navigation);
    expect(textOf('nav-map-problem'), contains('AVIF tiles can\'t be decoded'));
    expect(textOf('nav-map-problem'), contains('The position is still shown'));
  });

  for (final theme in [DayNight.day, DayNight.night]) {
    testWidgets('a raster tileset draws, with its attribution (${theme.name})', (tester) async {
      final map = OfflineMap('test/fixtures/maps/solid-z0-3.pmtiles', open: openPmTilesFile);
      await tester.runAsync(map.load);
      expect(map.state.value, isA<MapReady>());
      final h = await Harness.start(tester, map: map, theme: theme);
      await h.goTo(AppScreen.navigation);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(find.byKey(const ValueKey('nav-map-problem')), findsNothing);
      expect(textOf('nav-attribution'), 'Test pattern, not map data');
      expect(find.byType(RawImage), findsWidgets, reason: 'tiles drawn');
    });
  }

  // One session, day then night: vector_map_tiles keeps a module-level label
  // queue, and a second test's fake-time zone never runs the first test's
  // queue. The app runs in one zone (leaving Nav and coming back, and day ->
  // night, redraw: checked 2026-11-13).
  testWidgets('a vector tileset draws with the day style, then the night style (ADR-0032)', (tester) async {
    final map = OfflineMap('test/fixtures/maps/vector-z12-15.pmtiles', open: openPmTilesFile);
    await tester.runAsync(map.load);
    expect((map.state.value as MapReady).vector, isNotNull);
    // The fixture covers Lebanon, Kansas; the simulated fix is beside it.
    final display = SimulatedDisplaySource(mode: DayNight.day);
    final h = await Harness.start(tester, map: map, display: display);
    await h.goTo(AppScreen.navigation);
    // Vector mode: each tile is a CustomPaint with vector_map_tiles' own
    // painter (not exported, so matched by its type's name).
    final tilePainters = find.descendant(
      of: find.byType(VectorTileLayer),
      matching: find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter.runtimeType.toString() == 'VectorTilePainter',
      ),
    );
    Future<void> waitForTiles() async {
      for (var i = 0; i < 75 && tilePainters.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    for (final theme in [DayNight.day, DayNight.night]) {
      if (theme == DayNight.night) {
        await display.setChoice(DisplayChoice.night);
        // The theme reaches the map over a few frames; then new tiles.
        String themeId() => tester.widget<VectorTileLayer>(find.byType(VectorTileLayer)).theme.id;
        for (var i = 0; i < 50 && themeId() != 'protomaps-dark'; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      await waitForTiles();
      expect(find.byKey(const ValueKey('nav-map-problem')), findsNothing);
      expect(textOf('nav-attribution'), '© OpenStreetMap');
      final layer = tester.widget<VectorTileLayer>(find.byType(VectorTileLayer));
      expect(
        layer.layerMode,
        VectorTileLayerMode.vector,
        reason: 'raster mode draws tiles unturned: road names upside down on a turned map',
      );
      expect(
        layer.theme.id,
        theme == DayNight.night ? 'protomaps-dark' : 'protomaps-light',
      );
      expect(
        find.byWidgetPredicate((w) => w is TileLayer && w.tileProvider is PmTilesTileProvider),
        findsNothing,
        reason: 'no raster layer for a vector map',
      );
      expect(tilePainters, findsWidgets, reason: 'vector tiles drawn (${theme.name})');
    }
    // Let the layer's own timers finish.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a map stick shows its progress on every screen, and the result on Nav (ADR-0033)',
      (tester) async {
    final answers = <String>[
      '{"state":"copying","percent":43,"message":"","id":"n","device":"/dev/sda1","at":"2026-11-11T12:00:00Z"}',
      '{"state":"failed","percent":0,"message":"The copied map doesn\'t match its checksum. The old map is kept.",'
          '"id":"n","device":"/dev/sda1","at":"${DateTime.now().toUtc().toIso8601String()}"}',
    ];
    final map = OfflineMap(
      'test/fixtures/maps/solid-z0-3.pmtiles',
      statusPath: '/run/f250-maps/status.json',
      open: openPmTilesFile,
      readStatus: (_) async => answers.isEmpty ? null : answers.removeAt(0),
    );
    await tester.runAsync(map.load);
    await tester.runAsync(map.checkUpdate);
    final h = await Harness.start(tester, map: map);
    await tester.pump();
    expect(textOf('map-update-chip'), 'MAP 43%', reason: 'in the status bar on the Home screen');
    await h.goTo(AppScreen.navigation);
    expect(textOf('nav-map-update'), 'Copying the map from USB: 43%. Leave the stick in.');
    await tester.runAsync(map.checkUpdate);
    await tester.pump();
    expect(textOf('map-update-chip'), 'MAP UPDATE FAILED');
    expect(textOf('nav-map-update'), contains('The old map is kept'));
    expect(find.byKey(const ValueKey('nav-map-problem')), findsNothing, reason: 'the old map still shows');
  });

  testWidgets('dragging stops following; the locate button follows again', (tester) async {
    final h = await Harness.start(tester);
    await h.goTo(AppScreen.navigation);
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

  group('heading up (owner, 2026-11-12)', () {
    test('the map turns by minus the course', () {
      expect(NavigationScreen.rotationFor(0), 0);
      expect(NavigationScreen.rotationFor(90), -90);
      expect(NavigationScreen.rotationFor(180), 180);
      expect(NavigationScreen.rotationFor(270), 90);
      expect(NavigationScreen.rotationFor(359), 1);
    });

    test('only a current course while moving counts', () {
      const moving = FixReport(lat: 0, lon: 0, ageAtReceipt: Duration.zero, speedMps: 5, trackDeg: 370);
      expect(NavigationScreen.courseOf(moving, true), 10);
      expect(NavigationScreen.courseOf(moving, false), isNull, reason: 'stale');
      const slow = FixReport(lat: 0, lon: 0, ageAtReceipt: Duration.zero, speedMps: 0.5, trackDeg: 10);
      expect(NavigationScreen.courseOf(slow, true), isNull, reason: 'stopped: the course is noise');
      const noCourse = FixReport(lat: 0, lon: 0, ageAtReceipt: Duration.zero, speedMps: 5);
      expect(NavigationScreen.courseOf(noCourse, true), isNull);
    });

    testWidgets('the direction of travel is up while following; kept when stopped', (tester) async {
      final clock = FakeMonotonicClock(const Duration(seconds: 5));
      PositionState at(double track, {double speed = 20, bool current = true, double lat = 39.83}) => PositionState(
        link: PositionLink.connected,
        report: PositionReport(
          status: FixStatus.fix3d,
          receivedAt: clock.now(),
          current: current,
          staleAfter: const Duration(seconds: 3),
          fix: FixReport(lat: lat, lon: -98.53, ageAtReceipt: Duration.zero, speedMps: speed, trackDeg: track),
        ),
      );
      final src = FakePositionSource(clock, at(90));
      final h = await Harness.start(tester, position: src);
      await h.goTo(AppScreen.navigation);
      await tester.pump();
      double rotation() => tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!.camera.rotation;
      String compass() => tester
          .widget<Semantics>(
            find.ancestor(of: find.byKey(const ValueKey('nav-compass')), matching: find.byType(Semantics)).first,
          )
          .properties
          .label!;
      double arrow() {
        final m = tester.widget<Transform>(find.byKey(const ValueKey('nav-marker-arrow'))).transform;
        return math.atan2(m.entry(1, 0), m.entry(0, 0)) * 180 / math.pi;
      }

      expect(rotation(), closeTo(-90, 0.01), reason: 'heading east: east is up');
      expect(compass(), 'Compass: north is to the left');
      expect(arrow(), closeTo(0, 0.01), reason: 'the truck points up');

      src.value = at(180, lat: 39.82);
      await tester.pump();
      expect(rotation(), closeTo(180, 0.01));
      expect(compass(), 'Compass: north is down');
      expect(arrow(), closeTo(0, 0.01));

      src.value = at(181, lat: 39.81);
      await tester.pump();
      expect(rotation(), closeTo(180, 0.01), reason: 'a degree of jitter turns nothing');

      src.value = at(10, speed: 0.3, lat: 39.80);
      await tester.pump();
      expect(rotation(), closeTo(180, 0.01), reason: 'stopped: the last turn is kept');
      expect(find.byKey(const ValueKey('nav-marker-arrow')), findsNothing, reason: 'a dot while stopped');

      src.value = at(270, current: false, lat: 39.79);
      await tester.pump();
      expect(rotation(), closeTo(180, 0.01), reason: 'a stale course turns nothing');

      // Dragged: not following, the map stays as it is; following again
      // turns it to the course.
      src.value = at(270, lat: 39.78);
      await tester.pump();
      expect(rotation(), closeTo(90, 0.01));
      await tester.drag(find.byKey(const ValueKey('nav-marker-current')), const Offset(-150, 40));
      await tester.pump();
      src.value = at(0, lat: 39.77);
      await tester.pump();
      expect(rotation(), closeTo(90, 0.01), reason: 'not following: the driver is looking around');
      await tester.tap(find.byKey(const ValueKey('nav-follow')));
      await tester.pump();
      expect(rotation(), closeTo(0, 0.01));
      expect(compass(), 'Compass: north is up');
    });

    testWidgets('north up until the truck has moved', (tester) async {
      final clock = FakeMonotonicClock(const Duration(seconds: 5));
      final src = FakePositionSource(
        clock,
        PositionState(
          link: PositionLink.connected,
          report: PositionReport(
            status: FixStatus.fix3d,
            receivedAt: clock.now(),
            current: true,
            staleAfter: const Duration(seconds: 3),
            fix: const FixReport(lat: 39.83, lon: -98.53, ageAtReceipt: Duration.zero, speedMps: 0, trackDeg: 123),
          ),
        ),
      );
      final h = await Harness.start(tester, position: src);
      await h.goTo(AppScreen.navigation);
      await tester.pump();
      expect(tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!.camera.rotation, 0);
    });
  });
}
