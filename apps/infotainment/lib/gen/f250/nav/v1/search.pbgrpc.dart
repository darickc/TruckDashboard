// This is a generated file - do not edit.
//
// Generated from f250/nav/v1/search.proto.

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

import 'search.pb.dart' as $0;

export 'search.pb.dart';

@$pb.GrpcServiceName('f250.nav.v1.SearchService')
class SearchServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  SearchServiceClient(super.channel, {super.options, super.interceptors});

  /// Results for a typed query, best first, ranked near the truck. Cheap
  /// enough to call on every keystroke. Never fails for a missing index:
  /// `available` is false and `detail` says why.
  $grpc.ResponseFuture<$0.SearchResponse> search(
    $0.SearchRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$search, request, options: options);
  }

  // method descriptors

  static final _$search =
      $grpc.ClientMethod<$0.SearchRequest, $0.SearchResponse>(
          '/f250.nav.v1.SearchService/Search',
          ($0.SearchRequest value) => value.writeToBuffer(),
          $0.SearchResponse.fromBuffer);
}

@$pb.GrpcServiceName('f250.nav.v1.SearchService')
abstract class SearchServiceBase extends $grpc.Service {
  $core.String get $name => 'f250.nav.v1.SearchService';

  SearchServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.SearchRequest, $0.SearchResponse>(
        'Search',
        search_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.SearchRequest.fromBuffer(value),
        ($0.SearchResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.SearchResponse> search_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.SearchRequest> $request) async {
    return search($call, await $request);
  }

  $async.Future<$0.SearchResponse> search(
      $grpc.ServiceCall call, $0.SearchRequest request);
}
