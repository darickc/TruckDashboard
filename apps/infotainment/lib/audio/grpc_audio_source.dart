import 'dart:async';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';

import '../data/gateway_connection.dart';
import '../gen/f250/audio/v1/audio.pbgrpc.dart' as pb;
import 'audio_state.dart';

AudioSource createGrpcAudioSource(GatewayEndpoint endpoint) => GrpcAudioSource(endpoint: endpoint);

/// services/audio-manager over gRPC (`f250.audio.v1`, ADR-0039). Reconnects
/// on its own. audio-manager sends at least once a second; after
/// [silentAfter] with nothing the link counts as down and nothing is shown
/// as current (no phone, no track, no pairing window).
class GrpcAudioSource implements AudioSource {
  GrpcAudioSource({
    required this.endpoint,
    this.retryDelay = const Duration(seconds: 1),
    this.callTimeout = const Duration(seconds: 5),
    this.silentAfter = const Duration(seconds: 3),
  });

  final GatewayEndpoint endpoint;
  final Duration retryDelay, callTimeout, silentAfter;

  ClientChannel? _channel;
  pb.AudioServiceClient? _client;
  StreamSubscription<pb.WatchAudioResponse>? _stream;
  Timer? _retry, _silence;
  bool _running = false;

  final _status = ValueNotifier(const AudioStatus(link: AudioLink.connecting));

  @override
  ValueListenable<AudioStatus> get status => _status;

  @override
  void start() {
    if (_running) return;
    _running = true;
    final (host, port) = switch (endpoint) {
      UnixEndpoint(:final path) => (InternetAddress(path, type: InternetAddressType.unix), 0),
      TcpEndpoint(:final host, :final port) => (host as Object, port),
    };
    _channel = ClientChannel(host, port: port, options: const ChannelOptions(credentials: ChannelCredentials.insecure()));
    _client = pb.AudioServiceClient(_channel!);
    _status.value = AudioStatus(link: AudioLink.connecting, detail: 'connecting to $endpoint');
    _connect();
  }

  @override
  void stop() {
    _running = false;
    _retry?.cancel();
    _silence?.cancel();
    _stream?.cancel();
    _channel?.shutdown();
    _stream = null;
    _channel = null;
    _client = null;
  }

  pb.AudioServiceClient _need() {
    final c = _client;
    if (c == null) throw StateError('audio-manager not connected');
    return c;
  }

  CallOptions get _opts => CallOptions(timeout: callTimeout);

  void _connect() {
    final client = _client;
    if (!_running || client == null) return;
    _armSilence();
    _stream = client.watchAudio(pb.WatchAudioRequest()).listen(
      (r) {
        _armSilence();
        _status.value = AudioStatus(link: AudioLink.up, report: reportFromPb(r));
      },
      onError: (Object e) => _down(e is GrpcError ? (e.message ?? e.codeName) : '$e'),
      onDone: () => _down('audio-manager ended the stream'),
    );
  }

  void _armSilence() {
    _silence?.cancel();
    _silence = Timer(silentAfter, () => _down('audio-manager stopped answering'));
  }

  void _down(String why) {
    _silence?.cancel();
    _stream?.cancel();
    _stream = null;
    if (!_running) return;
    _status.value = AudioStatus(link: AudioLink.down, detail: why);
    _retry?.cancel();
    _retry = Timer(retryDelay, _connect);
  }

  @override
  Future<CommandResult> control(MediaCommand c) async {
    final r = await _need().control(
      pb.ControlRequest(
        source: 'dashboard',
        command: switch (c) {
          MediaCommand.play => pb.Command.COMMAND_PLAY,
          MediaCommand.pause => pb.Command.COMMAND_PAUSE,
          MediaCommand.next => pb.Command.COMMAND_NEXT,
          MediaCommand.previous => pb.Command.COMMAND_PREVIOUS,
        },
      ),
      options: _opts,
    );
    return CommandResult(ok: r.sent, detail: r.detail);
  }

  @override
  Future<CommandResult> openPairing([int seconds = 0]) async {
    final r = await _need().openPairing(pb.OpenPairingRequest(seconds: seconds, source: 'dashboard'), options: _opts);
    return CommandResult(ok: r.accepted, detail: r.detail);
  }

  @override
  Future<bool> closePairing() async {
    final r = await _need().closePairing(pb.ClosePairingRequest(source: 'dashboard'), options: _opts);
    return r.closing;
  }

  @override
  Future<CommandResult> confirm(int id, bool accept) async {
    final r = await _need().confirmPairing(
      pb.ConfirmPairingRequest(id: Int64(id), accept: accept, source: 'dashboard'),
      options: _opts,
    );
    return CommandResult(ok: r.answered, detail: r.detail);
  }

  @override
  Future<CommandResult> connectPhone(String address) async {
    final r = await _need().connectPhone(pb.ConnectPhoneRequest(address: address, source: 'dashboard'), options: _opts);
    return CommandResult(ok: r.accepted, detail: r.detail);
  }

  @override
  Future<CommandResult> disconnectPhone(String address) async {
    final r = await _need().disconnectPhone(pb.DisconnectPhoneRequest(address: address, source: 'dashboard'), options: _opts);
    return CommandResult(ok: r.accepted, detail: r.detail);
  }

  @override
  Future<CommandResult> forgetPhone(String address) async {
    final r = await _need().forgetPhone(pb.ForgetPhoneRequest(address: address, source: 'dashboard'), options: _opts);
    return CommandResult(ok: r.accepted, detail: r.detail);
  }

  @override
  Future<SpeakerSnapshot> getSpeakers() async {
    final r = await _need().getSpeakerSettings(pb.GetSpeakerSettingsRequest(), options: _opts);
    final l = r.limits;
    return SpeakerSnapshot(
      settings: speakersFromPb(r.settings),
      defaults: speakersFromPb(r.defaults),
      limits: SpeakerLimits(
        steps: l.steps,
        stepDb: l.stepDb,
        subMinDb: l.subMinDb,
        subMaxDb: l.subMaxDb,
        crossoverMinHz: l.crossoverMinHz,
        crossoverMaxHz: l.crossoverMaxHz,
        crossoverStepHz: l.crossoverStepHz,
      ),
    );
  }

  @override
  Future<CommandResult> setSpeakers(SpeakerSettings s) async {
    final r = await _need().setSpeakerSettings(
      pb.SetSpeakerSettingsRequest(
        source: 'dashboard',
        settings: pb.SpeakerSettings(
          fader: s.fader,
          balance: s.balance,
          subLevelDb: s.subLevelDb,
          crossoverHz: s.crossoverHz,
        ),
      ),
      options: _opts,
    );
    return CommandResult(ok: r.applied, detail: r.detail);
  }
}

SpeakerSettings speakersFromPb(pb.SpeakerSettings s) => SpeakerSettings(
  fader: s.fader,
  balance: s.balance,
  subLevelDb: s.subLevelDb,
  crossoverHz: s.crossoverHz,
);

Phone phoneFromPb(pb.Phone p) => Phone(
  address: p.address,
  name: p.name.isEmpty ? p.address : p.name,
  connected: p.connected,
  paired: p.paired,
  last: p.last,
);

PlayState playStateFromPb(pb.PlayState s) => switch (s) {
  pb.PlayState.PLAY_STATE_STOPPED => PlayState.stopped,
  pb.PlayState.PLAY_STATE_PLAYING => PlayState.playing,
  pb.PlayState.PLAY_STATE_PAUSED => PlayState.paused,
  pb.PlayState.PLAY_STATE_FORWARD_SEEK => PlayState.forwardSeek,
  pb.PlayState.PLAY_STATE_REVERSE_SEEK => PlayState.reverseSeek,
  pb.PlayState.PLAY_STATE_ERROR => PlayState.error,
  _ => PlayState.unknown,
};

AudioReport reportFromPb(pb.WatchAudioResponse r) {
  final ready = r.bluetooth == pb.BluetoothState.BLUETOOTH_STATE_READY;
  // A phone or track while Bluetooth isn't ready would be stale: dropped.
  final phone = ready && r.hasPhone() && r.phone.connected ? phoneFromPb(r.phone) : null;
  final np = r.nowPlaying;
  final p = r.pairing;
  return AudioReport(
    simulated: r.simulated,
    bluetoothReady: ready,
    bluetoothDetail: r.bluetoothDetail,
    phone: phone,
    known: ready ? [for (final k in r.known) phoneFromPb(k)] : const [],
    nowPlaying: phone != null && r.hasNowPlaying()
        ? NowPlaying(
            title: np.title,
            artist: np.artist,
            album: np.album,
            playerName: np.playerName,
            state: playStateFromPb(np.state),
            duration: np.durationMs == 0 ? null : Duration(milliseconds: np.durationMs),
            position: np.hasPosition ? Duration(milliseconds: np.positionMs) : null,
          )
        : null,
    streaming: phone != null && r.streaming,
    pairing: !r.hasPairing()
        ? const PairingStatus()
        : PairingStatus(
            phase: switch (p.state) {
              pb.PairingState.PAIRING_STATE_OPENING => PairingPhase.opening,
              pb.PairingState.PAIRING_STATE_OPEN => PairingPhase.open,
              pb.PairingState.PAIRING_STATE_CLOSING => PairingPhase.closing,
              pb.PairingState.PAIRING_STATE_FAILED => PairingPhase.failed,
              _ => PairingPhase.closed,
            },
            secondsLeft: p.secondsLeft,
            detail: p.detail,
            name: p.name,
            question: p.hasQuestion()
                ? PasskeyQuestion(
                    id: p.question.id.toInt(),
                    phoneName: p.question.phoneName,
                    address: p.question.address,
                    passkey: p.question.showsPasskey ? p.question.passkey : null,
                    secondsLeft: p.question.secondsLeft,
                  )
                : null,
          ),
    dsp: switch (r.dsp) {
      pb.DspState.DSP_STATE_APPLIED => DspPhase.applied,
      pb.DspState.DSP_STATE_STARTING => DspPhase.starting,
      _ => DspPhase.notRunning,
    },
    dspDetail: r.dspDetail,
    speaking: r.prompts.speaking,
    pausedForPrompt: phone != null && r.prompts.musicPaused,
    // An attempt only means something while Bluetooth is up.
    connect: ready && r.hasConnect()
        ? ConnectStatus(
            address: r.connect.address,
            name: r.connect.name.isEmpty ? r.connect.address : r.connect.name,
            automatic: r.connect.automatic,
            detail: r.connect.detail,
          )
        : const ConnectStatus(),
  );
}
