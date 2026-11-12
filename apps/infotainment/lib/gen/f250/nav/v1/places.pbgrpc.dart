// This is a generated file - do not edit.
//
// Generated from f250/nav/v1/places.proto.

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

import 'places.pb.dart' as $0;

export 'places.pb.dart';

@$pb.GrpcServiceName('f250.nav.v1.PlacesService')
class PlacesServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  PlacesServiceClient(super.channel, {super.options, super.interceptors});

  /// Every saved place. Never fails for a missing or unreadable file:
  /// `storage` says what happened.
  $grpc.ResponseFuture<$0.ListPlacesResponse> listPlaces(
    $0.ListPlacesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listPlaces, request, options: options);
  }

  /// Saves a place as Home (replacing any) or as a favourite. A favourite
  /// needs a name. Returns the places after the change.
  $grpc.ResponseFuture<$0.SavePlaceResponse> savePlace(
    $0.SavePlaceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$savePlace, request, options: options);
  }

  /// Renames a place of any kind. NOT_FOUND for an unknown id.
  $grpc.ResponseFuture<$0.RenamePlaceResponse> renamePlace(
    $0.RenamePlaceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$renamePlace, request, options: options);
  }

  /// Deletes a place of any kind. NOT_FOUND for an unknown id.
  $grpc.ResponseFuture<$0.DeletePlaceResponse> deletePlace(
    $0.DeletePlaceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$deletePlace, request, options: options);
  }

  // method descriptors

  static final _$listPlaces =
      $grpc.ClientMethod<$0.ListPlacesRequest, $0.ListPlacesResponse>(
          '/f250.nav.v1.PlacesService/ListPlaces',
          ($0.ListPlacesRequest value) => value.writeToBuffer(),
          $0.ListPlacesResponse.fromBuffer);
  static final _$savePlace =
      $grpc.ClientMethod<$0.SavePlaceRequest, $0.SavePlaceResponse>(
          '/f250.nav.v1.PlacesService/SavePlace',
          ($0.SavePlaceRequest value) => value.writeToBuffer(),
          $0.SavePlaceResponse.fromBuffer);
  static final _$renamePlace =
      $grpc.ClientMethod<$0.RenamePlaceRequest, $0.RenamePlaceResponse>(
          '/f250.nav.v1.PlacesService/RenamePlace',
          ($0.RenamePlaceRequest value) => value.writeToBuffer(),
          $0.RenamePlaceResponse.fromBuffer);
  static final _$deletePlace =
      $grpc.ClientMethod<$0.DeletePlaceRequest, $0.DeletePlaceResponse>(
          '/f250.nav.v1.PlacesService/DeletePlace',
          ($0.DeletePlaceRequest value) => value.writeToBuffer(),
          $0.DeletePlaceResponse.fromBuffer);
}

@$pb.GrpcServiceName('f250.nav.v1.PlacesService')
abstract class PlacesServiceBase extends $grpc.Service {
  $core.String get $name => 'f250.nav.v1.PlacesService';

  PlacesServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.ListPlacesRequest, $0.ListPlacesResponse>(
        'ListPlaces',
        listPlaces_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ListPlacesRequest.fromBuffer(value),
        ($0.ListPlacesResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SavePlaceRequest, $0.SavePlaceResponse>(
        'SavePlace',
        savePlace_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.SavePlaceRequest.fromBuffer(value),
        ($0.SavePlaceResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.RenamePlaceRequest, $0.RenamePlaceResponse>(
            'RenamePlace',
            renamePlace_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.RenamePlaceRequest.fromBuffer(value),
            ($0.RenamePlaceResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.DeletePlaceRequest, $0.DeletePlaceResponse>(
            'DeletePlace',
            deletePlace_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.DeletePlaceRequest.fromBuffer(value),
            ($0.DeletePlaceResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.ListPlacesResponse> listPlaces_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ListPlacesRequest> $request) async {
    return listPlaces($call, await $request);
  }

  $async.Future<$0.ListPlacesResponse> listPlaces(
      $grpc.ServiceCall call, $0.ListPlacesRequest request);

  $async.Future<$0.SavePlaceResponse> savePlace_Pre($grpc.ServiceCall $call,
      $async.Future<$0.SavePlaceRequest> $request) async {
    return savePlace($call, await $request);
  }

  $async.Future<$0.SavePlaceResponse> savePlace(
      $grpc.ServiceCall call, $0.SavePlaceRequest request);

  $async.Future<$0.RenamePlaceResponse> renamePlace_Pre($grpc.ServiceCall $call,
      $async.Future<$0.RenamePlaceRequest> $request) async {
    return renamePlace($call, await $request);
  }

  $async.Future<$0.RenamePlaceResponse> renamePlace(
      $grpc.ServiceCall call, $0.RenamePlaceRequest request);

  $async.Future<$0.DeletePlaceResponse> deletePlace_Pre($grpc.ServiceCall $call,
      $async.Future<$0.DeletePlaceRequest> $request) async {
    return deletePlace($call, await $request);
  }

  $async.Future<$0.DeletePlaceResponse> deletePlace(
      $grpc.ServiceCall call, $0.DeletePlaceRequest request);
}
