import 'package:f250_infotainment/audio/audio_state.dart';
import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:f250_infotainment/ui/theme.dart';
import 'package:f250_infotainment/ui/widgets/tap_target.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// The Media and Phones screens and Settings → Speakers (ADR-0039) at
/// 800×480, against
/// the simulated audio-manager and a fake one whose reports the test sets.
/// `[SIM]`.

Finder key(String k) => find.byKey(ValueKey(k));

String? text(WidgetTester tester, String k) {
  final f = key(k);
  if (f.evaluate().isEmpty) return null;
  return tester.widget<Text>(f).data;
}

void expectTouchTargets(WidgetTester tester, String where) {
  for (final e in find.byType(InkWell).evaluate()) {
    final size = (e.renderObject! as RenderBox).size;
    final label = e.findAncestorWidgetOfExactType<TapTarget>()?.label;
    expect(size.width, greaterThanOrEqualTo(kMinTouch - 0.01), reason: '$where: $label');
    expect(size.height, greaterThanOrEqualTo(kMinTouch - 0.01), reason: '$where: $label');
  }
}

/// An audio-manager whose status the test sets, recording the calls.
class FakeAudio implements AudioSource {
  final calls = <String>[];
  final _status = ValueNotifier(const AudioStatus(link: AudioLink.connecting));

  set value(AudioStatus s) => _status.value = s;

  @override
  ValueListenable<AudioStatus> get status => _status;
  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<CommandResult> control(MediaCommand c) async {
    calls.add('control ${c.name}');
    return const CommandResult(ok: false, detail: 'The phone refused Next.');
  }

  @override
  Future<CommandResult> openPairing([int seconds = 0]) async {
    calls.add('open');
    return const CommandResult(ok: true);
  }

  @override
  Future<bool> closePairing() async {
    calls.add('close');
    return true;
  }

  @override
  Future<CommandResult> confirm(int id, bool accept) async {
    calls.add('confirm $id $accept');
    return const CommandResult(ok: true);
  }

  @override
  Future<CommandResult> connectPhone(String address) async {
    calls.add('connect $address');
    return const CommandResult(ok: true);
  }

  @override
  Future<SpeakerSnapshot> getSpeakers() async =>
      const SpeakerSnapshot(settings: SpeakerSettings(), limits: SpeakerLimits(), defaults: SpeakerSettings());
  @override
  Future<CommandResult> setSpeakers(SpeakerSettings s) async {
    calls.add('speakers ${s.fader} ${s.balance} ${s.subLevelDb} ${s.crossoverHz}');
    return const CommandResult(ok: true);
  }
}

const phone = Phone(address: 'AA:BB', name: 'Pixel 8', connected: true, paired: true);

AudioStatus up(AudioReport r) => AudioStatus(link: AudioLink.up, report: r);

void main() {
  setUpAll(loadTestAssets);

  testWidgets('now playing from the simulated phone, and the controls', (tester) async {
    final audio = SimulatedAudioSource(autoRun: false);
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.media);
    expect(text(tester, 'media-title'), 'Simulated Track One');
    expect(text(tester, 'media-artist'), 'The Test Tones');
    expect(text(tester, 'media-album'), 'Not a Real Album');
    expect(text(tester, 'media-source'), 'Bluetooth · Simulated phone');
    expect(key('media-simulated'), findsOneWidget);
    expect(key('media-streaming'), findsOneWidget);
    expect(text(tester, 'media-time'), '0:00 / 3:05');
    expect(text(tester, 'media-state'), 'Playing');
    for (var i = 0; i < 61; i++) {
      audio.tick();
    }
    await tester.pump();
    expect(text(tester, 'media-time'), '1:01 / 3:05');
    expectTouchTargets(tester, 'media');

    await tester.tap(key('media-play-pause'));
    await tester.pump();
    expect(text(tester, 'media-state'), 'Paused');
    expect(key('media-streaming'), findsNothing);
    audio.tick();
    await tester.pump();
    expect(text(tester, 'media-time'), '1:01 / 3:05', reason: 'paused: no time passes');
    await tester.tap(key('media-next'));
    await tester.pump();
    expect(text(tester, 'media-title'), 'Second Simulated Song');
    await tester.tap(key('media-previous'));
    await tester.pump();
    expect(text(tester, 'media-title'), 'Simulated Track One');
  });

  testWidgets('link loss: the track goes with the phone, and comes back with it', (tester) async {
    final audio = SimulatedAudioSource(autoRun: false);
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.media);
    audio.disconnect();
    await tester.pump();
    expect(key('media-title'), findsNothing, reason: 'never the last track of a gone phone');
    expect(text(tester, 'media-headline'), 'No phone connected');
    expect(text(tester, 'media-explain'), 'Tap Phones to connect a paired phone or pair another.');
    // The controls are shown but do nothing.
    await tester.tap(key('media-next'));
    await tester.pump();
    expect(text(tester, 'media-headline'), 'No phone connected');
    expectTouchTargets(tester, 'media, no phone');
    audio.connect();
    await tester.pump();
    expect(text(tester, 'media-title'), 'Simulated Track One');
  });

  testWidgets('Bluetooth unavailable: said plainly, pairing off', (tester) async {
    final audio = SimulatedAudioSource(autoRun: false);
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.media);
    audio.setBluetooth(false);
    await tester.pump();
    expect(text(tester, 'media-headline'), 'Bluetooth unavailable');
    expect(text(tester, 'media-explain'), 'simulated: Bluetooth is off');
    expect(key('media-title'), findsNothing);
    await h.goTo(AppScreen.phones);
    expect(text(tester, 'phones-empty'), 'simulated: Bluetooth is off');
    await tester.tap(key('phones-pair'));
    await tester.pump();
    expect(text(tester, 'phones-pairing'), 'Bluetooth stopped: the pairing window is closed.',
        reason: 'Pair is off: nothing opened');
  });

  testWidgets('audio-manager not connected or silent: nothing current is shown', (tester) async {
    final audio = FakeAudio();
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.media);
    expect(text(tester, 'media-link'), 'Connecting to audio-manager…');
    audio.value = up(const AudioReport(
        phone: phone, nowPlaying: NowPlaying(title: 'Old Song', state: PlayState.playing)));
    await tester.pump();
    expect(text(tester, 'media-title'), 'Old Song');
    audio.value = const AudioStatus(link: AudioLink.down, detail: 'audio-manager stopped answering');
    await tester.pump();
    expect(find.text('Old Song'), findsNothing);
    expect(text(tester, 'media-link'), 'audio-manager not connected');
    expect(text(tester, 'media-link-detail'), startsWith('audio-manager stopped answering.'));
    expect(key('media-phones'), findsNothing);
    await h.goTo(AppScreen.phones);
    expect(text(tester, 'phones-link'), contains('audio-manager not connected'));
    expect(key('phones-pair'), findsNothing);
  });

  testWidgets('a phone with no player: connected, no controls', (tester) async {
    final audio = FakeAudio()..value = up(const AudioReport(phone: phone, streaming: true));
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.media);
    expect(text(tester, 'media-headline'), 'Connected to Pixel 8');
    // The badges follow the name: no empty room is kept between them (which
    // used to cut the name short with space to spare).
    expect(tester.getRect(key('media-streaming')).left - tester.getRect(key('media-source')).right,
        closeTo(6, 0.5));
    expect(text(tester, 'media-explain'), contains('no AVRCP player'));
    await tester.tap(key('media-play-pause'));
    await tester.pump();
    expect(audio.calls, isEmpty);
  });

  testWidgets('paused for spoken directions says so', (tester) async {
    final audio = FakeAudio()
      ..value = up(const AudioReport(
          phone: phone,
          pausedForPrompt: true,
          speaking: true,
          nowPlaying: NowPlaying(title: 'T', state: PlayState.paused)));
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.media);
    expect(find.text('PAUSED FOR DIRECTIONS'), findsOneWidget);
    audio.value = up(const AudioReport(
        phone: phone, nowPlaying: NowPlaying(title: 'T', state: PlayState.playing)));
    await tester.pump();
    expect(key('media-directions'), findsNothing);
  });

  testWidgets('a refused command says why', (tester) async {
    final audio = FakeAudio()
      ..value = up(const AudioReport(
          phone: phone,
          nowPlaying: NowPlaying(title: 'T', state: PlayState.playing, position: Duration(seconds: 5))));
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.media);
    expect(text(tester, 'media-time'), '0:05', reason: 'no duration: the position alone');
    await tester.tap(key('media-next'));
    await tester.pump();
    await tester.pump();
    expect(audio.calls, ['control next']);
    expect(text(tester, 'media-message'), 'The phone refused Next.');
  });

  testWidgets('pairing window: Pair, countdown, the code, accepted, closed', (tester) async {
    final audio = SimulatedAudioSource(autoRun: false, pairAfterTicks: 3);
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.phones);
    expect(find.textContaining('Pair a phone'), findsOneWidget);
    expect(text(tester, 'phones-pairing'), contains('Not visible to new phones'));
    await tester.tap(key('phones-pair'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Stop pairing · 2:00'), findsOneWidget);
    expect(text(tester, 'phones-pairing'), contains('Visible as "F-250" for 2:00'));
    audio.tick();
    await tester.pump();
    expect(find.textContaining('Stop pairing · 1:59'), findsOneWidget);
    audio
      ..tick()
      ..tick();
    await tester.pump();
    expect(key('phones-question'), findsOneWidget);
    expect(text(tester, 'phones-passkey'), '246 810');
    expect(find.text('Simulated phone 2 wants to pair'), findsOneWidget);
    expectTouchTargets(tester, 'phones, question');
    // Media points at it too.
    await h.goTo(AppScreen.media);
    expect(find.text('Phones · pairing request'), findsOneWidget);
    await tester.tap(key('media-phones'));
    await tester.pump();
    await tester.tap(key('phones-confirm-yes'));
    await tester.pump();
    await tester.pump();
    expect(key('phones-question'), findsNothing);
    expect(text(tester, 'phones-status-02:00:00:00:00:02'), 'Connected');
    expect(text(tester, 'phones-status-02:00:00:00:00:01'), 'Paired · not connected');
    expect(text(tester, 'phones-pairing'), 'Paired with Simulated phone 2.');
    expect(find.textContaining('Pair a phone'), findsOneWidget);
  });

  testWidgets('pairing window: refused, stopped by hand, and closing by itself', (tester) async {
    final audio = SimulatedAudioSource(autoRun: false, pairAfterTicks: 1);
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.phones);
    await tester.tap(key('phones-pair'));
    await tester.pump();
    audio.tick();
    await tester.pump();
    await tester.tap(key('phones-confirm-no'));
    await tester.pump();
    await tester.pump();
    expect(text(tester, 'phones-pairing'), contains('Visible as'));
    expect(text(tester, 'phones-status-02:00:00:00:00:01'), 'Connected');
    expect(key('phones-row-02:00:00:00:00:02'), findsNothing);
    await tester.tap(key('phones-pair'));
    await tester.pump();
    await tester.pump();
    expect(text(tester, 'phones-pairing'), 'Closed.');

    await tester.tap(key('phones-pair'));
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < SimulatedAudioSource.windowSeconds; i++) {
      audio.tick();
    }
    await tester.pump();
    expect(text(tester, 'phones-pairing'), 'Closed by itself after 120 s.');
    expect(key('phones-question'), findsNothing);
  });

  testWidgets('a code-less pairing request says to check the phone', (tester) async {
    final audio = FakeAudio()
      ..value = up(const AudioReport(
          phone: phone,
          pairing: PairingStatus(
              phase: PairingPhase.open,
              secondsLeft: 50,
              name: 'F-250',
              question: PasskeyQuestion(id: 7, phoneName: 'Unknown', address: 'CC', secondsLeft: 20))));
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.phones);
    expect(key('phones-passkey'), findsNothing);
    expect(find.textContaining('Accept only if it is the phone in your hand'), findsOneWidget);
    expect(find.text('Refused by itself in 20 s.'), findsOneWidget);
    await tester.tap(key('phones-confirm-no'));
    await tester.pump();
    expect(audio.calls, ['confirm 7 false']);
  });

  testWidgets('long titles and names fit at 800×480 in day and night', (tester) async {
    final long = 'A Very Long Song Title That Keeps Going ' * 4;
    for (final theme in DayNight.values) {
      final audio = FakeAudio()
        ..value = up(AudioReport(
            phone: Phone(address: 'A', name: 'Phone ' * 20, connected: true),
            known: [Phone(address: 'B', name: 'Other ' * 20, paired: true)],
            nowPlaying: NowPlaying(
                title: long,
                artist: long,
                album: long,
                state: PlayState.error,
                duration: const Duration(hours: 1, minutes: 2),
                position: const Duration(minutes: 3)),
            streaming: true,
            simulated: true,
            dspDetail: 'pipewire stopped (exit status: 1)'));
      final h = await Harness.start(tester, audio: audio, theme: theme);
      await h.goTo(AppScreen.media);
      expect(tester.takeException(), isNull);
      expect(text(tester, 'media-time'), '3:00 / 1:02:00');
      expect(text(tester, 'media-state'), 'The phone reports an error');
      expect(key('media-dsp'), findsNothing, reason: 'simulated: never a crossover to miss');
    }
  });

  testWidgets('long phone names fit on Phones at 800×480 in day and night', (tester) async {
    for (final theme in DayNight.values) {
      final audio = FakeAudio()
        ..value = up(AudioReport(
            phone: Phone(address: 'A', name: 'Phone ' * 20, connected: true),
            known: [
              for (var i = 0; i < 6; i++) Phone(address: 'B$i', name: 'Other ' * 20, paired: true, last: i == 0),
            ],
            connect: ConnectStatus(detail: 'Couldn\'t reach ${'Other ' * 20}: a long reason ' * 3)));
      final h = await Harness.start(tester, audio: audio, theme: theme);
      await h.goTo(AppScreen.phones);
      expect(tester.takeException(), isNull);
      expect(key('phones-row-B0'), findsOneWidget);
      expect(text(tester, 'phones-status-B0'), 'Last connected · not connected now');
      expectTouchTargets(tester, 'phones, long names');
    }
  });

  testWidgets('without the crossover running, Media says so', (tester) async {
    final audio = FakeAudio()
      ..value = up(const AudioReport(phone: phone, dsp: DspPhase.notRunning, dspDetail: 'pipewire stopped'));
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.media);
    expect(find.text('NO CROSSOVER'), findsOneWidget);
  });

  testWidgets('alerts stay visible on the Media screen', (tester) async {
    final h = await Harness.start(tester, scenario: 'eot_ect_freeze');
    await h.goTo(AppScreen.media);
    await h.advance(const Duration(seconds: 200));
    expect(find.byKey(const ValueKey('alert-banner')), findsOneWidget);
  });

  testWidgets('Phones opens from Media: paired phones, the last one first, Connect', (tester) async {
    final audio = SimulatedAudioSource(autoRun: false);
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.media);
    expect(tester.getRect(key('media-next')).right, greaterThan(760), reason: 'Media is the full width');
    await tester.tap(key('media-phones'));
    await tester.pump();
    expect(h.services.screens.value, AppScreen.phones);
    expect(text(tester, 'phones-status-02:00:00:00:00:01'), 'Connected');
    expect(text(tester, 'phones-status-02:00:00:00:00:03'), 'Paired · not connected');
    expect(key('phones-connect-02:00:00:00:00:01'), findsNothing, reason: 'already connected');
    expectTouchTargets(tester, 'phones');

    await tester.tap(key('phones-connect-02:00:00:00:00:03'));
    await tester.pump();
    await tester.pump();
    expect(text(tester, 'phones-status-02:00:00:00:00:03'), 'Connecting…');
    expect(text(tester, 'phones-detail'), 'Connecting to Old simulated phone…');
    expect(find.text('Connecting…'), findsWidgets);
    audio
      ..tick()
      ..tick();
    await tester.pump();
    expect(text(tester, 'phones-status-02:00:00:00:00:03'), 'Connected');
    // One phone at a time; the old one is now just paired.
    expect(text(tester, 'phones-status-02:00:00:00:00:01'), 'Paired · not connected');
    expect(key('phones-detail'), findsNothing);
    // The connected phone first.
    final rows = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('phones-row-'));
    expect(tester.getRect(rows.first).top, tester.getRect(key('phones-row-02:00:00:00:00:03')).top);

    // The link drops: the phone connected last is marked, first in the list.
    audio.disconnect();
    await tester.pump();
    expect(text(tester, 'phones-status-02:00:00:00:00:03'), 'Last connected · not connected now');
    expect(tester.getRect(key('phones-row-02:00:00:00:00:03')).top,
        lessThan(tester.getRect(key('phones-row-02:00:00:00:00:01')).top));

    // Back to Media.
    await tester.tap(find.byKey(const ValueKey('nav-back')));
    await tester.pump();
    expect(h.services.screens.value, AppScreen.media);
    expect(text(tester, 'media-explain'), 'Tap Phones to connect a paired phone or pair another.');
  });

  testWidgets('a connection that fails says why', (tester) async {
    final audio = SimulatedAudioSource(autoRun: false)..reachable = false;
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.phones);
    await tester.tap(key('phones-connect-02:00:00:00:00:03'));
    await tester.pump();
    audio
      ..tick()
      ..tick();
    await tester.pump();
    expect(text(tester, 'phones-detail'),
        'Couldn\'t connect to Old simulated phone: simulated: the phone didn\'t answer (out of range).');
    expect(text(tester, 'phones-status-02:00:00:00:00:01'), 'Connected', reason: 'the old phone stays');
  });

  testWidgets('audio-manager reconnecting the last phone by itself is shown', (tester) async {
    final audio = FakeAudio()
      ..value = up(const AudioReport(
          known: [
            Phone(address: 'AA:01', name: 'Pixel 8', paired: true, last: true),
            Phone(address: 'AA:02', name: 'Old iPhone', paired: true),
          ],
          connect: ConnectStatus(address: 'AA:01', name: 'Pixel 8', automatic: true)));
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.media);
    expect(text(tester, 'media-headline'), 'Connecting to Pixel 8…');
    expect(text(tester, 'media-explain'), contains('trying it again by itself'));
    expect(find.text('Phones · connecting…'), findsOneWidget);
    await h.goTo(AppScreen.phones);
    expect(text(tester, 'phones-status-AA:01'), 'Reconnecting by itself…');
    expect(text(tester, 'phones-detail'), 'Trying Pixel 8 again by itself…');
    // While an attempt runs, no other one starts from here.
    await tester.tap(key('phones-connect-AA:02'));
    await tester.pump();
    expect(audio.calls, isEmpty);

    audio.value = up(const AudioReport(
        known: [
          Phone(address: 'AA:01', name: 'Pixel 8', paired: true, last: true),
          Phone(address: 'AA:02', name: 'Old iPhone', paired: true),
        ],
        connect: ConnectStatus(detail: 'Stopped trying to reach Pixel 8 after 5 min. Tap it to connect.')));
    await tester.pump();
    expect(text(tester, 'phones-detail'), 'Stopped trying to reach Pixel 8 after 5 min. Tap it to connect.');
    await tester.tap(key('phones-connect-AA:02'));
    await tester.pump();
    expect(audio.calls, ['connect AA:02']);
    await h.goTo(AppScreen.media);
    expect(text(tester, 'media-explain'), 'Stopped trying to reach Pixel 8 after 5 min. Tap it to connect.');
  });

  testWidgets('Settings → Speakers: sliders, steps, limits, Defaults at the bottom', (tester) async {
    final audio = SimulatedAudioSource(autoRun: false);
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.settings);
    await tester.tap(key('settings-speakers'));
    await tester.pump();
    await tester.pump();
    expect(text(tester, 'spk-fader'), 'Centre');
    expect(text(tester, 'spk-crossover'), '80 Hz');
    expect(text(tester, 'spk-note'), contains('examples'));
    expectTouchTargets(tester, 'speakers');
    for (final k in ['fader', 'balance', 'sub']) {
      final r = tester.getRect(key('spk-$k-slider'));
      expect(r.height, greaterThanOrEqualTo(kMinTouch - 0.01), reason: '$k: a 60 px touch target');
      expect(r.width, greaterThan(400), reason: '$k: the full width, no column beside it');
    }
    // Defaults below everything, at the bottom.
    expect(tester.getRect(key('spk-reset')).top, greaterThan(tester.getRect(key('spk-crossover-up')).bottom));

    // A real drag on the fader moves it to the front.
    await tester.drag(key('spk-fader-slider'), const Offset(400, 0));
    await tester.pump();
    await tester.pump();
    expect(text(tester, 'spk-fader'), startsWith('Front'));
    expect((await audio.getSpeakers()).settings.fader, greaterThan(0));

    // Exact values through the sliders' callbacks.
    Future<void> slide(String k, double v) async {
      tester.widget<Slider>(key('spk-$k-slider')).onChanged!(v);
      await tester.pump();
      await tester.pump();
    }

    await slide('fader', 1);
    expect(text(tester, 'spk-fader'), 'Front 1 (Rear −2 dB)');
    expect(text(tester, 'spk-message'), contains('not applied'));
    expect(text(tester, 'spk-note'), contains('examples'), reason: 'the note stays with a message');
    await slide('balance', -1);
    expect(text(tester, 'spk-balance'), 'Left 1 (Right −2 dB)');
    await slide('sub', 1);
    expect(text(tester, 'spk-sub'), '+1 dB');
    await slide('fader', 10);
    expect(text(tester, 'spk-fader'), 'Front 10 (Rear off)');
    await slide('fader', 1);
    await tester.tap(key('spk-crossover-up'));
    await tester.pump();
    await tester.pump();
    expect(text(tester, 'spk-crossover'), '90 Hz');
    final got = await audio.getSpeakers();
    expect(got.settings, const SpeakerSettings(fader: 1, balance: -1, subLevelDb: 1, crossoverHz: 90));
    // The crossover stops at its limit.
    for (var i = 0; i < 5; i++) {
      await tester.tap(key('spk-crossover-up'));
      await tester.pump();
      await tester.pump();
    }
    expect(text(tester, 'spk-crossover'), '120 Hz');
    await tester.tap(key('spk-reset'));
    await tester.pump();
    await tester.pump();
    expect(text(tester, 'spk-fader'), 'Centre');
    expect(text(tester, 'spk-crossover'), '80 Hz');
    expect((await audio.getSpeakers()).settings, const SpeakerSettings());
  });

  testWidgets('Settings → Speakers with an alert banner: scrolls, nothing squeezed', (tester) async {
    final h = await Harness.start(tester, scenario: 'eot_ect_freeze');
    await h.advance(const Duration(seconds: 200));
    await h.goTo(AppScreen.settings);
    await tester.tap(key('settings-speakers'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('alert-banner')), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.getRect(key('spk-fader-slider')).height, greaterThanOrEqualTo(kMinTouch - 0.01));
    await tester.scrollUntilVisible(key('spk-reset'), 50, scrollable: find.byType(Scrollable).last);
    expect(key('spk-reset'), findsOneWidget);
  });

  testWidgets('Settings → Speakers without audio-manager says so', (tester) async {
    final audio = FakeAudio()..value = const AudioStatus(link: AudioLink.down, detail: 'refused');
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.settings);
    await tester.tap(key('settings-speakers'));
    await tester.pump();
    expect(text(tester, 'spk-detail'), contains('audio-manager not connected (refused)'));
    // It reads them when audio-manager comes up.
    audio.value = up(const AudioReport());
    await tester.pump();
    await tester.pump();
    expect(text(tester, 'spk-fader'), 'Centre');
  });
}
