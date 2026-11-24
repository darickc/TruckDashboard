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
    $core.bool? vector,
  }) {
    final result = GetOnlineMapStatusResponse._();
    if (configured != null) result.configured = configured;
    if (detail != null) result.detail = detail;
    if (attribution != null) result.attribution = attribution;
    if (tileSize != null) result.tileSize = tileSize;
    if (maxZoom != null) result.maxZoom = maxZoom;
    if (routingOnline != null) result.routingOnline = routingOnline;
    if (vector != null) result.vector = vector;
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
    ..aOB(7, _omitFieldNames ? '' : 'vector')
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

  /// The tiles are Mapbox Vector Tiles, drawn with GetMapStyle's style;
  /// false: raster images (the fields above).
  @$pb.TagNumber(7)
  $core.bool get vector => $_getBF(6);
  @$pb.TagNumber(7)
  set vector($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasVector() => $_has(6);
  @$pb.TagNumber(7)
  void clearVector() => $_clearField(7);
}

class GetTileRequest extends $pb.GeneratedMessage {
  factory GetTileRequest({
    MapStyle? style,
    $core.int? z,
    $core.int? x,
    $core.int? y,
    $core.String? source,
  }) {
    final result = GetTileRequest._();
    if (style != null) result.style = style;
    if (z != null) result.z = z;
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (source != null) result.source = source;
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
    ..aOS(5, _omitFieldNames ? '' : 'source')
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

  /// Vector: the style's source id ("composite", "mapbox-traffic"), at that
  /// source's zooms (GetMapStyleResponse). Empty: a raster tile.
  @$pb.TagNumber(5)
  $core.String get source => $_getSZ(4);
  @$pb.TagNumber(5)
  set source($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSource() => $_has(4);
  @$pb.TagNumber(5)
  void clearSource() => $_clearField(5);
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

  /// Raster: the image as Mapbox sent it (PNG or JPEG). Vector: the tile,
  /// uncompressed; empty where Mapbox has none.
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

class GetMapStyleRequest extends $pb.GeneratedMessage {
  factory GetMapStyleRequest({
    MapStyle? style,
    $core.int? pixelRatio,
  }) {
    final result = GetMapStyleRequest._();
    if (style != null) result.style = style;
    if (pixelRatio != null) result.pixelRatio = pixelRatio;
    return result;
  }

  GetMapStyleRequest._();

  factory GetMapStyleRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetMapStyleRequest()..mergeFromBuffer(data, registry);
  factory GetMapStyleRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetMapStyleRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetMapStyleRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: GetMapStyleRequest.$_createMessage)
    ..aE<MapStyle>(1, _omitFieldNames ? '' : 'style',
        enumValues: MapStyle.values)
    ..aI(2, _omitFieldNames ? '' : 'pixelRatio', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMapStyleRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMapStyleRequest copyWith(void Function(GetMapStyleRequest) updates) =>
      super.copyWith((message) => updates(message as GetMapStyleRequest))
          as GetMapStyleRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetMapStyleRequest() / GetMapStyleRequest.new instead')
  static GetMapStyleRequest create() => GetMapStyleRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetMapStyleRequest._();
  @$core.override
  GetMapStyleRequest createEmptyInstance() => GetMapStyleRequest._();
  @$core.pragma('dart2js:noInline')
  static GetMapStyleRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetMapStyleRequest>(
          GetMapStyleRequest.$_createMessage);
  static GetMapStyleRequest? _defaultInstance;

  @$pb.TagNumber(1)
  MapStyle get style => $_getN(0);
  @$pb.TagNumber(1)
  set style(MapStyle value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasStyle() => $_has(0);
  @$pb.TagNumber(1)
  void clearStyle() => $_clearField(1);

  /// The screen's pixels per logical pixel: 1 gets Mapbox's 1x sprites, 0
  /// (unset) or 2 and up its 2x. The bench Pi's panel is 1; its GPU can't
  /// hold the 2x sheet (4416 pixels wide), and a shrunk sheet puts every
  /// icon in the wrong place (bench-log 2026-11-24).
  @$pb.TagNumber(2)
  $core.int get pixelRatio => $_getIZ(1);
  @$pb.TagNumber(2)
  set pixelRatio($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPixelRatio() => $_has(1);
  @$pb.TagNumber(2)
  void clearPixelRatio() => $_clearField(2);
}

class MapSource extends $pb.GeneratedMessage {
  factory MapSource({
    $core.String? id,
    $core.int? minZoom,
    $core.int? maxZoom,
  }) {
    final result = MapSource._();
    if (id != null) result.id = id;
    if (minZoom != null) result.minZoom = minZoom;
    if (maxZoom != null) result.maxZoom = maxZoom;
    return result;
  }

  MapSource._();

  factory MapSource.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapSource()..mergeFromBuffer(data, registry);
  factory MapSource.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapSource()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MapSource',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: MapSource.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aI(2, _omitFieldNames ? '' : 'minZoom', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'maxZoom', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapSource clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapSource copyWith(void Function(MapSource) updates) =>
      super.copyWith((message) => updates(message as MapSource)) as MapSource;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MapSource() / MapSource.new instead')
  static MapSource create() => MapSource._();
  static $pb.GeneratedMessage $_createMessage() => MapSource._();
  @$core.override
  MapSource createEmptyInstance() => MapSource._();
  @$core.pragma('dart2js:noInline')
  static MapSource getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MapSource>(MapSource.$_createMessage);
  static MapSource? _defaultInstance;

  /// The id the style's layers name ("composite").
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// The zooms Mapbox has tiles for (its TileJSON); past max_zoom the
  /// dashboard draws max_zoom's tiles larger.
  @$pb.TagNumber(2)
  $core.int get minZoom => $_getIZ(1);
  @$pb.TagNumber(2)
  set minZoom($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMinZoom() => $_has(1);
  @$pb.TagNumber(2)
  void clearMinZoom() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get maxZoom => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxZoom($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMaxZoom() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxZoom() => $_clearField(3);
}

class GetMapStyleResponse extends $pb.GeneratedMessage {
  factory GetMapStyleResponse({
    $core.String? styleJson,
    $core.String? spriteJson,
    $core.List<$core.int>? spritePng,
    $core.Iterable<MapSource>? sources,
  }) {
    final result = GetMapStyleResponse._();
    if (styleJson != null) result.styleJson = styleJson;
    if (spriteJson != null) result.spriteJson = spriteJson;
    if (spritePng != null) result.spritePng = spritePng;
    if (sources != null) result.sources.addAll(sources);
    return result;
  }

  GetMapStyleResponse._();

  factory GetMapStyleResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetMapStyleResponse()..mergeFromBuffer(data, registry);
  factory GetMapStyleResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetMapStyleResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetMapStyleResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: GetMapStyleResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'styleJson')
    ..aOS(2, _omitFieldNames ? '' : 'spriteJson')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'spritePng', $pb.PbFieldType.OY)
    ..pPM<MapSource>(4, _omitFieldNames ? '' : 'sources',
        subBuilder: MapSource.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMapStyleResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMapStyleResponse copyWith(void Function(GetMapStyleResponse) updates) =>
      super.copyWith((message) => updates(message as GetMapStyleResponse))
          as GetMapStyleResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use GetMapStyleResponse() / GetMapStyleResponse.new instead')
  static GetMapStyleResponse create() => GetMapStyleResponse._();
  static $pb.GeneratedMessage $_createMessage() => GetMapStyleResponse._();
  @$core.override
  GetMapStyleResponse createEmptyInstance() => GetMapStyleResponse._();
  @$core.pragma('dart2js:noInline')
  static GetMapStyleResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetMapStyleResponse>(
          GetMapStyleResponse.$_createMessage);
  static GetMapStyleResponse? _defaultInstance;

  /// Mapbox's style document (JSON) as sent, with its `mapbox://` URLs: the
  /// dashboard asks GetTile for each source by id, not those URLs.
  @$pb.TagNumber(1)
  $core.String get styleJson => $_getSZ(0);
  @$pb.TagNumber(1)
  set styleJson($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStyleJson() => $_has(0);
  @$pb.TagNumber(1)
  void clearStyleJson() => $_clearField(1);

  /// The sprites at 2x: the index (JSON) and the image (PNG).
  @$pb.TagNumber(2)
  $core.String get spriteJson => $_getSZ(1);
  @$pb.TagNumber(2)
  set spriteJson($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSpriteJson() => $_has(1);
  @$pb.TagNumber(2)
  void clearSpriteJson() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get spritePng => $_getN(2);
  @$pb.TagNumber(3)
  set spritePng($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSpritePng() => $_has(2);
  @$pb.TagNumber(3)
  void clearSpritePng() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<MapSource> get sources => $_getList(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
