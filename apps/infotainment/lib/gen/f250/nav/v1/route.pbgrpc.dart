// This is a generated file - do not edit.
//
// Generated from f250/nav/v1/route.proto.

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

import 'route.pb.dart' as $0;

export 'route.pb.dart';

@$pb.GrpcServiceName('f250.nav.v1.RouteService')
class RouteServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  RouteServiceClient(super.channel, {super.options, super.interceptors});

  /// Routes from the current position to `destination`, replacing any route.
  /// Returns at once; the result arrives on WatchGuidance (ROUTING, then
  /// ACTIVE or FAILED).
  $grpc.ResponseFuture<$0.SetDestinationResponse> setDestination(
    $0.SetDestinationRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setDestination, request, options: options);
  }

  /// Drops the destination and the route.
  $grpc.ResponseFuture<$0.ClearRouteResponse> clearRoute(
    $0.ClearRouteRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$clearRoute, request, options: options);
  }

  /// Guidance now, then on every change and at least once a second.
  $grpc.ResponseStream<$0.WatchGuidanceResponse> watchGuidance(
    $0.WatchGuidanceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$watchGuidance, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// The line and maneuvers of a route, by the id Guidance names. NOT_FOUND
  /// once a newer route has replaced it.
  $grpc.ResponseFuture<$0.GetRouteResponse> getRoute(
    $0.GetRouteRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getRoute, request, options: options);
  }

  // method descriptors

  static final _$setDestination =
      $grpc.ClientMethod<$0.SetDestinationRequest, $0.SetDestinationResponse>(
          '/f250.nav.v1.RouteService/SetDestination',
          ($0.SetDestinationRequest value) => value.writeToBuffer(),
          $0.SetDestinationResponse.fromBuffer);
  static final _$clearRoute =
      $grpc.ClientMethod<$0.ClearRouteRequest, $0.ClearRouteResponse>(
          '/f250.nav.v1.RouteService/ClearRoute',
          ($0.ClearRouteRequest value) => value.writeToBuffer(),
          $0.ClearRouteResponse.fromBuffer);
  static final _$watchGuidance =
      $grpc.ClientMethod<$0.WatchGuidanceRequest, $0.WatchGuidanceResponse>(
          '/f250.nav.v1.RouteService/WatchGuidance',
          ($0.WatchGuidanceRequest value) => value.writeToBuffer(),
          $0.WatchGuidanceResponse.fromBuffer);
  static final _$getRoute =
      $grpc.ClientMethod<$0.GetRouteRequest, $0.GetRouteResponse>(
          '/f250.nav.v1.RouteService/GetRoute',
          ($0.GetRouteRequest value) => value.writeToBuffer(),
          $0.GetRouteResponse.fromBuffer);
}

@$pb.GrpcServiceName('f250.nav.v1.RouteService')
abstract class RouteServiceBase extends $grpc.Service {
  $core.String get $name => 'f250.nav.v1.RouteService';

  RouteServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.SetDestinationRequest,
            $0.SetDestinationResponse>(
        'SetDestination',
        setDestination_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SetDestinationRequest.fromBuffer(value),
        ($0.SetDestinationResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ClearRouteRequest, $0.ClearRouteResponse>(
        'ClearRoute',
        clearRoute_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ClearRouteRequest.fromBuffer(value),
        ($0.ClearRouteResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.WatchGuidanceRequest, $0.WatchGuidanceResponse>(
            'WatchGuidance',
            watchGuidance_Pre,
            false,
            true,
            ($core.List<$core.int> value) =>
                $0.WatchGuidanceRequest.fromBuffer(value),
            ($0.WatchGuidanceResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetRouteRequest, $0.GetRouteResponse>(
        'GetRoute',
        getRoute_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.GetRouteRequest.fromBuffer(value),
        ($0.GetRouteResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.SetDestinationResponse> setDestination_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SetDestinationRequest> $request) async {
    return setDestination($call, await $request);
  }

  $async.Future<$0.SetDestinationResponse> setDestination(
      $grpc.ServiceCall call, $0.SetDestinationRequest request);

  $async.Future<$0.ClearRouteResponse> clearRoute_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ClearRouteRequest> $request) async {
    return clearRoute($call, await $request);
  }

  $async.Future<$0.ClearRouteResponse> clearRoute(
      $grpc.ServiceCall call, $0.ClearRouteRequest request);

  $async.Stream<$0.WatchGuidanceResponse> watchGuidance_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.WatchGuidanceRequest> $request) async* {
    yield* watchGuidance($call, await $request);
  }

  $async.Stream<$0.WatchGuidanceResponse> watchGuidance(
      $grpc.ServiceCall call, $0.WatchGuidanceRequest request);

  $async.Future<$0.GetRouteResponse> getRoute_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetRouteRequest> $request) async {
    return getRoute($call, await $request);
  }

  $async.Future<$0.GetRouteResponse> getRoute(
      $grpc.ServiceCall call, $0.GetRouteRequest request);
}
