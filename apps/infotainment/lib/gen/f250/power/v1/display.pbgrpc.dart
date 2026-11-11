// This is a generated file - do not edit.
//
// Generated from f250/power/v1/display.proto.

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

import 'display.pb.dart' as $0;

export 'display.pb.dart';

@$pb.GrpcServiceName('f250.power.v1.DisplayService')
class DisplayServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  DisplayServiceClient(super.channel, {super.options, super.interceptors});

  /// The display state now, then again each time it changes. A client that
  /// loses the stream must not claim the display is being controlled.
  $grpc.ResponseStream<$0.WatchDisplayResponse> watchDisplay(
    $0.WatchDisplayRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$watchDisplay, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// Changes the driver's choice and/or a brightness. Unset fields (zero)
  /// leave that setting as it is.
  $grpc.ResponseFuture<$0.SetDisplayResponse> setDisplay(
    $0.SetDisplayRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setDisplay, request, options: options);
  }

  // method descriptors

  static final _$watchDisplay =
      $grpc.ClientMethod<$0.WatchDisplayRequest, $0.WatchDisplayResponse>(
          '/f250.power.v1.DisplayService/WatchDisplay',
          ($0.WatchDisplayRequest value) => value.writeToBuffer(),
          $0.WatchDisplayResponse.fromBuffer);
  static final _$setDisplay =
      $grpc.ClientMethod<$0.SetDisplayRequest, $0.SetDisplayResponse>(
          '/f250.power.v1.DisplayService/SetDisplay',
          ($0.SetDisplayRequest value) => value.writeToBuffer(),
          $0.SetDisplayResponse.fromBuffer);
}

@$pb.GrpcServiceName('f250.power.v1.DisplayService')
abstract class DisplayServiceBase extends $grpc.Service {
  $core.String get $name => 'f250.power.v1.DisplayService';

  DisplayServiceBase() {
    $addMethod(
        $grpc.ServiceMethod<$0.WatchDisplayRequest, $0.WatchDisplayResponse>(
            'WatchDisplay',
            watchDisplay_Pre,
            false,
            true,
            ($core.List<$core.int> value) =>
                $0.WatchDisplayRequest.fromBuffer(value),
            ($0.WatchDisplayResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetDisplayRequest, $0.SetDisplayResponse>(
        'SetDisplay',
        setDisplay_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.SetDisplayRequest.fromBuffer(value),
        ($0.SetDisplayResponse value) => value.writeToBuffer()));
  }

  $async.Stream<$0.WatchDisplayResponse> watchDisplay_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.WatchDisplayRequest> $request) async* {
    yield* watchDisplay($call, await $request);
  }

  $async.Stream<$0.WatchDisplayResponse> watchDisplay(
      $grpc.ServiceCall call, $0.WatchDisplayRequest request);

  $async.Future<$0.SetDisplayResponse> setDisplay_Pre($grpc.ServiceCall $call,
      $async.Future<$0.SetDisplayRequest> $request) async {
    return setDisplay($call, await $request);
  }

  $async.Future<$0.SetDisplayResponse> setDisplay(
      $grpc.ServiceCall call, $0.SetDisplayRequest request);
}
