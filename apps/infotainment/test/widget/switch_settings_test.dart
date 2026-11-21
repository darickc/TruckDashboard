import 'package:f250_infotainment/switch/switch_state.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';
import 'settings_test.dart' show openSection, tap;

/// Settings › System › 5-way switch.
Future<void> openSwitch(WidgetTester tester, Harness h) async {
  await openSection(tester, h, 'system');
  await tap(tester, 'system-switch');
}

/// A power-manager stand-in the test drives: its state, presses, and the
/// requests the screen sends.
class FakeSwitch implements SwitchSource {
  FakeSwitch({SwitchLink link = SwitchLink.connected}) {
    _status.value = SwitchStatus(link: link, report: link == SwitchLink.connected ? _report() : null);
  }

  final _status = ValueNotifier(const SwitchStatus(link: SwitchLink.connecting));
  Map<SwitchWire, SwitchRole> mapping = Map.of(defaultSwitchMapping);
  bool learning = false;
  int _seq = 0;
  final learningCalls = <bool>[];
  final saved = <Map<SwitchWire, SwitchRole>>[];
  int resets = 0;
  String saveDetail = 'Saved.';

  SwitchReport _report() => SwitchReport(
        wires: [
          for (final w in SwitchWire.values)
            WireInfo(wire: w, pin: defaultSwitchPins[w]!, role: mapping[w]!, present: w != SwitchWire.f17),
        ],
        learning: learning,
        learningTimeoutS: 60,
        longPressMs: 600,
        defaultMapping: mapEquals(mapping, defaultSwitchMapping),
      );

  void publish({SwitchPress? press}) {
    _status.value = SwitchStatus(
        link: SwitchLink.connected, report: _report(), lastPress: press ?? _status.value.lastPress);
  }

  void push(SwitchWire w) => publish(
      press: SwitchPress(
          wire: w, role: mapping[w]!, kind: PressKind.short, result: 'learning: not sent', seq: ++_seq));

  void lose() => _status.value = const SwitchStatus(link: SwitchLink.lost, detail: 'connection refused');

  @override
  ValueListenable<SwitchStatus> get status => _status;

  @override
  void start() {}

  @override
  void stop() {}

  @override
  Future<void> setLearning(bool on) async {
    learningCalls.add(on);
    learning = on;
    publish();
  }

  @override
  Future<SwitchSaveResult> setMapping(Map<SwitchWire, SwitchRole> m) async {
    saved.add(Map.of(m));
    mapping = Map.of(m);
    learning = false;
    publish();
    return SwitchSaveResult(saved: true, detail: saveDetail);
  }

  @override
  Future<SwitchSaveResult> resetMapping() async {
    resets++;
    mapping = Map.of(defaultSwitchMapping);
    publish();
    return const SwitchSaveResult(saved: true, detail: 'Saved.');
  }
}

void main() {
  setUpAll(loadTestAssets);

  testWidgets('the overview: each direction\'s wire and functions, and the last press', (tester) async {
    final fake = FakeSwitch();
    final h = await Harness.start(tester, switchSource: fake);
    await openSwitch(tester, h);
    expect(h.textOf('sw-summary'), 'Tap: media and calls · Hold 0.6 s: a camera');
    // The switch drawn: each direction's tap and hold where the thumb goes.
    for (final (role, tap, hold) in [
      ('up', 'Volume +', 'hold: Front'),
      ('down', 'Volume −', 'hold: Rear'),
      ('left', 'Previous', 'hold: Left'),
      ('right', 'Next', 'hold: Right'),
      ('press', 'Play/Pause', 'hold: Close'),
    ]) {
      final tile = find.byKey(ValueKey('sw-tile-$role'));
      expect(find.descendant(of: tile, matching: find.text(tap)), findsOneWidget, reason: role);
      expect(find.descendant(of: tile, matching: find.text(hold)), findsOneWidget, reason: role);
    }
    final up = tester.getCenter(find.byKey(const ValueKey('sw-tile-up')));
    final down = tester.getCenter(find.byKey(const ValueKey('sw-tile-down')));
    final left = tester.getCenter(find.byKey(const ValueKey('sw-tile-left')));
    final right = tester.getCenter(find.byKey(const ValueKey('sw-tile-right')));
    final press = tester.getCenter(find.byKey(const ValueKey('sw-tile-press')));
    expect((up.dy < press.dy, down.dy > press.dy, left.dx < press.dx, right.dx > press.dx), (true, true, true, true));
    expect(h.textOf('sw-wires'),
        'Wires: Up BCM6 · Down BCM16 · Left BCM12 · Right BCM13 · Press BCM17 (not readable)');
    expect(h.textOf('sw-last'), 'None yet');
    fake.publish(
        press: const SwitchPress(
            wire: SwitchWire.f16, role: SwitchRole.up, kind: PressKind.short, result: 'volume up → Volume 16.', seq: 1));
    await tester.pump();
    expect(h.textOf('sw-last'), 'Up · tap: volume up → Volume 16.');
    expect(find.byKey(const ValueKey('sw-simulated')), findsNothing);
  });

  testWidgets('set up: push each direction, a repeat is refused, then save', (tester) async {
    final fake = FakeSwitch();
    final h = await Harness.start(tester, switchSource: fake);
    await openSwitch(tester, h);
    await tap(tester, 'sw-learn');
    expect(fake.learningCalls, [true]);
    expect(h.textOf('sw-step'), 'STEP 1 OF 5');
    expect(h.textOf('sw-want'), 'UP');
    expect(h.textOf('sw-countdown'), 'Stops in 60 s without a push');
    h.clock.advance(const Duration(seconds: 8));
    h.store.refresh();
    await tester.pump();
    expect(h.textOf('sw-countdown'), 'Stops in 52 s without a push');

    // Mounted a quarter turn: the wire for "left" is up now.
    fake.push(SwitchWire.f13);
    await tester.pump();
    expect(h.textOf('sw-want'), 'DOWN');
    expect(h.textOf('sw-learn-msg'), 'Up is on BCM12.');
    expect(h.textOf('sw-countdown'), 'Stops in 60 s without a push', reason: 'a push restarts it');
    expect(find.descendant(of: find.byKey(const ValueKey('sw-tile-up')), matching: find.text('BCM12')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('sw-tile-down')), matching: find.byIcon(Icons.arrow_downward)),
        findsOneWidget);
    fake.push(SwitchWire.f13);
    await tester.pump();
    expect(h.textOf('sw-learn-msg'), 'That was Up again. Push the switch down.');
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(h.textOf('sw-step'), 'STEP 2 OF 5');
    for (final w in [SwitchWire.f14, SwitchWire.f16, SwitchWire.f15, SwitchWire.f17]) {
      fake.push(w);
      await tester.pump();
    }
    expect(h.textOf('sw-prompt'), 'All five found.');
    await tap(tester, 'sw-save');
    expect(fake.saved.single, {
      SwitchWire.f13: SwitchRole.up,
      SwitchWire.f14: SwitchRole.down,
      SwitchWire.f16: SwitchRole.left,
      SwitchWire.f15: SwitchRole.right,
      SwitchWire.f17: SwitchRole.press,
    });
    expect(h.textOf('sw-message'), 'Saved.');
    expect(h.textOf('sw-wires'), startsWith('Wires: Up BCM12 · Down BCM13 · Left BCM6 · Right BCM16'),
        reason: 'the overview shows the new directions');
  });

  testWidgets('save stays off until all five, start over clears them', (tester) async {
    final fake = FakeSwitch();
    final h = await Harness.start(tester, switchSource: fake);
    await openSwitch(tester, h);
    await tap(tester, 'sw-learn');
    fake.push(SwitchWire.f16);
    await tester.pump();
    await tap(tester, 'sw-save');
    expect(fake.saved, isEmpty);
    await tap(tester, 'sw-restart');
    expect(h.textOf('sw-want'), 'UP');
    expect(h.textOf('sw-step'), 'STEP 1 OF 5');
  });

  testWidgets('cancel ends learning and changes nothing', (tester) async {
    final fake = FakeSwitch();
    final h = await Harness.start(tester, switchSource: fake);
    await openSwitch(tester, h);
    await tap(tester, 'sw-learn');
    fake.push(SwitchWire.f13);
    await tester.pump();
    await tap(tester, 'sw-cancel');
    expect(fake.learningCalls, [true, false]);
    expect(fake.saved, isEmpty);
    expect(h.textOf('sw-message'), 'Cancelled: the directions are as they were.');
    expect(find.byKey(const ValueKey('sw-learn')), findsOneWidget);
  });

  testWidgets('learning running out, or power-manager going away, ends set-up', (tester) async {
    final fake = FakeSwitch();
    final h = await Harness.start(tester, switchSource: fake);
    await openSwitch(tester, h);
    await tap(tester, 'sw-learn');
    fake.learning = false; // power-manager's 60 s ran out
    fake.publish();
    await tester.pump();
    expect(h.textOf('sw-message'), 'Set-up ended: no push for 60 s. Nothing was changed.');
    expect(find.byKey(const ValueKey('sw-prompt')), findsNothing);

    await tap(tester, 'sw-learn');
    fake.lose();
    await tester.pump();
    expect(h.textOf('sw-detail'),
        'power-manager not connected (connection refused): the switch\'s directions can\'t be read or changed.');
    expect(find.byKey(const ValueKey('sw-learn')), findsNothing, reason: 'no buttons that can\'t work');
    expect(fake.saved, isEmpty);
  });

  testWidgets('reset to default, offered only when the directions differ', (tester) async {
    final fake = FakeSwitch()..mapping = {
      SwitchWire.f13: SwitchRole.up,
      SwitchWire.f14: SwitchRole.down,
      SwitchWire.f15: SwitchRole.left,
      SwitchWire.f16: SwitchRole.right,
      SwitchWire.f17: SwitchRole.press,
    };
    fake.publish();
    final h = await Harness.start(tester, switchSource: fake);
    await openSwitch(tester, h);
    await tap(tester, 'sw-reset');
    expect(fake.resets, 1);
    expect(h.textOf('sw-message'), 'Back to the default directions.');
    await tap(tester, 'sw-reset');
    expect(fake.resets, 1, reason: 'already the default');
  });

  testWidgets('simulated: marked, and the learn flow works with the stand-in buttons', (tester) async {
    final sim = SimulatedSwitchSource();
    final h = await Harness.start(tester, switchSource: sim);
    await openSwitch(tester, h);
    expect(find.byKey(const ValueKey('sw-simulated')), findsOneWidget);
    await tap(tester, 'sw-sim-f16');
    expect(h.textOf('sw-last'), 'Up · tap: volume up: simulated, not sent');
    await tap(tester, 'sw-learn');
    for (final w in [SwitchWire.f15, SwitchWire.f16, SwitchWire.f14, SwitchWire.f13, SwitchWire.f17]) {
      await tap(tester, 'sw-sim-${w.name}');
    }
    await tap(tester, 'sw-save');
    expect(sim.status.value.report!.wireFor(SwitchRole.up)!.wire, SwitchWire.f15);
    expect(sim.status.value.report!.learning, isFalse);
  });

  testWidgets('not connected: says so, offers nothing', (tester) async {
    final fake = FakeSwitch(link: SwitchLink.connecting);
    final h = await Harness.start(tester, switchSource: fake);
    await openSwitch(tester, h);
    expect(h.textOf('sw-detail'), startsWith('power-manager not connected'));
    expect(find.byKey(const ValueKey('sw-learn')), findsNothing);
    expect(find.byKey(const ValueKey('sw-reset')), findsNothing);
    expect(h.services.screens.value, AppScreen.settings);
  });

  testWidgets('System\'s row says whether the directions are set, and opens them', (tester) async {
    final fake = FakeSwitch();
    final h = await Harness.start(tester, switchSource: fake);
    await openSection(tester, h, 'system');
    expect(h.textOf('system-switch-state'), 'default directions');
    expect(tester.getSize(find.byKey(const ValueKey('system-switch'))).height, greaterThanOrEqualTo(60));
    fake.mapping = {
      SwitchWire.f13: SwitchRole.up,
      SwitchWire.f14: SwitchRole.down,
      SwitchWire.f15: SwitchRole.left,
      SwitchWire.f16: SwitchRole.right,
      SwitchWire.f17: SwitchRole.press,
    };
    fake.publish();
    await tester.pump();
    expect(h.textOf('system-switch-state'), 'directions set');
    await tap(tester, 'system-switch');
    expect(find.byKey(const ValueKey('sw-diagram')), findsOneWidget);
    await tap(tester, 'sw-back');
    expect(find.byKey(const ValueKey('system-switch')), findsOneWidget);
  });
}
