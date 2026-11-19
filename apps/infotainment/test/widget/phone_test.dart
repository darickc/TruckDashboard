import 'package:f250_infotainment/audio/audio_state.dart';
import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/screens/phone_lists.dart';
import 'package:f250_infotainment/ui/theme.dart';
import 'package:f250_infotainment/ui/widgets/call_bar.dart';
import 'package:f250_infotainment/ui/widgets/tap_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';
import 'media_test.dart' show FakeAudio, expectTouchTargets;

/// The Phone screen (ADR-0045 phase 2) [SIM]: the phone's contacts and
/// recent calls to call from, the keypad only when stopped, a dialled call
/// shown large while it rings and is talked on, refusals said, and nothing
/// from a phone that has gone.
void main() {
  setUpAll(loadTestAssets);

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<Harness> onPhone(WidgetTester tester, SimulatedAudioSource sim,
      {PhoneTab tab = PhoneTab.contacts, DayNight theme = DayNight.night}) async {
    final h = await Harness.start(tester, audio: sim, theme: theme);
    h.services.phoneTab.value = tab;
    await tester.tap(key('home-phones'));
    await tester.pump();
    // The lists arrive from audio-manager.
    await tester.pump();
    return h;
  }

  testWidgets('Home opens the contacts; Call places a call shown large until hung up', (tester) async {
    final sim = SimulatedAudioSource(autoRun: false);
    final h = await onPhone(tester, sim);
    expect(key('phone-tab-contacts'), findsOneWidget);
    expect(key('contacts-list'), findsOneWidget);
    // One row per number: Alex Rivera has two.
    expect(find.descendant(of: key('contact-0'), matching: find.text('Alex Rivera')), findsOneWidget);
    expect(find.descendant(of: key('contact-0'), matching: find.text('Mobile · +1 555 010 1001')), findsOneWidget);
    expect(find.descendant(of: key('contact-1'), matching: find.text('Work · +1 555 010 2001')), findsOneWidget);
    expectTouchTargets(tester, 'contacts');

    await tester.tap(key('contact-call-1'));
    await tester.pump();
    expect(key('call-view'), findsOneWidget, reason: 'the call replaces the lists');
    expect(key('call-bar'), findsNothing, reason: 'not twice on the Phone screen');
    expect(h.textOf('call-status'), 'Calling…');
    expect(h.textOf('call-caller'), 'Alex Rivera', reason: 'named from the contacts');
    expect(h.textOf('call-detail'), '+15550102001 · on Simulated phone', reason: 'the number as dialled');
    expect(key('call-hang-up'), findsOneWidget);
    expect(sim.status.value.report!.nowPlaying!.state, PlayState.paused, reason: 'the music pauses');

    sim.tick();
    await tester.pump();
    expect(h.textOf('call-status'), 'Ringing…');
    sim
      ..tick()
      ..tick()
      ..tick()
      ..tick();
    await tester.pump();
    expect(h.textOf('call-status'), 'In call');
    expect(h.textOf('call-timer'), matches(RegExp(r'^0:0\d$')), reason: 'the time, large, under the caller');
    expect(key('call-mute'), findsOneWidget);
    expect(tester.getSize(key('call-hang-up')).height, greaterThanOrEqualTo(kMinTouch));
    expectTouchTargets(tester, 'call view');

    // Elsewhere it is the bar, as for any call.
    await h.goTo(AppScreen.gauges);
    expect(key('call-bar'), findsOneWidget);
    await h.goTo(AppScreen.phones);
    await tester.tap(key('call-hang-up'));
    await tester.pump();
    expect(key('call-view'), findsNothing);
    expect(key('contacts-list'), findsOneWidget, reason: 'back to the lists');
    expect(sim.status.value.report!.nowPlaying!.state, PlayState.playing);
  });

  testWidgets('the letter groups jump down the contacts', (tester) async {
    final sim = SimulatedAudioSource(autoRun: false);
    await onPhone(tester, sim);
    expect(find.text('Dana Brooks'), findsNothing, reason: 'below the fold at first');
    await tester.tap(key('contacts-jump-DEF'));
    await tester.pump();
    final list = tester.getRect(key('contacts-list'));
    final name = tester.getRect(find.text('Dana Brooks'));
    expect(name.top, lessThan(list.top + ContactsView.rowExtent), reason: 'at the top of the list');
    // Near the end: as far as the list goes.
    await tester.tap(key('contacts-jump-TUV'));
    await tester.pump();
    expect(find.text('Taylor Diesel Repair'), findsOneWidget);
  });

  testWidgets('recent calls: newest first, kind and time, call back', (tester) async {
    final sim = SimulatedAudioSource(autoRun: false);
    final h = await onPhone(tester, sim, tab: PhoneTab.recent);
    expect(key('recent-list'), findsOneWidget);
    expect(find.descendant(of: key('recent-0'), matching: find.text('Blake Chen')), findsOneWidget);
    expect(find.descendant(of: key('recent-0'), matching: find.textContaining('Missed · ')), findsOneWidget);
    expect(find.descendant(of: key('recent-1'), matching: find.text('555-010-9999')), findsOneWidget,
        reason: 'no name: the number');
    expect(find.descendant(of: key('recent-2'), matching: find.textContaining('Outgoing')), findsOneWidget);
    await tester.tap(key('recent-call-0'));
    await tester.pump();
    expect(h.textOf('call-caller'), 'Blake Chen');
  });

  testWidgets('the keypad works only when stopped, with a current speed', (tester) async {
    final sim = SimulatedAudioSource(autoRun: false);
    final h = await onPhone(tester, sim, tab: PhoneTab.keypad);
    // No speed yet: as if moving.
    expect(keypadAllowed(h.services), isFalse);
    expect(h.textOf('phone-note'), contains('Stop the truck to use the keypad'));
    await tester.tap(key('keypad-5'));
    await tester.pump();
    expect(h.textOf('keypad-number'), 'Number', reason: 'the keys do nothing');

    // drive_cycle stands still for its first 30 s.
    await h.advance(const Duration(seconds: 3));
    expect(keypadAllowed(h.services), isTrue);
    expect(key('phone-note'), findsNothing);
    for (final k in ['5', '5', '5', '0', '1', '0', '0']) {
      await tester.tap(key('keypad-$k'));
      await tester.pump();
    }
    expect(h.textOf('keypad-number'), '5550100');
    await tester.tap(key('keypad-delete'));
    await tester.pump();
    expect(h.textOf('keypad-number'), '555010');
    await tester.tap(key('keypad-0'));
    await tester.pump();
    expectTouchTargets(tester, 'keypad');
    await tester.tap(key('keypad-call'));
    await tester.pump();
    expect(h.textOf('call-caller'), '5550100');
    await tester.tap(key('call-hang-up'));
    await tester.pump();
    expect(h.textOf('keypad-number'), 'Number', reason: 'cleared once placed');

    // Moving: locked again.
    await h.advance(const Duration(seconds: 60));
    expect(h.services.store['speed']!.value, greaterThan(50));
    expect(keypadAllowed(h.services), isFalse);
    expect(h.textOf('phone-note'), contains('Stop the truck'));
    await tester.tap(key('keypad-1'));
    await tester.pump();
    expect(h.textOf('keypad-number'), 'Number');
  });

  testWidgets('calls that stay on the phone: lists shown, Call dimmed, why said', (tester) async {
    final fake = FakeAudio()
      ..value = const AudioStatus(
        link: AudioLink.up,
        report: AudioReport(
          phone: Phone(address: 'AA', name: 'Pixel 8', connected: true, paired: true),
          calls: CallsStatus(detail: 'Calls stay on the phone: no call microphone is configured.'),
          phonebook: PhonebookStatus(phase: PhonebookPhase.failed, detail: 'the phone didn\'t allow it'),
        ),
      );
    final h = await Harness.start(tester, audio: fake);
    await h.goTo(AppScreen.phones);
    await tester.pump();
    expect(h.textOf('phone-list-state'), 'The phone didn\'t share its contacts: the phone didn\'t allow it');
    expect(key('phone-refresh'), findsOneWidget);
    h.services.phoneTab.value = PhoneTab.keypad;
    await tester.pump();
    await h.advance(const Duration(seconds: 3));
    expect(h.textOf('phone-note'), 'Calls stay on the phone: no call microphone is configured.');
  });

  testWidgets('no phone: no lists, and the way to Phones', (tester) async {
    final sim = SimulatedAudioSource(autoRun: false)..disconnect();
    final h = await onPhone(tester, sim);
    expect(key('contacts-list'), findsNothing);
    expect(h.textOf('phone-list-state'), contains('No phone is connected'));
    await tester.tap(key('phone-go-phones'));
    await tester.pump();
    expect(h.services.phoneTab.value, PhoneTab.phones);
    expect(key('phones-pair'), findsOneWidget);
  });

  testWidgets('a phone that goes takes its lists with it', (tester) async {
    final sim = SimulatedAudioSource(autoRun: false);
    await onPhone(tester, sim);
    expect(find.text('Alex Rivera'), findsNWidgets(2), reason: 'two numbers');
    sim.disconnect();
    await tester.pump();
    expect(find.text('Alex Rivera'), findsNothing);
    sim.connect();
    await tester.pump();
    await tester.pump();
    expect(find.text('Alex Rivera'), findsNWidgets(2), reason: 'read again for the phone back');
  });

  testWidgets('Media\'s Phones button opens the paired phones', (tester) async {
    final sim = SimulatedAudioSource(autoRun: false);
    final h = await Harness.start(tester, audio: sim);
    await h.goTo(AppScreen.media);
    await tester.tap(key('media-phones'));
    await tester.pump();
    expect(h.services.phoneTab.value, PhoneTab.phones);
    expect(key('phones-pair'), findsOneWidget);
  });

  for (final theme in DayNight.values) {
    for (final tab in PhoneTab.values) {
      testWidgets('lays out at 800×480: ${tab.name}, ${theme.name}, under an alert', (tester) async {
        final sim = SimulatedAudioSource(autoRun: false);
        final h = await Harness.start(tester, audio: sim, theme: theme, scenario: 'link_loss');
        await h.advance(const Duration(seconds: 100));
        h.services.phoneTab.value = tab;
        await h.goTo(AppScreen.phones);
        await tester.pump();
        expect(key('alert-banner'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expectTouchTargets(tester, '${tab.name} ${theme.name}');
      });
    }
  }

  testWidgets('recentTime says today, yesterday, or the date', (tester) async {
    final now = DateTime(2026, 11, 14, 15);
    expect(recentTime(DateTime(2026, 11, 14, 8, 5), now), 'Today 8:05 AM');
    expect(recentTime(DateTime(2026, 11, 13, 17, 10), now), 'Yesterday 5:10 PM');
    expect(recentTime(DateTime(2026, 11, 2, 0, 30), now), 'Nov 2 12:30 AM');
  });

  group('the call view (redesign 2026-11-18)', () {
    Future<Harness> inCall(WidgetTester tester, SimulatedAudioSource sim, {DayNight theme = DayNight.night}) async {
      final h = await onPhone(tester, sim, theme: theme);
      await tester.tap(key('contact-call-0'));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        sim.tick();
      }
      await tester.pump();
      return h;
    }

    testWidgets('the caller\'s initials, a large timer, Mute and a filled Hang up across the width', (tester) async {
      final sim = SimulatedAudioSource(autoRun: false);
      final h = await inCall(tester, sim);
      expect(h.textOf('call-initials'), 'AR');
      expect(h.textOf('call-timer'), isNotNull);
      final view = tester.getRect(key('call-view'));
      final mute = tester.getRect(key('call-mute'));
      final hang = tester.getRect(key('call-hang-up'));
      expect(mute.height, greaterThanOrEqualTo(80));
      expect(hang.height, greaterThanOrEqualTo(80));
      expect(hang.width, greaterThan(mute.width), reason: 'Hang up is the larger');
      expect(hang.right, closeTo(view.right - 16, 2), reason: 'the row spans the view');
      expect(mute.left, closeTo(view.left + 16, 2));
      final fill = tester.widget<TapTarget>(key('call-hang-up')).fill;
      expect(fill, Palette.night.critical);
      expect(tester.widget<TapTarget>(key('call-mute')).fill, isNull);
    });

    testWidgets('a caller with no name: a person icon, no initials', (tester) async {
      final sim = SimulatedAudioSource(autoRun: false);
      await onPhone(tester, sim);
      sim.ring(number: '5550100', name: '');
      await tester.pump();
      expect(key('call-avatar'), findsOneWidget);
      expect(key('call-initials'), findsNothing);
      // Ringing: Decline and Answer, both filled.
      expect(tester.widget<TapTarget>(key('call-hang-up')).fill, Palette.night.critical);
      expect(tester.widget<TapTarget>(key('call-answer')).fill, Palette.night.ok);
      expect(tester.getSize(key('call-answer')).height, greaterThanOrEqualTo(80));
    });

    test('initials: up to two, from words that start with a letter', () {
      PhoneCall c(String name, {bool withheld = false}) =>
          PhoneCall(id: 1, phase: CallPhase.active, number: '1', name: name, withheld: withheld, active: Duration.zero);
      expect(CallBarInitials.of(c('Alex Rivera')), 'AR');
      expect(CallBarInitials.of(c('Taylor Diesel Repair')), 'TD');
      expect(CallBarInitials.of(c('cher')), 'C');
      expect(CallBarInitials.of(c('  ')), '');
      expect(CallBarInitials.of(c('Alex', withheld: true)), '');
      expect(CallBarInitials.of(c('555 Towing')), 'T');
    });

    test('text on a filled button reads: white on dark, near-black on light', () {
      expect(TapTarget.onFill(Palette.day.critical), Colors.white);
      expect(TapTarget.onFill(Palette.night.ok), isNot(Colors.white));
    });

    for (final theme in DayNight.values) {
      testWidgets('lays out under an alert, ${theme.name}', (tester) async {
        final sim = SimulatedAudioSource(autoRun: false);
        final h = await Harness.start(tester, audio: sim, theme: theme, scenario: 'link_loss');
        await h.advance(const Duration(seconds: 100));
        h.services.phoneTab.value = PhoneTab.contacts;
        await h.goTo(AppScreen.phones);
        await tester.pump();
        await tester.tap(key('contact-call-0'));
        await tester.pump();
        for (var i = 0; i < 6; i++) {
          sim.tick();
        }
        await tester.pump();
        expect(find.byKey(const ValueKey('alert-banner')), findsOneWidget);
        expect(tester.takeException(), isNull);
        expectTouchTargets(tester, 'call view under an alert');
      });
    }
  });

  group('the lists (redesign 2026-11-18)', () {
    testWidgets('contacts: initials once per person, an arrow for further numbers, Call a green icon', (tester) async {
      final sim = SimulatedAudioSource(autoRun: false);
      await onPhone(tester, sim);
      // Alex Rivera has two numbers: rows 0 and 1.
      expect(find.descendant(of: key('contact-avatar-0'), matching: find.text('AR')), findsOneWidget);
      expect(key('contact-avatar-1'), findsNothing, reason: 'the same person\'s next number');
      expect(find.descendant(of: key('contact-1'), matching: find.byIcon(Icons.subdirectory_arrow_right_rounded)),
          findsOneWidget);
      final call = tester.widget<TapTarget>(key('contact-call-1'));
      expect(call.label, 'Call Alex Rivera, work');
      expect(find.descendant(of: key('contact-call-1'), matching: find.byType(Text)), findsNothing, reason: 'an icon');
      final r = tester.getRect(key('contact-call-1'));
      expect(r.height, greaterThanOrEqualTo(kMinTouch));
      expect(r.width, greaterThanOrEqualTo(kMinTouch));
      expectTouchTargets(tester, 'contacts');
    });

    testWidgets('recent calls keep their missed / incoming / outgoing icons', (tester) async {
      final sim = SimulatedAudioSource(autoRun: false);
      await onPhone(tester, sim, tab: PhoneTab.recent);
      expect(find.descendant(of: key('recent-0'), matching: find.byIcon(Icons.call_missed_rounded)), findsOneWidget);
      expect(tester.widget<TapTarget>(key('recent-call-0')).label, startsWith('Call '));
    });

    test('initials from a name: words that start with a letter, two at most', () {
      expect(nameInitials('Alex Rivera'), 'AR');
      expect(nameInitials('Taylor Diesel Repair'), 'TD');
      expect(nameInitials('+1 555 010 1001'), '');
      expect(nameInitials('Émile Zola'), 'ÉZ');
    });

    for (final theme in DayNight.values) {
      testWidgets('contacts lay out under an alert, ${theme.name}', (tester) async {
        final sim = SimulatedAudioSource(autoRun: false);
        final h = await Harness.start(tester, audio: sim, theme: theme, scenario: 'link_loss');
        await h.advance(const Duration(seconds: 100));
        h.services.phoneTab.value = PhoneTab.contacts;
        await h.goTo(AppScreen.phones);
        await tester.pump();
        expect(find.byKey(const ValueKey('alert-banner')), findsOneWidget);
        expect(tester.takeException(), isNull);
        expectTouchTargets(tester, 'contacts under an alert');
      });
    }
  });
}
