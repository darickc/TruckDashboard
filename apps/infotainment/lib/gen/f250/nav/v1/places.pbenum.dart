// This is a generated file - do not edit.
//
// Generated from f250/nav/v1/places.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class PlaceKind extends $pb.ProtobufEnum {
  static const PlaceKind PLACE_KIND_UNSPECIFIED =
      PlaceKind._(0, _omitEnumNames ? '' : 'PLACE_KIND_UNSPECIFIED');
  static const PlaceKind PLACE_KIND_HOME =
      PlaceKind._(1, _omitEnumNames ? '' : 'PLACE_KIND_HOME');
  static const PlaceKind PLACE_KIND_FAVOURITE =
      PlaceKind._(2, _omitEnumNames ? '' : 'PLACE_KIND_FAVOURITE');

  /// Added by SetDestination, newest first, bounded.
  static const PlaceKind PLACE_KIND_RECENT =
      PlaceKind._(3, _omitEnumNames ? '' : 'PLACE_KIND_RECENT');

  static const $core.List<PlaceKind> values = <PlaceKind>[
    PLACE_KIND_UNSPECIFIED,
    PLACE_KIND_HOME,
    PLACE_KIND_FAVOURITE,
    PLACE_KIND_RECENT,
  ];

  static final $core.List<PlaceKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static PlaceKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PlaceKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
