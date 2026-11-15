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
  const Phone({
    required this.address,
    required this.name,
    this.connected = false,
    this.paired = false,
    this.last = false,
  });

  final String address, name;
  final bool connected, paired;

  /// The phone connected most recently: audio-manager reconnects it by
  /// itself for a while (at start, and after the link drops).
  final bool last;
}

/// A connection to a paired phone being tried (the driver's choice, or
/// audio-manager reconnecting the last phone by itself), and how the last
/// one went.
@immutable
class ConnectStatus {
  const ConnectStatus({this.address = '', this.name = '', this.automatic = false, this.detail = ''});

  /// The phone being connected now; empty: none.
  final String address, name;
  final bool automatic;

  /// What happened last; may be empty.
  final String detail;

  bool get busy => address.isNotEmpty;
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
    this.coverArtId = '',
    this.coverArtDetail = '',
  });

  final String title, artist, album, playerName;
  final PlayState state;

  /// Null: the phone doesn't say.
  final Duration? duration;

  /// As of the report; null: unknown.
  final Duration? position;

  /// The track's picture, for [AudioSource.coverArt] (ADR-0042). Empty: no
  /// picture for this track. A new track gets a new id.
  final String coverArtId;

  /// Why there is no picture ("The phone doesn't offer cover art"); empty
  /// while there is one.
  final String coverArtDetail;
}

/// A track's picture as the phone sent it.
@immutable
class CoverArtImage {
  const CoverArtImage({required this.bytes, required this.mimeType});
  final Uint8List bytes;
  final String mimeType;
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

/// The master volume (ADR-0043): a gain in the speakers' filter-chain.
@immutable
class VolumeStatus {
  const VolumeStatus({
    required this.level,
    required this.max,
    required this.steps,
    this.muted = false,
    this.applied = true,
    this.detail = '',
  });

  /// 0 ..= [max].
  final int level;

  /// The cap (configuration): the driver can't go above it.
  final int max;

  /// The top step (0 dB).
  final int steps;

  /// The level is kept while muted.
  final bool muted;

  /// False: kept and shown, not reaching the speakers (no filter-chain).
  final bool applied;

  /// Why not applied.
  final String detail;

  @override
  bool operator ==(Object other) =>
      other is VolumeStatus &&
      other.level == level &&
      other.max == max &&
      other.steps == steps &&
      other.muted == muted &&
      other.applied == applied &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(level, max, steps, muted, applied, detail);
}

enum MuteAction { mute, unmute, toggle }

/// What the driver asks of the volume: one of steps, a level or mute.
@immutable
class VolumeChange {
  const VolumeChange.steps(int this.steps)
      : level = null,
        mute = null;
  const VolumeChange.level(int this.level)
      : steps = null,
        mute = null;
  const VolumeChange.toggleMute()
      : mute = MuteAction.toggle,
        steps = null,
        level = null;

  /// Up (positive, unmutes) or down.
  final int? steps;

  /// Set to this level (unmutes); above the cap: the cap.
  final int? level;
  final MuteAction? mute;
}

/// Where a call is (ADR-0045), as the phone reports it.
enum CallPhase { incoming, waiting, dialing, alerting, active, held, unknown }

/// One call on the connected phone.
@immutable
class PhoneCall {
  const PhoneCall({
    required this.id,
    required this.phase,
    this.number = '',
    this.name = '',
    this.withheld = false,
    this.active = Duration.zero,
    this.multiparty = false,
  });

  /// Names this call in [AudioSource.answerCall] and [AudioSource.hangUp].
  final int id;
  final CallPhase phase;

  /// As the phone gives them; empty: not given.
  final String number, name;

  /// The caller hid their number.
  final bool withheld;

  /// How long it has been active, as of the report.
  final Duration active;
  final bool multiparty;

  /// Ringing here: Answer (incoming only) or decline.
  bool get rings => phase == CallPhase.incoming || phase == CallPhase.waiting;

  /// Who it is, for the screen: the name, else the number, else why not.
  String get caller => name.isNotEmpty
      ? name
      : number.isNotEmpty
          ? number
          : withheld
              ? 'Number withheld'
              : 'Unknown caller';

  /// The number under a name; empty when the name is the number.
  String get secondLine => name.isNotEmpty && number.isNotEmpty ? number : '';
}

/// Calls on the connected phone, or why they stay on it.
@immutable
class CallsStatus {
  const CallsStatus({
    this.available = false,
    this.detail = '',
    this.call,
    this.otherCalls = 0,
    this.micMuted = false,
    this.phoneName = '',
  });

  /// Calls come to the head unit. False: [detail] says why not.
  final bool available;
  final String detail;

  /// The call to show (a ringing one first); null: none.
  final PhoneCall? call;

  /// Other calls on the phone (held, or the one behind a waiting call).
  final int otherCalls;
  final bool micMuted;
  final String phoneName;
}

/// Where the connected phone's lists are (ADR-0045 phase 2).
enum PhonebookPhase { none, loading, ready, failed, off }

/// The connected phone's contacts and recent calls, summarised in each
/// report; fetched whole with [AudioSource.phonebook] when [version]
/// changes.
@immutable
class PhonebookStatus {
  const PhonebookStatus({
    this.phase = PhonebookPhase.none,
    this.detail = '',
    this.version = 0,
    this.contacts = 0,
    this.recentCalls = 0,
  });

  final PhonebookPhase phase;

  /// Why they failed or are off.
  final String detail;
  final int version;
  final int contacts, recentCalls;
}

@immutable
class ContactNumber {
  const ContactNumber(this.number, [this.label = '']);

  final String number;

  /// "Mobile", "Home", "Work", "Other"; empty: not given.
  final String label;
}

@immutable
class Contact {
  const Contact(this.name, this.numbers);

  /// Empty: the phone has no name for it.
  final String name;
  final List<ContactNumber> numbers;

  /// The name, else the first number.
  String get title => name.isNotEmpty ? name : (numbers.firstOrNull?.number ?? '');
}

enum RecentKind { received, dialed, missed, unknown }

@immutable
class RecentCall {
  const RecentCall({this.name = '', this.number = '', this.kind = RecentKind.unknown, this.time});

  final String name, number;
  final RecentKind kind;

  /// The phone's own local time; null: not given.
  final DateTime? time;

  String get title => name.isNotEmpty
      ? name
      : number.isNotEmpty
          ? number
          : 'Number withheld';
}

/// The phone's lists as audio-manager last read them.
@immutable
class PhonebookData {
  const PhonebookData({this.version = 0, this.contacts = const [], this.recent = const []});

  final int version;

  /// By name.
  final List<Contact> contacts;

  /// Newest first.
  final List<RecentCall> recent;
}

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
    this.connect = const ConnectStatus(),
    this.volume,
    this.calls,
    this.phonebook,
    this.routingProblem = '',
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

  final ConnectStatus connect;

  /// The master volume; null from an audio-manager without one.
  final VolumeStatus? volume;

  /// Phone calls (ADR-0045); null from an audio-manager without them.
  final CallsStatus? calls;

  /// The phone's lists (ADR-0045 phase 2); null from an audio-manager
  /// without them.
  final PhonebookStatus? phonebook;

  /// Audio that should be playing (the call, the phone's music) left
  /// unlinked by PipeWire's session manager, said for the driver; empty:
  /// none seen (bench-log 2026-11-15).
  final String routingProblem;

  /// The call to show, if any.
  PhoneCall? get call => calls?.call;

  /// Every paired phone, the connected one first, then the last one, then
  /// by name.
  List<Phone> get paired {
    final others = [...known]..sort((a, b) {
        if (a.last != b.last) return a.last ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return [?phone, ...others];
  }
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

  /// Connects a paired phone (any other is disconnected first). Returns once
  /// the attempt has started; [AudioReport.connect] follows it.
  Future<CommandResult> connectPhone(String address);

  /// Disconnects the connected phone; it stays paired and isn't reconnected
  /// by itself.
  Future<CommandResult> disconnectPhone(String address);

  /// Forgets a paired phone: it has to be paired again to be used.
  Future<CommandResult> forgetPhone(String address);
  Future<SpeakerSnapshot> getSpeakers();
  Future<CommandResult> setSpeakers(SpeakerSettings s);

  /// The picture named [id] (NowPlaying.coverArtId); null when it is no
  /// longer the current track's.
  Future<CoverArtImage?> coverArt(String id);

  /// Changes the master volume (ADR-0043). [CommandResult.detail] says what
  /// wasn't as asked (above the cap); [AudioReport.volume] follows.
  Future<CommandResult> setVolume(VolumeChange c);

  /// Answers an incoming call (ADR-0045).
  Future<CommandResult> answerCall(int id);

  /// Declines a ringing call, or hangs up any other.
  Future<CommandResult> hangUp(int id);

  /// Mutes or unmutes the call microphone (during a call).
  Future<CommandResult> setMicMuted(bool muted);

  /// Calls [number] from the connected phone (ADR-0045 phase 2); the call
  /// then shows in [AudioReport.calls].
  Future<CommandResult> dial(String number);

  /// The connected phone's contacts and recent calls, as last read.
  Future<PhonebookData> phonebook();

  /// Reads them from the phone again; [AudioReport.phonebook] follows.
  Future<CommandResult> refreshPhonebook();
}

/// A phone, a playlist and a pairing window that don't exist, for the
/// browser preview, `make ui` and the tests. Labelled SIMULATED on screen.
/// Time moves in [tick]s of one second (a timer when [autoRun]; tests call
/// [tick] themselves).
class SimulatedAudioSource implements AudioSource {
  SimulatedAudioSource({
    this.autoRun = true,
    this.pairAfterTicks = 5,
    this.connectTicks = 2,
    this.ringEveryTicks,
  }) {
    _publish();
  }

  /// A made-up call rings this many ticks after start and after each call
  /// ends; null: only when [ring] is called.
  final int? ringEveryTicks;

  static const simCaller = 'Simulated Caller';
  static const simNumber = '+15550100';

  /// A connection asked for takes this many ticks.
  final int connectTicks;

  /// The phones answer a connection (in range).
  bool reachable = true;

  final bool autoRun;

  /// A second phone asks to pair this many ticks after the window opens;
  /// null: never.
  final int? pairAfterTicks;

  /// The third track has no picture, like a track a phone has none for.
  static const tracks = [
    NowPlaying(title: 'Simulated Track One', artist: 'The Test Tones', album: 'Not a Real Album', duration: Duration(seconds: 185), coverArtId: '1'),
    NowPlaying(title: 'Second Simulated Song', artist: 'The Test Tones', album: 'Not a Real Album', duration: Duration(seconds: 242), coverArtId: '2'),
    NowPlaying(title: 'A Third One', artist: 'Placeholder Band', album: 'Made Up', duration: Duration(seconds: 201), coverArtDetail: 'No picture for this track'),
  ];
  static const passkey = 246810;
  static const windowSeconds = 120;

  Timer? _timer;
  bool _bluetooth = true;
  final _phones = <Phone>[
    const Phone(address: '02:00:00:00:00:01', name: 'Simulated phone', connected: true, paired: true),
    const Phone(address: '02:00:00:00:00:03', name: 'Old simulated phone', paired: true),
  ];
  String _lastAddress = '02:00:00:00:00:01';
  Phone? _connecting;
  int _connectLeft = 0;
  String _connectDetail = '';
  int _index = 0;
  int _positionS = 0;
  PlayState _play = PlayState.playing;
  PairingPhase _pairing = PairingPhase.closed;
  int _pairLeft = 0, _sinceOpen = 0, _nextId = 1;
  String _pairDetail = '';
  PasskeyQuestion? _question;
  SpeakerSettings _speakers = const SpeakerSettings();
  static const _limits = SpeakerLimits();

  /// audio-manager's example volume: 30 steps, no cap, starting at 15.
  static const volumeSteps = 30;
  int _volume = 15;
  bool _muted = false;

  final _calls = <PhoneCall>[];
  int _nextCallId = 1, _sinceCall = 0;

  /// Ticks since each dialled call was placed.
  final _dialled = <int, int>{};

  /// A dialled call rings at the other end after this many ticks, and is
  /// answered this many after placing it.
  static const dialAlertingTicks = 1, dialAnsweredTicks = 4;

  /// The phone's lists: read again ([_bookLoading]) for a tick.
  int _bookVersion = 1;
  bool _bookLoading = false;
  String? _bookFor;

  /// The same made-up lists as audio-manager's simulated phone.
  static const simContacts = [
    Contact('Alex Rivera', [ContactNumber('+1 555 010 1001', 'Mobile'), ContactNumber('+1 555 010 2001', 'Work')]),
    Contact('Blake Chen', [ContactNumber('555-010-1002', 'Mobile')]),
    Contact('Casey Morgan', [ContactNumber('555-010-1003', 'Home')]),
    Contact('Dana Brooks', [ContactNumber('555-010-1004', 'Mobile')]),
    Contact('Ellis Parts & Service', [ContactNumber('555-010-1005', 'Work')]),
    Contact('Frankie Diaz', [ContactNumber('555-010-1006', 'Mobile')]),
    Contact("Gray's Towing", [ContactNumber('555-010-1007', 'Work')]),
    Contact('Harper Lee', [ContactNumber('555-010-1008', 'Mobile')]),
    Contact('Jordan Kim', [ContactNumber('555-010-1009', 'Mobile'), ContactNumber('555-010-2009', 'Home')]),
    Contact('Morgan Feed & Supply', [ContactNumber('555-010-1010', 'Work')]),
    Contact('Quinn Taylor', [ContactNumber('555-010-1011', 'Mobile')]),
    Contact('Riley Novak', [ContactNumber('555-010-1012', 'Mobile')]),
    Contact('Sam Ortiz', [ContactNumber('555-010-1013', 'Mobile')]),
    Contact('Taylor Diesel Repair', [ContactNumber('555-010-1014', 'Work')]),
    Contact('Whitney Hale', [ContactNumber('555-010-1015', 'Mobile')]),
  ];
  static final simRecent = [
    RecentCall(name: 'Blake Chen', number: '555-010-1002', kind: RecentKind.missed, time: DateTime(2026, 11, 14, 8, 15)),
    RecentCall(number: '555-010-9999', kind: RecentKind.received, time: DateTime(2026, 11, 13, 17, 10)),
    RecentCall(name: 'Taylor Diesel Repair', number: '555-010-1014', kind: RecentKind.dialed, time: DateTime(2026, 11, 13, 9, 30)),
    RecentCall(name: 'Alex Rivera', number: '+15550101001', kind: RecentKind.received, time: DateTime(2026, 11, 12, 18, 45)),
  ];
  bool _micMuted = false, _pausedForCall = false;

  final _status = ValueNotifier(const AudioStatus(link: AudioLink.connecting));

  @override
  ValueListenable<AudioStatus> get status => _status;

  Phone? get _connected => _phones.where((p) => p.connected).firstOrNull;

  Phone _marked(Phone p) => Phone(
      address: p.address, name: p.name, connected: p.connected, paired: p.paired, last: p.address == _lastAddress);

  void _setConnected(String? address) {
    for (var i = 0; i < _phones.length; i++) {
      final p = _phones[i];
      _phones[i] = Phone(address: p.address, name: p.name, paired: p.paired, connected: p.address == address);
    }
    if (address != null) _lastAddress = address;
  }

  void _publish() {
    final c = _bluetooth ? _connected : null;
    final phone = c == null ? null : _marked(c);
    final t = tracks[_index];
    _status.value = AudioStatus(
      link: AudioLink.up,
      report: AudioReport(
        simulated: true,
        bluetoothReady: _bluetooth,
        bluetoothDetail: _bluetooth ? '' : 'simulated: Bluetooth is off',
        phone: phone,
        known: _bluetooth ? [for (final p in _phones.where((p) => !p.connected)) _marked(p)] : const [],
        connect: ConnectStatus(
          address: _connecting?.address ?? '',
          name: _connecting?.name ?? '',
          detail: _connectDetail,
        ),
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
                coverArtId: t.coverArtId,
                coverArtDetail: t.coverArtDetail,
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
        volume: VolumeStatus(
          level: _volume,
          max: volumeSteps,
          steps: volumeSteps,
          muted: _muted,
          applied: false,
          detail: 'Not applied: simulated: no PipeWire.',
        ),
        calls: _callsStatus(phone),
        phonebook: _bookStatus(phone),
      ),
    );
  }

  PhonebookStatus _bookStatus(Phone? phone) {
    if (phone == null) {
      _bookFor = null;
      return const PhonebookStatus();
    }
    if (_bookFor != phone.address) {
      _bookFor = phone.address;
      _bookVersion++;
    }
    return PhonebookStatus(
      phase: _bookLoading ? PhonebookPhase.loading : PhonebookPhase.ready,
      version: _bookVersion,
      contacts: simContacts.length,
      recentCalls: simRecent.length,
    );
  }

  @override
  Future<PhonebookData> phonebook() async => _connected == null || !_bluetooth
      ? PhonebookData(version: _bookVersion)
      : PhonebookData(version: _bookVersion, contacts: simContacts, recent: simRecent);

  @override
  Future<CommandResult> refreshPhonebook() async {
    if (_connected == null) return const CommandResult(ok: false, detail: 'No phone is connected.');
    _bookLoading = true;
    _publish();
    return const CommandResult(ok: true, detail: 'Reading the phone\'s contacts…');
  }

  /// The contact [number] belongs to, as audio-manager names a call the
  /// phone gives no name for (phonebook::name_for): the same digits, or one
  /// ending with the other when the shorter has at least 7.
  static String nameFor(List<Contact> contacts, String number) {
    String digits(String n) => n.replaceAll(RegExp(r'[^0-9]'), '');
    final want = digits(number);
    if (want.isEmpty) return '';
    bool same(String n) {
      final have = digits(n);
      if (have == want) return true;
      final (short, long) = have.length < want.length ? (have, want) : (want, have);
      return short.length >= 7 && long.endsWith(short);
    }

    return contacts.where((c) => c.name.isNotEmpty && c.numbers.any((n) => same(n.number))).firstOrNull?.name ?? '';
  }

  /// What audio-manager accepts: digits, a leading +, * and #; spaces,
  /// dashes, dots, slashes and brackets dropped (phonebook::dial_number).
  static String? cleanNumber(String s) {
    final out = StringBuffer();
    final t = s.trim();
    for (var i = 0; i < t.length; i++) {
      final c = t[i];
      if ('0123456789*#'.contains(c) || (c == '+' && i == 0)) {
        out.write(c);
      } else if (!' -./()'.contains(c)) {
        return null;
      }
    }
    final n = out.toString();
    return n.contains(RegExp(r'[0-9]')) && n.length <= 80 ? n : null;
  }

  @override
  Future<CommandResult> dial(String number) async {
    final n = cleanNumber(number);
    if (n == null) return const CommandResult(ok: false, detail: 'That isn\'t a number to call.');
    if (_connected == null) return const CommandResult(ok: false, detail: 'No phone is connected.');
    if (_calls.isNotEmpty) {
      return const CommandResult(ok: false, detail: 'A call is in progress: hang it up first.');
    }
    if (_play == PlayState.playing) {
      _play = PlayState.paused;
      _pausedForCall = true;
    }
    final c = PhoneCall(id: _nextCallId++, phase: CallPhase.dialing, number: n, name: nameFor(simContacts, n));
    _calls.add(c);
    _dialled[c.id] = 0;
    _publish();
    return const CommandResult(ok: true, detail: 'Calling…');
  }

  CallsStatus _callsStatus(Phone? phone) {
    if (phone == null) return const CallsStatus(detail: 'No phone is connected.');
    final shown = [..._calls]..sort((a, b) => _rank(a.phase).compareTo(_rank(b.phase)));
    return CallsStatus(
      available: true,
      call: shown.firstOrNull,
      otherCalls: shown.isEmpty ? 0 : shown.length - 1,
      micMuted: _micMuted && _calls.isNotEmpty,
      phoneName: phone.name,
    );
  }

  static int _rank(CallPhase p) => switch (p) {
        CallPhase.incoming => 0,
        CallPhase.waiting => 1,
        CallPhase.active => 2,
        CallPhase.dialing || CallPhase.alerting => 3,
        CallPhase.held => 4,
        CallPhase.unknown => 5,
      };

  PhoneCall _with(PhoneCall c, {CallPhase? phase, Duration? active}) => PhoneCall(
      id: c.id,
      phase: phase ?? c.phase,
      number: c.number,
      name: c.name,
      withheld: c.withheld,
      active: active ?? c.active,
      multiparty: c.multiparty);

  /// A call rings on the simulated phone: incoming, or waiting during
  /// another. Returns its id.
  int ring({String number = simNumber, String name = simCaller}) {
    final busy = _calls.any((c) => !c.rings);
    if (_calls.isEmpty && _play == PlayState.playing) {
      _play = PlayState.paused;
      _pausedForCall = true;
    }
    final c = PhoneCall(
        id: _nextCallId++,
        phase: busy ? CallPhase.waiting : CallPhase.incoming,
        number: number,
        name: name,
        withheld: number.isEmpty);
    _calls.add(c);
    _publish();
    return c.id;
  }

  /// The far end hangs up.
  void endCall(int id) {
    _calls.removeWhere((c) => c.id == id);
    _dialled.remove(id);
    if (_calls.isNotEmpty && !_calls.any((c) => c.phase == CallPhase.active)) {
      final i = _calls.indexWhere((c) => c.phase == CallPhase.held);
      if (i >= 0) _calls[i] = _with(_calls[i], phase: CallPhase.active);
    }
    if (_calls.isEmpty) {
      _micMuted = false;
      _sinceCall = 0;
      // The call is in the phone's history now.
      _bookVersion++;
      if (_pausedForCall && _play == PlayState.paused) _play = PlayState.playing;
      _pausedForCall = false;
    }
    _publish();
  }

  @override
  Future<CommandResult> answerCall(int id) async {
    final i = _calls.indexWhere((c) => c.id == id);
    if (i < 0) return const CommandResult(ok: false, detail: 'That call has ended.');
    if (_calls[i].phase == CallPhase.waiting) {
      return const CommandResult(ok: false, detail: 'Another call is in progress: answer this one on the phone.');
    }
    if (_calls[i].phase != CallPhase.incoming) {
      return const CommandResult(ok: false, detail: 'That call isn\'t ringing.');
    }
    _calls[i] = _with(_calls[i], phase: CallPhase.active);
    _publish();
    return const CommandResult(ok: true, detail: 'Answered.');
  }

  @override
  Future<CommandResult> hangUp(int id) async {
    final c = _calls.where((c) => c.id == id).firstOrNull;
    if (c == null) return const CommandResult(ok: false, detail: 'That call has ended.');
    endCall(id);
    return CommandResult(ok: true, detail: c.rings ? 'Declined.' : 'Hung up.');
  }

  @override
  Future<CommandResult> setMicMuted(bool muted) async {
    if (_calls.isEmpty) return const CommandResult(ok: false, detail: 'There is no call.');
    _micMuted = muted;
    _publish();
    return const CommandResult(ok: true);
  }

  @override
  Future<CommandResult> setVolume(VolumeChange c) async {
    var note = '';
    final steps = c.steps, level = c.level, mute = c.mute;
    if (steps != null) {
      _volume = (_volume + steps).clamp(0, volumeSteps);
      if (steps > 0) _muted = false;
    } else if (level != null) {
      _volume = level.clamp(0, volumeSteps);
      if (level > volumeSteps) note = 'The maximum is $volumeSteps (configuration).';
      _muted = false;
    } else if (mute != null) {
      _muted = switch (mute) {
        MuteAction.mute => true,
        MuteAction.unmute => false,
        MuteAction.toggle => !_muted,
      };
    }
    _publish();
    return CommandResult(ok: true, detail: note);
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
    _bookLoading = false;
    for (var i = 0; i < _calls.length; i++) {
      final c = _calls[i];
      if (c.phase == CallPhase.active) {
        _calls[i] = _with(c, active: c.active + const Duration(seconds: 1));
      }
      final since = _dialled[c.id];
      if (since != null) {
        _dialled[c.id] = since + 1;
        if (since + 1 == dialAlertingTicks) _calls[i] = _with(_calls[i], phase: CallPhase.alerting);
        if (since + 1 >= dialAnsweredTicks) {
          _calls[i] = _with(_calls[i], phase: CallPhase.active);
          _dialled.remove(c.id);
        }
      }
    }
    final every = ringEveryTicks;
    if (every != null && _calls.isEmpty && _connected != null && ++_sinceCall >= every) {
      _sinceCall = 0;
      ring();
    }
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
      } else if (_sinceOpen == pairAfterTicks &&
          _question == null &&
          !_phones.any((p) => p.address == '02:00:00:00:00:02')) {
        _question = PasskeyQuestion(
            id: _nextId++, phoneName: 'Simulated phone 2', address: '02:00:00:00:00:02', passkey: passkey, secondsLeft: 30);
      }
    }
    final c = _connecting;
    if (c != null && --_connectLeft <= 0) {
      _connecting = null;
      if (reachable && _bluetooth) {
        _setConnected(c.address);
        _positionS = 0;
      } else {
        _connectDetail = 'Couldn\'t connect to ${c.name}: simulated: the phone didn\'t answer (out of range).';
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
    _setConnected(null);
    _publish();
  }

  /// The first paired phone connects again (by itself).
  void connect() {
    _setConnected(_phones.first.address);
    _publish();
  }

  @override
  Future<CommandResult> disconnectPhone(String address) async {
    final p = _phones.where((p) => p.address == address).firstOrNull;
    if (p == null) return const CommandResult(ok: false, detail: 'That phone isn\'t paired.');
    if (!p.connected) return CommandResult(ok: false, detail: '${p.name} isn\'t connected.');
    _setConnected(null);
    _publish();
    return CommandResult(ok: true, detail: 'Disconnecting ${p.name}…');
  }

  @override
  Future<CommandResult> forgetPhone(String address) async {
    final p = _phones.where((p) => p.address == address).firstOrNull;
    if (p == null) return const CommandResult(ok: false, detail: 'That phone isn\'t paired.');
    _phones.removeWhere((x) => x.address == address);
    if (_lastAddress == address) _lastAddress = '';
    _connectDetail = 'Deleted ${p.name}. Pair it again to use it.';
    _publish();
    return CommandResult(ok: true, detail: 'Deleting ${p.name}…');
  }

  @override
  Future<CommandResult> connectPhone(String address) async {
    if (!_bluetooth) return const CommandResult(ok: false, detail: 'Bluetooth is unavailable.');
    final p = _phones.where((p) => p.paired && p.address == address).firstOrNull;
    if (p == null) return const CommandResult(ok: false, detail: 'That phone isn\'t paired.');
    if (p.connected) return CommandResult(ok: false, detail: '${p.name} is already connected.');
    if (_connecting != null) return CommandResult(ok: false, detail: 'Already connecting to ${_connecting!.name}.');
    _connecting = p;
    _connectLeft = connectTicks;
    _connectDetail = '';
    _publish();
    return CommandResult(ok: true, detail: 'Connecting to ${p.name}…');
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
    // The driver's own choice: not resumed after a call.
    _pausedForCall = false;
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
      _setConnected(null);
      _phones.add(Phone(address: q.address, name: q.phoneName, paired: true));
      _setConnected(q.address);
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

  final _pictures = <String, CoverArtImage>{};

  @override
  Future<CoverArtImage?> coverArt(String id) async {
    final c = _bluetooth ? _connected : null;
    final t = tracks[_index];
    if (c == null || id.isEmpty || t.coverArtId != id) return null;
    return _pictures[id] ??=
        CoverArtImage(bytes: simulatedCoverArt(tracks.indexOf(t)), mimeType: 'image/bmp');
  }
}

/// A made-up picture for a simulated track: a 200×200 BMP (no image
/// library needed), a record on a gradient in the track's colours. The same
/// drawing as audio-manager's simulated phone (`sim.rs`, `sim_picture`).
Uint8List simulatedCoverArt(int seed) {
  const w = 200;
  const palette = [
    ([0x1d, 0x4e, 0x89], [0x5d, 0xad, 0xe2]),
    ([0x8e, 0x2c, 0x1f], [0xf0, 0x9a, 0x3e]),
    ([0x1e, 0x6b, 0x3a], [0xb8, 0xd8, 0x5a]),
  ];
  final (a, b) = palette[seed % palette.length];
  const row = w * 3;
  const size = 54 + row * w;
  final out = ByteData(size);
  void u16(int o, int v) => out.setUint16(o, v, Endian.little);
  void u32(int o, int v) => out.setUint32(o, v, Endian.little);
  out.setUint8(0, 0x42); // B
  out.setUint8(1, 0x4D); // M
  u32(2, size);
  u32(10, 54);
  u32(14, 40);
  u32(18, w);
  u32(22, w); // bottom-up
  u16(26, 1);
  u16(28, 24);
  u32(34, row * w);
  u32(38, 2835);
  u32(42, 2835);
  int mix(int x, int y, int t) => (x * (2 * w - t) + y * t) ~/ (2 * w);
  const c = w ~/ 2;
  var o = 54;
  for (var y = 0; y < w; y++) {
    for (var x = 0; x < w; x++) {
      final t = x + y;
      var px = [mix(a[0], b[0], t), mix(a[1], b[1], t), mix(a[2], b[2], t)];
      final d2 = (x - c) * (x - c) + (y - c) * (y - c);
      if (d2 >= 14 * 14 && d2 < 70 * 70) {
        final g = (d2 ~/ 150) % 3 == 0 ? 0x30 : 0x18;
        px = [g, g, g];
      } else if (d2 >= 3 * 3 && d2 < 14 * 14) {
        px = b;
      }
      // BMP is blue, green, red.
      out.setUint8(o++, px[2]);
      out.setUint8(o++, px[1]);
      out.setUint8(o++, px[0]);
    }
  }
  return out.buffer.asUint8List();
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
