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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'camera.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'camera.pbenum.dart';

class View extends $pb.GeneratedMessage {
  factory View({
    Camera? camera,
    Reason? reason,
    FeedState? feed,
    $core.String? feedDetail,
    ReverseStatus? reverse,
    $core.bool? blockedBySpeed,
  }) {
    final result = View._();
    if (camera != null) result.camera = camera;
    if (reason != null) result.reason = reason;
    if (feed != null) result.feed = feed;
    if (feedDetail != null) result.feedDetail = feedDetail;
    if (reverse != null) result.reverse = reverse;
    if (blockedBySpeed != null) result.blockedBySpeed = blockedBySpeed;
    return result;
  }

  View._();

  factory View.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      View()..mergeFromBuffer(data, registry);
  factory View.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      View()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'View',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.camera.v1'),
      createEmptyInstance: View.$_createMessage)
    ..aE<Camera>(1, _omitFieldNames ? '' : 'camera', enumValues: Camera.values)
    ..aE<Reason>(2, _omitFieldNames ? '' : 'reason', enumValues: Reason.values)
    ..aE<FeedState>(3, _omitFieldNames ? '' : 'feed',
        enumValues: FeedState.values)
    ..aOS(4, _omitFieldNames ? '' : 'feedDetail')
    ..aE<ReverseStatus>(5, _omitFieldNames ? '' : 'reverse',
        enumValues: ReverseStatus.values)
    ..aOB(6, _omitFieldNames ? '' : 'blockedBySpeed')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  View clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  View copyWith(void Function(View) updates) =>
      super.copyWith((message) => updates(message as View)) as View;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use View() / View.new instead')
  static View create() => View._();
  static $pb.GeneratedMessage $_createMessage() => View._();
  @$core.override
  View createEmptyInstance() => View._();
  @$core.pragma('dart2js:noInline')
  static View getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<View>(View.$_createMessage);
  static View? _defaultInstance;

  /// The camera on screen. Unset (CAMERA_UNSPECIFIED): no camera, the
  /// dashboard shows the screen it showed before.
  @$pb.TagNumber(1)
  Camera get camera => $_getN(0);
  @$pb.TagNumber(1)
  set camera(Camera value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCamera() => $_has(0);
  @$pb.TagNumber(1)
  void clearCamera() => $_clearField(1);

  @$pb.TagNumber(2)
  Reason get reason => $_getN(1);
  @$pb.TagNumber(2)
  set reason(Reason value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearReason() => $_clearField(2);

  /// Meaningful only while `camera` is set.
  @$pb.TagNumber(3)
  FeedState get feed => $_getN(2);
  @$pb.TagNumber(3)
  set feed(FeedState value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasFeed() => $_has(2);
  @$pb.TagNumber(3)
  void clearFeed() => $_clearField(3);

  /// Why the feed is unavailable, for the log and a detail line on screen.
  @$pb.TagNumber(4)
  $core.String get feedDetail => $_getSZ(3);
  @$pb.TagNumber(4)
  set feedDetail($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFeedDetail() => $_has(3);
  @$pb.TagNumber(4)
  void clearFeedDetail() => $_clearField(4);

  @$pb.TagNumber(5)
  ReverseStatus get reverse => $_getN(4);
  @$pb.TagNumber(5)
  set reverse(ReverseStatus value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasReverse() => $_has(4);
  @$pb.TagNumber(5)
  void clearReverse() => $_clearField(5);

  /// A camera is chosen, but the speed limit (or an unknown speed) hides it.
  @$pb.TagNumber(6)
  $core.bool get blockedBySpeed => $_getBF(5);
  @$pb.TagNumber(6)
  set blockedBySpeed($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasBlockedBySpeed() => $_has(5);
  @$pb.TagNumber(6)
  void clearBlockedBySpeed() => $_clearField(6);
}

class WatchViewRequest extends $pb.GeneratedMessage {
  factory WatchViewRequest() => WatchViewRequest._();

  WatchViewRequest._();

  factory WatchViewRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchViewRequest()..mergeFromBuffer(data, registry);
  factory WatchViewRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchViewRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchViewRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.camera.v1'),
      createEmptyInstance: WatchViewRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchViewRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchViewRequest copyWith(void Function(WatchViewRequest) updates) =>
      super.copyWith((message) => updates(message as WatchViewRequest))
          as WatchViewRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WatchViewRequest() / WatchViewRequest.new instead')
  static WatchViewRequest create() => WatchViewRequest._();
  static $pb.GeneratedMessage $_createMessage() => WatchViewRequest._();
  @$core.override
  WatchViewRequest createEmptyInstance() => WatchViewRequest._();
  @$core.pragma('dart2js:noInline')
  static WatchViewRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WatchViewRequest>(
          WatchViewRequest.$_createMessage);
  static WatchViewRequest? _defaultInstance;
}

class WatchViewResponse extends $pb.GeneratedMessage {
  factory WatchViewResponse({
    View? view,
  }) {
    final result = WatchViewResponse._();
    if (view != null) result.view = view;
    return result;
  }

  WatchViewResponse._();

  factory WatchViewResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchViewResponse()..mergeFromBuffer(data, registry);
  factory WatchViewResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchViewResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchViewResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.camera.v1'),
      createEmptyInstance: WatchViewResponse.$_createMessage)
    ..aOM<View>(1, _omitFieldNames ? '' : 'view',
        subBuilder: View.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchViewResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchViewResponse copyWith(void Function(WatchViewResponse) updates) =>
      super.copyWith((message) => updates(message as WatchViewResponse))
          as WatchViewResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WatchViewResponse() / WatchViewResponse.new instead')
  static WatchViewResponse create() => WatchViewResponse._();
  static $pb.GeneratedMessage $_createMessage() => WatchViewResponse._();
  @$core.override
  WatchViewResponse createEmptyInstance() => WatchViewResponse._();
  @$core.pragma('dart2js:noInline')
  static WatchViewResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WatchViewResponse>(
          WatchViewResponse.$_createMessage);
  static WatchViewResponse? _defaultInstance;

  @$pb.TagNumber(1)
  View get view => $_getN(0);
  @$pb.TagNumber(1)
  set view(View value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasView() => $_has(0);
  @$pb.TagNumber(1)
  void clearView() => $_clearField(1);
  @$pb.TagNumber(1)
  View ensureView() => $_ensure(0);
}

class MoveRequest extends $pb.GeneratedMessage {
  factory MoveRequest({
    SwitchMove? move,
    $core.String? source,
  }) {
    final result = MoveRequest._();
    if (move != null) result.move = move;
    if (source != null) result.source = source;
    return result;
  }

  MoveRequest._();

  factory MoveRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MoveRequest()..mergeFromBuffer(data, registry);
  factory MoveRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MoveRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MoveRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.camera.v1'),
      createEmptyInstance: MoveRequest.$_createMessage)
    ..aE<SwitchMove>(1, _omitFieldNames ? '' : 'move',
        enumValues: SwitchMove.values)
    ..aOS(2, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MoveRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MoveRequest copyWith(void Function(MoveRequest) updates) =>
      super.copyWith((message) => updates(message as MoveRequest))
          as MoveRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MoveRequest() / MoveRequest.new instead')
  static MoveRequest create() => MoveRequest._();
  static $pb.GeneratedMessage $_createMessage() => MoveRequest._();
  @$core.override
  MoveRequest createEmptyInstance() => MoveRequest._();
  @$core.pragma('dart2js:noInline')
  static MoveRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MoveRequest>(
          MoveRequest.$_createMessage);
  static MoveRequest? _defaultInstance;

  @$pb.TagNumber(1)
  SwitchMove get move => $_getN(0);
  @$pb.TagNumber(1)
  set move(SwitchMove value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMove() => $_has(0);
  @$pb.TagNumber(1)
  void clearMove() => $_clearField(1);

  /// Who sent it ("power-manager", "dashboard"), for the log.
  @$pb.TagNumber(2)
  $core.String get source => $_getSZ(1);
  @$pb.TagNumber(2)
  set source($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearSource() => $_clearField(2);
}

class MoveResponse extends $pb.GeneratedMessage {
  factory MoveResponse({
    View? view,
  }) {
    final result = MoveResponse._();
    if (view != null) result.view = view;
    return result;
  }

  MoveResponse._();

  factory MoveResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MoveResponse()..mergeFromBuffer(data, registry);
  factory MoveResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MoveResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MoveResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.camera.v1'),
      createEmptyInstance: MoveResponse.$_createMessage)
    ..aOM<View>(1, _omitFieldNames ? '' : 'view',
        subBuilder: View.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MoveResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MoveResponse copyWith(void Function(MoveResponse) updates) =>
      super.copyWith((message) => updates(message as MoveResponse))
          as MoveResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MoveResponse() / MoveResponse.new instead')
  static MoveResponse create() => MoveResponse._();
  static $pb.GeneratedMessage $_createMessage() => MoveResponse._();
  @$core.override
  MoveResponse createEmptyInstance() => MoveResponse._();
  @$core.pragma('dart2js:noInline')
  static MoveResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MoveResponse>(
          MoveResponse.$_createMessage);
  static MoveResponse? _defaultInstance;

  /// The view right after the move.
  @$pb.TagNumber(1)
  View get view => $_getN(0);
  @$pb.TagNumber(1)
  set view(View value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasView() => $_has(0);
  @$pb.TagNumber(1)
  void clearView() => $_clearField(1);
  @$pb.TagNumber(1)
  View ensureView() => $_ensure(0);
}

class CameraRecording extends $pb.GeneratedMessage {
  factory CameraRecording({
    Camera? camera,
    RecordingState? state,
    $core.String? detail,
    $core.String? segment,
  }) {
    final result = CameraRecording._();
    if (camera != null) result.camera = camera;
    if (state != null) result.state = state;
    if (detail != null) result.detail = detail;
    if (segment != null) result.segment = segment;
    return result;
  }

  CameraRecording._();

  factory CameraRecording.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CameraRecording()..mergeFromBuffer(data, registry);
  factory CameraRecording.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CameraRecording()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CameraRecording',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.camera.v1'),
      createEmptyInstance: CameraRecording.$_createMessage)
    ..aE<Camera>(1, _omitFieldNames ? '' : 'camera', enumValues: Camera.values)
    ..aE<RecordingState>(2, _omitFieldNames ? '' : 'state',
        enumValues: RecordingState.values)
    ..aOS(3, _omitFieldNames ? '' : 'detail')
    ..aOS(4, _omitFieldNames ? '' : 'segment')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CameraRecording clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CameraRecording copyWith(void Function(CameraRecording) updates) =>
      super.copyWith((message) => updates(message as CameraRecording))
          as CameraRecording;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CameraRecording() / CameraRecording.new instead')
  static CameraRecording create() => CameraRecording._();
  static $pb.GeneratedMessage $_createMessage() => CameraRecording._();
  @$core.override
  CameraRecording createEmptyInstance() => CameraRecording._();
  @$core.pragma('dart2js:noInline')
  static CameraRecording getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CameraRecording>(
          CameraRecording.$_createMessage);
  static CameraRecording? _defaultInstance;

  @$pb.TagNumber(1)
  Camera get camera => $_getN(0);
  @$pb.TagNumber(1)
  set camera(Camera value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCamera() => $_has(0);
  @$pb.TagNumber(1)
  void clearCamera() => $_clearField(1);

  @$pb.TagNumber(2)
  RecordingState get state => $_getN(1);
  @$pb.TagNumber(2)
  set state(RecordingState value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasState() => $_has(1);
  @$pb.TagNumber(2)
  void clearState() => $_clearField(2);

  /// Why it isn't recording, or what it is waiting for.
  @$pb.TagNumber(3)
  $core.String get detail => $_getSZ(2);
  @$pb.TagNumber(3)
  set detail($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDetail() => $_has(2);
  @$pb.TagNumber(3)
  void clearDetail() => $_clearField(3);

  /// The segment being written (file name only), while recording.
  @$pb.TagNumber(4)
  $core.String get segment => $_getSZ(3);
  @$pb.TagNumber(4)
  set segment($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSegment() => $_has(3);
  @$pb.TagNumber(4)
  void clearSegment() => $_clearField(4);
}

class Recording extends $pb.GeneratedMessage {
  factory Recording({
    $core.Iterable<CameraRecording>? cameras,
    $core.bool? driveMounted,
    $fixnum.Int64? driveFreeBytes,
    $fixnum.Int64? recordedBytes,
    $fixnum.Int64? protectedBytes,
    $fixnum.Int64? protectedMaxBytes,
    $core.int? clipSegmentsPending,
    $core.bool? clockTrusted,
    $core.String? problem,
  }) {
    final result = Recording._();
    if (cameras != null) result.cameras.addAll(cameras);
    if (driveMounted != null) result.driveMounted = driveMounted;
    if (driveFreeBytes != null) result.driveFreeBytes = driveFreeBytes;
    if (recordedBytes != null) result.recordedBytes = recordedBytes;
    if (protectedBytes != null) result.protectedBytes = protectedBytes;
    if (protectedMaxBytes != null) result.protectedMaxBytes = protectedMaxBytes;
    if (clipSegmentsPending != null)
      result.clipSegmentsPending = clipSegmentsPending;
    if (clockTrusted != null) result.clockTrusted = clockTrusted;
    if (problem != null) result.problem = problem;
    return result;
  }

  Recording._();

  factory Recording.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Recording()..mergeFromBuffer(data, registry);
  factory Recording.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Recording()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Recording',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.camera.v1'),
      createEmptyInstance: Recording.$_createMessage)
    ..pPM<CameraRecording>(1, _omitFieldNames ? '' : 'cameras',
        subBuilder: CameraRecording.$_createMessage)
    ..aOB(2, _omitFieldNames ? '' : 'driveMounted')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'driveFreeBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'recordedBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'protectedBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        6, _omitFieldNames ? '' : 'protectedMaxBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(7, _omitFieldNames ? '' : 'clipSegmentsPending',
        fieldType: $pb.PbFieldType.OU3)
    ..aOB(8, _omitFieldNames ? '' : 'clockTrusted')
    ..aOS(9, _omitFieldNames ? '' : 'problem')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Recording clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Recording copyWith(void Function(Recording) updates) =>
      super.copyWith((message) => updates(message as Recording)) as Recording;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Recording() / Recording.new instead')
  static Recording create() => Recording._();
  static $pb.GeneratedMessage $_createMessage() => Recording._();
  @$core.override
  Recording createEmptyInstance() => Recording._();
  @$core.pragma('dart2js:noInline')
  static Recording getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Recording>(Recording.$_createMessage);
  static Recording? _defaultInstance;

  /// The cameras set to record (RECORD_CAMERAS), in that order. Empty:
  /// recording is off.
  @$pb.TagNumber(1)
  $pb.PbList<CameraRecording> get cameras => $_getList(0);

  /// A data drive is mounted where recordings go. Without it nothing
  /// records and the SD card is never used (ADR-0027 decision 6).
  @$pb.TagNumber(2)
  $core.bool get driveMounted => $_getBF(1);
  @$pb.TagNumber(2)
  set driveMounted($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDriveMounted() => $_has(1);
  @$pb.TagNumber(2)
  void clearDriveMounted() => $_clearField(2);

  /// Free space on the drive and the unprotected video on it, from the last
  /// retention pass; meaningful only while drive_mounted.
  @$pb.TagNumber(3)
  $fixnum.Int64 get driveFreeBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set driveFreeBytes($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDriveFreeBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearDriveFreeBytes() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get recordedBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set recordedBytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRecordedBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearRecordedBytes() => $_clearField(4);

  /// Saved clips and their cap (RECORD_PROTECTED_MAX_GB).
  @$pb.TagNumber(5)
  $fixnum.Int64 get protectedBytes => $_getI64(4);
  @$pb.TagNumber(5)
  set protectedBytes($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasProtectedBytes() => $_has(4);
  @$pb.TagNumber(5)
  void clearProtectedBytes() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get protectedMaxBytes => $_getI64(5);
  @$pb.TagNumber(6)
  set protectedMaxBytes($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasProtectedMaxBytes() => $_has(5);
  @$pb.TagNumber(6)
  void clearProtectedMaxBytes() => $_clearField(6);

  /// Segments still to be moved into a saved clip as they finish.
  @$pb.TagNumber(7)
  $core.int get clipSegmentsPending => $_getIZ(6);
  @$pb.TagNumber(7)
  set clipSegmentsPending($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasClipSegmentsPending() => $_has(6);
  @$pb.TagNumber(7)
  void clearClipSegmentsPending() => $_clearField(7);

  /// The clock is trusted now (NTP synchronized): segment names carry the
  /// wall time, and the age limit applies.
  @$pb.TagNumber(8)
  $core.bool get clockTrusted => $_getBF(7);
  @$pb.TagNumber(8)
  set clockTrusted($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasClockTrusted() => $_has(7);
  @$pb.TagNumber(8)
  void clearClockTrusted() => $_clearField(8);

  /// Something the driver should know that isn't one camera's: the drive is
  /// full with nothing left to delete, or the minutes before an unclean stop
  /// didn't all fit in the saved clips. Empty when nothing is wrong.
  @$pb.TagNumber(9)
  $core.String get problem => $_getSZ(8);
  @$pb.TagNumber(9)
  set problem($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasProblem() => $_has(8);
  @$pb.TagNumber(9)
  void clearProblem() => $_clearField(9);
}

class WatchRecordingRequest extends $pb.GeneratedMessage {
  factory WatchRecordingRequest() => WatchRecordingRequest._();

  WatchRecordingRequest._();

  factory WatchRecordingRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchRecordingRequest()..mergeFromBuffer(data, registry);
  factory WatchRecordingRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchRecordingRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchRecordingRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.camera.v1'),
      createEmptyInstance: WatchRecordingRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchRecordingRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchRecordingRequest copyWith(
          void Function(WatchRecordingRequest) updates) =>
      super.copyWith((message) => updates(message as WatchRecordingRequest))
          as WatchRecordingRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use WatchRecordingRequest() / WatchRecordingRequest.new instead')
  static WatchRecordingRequest create() => WatchRecordingRequest._();
  static $pb.GeneratedMessage $_createMessage() => WatchRecordingRequest._();
  @$core.override
  WatchRecordingRequest createEmptyInstance() => WatchRecordingRequest._();
  @$core.pragma('dart2js:noInline')
  static WatchRecordingRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WatchRecordingRequest>(
          WatchRecordingRequest.$_createMessage);
  static WatchRecordingRequest? _defaultInstance;
}

class WatchRecordingResponse extends $pb.GeneratedMessage {
  factory WatchRecordingResponse({
    Recording? recording,
  }) {
    final result = WatchRecordingResponse._();
    if (recording != null) result.recording = recording;
    return result;
  }

  WatchRecordingResponse._();

  factory WatchRecordingResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchRecordingResponse()..mergeFromBuffer(data, registry);
  factory WatchRecordingResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchRecordingResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchRecordingResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.camera.v1'),
      createEmptyInstance: WatchRecordingResponse.$_createMessage)
    ..aOM<Recording>(1, _omitFieldNames ? '' : 'recording',
        subBuilder: Recording.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchRecordingResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchRecordingResponse copyWith(
          void Function(WatchRecordingResponse) updates) =>
      super.copyWith((message) => updates(message as WatchRecordingResponse))
          as WatchRecordingResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use WatchRecordingResponse() / WatchRecordingResponse.new instead')
  static WatchRecordingResponse create() => WatchRecordingResponse._();
  static $pb.GeneratedMessage $_createMessage() => WatchRecordingResponse._();
  @$core.override
  WatchRecordingResponse createEmptyInstance() => WatchRecordingResponse._();
  @$core.pragma('dart2js:noInline')
  static WatchRecordingResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WatchRecordingResponse>(
          WatchRecordingResponse.$_createMessage);
  static WatchRecordingResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Recording get recording => $_getN(0);
  @$pb.TagNumber(1)
  set recording(Recording value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasRecording() => $_has(0);
  @$pb.TagNumber(1)
  void clearRecording() => $_clearField(1);
  @$pb.TagNumber(1)
  Recording ensureRecording() => $_ensure(0);
}

class SaveClipRequest extends $pb.GeneratedMessage {
  factory SaveClipRequest({
    $core.String? source,
  }) {
    final result = SaveClipRequest._();
    if (source != null) result.source = source;
    return result;
  }

  SaveClipRequest._();

  factory SaveClipRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SaveClipRequest()..mergeFromBuffer(data, registry);
  factory SaveClipRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SaveClipRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SaveClipRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.camera.v1'),
      createEmptyInstance: SaveClipRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SaveClipRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SaveClipRequest copyWith(void Function(SaveClipRequest) updates) =>
      super.copyWith((message) => updates(message as SaveClipRequest))
          as SaveClipRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SaveClipRequest() / SaveClipRequest.new instead')
  static SaveClipRequest create() => SaveClipRequest._();
  static $pb.GeneratedMessage $_createMessage() => SaveClipRequest._();
  @$core.override
  SaveClipRequest createEmptyInstance() => SaveClipRequest._();
  @$core.pragma('dart2js:noInline')
  static SaveClipRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SaveClipRequest>(
          SaveClipRequest.$_createMessage);
  static SaveClipRequest? _defaultInstance;

  /// Who asked ("dashboard"), for the log.
  @$pb.TagNumber(1)
  $core.String get source => $_getSZ(0);
  @$pb.TagNumber(1)
  set source($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSource() => $_has(0);
  @$pb.TagNumber(1)
  void clearSource() => $_clearField(1);
}

class SaveClipResponse extends $pb.GeneratedMessage {
  factory SaveClipResponse({
    $core.bool? saved,
    $core.String? detail,
    $core.int? segmentsProtected,
    $core.int? segmentsToCome,
  }) {
    final result = SaveClipResponse._();
    if (saved != null) result.saved = saved;
    if (detail != null) result.detail = detail;
    if (segmentsProtected != null) result.segmentsProtected = segmentsProtected;
    if (segmentsToCome != null) result.segmentsToCome = segmentsToCome;
    return result;
  }

  SaveClipResponse._();

  factory SaveClipResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SaveClipResponse()..mergeFromBuffer(data, registry);
  factory SaveClipResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SaveClipResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SaveClipResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.camera.v1'),
      createEmptyInstance: SaveClipResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'saved')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..aI(3, _omitFieldNames ? '' : 'segmentsProtected',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'segmentsToCome',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SaveClipResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SaveClipResponse copyWith(void Function(SaveClipResponse) updates) =>
      super.copyWith((message) => updates(message as SaveClipResponse))
          as SaveClipResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SaveClipResponse() / SaveClipResponse.new instead')
  static SaveClipResponse create() => SaveClipResponse._();
  static $pb.GeneratedMessage $_createMessage() => SaveClipResponse._();
  @$core.override
  SaveClipResponse createEmptyInstance() => SaveClipResponse._();
  @$core.pragma('dart2js:noInline')
  static SaveClipResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SaveClipResponse>(
          SaveClipResponse.$_createMessage);
  static SaveClipResponse? _defaultInstance;

  /// False: nothing was protected, and `detail` says why.
  @$pb.TagNumber(1)
  $core.bool get saved => $_getBF(0);
  @$pb.TagNumber(1)
  set saved($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSaved() => $_has(0);
  @$pb.TagNumber(1)
  void clearSaved() => $_clearField(1);

  /// What happened, in words for the screen.
  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);

  /// Finished segments moved into the saved clips now.
  @$pb.TagNumber(3)
  $core.int get segmentsProtected => $_getIZ(2);
  @$pb.TagNumber(3)
  set segmentsProtected($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSegmentsProtected() => $_has(2);
  @$pb.TagNumber(3)
  void clearSegmentsProtected() => $_clearField(3);

  /// Segments that will be moved as they finish (the one being written and
  /// the ones after it), across the cameras.
  @$pb.TagNumber(4)
  $core.int get segmentsToCome => $_getIZ(3);
  @$pb.TagNumber(4)
  set segmentsToCome($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSegmentsToCome() => $_has(3);
  @$pb.TagNumber(4)
  void clearSegmentsToCome() => $_clearField(4);
}

/// A video device plugged in now (ADR-0029 decision 3).
class CameraDevice extends $pb.GeneratedMessage {
  factory CameraDevice({
    $core.String? path,
    $core.String? label,
  }) {
    final result = CameraDevice._();
    if (path != null) result.path = path;
    if (label != null) result.label = label;
    return result;
  }

  CameraDevice._();

  factory CameraDevice.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CameraDevice()..mergeFromBuffer(data, registry);
  factory CameraDevice.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CameraDevice()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CameraDevice',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.camera.v1'),
      createEmptyInstance: CameraDevice.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..aOS(2, _omitFieldNames ? '' : 'label')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CameraDevice clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CameraDevice copyWith(void Function(CameraDevice) updates) =>
      super.copyWith((message) => updates(message as CameraDevice))
          as CameraDevice;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CameraDevice() / CameraDevice.new instead')
  static CameraDevice create() => CameraDevice._();
  static $pb.GeneratedMessage $_createMessage() => CameraDevice._();
  @$core.override
  CameraDevice createEmptyInstance() => CameraDevice._();
  @$core.pragma('dart2js:noInline')
  static CameraDevice getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CameraDevice>(
          CameraDevice.$_createMessage);
  static CameraDevice? _defaultInstance;

  /// /dev/v4l/by-path/...-video-index0: names the USB port, so a camera's
  /// role follows the port.
  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);

  /// The /dev/v4l/by-id name pointing at the same device (the camera's
  /// model), or empty.
  @$pb.TagNumber(2)
  $core.String get label => $_getSZ(1);
  @$pb.TagNumber(2)
  set label($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLabel() => $_has(1);
  @$pb.TagNumber(2)
  void clearLabel() => $_clearField(2);
}

class CameraAssignment extends $pb.GeneratedMessage {
  factory CameraAssignment({
    Camera? camera,
    $core.String? device,
  }) {
    final result = CameraAssignment._();
    if (camera != null) result.camera = camera;
    if (device != null) result.device = device;
    return result;
  }

  CameraAssignment._();

  factory CameraAssignment.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CameraAssignment()..mergeFromBuffer(data, registry);
  factory CameraAssignment.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CameraAssignment()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CameraAssignment',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.camera.v1'),
      createEmptyInstance: CameraAssignment.$_createMessage)
    ..aE<Camera>(1, _omitFieldNames ? '' : 'camera', enumValues: Camera.values)
    ..aOS(2, _omitFieldNames ? '' : 'device')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CameraAssignment clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CameraAssignment copyWith(void Function(CameraAssignment) updates) =>
      super.copyWith((message) => updates(message as CameraAssignment))
          as CameraAssignment;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CameraAssignment() / CameraAssignment.new instead')
  static CameraAssignment create() => CameraAssignment._();
  static $pb.GeneratedMessage $_createMessage() => CameraAssignment._();
  @$core.override
  CameraAssignment createEmptyInstance() => CameraAssignment._();
  @$core.pragma('dart2js:noInline')
  static CameraAssignment getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CameraAssignment>(
          CameraAssignment.$_createMessage);
  static CameraAssignment? _defaultInstance;

  @$pb.TagNumber(1)
  Camera get camera => $_getN(0);
  @$pb.TagNumber(1)
  set camera(Camera value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCamera() => $_has(0);
  @$pb.TagNumber(1)
  void clearCamera() => $_clearField(1);

  /// Empty: no device; the camera shows as unavailable when chosen.
  @$pb.TagNumber(2)
  $core.String get device => $_getSZ(1);
  @$pb.TagNumber(2)
  set device($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDevice() => $_has(1);
  @$pb.TagNumber(2)
  void clearDevice() => $_clearField(2);
}

class CameraSettings extends $pb.GeneratedMessage {
  factory CameraSettings({
    $core.Iterable<CameraAssignment>? cameras,
    $core.Iterable<Camera>? record,
    SettingsSource? source,
    $core.String? recordingUnavailable,
  }) {
    final result = CameraSettings._();
    if (cameras != null) result.cameras.addAll(cameras);
    if (record != null) result.record.addAll(record);
    if (source != null) result.source = source;
    if (recordingUnavailable != null)
      result.recordingUnavailable = recordingUnavailable;
    return result;
  }

  CameraSettings._();

  factory CameraSettings.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CameraSettings()..mergeFromBuffer(data, registry);
  factory CameraSettings.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CameraSettings()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CameraSettings',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.camera.v1'),
      createEmptyInstance: CameraSettings.$_createMessage)
    ..pPM<CameraAssignment>(1, _omitFieldNames ? '' : 'cameras',
        subBuilder: CameraAssignment.$_createMessage)
    ..pc<Camera>(2, _omitFieldNames ? '' : 'record', $pb.PbFieldType.KE,
        valueOf: Camera.valueOf,
        enumValues: Camera.values,
        defaultEnumValue: Camera.CAMERA_UNSPECIFIED)
    ..aE<SettingsSource>(3, _omitFieldNames ? '' : 'source',
        enumValues: SettingsSource.values)
    ..aOS(4, _omitFieldNames ? '' : 'recordingUnavailable')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CameraSettings clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CameraSettings copyWith(void Function(CameraSettings) updates) =>
      super.copyWith((message) => updates(message as CameraSettings))
          as CameraSettings;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CameraSettings() / CameraSettings.new instead')
  static CameraSettings create() => CameraSettings._();
  static $pb.GeneratedMessage $_createMessage() => CameraSettings._();
  @$core.override
  CameraSettings createEmptyInstance() => CameraSettings._();
  @$core.pragma('dart2js:noInline')
  static CameraSettings getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CameraSettings>(
          CameraSettings.$_createMessage);
  static CameraSettings? _defaultInstance;

  /// Front, left, right and rear, in that order.
  @$pb.TagNumber(1)
  $pb.PbList<CameraAssignment> get cameras => $_getList(0);

  /// The cameras recorded: front and/or rear.
  @$pb.TagNumber(2)
  $pb.PbList<Camera> get record => $_getList(1);

  @$pb.TagNumber(3)
  SettingsSource get source => $_getN(2);
  @$pb.TagNumber(3)
  set source(SettingsSource value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasSource() => $_has(2);
  @$pb.TagNumber(3)
  void clearSource() => $_clearField(3);

  /// Why recording can't happen (no data drive configured, a build that
  /// can't record); empty when it can.
  @$pb.TagNumber(4)
  $core.String get recordingUnavailable => $_getSZ(3);
  @$pb.TagNumber(4)
  set recordingUnavailable($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRecordingUnavailable() => $_has(3);
  @$pb.TagNumber(4)
  void clearRecordingUnavailable() => $_clearField(4);
}

class GetCameraSettingsRequest extends $pb.GeneratedMessage {
  factory GetCameraSettingsRequest() => GetCameraSettingsRequest._();

  GetCameraSettingsRequest._();

  factory GetCameraSettingsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetCameraSettingsRequest()..mergeFromBuffer(data, registry);
  factory GetCameraSettingsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetCameraSettingsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetCameraSettingsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.camera.v1'),
      createEmptyInstance: GetCameraSettingsRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetCameraSettingsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetCameraSettingsRequest copyWith(
          void Function(GetCameraSettingsRequest) updates) =>
      super.copyWith((message) => updates(message as GetCameraSettingsRequest))
          as GetCameraSettingsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetCameraSettingsRequest() / GetCameraSettingsRequest.new instead')
  static GetCameraSettingsRequest create() => GetCameraSettingsRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetCameraSettingsRequest._();
  @$core.override
  GetCameraSettingsRequest createEmptyInstance() =>
      GetCameraSettingsRequest._();
  @$core.pragma('dart2js:noInline')
  static GetCameraSettingsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetCameraSettingsRequest>(
          GetCameraSettingsRequest.$_createMessage);
  static GetCameraSettingsRequest? _defaultInstance;
}

class GetCameraSettingsResponse extends $pb.GeneratedMessage {
  factory GetCameraSettingsResponse({
    CameraSettings? settings,
    $core.Iterable<CameraDevice>? devices,
  }) {
    final result = GetCameraSettingsResponse._();
    if (settings != null) result.settings = settings;
    if (devices != null) result.devices.addAll(devices);
    return result;
  }

  GetCameraSettingsResponse._();

  factory GetCameraSettingsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetCameraSettingsResponse()..mergeFromBuffer(data, registry);
  factory GetCameraSettingsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetCameraSettingsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetCameraSettingsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.camera.v1'),
      createEmptyInstance: GetCameraSettingsResponse.$_createMessage)
    ..aOM<CameraSettings>(1, _omitFieldNames ? '' : 'settings',
        subBuilder: CameraSettings.$_createMessage)
    ..pPM<CameraDevice>(2, _omitFieldNames ? '' : 'devices',
        subBuilder: CameraDevice.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetCameraSettingsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetCameraSettingsResponse copyWith(
          void Function(GetCameraSettingsResponse) updates) =>
      super.copyWith((message) => updates(message as GetCameraSettingsResponse))
          as GetCameraSettingsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetCameraSettingsResponse() / GetCameraSettingsResponse.new instead')
  static GetCameraSettingsResponse create() => GetCameraSettingsResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      GetCameraSettingsResponse._();
  @$core.override
  GetCameraSettingsResponse createEmptyInstance() =>
      GetCameraSettingsResponse._();
  @$core.pragma('dart2js:noInline')
  static GetCameraSettingsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetCameraSettingsResponse>(
          GetCameraSettingsResponse.$_createMessage);
  static GetCameraSettingsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  CameraSettings get settings => $_getN(0);
  @$pb.TagNumber(1)
  set settings(CameraSettings value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSettings() => $_has(0);
  @$pb.TagNumber(1)
  void clearSettings() => $_clearField(1);
  @$pb.TagNumber(1)
  CameraSettings ensureSettings() => $_ensure(0);

  /// The cameras plugged in now.
  @$pb.TagNumber(2)
  $pb.PbList<CameraDevice> get devices => $_getList(1);
}

class SetCameraSettingsRequest extends $pb.GeneratedMessage {
  factory SetCameraSettingsRequest({
    $core.Iterable<CameraAssignment>? cameras,
    $core.Iterable<Camera>? record,
    $core.bool? useDefaults,
    $core.String? source,
  }) {
    final result = SetCameraSettingsRequest._();
    if (cameras != null) result.cameras.addAll(cameras);
    if (record != null) result.record.addAll(record);
    if (useDefaults != null) result.useDefaults = useDefaults;
    if (source != null) result.source = source;
    return result;
  }

  SetCameraSettingsRequest._();

  factory SetCameraSettingsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetCameraSettingsRequest()..mergeFromBuffer(data, registry);
  factory SetCameraSettingsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetCameraSettingsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetCameraSettingsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.camera.v1'),
      createEmptyInstance: SetCameraSettingsRequest.$_createMessage)
    ..pPM<CameraAssignment>(1, _omitFieldNames ? '' : 'cameras',
        subBuilder: CameraAssignment.$_createMessage)
    ..pc<Camera>(2, _omitFieldNames ? '' : 'record', $pb.PbFieldType.KE,
        valueOf: Camera.valueOf,
        enumValues: Camera.values,
        defaultEnumValue: Camera.CAMERA_UNSPECIFIED)
    ..aOB(3, _omitFieldNames ? '' : 'useDefaults')
    ..aOS(4, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetCameraSettingsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetCameraSettingsRequest copyWith(
          void Function(SetCameraSettingsRequest) updates) =>
      super.copyWith((message) => updates(message as SetCameraSettingsRequest))
          as SetCameraSettingsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SetCameraSettingsRequest() / SetCameraSettingsRequest.new instead')
  static SetCameraSettingsRequest create() => SetCameraSettingsRequest._();
  static $pb.GeneratedMessage $_createMessage() => SetCameraSettingsRequest._();
  @$core.override
  SetCameraSettingsRequest createEmptyInstance() =>
      SetCameraSettingsRequest._();
  @$core.pragma('dart2js:noInline')
  static SetCameraSettingsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetCameraSettingsRequest>(
          SetCameraSettingsRequest.$_createMessage);
  static SetCameraSettingsRequest? _defaultInstance;

  /// All four cameras; one left out has no device.
  @$pb.TagNumber(1)
  $pb.PbList<CameraAssignment> get cameras => $_getList(0);

  @$pb.TagNumber(2)
  $pb.PbList<Camera> get record => $_getList(1);

  /// Forget the saved settings and use /etc/default/f250's again; `cameras`
  /// and `record` are ignored.
  @$pb.TagNumber(3)
  $core.bool get useDefaults => $_getBF(2);
  @$pb.TagNumber(3)
  set useDefaults($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasUseDefaults() => $_has(2);
  @$pb.TagNumber(3)
  void clearUseDefaults() => $_clearField(3);

  /// Who asked ("dashboard"), for the log.
  @$pb.TagNumber(4)
  $core.String get source => $_getSZ(3);
  @$pb.TagNumber(4)
  set source($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSource() => $_has(3);
  @$pb.TagNumber(4)
  void clearSource() => $_clearField(4);
}

class SetCameraSettingsResponse extends $pb.GeneratedMessage {
  factory SetCameraSettingsResponse({
    $core.bool? applied,
    $core.String? detail,
  }) {
    final result = SetCameraSettingsResponse._();
    if (applied != null) result.applied = applied;
    if (detail != null) result.detail = detail;
    return result;
  }

  SetCameraSettingsResponse._();

  factory SetCameraSettingsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetCameraSettingsResponse()..mergeFromBuffer(data, registry);
  factory SetCameraSettingsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetCameraSettingsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetCameraSettingsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.camera.v1'),
      createEmptyInstance: SetCameraSettingsResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'applied')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetCameraSettingsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetCameraSettingsResponse copyWith(
          void Function(SetCameraSettingsResponse) updates) =>
      super.copyWith((message) => updates(message as SetCameraSettingsResponse))
          as SetCameraSettingsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SetCameraSettingsResponse() / SetCameraSettingsResponse.new instead')
  static SetCameraSettingsResponse create() => SetCameraSettingsResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      SetCameraSettingsResponse._();
  @$core.override
  SetCameraSettingsResponse createEmptyInstance() =>
      SetCameraSettingsResponse._();
  @$core.pragma('dart2js:noInline')
  static SetCameraSettingsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetCameraSettingsResponse>(
          SetCameraSettingsResponse.$_createMessage);
  static SetCameraSettingsResponse? _defaultInstance;

  /// True: saved, and camera-manager is restarting to apply them.
  @$pb.TagNumber(1)
  $core.bool get applied => $_getBF(0);
  @$pb.TagNumber(1)
  set applied($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasApplied() => $_has(0);
  @$pb.TagNumber(1)
  void clearApplied() => $_clearField(1);

  /// Why not, or what happens next, in words for the screen.
  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
