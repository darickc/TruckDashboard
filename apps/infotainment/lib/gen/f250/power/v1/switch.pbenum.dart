// This is a generated file - do not edit.
//
// Generated from f250/power/v1/switch.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// One of the switch's five wires: a contact to ground on its own GPIO, which
/// the gpio-key overlay (agl/boot/config-f250.txt) makes a key. Named by the
/// key, which never changes; `WireInfo.pin` says which GPIO it is on.
class Wire extends $pb.ProtobufEnum {
  static const Wire WIRE_UNSPECIFIED =
      Wire._(0, _omitEnumNames ? '' : 'WIRE_UNSPECIFIED');
  static const Wire WIRE_F13 = Wire._(1, _omitEnumNames ? '' : 'WIRE_F13');
  static const Wire WIRE_F14 = Wire._(2, _omitEnumNames ? '' : 'WIRE_F14');
  static const Wire WIRE_F15 = Wire._(3, _omitEnumNames ? '' : 'WIRE_F15');
  static const Wire WIRE_F16 = Wire._(4, _omitEnumNames ? '' : 'WIRE_F16');
  static const Wire WIRE_F17 = Wire._(5, _omitEnumNames ? '' : 'WIRE_F17');

  static const $core.List<Wire> values = <Wire>[
    WIRE_UNSPECIFIED,
    WIRE_F13,
    WIRE_F14,
    WIRE_F15,
    WIRE_F16,
    WIRE_F17,
  ];

  static final $core.List<Wire?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static Wire? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Wire._(super.value, super.name);
}

/// What a wire does: its short and long press follow from the role (ADR-0051).
class Role extends $pb.ProtobufEnum {
  static const Role ROLE_UNSPECIFIED =
      Role._(0, _omitEnumNames ? '' : 'ROLE_UNSPECIFIED');

  /// Short: volume up a step. Long: front camera.
  static const Role ROLE_UP = Role._(1, _omitEnumNames ? '' : 'ROLE_UP');

  /// Short: volume down a step. Long: rear camera.
  static const Role ROLE_DOWN = Role._(2, _omitEnumNames ? '' : 'ROLE_DOWN');

  /// Short: previous track. Long: left camera.
  static const Role ROLE_LEFT = Role._(3, _omitEnumNames ? '' : 'ROLE_LEFT');

  /// Short: next track. Long: right camera.
  static const Role ROLE_RIGHT = Role._(4, _omitEnumNames ? '' : 'ROLE_RIGHT');

  /// Short: play/pause, answer a ringing call, hang up a call. Long: close the
  /// camera.
  static const Role ROLE_PRESS = Role._(5, _omitEnumNames ? '' : 'ROLE_PRESS');

  static const $core.List<Role> values = <Role>[
    ROLE_UNSPECIFIED,
    ROLE_UP,
    ROLE_DOWN,
    ROLE_LEFT,
    ROLE_RIGHT,
    ROLE_PRESS,
  ];

  static final $core.List<Role?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static Role? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Role._(super.value, super.name);
}

class PressKind extends $pb.ProtobufEnum {
  static const PressKind PRESS_KIND_UNSPECIFIED =
      PressKind._(0, _omitEnumNames ? '' : 'PRESS_KIND_UNSPECIFIED');
  static const PressKind PRESS_KIND_SHORT =
      PressKind._(1, _omitEnumNames ? '' : 'PRESS_KIND_SHORT');
  static const PressKind PRESS_KIND_LONG =
      PressKind._(2, _omitEnumNames ? '' : 'PRESS_KIND_LONG');

  static const $core.List<PressKind> values = <PressKind>[
    PRESS_KIND_UNSPECIFIED,
    PRESS_KIND_SHORT,
    PRESS_KIND_LONG,
  ];

  static final $core.List<PressKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static PressKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PressKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
