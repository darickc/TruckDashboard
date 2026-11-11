// This is a generated file - do not edit.
//
// Generated from f250/camera/v1/camera.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class Camera extends $pb.ProtobufEnum {
  static const Camera CAMERA_UNSPECIFIED =
      Camera._(0, _omitEnumNames ? '' : 'CAMERA_UNSPECIFIED');
  static const Camera CAMERA_LEFT =
      Camera._(1, _omitEnumNames ? '' : 'CAMERA_LEFT');
  static const Camera CAMERA_RIGHT =
      Camera._(2, _omitEnumNames ? '' : 'CAMERA_RIGHT');
  static const Camera CAMERA_REAR =
      Camera._(3, _omitEnumNames ? '' : 'CAMERA_REAR');

  /// Added 2026-11-10: the switch's forward move shows it by default.
  static const Camera CAMERA_FRONT =
      Camera._(4, _omitEnumNames ? '' : 'CAMERA_FRONT');

  static const $core.List<Camera> values = <Camera>[
    CAMERA_UNSPECIFIED,
    CAMERA_LEFT,
    CAMERA_RIGHT,
    CAMERA_REAR,
    CAMERA_FRONT,
  ];

  static final $core.List<Camera?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static Camera? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Camera._(super.value, super.name);
}

class SwitchMove extends $pb.ProtobufEnum {
  static const SwitchMove SWITCH_MOVE_UNSPECIFIED =
      SwitchMove._(0, _omitEnumNames ? '' : 'SWITCH_MOVE_UNSPECIFIED');
  static const SwitchMove SWITCH_MOVE_LEFT =
      SwitchMove._(1, _omitEnumNames ? '' : 'SWITCH_MOVE_LEFT');
  static const SwitchMove SWITCH_MOVE_RIGHT =
      SwitchMove._(2, _omitEnumNames ? '' : 'SWITCH_MOVE_RIGHT');
  static const SwitchMove SWITCH_MOVE_BACK =
      SwitchMove._(3, _omitEnumNames ? '' : 'SWITCH_MOVE_BACK');
  static const SwitchMove SWITCH_MOVE_FORWARD =
      SwitchMove._(4, _omitEnumNames ? '' : 'SWITCH_MOVE_FORWARD');
  static const SwitchMove SWITCH_MOVE_PRESS =
      SwitchMove._(5, _omitEnumNames ? '' : 'SWITCH_MOVE_PRESS');

  static const $core.List<SwitchMove> values = <SwitchMove>[
    SWITCH_MOVE_UNSPECIFIED,
    SWITCH_MOVE_LEFT,
    SWITCH_MOVE_RIGHT,
    SWITCH_MOVE_BACK,
    SWITCH_MOVE_FORWARD,
    SWITCH_MOVE_PRESS,
  ];

  static final $core.List<SwitchMove?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static SwitchMove? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const SwitchMove._(super.value, super.name);
}

/// Why a camera is on screen.
class Reason extends $pb.ProtobufEnum {
  static const Reason REASON_UNSPECIFIED =
      Reason._(0, _omitEnumNames ? '' : 'REASON_UNSPECIFIED');
  static const Reason REASON_REVERSE =
      Reason._(1, _omitEnumNames ? '' : 'REASON_REVERSE');
  static const Reason REASON_SWITCH =
      Reason._(2, _omitEnumNames ? '' : 'REASON_SWITCH');

  static const $core.List<Reason> values = <Reason>[
    REASON_UNSPECIFIED,
    REASON_REVERSE,
    REASON_SWITCH,
  ];

  static final $core.List<Reason?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static Reason? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Reason._(super.value, super.name);
}

/// The reverse signal, for the dashboard's indicator.
class ReverseStatus extends $pb.ProtobufEnum {
  static const ReverseStatus REVERSE_STATUS_UNSPECIFIED =
      ReverseStatus._(0, _omitEnumNames ? '' : 'REVERSE_STATUS_UNSPECIFIED');

  /// Automatic reverse is switched off in camera-manager's configuration.
  static const ReverseStatus REVERSE_STATUS_OFF =
      ReverseStatus._(1, _omitEnumNames ? '' : 'REVERSE_STATUS_OFF');

  /// Stale, invalid or never received: must be shown as unknown.
  static const ReverseStatus REVERSE_STATUS_UNKNOWN =
      ReverseStatus._(2, _omitEnumNames ? '' : 'REVERSE_STATUS_UNKNOWN');
  static const ReverseStatus REVERSE_STATUS_NOT_ENGAGED =
      ReverseStatus._(3, _omitEnumNames ? '' : 'REVERSE_STATUS_NOT_ENGAGED');
  static const ReverseStatus REVERSE_STATUS_ENGAGED =
      ReverseStatus._(4, _omitEnumNames ? '' : 'REVERSE_STATUS_ENGAGED');

  static const $core.List<ReverseStatus> values = <ReverseStatus>[
    REVERSE_STATUS_UNSPECIFIED,
    REVERSE_STATUS_OFF,
    REVERSE_STATUS_UNKNOWN,
    REVERSE_STATUS_NOT_ENGAGED,
    REVERSE_STATUS_ENGAGED,
  ];

  static final $core.List<ReverseStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static ReverseStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ReverseStatus._(super.value, super.name);
}

/// The chosen camera's feed.
class FeedState extends $pb.ProtobufEnum {
  static const FeedState FEED_STATE_UNSPECIFIED =
      FeedState._(0, _omitEnumNames ? '' : 'FEED_STATE_UNSPECIFIED');

  /// The pipeline is starting and hasn't delivered a frame yet.
  static const FeedState FEED_STATE_STARTING =
      FeedState._(1, _omitEnumNames ? '' : 'FEED_STATE_STARTING');

  /// Frames are arriving; the camera's window is on screen.
  static const FeedState FEED_STATE_LIVE =
      FeedState._(2, _omitEnumNames ? '' : 'FEED_STATE_LIVE');

  /// No frames (no device, a failed pipeline, frames stopped). The window is
  /// closed; the dashboard shows "Camera unavailable" in its place.
  static const FeedState FEED_STATE_UNAVAILABLE =
      FeedState._(3, _omitEnumNames ? '' : 'FEED_STATE_UNAVAILABLE');

  static const $core.List<FeedState> values = <FeedState>[
    FEED_STATE_UNSPECIFIED,
    FEED_STATE_STARTING,
    FEED_STATE_LIVE,
    FEED_STATE_UNAVAILABLE,
  ];

  static final $core.List<FeedState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static FeedState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const FeedState._(super.value, super.name);
}

/// One recorded camera's state (ADR-0027 decisions 1 and 9).
class RecordingState extends $pb.ProtobufEnum {
  static const RecordingState RECORDING_STATE_UNSPECIFIED =
      RecordingState._(0, _omitEnumNames ? '' : 'RECORDING_STATE_UNSPECIFIED');

  /// The camera is set to record and the pipeline is starting: no segment
  /// has received a frame yet.
  static const RecordingState RECORDING_STATE_STARTING =
      RecordingState._(1, _omitEnumNames ? '' : 'RECORDING_STATE_STARTING');

  /// Frames are reaching a segment on the data drive.
  static const RecordingState RECORDING_STATE_RECORDING =
      RecordingState._(2, _omitEnumNames ? '' : 'RECORDING_STATE_RECORDING');

  /// Set to record but not recording: no drive, no device, the drive is
  /// full, frames stopped, or this build can't record. `detail` says which.
  /// The dashboard raises an advisory for it: a dead dashcam must not be
  /// discovered after the incident it missed.
  static const RecordingState RECORDING_STATE_NOT_RECORDING = RecordingState._(
      3, _omitEnumNames ? '' : 'RECORDING_STATE_NOT_RECORDING');

  static const $core.List<RecordingState> values = <RecordingState>[
    RECORDING_STATE_UNSPECIFIED,
    RECORDING_STATE_STARTING,
    RECORDING_STATE_RECORDING,
    RECORDING_STATE_NOT_RECORDING,
  ];

  static final $core.List<RecordingState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static RecordingState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const RecordingState._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
