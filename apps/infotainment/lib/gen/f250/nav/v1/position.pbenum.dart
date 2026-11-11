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

import 'package:protobuf/protobuf.dart' as $pb;

/// What the receiver can say now.
class FixStatus extends $pb.ProtobufEnum {
  static const FixStatus FIX_STATUS_UNSPECIFIED =
      FixStatus._(0, _omitEnumNames ? '' : 'FIX_STATUS_UNSPECIFIED');

  /// gpsd isn't reachable.
  static const FixStatus FIX_STATUS_UNAVAILABLE =
      FixStatus._(1, _omitEnumNames ? '' : 'FIX_STATUS_UNAVAILABLE');

  /// gpsd has no receiver.
  static const FixStatus FIX_STATUS_NO_RECEIVER =
      FixStatus._(2, _omitEnumNames ? '' : 'FIX_STATUS_NO_RECEIVER');

  /// A receiver, but nothing from it within the stale limit.
  static const FixStatus FIX_STATUS_RECEIVER_SILENT =
      FixStatus._(3, _omitEnumNames ? '' : 'FIX_STATUS_RECEIVER_SILENT');

  /// The receiver reports no fix.
  static const FixStatus FIX_STATUS_NO_FIX =
      FixStatus._(4, _omitEnumNames ? '' : 'FIX_STATUS_NO_FIX');
  static const FixStatus FIX_STATUS_FIX_2D =
      FixStatus._(5, _omitEnumNames ? '' : 'FIX_STATUS_FIX_2D');
  static const FixStatus FIX_STATUS_FIX_3D =
      FixStatus._(6, _omitEnumNames ? '' : 'FIX_STATUS_FIX_3D');

  static const $core.List<FixStatus> values = <FixStatus>[
    FIX_STATUS_UNSPECIFIED,
    FIX_STATUS_UNAVAILABLE,
    FIX_STATUS_NO_RECEIVER,
    FIX_STATUS_RECEIVER_SILENT,
    FIX_STATUS_NO_FIX,
    FIX_STATUS_FIX_2D,
    FIX_STATUS_FIX_3D,
  ];

  static final $core.List<FixStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static FixStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const FixStatus._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
