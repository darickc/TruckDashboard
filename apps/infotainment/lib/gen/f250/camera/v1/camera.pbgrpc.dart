// This is a generated file - do not edit.
//
// Generated from f250/camera/v1/camera.proto.

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

import 'camera.pb.dart' as $0;

export 'camera.pb.dart';

@$pb.GrpcServiceName('f250.camera.v1.CameraService')
class CameraServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  CameraServiceClient(super.channel, {super.options, super.interceptors});

  /// The view now, then again each time it changes. A client that loses the
  /// stream must assume the camera state is unknown.
  $grpc.ResponseStream<$0.WatchViewResponse> watchView(
    $0.WatchViewRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$watchView, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// One debounced move of the camera switch (or an on-screen equivalent).
  $grpc.ResponseFuture<$0.MoveResponse> move(
    $0.MoveRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$move, request, options: options);
  }

  /// Front and rear recording (ADR-0027 decision 9, added 2026-11-10): the
  /// state now, then again each time it changes. A client that loses the
  /// stream must assume nothing is recording: it never shows REC on its own.
  $grpc.ResponseStream<$0.WatchRecordingResponse> watchRecording(
    $0.WatchRecordingRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$watchRecording, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// "Save clip" (ADR-0027 decision 8): protects the segment being written
  /// and the minutes around it from retention. Refused, with a reason, when
  /// nothing is recording or the saved clips are full.
  $grpc.ResponseFuture<$0.SaveClipResponse> saveClip(
    $0.SaveClipRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$saveClip, request, options: options);
  }

  // method descriptors

  static final _$watchView =
      $grpc.ClientMethod<$0.WatchViewRequest, $0.WatchViewResponse>(
          '/f250.camera.v1.CameraService/WatchView',
          ($0.WatchViewRequest value) => value.writeToBuffer(),
          $0.WatchViewResponse.fromBuffer);
  static final _$move = $grpc.ClientMethod<$0.MoveRequest, $0.MoveResponse>(
      '/f250.camera.v1.CameraService/Move',
      ($0.MoveRequest value) => value.writeToBuffer(),
      $0.MoveResponse.fromBuffer);
  static final _$watchRecording =
      $grpc.ClientMethod<$0.WatchRecordingRequest, $0.WatchRecordingResponse>(
          '/f250.camera.v1.CameraService/WatchRecording',
          ($0.WatchRecordingRequest value) => value.writeToBuffer(),
          $0.WatchRecordingResponse.fromBuffer);
  static final _$saveClip =
      $grpc.ClientMethod<$0.SaveClipRequest, $0.SaveClipResponse>(
          '/f250.camera.v1.CameraService/SaveClip',
          ($0.SaveClipRequest value) => value.writeToBuffer(),
          $0.SaveClipResponse.fromBuffer);
}

@$pb.GrpcServiceName('f250.camera.v1.CameraService')
abstract class CameraServiceBase extends $grpc.Service {
  $core.String get $name => 'f250.camera.v1.CameraService';

  CameraServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.WatchViewRequest, $0.WatchViewResponse>(
        'WatchView',
        watchView_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.WatchViewRequest.fromBuffer(value),
        ($0.WatchViewResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.MoveRequest, $0.MoveResponse>(
        'Move',
        move_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.MoveRequest.fromBuffer(value),
        ($0.MoveResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.WatchRecordingRequest,
            $0.WatchRecordingResponse>(
        'WatchRecording',
        watchRecording_Pre,
        false,
        true,
        ($core.List<$core.int> value) =>
            $0.WatchRecordingRequest.fromBuffer(value),
        ($0.WatchRecordingResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SaveClipRequest, $0.SaveClipResponse>(
        'SaveClip',
        saveClip_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.SaveClipRequest.fromBuffer(value),
        ($0.SaveClipResponse value) => value.writeToBuffer()));
  }

  $async.Stream<$0.WatchViewResponse> watchView_Pre($grpc.ServiceCall $call,
      $async.Future<$0.WatchViewRequest> $request) async* {
    yield* watchView($call, await $request);
  }

  $async.Stream<$0.WatchViewResponse> watchView(
      $grpc.ServiceCall call, $0.WatchViewRequest request);

  $async.Future<$0.MoveResponse> move_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.MoveRequest> $request) async {
    return move($call, await $request);
  }

  $async.Future<$0.MoveResponse> move(
      $grpc.ServiceCall call, $0.MoveRequest request);

  $async.Stream<$0.WatchRecordingResponse> watchRecording_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.WatchRecordingRequest> $request) async* {
    yield* watchRecording($call, await $request);
  }

  $async.Stream<$0.WatchRecordingResponse> watchRecording(
      $grpc.ServiceCall call, $0.WatchRecordingRequest request);

  $async.Future<$0.SaveClipResponse> saveClip_Pre($grpc.ServiceCall $call,
      $async.Future<$0.SaveClipRequest> $request) async {
    return saveClip($call, await $request);
  }

  $async.Future<$0.SaveClipResponse> saveClip(
      $grpc.ServiceCall call, $0.SaveClipRequest request);
}
