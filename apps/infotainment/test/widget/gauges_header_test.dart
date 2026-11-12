import 'package:f250_infotainment/config/app_config.dart';
import 'package:f250_infotainment/model/signal_catalog.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

Future<void> _openProfile(WidgetTester tester, Harness h, String id) async {
  await h.goTo(AppScreen.gauges);
  await tester.tap(find.byKey(ValueKey('profile-$id')));
  await tester.pump();
}

void main() {
  setUpAll(loadTestAssets);

  testWidgets('towing shows RPM at the right end of the selector row', (tester) async {
    final h = await Harness.start(tester);
    await h.advance(const Duration(seconds: 120));
    await _openProfile(tester, h, 'towing');
    expect(h.textOf('header-value-rpm'), matches(RegExp(r'^\d+$')));
    // Right-aligned: its right edge is the selector row's right edge.
    final header = tester.getRect(find.byKey(const ValueKey('header-towing')));
    final screen = tester.getRect(find.byKey(const ValueKey('screen-gauges')));
    expect(header.right, closeTo(screen.right, 0.5));
    expect(header.height, 60);
  });

  testWidgets('engine profile has no header readout', (tester) async {
    final h = await Harness.start(tester);
    await h.advance(const Duration(seconds: 5));
    await _openProfile(tester, h, 'engine');
    expect(find.byKey(const ValueKey('header-value-rpm')), findsNothing);
  });

  testWidgets('header RPM goes stale with the link', (tester) async {
    final h = await Harness.start(tester, scenario: 'link_loss');
    await h.advance(const Duration(seconds: 100));
    await _openProfile(tester, h, 'towing');
    expect(h.textOf('header-status-rpm'), startsWith('STALE'));
  });

  test('an unknown header signal fails fast', () {
    const rules = '{"rules": []}';
    const profiles = '{"profiles": [{"id": "p", "name": "P", "header": "rmp", '
        '"tiles": [{"signal": "rpm", "style": "digital"}]}]}';
    expect(() => AppConfig.parse(rules, profiles, signalsById), throwsFormatException);
  });
}
