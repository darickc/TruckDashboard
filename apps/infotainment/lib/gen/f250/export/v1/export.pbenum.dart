// This is a generated file - do not edit.
//
// Generated from f250/export/v1/export.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// What a stick is to the head unit.
class StickRole extends $pb.ProtobufEnum {
  static const StickRole STICK_ROLE_UNSPECIFIED =
      StickRole._(0, _omitEnumNames ? '' : 'STICK_ROLE_UNSPECIFIED');

  /// Being looked at: mounted read-only for a moment to read its free space.
  static const StickRole STICK_ROLE_CHECKING =
      StickRole._(1, _omitEnumNames ? '' : 'STICK_ROLE_CHECKING');

  /// An exFAT or FAT stick without map data: recordings can be copied to it.
  static const StickRole STICK_ROLE_EXPORT =
      StickRole._(2, _omitEnumNames ? '' : 'STICK_ROLE_EXPORT');

  /// It has f250/map.pmtiles, f250/routing.tar or f250/search.sqlite: the
  /// map import's (ADR-0033). Recordings are never copied to a map stick.
  static const StickRole STICK_ROLE_MAP =
      StickRole._(3, _omitEnumNames ? '' : 'STICK_ROLE_MAP');

  /// Not usable: another filesystem, none, or it couldn't be mounted.
  /// `detail` says why.
  static const StickRole STICK_ROLE_UNUSABLE =
      StickRole._(4, _omitEnumNames ? '' : 'STICK_ROLE_UNUSABLE');

  static const $core.List<StickRole> values = <StickRole>[
    STICK_ROLE_UNSPECIFIED,
    STICK_ROLE_CHECKING,
    STICK_ROLE_EXPORT,
    STICK_ROLE_MAP,
    STICK_ROLE_UNUSABLE,
  ];

  static final $core.List<StickRole?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static StickRole? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const StickRole._(super.value, super.name);
}

class CopyState extends $pb.ProtobufEnum {
  static const CopyState COPY_STATE_UNSPECIFIED =
      CopyState._(0, _omitEnumNames ? '' : 'COPY_STATE_UNSPECIFIED');

  /// No copy since the service started.
  static const CopyState COPY_STATE_IDLE =
      CopyState._(1, _omitEnumNames ? '' : 'COPY_STATE_IDLE');

  /// Mounting the stick and checking it has room.
  static const CopyState COPY_STATE_PREPARING =
      CopyState._(2, _omitEnumNames ? '' : 'COPY_STATE_PREPARING');
  static const CopyState COPY_STATE_COPYING =
      CopyState._(3, _omitEnumNames ? '' : 'COPY_STATE_COPYING');

  /// Every file is written: flushing the stick and unmounting it. The stick
  /// must stay in.
  static const CopyState COPY_STATE_FINISHING =
      CopyState._(4, _omitEnumNames ? '' : 'COPY_STATE_FINISHING');

  /// Done: every file is on the stick, which is synced and unmounted.
  static const CopyState COPY_STATE_DONE =
      CopyState._(5, _omitEnumNames ? '' : 'COPY_STATE_DONE');

  /// Stopped by a problem (`detail`): no stick, full, read-only, removed.
  static const CopyState COPY_STATE_FAILED =
      CopyState._(6, _omitEnumNames ? '' : 'COPY_STATE_FAILED');

  /// Stopped by CancelCopy.
  static const CopyState COPY_STATE_CANCELLED =
      CopyState._(7, _omitEnumNames ? '' : 'COPY_STATE_CANCELLED');

  static const $core.List<CopyState> values = <CopyState>[
    COPY_STATE_UNSPECIFIED,
    COPY_STATE_IDLE,
    COPY_STATE_PREPARING,
    COPY_STATE_COPYING,
    COPY_STATE_FINISHING,
    COPY_STATE_DONE,
    COPY_STATE_FAILED,
    COPY_STATE_CANCELLED,
  ];

  static final $core.List<CopyState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 7);
  static CopyState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const CopyState._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
