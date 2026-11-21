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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'switch.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'switch.pbenum.dart';

class WireInfo extends $pb.GeneratedMessage {
  factory WireInfo({
    Wire? wire,
    $core.String? pin,
    Role? role,
    $core.bool? present,
  }) {
    final result = WireInfo._();
    if (wire != null) result.wire = wire;
    if (pin != null) result.pin = pin;
    if (role != null) result.role = role;
    if (present != null) result.present = present;
    return result;
  }

  WireInfo._();

  factory WireInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WireInfo()..mergeFromBuffer(data, registry);
  factory WireInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WireInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WireInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.power.v1'),
      createEmptyInstance: WireInfo.$_createMessage)
    ..aE<Wire>(1, _omitFieldNames ? '' : 'wire', enumValues: Wire.values)
    ..aOS(2, _omitFieldNames ? '' : 'pin')
    ..aE<Role>(3, _omitFieldNames ? '' : 'role', enumValues: Role.values)
    ..aOB(4, _omitFieldNames ? '' : 'present')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WireInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WireInfo copyWith(void Function(WireInfo) updates) =>
      super.copyWith((message) => updates(message as WireInfo)) as WireInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WireInfo() / WireInfo.new instead')
  static WireInfo create() => WireInfo._();
  static $pb.GeneratedMessage $_createMessage() => WireInfo._();
  @$core.override
  WireInfo createEmptyInstance() => WireInfo._();
  @$core.pragma('dart2js:noInline')
  static WireInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WireInfo>(WireInfo.$_createMessage);
  static WireInfo? _defaultInstance;

  @$pb.TagNumber(1)
  Wire get wire => $_getN(0);
  @$pb.TagNumber(1)
  set wire(Wire value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasWire() => $_has(0);
  @$pb.TagNumber(1)
  void clearWire() => $_clearField(1);

  /// The GPIO, for the screen ("BCM12, pin 32").
  @$pb.TagNumber(2)
  $core.String get pin => $_getSZ(1);
  @$pb.TagNumber(2)
  set pin($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPin() => $_has(1);
  @$pb.TagNumber(2)
  void clearPin() => $_clearField(2);

  @$pb.TagNumber(3)
  Role get role => $_getN(2);
  @$pb.TagNumber(3)
  set role(Role value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasRole() => $_has(2);
  @$pb.TagNumber(3)
  void clearRole() => $_clearField(3);

  /// An input device with this wire's key is open.
  @$pb.TagNumber(4)
  $core.bool get present => $_getBF(3);
  @$pb.TagNumber(4)
  set present($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPresent() => $_has(3);
  @$pb.TagNumber(4)
  void clearPresent() => $_clearField(4);
}

class SwitchState extends $pb.GeneratedMessage {
  factory SwitchState({
    $core.Iterable<WireInfo>? wires,
    $core.bool? learning,
    $core.int? learningTimeoutS,
    $core.int? longPressMs,
    $core.bool? defaultMapping,
    $core.String? problem,
  }) {
    final result = SwitchState._();
    if (wires != null) result.wires.addAll(wires);
    if (learning != null) result.learning = learning;
    if (learningTimeoutS != null) result.learningTimeoutS = learningTimeoutS;
    if (longPressMs != null) result.longPressMs = longPressMs;
    if (defaultMapping != null) result.defaultMapping = defaultMapping;
    if (problem != null) result.problem = problem;
    return result;
  }

  SwitchState._();

  factory SwitchState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SwitchState()..mergeFromBuffer(data, registry);
  factory SwitchState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SwitchState()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SwitchState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.power.v1'),
      createEmptyInstance: SwitchState.$_createMessage)
    ..pPM<WireInfo>(1, _omitFieldNames ? '' : 'wires',
        subBuilder: WireInfo.$_createMessage)
    ..aOB(2, _omitFieldNames ? '' : 'learning')
    ..aI(3, _omitFieldNames ? '' : 'learningTimeoutS',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'longPressMs',
        fieldType: $pb.PbFieldType.OU3)
    ..aOB(5, _omitFieldNames ? '' : 'defaultMapping')
    ..aOS(6, _omitFieldNames ? '' : 'problem')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SwitchState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SwitchState copyWith(void Function(SwitchState) updates) =>
      super.copyWith((message) => updates(message as SwitchState))
          as SwitchState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SwitchState() / SwitchState.new instead')
  static SwitchState create() => SwitchState._();
  static $pb.GeneratedMessage $_createMessage() => SwitchState._();
  @$core.override
  SwitchState createEmptyInstance() => SwitchState._();
  @$core.pragma('dart2js:noInline')
  static SwitchState getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SwitchState>(
          SwitchState.$_createMessage);
  static SwitchState? _defaultInstance;

  /// All five wires, in Wire order.
  @$pb.TagNumber(1)
  $pb.PbList<WireInfo> get wires => $_getList(0);

  /// Presses are reported, not sent.
  @$pb.TagNumber(2)
  $core.bool get learning => $_getBF(1);
  @$pb.TagNumber(2)
  set learning($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLearning() => $_has(1);
  @$pb.TagNumber(2)
  void clearLearning() => $_clearField(2);

  /// Learning ends after this long without a press.
  @$pb.TagNumber(3)
  $core.int get learningTimeoutS => $_getIZ(2);
  @$pb.TagNumber(3)
  set learningTimeoutS($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLearningTimeoutS() => $_has(2);
  @$pb.TagNumber(3)
  void clearLearningTimeoutS() => $_clearField(3);

  /// A press held this long is a long press.
  @$pb.TagNumber(4)
  $core.int get longPressMs => $_getIZ(3);
  @$pb.TagNumber(4)
  set longPressMs($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLongPressMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearLongPressMs() => $_clearField(4);

  /// The mapping is the default (none saved, or reset).
  @$pb.TagNumber(5)
  $core.bool get defaultMapping => $_getBF(4);
  @$pb.TagNumber(5)
  set defaultMapping($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDefaultMapping() => $_has(4);
  @$pb.TagNumber(5)
  void clearDefaultMapping() => $_clearField(5);

  /// Why the switch can't be read or the mapping wasn't loaded; empty when
  /// all is well.
  @$pb.TagNumber(6)
  $core.String get problem => $_getSZ(5);
  @$pb.TagNumber(6)
  set problem($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasProblem() => $_has(5);
  @$pb.TagNumber(6)
  void clearProblem() => $_clearField(6);
}

class Press extends $pb.GeneratedMessage {
  factory Press({
    Wire? wire,
    Role? role,
    PressKind? kind,
    $core.String? result,
    $fixnum.Int64? seq,
  }) {
    final result$ = Press._();
    if (wire != null) result$.wire = wire;
    if (role != null) result$.role = role;
    if (kind != null) result$.kind = kind;
    if (result != null) result$.result = result;
    if (seq != null) result$.seq = seq;
    return result$;
  }

  Press._();

  factory Press.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Press()..mergeFromBuffer(data, registry);
  factory Press.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Press()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Press',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.power.v1'),
      createEmptyInstance: Press.$_createMessage)
    ..aE<Wire>(1, _omitFieldNames ? '' : 'wire', enumValues: Wire.values)
    ..aE<Role>(2, _omitFieldNames ? '' : 'role', enumValues: Role.values)
    ..aE<PressKind>(3, _omitFieldNames ? '' : 'kind',
        enumValues: PressKind.values)
    ..aOS(4, _omitFieldNames ? '' : 'result')
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Press clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Press copyWith(void Function(Press) updates) =>
      super.copyWith((message) => updates(message as Press)) as Press;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Press() / Press.new instead')
  static Press create() => Press._();
  static $pb.GeneratedMessage $_createMessage() => Press._();
  @$core.override
  Press createEmptyInstance() => Press._();
  @$core.pragma('dart2js:noInline')
  static Press getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Press>(Press.$_createMessage);
  static Press? _defaultInstance;

  @$pb.TagNumber(1)
  Wire get wire => $_getN(0);
  @$pb.TagNumber(1)
  set wire(Wire value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasWire() => $_has(0);
  @$pb.TagNumber(1)
  void clearWire() => $_clearField(1);

  /// The role the wire had when pressed.
  @$pb.TagNumber(2)
  Role get role => $_getN(1);
  @$pb.TagNumber(2)
  set role(Role value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasRole() => $_has(1);
  @$pb.TagNumber(2)
  void clearRole() => $_clearField(2);

  @$pb.TagNumber(3)
  PressKind get kind => $_getN(2);
  @$pb.TagNumber(3)
  set kind(PressKind value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasKind() => $_has(2);
  @$pb.TagNumber(3)
  void clearKind() => $_clearField(3);

  /// What it did, for the screen ("volume up", "rear camera",
  /// "learning: not sent", "audio-manager didn't answer").
  @$pb.TagNumber(4)
  $core.String get result => $_getSZ(3);
  @$pb.TagNumber(4)
  set result($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasResult() => $_has(3);
  @$pb.TagNumber(4)
  void clearResult() => $_clearField(4);

  /// Counts up with each press since power-manager started, so a client can
  /// tell two presses of the same wire apart.
  @$pb.TagNumber(5)
  $fixnum.Int64 get seq => $_getI64(4);
  @$pb.TagNumber(5)
  set seq($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSeq() => $_has(4);
  @$pb.TagNumber(5)
  void clearSeq() => $_clearField(5);
}

class WatchSwitchRequest extends $pb.GeneratedMessage {
  factory WatchSwitchRequest() => WatchSwitchRequest._();

  WatchSwitchRequest._();

  factory WatchSwitchRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchSwitchRequest()..mergeFromBuffer(data, registry);
  factory WatchSwitchRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchSwitchRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchSwitchRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.power.v1'),
      createEmptyInstance: WatchSwitchRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchSwitchRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchSwitchRequest copyWith(void Function(WatchSwitchRequest) updates) =>
      super.copyWith((message) => updates(message as WatchSwitchRequest))
          as WatchSwitchRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WatchSwitchRequest() / WatchSwitchRequest.new instead')
  static WatchSwitchRequest create() => WatchSwitchRequest._();
  static $pb.GeneratedMessage $_createMessage() => WatchSwitchRequest._();
  @$core.override
  WatchSwitchRequest createEmptyInstance() => WatchSwitchRequest._();
  @$core.pragma('dart2js:noInline')
  static WatchSwitchRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WatchSwitchRequest>(
          WatchSwitchRequest.$_createMessage);
  static WatchSwitchRequest? _defaultInstance;
}

enum WatchSwitchResponse_Event { state, press, notSet }

class WatchSwitchResponse extends $pb.GeneratedMessage {
  factory WatchSwitchResponse({
    SwitchState? state,
    Press? press,
  }) {
    final result = WatchSwitchResponse._();
    if (state != null) result.state = state;
    if (press != null) result.press = press;
    return result;
  }

  WatchSwitchResponse._();

  factory WatchSwitchResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchSwitchResponse()..mergeFromBuffer(data, registry);
  factory WatchSwitchResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchSwitchResponse()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, WatchSwitchResponse_Event>
      _WatchSwitchResponse_EventByTag = {
    1: WatchSwitchResponse_Event.state,
    2: WatchSwitchResponse_Event.press,
    0: WatchSwitchResponse_Event.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchSwitchResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.power.v1'),
      createEmptyInstance: WatchSwitchResponse.$_createMessage)
    ..oo(0, [1, 2])
    ..aOM<SwitchState>(1, _omitFieldNames ? '' : 'state',
        subBuilder: SwitchState.$_createMessage)
    ..aOM<Press>(2, _omitFieldNames ? '' : 'press',
        subBuilder: Press.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchSwitchResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchSwitchResponse copyWith(void Function(WatchSwitchResponse) updates) =>
      super.copyWith((message) => updates(message as WatchSwitchResponse))
          as WatchSwitchResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use WatchSwitchResponse() / WatchSwitchResponse.new instead')
  static WatchSwitchResponse create() => WatchSwitchResponse._();
  static $pb.GeneratedMessage $_createMessage() => WatchSwitchResponse._();
  @$core.override
  WatchSwitchResponse createEmptyInstance() => WatchSwitchResponse._();
  @$core.pragma('dart2js:noInline')
  static WatchSwitchResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WatchSwitchResponse>(
          WatchSwitchResponse.$_createMessage);
  static WatchSwitchResponse? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  WatchSwitchResponse_Event whichEvent() =>
      _WatchSwitchResponse_EventByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  void clearEvent() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  SwitchState get state => $_getN(0);
  @$pb.TagNumber(1)
  set state(SwitchState value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasState() => $_has(0);
  @$pb.TagNumber(1)
  void clearState() => $_clearField(1);
  @$pb.TagNumber(1)
  SwitchState ensureState() => $_ensure(0);

  @$pb.TagNumber(2)
  Press get press => $_getN(1);
  @$pb.TagNumber(2)
  set press(Press value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPress() => $_has(1);
  @$pb.TagNumber(2)
  void clearPress() => $_clearField(2);
  @$pb.TagNumber(2)
  Press ensurePress() => $_ensure(1);
}

class SetLearningRequest extends $pb.GeneratedMessage {
  factory SetLearningRequest({
    $core.bool? on,
    $core.String? source,
  }) {
    final result = SetLearningRequest._();
    if (on != null) result.on = on;
    if (source != null) result.source = source;
    return result;
  }

  SetLearningRequest._();

  factory SetLearningRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetLearningRequest()..mergeFromBuffer(data, registry);
  factory SetLearningRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetLearningRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetLearningRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.power.v1'),
      createEmptyInstance: SetLearningRequest.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'on')
    ..aOS(2, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetLearningRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetLearningRequest copyWith(void Function(SetLearningRequest) updates) =>
      super.copyWith((message) => updates(message as SetLearningRequest))
          as SetLearningRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SetLearningRequest() / SetLearningRequest.new instead')
  static SetLearningRequest create() => SetLearningRequest._();
  static $pb.GeneratedMessage $_createMessage() => SetLearningRequest._();
  @$core.override
  SetLearningRequest createEmptyInstance() => SetLearningRequest._();
  @$core.pragma('dart2js:noInline')
  static SetLearningRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetLearningRequest>(
          SetLearningRequest.$_createMessage);
  static SetLearningRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get on => $_getBF(0);
  @$pb.TagNumber(1)
  set on($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOn() => $_has(0);
  @$pb.TagNumber(1)
  void clearOn() => $_clearField(1);

  /// Who asked ("dashboard"), for the log.
  @$pb.TagNumber(2)
  $core.String get source => $_getSZ(1);
  @$pb.TagNumber(2)
  set source($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearSource() => $_clearField(2);
}

class SetLearningResponse extends $pb.GeneratedMessage {
  factory SetLearningResponse({
    SwitchState? state,
  }) {
    final result = SetLearningResponse._();
    if (state != null) result.state = state;
    return result;
  }

  SetLearningResponse._();

  factory SetLearningResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetLearningResponse()..mergeFromBuffer(data, registry);
  factory SetLearningResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetLearningResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetLearningResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.power.v1'),
      createEmptyInstance: SetLearningResponse.$_createMessage)
    ..aOM<SwitchState>(1, _omitFieldNames ? '' : 'state',
        subBuilder: SwitchState.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetLearningResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetLearningResponse copyWith(void Function(SetLearningResponse) updates) =>
      super.copyWith((message) => updates(message as SetLearningResponse))
          as SetLearningResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use SetLearningResponse() / SetLearningResponse.new instead')
  static SetLearningResponse create() => SetLearningResponse._();
  static $pb.GeneratedMessage $_createMessage() => SetLearningResponse._();
  @$core.override
  SetLearningResponse createEmptyInstance() => SetLearningResponse._();
  @$core.pragma('dart2js:noInline')
  static SetLearningResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetLearningResponse>(
          SetLearningResponse.$_createMessage);
  static SetLearningResponse? _defaultInstance;

  @$pb.TagNumber(1)
  SwitchState get state => $_getN(0);
  @$pb.TagNumber(1)
  set state(SwitchState value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasState() => $_has(0);
  @$pb.TagNumber(1)
  void clearState() => $_clearField(1);
  @$pb.TagNumber(1)
  SwitchState ensureState() => $_ensure(0);
}

class WireRole extends $pb.GeneratedMessage {
  factory WireRole({
    Wire? wire,
    Role? role,
  }) {
    final result = WireRole._();
    if (wire != null) result.wire = wire;
    if (role != null) result.role = role;
    return result;
  }

  WireRole._();

  factory WireRole.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WireRole()..mergeFromBuffer(data, registry);
  factory WireRole.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WireRole()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WireRole',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.power.v1'),
      createEmptyInstance: WireRole.$_createMessage)
    ..aE<Wire>(1, _omitFieldNames ? '' : 'wire', enumValues: Wire.values)
    ..aE<Role>(2, _omitFieldNames ? '' : 'role', enumValues: Role.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WireRole clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WireRole copyWith(void Function(WireRole) updates) =>
      super.copyWith((message) => updates(message as WireRole)) as WireRole;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WireRole() / WireRole.new instead')
  static WireRole create() => WireRole._();
  static $pb.GeneratedMessage $_createMessage() => WireRole._();
  @$core.override
  WireRole createEmptyInstance() => WireRole._();
  @$core.pragma('dart2js:noInline')
  static WireRole getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WireRole>(WireRole.$_createMessage);
  static WireRole? _defaultInstance;

  @$pb.TagNumber(1)
  Wire get wire => $_getN(0);
  @$pb.TagNumber(1)
  set wire(Wire value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasWire() => $_has(0);
  @$pb.TagNumber(1)
  void clearWire() => $_clearField(1);

  @$pb.TagNumber(2)
  Role get role => $_getN(1);
  @$pb.TagNumber(2)
  set role(Role value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasRole() => $_has(1);
  @$pb.TagNumber(2)
  void clearRole() => $_clearField(2);
}

class SetMappingRequest extends $pb.GeneratedMessage {
  factory SetMappingRequest({
    $core.Iterable<WireRole>? wires,
    $core.String? source,
  }) {
    final result = SetMappingRequest._();
    if (wires != null) result.wires.addAll(wires);
    if (source != null) result.source = source;
    return result;
  }

  SetMappingRequest._();

  factory SetMappingRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetMappingRequest()..mergeFromBuffer(data, registry);
  factory SetMappingRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetMappingRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetMappingRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.power.v1'),
      createEmptyInstance: SetMappingRequest.$_createMessage)
    ..pPM<WireRole>(1, _omitFieldNames ? '' : 'wires',
        subBuilder: WireRole.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetMappingRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetMappingRequest copyWith(void Function(SetMappingRequest) updates) =>
      super.copyWith((message) => updates(message as SetMappingRequest))
          as SetMappingRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SetMappingRequest() / SetMappingRequest.new instead')
  static SetMappingRequest create() => SetMappingRequest._();
  static $pb.GeneratedMessage $_createMessage() => SetMappingRequest._();
  @$core.override
  SetMappingRequest createEmptyInstance() => SetMappingRequest._();
  @$core.pragma('dart2js:noInline')
  static SetMappingRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetMappingRequest>(
          SetMappingRequest.$_createMessage);
  static SetMappingRequest? _defaultInstance;

  /// All five wires, each with a different role.
  @$pb.TagNumber(1)
  $pb.PbList<WireRole> get wires => $_getList(0);

  @$pb.TagNumber(2)
  $core.String get source => $_getSZ(1);
  @$pb.TagNumber(2)
  set source($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearSource() => $_clearField(2);
}

class SetMappingResponse extends $pb.GeneratedMessage {
  factory SetMappingResponse({
    $core.bool? saved,
    $core.String? detail,
    SwitchState? state,
  }) {
    final result = SetMappingResponse._();
    if (saved != null) result.saved = saved;
    if (detail != null) result.detail = detail;
    if (state != null) result.state = state;
    return result;
  }

  SetMappingResponse._();

  factory SetMappingResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetMappingResponse()..mergeFromBuffer(data, registry);
  factory SetMappingResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetMappingResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetMappingResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.power.v1'),
      createEmptyInstance: SetMappingResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'saved')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..aOM<SwitchState>(3, _omitFieldNames ? '' : 'state',
        subBuilder: SwitchState.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetMappingResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetMappingResponse copyWith(void Function(SetMappingResponse) updates) =>
      super.copyWith((message) => updates(message as SetMappingResponse))
          as SetMappingResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SetMappingResponse() / SetMappingResponse.new instead')
  static SetMappingResponse create() => SetMappingResponse._();
  static $pb.GeneratedMessage $_createMessage() => SetMappingResponse._();
  @$core.override
  SetMappingResponse createEmptyInstance() => SetMappingResponse._();
  @$core.pragma('dart2js:noInline')
  static SetMappingResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetMappingResponse>(
          SetMappingResponse.$_createMessage);
  static SetMappingResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get saved => $_getBF(0);
  @$pb.TagNumber(1)
  set saved($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSaved() => $_has(0);
  @$pb.TagNumber(1)
  void clearSaved() => $_clearField(1);

  /// Why not, in words for the screen.
  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);

  @$pb.TagNumber(3)
  SwitchState get state => $_getN(2);
  @$pb.TagNumber(3)
  set state(SwitchState value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasState() => $_has(2);
  @$pb.TagNumber(3)
  void clearState() => $_clearField(3);
  @$pb.TagNumber(3)
  SwitchState ensureState() => $_ensure(2);
}

class ResetMappingRequest extends $pb.GeneratedMessage {
  factory ResetMappingRequest({
    $core.String? source,
  }) {
    final result = ResetMappingRequest._();
    if (source != null) result.source = source;
    return result;
  }

  ResetMappingRequest._();

  factory ResetMappingRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResetMappingRequest()..mergeFromBuffer(data, registry);
  factory ResetMappingRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResetMappingRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ResetMappingRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.power.v1'),
      createEmptyInstance: ResetMappingRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResetMappingRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResetMappingRequest copyWith(void Function(ResetMappingRequest) updates) =>
      super.copyWith((message) => updates(message as ResetMappingRequest))
          as ResetMappingRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ResetMappingRequest() / ResetMappingRequest.new instead')
  static ResetMappingRequest create() => ResetMappingRequest._();
  static $pb.GeneratedMessage $_createMessage() => ResetMappingRequest._();
  @$core.override
  ResetMappingRequest createEmptyInstance() => ResetMappingRequest._();
  @$core.pragma('dart2js:noInline')
  static ResetMappingRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ResetMappingRequest>(
          ResetMappingRequest.$_createMessage);
  static ResetMappingRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get source => $_getSZ(0);
  @$pb.TagNumber(1)
  set source($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSource() => $_has(0);
  @$pb.TagNumber(1)
  void clearSource() => $_clearField(1);
}

class ResetMappingResponse extends $pb.GeneratedMessage {
  factory ResetMappingResponse({
    $core.bool? saved,
    $core.String? detail,
    SwitchState? state,
  }) {
    final result = ResetMappingResponse._();
    if (saved != null) result.saved = saved;
    if (detail != null) result.detail = detail;
    if (state != null) result.state = state;
    return result;
  }

  ResetMappingResponse._();

  factory ResetMappingResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResetMappingResponse()..mergeFromBuffer(data, registry);
  factory ResetMappingResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResetMappingResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ResetMappingResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.power.v1'),
      createEmptyInstance: ResetMappingResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'saved')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..aOM<SwitchState>(3, _omitFieldNames ? '' : 'state',
        subBuilder: SwitchState.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResetMappingResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResetMappingResponse copyWith(void Function(ResetMappingResponse) updates) =>
      super.copyWith((message) => updates(message as ResetMappingResponse))
          as ResetMappingResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ResetMappingResponse() / ResetMappingResponse.new instead')
  static ResetMappingResponse create() => ResetMappingResponse._();
  static $pb.GeneratedMessage $_createMessage() => ResetMappingResponse._();
  @$core.override
  ResetMappingResponse createEmptyInstance() => ResetMappingResponse._();
  @$core.pragma('dart2js:noInline')
  static ResetMappingResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ResetMappingResponse>(
          ResetMappingResponse.$_createMessage);
  static ResetMappingResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get saved => $_getBF(0);
  @$pb.TagNumber(1)
  set saved($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSaved() => $_has(0);
  @$pb.TagNumber(1)
  void clearSaved() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);

  @$pb.TagNumber(3)
  SwitchState get state => $_getN(2);
  @$pb.TagNumber(3)
  set state(SwitchState value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasState() => $_has(2);
  @$pb.TagNumber(3)
  void clearState() => $_clearField(3);
  @$pb.TagNumber(3)
  SwitchState ensureState() => $_ensure(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
