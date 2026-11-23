// This is a generated file - do not edit.
//
// Generated from f250/nav/v1/online_map.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'online_map.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'online_map.pbenum.dart';

class GetOnlineMapStatusRequest extends $pb.GeneratedMessage {
  factory GetOnlineMapStatusRequest() => GetOnlineMapStatusRequest._();

  GetOnlineMapStatusRequest._();

  factory GetOnlineMapStatusRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetOnlineMapStatusRequest()..mergeFromBuffer(data, registry);
  factory GetOnlineMapStatusRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetOnlineMapStatusRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetOnlineMapStatusRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: GetOnlineMapStatusRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetOnlineMapStatusRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetOnlineMapStatusRequest copyWith(
          void Function(GetOnlineMapStatusRequest) updates) =>
      super.copyWith((message) => updates(message as GetOnlineMapStatusRequest))
          as GetOnlineMapStatusRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetOnlineMapStatusRequest() / GetOnlineMapStatusRequest.new instead')
  static GetOnlineMapStatusRequest create() => GetOnlineMapStatusRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      GetOnlineMapStatusRequest._();
  @$core.override
  GetOnlineMapStatusRequest createEmptyInstance() =>
      GetOnlineMapStatusRequest._();
  @$core.pragma('dart2js:noInline')
  static GetOnlineMapStatusRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetOnlineMapStatusRequest>(
          GetOnlineMapStatusRequest.$_createMessage);
  static GetOnlineMapStatusRequest? _defaultInstance;
}

class GetOnlineMapStatusResponse extends $pb.GeneratedMessage {
  factory GetOnlineMapStatusResponse({
    $core.bool? configured,
    $core.String? detail,
    $core.String? attribution,
    $core.int? tileSize,
    $core.int? maxZoom,
    $core.bool? routingOnline,
  }) {
    final result = GetOnlineMapStatusResponse._();
    if (configured != null) result.configured = configured;
    if (detail != null) result.detail = detail;
    if (attribution != null) result.attribution = attribution;
    if (tileSize != null) result.tileSize = tileSize;
    if (maxZoom != null) result.maxZoom = maxZoom;
    if (routingOnline != null) result.routingOnline = routingOnline;
    return result;
  }

  GetOnlineMapStatusResponse._();

  factory GetOnlineMapStatusResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetOnlineMapStatusResponse()..mergeFromBuffer(data, registry);
  factory GetOnlineMapStatusResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetOnlineMapStatusResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetOnlineMapStatusResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: GetOnlineMapStatusResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'configured')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..aOS(3, _omitFieldNames ? '' : 'attribution')
    ..aI(4, _omitFieldNames ? '' : 'tileSize', fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'maxZoom', fieldType: $pb.PbFieldType.OU3)
    ..aOB(6, _omitFieldNames ? '' : 'routingOnline')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetOnlineMapStatusResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetOnlineMapStatusResponse copyWith(
          void Function(GetOnlineMapStatusResponse) updates) =>
      super.copyWith(
              (message) => updates(message as GetOnlineMapStatusResponse))
          as GetOnlineMapStatusResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetOnlineMapStatusResponse() / GetOnlineMapStatusResponse.new instead')
  static GetOnlineMapStatusResponse create() => GetOnlineMapStatusResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      GetOnlineMapStatusResponse._();
  @$core.override
  GetOnlineMapStatusResponse createEmptyInstance() =>
      GetOnlineMapStatusResponse._();
  @$core.pragma('dart2js:noInline')
  static GetOnlineMapStatusResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetOnlineMapStatusResponse>(
          GetOnlineMapStatusResponse.$_createMessage);
  static GetOnlineMapStatusResponse? _defaultInstance;

  /// A Mapbox token is configured.
  @$pb.TagNumber(1)
  $core.bool get configured => $_getBF(0);
  @$pb.TagNumber(1)
  set configured($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConfigured() => $_has(0);
  @$pb.TagNumber(1)
  void clearConfigured() => $_clearField(1);

  /// Why not, or which styles: for the screen and the log.
  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);

  /// To show with the map: "© Mapbox © OpenStreetMap".
  @$pb.TagNumber(3)
  $core.String get attribution => $_getSZ(2);
  @$pb.TagNumber(3)
  set attribution($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAttribution() => $_has(2);
  @$pb.TagNumber(3)
  void clearAttribution() => $_clearField(3);

  /// The tiles' size in pixels (512): they are one zoom level behind
  /// 256-pixel tiles.
  @$pb.TagNumber(4)
  $core.int get tileSize => $_getIZ(3);
  @$pb.TagNumber(4)
  set tileSize($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTileSize() => $_has(3);
  @$pb.TagNumber(4)
  void clearTileSize() => $_clearField(4);

  /// The highest tile zoom asked for.
  @$pb.TagNumber(5)
  $core.int get maxZoom => $_getIZ(4);
  @$pb.TagNumber(5)
  set maxZoom($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMaxZoom() => $_has(4);
  @$pb.TagNumber(5)
  void clearMaxZoom() => $_clearField(5);

  /// Routes go to Mapbox first now: false while it is skipped after a
  /// failure (ADR-0052 decision 3), or without a token.
  @$pb.TagNumber(6)
  $core.bool get routingOnline => $_getBF(5);
  @$pb.TagNumber(6)
  set routingOnline($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasRoutingOnline() => $_has(5);
  @$pb.TagNumber(6)
  void clearRoutingOnline() => $_clearField(6);
}

class GetTileRequest extends $pb.GeneratedMessage {
  factory GetTileRequest({
    MapStyle? style,
    $core.int? z,
    $core.int? x,
    $core.int? y,
  }) {
    final result = GetTileRequest._();
    if (style != null) result.style = style;
    if (z != null) result.z = z;
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    return result;
  }

  GetTileRequest._();

  factory GetTileRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetTileRequest()..mergeFromBuffer(data, registry);
  factory GetTileRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetTileRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetTileRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: GetTileRequest.$_createMessage)
    ..aE<MapStyle>(1, _omitFieldNames ? '' : 'style',
        enumValues: MapStyle.values)
    ..aI(2, _omitFieldNames ? '' : 'z', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'x', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'y', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetTileRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetTileRequest copyWith(void Function(GetTileRequest) updates) =>
      super.copyWith((message) => updates(message as GetTileRequest))
          as GetTileRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetTileRequest() / GetTileRequest.new instead')
  static GetTileRequest create() => GetTileRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetTileRequest._();
  @$core.override
  GetTileRequest createEmptyInstance() => GetTileRequest._();
  @$core.pragma('dart2js:noInline')
  static GetTileRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetTileRequest>(
          GetTileRequest.$_createMessage);
  static GetTileRequest? _defaultInstance;

  @$pb.TagNumber(1)
  MapStyle get style => $_getN(0);
  @$pb.TagNumber(1)
  set style(MapStyle value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasStyle() => $_has(0);
  @$pb.TagNumber(1)
  void clearStyle() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get z => $_getIZ(1);
  @$pb.TagNumber(2)
  set z($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasZ() => $_has(1);
  @$pb.TagNumber(2)
  void clearZ() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get x => $_getIZ(2);
  @$pb.TagNumber(3)
  set x($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasX() => $_has(2);
  @$pb.TagNumber(3)
  void clearX() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get y => $_getIZ(3);
  @$pb.TagNumber(4)
  set y($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasY() => $_has(3);
  @$pb.TagNumber(4)
  void clearY() => $_clearField(4);
}

class GetTileResponse extends $pb.GeneratedMessage {
  factory GetTileResponse({
    $core.List<$core.int>? data,
    $core.String? contentType,
  }) {
    final result = GetTileResponse._();
    if (data != null) result.data = data;
    if (contentType != null) result.contentType = contentType;
    return result;
  }

  GetTileResponse._();

  factory GetTileResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetTileResponse()..mergeFromBuffer(data, registry);
  factory GetTileResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetTileResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetTileResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: GetTileResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'contentType')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetTileResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetTileResponse copyWith(void Function(GetTileResponse) updates) =>
      super.copyWith((message) => updates(message as GetTileResponse))
          as GetTileResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetTileResponse() / GetTileResponse.new instead')
  static GetTileResponse create() => GetTileResponse._();
  static $pb.GeneratedMessage $_createMessage() => GetTileResponse._();
  @$core.override
  GetTileResponse createEmptyInstance() => GetTileResponse._();
  @$core.pragma('dart2js:noInline')
  static GetTileResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetTileResponse>(
          GetTileResponse.$_createMessage);
  static GetTileResponse? _defaultInstance;

  /// The image as Mapbox sent it (PNG or JPEG).
  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get contentType => $_getSZ(1);
  @$pb.TagNumber(2)
  set contentType($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasContentType() => $_has(1);
  @$pb.TagNumber(2)
  void clearContentType() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
