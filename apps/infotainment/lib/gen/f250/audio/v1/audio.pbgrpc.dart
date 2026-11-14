// This is a generated file - do not edit.
//
// Generated from f250/audio/v1/audio.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'audio.pb.dart' as $0;

export 'audio.pb.dart';

@$pb.GrpcServiceName('f250.audio.v1.AudioService')
class AudioServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  AudioServiceClient(super.channel, {super.options, super.interceptors});

  /// Everything the Media screen shows: now, then on each change, and at
  /// least once a second (a heartbeat). A client that hears nothing for a
  /// few seconds, or loses the stream, must show nothing as current: no
  /// track, no phone, no pairing window.
  $grpc.ResponseStream<$0.WatchAudioResponse> watchAudio(
    $0.WatchAudioRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$watchAudio, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// Play, pause, next or previous, sent to the connected phone's player
  /// (AVRCP). Refused, with a reason, without a phone or a player.
  $grpc.ResponseFuture<$0.ControlResponse> control(
    $0.ControlRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$control, request, options: options);
  }

  /// Opens the pairing window: the head unit is discoverable and accepts a
  /// new phone for `seconds` (clamped to the configured limit), then closes
  /// by itself. Opening an open window restarts its countdown.
  $grpc.ResponseFuture<$0.OpenPairingResponse> openPairing(
    $0.OpenPairingRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$openPairing, request, options: options);
  }

  /// Closes the pairing window now.
  $grpc.ResponseFuture<$0.ClosePairingResponse> closePairing(
    $0.ClosePairingRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$closePairing, request, options: options);
  }

  /// Connects a phone paired before (one in `known`), disconnecting any
  /// other first: one phone at a time. Returns at once; the attempt and its
  /// outcome are in WatchAudioResponse.connect. Refused, with a reason, for
  /// a phone that isn't paired, without Bluetooth, or while another attempt
  /// runs.
  $grpc.ResponseFuture<$0.ConnectPhoneResponse> connectPhone(
    $0.ConnectPhoneRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$connectPhone, request, options: options);
  }

  /// Disconnects the connected phone. It stays paired; audio-manager doesn't
  /// reconnect it by itself afterwards (the driver chose this). Returns at
  /// once; refused, with a reason, for a phone that isn't connected.
  $grpc.ResponseFuture<$0.DisconnectPhoneResponse> disconnectPhone(
    $0.DisconnectPhoneRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$disconnectPhone, request, options: options);
  }

  /// Forgets a paired phone (BlueZ removes the pairing): it has to be paired
  /// again through the window to be used. Disconnects it first if it is
  /// connected. Returns at once.
  $grpc.ResponseFuture<$0.ForgetPhoneResponse> forgetPhone(
    $0.ForgetPhoneRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$forgetPhone, request, options: options);
  }

  /// Answers a passkey question (Pairing.confirmation).
  $grpc.ResponseFuture<$0.ConfirmPairingResponse> confirmPairing(
    $0.ConfirmPairingRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$confirmPairing, request, options: options);
  }

  /// The speaker settings, their limits, and whether they are applied.
  $grpc.ResponseFuture<$0.GetSpeakerSettingsResponse> getSpeakerSettings(
    $0.GetSpeakerSettingsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getSpeakerSettings, request, options: options);
  }

  /// Validates, saves and applies the speaker settings. Refused, with a
  /// reason, when a value is outside its limits.
  $grpc.ResponseFuture<$0.SetSpeakerSettingsResponse> setSpeakerSettings(
    $0.SetSpeakerSettingsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setSpeakerSettings, request, options: options);
  }

  /// Says a short prompt (spoken directions) through the speakers, cutting off
  /// any prompt still being said: the newer one matters. Returns at once. The
  /// music is silenced as the prompt starts and the phone is paused; the
  /// phone resumes a few seconds after the last prompt, only if audio-manager
  /// paused it and it is still paused (the driver's own pause wins).
  $grpc.ResponseFuture<$0.SpeakResponse> speak(
    $0.SpeakRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$speak, request, options: options);
  }

  /// Stops the prompt being said, if any (muted, or the route ended).
  $grpc.ResponseFuture<$0.StopSpeakingResponse> stopSpeaking(
    $0.StopSpeakingRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$stopSpeaking, request, options: options);
  }

  /// The picture of the track now playing (NowPlaying.cover_art_id), as the
  /// phone sent it. found is false for an id that isn't the current one: a
  /// picture is never served for a track that has gone.
  $grpc.ResponseFuture<$0.GetCoverArtResponse> getCoverArt(
    $0.GetCoverArtRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getCoverArt, request, options: options);
  }

  /// The master volume (ADR-0043): a level, a number of steps, or mute. The
  /// knob (Linux input on the Pi) goes through the same change.
  $grpc.ResponseFuture<$0.SetVolumeResponse> setVolume(
    $0.SetVolumeRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setVolume, request, options: options);
  }

  /// Answers an incoming call (Call.state INCOMING). Refused, with a reason,
  /// for a call that isn't incoming, has gone, or when calls are off. A
  /// waiting call (during another) is answered on the phone.
  $grpc.ResponseFuture<$0.AnswerCallResponse> answerCall(
    $0.AnswerCallRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$answerCall, request, options: options);
  }

  /// Ends a call: declines an incoming or waiting call, hangs up any other.
  $grpc.ResponseFuture<$0.HangUpResponse> hangUp(
    $0.HangUpRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$hangUp, request, options: options);
  }

  /// Mutes or unmutes the call microphone. Only during a call; every call
  /// starts unmuted.
  $grpc.ResponseFuture<$0.SetMicMutedResponse> setMicMuted(
    $0.SetMicMutedRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setMicMuted, request, options: options);
  }

  // method descriptors

  static final _$watchAudio =
      $grpc.ClientMethod<$0.WatchAudioRequest, $0.WatchAudioResponse>(
          '/f250.audio.v1.AudioService/WatchAudio',
          ($0.WatchAudioRequest value) => value.writeToBuffer(),
          $0.WatchAudioResponse.fromBuffer);
  static final _$control =
      $grpc.ClientMethod<$0.ControlRequest, $0.ControlResponse>(
          '/f250.audio.v1.AudioService/Control',
          ($0.ControlRequest value) => value.writeToBuffer(),
          $0.ControlResponse.fromBuffer);
  static final _$openPairing =
      $grpc.ClientMethod<$0.OpenPairingRequest, $0.OpenPairingResponse>(
          '/f250.audio.v1.AudioService/OpenPairing',
          ($0.OpenPairingRequest value) => value.writeToBuffer(),
          $0.OpenPairingResponse.fromBuffer);
  static final _$closePairing =
      $grpc.ClientMethod<$0.ClosePairingRequest, $0.ClosePairingResponse>(
          '/f250.audio.v1.AudioService/ClosePairing',
          ($0.ClosePairingRequest value) => value.writeToBuffer(),
          $0.ClosePairingResponse.fromBuffer);
  static final _$connectPhone =
      $grpc.ClientMethod<$0.ConnectPhoneRequest, $0.ConnectPhoneResponse>(
          '/f250.audio.v1.AudioService/ConnectPhone',
          ($0.ConnectPhoneRequest value) => value.writeToBuffer(),
          $0.ConnectPhoneResponse.fromBuffer);
  static final _$disconnectPhone =
      $grpc.ClientMethod<$0.DisconnectPhoneRequest, $0.DisconnectPhoneResponse>(
          '/f250.audio.v1.AudioService/DisconnectPhone',
          ($0.DisconnectPhoneRequest value) => value.writeToBuffer(),
          $0.DisconnectPhoneResponse.fromBuffer);
  static final _$forgetPhone =
      $grpc.ClientMethod<$0.ForgetPhoneRequest, $0.ForgetPhoneResponse>(
          '/f250.audio.v1.AudioService/ForgetPhone',
          ($0.ForgetPhoneRequest value) => value.writeToBuffer(),
          $0.ForgetPhoneResponse.fromBuffer);
  static final _$confirmPairing =
      $grpc.ClientMethod<$0.ConfirmPairingRequest, $0.ConfirmPairingResponse>(
          '/f250.audio.v1.AudioService/ConfirmPairing',
          ($0.ConfirmPairingRequest value) => value.writeToBuffer(),
          $0.ConfirmPairingResponse.fromBuffer);
  static final _$getSpeakerSettings = $grpc.ClientMethod<
          $0.GetSpeakerSettingsRequest, $0.GetSpeakerSettingsResponse>(
      '/f250.audio.v1.AudioService/GetSpeakerSettings',
      ($0.GetSpeakerSettingsRequest value) => value.writeToBuffer(),
      $0.GetSpeakerSettingsResponse.fromBuffer);
  static final _$setSpeakerSettings = $grpc.ClientMethod<
          $0.SetSpeakerSettingsRequest, $0.SetSpeakerSettingsResponse>(
      '/f250.audio.v1.AudioService/SetSpeakerSettings',
      ($0.SetSpeakerSettingsRequest value) => value.writeToBuffer(),
      $0.SetSpeakerSettingsResponse.fromBuffer);
  static final _$speak = $grpc.ClientMethod<$0.SpeakRequest, $0.SpeakResponse>(
      '/f250.audio.v1.AudioService/Speak',
      ($0.SpeakRequest value) => value.writeToBuffer(),
      $0.SpeakResponse.fromBuffer);
  static final _$stopSpeaking =
      $grpc.ClientMethod<$0.StopSpeakingRequest, $0.StopSpeakingResponse>(
          '/f250.audio.v1.AudioService/StopSpeaking',
          ($0.StopSpeakingRequest value) => value.writeToBuffer(),
          $0.StopSpeakingResponse.fromBuffer);
  static final _$getCoverArt =
      $grpc.ClientMethod<$0.GetCoverArtRequest, $0.GetCoverArtResponse>(
          '/f250.audio.v1.AudioService/GetCoverArt',
          ($0.GetCoverArtRequest value) => value.writeToBuffer(),
          $0.GetCoverArtResponse.fromBuffer);
  static final _$setVolume =
      $grpc.ClientMethod<$0.SetVolumeRequest, $0.SetVolumeResponse>(
          '/f250.audio.v1.AudioService/SetVolume',
          ($0.SetVolumeRequest value) => value.writeToBuffer(),
          $0.SetVolumeResponse.fromBuffer);
  static final _$answerCall =
      $grpc.ClientMethod<$0.AnswerCallRequest, $0.AnswerCallResponse>(
          '/f250.audio.v1.AudioService/AnswerCall',
          ($0.AnswerCallRequest value) => value.writeToBuffer(),
          $0.AnswerCallResponse.fromBuffer);
  static final _$hangUp =
      $grpc.ClientMethod<$0.HangUpRequest, $0.HangUpResponse>(
          '/f250.audio.v1.AudioService/HangUp',
          ($0.HangUpRequest value) => value.writeToBuffer(),
          $0.HangUpResponse.fromBuffer);
  static final _$setMicMuted =
      $grpc.ClientMethod<$0.SetMicMutedRequest, $0.SetMicMutedResponse>(
          '/f250.audio.v1.AudioService/SetMicMuted',
          ($0.SetMicMutedRequest value) => value.writeToBuffer(),
          $0.SetMicMutedResponse.fromBuffer);
}

@$pb.GrpcServiceName('f250.audio.v1.AudioService')
abstract class AudioServiceBase extends $grpc.Service {
  $core.String get $name => 'f250.audio.v1.AudioService';

  AudioServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.WatchAudioRequest, $0.WatchAudioResponse>(
        'WatchAudio',
        watchAudio_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.WatchAudioRequest.fromBuffer(value),
        ($0.WatchAudioResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ControlRequest, $0.ControlResponse>(
        'Control',
        control_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ControlRequest.fromBuffer(value),
        ($0.ControlResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.OpenPairingRequest, $0.OpenPairingResponse>(
            'OpenPairing',
            openPairing_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.OpenPairingRequest.fromBuffer(value),
            ($0.OpenPairingResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ClosePairingRequest, $0.ClosePairingResponse>(
            'ClosePairing',
            closePairing_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ClosePairingRequest.fromBuffer(value),
            ($0.ClosePairingResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ConnectPhoneRequest, $0.ConnectPhoneResponse>(
            'ConnectPhone',
            connectPhone_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ConnectPhoneRequest.fromBuffer(value),
            ($0.ConnectPhoneResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.DisconnectPhoneRequest,
            $0.DisconnectPhoneResponse>(
        'DisconnectPhone',
        disconnectPhone_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.DisconnectPhoneRequest.fromBuffer(value),
        ($0.DisconnectPhoneResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ForgetPhoneRequest, $0.ForgetPhoneResponse>(
            'ForgetPhone',
            forgetPhone_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ForgetPhoneRequest.fromBuffer(value),
            ($0.ForgetPhoneResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ConfirmPairingRequest,
            $0.ConfirmPairingResponse>(
        'ConfirmPairing',
        confirmPairing_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ConfirmPairingRequest.fromBuffer(value),
        ($0.ConfirmPairingResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetSpeakerSettingsRequest,
            $0.GetSpeakerSettingsResponse>(
        'GetSpeakerSettings',
        getSpeakerSettings_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetSpeakerSettingsRequest.fromBuffer(value),
        ($0.GetSpeakerSettingsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetSpeakerSettingsRequest,
            $0.SetSpeakerSettingsResponse>(
        'SetSpeakerSettings',
        setSpeakerSettings_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SetSpeakerSettingsRequest.fromBuffer(value),
        ($0.SetSpeakerSettingsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SpeakRequest, $0.SpeakResponse>(
        'Speak',
        speak_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.SpeakRequest.fromBuffer(value),
        ($0.SpeakResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.StopSpeakingRequest, $0.StopSpeakingResponse>(
            'StopSpeaking',
            stopSpeaking_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.StopSpeakingRequest.fromBuffer(value),
            ($0.StopSpeakingResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.GetCoverArtRequest, $0.GetCoverArtResponse>(
            'GetCoverArt',
            getCoverArt_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.GetCoverArtRequest.fromBuffer(value),
            ($0.GetCoverArtResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetVolumeRequest, $0.SetVolumeResponse>(
        'SetVolume',
        setVolume_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.SetVolumeRequest.fromBuffer(value),
        ($0.SetVolumeResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.AnswerCallRequest, $0.AnswerCallResponse>(
        'AnswerCall',
        answerCall_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.AnswerCallRequest.fromBuffer(value),
        ($0.AnswerCallResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.HangUpRequest, $0.HangUpResponse>(
        'HangUp',
        hangUp_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.HangUpRequest.fromBuffer(value),
        ($0.HangUpResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.SetMicMutedRequest, $0.SetMicMutedResponse>(
            'SetMicMuted',
            setMicMuted_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.SetMicMutedRequest.fromBuffer(value),
            ($0.SetMicMutedResponse value) => value.writeToBuffer()));
  }

  $async.Stream<$0.WatchAudioResponse> watchAudio_Pre($grpc.ServiceCall $call,
      $async.Future<$0.WatchAudioRequest> $request) async* {
    yield* watchAudio($call, await $request);
  }

  $async.Stream<$0.WatchAudioResponse> watchAudio(
      $grpc.ServiceCall call, $0.WatchAudioRequest request);

  $async.Future<$0.ControlResponse> control_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ControlRequest> $request) async {
    return control($call, await $request);
  }

  $async.Future<$0.ControlResponse> control(
      $grpc.ServiceCall call, $0.ControlRequest request);

  $async.Future<$0.OpenPairingResponse> openPairing_Pre($grpc.ServiceCall $call,
      $async.Future<$0.OpenPairingRequest> $request) async {
    return openPairing($call, await $request);
  }

  $async.Future<$0.OpenPairingResponse> openPairing(
      $grpc.ServiceCall call, $0.OpenPairingRequest request);

  $async.Future<$0.ClosePairingResponse> closePairing_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ClosePairingRequest> $request) async {
    return closePairing($call, await $request);
  }

  $async.Future<$0.ClosePairingResponse> closePairing(
      $grpc.ServiceCall call, $0.ClosePairingRequest request);

  $async.Future<$0.ConnectPhoneResponse> connectPhone_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ConnectPhoneRequest> $request) async {
    return connectPhone($call, await $request);
  }

  $async.Future<$0.ConnectPhoneResponse> connectPhone(
      $grpc.ServiceCall call, $0.ConnectPhoneRequest request);

  $async.Future<$0.DisconnectPhoneResponse> disconnectPhone_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.DisconnectPhoneRequest> $request) async {
    return disconnectPhone($call, await $request);
  }

  $async.Future<$0.DisconnectPhoneResponse> disconnectPhone(
      $grpc.ServiceCall call, $0.DisconnectPhoneRequest request);

  $async.Future<$0.ForgetPhoneResponse> forgetPhone_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ForgetPhoneRequest> $request) async {
    return forgetPhone($call, await $request);
  }

  $async.Future<$0.ForgetPhoneResponse> forgetPhone(
      $grpc.ServiceCall call, $0.ForgetPhoneRequest request);

  $async.Future<$0.ConfirmPairingResponse> confirmPairing_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ConfirmPairingRequest> $request) async {
    return confirmPairing($call, await $request);
  }

  $async.Future<$0.ConfirmPairingResponse> confirmPairing(
      $grpc.ServiceCall call, $0.ConfirmPairingRequest request);

  $async.Future<$0.GetSpeakerSettingsResponse> getSpeakerSettings_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GetSpeakerSettingsRequest> $request) async {
    return getSpeakerSettings($call, await $request);
  }

  $async.Future<$0.GetSpeakerSettingsResponse> getSpeakerSettings(
      $grpc.ServiceCall call, $0.GetSpeakerSettingsRequest request);

  $async.Future<$0.SetSpeakerSettingsResponse> setSpeakerSettings_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SetSpeakerSettingsRequest> $request) async {
    return setSpeakerSettings($call, await $request);
  }

  $async.Future<$0.SetSpeakerSettingsResponse> setSpeakerSettings(
      $grpc.ServiceCall call, $0.SetSpeakerSettingsRequest request);

  $async.Future<$0.SpeakResponse> speak_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.SpeakRequest> $request) async {
    return speak($call, await $request);
  }

  $async.Future<$0.SpeakResponse> speak(
      $grpc.ServiceCall call, $0.SpeakRequest request);

  $async.Future<$0.StopSpeakingResponse> stopSpeaking_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.StopSpeakingRequest> $request) async {
    return stopSpeaking($call, await $request);
  }

  $async.Future<$0.StopSpeakingResponse> stopSpeaking(
      $grpc.ServiceCall call, $0.StopSpeakingRequest request);

  $async.Future<$0.GetCoverArtResponse> getCoverArt_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetCoverArtRequest> $request) async {
    return getCoverArt($call, await $request);
  }

  $async.Future<$0.GetCoverArtResponse> getCoverArt(
      $grpc.ServiceCall call, $0.GetCoverArtRequest request);

  $async.Future<$0.SetVolumeResponse> setVolume_Pre($grpc.ServiceCall $call,
      $async.Future<$0.SetVolumeRequest> $request) async {
    return setVolume($call, await $request);
  }

  $async.Future<$0.SetVolumeResponse> setVolume(
      $grpc.ServiceCall call, $0.SetVolumeRequest request);

  $async.Future<$0.AnswerCallResponse> answerCall_Pre($grpc.ServiceCall $call,
      $async.Future<$0.AnswerCallRequest> $request) async {
    return answerCall($call, await $request);
  }

  $async.Future<$0.AnswerCallResponse> answerCall(
      $grpc.ServiceCall call, $0.AnswerCallRequest request);

  $async.Future<$0.HangUpResponse> hangUp_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.HangUpRequest> $request) async {
    return hangUp($call, await $request);
  }

  $async.Future<$0.HangUpResponse> hangUp(
      $grpc.ServiceCall call, $0.HangUpRequest request);

  $async.Future<$0.SetMicMutedResponse> setMicMuted_Pre($grpc.ServiceCall $call,
      $async.Future<$0.SetMicMutedRequest> $request) async {
    return setMicMuted($call, await $request);
  }

  $async.Future<$0.SetMicMutedResponse> setMicMuted(
      $grpc.ServiceCall call, $0.SetMicMutedRequest request);
}
