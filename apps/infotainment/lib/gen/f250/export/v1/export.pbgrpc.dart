// This is a generated file - do not edit.
//
// Generated from f250/export/v1/export.proto.

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

import 'export.pb.dart' as $0;

export 'export.pb.dart';

@$pb.GrpcServiceName('f250.export.v1.ExportService')
class ExportServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  ExportServiceClient(super.channel, {super.options, super.interceptors});

  /// The recordings on the data drive now (front, rear and saved clips), in
  /// recording order.
  $grpc.ResponseFuture<$0.ListRecordingsResponse> listRecordings(
    $0.ListRecordingsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listRecordings, request, options: options);
  }

  /// The USB sticks plugged in and the copy, now and then again each time
  /// either changes. A client that loses the stream must assume nothing
  /// about a copy in progress: it never says "safe to unplug" on its own.
  $grpc.ResponseStream<$0.WatchExportResponse> watchExport(
    $0.WatchExportRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$watchExport, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// Starts copying the given recordings to a stick. Refused, with a reason,
  /// while another copy runs, when the stick isn't an export stick, or when
  /// the recordings don't fit.
  $grpc.ResponseFuture<$0.StartCopyResponse> startCopy(
    $0.StartCopyRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$startCopy, request, options: options);
  }

  /// Stops the copy after the file being written is abandoned (its partial
  /// copy is removed); the files already finished stay on the stick, which
  /// is then synced and unmounted.
  $grpc.ResponseFuture<$0.CancelCopyResponse> cancelCopy(
    $0.CancelCopyRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$cancelCopy, request, options: options);
  }

  // method descriptors

  static final _$listRecordings =
      $grpc.ClientMethod<$0.ListRecordingsRequest, $0.ListRecordingsResponse>(
          '/f250.export.v1.ExportService/ListRecordings',
          ($0.ListRecordingsRequest value) => value.writeToBuffer(),
          $0.ListRecordingsResponse.fromBuffer);
  static final _$watchExport =
      $grpc.ClientMethod<$0.WatchExportRequest, $0.WatchExportResponse>(
          '/f250.export.v1.ExportService/WatchExport',
          ($0.WatchExportRequest value) => value.writeToBuffer(),
          $0.WatchExportResponse.fromBuffer);
  static final _$startCopy =
      $grpc.ClientMethod<$0.StartCopyRequest, $0.StartCopyResponse>(
          '/f250.export.v1.ExportService/StartCopy',
          ($0.StartCopyRequest value) => value.writeToBuffer(),
          $0.StartCopyResponse.fromBuffer);
  static final _$cancelCopy =
      $grpc.ClientMethod<$0.CancelCopyRequest, $0.CancelCopyResponse>(
          '/f250.export.v1.ExportService/CancelCopy',
          ($0.CancelCopyRequest value) => value.writeToBuffer(),
          $0.CancelCopyResponse.fromBuffer);
}

@$pb.GrpcServiceName('f250.export.v1.ExportService')
abstract class ExportServiceBase extends $grpc.Service {
  $core.String get $name => 'f250.export.v1.ExportService';

  ExportServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.ListRecordingsRequest,
            $0.ListRecordingsResponse>(
        'ListRecordings',
        listRecordings_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListRecordingsRequest.fromBuffer(value),
        ($0.ListRecordingsResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.WatchExportRequest, $0.WatchExportResponse>(
            'WatchExport',
            watchExport_Pre,
            false,
            true,
            ($core.List<$core.int> value) =>
                $0.WatchExportRequest.fromBuffer(value),
            ($0.WatchExportResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.StartCopyRequest, $0.StartCopyResponse>(
        'StartCopy',
        startCopy_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.StartCopyRequest.fromBuffer(value),
        ($0.StartCopyResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CancelCopyRequest, $0.CancelCopyResponse>(
        'CancelCopy',
        cancelCopy_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.CancelCopyRequest.fromBuffer(value),
        ($0.CancelCopyResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.ListRecordingsResponse> listRecordings_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListRecordingsRequest> $request) async {
    return listRecordings($call, await $request);
  }

  $async.Future<$0.ListRecordingsResponse> listRecordings(
      $grpc.ServiceCall call, $0.ListRecordingsRequest request);

  $async.Stream<$0.WatchExportResponse> watchExport_Pre($grpc.ServiceCall $call,
      $async.Future<$0.WatchExportRequest> $request) async* {
    yield* watchExport($call, await $request);
  }

  $async.Stream<$0.WatchExportResponse> watchExport(
      $grpc.ServiceCall call, $0.WatchExportRequest request);

  $async.Future<$0.StartCopyResponse> startCopy_Pre($grpc.ServiceCall $call,
      $async.Future<$0.StartCopyRequest> $request) async {
    return startCopy($call, await $request);
  }

  $async.Future<$0.StartCopyResponse> startCopy(
      $grpc.ServiceCall call, $0.StartCopyRequest request);

  $async.Future<$0.CancelCopyResponse> cancelCopy_Pre($grpc.ServiceCall $call,
      $async.Future<$0.CancelCopyRequest> $request) async {
    return cancelCopy($call, await $request);
  }

  $async.Future<$0.CancelCopyResponse> cancelCopy(
      $grpc.ServiceCall call, $0.CancelCopyRequest request);
}
