import 'package:f250_infotainment/nav/data_licences.dart';
import 'package:f250_infotainment/nav/offline_map.dart';
import 'package:f250_infotainment/nav/pmtiles_file.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/screens/diagnostics_screen.dart';
import 'package:f250_infotainment/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

Future<void> openLicences(WidgetTester tester, Harness h) async {
  await h.goTo(AppScreen.diagnostics);
  await tester.tap(find.byKey(const ValueKey('diag-licences')));
  await tester.pumpAndSettle();
}

/// Data licences (docs/setup/map-data.md): the ODbL and
/// openstreetmap.org/copyright findable on the head unit, as the OSMF
/// attribution guideline asks of a screen whose credit can't be a link.
void main() {
  setUpAll(loadTestAssets);

  testWidgets('every data source, the ODbL and openstreetmap.org/copyright', (tester) async {
    final h = await Harness.start(tester);
    await openLicences(tester, h);
    expect(h.textOf('licences-osm'), contains('Open Database License (ODbL) 1.0'));
    expect(h.textOf('licences-osm'), contains('openstreetmap.org/copyright'));
    expect(h.textOf('licences-installed-map'), 'No map installed.');
    // The list scrolls at 800×480: every source is reachable.
    for (final l in dataLicences) {
      final entry = find.byKey(ValueKey('licences-${l.key}'));
      await tester.scrollUntilVisible(entry, 60, scrollable: find.byType(Scrollable).last);
      expect(entry, findsOneWidget, reason: l.key);
    }
    expect(h.textOf('licences-census'), contains('U.S. Census Bureau'));
    expect(tester.takeException(), isNull);
  });

  testWidgets("the installed map's own credit", (tester) async {
    final map = OfflineMap('test/fixtures/maps/solid-z0-3.pmtiles', open: openPmTilesFile);
    await tester.runAsync(map.load);
    final h = await Harness.start(tester, map: map);
    await openLicences(tester, h);
    expect(h.textOf('licences-installed-map'), 'Installed map: Test pattern, not map data');
  });

  testWidgets('six Diagnostics tabs, each wide enough for its word at the panel font', (tester) async {
    final h = await Harness.start(tester);
    await h.goTo(AppScreen.diagnostics);
    // The test font draws squares, so the widths are checked against the
    // panel's DejaVu Sans Bold at 16 px: "Developer" is the widest word, a
    // little under 100 px (as "Speakers" in Settings, navigation_test.dart).
    for (final d in DiagSection.values) {
      final r = tester.getRect(find.byKey(ValueKey('diag-${d.name}')));
      expect(r.width, greaterThanOrEqualTo(100), reason: d.name);
      expect(r.height, greaterThanOrEqualTo(kMinTouch), reason: d.name);
    }
    expect(tester.takeException(), isNull);
  });
}
