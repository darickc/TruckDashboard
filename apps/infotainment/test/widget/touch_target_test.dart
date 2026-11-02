import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/theme.dart';
import 'package:f250_infotainment/ui/widgets/tap_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

void main() {
  setUpAll(loadTestAssets);

  /// Every tap handler in the tree (InkWell and anything else builds on a
  /// GestureDetector) must sit on a target of at least kMinTouch.
  void expectAllTargetsLargeEnough(WidgetTester tester, String where) {
    final tappable = find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onTap != null,
        skipOffstage: true);
    expect(tappable, findsWidgets, reason: where);
    for (final e in tappable.evaluate()) {
      final size = (e.renderObject! as RenderBox).size;
      final label = e.findAncestorWidgetOfExactType<TapTarget>()?.label ?? e.widget.toString();
      expect(size.width, greaterThanOrEqualTo(kMinTouch - 0.01), reason: '$where: $label');
      expect(size.height, greaterThanOrEqualTo(kMinTouch - 0.01), reason: '$where: $label');
      expect(e.findAncestorWidgetOfExactType<TapTarget>(), isNotNull,
          reason: '$where: tap handler outside TapTarget ($label)');
    }
  }

  testWidgets('every tappable is at least 60×60 on every screen', (tester) async {
    final h = await Harness.start(tester);
    await h.advance(const Duration(seconds: 5));
    for (final tab in AppTab.values) {
      await h.goTo(tab);
      expectAllTargetsLargeEnough(tester, tab.name);
    }
    for (final section in ['signals', 'link', 'dtcs', 'events', 'developer']) {
      await h.goTo(AppTab.diagnostics);
      await tester.tap(find.byKey(ValueKey('diag-$section')));
      await tester.pump();
      expectAllTargetsLargeEnough(tester, 'diagnostics/$section');
    }
  });
}
