// This is a generated file - do not edit.
//
// Generated from f250/nav/v1/online_map.proto.

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

import 'online_map.pb.dart' as $0;

export 'online_map.pb.dart';

@$pb.GrpcServiceName('f250.nav.v1.OnlineMapService')
class OnlineMapServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  OnlineMapServiceClient(super.channel, {super.options, super.interceptors});

  /// Whether the online map can be used at all: a token is configured.
  /// Whether there is a network is the Wi-Fi service's to say.
  $grpc.ResponseFuture<$0.GetOnlineMapStatusResponse> getOnlineMapStatus(
    $0.GetOnlineMapStatusRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getOnlineMapStatus, request, options: options);
  }

  /// One tile. FAILED_PRECONDITION without a token, UNAVAILABLE when Mapbox
  /// can't be reached or refuses (the message says why), INVALID_ARGUMENT
  /// for a tile outside the zooms.
  $grpc.ResponseFuture<$0.GetTileResponse> getTile(
    $0.GetTileRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getTile, request, options: options);
  }

  /// The vector map's style for day or night: Mapbox's style document, its
  /// sprites, and the zooms of each of its vector sources. FAILED_PRECONDITION
  /// without a token or while the map is raster, UNAVAILABLE when Mapbox can't
  /// be reached.
  $grpc.ResponseFuture<$0.GetMapStyleResponse> getMapStyle(
    $0.GetMapStyleRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getMapStyle, request, options: options);
  }

  // method descriptors

  static final _$getOnlineMapStatus = $grpc.ClientMethod<
          $0.GetOnlineMapStatusRequest, $0.GetOnlineMapStatusResponse>(
      '/f250.nav.v1.OnlineMapService/GetOnlineMapStatus',
      ($0.GetOnlineMapStatusRequest value) => value.writeToBuffer(),
      $0.GetOnlineMapStatusResponse.fromBuffer);
  static final _$getTile =
      $grpc.ClientMethod<$0.GetTileRequest, $0.GetTileResponse>(
          '/f250.nav.v1.OnlineMapService/GetTile',
          ($0.GetTileRequest value) => value.writeToBuffer(),
          $0.GetTileResponse.fromBuffer);
  static final _$getMapStyle =
      $grpc.ClientMethod<$0.GetMapStyleRequest, $0.GetMapStyleResponse>(
          '/f250.nav.v1.OnlineMapService/GetMapStyle',
          ($0.GetMapStyleRequest value) => value.writeToBuffer(),
          $0.GetMapStyleResponse.fromBuffer);
}

@$pb.GrpcServiceName('f250.nav.v1.OnlineMapService')
abstract class OnlineMapServiceBase extends $grpc.Service {
  $core.String get $name => 'f250.nav.v1.OnlineMapService';

  OnlineMapServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.GetOnlineMapStatusRequest,
            $0.GetOnlineMapStatusResponse>(
        'GetOnlineMapStatus',
        getOnlineMapStatus_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetOnlineMapStatusRequest.fromBuffer(value),
        ($0.GetOnlineMapStatusResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetTileRequest, $0.GetTileResponse>(
        'GetTile',
        getTile_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.GetTileRequest.fromBuffer(value),
        ($0.GetTileResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.GetMapStyleRequest, $0.GetMapStyleResponse>(
            'GetMapStyle',
            getMapStyle_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.GetMapStyleRequest.fromBuffer(value),
            ($0.GetMapStyleResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.GetOnlineMapStatusResponse> getOnlineMapStatus_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GetOnlineMapStatusRequest> $request) async {
    return getOnlineMapStatus($call, await $request);
  }

  $async.Future<$0.GetOnlineMapStatusResponse> getOnlineMapStatus(
      $grpc.ServiceCall call, $0.GetOnlineMapStatusRequest request);

  $async.Future<$0.GetTileResponse> getTile_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetTileRequest> $request) async {
    return getTile($call, await $request);
  }

  $async.Future<$0.GetTileResponse> getTile(
      $grpc.ServiceCall call, $0.GetTileRequest request);

  $async.Future<$0.GetMapStyleResponse> getMapStyle_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetMapStyleRequest> $request) async {
    return getMapStyle($call, await $request);
  }

  $async.Future<$0.GetMapStyleResponse> getMapStyle(
      $grpc.ServiceCall call, $0.GetMapStyleRequest request);
}
