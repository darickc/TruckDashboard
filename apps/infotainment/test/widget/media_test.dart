import 'dart:async';

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

  @override
  Future<CommandResult> answerCall(int id) async {
    calls.add('answer $id');
    return const CommandResult(ok: true, detail: 'Answered.');
  }

  @override
  Future<CommandResult> hangUp(int id) async {
    calls.add('hang up $id');
    return const CommandResult(ok: false, detail: 'The phone didn\'t end the call: InvalidState.');
  }

  @override
  Future<CommandResult> setMicMuted(bool muted) async {
    calls.add('mute $muted');
    return const CommandResult(ok: true);
  }
  @override
  Future<CommandResult> dial(String number) async {
    calls.add('dial $number');
    return const CommandResult(ok: true);
  }

  @override
  Future<PhonebookData> phonebook() async => const PhonebookData();

  @override
  Future<CommandResult> refreshPhonebook() async => const CommandResult(ok: true);
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
  Future<CommandResult> disconnectPhone(String address) async {
    calls.add('disconnect $address');
    return const CommandResult(ok: true);
  }

  @override
  Future<CommandResult> forgetPhone(String address) async {
    calls.add('forget $address');
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

  /// Pictures asked for, answered when the test completes them.
  final pictures = <String, Completer<CoverArtImage?>>{};

  @override
  Future<CoverArtImage?> coverArt(String id) {
    calls.add('cover art $id');
    return (pictures[id] ??= Completer<CoverArtImage?>()).future;
  }

  /// What a volume change answers (above the cap).
  String volumeNote = '';

  @override
  Future<CommandResult> setVolume(VolumeChange c) async {
    calls.add('volume ${c.steps ?? c.level ?? c.mute?.name}');
    return CommandResult(ok: true, detail: volumeNote);
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

  testWidgets('cover art (ADR-0042): each track\'s picture, none for a track without one', (tester) async {
    final audio = SimulatedAudioSource(autoRun: false);
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.media);
    await tester.pump();
    expect(key('media-cover-art-1'), findsOneWidget);
    final size = tester.getSize(key('media-cover-art-1'));
    expect(size.width, size.height, reason: 'square');
    expect(size.width, greaterThanOrEqualTo(150), reason: 'big enough to see at a glance');
    await tester.tap(key('media-next'));
    await tester.pump();
    await tester.pump();
    expect(key('media-cover-art-1'), findsNothing, reason: 'never the last track\'s picture');
    expect(key('media-cover-art-2'), findsOneWidget);
    await tester.tap(key('media-next'));
    await tester.pump();
    await tester.pump();
    expect(key('media-cover-art-2'), findsNothing);
    expect(key('media-cover-none'), findsOneWidget);
    expect(text(tester, 'media-cover-why'), 'No picture for this track');
    expectTouchTargets(tester, 'media, no picture');
    audio.disconnect();
    await tester.pump();
    expect(key('media-cover-none'), findsNothing, reason: 'no track, no picture');
  });

  testWidgets('cover art: a picture that arrives after its track has gone is not shown', (tester) async {
    final audio = FakeAudio();
    AudioReport report(String id, String detail) => AudioReport(
          bluetoothReady: true,
          phone: phone,
          nowPlaying: NowPlaying(title: 'Track $id', state: PlayState.playing, coverArtId: id, coverArtDetail: detail),
        );
    // A completed future reaches the widget in a microtask, then a frame.
    Future<void> settle() async {
      await tester.pump();
      await tester.pump();
    }

    audio.value = up(report('a', ''));
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.media);
    await tester.pump();
    expect(audio.calls, contains('cover art a'));
    expect(key('media-cover-none'), findsOneWidget, reason: 'loading: the note, no words');
    expect(key('media-cover-why'), findsNothing);
    audio.value = up(report('b', ''));
    await tester.pump();
    audio.pictures['a']!.complete(CoverArtImage(bytes: simulatedCoverArt(0), mimeType: 'image/bmp'));
    await settle();
    expect(key('media-cover-art-a'), findsNothing, reason: 'track a has gone');
    audio.pictures['b']!.complete(CoverArtImage(bytes: simulatedCoverArt(1), mimeType: 'image/bmp'));
    await settle();
    expect(key('media-cover-art-b'), findsOneWidget);

    // No picture offered: why, from audio-manager.
    audio.value = up(report('', 'The phone doesn\'t offer cover art'));
    await tester.pump();
    expect(key('media-cover-art-b'), findsNothing);
    expect(text(tester, 'media-cover-why'), 'The phone doesn\'t offer cover art');

    // Gone by the time it is asked for (null): the note.
    audio.value = up(report('c', ''));
    await tester.pump();
    audio.pictures['c']!.complete(null);
    await settle();
    expect(key('media-cover-none'), findsOneWidget);
    expect(key('media-cover-art-c'), findsNothing);

    // audio-manager fails the call: said.
    audio.value = up(report('d', ''));
    await tester.pump();
    audio.pictures['d']!.completeError(StateError('audio-manager not connected'));
    await settle();
    expect(text(tester, 'media-cover-why'), contains('The picture didn\'t arrive'));
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
    h.services.phoneTab.value = PhoneTab.phones;
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
    h.services.phoneTab.value = PhoneTab.phones;
    await h.goTo(AppScreen.phones);
    expect(text(tester, 'phones-link'), contains('audio-manager not connected'));
    expect(key('phones-pair'), findsNothing);
  });

  testWidgets('a phone with no player: connected, no controls', (tester) async {
    final audio = FakeAudio()..value = up(const AudioReport(phone: phone, streaming: true));
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.media);
    expect(text(tester, 'media-headline'), 'Connected to Pixel 8');
    // The badges sit on their own line under the name, so they never cut it
    // short (redesign 2026-11-18; they once kept empty room beside it).
    expect(tester.getRect(key('media-streaming')).top, greaterThan(tester.getRect(key('media-source')).bottom));
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
    h.services.phoneTab.value = PhoneTab.phones;
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
    expect(text(tester, 'phones-status-02:00:00:00:00:01'), 'Not connected');
    expect(text(tester, 'phones-pairing'), 'Paired with Simulated phone 2.');
    expect(find.textContaining('Pair a phone'), findsOneWidget);
  });

  testWidgets('pairing window: refused, stopped by hand, and closing by itself', (tester) async {
    final audio = SimulatedAudioSource(autoRun: false, pairAfterTicks: 1);
    final h = await Harness.start(tester, audio: audio);
    h.services.phoneTab.value = PhoneTab.phones;
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
    h.services.phoneTab.value = PhoneTab.phones;
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
      h.services.phoneTab.value = PhoneTab.phones;
      await h.goTo(AppScreen.phones);
      expect(tester.takeException(), isNull);
      expect(key('phones-row-B0'), findsOneWidget);
      expect(text(tester, 'phones-status-B0'), 'Last used');
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

  testWidgets('volume (ADR-0043): −, +, mute on Media; the level shown over the screen for 2 s', (tester) async {
    final audio = SimulatedAudioSource(autoRun: false);
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.media);
    expect(text(tester, 'media-volume-level'), '15');
    expect(key('volume-overlay'), findsNothing, reason: 'not for the first report');
    expectTouchTargets(tester, 'media with the volume');

    await tester.tap(key('media-volume-up'));
    await tester.pump();
    expect(text(tester, 'media-volume-level'), '16');
    expect(key('volume-overlay'), findsNothing, reason: 'Media shows the level; the overlay would cover its buttons');
    await tester.tap(key('media-volume-down'));
    await tester.tap(key('media-volume-down'));
    await tester.pump();
    expect(text(tester, 'media-volume-level'), '14');

    await tester.tap(key('media-volume-mute'));
    await tester.pump();
    expect(text(tester, 'media-volume-level'), 'Muted');
    await tester.tap(key('media-volume-up'));
    await tester.pump();
    expect(text(tester, 'media-volume-level'), '15', reason: 'up unmutes');

    // Elsewhere, a change (the knob) shows the level for 2 s; the
    // simulation has no filter-chain, which it says.
    await h.goTo(AppScreen.home);
    await audio.setVolume(const VolumeChange.toggleMute());
    await tester.pump();
    expect(text(tester, 'volume-overlay-level'), 'Muted');
    await audio.setVolume(const VolumeChange.steps(1));
    await tester.pump();
    expect(text(tester, 'volume-overlay-level'), '16');
    expect(key('volume-overlay-not-applied'), findsOneWidget);
    // Gone 2 s after the last change, and the once-a-second update doesn't
    // bring it back.
    await tester.pump(const Duration(milliseconds: 1900));
    expect(key('volume-overlay'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(key('volume-overlay'), findsNothing);
    audio.tick();
    await tester.pump();
    expect(key('volume-overlay'), findsNothing);
  });

  testWidgets('volume: the knob shows the level on any screen, below the alert banner', (tester) async {
    final audio = SimulatedAudioSource(autoRun: false);
    final h = await Harness.start(tester, scenario: 'eot_ect_freeze', audio: audio);
    await h.goTo(AppScreen.gauges);
    await h.advance(const Duration(seconds: 200));
    final banner = find.byKey(const ValueKey('alert-banner'));
    expect(banner, findsOneWidget);
    // A change from elsewhere (the knob, through audio-manager).
    await audio.setVolume(const VolumeChange.steps(-3));
    await tester.pump();
    final overlay = key('volume-overlay');
    expect(overlay, findsOneWidget);
    expect(text(tester, 'volume-overlay-level'), '12');
    final o = tester.getRect(overlay), b = tester.getRect(banner);
    expect(o.top, greaterThanOrEqualTo(b.bottom), reason: 'never over the alert');
    expect(o.bottom, lessThanOrEqualTo(480));
    expect(banner.hitTestable(), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('volume: the cap is said; without a volume the buttons are off', (tester) async {
    final audio = FakeAudio()
      ..value = up(const AudioReport(
          phone: phone, volume: VolumeStatus(level: 24, max: 24, steps: 30, applied: true)))
      ..volumeNote = 'The maximum is 24 (configuration).';
    final h = await Harness.start(tester, audio: audio);
    await h.goTo(AppScreen.media);
    expect(text(tester, 'media-volume-level'), '24');
    expect(find.text('max'), findsOneWidget);
    await tester.tap(key('media-volume-up'));
    await tester.pump();
    expect(audio.calls, ['volume 1']);
    expect(text(tester, 'media-message'), 'The maximum is 24 (configuration).');
    await tester.tap(key('media-volume-mute'));
    await tester.pump();
    expect(audio.calls.last, 'volume toggle');

    // The cap mark on the level bar (on any screen but Media).
    await h.goTo(AppScreen.home);
    audio.value = up(const AudioReport(phone: phone, volume: VolumeStatus(level: 20, max: 24, steps: 30)));
    await tester.pump();
    expect(key('volume-overlay-cap'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await h.goTo(AppScreen.media);

    // An audio-manager without a volume: no level, nothing sent.
    audio.value = up(const AudioReport(phone: phone));
    await tester.pump();
    expect(text(tester, 'media-volume-level'), '—');
    audio.calls.clear();
    await tester.tap(key('media-volume-up'));
    await tester.pump();
    expect(audio.calls, isEmpty);
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
    // The volume ends the controls' row at the right edge (ADR-0043).
    expect(tester.getRect(key('media-volume-mute')).right, greaterThan(760), reason: 'Media is the full width');
    await tester.tap(key('media-phones'));
    await tester.pump();
    expect(h.services.screens.value, AppScreen.phones);
    expect(text(tester, 'phones-status-02:00:00:00:00:01'), 'Connected');
    expect(text(tester, 'phones-status-02:00:00:00:00:03'), 'Not connected');
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
    expect(text(tester, 'phones-status-02:00:00:00:00:01'), 'Not connected');
    expect(key('phones-detail'), findsNothing);
    // The connected phone first.
    final rows = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('phones-row-'));
    expect(tester.getRect(rows.first).top, tester.getRect(key('phones-row-02:00:00:00:00:03')).top);

    // The link drops: the phone connected last is marked, first in the list.
    audio.disconnect();
    await tester.pump();
    expect(text(tester, 'phones-status-02:00:00:00:00:03'), 'Last used');
    expect(tester.getRect(key('phones-row-02:00:00:00:00:03')).top,
        lessThan(tester.getRect(key('phones-row-02:00:00:00:00:01')).top));

    // Back to Media.
    await tester.tap(find.byKey(const ValueKey('nav-back')));
    await tester.pump();
    expect(h.services.screens.value, AppScreen.media);
    expect(text(tester, 'media-explain'), 'Tap Phones to connect a paired phone or pair another.');
  });

  testWidgets('Disconnect, and Delete asked again in the row', (tester) async {
    final audio = SimulatedAudioSource(autoRun: false);
    final h = await Harness.start(tester, audio: audio);
    h.services.phoneTab.value = PhoneTab.phones;
    await h.goTo(AppScreen.phones);
    expect(key('phones-connect-02:00:00:00:00:01'), findsNothing);
    expect(key('phones-disconnect-02:00:00:00:00:03'), findsNothing);
    expectTouchTargets(tester, 'phones, Disconnect and Delete');

    await tester.tap(key('phones-disconnect-02:00:00:00:00:01'));
    await tester.pump();
    await tester.pump();
    expect(text(tester, 'phones-status-02:00:00:00:00:01'), 'Last used');
    expect(key('phones-connect-02:00:00:00:00:01'), findsOneWidget);
    expect(key('media-title'), findsNothing);

    // Delete asks first; Keep leaves it.
    await tester.tap(key('phones-delete-02:00:00:00:00:03'));
    await tester.pump();
    expect(key('phones-confirm-02:00:00:00:00:03'), findsOneWidget);
    expect(find.text('Delete Old simulated phone?'), findsOneWidget);
    expect(find.text('Pair it again to use it.'), findsOneWidget);
    expectTouchTargets(tester, 'phones, confirm Delete');
    await tester.tap(key('phones-delete-no-02:00:00:00:00:03'));
    await tester.pump();
    expect(key('phones-confirm-02:00:00:00:00:03'), findsNothing);
    expect(key('phones-row-02:00:00:00:00:03'), findsOneWidget);
    // Delete, then yes: gone, and said.
    await tester.tap(key('phones-delete-02:00:00:00:00:03'));
    await tester.pump();
    await tester.tap(key('phones-delete-yes-02:00:00:00:00:03'));
    await tester.pump();
    await tester.pump();
    expect(key('phones-row-02:00:00:00:00:03'), findsNothing);
    expect(text(tester, 'phones-detail'), 'Deleted Old simulated phone. Pair it again to use it.');
  });

  testWidgets('Disconnect and Delete reach audio-manager', (tester) async {
    final audio = FakeAudio()
      ..value = up(const AudioReport(
          phone: Phone(address: 'AA:01', name: 'Pixel 8', connected: true, paired: true, last: true),
          known: [Phone(address: 'AA:02', name: 'Old iPhone', paired: true)]));
    final h = await Harness.start(tester, audio: audio);
    h.services.phoneTab.value = PhoneTab.phones;
    await h.goTo(AppScreen.phones);
    await tester.tap(key('phones-disconnect-AA:01'));
    await tester.pump();
    await tester.tap(key('phones-delete-AA:02'));
    await tester.pump();
    await tester.tap(key('phones-delete-yes-AA:02'));
    await tester.pump();
    expect(audio.calls, ['disconnect AA:01', 'forget AA:02']);
  });

  testWidgets('a connection that fails says why', (tester) async {
    final audio = SimulatedAudioSource(autoRun: false)..reachable = false;
    final h = await Harness.start(tester, audio: audio);
    h.services.phoneTab.value = PhoneTab.phones;
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
    h.services.phoneTab.value = PhoneTab.phones;
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
  group('layout (redesign 2026-11-18)', () {
    const playingReport = AudioReport(
      phone: phone,
      streaming: true,
      simulated: true,
      pausedForPrompt: true,
      volume: VolumeStatus(level: 15, max: 24, steps: 30, applied: true),
      nowPlaying: NowPlaying(
        title: 'A song with quite a long title that has to wrap onto two lines',
        artist: 'Band',
        album: 'Album',
        state: PlayState.playing,
        position: Duration(seconds: 18),
        duration: Duration(seconds: 185),
      ),
    );

    testWidgets('the source and track sit beside the picture; badges under the name', (tester) async {
      final audio = FakeAudio()..value = up(playingReport);
      final h = await Harness.start(tester, audio: audio);
      await h.goTo(AppScreen.media);
      final art = tester.getRect(key('media-cover-none'));
      expect(tester.getRect(key('media-source')).left, greaterThan(art.right));
      expect(tester.getRect(key('media-title')).left, greaterThan(art.right));
      expect(
        tester.getRect(key('media-directions')).top,
        greaterThan(tester.getRect(key('media-source')).bottom),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('transport: large buttons, play/pause the widest and marked', (tester) async {
      final audio = FakeAudio()..value = up(playingReport);
      final h = await Harness.start(tester, audio: audio);
      await h.goTo(AppScreen.media);
      expectTouchTargets(tester, 'media');
      final play = tester.getSize(key('media-play-pause'));
      expect(play.width, greaterThan(tester.getSize(key('media-next')).width));
      expect(play.height, greaterThanOrEqualTo(72));
      expect(tester.widget<TapTarget>(key('media-play-pause')).selected, isTrue);
      expect(tester.widget<TapTarget>(key('media-play-pause')).label, 'Pause');
    });

    testWidgets('Phones is an icon until something needs the driver', (tester) async {
      final audio = FakeAudio()..value = up(playingReport);
      final h = await Harness.start(tester, audio: audio);
      await h.goTo(AppScreen.media);
      expect(tester.getSize(key('media-phones')), const Size(kMinTouch, kMinTouch));
      expect(find.descendant(of: key('media-phones'), matching: find.byType(Text)), findsNothing);
      expect(tester.widget<TapTarget>(key('media-phones')).label, 'Phones');
      audio.value = up(
        const AudioReport(
          phone: phone,
          connect: ConnectStatus(address: 'b', name: 'Old'),
        ),
      );
      await tester.pump();
      expect(find.text('Phones · connecting…'), findsOneWidget);
    });

    testWidgets('the volume bar follows the level', (tester) async {
      final audio = FakeAudio()..value = up(playingReport);
      final h = await Harness.start(tester, audio: audio);
      await h.goTo(AppScreen.media);
      final track = tester.getSize(
        find.ancestor(of: key('media-volume-bar'), matching: find.byType(Stack)).first,
      );
      expect(tester.getSize(key('media-volume-bar')).width, closeTo(track.width * 15 / 30, 0.5));
    });

    for (final theme in DayNight.values) {
      testWidgets('lays out under an alert with every badge, ${theme.name}', (tester) async {
        final audio = FakeAudio()
          ..value = up(
            const AudioReport(
              phone: Phone(address: 'x', name: 'A phone with a very long name indeed', connected: true),
              streaming: true,
              pausedForPrompt: true,
              pairing: PairingStatus(phase: PairingPhase.open, secondsLeft: 90),
              volume: VolumeStatus(level: 0, max: 30, steps: 30, muted: true),
              nowPlaying: NowPlaying(title: 'T', state: PlayState.paused),
            ),
          );
        final h = await Harness.start(tester, scenario: 'link_loss', theme: theme, audio: audio);
        await h.advance(const Duration(seconds: 100));
        await h.goTo(AppScreen.media);
        expect(find.byKey(const ValueKey('alert-banner')), findsOneWidget);
        expect(tester.takeException(), isNull);
        expectTouchTargets(tester, 'media under an alert');
      });
    }
  });
}
