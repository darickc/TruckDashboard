import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/network/wifi_state.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/theme.dart';
import 'package:f250_infotainment/ui/widgets/tap_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// Settings › System › Wi-Fi (ADR-0052) against the simulated radio.
void main() {
  setUpAll(loadTestAssets);

  Future<Harness> open(WidgetTester tester, {WifiSource? wifi, DayNight theme = DayNight.night}) async {
    final h = await Harness.start(
      tester,
      theme: theme,
      wifi: wifi ?? (SimulatedWifiSource(joinTime: const Duration(milliseconds: 100))..start()),
    );
    await h.goTo(AppScreen.settings);
    await tester.tap(find.byKey(const ValueKey('settings-system')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('system-wifi')));
    await tester.pump();
    return h;
  }

  Future<void> tap(WidgetTester tester, String key) async {
    // Rows further down the list are scrolled to first, as a finger would.
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String keys) async {
    for (final c in keys.split('')) {
      await tap(tester, 'osk-key-$c');
    }
  }

  testWidgets('System says where Wi-Fi is, opens it, and Back returns', (tester) async {
    final h = await Harness.start(tester, wifi: SimulatedWifiSource()..start());
    await h.goTo(AppScreen.settings);
    await tap(tester, 'settings-system');
    expect(h.textOf('system-wifi-state'), 'on F-250 Hotspot · simulated');
    await tap(tester, 'system-wifi');
    expect(h.textOf('wifi-status'), 'On F-250 Hotspot · 192.0.2.10 · internet reached');
    expect(find.byKey(const ValueKey('wifi-simulated')), findsOneWidget);
    expect(find.byKey(const ValueKey('wifi-network-wifi_sim_shop_managed_psk')), findsOneWidget);
    await tap(tester, 'wifi-back');
    expect(find.byKey(const ValueKey('system-wifi')), findsOneWidget);
  });

  testWidgets('a secured network asks for its passphrase; wrong, then right', (tester) async {
    final h = await open(tester);
    await tap(tester, 'wifi-network-wifi_sim_shop_managed_psk');
    await tap(tester, 'wifi-join');
    expect(find.byKey(const ValueKey('wifi-passphrase-entry')), findsOneWidget);
    await type(tester, 'wrongpass');
    expect(h.textOf('wifi-passphrase'), '•' * 9, reason: 'hidden while typed');
    await tap(tester, 'osk-done');
    await tester.pump(const Duration(milliseconds: 200));
    expect(h.textOf('wifi-message'), 'Shop Wi-Fi: Wrong passphrase');

    await tap(tester, 'wifi-network-wifi_sim_shop_managed_psk');
    // Still chosen after the failure? Choose it again if the tap unchose it.
    if (find.byKey(const ValueKey('wifi-join')).evaluate().isEmpty) {
      await tap(tester, 'wifi-network-wifi_sim_shop_managed_psk');
    }
    await tap(tester, 'wifi-join');
    // Capitals with Shift, digits on the second layer.
    await tap(tester, 'osk-shift');
    await type(tester, 'T');
    await tap(tester, 'osk-shift');
    await type(tester, 'ruck');
    await tap(tester, 'osk-layer');
    await type(tester, '2026');
    await tap(tester, 'osk-shift'); // the second page of symbols
    await type(tester, '~');
    await tap(tester, 'wifi-passphrase-show');
    expect(h.textOf('wifi-passphrase'), 'Truck2026~');
    await tap(tester, 'osk-done');
    await tester.pump(const Duration(milliseconds: 200));
    expect(h.textOf('wifi-message'), 'Joined Shop Wi-Fi');
    expect(h.textOf('wifi-status'), startsWith('On Shop Wi-Fi'));
  });

  testWidgets('Cancel leaves the passphrase untried', (tester) async {
    final h = await open(tester);
    await tap(tester, 'wifi-network-wifi_sim_shop_managed_psk');
    await tap(tester, 'wifi-join');
    await type(tester, 'abc');
    await tap(tester, 'wifi-passphrase-cancel');
    expect(find.byKey(const ValueKey('wifi-passphrase-entry')), findsNothing);
    expect(h.textOf('wifi-status'), startsWith('On F-250 Hotspot'));
  });

  testWidgets('Leave, Forget, an open network, and an enterprise one', (tester) async {
    final h = await open(tester);
    await tap(tester, 'wifi-network-wifi_sim_hotspot_managed_psk');
    await tap(tester, 'wifi-leave');
    expect(h.textOf('wifi-status'), 'Not on a network');
    await tap(tester, 'wifi-network-wifi_sim_hotspot_managed_psk');
    if (find.byKey(const ValueKey('wifi-forget')).evaluate().isEmpty) {
      await tap(tester, 'wifi-network-wifi_sim_hotspot_managed_psk');
    }
    await tap(tester, 'wifi-forget');
    expect(h.textOf('wifi-message'), 'F-250 Hotspot forgotten');

    await tap(tester, 'wifi-network-wifi_sim_stop_managed_none');
    await tap(tester, 'wifi-join');
    expect(find.byKey(const ValueKey('wifi-passphrase-entry')), findsNothing, reason: 'open: no passphrase');
    await tester.pump(const Duration(milliseconds: 200));
    expect(h.textOf('wifi-status'), startsWith('On Truck Stop Free'));

    await tap(tester, 'wifi-network-wifi_sim_corp_managed_ieee8021x');
    expect(h.textOf('wifi-message'), contains("can't be set from here"));
    expect(find.byKey(const ValueKey('wifi-join')), findsNothing);
  });

  testWidgets('Wi-Fi off hides the networks', (tester) async {
    final h = await open(tester);
    await tap(tester, 'wifi-power');
    expect(h.textOf('wifi-status'), 'Wi-Fi is off');
    expect(find.byKey(const ValueKey('wifi-list')), findsNothing);
    expect(h.services.wifi.view.value.onNetwork, isFalse);
  });

  testWidgets('no network service: says so', (tester) async {
    final h = await open(tester, wifi: UnavailableWifiSource('network service unavailable: no socket'));
    expect(h.textOf('wifi-status'), 'Unavailable: network service unavailable: no socket');
    expect(find.byKey(const ValueKey('wifi-list')), findsNothing);
  });

  for (final theme in DayNight.values) {
    testWidgets('fits 800×480 with 60-pixel targets, list and keyboard, ${theme.name}', (tester) async {
      await open(tester, theme: theme);
      void check() {
        for (final e in find.byType(TapTarget).evaluate()) {
          final size = tester.getSize(find.byWidget(e.widget));
          expect(size.width, greaterThanOrEqualTo(kMinTouch - 0.01), reason: '${e.widget.key}');
          expect(size.height, greaterThanOrEqualTo(kMinTouch - 0.01), reason: '${e.widget.key}');
        }
        expect(tester.takeException(), isNull);
      }

      check();
      await tap(tester, 'wifi-network-wifi_sim_shop_managed_psk');
      check();
      await tap(tester, 'wifi-join');
      check();
      final kb = tester.getRect(find.byKey(const ValueKey('osk')));
      expect(kb.bottom, lessThanOrEqualTo(480));
    });
  }
}
