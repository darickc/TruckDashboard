import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/widgets/badges.dart';
import 'package:f250_infotainment/ui/widgets/gauge_tile.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

Finder _badgeIn(String signalId) => find.descendant(
    of: find.byWidgetPredicate((w) => w is DigitalGauge && w.signalId == signalId),
    matching: find.byType(UnverifiedBadge));

void main() {
  setUpAll(loadTestAssets);

  testWidgets('towing profile has a fuel tile', (tester) async {
    final h = await Harness.start(tester);
    await h.advance(const Duration(seconds: 6));
    await h.goTo(AppScreen.gauges);
    await tester.tap(find.byKey(const ValueKey('profile-towing')));
    await tester.pump();
    expect(h.textOf('value-fuel_level'), matches(RegExp(r'^\d+$')));
    expect(_badgeIn('fuel_level'), findsOneWidget);
    // Speed takes the slot EGT had; no probe is installed.
    expect(h.textOf('value-speed'), matches(RegExp(r'^\d+$')));
    expect(find.byKey(const ValueKey('value-egt')), findsNothing);
  });

  testWidgets('computed values inherit unverified status from their inputs', (tester) async {
    final h = await Harness.start(tester);
    await h.advance(const Duration(seconds: 6));
    await h.goTo(AppScreen.gauges);
    // EOT−ECT uses EOT (imported, unverified); trans temp is verified on the truck.
    expect(_badgeIn('eot_ect_delta'), findsOneWidget);
    expect(_badgeIn('trans_temp'), findsNothing);
    expect(_badgeIn('ect'), findsNothing);
  });

  testWidgets('fuel goes stale with everything else when the link drops', (tester) async {
    final h = await Harness.start(tester, scenario: 'link_loss');
    await h.advance(const Duration(seconds: 115)); // > 15 s after the drop at 90 s
    await h.goTo(AppScreen.gauges);
    await tester.tap(find.byKey(const ValueKey('profile-towing')));
    await tester.pump();
    expect(h.textOf('status-fuel_level'), startsWith('STALE'));
  });
}
