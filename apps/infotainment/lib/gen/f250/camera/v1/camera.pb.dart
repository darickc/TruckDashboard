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

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
