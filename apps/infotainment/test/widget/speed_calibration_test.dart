import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

Future<void> _openDeveloper(WidgetTester tester, Harness h) async {
  await h.goTo(AppTab.diagnostics);
  await tester.tap(find.byKey(const ValueKey('diag-developer')));
  await tester.pump();
  await tester.scrollUntilVisible(find.byKey(const ValueKey('speed-scale-+1%')), 80,
      scrollable: find.byType(Scrollable).last);
  await tester.pump();
}

void main() {
  setUpAll(loadTestAssets);

  testWidgets('live adjustment changes the shown speed and says it is temporary',
      (tester) async {
    final h = await Harness.start(tester);
    await h.advance(const Duration(seconds: 120)); // cruising
    await _openDeveloper(tester, h);
    expect(h.textOf('speed-scale'), '×1.0000');

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const ValueKey('speed-scale-+1%')));
      await tester.pump();
    }
    expect(h.textOf('speed-scale'), '×1.0510');
    expect(find.textContaining('Lasts until restart'), findsOneWidget);

    final raw = h.store['speed']!.lastGoodRaw!;
    expect(h.store['speed']!.lastGoodValue, closeTo(raw * 1.051, 1e-9));
    expect(h.textOf('speed-scale-reading'), contains('Truck reports'));

    await tester.tap(find.byKey(const ValueKey('speed-scale-reset')));
    await tester.pump();
    expect(h.textOf('speed-scale'), '×1.0000');
  });

  testWidgets('the diagnostics list shows an active factor', (tester) async {
    final h = await Harness.start(tester);
    await h.advance(const Duration(seconds: 10));
    await _openDeveloper(tester, h);
    await tester.tap(find.byKey(const ValueKey('speed-scale-+1%')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('diag-signals')));
    await tester.pump();
    expect(h.textOf('diag-source-speed'), 'SAE ×1.010');
    expect(h.textOf('diag-source-rpm'), 'SAE');
  });

  testWidgets('speed is back on the Home summary', (tester) async {
    final h = await Harness.start(tester);
    await h.advance(const Duration(seconds: 120));
    expect(h.textOf('compact-speed'), matches(RegExp(r'^\d+ mph$')));
  });
}
