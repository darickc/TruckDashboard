// This is a generated file - do not edit.
//
// Generated from f250/network/v1/wifi.proto.

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

import 'wifi.pb.dart' as $0;

export 'wifi.pb.dart';

@$pb.GrpcServiceName('f250.network.v1.WifiService')
class WifiServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  WifiServiceClient(super.channel, {super.options, super.interceptors});

  /// The state now, then on every change.
  $grpc.ResponseStream<$0.WatchWifiResponse> watchWifi(
    $0.WatchWifiRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$watchWifi, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// Turns the Wi-Fi radio on or off (connman's Powered).
  $grpc.ResponseFuture<$0.SetWifiEnabledResponse> setWifiEnabled(
    $0.SetWifiEnabledRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setWifiEnabled, request, options: options);
  }

  /// Looks for networks; WatchWifi shows what it finds.
  $grpc.ResponseFuture<$0.ScanWifiResponse> scanWifi(
    $0.ScanWifiRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$scanWifi, request, options: options);
  }

  /// Joins a network and returns when that succeeded or failed, so it can
  /// take tens of seconds. The passphrase is needed only for a secured
  /// network that isn't saved.
  $grpc.ResponseFuture<$0.ConnectWifiResponse> connectWifi(
    $0.ConnectWifiRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$connectWifi, request, options: options);
  }

  /// Leaves a network; it stays saved.
  $grpc.ResponseFuture<$0.DisconnectWifiResponse> disconnectWifi(
    $0.DisconnectWifiRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$disconnectWifi, request, options: options);
  }

  /// Forgets a saved network (and leaves it).
  $grpc.ResponseFuture<$0.ForgetWifiResponse> forgetWifi(
    $0.ForgetWifiRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$forgetWifi, request, options: options);
  }

  // method descriptors

  static final _$watchWifi =
      $grpc.ClientMethod<$0.WatchWifiRequest, $0.WatchWifiResponse>(
          '/f250.network.v1.WifiService/WatchWifi',
          ($0.WatchWifiRequest value) => value.writeToBuffer(),
          $0.WatchWifiResponse.fromBuffer);
  static final _$setWifiEnabled =
      $grpc.ClientMethod<$0.SetWifiEnabledRequest, $0.SetWifiEnabledResponse>(
          '/f250.network.v1.WifiService/SetWifiEnabled',
          ($0.SetWifiEnabledRequest value) => value.writeToBuffer(),
          $0.SetWifiEnabledResponse.fromBuffer);
  static final _$scanWifi =
      $grpc.ClientMethod<$0.ScanWifiRequest, $0.ScanWifiResponse>(
          '/f250.network.v1.WifiService/ScanWifi',
          ($0.ScanWifiRequest value) => value.writeToBuffer(),
          $0.ScanWifiResponse.fromBuffer);
  static final _$connectWifi =
      $grpc.ClientMethod<$0.ConnectWifiRequest, $0.ConnectWifiResponse>(
          '/f250.network.v1.WifiService/ConnectWifi',
          ($0.ConnectWifiRequest value) => value.writeToBuffer(),
          $0.ConnectWifiResponse.fromBuffer);
  static final _$disconnectWifi =
      $grpc.ClientMethod<$0.DisconnectWifiRequest, $0.DisconnectWifiResponse>(
          '/f250.network.v1.WifiService/DisconnectWifi',
          ($0.DisconnectWifiRequest value) => value.writeToBuffer(),
          $0.DisconnectWifiResponse.fromBuffer);
  static final _$forgetWifi =
      $grpc.ClientMethod<$0.ForgetWifiRequest, $0.ForgetWifiResponse>(
          '/f250.network.v1.WifiService/ForgetWifi',
          ($0.ForgetWifiRequest value) => value.writeToBuffer(),
          $0.ForgetWifiResponse.fromBuffer);
}

@$pb.GrpcServiceName('f250.network.v1.WifiService')
abstract class WifiServiceBase extends $grpc.Service {
  $core.String get $name => 'f250.network.v1.WifiService';

  WifiServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.WatchWifiRequest, $0.WatchWifiResponse>(
        'WatchWifi',
        watchWifi_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.WatchWifiRequest.fromBuffer(value),
        ($0.WatchWifiResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetWifiEnabledRequest,
            $0.SetWifiEnabledResponse>(
        'SetWifiEnabled',
        setWifiEnabled_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SetWifiEnabledRequest.fromBuffer(value),
        ($0.SetWifiEnabledResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ScanWifiRequest, $0.ScanWifiResponse>(
        'ScanWifi',
        scanWifi_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ScanWifiRequest.fromBuffer(value),
        ($0.ScanWifiResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ConnectWifiRequest, $0.ConnectWifiResponse>(
            'ConnectWifi',
            connectWifi_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ConnectWifiRequest.fromBuffer(value),
            ($0.ConnectWifiResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.DisconnectWifiRequest,
            $0.DisconnectWifiResponse>(
        'DisconnectWifi',
        disconnectWifi_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.DisconnectWifiRequest.fromBuffer(value),
        ($0.DisconnectWifiResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ForgetWifiRequest, $0.ForgetWifiResponse>(
        'ForgetWifi',
        forgetWifi_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ForgetWifiRequest.fromBuffer(value),
        ($0.ForgetWifiResponse value) => value.writeToBuffer()));
  }

  $async.Stream<$0.WatchWifiResponse> watchWifi_Pre($grpc.ServiceCall $call,
      $async.Future<$0.WatchWifiRequest> $request) async* {
    yield* watchWifi($call, await $request);
  }

  $async.Stream<$0.WatchWifiResponse> watchWifi(
      $grpc.ServiceCall call, $0.WatchWifiRequest request);

  $async.Future<$0.SetWifiEnabledResponse> setWifiEnabled_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SetWifiEnabledRequest> $request) async {
    return setWifiEnabled($call, await $request);
  }

  $async.Future<$0.SetWifiEnabledResponse> setWifiEnabled(
      $grpc.ServiceCall call, $0.SetWifiEnabledRequest request);

  $async.Future<$0.ScanWifiResponse> scanWifi_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ScanWifiRequest> $request) async {
    return scanWifi($call, await $request);
  }

  $async.Future<$0.ScanWifiResponse> scanWifi(
      $grpc.ServiceCall call, $0.ScanWifiRequest request);

  $async.Future<$0.ConnectWifiResponse> connectWifi_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ConnectWifiRequest> $request) async {
    return connectWifi($call, await $request);
  }

  $async.Future<$0.ConnectWifiResponse> connectWifi(
      $grpc.ServiceCall call, $0.ConnectWifiRequest request);

  $async.Future<$0.DisconnectWifiResponse> disconnectWifi_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.DisconnectWifiRequest> $request) async {
    return disconnectWifi($call, await $request);
  }

  $async.Future<$0.DisconnectWifiResponse> disconnectWifi(
      $grpc.ServiceCall call, $0.DisconnectWifiRequest request);

  $async.Future<$0.ForgetWifiResponse> forgetWifi_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ForgetWifiRequest> $request) async {
    return forgetWifi($call, await $request);
  }

  $async.Future<$0.ForgetWifiResponse> forgetWifi(
      $grpc.ServiceCall call, $0.ForgetWifiRequest request);
}
