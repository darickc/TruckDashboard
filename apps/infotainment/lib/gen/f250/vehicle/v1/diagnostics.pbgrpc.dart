// This is a generated file - do not edit.
//
// Generated from f250/vehicle/v1/diagnostics.proto.

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

import 'diagnostics.pb.dart' as $0;

export 'diagnostics.pb.dart';

@$pb.GrpcServiceName('f250.vehicle.v1.DiagnosticsService')
class DiagnosticsServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  DiagnosticsServiceClient(super.channel, {super.options, super.interceptors});

  /// Enable or disable polling of one signal at runtime (not persisted).
  $grpc.ResponseFuture<$0.SetPollingResponse> setPolling(
    $0.SetPollingRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setPolling, request, options: options);
  }

  /// Poll one signal now, `count` times, reporting every responder.
  $grpc.ResponseFuture<$0.ProbeResponse> probe(
    $0.ProbeRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$probe, request, options: options);
  }

  /// Send one raw line (AT command or allow-listed OBD request) and return the
  /// adapter's lines verbatim. Polling pauses while a raw request is in flight.
  $grpc.ResponseFuture<$0.RawResponse> raw(
    $0.RawRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$raw, request, options: options);
  }

  $grpc.ResponseFuture<$0.StatsResponse> stats(
    $0.StatsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$stats, request, options: options);
  }

  // method descriptors

  static final _$setPolling =
      $grpc.ClientMethod<$0.SetPollingRequest, $0.SetPollingResponse>(
          '/f250.vehicle.v1.DiagnosticsService/SetPolling',
          ($0.SetPollingRequest value) => value.writeToBuffer(),
          $0.SetPollingResponse.fromBuffer);
  static final _$probe = $grpc.ClientMethod<$0.ProbeRequest, $0.ProbeResponse>(
      '/f250.vehicle.v1.DiagnosticsService/Probe',
      ($0.ProbeRequest value) => value.writeToBuffer(),
      $0.ProbeResponse.fromBuffer);
  static final _$raw = $grpc.ClientMethod<$0.RawRequest, $0.RawResponse>(
      '/f250.vehicle.v1.DiagnosticsService/Raw',
      ($0.RawRequest value) => value.writeToBuffer(),
      $0.RawResponse.fromBuffer);
  static final _$stats = $grpc.ClientMethod<$0.StatsRequest, $0.StatsResponse>(
      '/f250.vehicle.v1.DiagnosticsService/Stats',
      ($0.StatsRequest value) => value.writeToBuffer(),
      $0.StatsResponse.fromBuffer);
}

@$pb.GrpcServiceName('f250.vehicle.v1.DiagnosticsService')
abstract class DiagnosticsServiceBase extends $grpc.Service {
  $core.String get $name => 'f250.vehicle.v1.DiagnosticsService';

  DiagnosticsServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.SetPollingRequest, $0.SetPollingResponse>(
        'SetPolling',
        setPolling_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.SetPollingRequest.fromBuffer(value),
        ($0.SetPollingResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ProbeRequest, $0.ProbeResponse>(
        'Probe',
        probe_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ProbeRequest.fromBuffer(value),
        ($0.ProbeResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.RawRequest, $0.RawResponse>(
        'Raw',
        raw_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.RawRequest.fromBuffer(value),
        ($0.RawResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.StatsRequest, $0.StatsResponse>(
        'Stats',
        stats_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.StatsRequest.fromBuffer(value),
        ($0.StatsResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.SetPollingResponse> setPolling_Pre($grpc.ServiceCall $call,
      $async.Future<$0.SetPollingRequest> $request) async {
    return setPolling($call, await $request);
  }

  $async.Future<$0.SetPollingResponse> setPolling(
      $grpc.ServiceCall call, $0.SetPollingRequest request);

  $async.Future<$0.ProbeResponse> probe_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.ProbeRequest> $request) async {
    return probe($call, await $request);
  }

  $async.Future<$0.ProbeResponse> probe(
      $grpc.ServiceCall call, $0.ProbeRequest request);

  $async.Future<$0.RawResponse> raw_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.RawRequest> $request) async {
    return raw($call, await $request);
  }

  $async.Future<$0.RawResponse> raw(
      $grpc.ServiceCall call, $0.RawRequest request);

  $async.Future<$0.StatsResponse> stats_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.StatsRequest> $request) async {
    return stats($call, await $request);
  }

  $async.Future<$0.StatsResponse> stats(
      $grpc.ServiceCall call, $0.StatsRequest request);
}
