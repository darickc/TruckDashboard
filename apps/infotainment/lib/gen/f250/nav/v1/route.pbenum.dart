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

import 'package:protobuf/protobuf.dart' as $pb;

class RouteState extends $pb.ProtobufEnum {
  static const RouteState ROUTE_STATE_UNSPECIFIED =
      RouteState._(0, _omitEnumNames ? '' : 'ROUTE_STATE_UNSPECIFIED');

  /// Routing can't work here: no Valhalla, or no routing data. `detail`
  /// says which.
  static const RouteState ROUTE_STATE_UNAVAILABLE =
      RouteState._(1, _omitEnumNames ? '' : 'ROUTE_STATE_UNAVAILABLE');

  /// No destination.
  static const RouteState ROUTE_STATE_IDLE =
      RouteState._(2, _omitEnumNames ? '' : 'ROUTE_STATE_IDLE');

  /// Asking Valhalla: the first route, or a new one after leaving the route.
  /// A previous route (route_id) may still be shown meanwhile.
  static const RouteState ROUTE_STATE_ROUTING =
      RouteState._(3, _omitEnumNames ? '' : 'ROUTE_STATE_ROUTING');

  /// A route, being followed.
  static const RouteState ROUTE_STATE_ACTIVE =
      RouteState._(4, _omitEnumNames ? '' : 'ROUTE_STATE_ACTIVE');

  /// The last request failed; `detail` says why. The destination is kept,
  /// and SetDestination again retries.
  static const RouteState ROUTE_STATE_FAILED =
      RouteState._(5, _omitEnumNames ? '' : 'ROUTE_STATE_FAILED');

  /// Within the arrival distance of the destination.
  static const RouteState ROUTE_STATE_ARRIVED =
      RouteState._(6, _omitEnumNames ? '' : 'ROUTE_STATE_ARRIVED');

  static const $core.List<RouteState> values = <RouteState>[
    ROUTE_STATE_UNSPECIFIED,
    ROUTE_STATE_UNAVAILABLE,
    ROUTE_STATE_IDLE,
    ROUTE_STATE_ROUTING,
    ROUTE_STATE_ACTIVE,
    ROUTE_STATE_FAILED,
    ROUTE_STATE_ARRIVED,
  ];

  static final $core.List<RouteState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static RouteState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const RouteState._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
