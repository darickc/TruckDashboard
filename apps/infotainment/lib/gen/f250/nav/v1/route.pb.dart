// This is a generated file - do not edit.
//
// Generated from f250/nav/v1/route.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'route.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'route.pbenum.dart';

class LatLon extends $pb.GeneratedMessage {
  factory LatLon({
    $core.double? latitudeDeg,
    $core.double? longitudeDeg,
  }) {
    final result = LatLon._();
    if (latitudeDeg != null) result.latitudeDeg = latitudeDeg;
    if (longitudeDeg != null) result.longitudeDeg = longitudeDeg;
    return result;
  }

  LatLon._();

  factory LatLon.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LatLon()..mergeFromBuffer(data, registry);
  factory LatLon.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LatLon()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LatLon',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: LatLon.$_createMessage)
    ..aD(1, _omitFieldNames ? '' : 'latitudeDeg')
    ..aD(2, _omitFieldNames ? '' : 'longitudeDeg')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LatLon clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LatLon copyWith(void Function(LatLon) updates) =>
      super.copyWith((message) => updates(message as LatLon)) as LatLon;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use LatLon() / LatLon.new instead')
  static LatLon create() => LatLon._();
  static $pb.GeneratedMessage $_createMessage() => LatLon._();
  @$core.override
  LatLon createEmptyInstance() => LatLon._();
  @$core.pragma('dart2js:noInline')
  static LatLon getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LatLon>(LatLon.$_createMessage);
  static LatLon? _defaultInstance;

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
}

class Maneuver extends $pb.GeneratedMessage {
  factory Maneuver({
    $core.int? type,
    $core.String? instruction,
    $core.Iterable<$core.String>? streetNames,
    $core.double? lengthM,
    $core.double? timeS,
    $core.int? beginShapeIndex,
    $core.double? startM,
  }) {
    final result = Maneuver._();
    if (type != null) result.type = type;
    if (instruction != null) result.instruction = instruction;
    if (streetNames != null) result.streetNames.addAll(streetNames);
    if (lengthM != null) result.lengthM = lengthM;
    if (timeS != null) result.timeS = timeS;
    if (beginShapeIndex != null) result.beginShapeIndex = beginShapeIndex;
    if (startM != null) result.startM = startM;
    return result;
  }

  Maneuver._();

  factory Maneuver.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Maneuver()..mergeFromBuffer(data, registry);
  factory Maneuver.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Maneuver()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Maneuver',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: Maneuver.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'type', fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'instruction')
    ..pPS(3, _omitFieldNames ? '' : 'streetNames')
    ..aD(4, _omitFieldNames ? '' : 'lengthM')
    ..aD(5, _omitFieldNames ? '' : 'timeS')
    ..aI(6, _omitFieldNames ? '' : 'beginShapeIndex',
        fieldType: $pb.PbFieldType.OU3)
    ..aD(7, _omitFieldNames ? '' : 'startM')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Maneuver clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Maneuver copyWith(void Function(Maneuver) updates) =>
      super.copyWith((message) => updates(message as Maneuver)) as Maneuver;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Maneuver() / Maneuver.new instead')
  static Maneuver create() => Maneuver._();
  static $pb.GeneratedMessage $_createMessage() => Maneuver._();
  @$core.override
  Maneuver createEmptyInstance() => Maneuver._();
  @$core.pragma('dart2js:noInline')
  static Maneuver getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Maneuver>(Maneuver.$_createMessage);
  static Maneuver? _defaultInstance;

  /// Valhalla's maneuver type (odin's DirectionsLeg_Maneuver_Type, e.g.
  /// 10 right, 15 left, 4 destination), for the icon.
  @$pb.TagNumber(1)
  $core.int get type => $_getIZ(0);
  @$pb.TagNumber(1)
  set type($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => $_clearField(1);

  /// Valhalla's text, e.g. "Turn right onto US 36/US 281."
  @$pb.TagNumber(2)
  $core.String get instruction => $_getSZ(1);
  @$pb.TagNumber(2)
  set instruction($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasInstruction() => $_has(1);
  @$pb.TagNumber(2)
  void clearInstruction() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get streetNames => $_getList(2);

  /// From this maneuver to the next.
  @$pb.TagNumber(4)
  $core.double get lengthM => $_getN(3);
  @$pb.TagNumber(4)
  set lengthM($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLengthM() => $_has(3);
  @$pb.TagNumber(4)
  void clearLengthM() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get timeS => $_getN(4);
  @$pb.TagNumber(5)
  set timeS($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTimeS() => $_has(4);
  @$pb.TagNumber(5)
  void clearTimeS() => $_clearField(5);

  /// Where it starts, as an index into Route.shape and as a distance from
  /// the route's start.
  @$pb.TagNumber(6)
  $core.int get beginShapeIndex => $_getIZ(5);
  @$pb.TagNumber(6)
  set beginShapeIndex($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasBeginShapeIndex() => $_has(5);
  @$pb.TagNumber(6)
  void clearBeginShapeIndex() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.double get startM => $_getN(6);
  @$pb.TagNumber(7)
  set startM($core.double value) => $_setDouble(6, value);
  @$pb.TagNumber(7)
  $core.bool hasStartM() => $_has(6);
  @$pb.TagNumber(7)
  void clearStartM() => $_clearField(7);
}

class Route extends $pb.GeneratedMessage {
  factory Route({
    $fixnum.Int64? id,
    $core.Iterable<LatLon>? shape,
    $core.Iterable<Maneuver>? maneuvers,
    $core.double? lengthM,
    $core.double? timeS,
    LatLon? destination,
    $core.String? costing,
    $core.bool? hasToll,
    $core.bool? hasHighway,
    $core.bool? hasFerry,
  }) {
    final result = Route._();
    if (id != null) result.id = id;
    if (shape != null) result.shape.addAll(shape);
    if (maneuvers != null) result.maneuvers.addAll(maneuvers);
    if (lengthM != null) result.lengthM = lengthM;
    if (timeS != null) result.timeS = timeS;
    if (destination != null) result.destination = destination;
    if (costing != null) result.costing = costing;
    if (hasToll != null) result.hasToll = hasToll;
    if (hasHighway != null) result.hasHighway = hasHighway;
    if (hasFerry != null) result.hasFerry = hasFerry;
    return result;
  }

  Route._();

  factory Route.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Route()..mergeFromBuffer(data, registry);
  factory Route.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Route()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Route',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: Route.$_createMessage)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'id', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..pPM<LatLon>(2, _omitFieldNames ? '' : 'shape',
        subBuilder: LatLon.$_createMessage)
    ..pPM<Maneuver>(3, _omitFieldNames ? '' : 'maneuvers',
        subBuilder: Maneuver.$_createMessage)
    ..aD(4, _omitFieldNames ? '' : 'lengthM')
    ..aD(5, _omitFieldNames ? '' : 'timeS')
    ..aOM<LatLon>(6, _omitFieldNames ? '' : 'destination',
        subBuilder: LatLon.$_createMessage)
    ..aOS(7, _omitFieldNames ? '' : 'costing')
    ..aOB(8, _omitFieldNames ? '' : 'hasToll')
    ..aOB(9, _omitFieldNames ? '' : 'hasHighway')
    ..aOB(10, _omitFieldNames ? '' : 'hasFerry')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Route clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Route copyWith(void Function(Route) updates) =>
      super.copyWith((message) => updates(message as Route)) as Route;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Route() / Route.new instead')
  static Route create() => Route._();
  static $pb.GeneratedMessage $_createMessage() => Route._();
  @$core.override
  Route createEmptyInstance() => Route._();
  @$core.pragma('dart2js:noInline')
  static Route getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Route>(Route.$_createMessage);
  static Route? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<LatLon> get shape => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<Maneuver> get maneuvers => $_getList(2);

  @$pb.TagNumber(4)
  $core.double get lengthM => $_getN(3);
  @$pb.TagNumber(4)
  set lengthM($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLengthM() => $_has(3);
  @$pb.TagNumber(4)
  void clearLengthM() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get timeS => $_getN(4);
  @$pb.TagNumber(5)
  set timeS($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTimeS() => $_has(4);
  @$pb.TagNumber(5)
  void clearTimeS() => $_clearField(5);

  @$pb.TagNumber(6)
  LatLon get destination => $_getN(5);
  @$pb.TagNumber(6)
  set destination(LatLon value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasDestination() => $_has(5);
  @$pb.TagNumber(6)
  void clearDestination() => $_clearField(6);
  @$pb.TagNumber(6)
  LatLon ensureDestination() => $_ensure(5);

  /// Valhalla's costing model: "auto", or "truck" with configured dimensions.
  @$pb.TagNumber(7)
  $core.String get costing => $_getSZ(6);
  @$pb.TagNumber(7)
  set costing($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasCosting() => $_has(6);
  @$pb.TagNumber(7)
  void clearCosting() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get hasToll => $_getBF(7);
  @$pb.TagNumber(8)
  set hasToll($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasHasToll() => $_has(7);
  @$pb.TagNumber(8)
  void clearHasToll() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get hasHighway => $_getBF(8);
  @$pb.TagNumber(9)
  set hasHighway($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasHasHighway() => $_has(8);
  @$pb.TagNumber(9)
  void clearHasHighway() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.bool get hasFerry => $_getBF(9);
  @$pb.TagNumber(10)
  set hasFerry($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(10)
  $core.bool hasHasFerry() => $_has(9);
  @$pb.TagNumber(10)
  void clearHasFerry() => $_clearField(10);
}

/// Where the truck is along the route. Only while the position is current:
/// stale progress is never sent (CLAUDE.md rule 4).
class Progress extends $pb.GeneratedMessage {
  factory Progress({
    $core.int? maneuverIndex,
    $core.double? toManeuverM,
    $core.double? remainingM,
    $core.double? remainingS,
    $core.double? offRouteM,
    $core.bool? offRoute,
  }) {
    final result = Progress._();
    if (maneuverIndex != null) result.maneuverIndex = maneuverIndex;
    if (toManeuverM != null) result.toManeuverM = toManeuverM;
    if (remainingM != null) result.remainingM = remainingM;
    if (remainingS != null) result.remainingS = remainingS;
    if (offRouteM != null) result.offRouteM = offRouteM;
    if (offRoute != null) result.offRoute = offRoute;
    return result;
  }

  Progress._();

  factory Progress.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Progress()..mergeFromBuffer(data, registry);
  factory Progress.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Progress()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Progress',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: Progress.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'maneuverIndex',
        fieldType: $pb.PbFieldType.OU3)
    ..aD(2, _omitFieldNames ? '' : 'toManeuverM')
    ..aD(3, _omitFieldNames ? '' : 'remainingM')
    ..aD(4, _omitFieldNames ? '' : 'remainingS')
    ..aD(5, _omitFieldNames ? '' : 'offRouteM')
    ..aOB(6, _omitFieldNames ? '' : 'offRoute')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Progress clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Progress copyWith(void Function(Progress) updates) =>
      super.copyWith((message) => updates(message as Progress)) as Progress;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Progress() / Progress.new instead')
  static Progress create() => Progress._();
  static $pb.GeneratedMessage $_createMessage() => Progress._();
  @$core.override
  Progress createEmptyInstance() => Progress._();
  @$core.pragma('dart2js:noInline')
  static Progress getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Progress>(Progress.$_createMessage);
  static Progress? _defaultInstance;

  /// The next maneuver, an index into Route.maneuvers.
  @$pb.TagNumber(1)
  $core.int get maneuverIndex => $_getIZ(0);
  @$pb.TagNumber(1)
  set maneuverIndex($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasManeuverIndex() => $_has(0);
  @$pb.TagNumber(1)
  void clearManeuverIndex() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get toManeuverM => $_getN(1);
  @$pb.TagNumber(2)
  set toManeuverM($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasToManeuverM() => $_has(1);
  @$pb.TagNumber(2)
  void clearToManeuverM() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get remainingM => $_getN(2);
  @$pb.TagNumber(3)
  set remainingM($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRemainingM() => $_has(2);
  @$pb.TagNumber(3)
  void clearRemainingM() => $_clearField(3);

  /// Valhalla's estimate for the rest of the route, scaled by what is left.
  @$pb.TagNumber(4)
  $core.double get remainingS => $_getN(3);
  @$pb.TagNumber(4)
  set remainingS($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRemainingS() => $_has(3);
  @$pb.TagNumber(4)
  void clearRemainingS() => $_clearField(4);

  /// How far the position is from the route line.
  @$pb.TagNumber(5)
  $core.double get offRouteM => $_getN(4);
  @$pb.TagNumber(5)
  set offRouteM($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasOffRouteM() => $_has(4);
  @$pb.TagNumber(5)
  void clearOffRouteM() => $_clearField(5);

  /// Farther than the off-route limit: a new route is coming.
  @$pb.TagNumber(6)
  $core.bool get offRoute => $_getBF(5);
  @$pb.TagNumber(6)
  set offRoute($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasOffRoute() => $_has(5);
  @$pb.TagNumber(6)
  void clearOffRoute() => $_clearField(6);
}

class Guidance extends $pb.GeneratedMessage {
  factory Guidance({
    RouteState? state,
    $fixnum.Int64? routeId,
    LatLon? destination,
    Progress? progress,
    $core.String? detail,
    $core.int? reroutes,
  }) {
    final result = Guidance._();
    if (state != null) result.state = state;
    if (routeId != null) result.routeId = routeId;
    if (destination != null) result.destination = destination;
    if (progress != null) result.progress = progress;
    if (detail != null) result.detail = detail;
    if (reroutes != null) result.reroutes = reroutes;
    return result;
  }

  Guidance._();

  factory Guidance.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Guidance()..mergeFromBuffer(data, registry);
  factory Guidance.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Guidance()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Guidance',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: Guidance.$_createMessage)
    ..aE<RouteState>(1, _omitFieldNames ? '' : 'state',
        enumValues: RouteState.values)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'routeId', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<LatLon>(3, _omitFieldNames ? '' : 'destination',
        subBuilder: LatLon.$_createMessage)
    ..aOM<Progress>(4, _omitFieldNames ? '' : 'progress',
        subBuilder: Progress.$_createMessage)
    ..aOS(5, _omitFieldNames ? '' : 'detail')
    ..aI(6, _omitFieldNames ? '' : 'reroutes', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Guidance clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Guidance copyWith(void Function(Guidance) updates) =>
      super.copyWith((message) => updates(message as Guidance)) as Guidance;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Guidance() / Guidance.new instead')
  static Guidance create() => Guidance._();
  static $pb.GeneratedMessage $_createMessage() => Guidance._();
  @$core.override
  Guidance createEmptyInstance() => Guidance._();
  @$core.pragma('dart2js:noInline')
  static Guidance getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Guidance>(Guidance.$_createMessage);
  static Guidance? _defaultInstance;

  @$pb.TagNumber(1)
  RouteState get state => $_getN(0);
  @$pb.TagNumber(1)
  set state(RouteState value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasState() => $_has(0);
  @$pb.TagNumber(1)
  void clearState() => $_clearField(1);

  /// The route on screen, 0 for none. GetRoute fetches it when it changes.
  @$pb.TagNumber(2)
  $fixnum.Int64 get routeId => $_getI64(1);
  @$pb.TagNumber(2)
  set routeId($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRouteId() => $_has(1);
  @$pb.TagNumber(2)
  void clearRouteId() => $_clearField(2);

  /// Present while there is a destination.
  @$pb.TagNumber(3)
  LatLon get destination => $_getN(2);
  @$pb.TagNumber(3)
  set destination(LatLon value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasDestination() => $_has(2);
  @$pb.TagNumber(3)
  void clearDestination() => $_clearField(3);
  @$pb.TagNumber(3)
  LatLon ensureDestination() => $_ensure(2);

  /// Present only on a route with a current position.
  @$pb.TagNumber(4)
  Progress get progress => $_getN(3);
  @$pb.TagNumber(4)
  set progress(Progress value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasProgress() => $_has(3);
  @$pb.TagNumber(4)
  void clearProgress() => $_clearField(4);
  @$pb.TagNumber(4)
  Progress ensureProgress() => $_ensure(3);

  /// Why: unavailable, failed, waiting for a position, rerouting.
  @$pb.TagNumber(5)
  $core.String get detail => $_getSZ(4);
  @$pb.TagNumber(5)
  set detail($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDetail() => $_has(4);
  @$pb.TagNumber(5)
  void clearDetail() => $_clearField(5);

  /// New routes after leaving the route, for this destination.
  @$pb.TagNumber(6)
  $core.int get reroutes => $_getIZ(5);
  @$pb.TagNumber(6)
  set reroutes($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasReroutes() => $_has(5);
  @$pb.TagNumber(6)
  void clearReroutes() => $_clearField(6);
}

class SetDestinationRequest extends $pb.GeneratedMessage {
  factory SetDestinationRequest({
    LatLon? destination,
  }) {
    final result = SetDestinationRequest._();
    if (destination != null) result.destination = destination;
    return result;
  }

  SetDestinationRequest._();

  factory SetDestinationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetDestinationRequest()..mergeFromBuffer(data, registry);
  factory SetDestinationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetDestinationRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetDestinationRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: SetDestinationRequest.$_createMessage)
    ..aOM<LatLon>(1, _omitFieldNames ? '' : 'destination',
        subBuilder: LatLon.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetDestinationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetDestinationRequest copyWith(
          void Function(SetDestinationRequest) updates) =>
      super.copyWith((message) => updates(message as SetDestinationRequest))
          as SetDestinationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SetDestinationRequest() / SetDestinationRequest.new instead')
  static SetDestinationRequest create() => SetDestinationRequest._();
  static $pb.GeneratedMessage $_createMessage() => SetDestinationRequest._();
  @$core.override
  SetDestinationRequest createEmptyInstance() => SetDestinationRequest._();
  @$core.pragma('dart2js:noInline')
  static SetDestinationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetDestinationRequest>(
          SetDestinationRequest.$_createMessage);
  static SetDestinationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  LatLon get destination => $_getN(0);
  @$pb.TagNumber(1)
  set destination(LatLon value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasDestination() => $_has(0);
  @$pb.TagNumber(1)
  void clearDestination() => $_clearField(1);
  @$pb.TagNumber(1)
  LatLon ensureDestination() => $_ensure(0);
}

class SetDestinationResponse extends $pb.GeneratedMessage {
  factory SetDestinationResponse() => SetDestinationResponse._();

  SetDestinationResponse._();

  factory SetDestinationResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetDestinationResponse()..mergeFromBuffer(data, registry);
  factory SetDestinationResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetDestinationResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetDestinationResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: SetDestinationResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetDestinationResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetDestinationResponse copyWith(
          void Function(SetDestinationResponse) updates) =>
      super.copyWith((message) => updates(message as SetDestinationResponse))
          as SetDestinationResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SetDestinationResponse() / SetDestinationResponse.new instead')
  static SetDestinationResponse create() => SetDestinationResponse._();
  static $pb.GeneratedMessage $_createMessage() => SetDestinationResponse._();
  @$core.override
  SetDestinationResponse createEmptyInstance() => SetDestinationResponse._();
  @$core.pragma('dart2js:noInline')
  static SetDestinationResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetDestinationResponse>(
          SetDestinationResponse.$_createMessage);
  static SetDestinationResponse? _defaultInstance;
}

class ClearRouteRequest extends $pb.GeneratedMessage {
  factory ClearRouteRequest() => ClearRouteRequest._();

  ClearRouteRequest._();

  factory ClearRouteRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ClearRouteRequest()..mergeFromBuffer(data, registry);
  factory ClearRouteRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ClearRouteRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ClearRouteRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: ClearRouteRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClearRouteRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClearRouteRequest copyWith(void Function(ClearRouteRequest) updates) =>
      super.copyWith((message) => updates(message as ClearRouteRequest))
          as ClearRouteRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ClearRouteRequest() / ClearRouteRequest.new instead')
  static ClearRouteRequest create() => ClearRouteRequest._();
  static $pb.GeneratedMessage $_createMessage() => ClearRouteRequest._();
  @$core.override
  ClearRouteRequest createEmptyInstance() => ClearRouteRequest._();
  @$core.pragma('dart2js:noInline')
  static ClearRouteRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ClearRouteRequest>(
          ClearRouteRequest.$_createMessage);
  static ClearRouteRequest? _defaultInstance;
}

class ClearRouteResponse extends $pb.GeneratedMessage {
  factory ClearRouteResponse() => ClearRouteResponse._();

  ClearRouteResponse._();

  factory ClearRouteResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ClearRouteResponse()..mergeFromBuffer(data, registry);
  factory ClearRouteResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ClearRouteResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ClearRouteResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: ClearRouteResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClearRouteResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClearRouteResponse copyWith(void Function(ClearRouteResponse) updates) =>
      super.copyWith((message) => updates(message as ClearRouteResponse))
          as ClearRouteResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ClearRouteResponse() / ClearRouteResponse.new instead')
  static ClearRouteResponse create() => ClearRouteResponse._();
  static $pb.GeneratedMessage $_createMessage() => ClearRouteResponse._();
  @$core.override
  ClearRouteResponse createEmptyInstance() => ClearRouteResponse._();
  @$core.pragma('dart2js:noInline')
  static ClearRouteResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ClearRouteResponse>(
          ClearRouteResponse.$_createMessage);
  static ClearRouteResponse? _defaultInstance;
}

class WatchGuidanceRequest extends $pb.GeneratedMessage {
  factory WatchGuidanceRequest() => WatchGuidanceRequest._();

  WatchGuidanceRequest._();

  factory WatchGuidanceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchGuidanceRequest()..mergeFromBuffer(data, registry);
  factory WatchGuidanceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchGuidanceRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchGuidanceRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: WatchGuidanceRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchGuidanceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchGuidanceRequest copyWith(void Function(WatchGuidanceRequest) updates) =>
      super.copyWith((message) => updates(message as WatchGuidanceRequest))
          as WatchGuidanceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use WatchGuidanceRequest() / WatchGuidanceRequest.new instead')
  static WatchGuidanceRequest create() => WatchGuidanceRequest._();
  static $pb.GeneratedMessage $_createMessage() => WatchGuidanceRequest._();
  @$core.override
  WatchGuidanceRequest createEmptyInstance() => WatchGuidanceRequest._();
  @$core.pragma('dart2js:noInline')
  static WatchGuidanceRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WatchGuidanceRequest>(
          WatchGuidanceRequest.$_createMessage);
  static WatchGuidanceRequest? _defaultInstance;
}

class WatchGuidanceResponse extends $pb.GeneratedMessage {
  factory WatchGuidanceResponse({
    Guidance? guidance,
  }) {
    final result = WatchGuidanceResponse._();
    if (guidance != null) result.guidance = guidance;
    return result;
  }

  WatchGuidanceResponse._();

  factory WatchGuidanceResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchGuidanceResponse()..mergeFromBuffer(data, registry);
  factory WatchGuidanceResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchGuidanceResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchGuidanceResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: WatchGuidanceResponse.$_createMessage)
    ..aOM<Guidance>(1, _omitFieldNames ? '' : 'guidance',
        subBuilder: Guidance.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchGuidanceResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchGuidanceResponse copyWith(
          void Function(WatchGuidanceResponse) updates) =>
      super.copyWith((message) => updates(message as WatchGuidanceResponse))
          as WatchGuidanceResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use WatchGuidanceResponse() / WatchGuidanceResponse.new instead')
  static WatchGuidanceResponse create() => WatchGuidanceResponse._();
  static $pb.GeneratedMessage $_createMessage() => WatchGuidanceResponse._();
  @$core.override
  WatchGuidanceResponse createEmptyInstance() => WatchGuidanceResponse._();
  @$core.pragma('dart2js:noInline')
  static WatchGuidanceResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WatchGuidanceResponse>(
          WatchGuidanceResponse.$_createMessage);
  static WatchGuidanceResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Guidance get guidance => $_getN(0);
  @$pb.TagNumber(1)
  set guidance(Guidance value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasGuidance() => $_has(0);
  @$pb.TagNumber(1)
  void clearGuidance() => $_clearField(1);
  @$pb.TagNumber(1)
  Guidance ensureGuidance() => $_ensure(0);
}

class GetRouteRequest extends $pb.GeneratedMessage {
  factory GetRouteRequest({
    $fixnum.Int64? routeId,
  }) {
    final result = GetRouteRequest._();
    if (routeId != null) result.routeId = routeId;
    return result;
  }

  GetRouteRequest._();

  factory GetRouteRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetRouteRequest()..mergeFromBuffer(data, registry);
  factory GetRouteRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetRouteRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetRouteRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: GetRouteRequest.$_createMessage)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'routeId', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetRouteRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetRouteRequest copyWith(void Function(GetRouteRequest) updates) =>
      super.copyWith((message) => updates(message as GetRouteRequest))
          as GetRouteRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetRouteRequest() / GetRouteRequest.new instead')
  static GetRouteRequest create() => GetRouteRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetRouteRequest._();
  @$core.override
  GetRouteRequest createEmptyInstance() => GetRouteRequest._();
  @$core.pragma('dart2js:noInline')
  static GetRouteRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetRouteRequest>(
          GetRouteRequest.$_createMessage);
  static GetRouteRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get routeId => $_getI64(0);
  @$pb.TagNumber(1)
  set routeId($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRouteId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRouteId() => $_clearField(1);
}

class GetRouteResponse extends $pb.GeneratedMessage {
  factory GetRouteResponse({
    Route? route,
  }) {
    final result = GetRouteResponse._();
    if (route != null) result.route = route;
    return result;
  }

  GetRouteResponse._();

  factory GetRouteResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetRouteResponse()..mergeFromBuffer(data, registry);
  factory GetRouteResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetRouteResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetRouteResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: GetRouteResponse.$_createMessage)
    ..aOM<Route>(1, _omitFieldNames ? '' : 'route',
        subBuilder: Route.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetRouteResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetRouteResponse copyWith(void Function(GetRouteResponse) updates) =>
      super.copyWith((message) => updates(message as GetRouteResponse))
          as GetRouteResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetRouteResponse() / GetRouteResponse.new instead')
  static GetRouteResponse create() => GetRouteResponse._();
  static $pb.GeneratedMessage $_createMessage() => GetRouteResponse._();
  @$core.override
  GetRouteResponse createEmptyInstance() => GetRouteResponse._();
  @$core.pragma('dart2js:noInline')
  static GetRouteResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetRouteResponse>(
          GetRouteResponse.$_createMessage);
  static GetRouteResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Route get route => $_getN(0);
  @$pb.TagNumber(1)
  set route(Route value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasRoute() => $_has(0);
  @$pb.TagNumber(1)
  void clearRoute() => $_clearField(1);
  @$pb.TagNumber(1)
  Route ensureRoute() => $_ensure(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
