import 'package:f250_infotainment/telemetry/source_info.dart';
import 'package:f250_infotainment/telemetry/warnings.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/banner_alerts.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// "Not polling the truck" (ADR-0007 amendment): the gateway is passive
/// although polling was asked for. On 2026-11-10 a drive never polled and
/// nothing on screen said why. `[SIM]`.

const why = 'not polling: the CAN adapter is listen-only, waiting to hear the truck\'s bus '
    '(CAN_AUTO_ACTIVE)';

SourceInfo gateway({bool? transmit = false, String? detail = why, bool simulated = false}) =>
    SourceInfo(
        transport: 'gateway: can:can0',
        simulated: simulated,
        transmitEnabled: transmit,
        machineState: transmit == true ? 'POLLING' : 'PASSIVE_ONLY',
        detail: detail);

void main() {
  setUpAll(loadTestAssets);

  test('only a passive gateway with a reason raises it', () {
    final a = pollingAlerts(gateway());
    expect(a, hasLength(1));
    expect(a.single.title, 'Not polling the truck');
    expect(a.single.level, AlertLevel.critical);
    expect(a.single.detail, startsWith('The CAN adapter is listen-only'));
    expect(pollingAlerts(gateway(detail: null)), isEmpty, reason: 'TRANSMIT=0 by choice');
    expect(pollingAlerts(gateway(transmit: true)), isEmpty, reason: 'polling');
    expect(pollingAlerts(gateway(transmit: null)), isEmpty, reason: 'in-app simulator');
    expect(pollingAlerts(gateway(simulated: true)), isEmpty);
    expect(
        pollingAlerts(gateway(detail: 'polling asks 12.0 req/s of a 10.0 req/s link')), isEmpty);
  });

  testWidgets('it shows in the banner on every screen', (tester) async {
    final h = await Harness.start(tester);
    h.store.source = gateway();
    await h.advance(const Duration(seconds: 1));
    // It is the cause of "Vehicle data lost", so it comes first.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('alert-banner')), matching: find.text('Vehicle data lost')),
        findsNothing);
    for (final tab in AppTab.values) {
      await h.goTo(tab);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('alert-banner')),
              matching: find.text('Not polling the truck')),
          findsOneWidget,
          reason: '$tab');
    }
    h.store.source = gateway(transmit: true, detail: null);
    await h.advance(const Duration(seconds: 1));
    expect(find.text('Not polling the truck'), findsNothing);
  });
}
