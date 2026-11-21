// This is a generated file - do not edit.
//
// Generated from f250/power/v1/switch.proto.

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

import 'switch.pb.dart' as $0;

export 'switch.pb.dart';

@$pb.GrpcServiceName('f250.power.v1.SwitchService')
class SwitchServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  SwitchServiceClient(super.channel, {super.options, super.interceptors});

  /// The switch's state now, then again on each change, and each press as it
  /// happens. A client that loses the stream must not show the state as
  /// current.
  $grpc.ResponseStream<$0.WatchSwitchResponse> watchSwitch(
    $0.WatchSwitchRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$watchSwitch, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// Turns learning on or off. While on, presses are reported and not sent.
  /// It turns itself off after `learning_timeout_s` without a press, so a
  /// screen that went away can't leave the switch doing nothing.
  $grpc.ResponseFuture<$0.SetLearningResponse> setLearning(
    $0.SetLearningRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setLearning, request, options: options);
  }

  /// Saves which wire is which role, and turns learning off. Refused, with a
  /// reason, unless every wire has a different role.
  $grpc.ResponseFuture<$0.SetMappingResponse> setMapping(
    $0.SetMappingRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setMapping, request, options: options);
  }

  /// Back to the default mapping (the wiring doc's), saved, learning off.
  $grpc.ResponseFuture<$0.ResetMappingResponse> resetMapping(
    $0.ResetMappingRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$resetMapping, request, options: options);
  }

  // method descriptors

  static final _$watchSwitch =
      $grpc.ClientMethod<$0.WatchSwitchRequest, $0.WatchSwitchResponse>(
          '/f250.power.v1.SwitchService/WatchSwitch',
          ($0.WatchSwitchRequest value) => value.writeToBuffer(),
          $0.WatchSwitchResponse.fromBuffer);
  static final _$setLearning =
      $grpc.ClientMethod<$0.SetLearningRequest, $0.SetLearningResponse>(
          '/f250.power.v1.SwitchService/SetLearning',
          ($0.SetLearningRequest value) => value.writeToBuffer(),
          $0.SetLearningResponse.fromBuffer);
  static final _$setMapping =
      $grpc.ClientMethod<$0.SetMappingRequest, $0.SetMappingResponse>(
          '/f250.power.v1.SwitchService/SetMapping',
          ($0.SetMappingRequest value) => value.writeToBuffer(),
          $0.SetMappingResponse.fromBuffer);
  static final _$resetMapping =
      $grpc.ClientMethod<$0.ResetMappingRequest, $0.ResetMappingResponse>(
          '/f250.power.v1.SwitchService/ResetMapping',
          ($0.ResetMappingRequest value) => value.writeToBuffer(),
          $0.ResetMappingResponse.fromBuffer);
}

@$pb.GrpcServiceName('f250.power.v1.SwitchService')
abstract class SwitchServiceBase extends $grpc.Service {
  $core.String get $name => 'f250.power.v1.SwitchService';

  SwitchServiceBase() {
    $addMethod(
        $grpc.ServiceMethod<$0.WatchSwitchRequest, $0.WatchSwitchResponse>(
            'WatchSwitch',
            watchSwitch_Pre,
            false,
            true,
            ($core.List<$core.int> value) =>
                $0.WatchSwitchRequest.fromBuffer(value),
            ($0.WatchSwitchResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.SetLearningRequest, $0.SetLearningResponse>(
            'SetLearning',
            setLearning_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.SetLearningRequest.fromBuffer(value),
            ($0.SetLearningResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetMappingRequest, $0.SetMappingResponse>(
        'SetMapping',
        setMapping_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.SetMappingRequest.fromBuffer(value),
        ($0.SetMappingResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ResetMappingRequest, $0.ResetMappingResponse>(
            'ResetMapping',
            resetMapping_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ResetMappingRequest.fromBuffer(value),
            ($0.ResetMappingResponse value) => value.writeToBuffer()));
  }

  $async.Stream<$0.WatchSwitchResponse> watchSwitch_Pre($grpc.ServiceCall $call,
      $async.Future<$0.WatchSwitchRequest> $request) async* {
    yield* watchSwitch($call, await $request);
  }

  $async.Stream<$0.WatchSwitchResponse> watchSwitch(
      $grpc.ServiceCall call, $0.WatchSwitchRequest request);

  $async.Future<$0.SetLearningResponse> setLearning_Pre($grpc.ServiceCall $call,
      $async.Future<$0.SetLearningRequest> $request) async {
    return setLearning($call, await $request);
  }

  $async.Future<$0.SetLearningResponse> setLearning(
      $grpc.ServiceCall call, $0.SetLearningRequest request);

  $async.Future<$0.SetMappingResponse> setMapping_Pre($grpc.ServiceCall $call,
      $async.Future<$0.SetMappingRequest> $request) async {
    return setMapping($call, await $request);
  }

  $async.Future<$0.SetMappingResponse> setMapping(
      $grpc.ServiceCall call, $0.SetMappingRequest request);

  $async.Future<$0.ResetMappingResponse> resetMapping_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ResetMappingRequest> $request) async {
    return resetMapping($call, await $request);
  }

  $async.Future<$0.ResetMappingResponse> resetMapping(
      $grpc.ServiceCall call, $0.ResetMappingRequest request);
}
