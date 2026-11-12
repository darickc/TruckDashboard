import 'dart:async';

import 'package:flutter/foundation.dart';

/// Bluetooth audio and the speaker settings (ADR-0039), as
/// services/audio-manager reports them over `f250.audio.v1`. The dashboard
/// shows and asks; it never talks to BlueZ or PipeWire (CLAUDE.md rule 5).
///
/// Honesty: a [AudioStatus.report] exists only while audio-manager is
/// connected and has been heard from in the last few seconds. Without one
/// nothing is shown as current: no phone, no track, no pairing window.

enum PlayState { unknown, stopped, playing, paused, forwardSeek, reverseSeek, error }

@immutable
class Phone {
  const Phone({required this.address, required this.name, this.connected = false, this.paired = false});

  final String address, name;
  final bool connected, paired;
}

@immutable
class NowPlaying {
  const NowPlaying({
    this.title = '',
    this.artist = '',
    this.album = '',
    this.state = PlayState.unknown,
    this.duration,
    this.position,
    this.playerName = '',
  });

  final String title, artist, album, playerName;
  final PlayState state;

  /// Null: the phone doesn't say.
  final Duration? duration;

  /// As of the report; null: unknown.
  final Duration? position;
}

enum PairingPhase { closed, opening, open, closing, failed }

@immutable
class PasskeyQuestion {
  const PasskeyQuestion({
    required this.id,
    required this.phoneName,
    required this.address,
    this.passkey,
    this.secondsLeft = 0,
  });

  final int id;
  final String phoneName, address;

  /// The six-digit code the phone shows; null: pairing without a code.
  final int? passkey;
  final int secondsLeft;

  String get code => passkey == null ? '' : passkey!.toString().padLeft(6, '0');
}

@immutable
class PairingStatus {
  const PairingStatus({
    this.phase = PairingPhase.closed,
    this.secondsLeft = 0,
    this.detail = '',
    this.question,
    this.name = '',
  });

  final PairingPhase phase;
  final int secondsLeft;
  final String detail;
  final PasskeyQuestion? question;

  /// The name phones see.
  final String name;

  bool get open => phase == PairingPhase.open || phase == PairingPhase.opening;
}

enum DspPhase { applied, starting, notRunning }

/// What audio-manager reported last.
@immutable
class AudioReport {
  const AudioReport({
    this.bluetoothReady = true,
    this.bluetoothDetail = '',
    this.phone,
    this.known = const [],
    this.nowPlaying,
    this.streaming = false,
    this.pairing = const PairingStatus(),
    this.dsp = DspPhase.notRunning,
    this.dspDetail = '',
    this.simulated = false,
    this.speaking = false,
    this.pausedForPrompt = false,
  });

  final bool bluetoothReady;
  final String bluetoothDetail;

  /// The connected phone.
  final Phone? phone;

  /// Paired, not connected.
  final List<Phone> known;

  /// The connected phone's player; never a gone phone's.
  final NowPlaying? nowPlaying;

  /// Audio is arriving from the phone.
  final bool streaming;
  final PairingStatus pairing;
  final DspPhase dsp;
  final String dspDetail;
  final bool simulated;

  /// A spoken direction is being said now.
  final bool speaking;

  /// audio-manager paused the phone for spoken directions and will resume it
  /// (ADR-0039 decision 9).
  final bool pausedForPrompt;
}

enum AudioLink { connecting, up, down }

@immutable
class AudioStatus {
  const AudioStatus({required this.link, this.report, this.detail});

  final AudioLink link;

  /// Null unless the link is up and current.
  final AudioReport? report;

  /// Why the link is down.
  final String? detail;
}

enum MediaCommand { play, pause, next, previous }

@immutable
class CommandResult {
  const CommandResult({required this.ok, this.detail = ''});

  final bool ok;
  final String detail;
}

@immutable
class SpeakerSettings {
  const SpeakerSettings({this.fader = 0, this.balance = 0, this.subLevelDb = 0, this.crossoverHz = 80});

  /// −steps (rear) … +steps (front).
  final int fader;

  /// −steps (left) … +steps (right).
  final int balance;
  final int subLevelDb;
  final int crossoverHz;

  SpeakerSettings copyWith({int? fader, int? balance, int? subLevelDb, int? crossoverHz}) =>
      SpeakerSettings(
        fader: fader ?? this.fader,
        balance: balance ?? this.balance,
        subLevelDb: subLevelDb ?? this.subLevelDb,
        crossoverHz: crossoverHz ?? this.crossoverHz,
      );

  @override
  bool operator ==(Object other) =>
      other is SpeakerSettings &&
      other.fader == fader &&
      other.balance == balance &&
      other.subLevelDb == subLevelDb &&
      other.crossoverHz == crossoverHz;

  @override
  int get hashCode => Object.hash(fader, balance, subLevelDb, crossoverHz);
}

/// audio-manager's configured limits: examples, not recommendations.
@immutable
class SpeakerLimits {
  const SpeakerLimits({
    this.steps = 10,
    this.stepDb = 2,
    this.subMinDb = -20,
    this.subMaxDb = 6,
    this.crossoverMinHz = 50,
    this.crossoverMaxHz = 120,
    this.crossoverStepHz = 10,
  });

  final int steps;
  final double stepDb;
  final int subMinDb, subMaxDb;
  final int crossoverMinHz, crossoverMaxHz, crossoverStepHz;

  /// Null when [s] is allowed, else why not.
  String? check(SpeakerSettings s) {
    if (s.fader.abs() > steps) return 'Fader ${s.fader} is outside ±$steps.';
    if (s.balance.abs() > steps) return 'Balance ${s.balance} is outside ±$steps.';
    if (s.subLevelDb < subMinDb || s.subLevelDb > subMaxDb) {
      return 'Sub level ${s.subLevelDb} dB is outside $subMinDb..$subMaxDb dB.';
    }
    if (s.crossoverHz < crossoverMinHz || s.crossoverHz > crossoverMaxHz) {
      return 'Crossover ${s.crossoverHz} Hz is outside $crossoverMinHz..$crossoverMaxHz Hz.';
    }
    return null;
  }
}

@immutable
class SpeakerSnapshot {
  const SpeakerSnapshot({required this.settings, required this.limits, required this.defaults});

  final SpeakerSettings settings, defaults;
  final SpeakerLimits limits;
}

/// services/audio-manager, or a simulation of it.
abstract class AudioSource {
  ValueListenable<AudioStatus> get status;
  void start();
  void stop();
  Future<CommandResult> control(MediaCommand c);

  /// [seconds] 0: audio-manager's default length.
  Future<CommandResult> openPairing([int seconds = 0]);
  Future<bool> closePairing();
  Future<CommandResult> confirm(int id, bool accept);
  Future<SpeakerSnapshot> getSpeakers();
  Future<CommandResult> setSpeakers(SpeakerSettings s);
}

/// A phone, a playlist and a pairing window that don't exist, for the
/// browser preview, `make ui` and the tests. Labelled SIMULATED on screen.
/// Time moves in [tick]s of one second (a timer when [autoRun]; tests call
/// [tick] themselves).
class SimulatedAudioSource implements AudioSource {
  SimulatedAudioSource({this.autoRun = true, this.pairAfterTicks = 5}) {
    _publish();
  }

  final bool autoRun;

  /// A second phone asks to pair this many ticks after the window opens;
  /// null: never.
  final int? pairAfterTicks;

  static const tracks = [
    NowPlaying(title: 'Simulated Track One', artist: 'The Test Tones', album: 'Not a Real Album', duration: Duration(seconds: 185)),
    NowPlaying(title: 'Second Simulated Song', artist: 'The Test Tones', album: 'Not a Real Album', duration: Duration(seconds: 242)),
    NowPlaying(title: 'A Third One', artist: 'Placeholder Band', album: 'Made Up', duration: Duration(seconds: 201)),
  ];
  static const passkey = 246810;
  static const windowSeconds = 120;

  Timer? _timer;
  bool _bluetooth = true;
  final _phones = <Phone>[
    const Phone(address: '02:00:00:00:00:01', name: 'Simulated phone', connected: true, paired: true),
  ];
  int _index = 0;
  int _positionS = 0;
  PlayState _play = PlayState.playing;
  PairingPhase _pairing = PairingPhase.closed;
  int _pairLeft = 0, _sinceOpen = 0, _nextId = 1;
  String _pairDetail = '';
  PasskeyQuestion? _question;
  SpeakerSettings _speakers = const SpeakerSettings();
  static const _limits = SpeakerLimits();

  final _status = ValueNotifier(const AudioStatus(link: AudioLink.connecting));

  @override
  ValueListenable<AudioStatus> get status => _status;

  Phone? get _connected => _phones.where((p) => p.connected).firstOrNull;

  void _publish() {
    final phone = _bluetooth ? _connected : null;
    final t = tracks[_index];
    _status.value = AudioStatus(
      link: AudioLink.up,
      report: AudioReport(
        simulated: true,
        bluetoothReady: _bluetooth,
        bluetoothDetail: _bluetooth ? '' : 'simulated: Bluetooth is off',
        phone: phone,
        known: _bluetooth ? _phones.where((p) => !p.connected).toList() : const [],
        nowPlaying: phone == null
            ? null
            : NowPlaying(
                title: t.title,
                artist: t.artist,
                album: t.album,
                duration: t.duration,
                state: _play,
                position: Duration(seconds: _positionS),
                playerName: 'Simulated player',
              ),
        streaming: phone != null && _play == PlayState.playing,
        pairing: PairingStatus(
          phase: _pairing,
          secondsLeft: _pairing == PairingPhase.open ? _pairLeft : 0,
          detail: _pairDetail,
          question: _question,
          name: 'F-250',
        ),
        dspDetail: 'simulated: no PipeWire',
      ),
    );
  }

  @override
  void start() {
    if (!autoRun || _timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// One second passes.
  void tick() {
    if (_play == PlayState.playing && _connected != null) {
      _positionS++;
      if (_positionS >= tracks[_index].duration!.inSeconds) {
        _index = (_index + 1) % tracks.length;
        _positionS = 0;
      }
    }
    if (_pairing == PairingPhase.open) {
      _pairLeft--;
      _sinceOpen++;
      if (_pairLeft <= 0) {
        _close('Closed by itself after $windowSeconds s.');
      } else if (_sinceOpen == pairAfterTicks && _question == null && _phones.length == 1) {
        _question = PasskeyQuestion(
            id: _nextId++, phoneName: 'Simulated phone 2', address: '02:00:00:00:00:02', passkey: passkey, secondsLeft: 30);
      }
    }
    _publish();
  }

  void _close(String why) {
    _pairing = PairingPhase.closed;
    _pairLeft = 0;
    _question = null;
    _pairDetail = why;
  }

  /// The phone drops the link.
  void disconnect() {
    for (var i = 0; i < _phones.length; i++) {
      final p = _phones[i];
      _phones[i] = Phone(address: p.address, name: p.name, paired: p.paired);
    }
    _publish();
  }

  /// The first paired phone connects again.
  void connect() {
    final p = _phones.first;
    _phones[0] = Phone(address: p.address, name: p.name, paired: true, connected: true);
    _publish();
  }

  /// Bluetooth goes away (or comes back); the window closes.
  void setBluetooth(bool on) {
    _bluetooth = on;
    if (!on) _close('Bluetooth stopped: the pairing window is closed.');
    _publish();
  }

  @override
  Future<CommandResult> control(MediaCommand c) async {
    if (!_bluetooth || _connected == null) {
      return const CommandResult(ok: false, detail: 'No phone is connected.');
    }
    switch (c) {
      case MediaCommand.play:
        _play = PlayState.playing;
      case MediaCommand.pause:
        _play = PlayState.paused;
      case MediaCommand.next:
        _index = (_index + 1) % tracks.length;
        _positionS = 0;
      case MediaCommand.previous:
        if (_positionS < 3) _index = (_index + tracks.length - 1) % tracks.length;
        _positionS = 0;
    }
    _publish();
    return const CommandResult(ok: true);
  }

  @override
  Future<CommandResult> openPairing([int seconds = 0]) async {
    if (!_bluetooth) {
      return const CommandResult(ok: false, detail: 'Bluetooth is unavailable: the pairing window can\'t open.');
    }
    _pairing = PairingPhase.open;
    _pairLeft = seconds > 0 ? seconds : windowSeconds;
    _sinceOpen = 0;
    _pairDetail = '';
    _publish();
    return const CommandResult(ok: true);
  }

  @override
  Future<bool> closePairing() async {
    if (!_pairing.isOpenish) return false;
    _close('Closed.');
    _publish();
    return true;
  }

  @override
  Future<CommandResult> confirm(int id, bool accept) async {
    final q = _question;
    if (q == null || q.id != id) {
      return const CommandResult(ok: false, detail: 'That question has already gone.');
    }
    _question = null;
    if (accept) {
      for (var i = 0; i < _phones.length; i++) {
        final p = _phones[i];
        _phones[i] = Phone(address: p.address, name: p.name, paired: true);
      }
      _phones.add(Phone(address: q.address, name: q.phoneName, paired: true, connected: true));
      _close('Paired with ${q.phoneName}.');
    } else {
      _pairDetail = 'Refused ${q.phoneName}.';
    }
    _publish();
    return const CommandResult(ok: true);
  }

  @override
  Future<SpeakerSnapshot> getSpeakers() async =>
      SpeakerSnapshot(settings: _speakers, limits: _limits, defaults: const SpeakerSettings());

  @override
  Future<CommandResult> setSpeakers(SpeakerSettings s) async {
    final why = _limits.check(s);
    if (why != null) return CommandResult(ok: false, detail: why);
    _speakers = s;
    return const CommandResult(ok: true, detail: 'Saved, not applied: simulated: no PipeWire.');
  }
}

extension on PairingPhase {
  bool get isOpenish => this == PairingPhase.open || this == PairingPhase.opening;
}

/// `m:ss` (or `h:mm:ss`).
String formatTrackTime(Duration d) {
  final s = d.inSeconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}
