// This is a generated file - do not edit.
//
// Generated from f250/vehicle/v1/diagnostics.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class SetPollingRequest extends $pb.GeneratedMessage {
  factory SetPollingRequest({
    $core.String? signalId,
    $core.bool? enabled,
  }) {
    final result = SetPollingRequest._();
    if (signalId != null) result.signalId = signalId;
    if (enabled != null) result.enabled = enabled;
    return result;
  }

  SetPollingRequest._();

  factory SetPollingRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetPollingRequest()..mergeFromBuffer(data, registry);
  factory SetPollingRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetPollingRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetPollingRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: SetPollingRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'signalId')
    ..aOB(2, _omitFieldNames ? '' : 'enabled')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetPollingRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetPollingRequest copyWith(void Function(SetPollingRequest) updates) =>
      super.copyWith((message) => updates(message as SetPollingRequest))
          as SetPollingRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SetPollingRequest() / SetPollingRequest.new instead')
  static SetPollingRequest create() => SetPollingRequest._();
  static $pb.GeneratedMessage $_createMessage() => SetPollingRequest._();
  @$core.override
  SetPollingRequest createEmptyInstance() => SetPollingRequest._();
  @$core.pragma('dart2js:noInline')
  static SetPollingRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetPollingRequest>(
          SetPollingRequest.$_createMessage);
  static SetPollingRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get signalId => $_getSZ(0);
  @$pb.TagNumber(1)
  set signalId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSignalId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSignalId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get enabled => $_getBF(1);
  @$pb.TagNumber(2)
  set enabled($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEnabled() => $_has(1);
  @$pb.TagNumber(2)
  void clearEnabled() => $_clearField(2);
}

class SetPollingResponse extends $pb.GeneratedMessage {
  factory SetPollingResponse() => SetPollingResponse._();

  SetPollingResponse._();

  factory SetPollingResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetPollingResponse()..mergeFromBuffer(data, registry);
  factory SetPollingResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetPollingResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetPollingResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: SetPollingResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetPollingResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetPollingResponse copyWith(void Function(SetPollingResponse) updates) =>
      super.copyWith((message) => updates(message as SetPollingResponse))
          as SetPollingResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SetPollingResponse() / SetPollingResponse.new instead')
  static SetPollingResponse create() => SetPollingResponse._();
  static $pb.GeneratedMessage $_createMessage() => SetPollingResponse._();
  @$core.override
  SetPollingResponse createEmptyInstance() => SetPollingResponse._();
  @$core.pragma('dart2js:noInline')
  static SetPollingResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetPollingResponse>(
          SetPollingResponse.$_createMessage);
  static SetPollingResponse? _defaultInstance;
}

class ProbeRequest extends $pb.GeneratedMessage {
  factory ProbeRequest({
    $core.String? signalId,
    $core.int? count,
  }) {
    final result = ProbeRequest._();
    if (signalId != null) result.signalId = signalId;
    if (count != null) result.count = count;
    return result;
  }

  ProbeRequest._();

  factory ProbeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ProbeRequest()..mergeFromBuffer(data, registry);
  factory ProbeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ProbeRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProbeRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: ProbeRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'signalId')
    ..aI(2, _omitFieldNames ? '' : 'count', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProbeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProbeRequest copyWith(void Function(ProbeRequest) updates) =>
      super.copyWith((message) => updates(message as ProbeRequest))
          as ProbeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ProbeRequest() / ProbeRequest.new instead')
  static ProbeRequest create() => ProbeRequest._();
  static $pb.GeneratedMessage $_createMessage() => ProbeRequest._();
  @$core.override
  ProbeRequest createEmptyInstance() => ProbeRequest._();
  @$core.pragma('dart2js:noInline')
  static ProbeRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ProbeRequest>(
          ProbeRequest.$_createMessage);
  static ProbeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get signalId => $_getSZ(0);
  @$pb.TagNumber(1)
  set signalId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSignalId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSignalId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get count => $_getIZ(1);
  @$pb.TagNumber(2)
  set count($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCount() => $_has(1);
  @$pb.TagNumber(2)
  void clearCount() => $_clearField(2);
}

class Responder extends $pb.GeneratedMessage {
  factory Responder({
    $core.String? canId,
    $core.String? payloadHex,
    $core.double? decoded,
  }) {
    final result = Responder._();
    if (canId != null) result.canId = canId;
    if (payloadHex != null) result.payloadHex = payloadHex;
    if (decoded != null) result.decoded = decoded;
    return result;
  }

  Responder._();

  factory Responder.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Responder()..mergeFromBuffer(data, registry);
  factory Responder.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Responder()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Responder',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: Responder.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'canId')
    ..aOS(2, _omitFieldNames ? '' : 'payloadHex')
    ..aD(3, _omitFieldNames ? '' : 'decoded')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Responder clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Responder copyWith(void Function(Responder) updates) =>
      super.copyWith((message) => updates(message as Responder)) as Responder;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Responder() / Responder.new instead')
  static Responder create() => Responder._();
  static $pb.GeneratedMessage $_createMessage() => Responder._();
  @$core.override
  Responder createEmptyInstance() => Responder._();
  @$core.pragma('dart2js:noInline')
  static Responder getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Responder>(Responder.$_createMessage);
  static Responder? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get canId => $_getSZ(0);
  @$pb.TagNumber(1)
  set canId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCanId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCanId() => $_clearField(1);

  /// Payload bytes after the positive-response echo, hex.
  @$pb.TagNumber(2)
  $core.String get payloadHex => $_getSZ(1);
  @$pb.TagNumber(2)
  set payloadHex($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPayloadHex() => $_has(1);
  @$pb.TagNumber(2)
  void clearPayloadHex() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get decoded => $_getN(2);
  @$pb.TagNumber(3)
  set decoded($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDecoded() => $_has(2);
  @$pb.TagNumber(3)
  void clearDecoded() => $_clearField(3);
}

class ProbeAttempt extends $pb.GeneratedMessage {
  factory ProbeAttempt({
    $core.String? outcome,
    $core.int? latencyMs,
    $core.Iterable<Responder>? responders,
    $core.int? nrc,
    $core.String? detail,
  }) {
    final result = ProbeAttempt._();
    if (outcome != null) result.outcome = outcome;
    if (latencyMs != null) result.latencyMs = latencyMs;
    if (responders != null) result.responders.addAll(responders);
    if (nrc != null) result.nrc = nrc;
    if (detail != null) result.detail = detail;
    return result;
  }

  ProbeAttempt._();

  factory ProbeAttempt.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ProbeAttempt()..mergeFromBuffer(data, registry);
  factory ProbeAttempt.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ProbeAttempt()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProbeAttempt',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: ProbeAttempt.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'outcome')
    ..aI(2, _omitFieldNames ? '' : 'latencyMs', fieldType: $pb.PbFieldType.OU3)
    ..pPM<Responder>(3, _omitFieldNames ? '' : 'responders',
        subBuilder: Responder.$_createMessage)
    ..aI(4, _omitFieldNames ? '' : 'nrc', fieldType: $pb.PbFieldType.OU3)
    ..aOS(5, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProbeAttempt clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProbeAttempt copyWith(void Function(ProbeAttempt) updates) =>
      super.copyWith((message) => updates(message as ProbeAttempt))
          as ProbeAttempt;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ProbeAttempt() / ProbeAttempt.new instead')
  static ProbeAttempt create() => ProbeAttempt._();
  static $pb.GeneratedMessage $_createMessage() => ProbeAttempt._();
  @$core.override
  ProbeAttempt createEmptyInstance() => ProbeAttempt._();
  @$core.pragma('dart2js:noInline')
  static ProbeAttempt getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ProbeAttempt>(
          ProbeAttempt.$_createMessage);
  static ProbeAttempt? _defaultInstance;

  /// "ok", "no_response", "negative", "invalid", "link_down", "refused".
  @$pb.TagNumber(1)
  $core.String get outcome => $_getSZ(0);
  @$pb.TagNumber(1)
  set outcome($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOutcome() => $_has(0);
  @$pb.TagNumber(1)
  void clearOutcome() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get latencyMs => $_getIZ(1);
  @$pb.TagNumber(2)
  set latencyMs($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLatencyMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearLatencyMs() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<Responder> get responders => $_getList(2);

  @$pb.TagNumber(4)
  $core.int get nrc => $_getIZ(3);
  @$pb.TagNumber(4)
  set nrc($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasNrc() => $_has(3);
  @$pb.TagNumber(4)
  void clearNrc() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get detail => $_getSZ(4);
  @$pb.TagNumber(5)
  set detail($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDetail() => $_has(4);
  @$pb.TagNumber(5)
  void clearDetail() => $_clearField(5);
}

class ProbeResponse extends $pb.GeneratedMessage {
  factory ProbeResponse({
    $core.Iterable<ProbeAttempt>? attempts,
  }) {
    final result = ProbeResponse._();
    if (attempts != null) result.attempts.addAll(attempts);
    return result;
  }

  ProbeResponse._();

  factory ProbeResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ProbeResponse()..mergeFromBuffer(data, registry);
  factory ProbeResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ProbeResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProbeResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: ProbeResponse.$_createMessage)
    ..pPM<ProbeAttempt>(1, _omitFieldNames ? '' : 'attempts',
        subBuilder: ProbeAttempt.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProbeResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProbeResponse copyWith(void Function(ProbeResponse) updates) =>
      super.copyWith((message) => updates(message as ProbeResponse))
          as ProbeResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ProbeResponse() / ProbeResponse.new instead')
  static ProbeResponse create() => ProbeResponse._();
  static $pb.GeneratedMessage $_createMessage() => ProbeResponse._();
  @$core.override
  ProbeResponse createEmptyInstance() => ProbeResponse._();
  @$core.pragma('dart2js:noInline')
  static ProbeResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ProbeResponse>(
          ProbeResponse.$_createMessage);
  static ProbeResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<ProbeAttempt> get attempts => $_getList(0);
}

class RawRequest extends $pb.GeneratedMessage {
  factory RawRequest({
    $core.String? line,
  }) {
    final result = RawRequest._();
    if (line != null) result.line = line;
    return result;
  }

  RawRequest._();

  factory RawRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RawRequest()..mergeFromBuffer(data, registry);
  factory RawRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RawRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RawRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: RawRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'line')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RawRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RawRequest copyWith(void Function(RawRequest) updates) =>
      super.copyWith((message) => updates(message as RawRequest)) as RawRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RawRequest() / RawRequest.new instead')
  static RawRequest create() => RawRequest._();
  static $pb.GeneratedMessage $_createMessage() => RawRequest._();
  @$core.override
  RawRequest createEmptyInstance() => RawRequest._();
  @$core.pragma('dart2js:noInline')
  static RawRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RawRequest>(RawRequest.$_createMessage);
  static RawRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get line => $_getSZ(0);
  @$pb.TagNumber(1)
  set line($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLine() => $_has(0);
  @$pb.TagNumber(1)
  void clearLine() => $_clearField(1);
}

class RawResponse extends $pb.GeneratedMessage {
  factory RawResponse({
    $core.Iterable<$core.String>? lines,
    $core.int? latencyMs,
    $core.String? refused,
  }) {
    final result = RawResponse._();
    if (lines != null) result.lines.addAll(lines);
    if (latencyMs != null) result.latencyMs = latencyMs;
    if (refused != null) result.refused = refused;
    return result;
  }

  RawResponse._();

  factory RawResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RawResponse()..mergeFromBuffer(data, registry);
  factory RawResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RawResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RawResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: RawResponse.$_createMessage)
    ..pPS(1, _omitFieldNames ? '' : 'lines')
    ..aI(2, _omitFieldNames ? '' : 'latencyMs', fieldType: $pb.PbFieldType.OU3)
    ..aOS(3, _omitFieldNames ? '' : 'refused')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RawResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RawResponse copyWith(void Function(RawResponse) updates) =>
      super.copyWith((message) => updates(message as RawResponse))
          as RawResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RawResponse() / RawResponse.new instead')
  static RawResponse create() => RawResponse._();
  static $pb.GeneratedMessage $_createMessage() => RawResponse._();
  @$core.override
  RawResponse createEmptyInstance() => RawResponse._();
  @$core.pragma('dart2js:noInline')
  static RawResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RawResponse>(
          RawResponse.$_createMessage);
  static RawResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get lines => $_getList(0);

  @$pb.TagNumber(2)
  $core.int get latencyMs => $_getIZ(1);
  @$pb.TagNumber(2)
  set latencyMs($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLatencyMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearLatencyMs() => $_clearField(2);

  /// Set when the gateway refused the line (e.g. a service outside the allow-list).
  @$pb.TagNumber(3)
  $core.String get refused => $_getSZ(2);
  @$pb.TagNumber(3)
  set refused($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRefused() => $_has(2);
  @$pb.TagNumber(3)
  void clearRefused() => $_clearField(3);
}

class StatsRequest extends $pb.GeneratedMessage {
  factory StatsRequest({
    $core.bool? reset,
  }) {
    final result = StatsRequest._();
    if (reset != null) result.reset = reset;
    return result;
  }

  StatsRequest._();

  factory StatsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StatsRequest()..mergeFromBuffer(data, registry);
  factory StatsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StatsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StatsRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: StatsRequest.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'reset')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StatsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StatsRequest copyWith(void Function(StatsRequest) updates) =>
      super.copyWith((message) => updates(message as StatsRequest))
          as StatsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use StatsRequest() / StatsRequest.new instead')
  static StatsRequest create() => StatsRequest._();
  static $pb.GeneratedMessage $_createMessage() => StatsRequest._();
  @$core.override
  StatsRequest createEmptyInstance() => StatsRequest._();
  @$core.pragma('dart2js:noInline')
  static StatsRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StatsRequest>(
          StatsRequest.$_createMessage);
  static StatsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get reset => $_getBF(0);
  @$pb.TagNumber(1)
  set reset($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasReset() => $_has(0);
  @$pb.TagNumber(1)
  void clearReset() => $_clearField(1);
}

class SignalStats extends $pb.GeneratedMessage {
  factory SignalStats({
    $core.String? signalId,
    $fixnum.Int64? successes,
    $fixnum.Int64? failures,
    $core.int? latencyP50Ms,
    $core.int? latencyP95Ms,
    $core.String? pollState,
    $core.int? intervalMs,
  }) {
    final result = SignalStats._();
    if (signalId != null) result.signalId = signalId;
    if (successes != null) result.successes = successes;
    if (failures != null) result.failures = failures;
    if (latencyP50Ms != null) result.latencyP50Ms = latencyP50Ms;
    if (latencyP95Ms != null) result.latencyP95Ms = latencyP95Ms;
    if (pollState != null) result.pollState = pollState;
    if (intervalMs != null) result.intervalMs = intervalMs;
    return result;
  }

  SignalStats._();

  factory SignalStats.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SignalStats()..mergeFromBuffer(data, registry);
  factory SignalStats.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SignalStats()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SignalStats',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: SignalStats.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'signalId')
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'successes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'failures', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(4, _omitFieldNames ? '' : 'latencyP50Ms',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'latencyP95Ms',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(6, _omitFieldNames ? '' : 'pollState')
    ..aI(7, _omitFieldNames ? '' : 'intervalMs', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SignalStats clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SignalStats copyWith(void Function(SignalStats) updates) =>
      super.copyWith((message) => updates(message as SignalStats))
          as SignalStats;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SignalStats() / SignalStats.new instead')
  static SignalStats create() => SignalStats._();
  static $pb.GeneratedMessage $_createMessage() => SignalStats._();
  @$core.override
  SignalStats createEmptyInstance() => SignalStats._();
  @$core.pragma('dart2js:noInline')
  static SignalStats getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SignalStats>(
          SignalStats.$_createMessage);
  static SignalStats? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get signalId => $_getSZ(0);
  @$pb.TagNumber(1)
  set signalId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSignalId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSignalId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get successes => $_getI64(1);
  @$pb.TagNumber(2)
  set successes($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSuccesses() => $_has(1);
  @$pb.TagNumber(2)
  void clearSuccesses() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get failures => $_getI64(2);
  @$pb.TagNumber(3)
  set failures($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFailures() => $_has(2);
  @$pb.TagNumber(3)
  void clearFailures() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get latencyP50Ms => $_getIZ(3);
  @$pb.TagNumber(4)
  set latencyP50Ms($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLatencyP50Ms() => $_has(3);
  @$pb.TagNumber(4)
  void clearLatencyP50Ms() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get latencyP95Ms => $_getIZ(4);
  @$pb.TagNumber(5)
  set latencyP95Ms($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasLatencyP95Ms() => $_has(4);
  @$pb.TagNumber(5)
  void clearLatencyP95Ms() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get pollState => $_getSZ(5);
  @$pb.TagNumber(6)
  set pollState($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPollState() => $_has(5);
  @$pb.TagNumber(6)
  void clearPollState() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get intervalMs => $_getIZ(6);
  @$pb.TagNumber(7)
  set intervalMs($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIntervalMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearIntervalMs() => $_clearField(7);
}

class StatsResponse extends $pb.GeneratedMessage {
  factory StatsResponse({
    $core.double? requestsPerSecond,
    $core.Iterable<SignalStats>? signals,
    $fixnum.Int64? windowMs,
  }) {
    final result = StatsResponse._();
    if (requestsPerSecond != null) result.requestsPerSecond = requestsPerSecond;
    if (signals != null) result.signals.addAll(signals);
    if (windowMs != null) result.windowMs = windowMs;
    return result;
  }

  StatsResponse._();

  factory StatsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StatsResponse()..mergeFromBuffer(data, registry);
  factory StatsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StatsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StatsResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: StatsResponse.$_createMessage)
    ..aD(1, _omitFieldNames ? '' : 'requestsPerSecond')
    ..pPM<SignalStats>(2, _omitFieldNames ? '' : 'signals',
        subBuilder: SignalStats.$_createMessage)
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'windowMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StatsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StatsResponse copyWith(void Function(StatsResponse) updates) =>
      super.copyWith((message) => updates(message as StatsResponse))
          as StatsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use StatsResponse() / StatsResponse.new instead')
  static StatsResponse create() => StatsResponse._();
  static $pb.GeneratedMessage $_createMessage() => StatsResponse._();
  @$core.override
  StatsResponse createEmptyInstance() => StatsResponse._();
  @$core.pragma('dart2js:noInline')
  static StatsResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StatsResponse>(
          StatsResponse.$_createMessage);
  static StatsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get requestsPerSecond => $_getN(0);
  @$pb.TagNumber(1)
  set requestsPerSecond($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestsPerSecond() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestsPerSecond() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<SignalStats> get signals => $_getList(1);

  @$pb.TagNumber(3)
  $fixnum.Int64 get windowMs => $_getI64(2);
  @$pb.TagNumber(3)
  set windowMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasWindowMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearWindowMs() => $_clearField(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
