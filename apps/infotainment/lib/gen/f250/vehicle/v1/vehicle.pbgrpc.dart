// This is a generated file - do not edit.
//
// Generated from f250/vehicle/v1/vehicle.proto.

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

import 'vehicle.pb.dart' as $0;

export 'vehicle.pb.dart';

@$pb.GrpcServiceName('f250.vehicle.v1.VehicleService')
class VehicleServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  VehicleServiceClient(super.channel, {super.options, super.interceptors});

  /// Every known signal and how much to trust its definition.
  $grpc.ResponseFuture<$0.ListSignalsResponse> listSignals(
    $0.ListSignalsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listSignals, request, options: options);
  }

  /// Full state at a fixed period. A client that stops receiving snapshots
  /// must treat all data as stale (the UI does).
  $grpc.ResponseStream<$0.StreamSnapshotsResponse> streamSnapshots(
    $0.StreamSnapshotsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$streamSnapshots, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// Recent structured events (state transitions, recoveries, errors).
  $grpc.ResponseFuture<$0.ListEventsResponse> listEvents(
    $0.ListEventsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listEvents, request, options: options);
  }

  /// Truck-specific correction for one signal (docs/diagnostics/CALIBRATION.md).
  /// Affects only what is displayed and recorded; nothing is written to the truck.
  $grpc.ResponseFuture<$0.SetCalibrationResponse> setCalibration(
    $0.SetCalibrationRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setCalibration, request, options: options);
  }

  /// Whether the truck is in reverse, from the broadcast `230` byte 0, heard
  /// passively (ADR-0046): one message at once, then on every change and at
  /// least every 100 ms. Unknown when the broadcast is stale or can't be read,
  /// never "not engaged". A client that stops receiving messages must treat
  /// reverse as unknown.
  $grpc.ResponseStream<$0.WatchReverseResponse> watchReverse(
    $0.WatchReverseRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$watchReverse, $async.Stream.fromIterable([request]),
        options: options);
  }

  // method descriptors

  static final _$listSignals =
      $grpc.ClientMethod<$0.ListSignalsRequest, $0.ListSignalsResponse>(
          '/f250.vehicle.v1.VehicleService/ListSignals',
          ($0.ListSignalsRequest value) => value.writeToBuffer(),
          $0.ListSignalsResponse.fromBuffer);
  static final _$streamSnapshots =
      $grpc.ClientMethod<$0.StreamSnapshotsRequest, $0.StreamSnapshotsResponse>(
          '/f250.vehicle.v1.VehicleService/StreamSnapshots',
          ($0.StreamSnapshotsRequest value) => value.writeToBuffer(),
          $0.StreamSnapshotsResponse.fromBuffer);
  static final _$listEvents =
      $grpc.ClientMethod<$0.ListEventsRequest, $0.ListEventsResponse>(
          '/f250.vehicle.v1.VehicleService/ListEvents',
          ($0.ListEventsRequest value) => value.writeToBuffer(),
          $0.ListEventsResponse.fromBuffer);
  static final _$setCalibration =
      $grpc.ClientMethod<$0.SetCalibrationRequest, $0.SetCalibrationResponse>(
          '/f250.vehicle.v1.VehicleService/SetCalibration',
          ($0.SetCalibrationRequest value) => value.writeToBuffer(),
          $0.SetCalibrationResponse.fromBuffer);
  static final _$watchReverse =
      $grpc.ClientMethod<$0.WatchReverseRequest, $0.WatchReverseResponse>(
          '/f250.vehicle.v1.VehicleService/WatchReverse',
          ($0.WatchReverseRequest value) => value.writeToBuffer(),
          $0.WatchReverseResponse.fromBuffer);
}

@$pb.GrpcServiceName('f250.vehicle.v1.VehicleService')
abstract class VehicleServiceBase extends $grpc.Service {
  $core.String get $name => 'f250.vehicle.v1.VehicleService';

  VehicleServiceBase() {
    $addMethod(
        $grpc.ServiceMethod<$0.ListSignalsRequest, $0.ListSignalsResponse>(
            'ListSignals',
            listSignals_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ListSignalsRequest.fromBuffer(value),
            ($0.ListSignalsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.StreamSnapshotsRequest,
            $0.StreamSnapshotsResponse>(
        'StreamSnapshots',
        streamSnapshots_Pre,
        false,
        true,
        ($core.List<$core.int> value) =>
            $0.StreamSnapshotsRequest.fromBuffer(value),
        ($0.StreamSnapshotsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListEventsRequest, $0.ListEventsResponse>(
        'ListEvents',
        listEvents_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ListEventsRequest.fromBuffer(value),
        ($0.ListEventsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetCalibrationRequest,
            $0.SetCalibrationResponse>(
        'SetCalibration',
        setCalibration_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SetCalibrationRequest.fromBuffer(value),
        ($0.SetCalibrationResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.WatchReverseRequest, $0.WatchReverseResponse>(
            'WatchReverse',
            watchReverse_Pre,
            false,
            true,
            ($core.List<$core.int> value) =>
                $0.WatchReverseRequest.fromBuffer(value),
            ($0.WatchReverseResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.ListSignalsResponse> listSignals_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ListSignalsRequest> $request) async {
    return listSignals($call, await $request);
  }

  $async.Future<$0.ListSignalsResponse> listSignals(
      $grpc.ServiceCall call, $0.ListSignalsRequest request);

  $async.Stream<$0.StreamSnapshotsResponse> streamSnapshots_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.StreamSnapshotsRequest> $request) async* {
    yield* streamSnapshots($call, await $request);
  }

  $async.Stream<$0.StreamSnapshotsResponse> streamSnapshots(
      $grpc.ServiceCall call, $0.StreamSnapshotsRequest request);

  $async.Future<$0.ListEventsResponse> listEvents_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ListEventsRequest> $request) async {
    return listEvents($call, await $request);
  }

  $async.Future<$0.ListEventsResponse> listEvents(
      $grpc.ServiceCall call, $0.ListEventsRequest request);

  $async.Future<$0.SetCalibrationResponse> setCalibration_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SetCalibrationRequest> $request) async {
    return setCalibration($call, await $request);
  }

  $async.Future<$0.SetCalibrationResponse> setCalibration(
      $grpc.ServiceCall call, $0.SetCalibrationRequest request);

  $async.Stream<$0.WatchReverseResponse> watchReverse_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.WatchReverseRequest> $request) async* {
    yield* watchReverse($call, await $request);
  }

  $async.Stream<$0.WatchReverseResponse> watchReverse(
      $grpc.ServiceCall call, $0.WatchReverseRequest request);
}
