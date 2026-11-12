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
}
