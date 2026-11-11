// This is a generated file - do not edit.
//
// Generated from f250/nav/v1/position.proto.

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

import 'position.pb.dart' as $0;

export 'position.pb.dart';

@$pb.GrpcServiceName('f250.nav.v1.PositionService')
class PositionServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  PositionServiceClient(super.channel, {super.options, super.interceptors});

  /// The position now, then again on each report and at least once a second,
  /// so ages keep moving. A client that loses the stream, or hears nothing
  /// for longer than `stale_after_ms`, must not show the position as current.
  $grpc.ResponseStream<$0.WatchPositionResponse> watchPosition(
    $0.WatchPositionRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$watchPosition, $async.Stream.fromIterable([request]),
        options: options);
  }

  // method descriptors

  static final _$watchPosition =
      $grpc.ClientMethod<$0.WatchPositionRequest, $0.WatchPositionResponse>(
          '/f250.nav.v1.PositionService/WatchPosition',
          ($0.WatchPositionRequest value) => value.writeToBuffer(),
          $0.WatchPositionResponse.fromBuffer);
}

@$pb.GrpcServiceName('f250.nav.v1.PositionService')
abstract class PositionServiceBase extends $grpc.Service {
  $core.String get $name => 'f250.nav.v1.PositionService';

  PositionServiceBase() {
    $addMethod(
        $grpc.ServiceMethod<$0.WatchPositionRequest, $0.WatchPositionResponse>(
            'WatchPosition',
            watchPosition_Pre,
            false,
            true,
            ($core.List<$core.int> value) =>
                $0.WatchPositionRequest.fromBuffer(value),
            ($0.WatchPositionResponse value) => value.writeToBuffer()));
  }

  $async.Stream<$0.WatchPositionResponse> watchPosition_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.WatchPositionRequest> $request) async* {
    yield* watchPosition($call, await $request);
  }

  $async.Stream<$0.WatchPositionResponse> watchPosition(
      $grpc.ServiceCall call, $0.WatchPositionRequest request);
}
