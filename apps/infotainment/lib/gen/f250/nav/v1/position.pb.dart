// This is a generated file - do not edit.
//
// Generated from f250/nav/v1/position.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'position.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'position.pbenum.dart';

class Fix extends $pb.GeneratedMessage {
  factory Fix({
    $core.double? latitudeDeg,
    $core.double? longitudeDeg,
    $fixnum.Int64? ageMs,
    $core.double? altitudeMslM,
    $core.double? speedMps,
    $core.double? trackDeg,
    $core.double? horizontalErrorM,
    $fixnum.Int64? utcTimeMs,
  }) {
    final result = Fix._();
    if (latitudeDeg != null) result.latitudeDeg = latitudeDeg;
    if (longitudeDeg != null) result.longitudeDeg = longitudeDeg;
    if (ageMs != null) result.ageMs = ageMs;
    if (altitudeMslM != null) result.altitudeMslM = altitudeMslM;
    if (speedMps != null) result.speedMps = speedMps;
    if (trackDeg != null) result.trackDeg = trackDeg;
    if (horizontalErrorM != null) result.horizontalErrorM = horizontalErrorM;
    if (utcTimeMs != null) result.utcTimeMs = utcTimeMs;
    return result;
  }

  Fix._();

  factory Fix.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Fix()..mergeFromBuffer(data, registry);
  factory Fix.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Fix()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Fix',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: Fix.$_createMessage)
    ..aD(1, _omitFieldNames ? '' : 'latitudeDeg')
    ..aD(2, _omitFieldNames ? '' : 'longitudeDeg')
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'ageMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aD(4, _omitFieldNames ? '' : 'altitudeMslM')
    ..aD(5, _omitFieldNames ? '' : 'speedMps')
    ..aD(6, _omitFieldNames ? '' : 'trackDeg')
    ..aD(7, _omitFieldNames ? '' : 'horizontalErrorM')
    ..aInt64(8, _omitFieldNames ? '' : 'utcTimeMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Fix clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Fix copyWith(void Function(Fix) updates) =>
      super.copyWith((message) => updates(message as Fix)) as Fix;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Fix() / Fix.new instead')
  static Fix create() => Fix._();
  static $pb.GeneratedMessage $_createMessage() => Fix._();
  @$core.override
  Fix createEmptyInstance() => Fix._();
  @$core.pragma('dart2js:noInline')
  static Fix getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Fix>(Fix.$_createMessage);
  static Fix? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get latitudeDeg => $_getN(0);
  @$pb.TagNumber(1)
  set latitudeDeg($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLatitudeDeg() => $_has(0);
  @$pb.TagNumber(1)
  void clearLatitudeDeg() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get longitudeDeg => $_getN(1);
  @$pb.TagNumber(2)
  set longitudeDeg($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLongitudeDeg() => $_has(1);
  @$pb.TagNumber(2)
  void clearLongitudeDeg() => $_clearField(2);

  /// How old the position was when this message was sent (monotonic).
  @$pb.TagNumber(3)
  $fixnum.Int64 get ageMs => $_getI64(2);
  @$pb.TagNumber(3)
  set ageMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAgeMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearAgeMs() => $_clearField(3);

  /// 3D fixes only. Above mean sea level.
  @$pb.TagNumber(4)
  $core.double get altitudeMslM => $_getN(3);
  @$pb.TagNumber(4)
  set altitudeMslM($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAltitudeMslM() => $_has(3);
  @$pb.TagNumber(4)
  void clearAltitudeMslM() => $_clearField(4);

  /// Speed over ground.
  @$pb.TagNumber(5)
  $core.double get speedMps => $_getN(4);
  @$pb.TagNumber(5)
  set speedMps($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSpeedMps() => $_has(4);
  @$pb.TagNumber(5)
  void clearSpeedMps() => $_clearField(5);

  /// Course over ground, degrees clockwise from true north.
  @$pb.TagNumber(6)
  $core.double get trackDeg => $_getN(5);
  @$pb.TagNumber(6)
  set trackDeg($core.double value) => $_setDouble(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTrackDeg() => $_has(5);
  @$pb.TagNumber(6)
  void clearTrackDeg() => $_clearField(6);

  /// gpsd's estimated horizontal error (`eph`). Its confidence level
  /// depends on the receiver.
  @$pb.TagNumber(7)
  $core.double get horizontalErrorM => $_getN(6);
  @$pb.TagNumber(7)
  set horizontalErrorM($core.double value) => $_setDouble(6, value);
  @$pb.TagNumber(7)
  $core.bool hasHorizontalErrorM() => $_has(6);
  @$pb.TagNumber(7)
  void clearHorizontalErrorM() => $_clearField(7);

  /// The receiver's UTC time for this fix, ms since the Unix epoch.
  @$pb.TagNumber(8)
  $fixnum.Int64 get utcTimeMs => $_getI64(7);
  @$pb.TagNumber(8)
  set utcTimeMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasUtcTimeMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearUtcTimeMs() => $_clearField(8);
}

class Position extends $pb.GeneratedMessage {
  factory Position({
    FixStatus? status,
    Fix? fix,
    $core.bool? current,
    $fixnum.Int64? staleAfterMs,
    $core.int? satellitesUsed,
    $core.int? satellitesVisible,
    $core.String? source,
    $core.bool? simulated,
    $core.String? detail,
  }) {
    final result = Position._();
    if (status != null) result.status = status;
    if (fix != null) result.fix = fix;
    if (current != null) result.current = current;
    if (staleAfterMs != null) result.staleAfterMs = staleAfterMs;
    if (satellitesUsed != null) result.satellitesUsed = satellitesUsed;
    if (satellitesVisible != null) result.satellitesVisible = satellitesVisible;
    if (source != null) result.source = source;
    if (simulated != null) result.simulated = simulated;
    if (detail != null) result.detail = detail;
    return result;
  }

  Position._();

  factory Position.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Position()..mergeFromBuffer(data, registry);
  factory Position.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Position()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Position',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: Position.$_createMessage)
    ..aE<FixStatus>(1, _omitFieldNames ? '' : 'status',
        enumValues: FixStatus.values)
    ..aOM<Fix>(2, _omitFieldNames ? '' : 'fix', subBuilder: Fix.$_createMessage)
    ..aOB(3, _omitFieldNames ? '' : 'current')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'staleAfterMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(5, _omitFieldNames ? '' : 'satellitesUsed',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'satellitesVisible',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(7, _omitFieldNames ? '' : 'source')
    ..aOB(8, _omitFieldNames ? '' : 'simulated')
    ..aOS(9, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Position clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Position copyWith(void Function(Position) updates) =>
      super.copyWith((message) => updates(message as Position)) as Position;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Position() / Position.new instead')
  static Position create() => Position._();
  static $pb.GeneratedMessage $_createMessage() => Position._();
  @$core.override
  Position createEmptyInstance() => Position._();
  @$core.pragma('dart2js:noInline')
  static Position getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Position>(Position.$_createMessage);
  static Position? _defaultInstance;

  @$pb.TagNumber(1)
  FixStatus get status => $_getN(0);
  @$pb.TagNumber(1)
  set status(FixStatus value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasStatus() => $_has(0);
  @$pb.TagNumber(1)
  void clearStatus() => $_clearField(1);

  /// The last good fix, present once there has been one, whatever the
  /// status now.
  @$pb.TagNumber(2)
  Fix get fix => $_getN(1);
  @$pb.TagNumber(2)
  set fix(Fix value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasFix() => $_has(1);
  @$pb.TagNumber(2)
  void clearFix() => $_clearField(2);
  @$pb.TagNumber(2)
  Fix ensureFix() => $_ensure(1);

  /// The fix is current: a fix status, and younger than stale_after_ms.
  /// Otherwise the fix may be shown only as "last known", with its age.
  @$pb.TagNumber(3)
  $core.bool get current => $_getBF(2);
  @$pb.TagNumber(3)
  set current($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCurrent() => $_has(2);
  @$pb.TagNumber(3)
  void clearCurrent() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get staleAfterMs => $_getI64(3);
  @$pb.TagNumber(4)
  set staleAfterMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasStaleAfterMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearStaleAfterMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get satellitesUsed => $_getIZ(4);
  @$pb.TagNumber(5)
  set satellitesUsed($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSatellitesUsed() => $_has(4);
  @$pb.TagNumber(5)
  void clearSatellitesUsed() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get satellitesVisible => $_getIZ(5);
  @$pb.TagNumber(6)
  set satellitesVisible($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSatellitesVisible() => $_has(5);
  @$pb.TagNumber(6)
  void clearSatellitesVisible() => $_clearField(6);

  /// Where it comes from: "gpsd 3.27.5: /dev/ttyACM0", or "simulated".
  @$pb.TagNumber(7)
  $core.String get source => $_getSZ(6);
  @$pb.TagNumber(7)
  set source($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSource() => $_has(6);
  @$pb.TagNumber(7)
  void clearSource() => $_clearField(7);

  /// True for the simulated receiver: never the truck's real position.
  @$pb.TagNumber(8)
  $core.bool get simulated => $_getBF(7);
  @$pb.TagNumber(8)
  set simulated($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasSimulated() => $_has(7);
  @$pb.TagNumber(8)
  void clearSimulated() => $_clearField(8);

  /// Why there is no current fix, for the screen. Empty while there is one.
  @$pb.TagNumber(9)
  $core.String get detail => $_getSZ(8);
  @$pb.TagNumber(9)
  set detail($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasDetail() => $_has(8);
  @$pb.TagNumber(9)
  void clearDetail() => $_clearField(9);
}

class WatchPositionRequest extends $pb.GeneratedMessage {
  factory WatchPositionRequest() => WatchPositionRequest._();

  WatchPositionRequest._();

  factory WatchPositionRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchPositionRequest()..mergeFromBuffer(data, registry);
  factory WatchPositionRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchPositionRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchPositionRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: WatchPositionRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchPositionRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchPositionRequest copyWith(void Function(WatchPositionRequest) updates) =>
      super.copyWith((message) => updates(message as WatchPositionRequest))
          as WatchPositionRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use WatchPositionRequest() / WatchPositionRequest.new instead')
  static WatchPositionRequest create() => WatchPositionRequest._();
  static $pb.GeneratedMessage $_createMessage() => WatchPositionRequest._();
  @$core.override
  WatchPositionRequest createEmptyInstance() => WatchPositionRequest._();
  @$core.pragma('dart2js:noInline')
  static WatchPositionRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WatchPositionRequest>(
          WatchPositionRequest.$_createMessage);
  static WatchPositionRequest? _defaultInstance;
}

class WatchPositionResponse extends $pb.GeneratedMessage {
  factory WatchPositionResponse({
    Position? position,
  }) {
    final result = WatchPositionResponse._();
    if (position != null) result.position = position;
    return result;
  }

  WatchPositionResponse._();

  factory WatchPositionResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchPositionResponse()..mergeFromBuffer(data, registry);
  factory WatchPositionResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchPositionResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchPositionResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: WatchPositionResponse.$_createMessage)
    ..aOM<Position>(1, _omitFieldNames ? '' : 'position',
        subBuilder: Position.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchPositionResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchPositionResponse copyWith(
          void Function(WatchPositionResponse) updates) =>
      super.copyWith((message) => updates(message as WatchPositionResponse))
          as WatchPositionResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use WatchPositionResponse() / WatchPositionResponse.new instead')
  static WatchPositionResponse create() => WatchPositionResponse._();
  static $pb.GeneratedMessage $_createMessage() => WatchPositionResponse._();
  @$core.override
  WatchPositionResponse createEmptyInstance() => WatchPositionResponse._();
  @$core.pragma('dart2js:noInline')
  static WatchPositionResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WatchPositionResponse>(
          WatchPositionResponse.$_createMessage);
  static WatchPositionResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Position get position => $_getN(0);
  @$pb.TagNumber(1)
  set position(Position value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPosition() => $_has(0);
  @$pb.TagNumber(1)
  void clearPosition() => $_clearField(1);
  @$pb.TagNumber(1)
  Position ensurePosition() => $_ensure(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
