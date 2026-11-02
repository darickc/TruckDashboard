// This is a generated file - do not edit.
//
// Generated from f250/vehicle/v1/vehicle.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'vehicle.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'vehicle.pbenum.dart';

class SignalDefinition extends $pb.GeneratedMessage {
  factory SignalDefinition({
    $core.String? id,
    $core.String? name,
    $core.String? shortName,
    Quantity? quantity,
    $core.String? unit,
    Provenance? provenance,
    $core.double? min,
    $core.double? max,
    $core.int? staleAfterMs,
    $core.String? request,
    $core.String? responder,
    $core.String? evidence,
    $core.bool? enabled,
    $core.String? disabledReason,
    $core.Iterable<$core.String>? inputs,
    $core.double? calibrationScale,
    $core.double? calibrationOffset,
  }) {
    final result = SignalDefinition._();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (shortName != null) result.shortName = shortName;
    if (quantity != null) result.quantity = quantity;
    if (unit != null) result.unit = unit;
    if (provenance != null) result.provenance = provenance;
    if (min != null) result.min = min;
    if (max != null) result.max = max;
    if (staleAfterMs != null) result.staleAfterMs = staleAfterMs;
    if (request != null) result.request = request;
    if (responder != null) result.responder = responder;
    if (evidence != null) result.evidence = evidence;
    if (enabled != null) result.enabled = enabled;
    if (disabledReason != null) result.disabledReason = disabledReason;
    if (inputs != null) result.inputs.addAll(inputs);
    if (calibrationScale != null) result.calibrationScale = calibrationScale;
    if (calibrationOffset != null) result.calibrationOffset = calibrationOffset;
    return result;
  }

  SignalDefinition._();

  factory SignalDefinition.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SignalDefinition()..mergeFromBuffer(data, registry);
  factory SignalDefinition.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SignalDefinition()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SignalDefinition',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: SignalDefinition.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'shortName')
    ..aE<Quantity>(4, _omitFieldNames ? '' : 'quantity',
        enumValues: Quantity.values)
    ..aOS(5, _omitFieldNames ? '' : 'unit')
    ..aE<Provenance>(6, _omitFieldNames ? '' : 'provenance',
        enumValues: Provenance.values)
    ..aD(7, _omitFieldNames ? '' : 'min')
    ..aD(8, _omitFieldNames ? '' : 'max')
    ..aI(9, _omitFieldNames ? '' : 'staleAfterMs',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(10, _omitFieldNames ? '' : 'request')
    ..aOS(11, _omitFieldNames ? '' : 'responder')
    ..aOS(12, _omitFieldNames ? '' : 'evidence')
    ..aOB(13, _omitFieldNames ? '' : 'enabled')
    ..aOS(14, _omitFieldNames ? '' : 'disabledReason')
    ..pPS(15, _omitFieldNames ? '' : 'inputs')
    ..aD(16, _omitFieldNames ? '' : 'calibrationScale')
    ..aD(17, _omitFieldNames ? '' : 'calibrationOffset')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SignalDefinition clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SignalDefinition copyWith(void Function(SignalDefinition) updates) =>
      super.copyWith((message) => updates(message as SignalDefinition))
          as SignalDefinition;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SignalDefinition() / SignalDefinition.new instead')
  static SignalDefinition create() => SignalDefinition._();
  static $pb.GeneratedMessage $_createMessage() => SignalDefinition._();
  @$core.override
  SignalDefinition createEmptyInstance() => SignalDefinition._();
  @$core.pragma('dart2js:noInline')
  static SignalDefinition getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SignalDefinition>(
          SignalDefinition.$_createMessage);
  static SignalDefinition? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get shortName => $_getSZ(2);
  @$pb.TagNumber(3)
  set shortName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasShortName() => $_has(2);
  @$pb.TagNumber(3)
  void clearShortName() => $_clearField(3);

  @$pb.TagNumber(4)
  Quantity get quantity => $_getN(3);
  @$pb.TagNumber(4)
  set quantity(Quantity value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasQuantity() => $_has(3);
  @$pb.TagNumber(4)
  void clearQuantity() => $_clearField(4);

  /// Canonical unit (degC, kPa, V, km/h, rpm, %).
  @$pb.TagNumber(5)
  $core.String get unit => $_getSZ(4);
  @$pb.TagNumber(5)
  set unit($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasUnit() => $_has(4);
  @$pb.TagNumber(5)
  void clearUnit() => $_clearField(5);

  @$pb.TagNumber(6)
  Provenance get provenance => $_getN(5);
  @$pb.TagNumber(6)
  set provenance(Provenance value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasProvenance() => $_has(5);
  @$pb.TagNumber(6)
  void clearProvenance() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.double get min => $_getN(6);
  @$pb.TagNumber(7)
  set min($core.double value) => $_setDouble(6, value);
  @$pb.TagNumber(7)
  $core.bool hasMin() => $_has(6);
  @$pb.TagNumber(7)
  void clearMin() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.double get max => $_getN(7);
  @$pb.TagNumber(8)
  set max($core.double value) => $_setDouble(7, value);
  @$pb.TagNumber(8)
  $core.bool hasMax() => $_has(7);
  @$pb.TagNumber(8)
  void clearMax() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get staleAfterMs => $_getIZ(8);
  @$pb.TagNumber(9)
  set staleAfterMs($core.int value) => $_setUnsignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasStaleAfterMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearStaleAfterMs() => $_clearField(9);

  /// Request as documented, for display (e.g. "22 16 74").
  @$pb.TagNumber(10)
  $core.String get request => $_getSZ(9);
  @$pb.TagNumber(10)
  set request($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasRequest() => $_has(9);
  @$pb.TagNumber(10)
  void clearRequest() => $_clearField(10);

  /// CAN ID of the owning module when verified (e.g. "7E9").
  @$pb.TagNumber(11)
  $core.String get responder => $_getSZ(10);
  @$pb.TagNumber(11)
  set responder($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasResponder() => $_has(10);
  @$pb.TagNumber(11)
  void clearResponder() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get evidence => $_getSZ(11);
  @$pb.TagNumber(12)
  set evidence($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasEvidence() => $_has(11);
  @$pb.TagNumber(12)
  void clearEvidence() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.bool get enabled => $_getBF(12);
  @$pb.TagNumber(13)
  set enabled($core.bool value) => $_setBool(12, value);
  @$pb.TagNumber(13)
  $core.bool hasEnabled() => $_has(12);
  @$pb.TagNumber(13)
  void clearEnabled() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get disabledReason => $_getSZ(13);
  @$pb.TagNumber(14)
  set disabledReason($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasDisabledReason() => $_has(13);
  @$pb.TagNumber(14)
  void clearDisabledReason() => $_clearField(14);

  /// Computed signals: input ids.
  @$pb.TagNumber(15)
  $pb.PbList<$core.String> get inputs => $_getList(14);

  @$pb.TagNumber(16)
  $core.double get calibrationScale => $_getN(15);
  @$pb.TagNumber(16)
  set calibrationScale($core.double value) => $_setDouble(15, value);
  @$pb.TagNumber(16)
  $core.bool hasCalibrationScale() => $_has(15);
  @$pb.TagNumber(16)
  void clearCalibrationScale() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.double get calibrationOffset => $_getN(16);
  @$pb.TagNumber(17)
  set calibrationOffset($core.double value) => $_setDouble(16, value);
  @$pb.TagNumber(17)
  $core.bool hasCalibrationOffset() => $_has(16);
  @$pb.TagNumber(17)
  void clearCalibrationOffset() => $_clearField(17);
}

class ListSignalsRequest extends $pb.GeneratedMessage {
  factory ListSignalsRequest() => ListSignalsRequest._();

  ListSignalsRequest._();

  factory ListSignalsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListSignalsRequest()..mergeFromBuffer(data, registry);
  factory ListSignalsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListSignalsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListSignalsRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: ListSignalsRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListSignalsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListSignalsRequest copyWith(void Function(ListSignalsRequest) updates) =>
      super.copyWith((message) => updates(message as ListSignalsRequest))
          as ListSignalsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListSignalsRequest() / ListSignalsRequest.new instead')
  static ListSignalsRequest create() => ListSignalsRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListSignalsRequest._();
  @$core.override
  ListSignalsRequest createEmptyInstance() => ListSignalsRequest._();
  @$core.pragma('dart2js:noInline')
  static ListSignalsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListSignalsRequest>(
          ListSignalsRequest.$_createMessage);
  static ListSignalsRequest? _defaultInstance;
}

class ListSignalsResponse extends $pb.GeneratedMessage {
  factory ListSignalsResponse({
    $core.Iterable<SignalDefinition>? signals,
  }) {
    final result = ListSignalsResponse._();
    if (signals != null) result.signals.addAll(signals);
    return result;
  }

  ListSignalsResponse._();

  factory ListSignalsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListSignalsResponse()..mergeFromBuffer(data, registry);
  factory ListSignalsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListSignalsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListSignalsResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: ListSignalsResponse.$_createMessage)
    ..pPM<SignalDefinition>(1, _omitFieldNames ? '' : 'signals',
        subBuilder: SignalDefinition.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListSignalsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListSignalsResponse copyWith(void Function(ListSignalsResponse) updates) =>
      super.copyWith((message) => updates(message as ListSignalsResponse))
          as ListSignalsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ListSignalsResponse() / ListSignalsResponse.new instead')
  static ListSignalsResponse create() => ListSignalsResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListSignalsResponse._();
  @$core.override
  ListSignalsResponse createEmptyInstance() => ListSignalsResponse._();
  @$core.pragma('dart2js:noInline')
  static ListSignalsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListSignalsResponse>(
          ListSignalsResponse.$_createMessage);
  static ListSignalsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<SignalDefinition> get signals => $_getList(0);
}

class Sample extends $pb.GeneratedMessage {
  factory Sample({
    $core.String? signalId,
    Validity? validity,
    $core.double? value,
    $core.double? lastGoodValue,
    $core.double? lastGoodRaw,
    $fixnum.Int64? lastGoodAgeMs,
    $core.double? rejectedValue,
    $core.int? lastNrc,
    $core.String? lastResponder,
    $core.int? lastLatencyMs,
    $fixnum.Int64? successes,
    $fixnum.Int64? failures,
    $core.int? consecutiveFailures,
    $core.Iterable<$core.String>? invalidInputs,
    $core.String? pollState,
  }) {
    final result = Sample._();
    if (signalId != null) result.signalId = signalId;
    if (validity != null) result.validity = validity;
    if (value != null) result.value = value;
    if (lastGoodValue != null) result.lastGoodValue = lastGoodValue;
    if (lastGoodRaw != null) result.lastGoodRaw = lastGoodRaw;
    if (lastGoodAgeMs != null) result.lastGoodAgeMs = lastGoodAgeMs;
    if (rejectedValue != null) result.rejectedValue = rejectedValue;
    if (lastNrc != null) result.lastNrc = lastNrc;
    if (lastResponder != null) result.lastResponder = lastResponder;
    if (lastLatencyMs != null) result.lastLatencyMs = lastLatencyMs;
    if (successes != null) result.successes = successes;
    if (failures != null) result.failures = failures;
    if (consecutiveFailures != null)
      result.consecutiveFailures = consecutiveFailures;
    if (invalidInputs != null) result.invalidInputs.addAll(invalidInputs);
    if (pollState != null) result.pollState = pollState;
    return result;
  }

  Sample._();

  factory Sample.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Sample()..mergeFromBuffer(data, registry);
  factory Sample.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Sample()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Sample',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: Sample.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'signalId')
    ..aE<Validity>(2, _omitFieldNames ? '' : 'validity',
        enumValues: Validity.values)
    ..aD(3, _omitFieldNames ? '' : 'value')
    ..aD(4, _omitFieldNames ? '' : 'lastGoodValue')
    ..aD(5, _omitFieldNames ? '' : 'lastGoodRaw')
    ..a<$fixnum.Int64>(
        6, _omitFieldNames ? '' : 'lastGoodAgeMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aD(7, _omitFieldNames ? '' : 'rejectedValue')
    ..aI(8, _omitFieldNames ? '' : 'lastNrc', fieldType: $pb.PbFieldType.OU3)
    ..aOS(9, _omitFieldNames ? '' : 'lastResponder')
    ..aI(10, _omitFieldNames ? '' : 'lastLatencyMs',
        fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(
        11, _omitFieldNames ? '' : 'successes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        12, _omitFieldNames ? '' : 'failures', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(13, _omitFieldNames ? '' : 'consecutiveFailures',
        fieldType: $pb.PbFieldType.OU3)
    ..pPS(14, _omitFieldNames ? '' : 'invalidInputs')
    ..aOS(15, _omitFieldNames ? '' : 'pollState')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Sample clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Sample copyWith(void Function(Sample) updates) =>
      super.copyWith((message) => updates(message as Sample)) as Sample;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Sample() / Sample.new instead')
  static Sample create() => Sample._();
  static $pb.GeneratedMessage $_createMessage() => Sample._();
  @$core.override
  Sample createEmptyInstance() => Sample._();
  @$core.pragma('dart2js:noInline')
  static Sample getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Sample>(Sample.$_createMessage);
  static Sample? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get signalId => $_getSZ(0);
  @$pb.TagNumber(1)
  set signalId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSignalId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSignalId() => $_clearField(1);

  @$pb.TagNumber(2)
  Validity get validity => $_getN(1);
  @$pb.TagNumber(2)
  set validity(Validity value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasValidity() => $_has(1);
  @$pb.TagNumber(2)
  void clearValidity() => $_clearField(2);

  /// Present only while validity is VALID. A client must never display
  /// last_good_value as current.
  @$pb.TagNumber(3)
  $core.double get value => $_getN(2);
  @$pb.TagNumber(3)
  set value($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasValue() => $_has(2);
  @$pb.TagNumber(3)
  void clearValue() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get lastGoodValue => $_getN(3);
  @$pb.TagNumber(4)
  set lastGoodValue($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLastGoodValue() => $_has(3);
  @$pb.TagNumber(4)
  void clearLastGoodValue() => $_clearField(4);

  /// Before calibration.
  @$pb.TagNumber(5)
  $core.double get lastGoodRaw => $_getN(4);
  @$pb.TagNumber(5)
  set lastGoodRaw($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasLastGoodRaw() => $_has(4);
  @$pb.TagNumber(5)
  void clearLastGoodRaw() => $_clearField(5);

  /// Age of the last good reading at Snapshot.mono_ms.
  @$pb.TagNumber(6)
  $fixnum.Int64 get lastGoodAgeMs => $_getI64(5);
  @$pb.TagNumber(6)
  set lastGoodAgeMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLastGoodAgeMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearLastGoodAgeMs() => $_clearField(6);

  /// The latest answer, when it was implausible (OUT_OF_RANGE).
  @$pb.TagNumber(7)
  $core.double get rejectedValue => $_getN(6);
  @$pb.TagNumber(7)
  set rejectedValue($core.double value) => $_setDouble(6, value);
  @$pb.TagNumber(7)
  $core.bool hasRejectedValue() => $_has(6);
  @$pb.TagNumber(7)
  void clearRejectedValue() => $_clearField(7);

  /// Last negative response code, 0 if none.
  @$pb.TagNumber(8)
  $core.int get lastNrc => $_getIZ(7);
  @$pb.TagNumber(8)
  set lastNrc($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasLastNrc() => $_has(7);
  @$pb.TagNumber(8)
  void clearLastNrc() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get lastResponder => $_getSZ(8);
  @$pb.TagNumber(9)
  set lastResponder($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasLastResponder() => $_has(8);
  @$pb.TagNumber(9)
  void clearLastResponder() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get lastLatencyMs => $_getIZ(9);
  @$pb.TagNumber(10)
  set lastLatencyMs($core.int value) => $_setUnsignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasLastLatencyMs() => $_has(9);
  @$pb.TagNumber(10)
  void clearLastLatencyMs() => $_clearField(10);

  @$pb.TagNumber(11)
  $fixnum.Int64 get successes => $_getI64(10);
  @$pb.TagNumber(11)
  set successes($fixnum.Int64 value) => $_setInt64(10, value);
  @$pb.TagNumber(11)
  $core.bool hasSuccesses() => $_has(10);
  @$pb.TagNumber(11)
  void clearSuccesses() => $_clearField(11);

  @$pb.TagNumber(12)
  $fixnum.Int64 get failures => $_getI64(11);
  @$pb.TagNumber(12)
  set failures($fixnum.Int64 value) => $_setInt64(11, value);
  @$pb.TagNumber(12)
  $core.bool hasFailures() => $_has(11);
  @$pb.TagNumber(12)
  void clearFailures() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.int get consecutiveFailures => $_getIZ(12);
  @$pb.TagNumber(13)
  set consecutiveFailures($core.int value) => $_setUnsignedInt32(12, value);
  @$pb.TagNumber(13)
  $core.bool hasConsecutiveFailures() => $_has(12);
  @$pb.TagNumber(13)
  void clearConsecutiveFailures() => $_clearField(13);

  /// Computed signals: inputs that are not VALID.
  @$pb.TagNumber(14)
  $pb.PbList<$core.String> get invalidInputs => $_getList(13);

  /// Scheduler state for diagnosis (ACTIVE, SUSPECT, BACKOFF, QUARANTINED, OFF).
  @$pb.TagNumber(15)
  $core.String get pollState => $_getSZ(14);
  @$pb.TagNumber(15)
  set pollState($core.String value) => $_setString(14, value);
  @$pb.TagNumber(15)
  $core.bool hasPollState() => $_has(14);
  @$pb.TagNumber(15)
  void clearPollState() => $_clearField(15);
}

class LinkStatus extends $pb.GeneratedMessage {
  factory LinkStatus({
    LinkState? state,
    $fixnum.Int64? sinceMonoMs,
    $core.String? transport,
    $core.bool? simulated,
    $core.bool? transmitEnabled,
    $core.double? requestsPerSecond,
    $core.String? machineState,
    $core.String? detail,
    $core.double? adapterVoltage,
    $core.String? scenario,
    $core.double? scenarioSeconds,
  }) {
    final result = LinkStatus._();
    if (state != null) result.state = state;
    if (sinceMonoMs != null) result.sinceMonoMs = sinceMonoMs;
    if (transport != null) result.transport = transport;
    if (simulated != null) result.simulated = simulated;
    if (transmitEnabled != null) result.transmitEnabled = transmitEnabled;
    if (requestsPerSecond != null) result.requestsPerSecond = requestsPerSecond;
    if (machineState != null) result.machineState = machineState;
    if (detail != null) result.detail = detail;
    if (adapterVoltage != null) result.adapterVoltage = adapterVoltage;
    if (scenario != null) result.scenario = scenario;
    if (scenarioSeconds != null) result.scenarioSeconds = scenarioSeconds;
    return result;
  }

  LinkStatus._();

  factory LinkStatus.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LinkStatus()..mergeFromBuffer(data, registry);
  factory LinkStatus.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LinkStatus()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LinkStatus',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: LinkStatus.$_createMessage)
    ..aE<LinkState>(1, _omitFieldNames ? '' : 'state',
        enumValues: LinkState.values)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'sinceMonoMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(3, _omitFieldNames ? '' : 'transport')
    ..aOB(4, _omitFieldNames ? '' : 'simulated')
    ..aOB(5, _omitFieldNames ? '' : 'transmitEnabled')
    ..aD(6, _omitFieldNames ? '' : 'requestsPerSecond')
    ..aOS(7, _omitFieldNames ? '' : 'machineState')
    ..aOS(8, _omitFieldNames ? '' : 'detail')
    ..aD(9, _omitFieldNames ? '' : 'adapterVoltage')
    ..aOS(10, _omitFieldNames ? '' : 'scenario')
    ..aD(11, _omitFieldNames ? '' : 'scenarioSeconds')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LinkStatus clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LinkStatus copyWith(void Function(LinkStatus) updates) =>
      super.copyWith((message) => updates(message as LinkStatus)) as LinkStatus;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use LinkStatus() / LinkStatus.new instead')
  static LinkStatus create() => LinkStatus._();
  static $pb.GeneratedMessage $_createMessage() => LinkStatus._();
  @$core.override
  LinkStatus createEmptyInstance() => LinkStatus._();
  @$core.pragma('dart2js:noInline')
  static LinkStatus getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LinkStatus>(LinkStatus.$_createMessage);
  static LinkStatus? _defaultInstance;

  @$pb.TagNumber(1)
  LinkState get state => $_getN(0);
  @$pb.TagNumber(1)
  set state(LinkState value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasState() => $_has(0);
  @$pb.TagNumber(1)
  void clearState() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get sinceMonoMs => $_getI64(1);
  @$pb.TagNumber(2)
  set sinceMonoMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSinceMonoMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearSinceMonoMs() => $_clearField(2);

  /// "simulated", "obdlink", "socketcan".
  @$pb.TagNumber(3)
  $core.String get transport => $_getSZ(2);
  @$pb.TagNumber(3)
  set transport($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTransport() => $_has(2);
  @$pb.TagNumber(3)
  void clearTransport() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get simulated => $_getBF(3);
  @$pb.TagNumber(4)
  set simulated($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSimulated() => $_has(3);
  @$pb.TagNumber(4)
  void clearSimulated() => $_clearField(4);

  /// False = PASSIVE_ONLY (ADR-0007): nothing is transmitted to the vehicle.
  @$pb.TagNumber(5)
  $core.bool get transmitEnabled => $_getBF(4);
  @$pb.TagNumber(5)
  set transmitEnabled($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTransmitEnabled() => $_has(4);
  @$pb.TagNumber(5)
  void clearTransmitEnabled() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.double get requestsPerSecond => $_getN(5);
  @$pb.TagNumber(6)
  set requestsPerSecond($core.double value) => $_setDouble(5, value);
  @$pb.TagNumber(6)
  $core.bool hasRequestsPerSecond() => $_has(5);
  @$pb.TagNumber(6)
  void clearRequestsPerSecond() => $_clearField(6);

  /// Gateway link state machine (diagnostic-recovery.md), e.g. "POLLING".
  @$pb.TagNumber(7)
  $core.String get machineState => $_getSZ(6);
  @$pb.TagNumber(7)
  set machineState($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasMachineState() => $_has(6);
  @$pb.TagNumber(7)
  void clearMachineState() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get detail => $_getSZ(7);
  @$pb.TagNumber(8)
  set detail($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasDetail() => $_has(7);
  @$pb.TagNumber(8)
  void clearDetail() => $_clearField(8);

  /// Adapter supply voltage from ATRV, when the transport has one.
  @$pb.TagNumber(9)
  $core.double get adapterVoltage => $_getN(8);
  @$pb.TagNumber(9)
  set adapterVoltage($core.double value) => $_setDouble(8, value);
  @$pb.TagNumber(9)
  $core.bool hasAdapterVoltage() => $_has(8);
  @$pb.TagNumber(9)
  void clearAdapterVoltage() => $_clearField(9);

  /// Simulated source only: scenario id and clock.
  @$pb.TagNumber(10)
  $core.String get scenario => $_getSZ(9);
  @$pb.TagNumber(10)
  set scenario($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasScenario() => $_has(9);
  @$pb.TagNumber(10)
  void clearScenario() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.double get scenarioSeconds => $_getN(10);
  @$pb.TagNumber(11)
  set scenarioSeconds($core.double value) => $_setDouble(10, value);
  @$pb.TagNumber(11)
  $core.bool hasScenarioSeconds() => $_has(10);
  @$pb.TagNumber(11)
  void clearScenarioSeconds() => $_clearField(11);
}

class Alert extends $pb.GeneratedMessage {
  factory Alert({
    $core.String? id,
    AlertKind? kind,
    AlertLevel? level,
    $fixnum.Int64? sinceMonoMs,
    $core.String? signalId,
    $core.String? ruleId,
    $core.double? threshold,
    $core.bool? above,
  }) {
    final result = Alert._();
    if (id != null) result.id = id;
    if (kind != null) result.kind = kind;
    if (level != null) result.level = level;
    if (sinceMonoMs != null) result.sinceMonoMs = sinceMonoMs;
    if (signalId != null) result.signalId = signalId;
    if (ruleId != null) result.ruleId = ruleId;
    if (threshold != null) result.threshold = threshold;
    if (above != null) result.above = above;
    return result;
  }

  Alert._();

  factory Alert.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Alert()..mergeFromBuffer(data, registry);
  factory Alert.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Alert()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Alert',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: Alert.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aE<AlertKind>(2, _omitFieldNames ? '' : 'kind',
        enumValues: AlertKind.values)
    ..aE<AlertLevel>(3, _omitFieldNames ? '' : 'level',
        enumValues: AlertLevel.values)
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'sinceMonoMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(5, _omitFieldNames ? '' : 'signalId')
    ..aOS(6, _omitFieldNames ? '' : 'ruleId')
    ..aD(7, _omitFieldNames ? '' : 'threshold')
    ..aOB(8, _omitFieldNames ? '' : 'above')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Alert clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Alert copyWith(void Function(Alert) updates) =>
      super.copyWith((message) => updates(message as Alert)) as Alert;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Alert() / Alert.new instead')
  static Alert create() => Alert._();
  static $pb.GeneratedMessage $_createMessage() => Alert._();
  @$core.override
  Alert createEmptyInstance() => Alert._();
  @$core.pragma('dart2js:noInline')
  static Alert getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Alert>(Alert.$_createMessage);
  static Alert? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  AlertKind get kind => $_getN(1);
  @$pb.TagNumber(2)
  set kind(AlertKind value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasKind() => $_has(1);
  @$pb.TagNumber(2)
  void clearKind() => $_clearField(2);

  @$pb.TagNumber(3)
  AlertLevel get level => $_getN(2);
  @$pb.TagNumber(3)
  set level(AlertLevel value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasLevel() => $_has(2);
  @$pb.TagNumber(3)
  void clearLevel() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get sinceMonoMs => $_getI64(3);
  @$pb.TagNumber(4)
  set sinceMonoMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSinceMonoMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearSinceMonoMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get signalId => $_getSZ(4);
  @$pb.TagNumber(5)
  set signalId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSignalId() => $_has(4);
  @$pb.TagNumber(5)
  void clearSignalId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get ruleId => $_getSZ(5);
  @$pb.TagNumber(6)
  set ruleId($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasRuleId() => $_has(5);
  @$pb.TagNumber(6)
  void clearRuleId() => $_clearField(6);

  /// Threshold that was crossed (canonical units) and its direction.
  @$pb.TagNumber(7)
  $core.double get threshold => $_getN(6);
  @$pb.TagNumber(7)
  set threshold($core.double value) => $_setDouble(6, value);
  @$pb.TagNumber(7)
  $core.bool hasThreshold() => $_has(6);
  @$pb.TagNumber(7)
  void clearThreshold() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get above => $_getBF(7);
  @$pb.TagNumber(8)
  set above($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasAbove() => $_has(7);
  @$pb.TagNumber(8)
  void clearAbove() => $_clearField(8);
}

class Snapshot extends $pb.GeneratedMessage {
  factory Snapshot({
    $fixnum.Int64? monoMs,
    $core.Iterable<Sample>? samples,
    LinkStatus? link,
    $core.Iterable<Alert>? alerts,
  }) {
    final result = Snapshot._();
    if (monoMs != null) result.monoMs = monoMs;
    if (samples != null) result.samples.addAll(samples);
    if (link != null) result.link = link;
    if (alerts != null) result.alerts.addAll(alerts);
    return result;
  }

  Snapshot._();

  factory Snapshot.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Snapshot()..mergeFromBuffer(data, registry);
  factory Snapshot.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Snapshot()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Snapshot',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: Snapshot.$_createMessage)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'monoMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..pPM<Sample>(2, _omitFieldNames ? '' : 'samples',
        subBuilder: Sample.$_createMessage)
    ..aOM<LinkStatus>(3, _omitFieldNames ? '' : 'link',
        subBuilder: LinkStatus.$_createMessage)
    ..pPM<Alert>(4, _omitFieldNames ? '' : 'alerts',
        subBuilder: Alert.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Snapshot clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Snapshot copyWith(void Function(Snapshot) updates) =>
      super.copyWith((message) => updates(message as Snapshot)) as Snapshot;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Snapshot() / Snapshot.new instead')
  static Snapshot create() => Snapshot._();
  static $pb.GeneratedMessage $_createMessage() => Snapshot._();
  @$core.override
  Snapshot createEmptyInstance() => Snapshot._();
  @$core.pragma('dart2js:noInline')
  static Snapshot getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Snapshot>(Snapshot.$_createMessage);
  static Snapshot? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get monoMs => $_getI64(0);
  @$pb.TagNumber(1)
  set monoMs($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMonoMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearMonoMs() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<Sample> get samples => $_getList(1);

  @$pb.TagNumber(3)
  LinkStatus get link => $_getN(2);
  @$pb.TagNumber(3)
  set link(LinkStatus value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasLink() => $_has(2);
  @$pb.TagNumber(3)
  void clearLink() => $_clearField(3);
  @$pb.TagNumber(3)
  LinkStatus ensureLink() => $_ensure(2);

  /// Critical first, then oldest first.
  @$pb.TagNumber(4)
  $pb.PbList<Alert> get alerts => $_getList(3);
}

class StreamSnapshotsRequest extends $pb.GeneratedMessage {
  factory StreamSnapshotsRequest({
    $core.int? periodMs,
  }) {
    final result = StreamSnapshotsRequest._();
    if (periodMs != null) result.periodMs = periodMs;
    return result;
  }

  StreamSnapshotsRequest._();

  factory StreamSnapshotsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StreamSnapshotsRequest()..mergeFromBuffer(data, registry);
  factory StreamSnapshotsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StreamSnapshotsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StreamSnapshotsRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: StreamSnapshotsRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'periodMs', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StreamSnapshotsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StreamSnapshotsRequest copyWith(
          void Function(StreamSnapshotsRequest) updates) =>
      super.copyWith((message) => updates(message as StreamSnapshotsRequest))
          as StreamSnapshotsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use StreamSnapshotsRequest() / StreamSnapshotsRequest.new instead')
  static StreamSnapshotsRequest create() => StreamSnapshotsRequest._();
  static $pb.GeneratedMessage $_createMessage() => StreamSnapshotsRequest._();
  @$core.override
  StreamSnapshotsRequest createEmptyInstance() => StreamSnapshotsRequest._();
  @$core.pragma('dart2js:noInline')
  static StreamSnapshotsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StreamSnapshotsRequest>(
          StreamSnapshotsRequest.$_createMessage);
  static StreamSnapshotsRequest? _defaultInstance;

  /// 0 = gateway default (250 ms). Clamped to 100..2000.
  @$pb.TagNumber(1)
  $core.int get periodMs => $_getIZ(0);
  @$pb.TagNumber(1)
  set periodMs($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPeriodMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearPeriodMs() => $_clearField(1);
}

class StreamSnapshotsResponse extends $pb.GeneratedMessage {
  factory StreamSnapshotsResponse({
    Snapshot? snapshot,
  }) {
    final result = StreamSnapshotsResponse._();
    if (snapshot != null) result.snapshot = snapshot;
    return result;
  }

  StreamSnapshotsResponse._();

  factory StreamSnapshotsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StreamSnapshotsResponse()..mergeFromBuffer(data, registry);
  factory StreamSnapshotsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StreamSnapshotsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StreamSnapshotsResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: StreamSnapshotsResponse.$_createMessage)
    ..aOM<Snapshot>(1, _omitFieldNames ? '' : 'snapshot',
        subBuilder: Snapshot.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StreamSnapshotsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StreamSnapshotsResponse copyWith(
          void Function(StreamSnapshotsResponse) updates) =>
      super.copyWith((message) => updates(message as StreamSnapshotsResponse))
          as StreamSnapshotsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use StreamSnapshotsResponse() / StreamSnapshotsResponse.new instead')
  static StreamSnapshotsResponse create() => StreamSnapshotsResponse._();
  static $pb.GeneratedMessage $_createMessage() => StreamSnapshotsResponse._();
  @$core.override
  StreamSnapshotsResponse createEmptyInstance() => StreamSnapshotsResponse._();
  @$core.pragma('dart2js:noInline')
  static StreamSnapshotsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StreamSnapshotsResponse>(
          StreamSnapshotsResponse.$_createMessage);
  static StreamSnapshotsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Snapshot get snapshot => $_getN(0);
  @$pb.TagNumber(1)
  set snapshot(Snapshot value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSnapshot() => $_has(0);
  @$pb.TagNumber(1)
  void clearSnapshot() => $_clearField(1);
  @$pb.TagNumber(1)
  Snapshot ensureSnapshot() => $_ensure(0);
}

class Event extends $pb.GeneratedMessage {
  factory Event({
    $fixnum.Int64? monoMs,
    $fixnum.Int64? wallMs,
    EventSeverity? severity,
    $core.String? message,
  }) {
    final result = Event._();
    if (monoMs != null) result.monoMs = monoMs;
    if (wallMs != null) result.wallMs = wallMs;
    if (severity != null) result.severity = severity;
    if (message != null) result.message = message;
    return result;
  }

  Event._();

  factory Event.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Event()..mergeFromBuffer(data, registry);
  factory Event.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Event()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Event',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: Event.$_createMessage)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'monoMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, _omitFieldNames ? '' : 'wallMs')
    ..aE<EventSeverity>(3, _omitFieldNames ? '' : 'severity',
        enumValues: EventSeverity.values)
    ..aOS(4, _omitFieldNames ? '' : 'message')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Event clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Event copyWith(void Function(Event) updates) =>
      super.copyWith((message) => updates(message as Event)) as Event;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Event() / Event.new instead')
  static Event create() => Event._();
  static $pb.GeneratedMessage $_createMessage() => Event._();
  @$core.override
  Event createEmptyInstance() => Event._();
  @$core.pragma('dart2js:noInline')
  static Event getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Event>(Event.$_createMessage);
  static Event? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get monoMs => $_getI64(0);
  @$pb.TagNumber(1)
  set monoMs($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMonoMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearMonoMs() => $_clearField(1);

  /// Unix epoch milliseconds (wall clock; may jump).
  @$pb.TagNumber(2)
  $fixnum.Int64 get wallMs => $_getI64(1);
  @$pb.TagNumber(2)
  set wallMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasWallMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearWallMs() => $_clearField(2);

  @$pb.TagNumber(3)
  EventSeverity get severity => $_getN(2);
  @$pb.TagNumber(3)
  set severity(EventSeverity value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasSeverity() => $_has(2);
  @$pb.TagNumber(3)
  void clearSeverity() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get message => $_getSZ(3);
  @$pb.TagNumber(4)
  set message($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearMessage() => $_clearField(4);
}

class ListEventsRequest extends $pb.GeneratedMessage {
  factory ListEventsRequest({
    $core.int? limit,
  }) {
    final result = ListEventsRequest._();
    if (limit != null) result.limit = limit;
    return result;
  }

  ListEventsRequest._();

  factory ListEventsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListEventsRequest()..mergeFromBuffer(data, registry);
  factory ListEventsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListEventsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListEventsRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: ListEventsRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'limit', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListEventsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListEventsRequest copyWith(void Function(ListEventsRequest) updates) =>
      super.copyWith((message) => updates(message as ListEventsRequest))
          as ListEventsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListEventsRequest() / ListEventsRequest.new instead')
  static ListEventsRequest create() => ListEventsRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListEventsRequest._();
  @$core.override
  ListEventsRequest createEmptyInstance() => ListEventsRequest._();
  @$core.pragma('dart2js:noInline')
  static ListEventsRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ListEventsRequest>(
          ListEventsRequest.$_createMessage);
  static ListEventsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get limit => $_getIZ(0);
  @$pb.TagNumber(1)
  set limit($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLimit() => $_has(0);
  @$pb.TagNumber(1)
  void clearLimit() => $_clearField(1);
}

class ListEventsResponse extends $pb.GeneratedMessage {
  factory ListEventsResponse({
    $core.Iterable<Event>? events,
    $fixnum.Int64? dropped,
  }) {
    final result = ListEventsResponse._();
    if (events != null) result.events.addAll(events);
    if (dropped != null) result.dropped = dropped;
    return result;
  }

  ListEventsResponse._();

  factory ListEventsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListEventsResponse()..mergeFromBuffer(data, registry);
  factory ListEventsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListEventsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListEventsResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: ListEventsResponse.$_createMessage)
    ..pPM<Event>(1, _omitFieldNames ? '' : 'events',
        subBuilder: Event.$_createMessage)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'dropped', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListEventsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListEventsResponse copyWith(void Function(ListEventsResponse) updates) =>
      super.copyWith((message) => updates(message as ListEventsResponse))
          as ListEventsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListEventsResponse() / ListEventsResponse.new instead')
  static ListEventsResponse create() => ListEventsResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListEventsResponse._();
  @$core.override
  ListEventsResponse createEmptyInstance() => ListEventsResponse._();
  @$core.pragma('dart2js:noInline')
  static ListEventsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListEventsResponse>(
          ListEventsResponse.$_createMessage);
  static ListEventsResponse? _defaultInstance;

  /// Newest first.
  @$pb.TagNumber(1)
  $pb.PbList<Event> get events => $_getList(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get dropped => $_getI64(1);
  @$pb.TagNumber(2)
  set dropped($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDropped() => $_has(1);
  @$pb.TagNumber(2)
  void clearDropped() => $_clearField(2);
}

class SetCalibrationRequest extends $pb.GeneratedMessage {
  factory SetCalibrationRequest({
    $core.String? signalId,
    $core.double? scale,
    $core.double? offset,
  }) {
    final result = SetCalibrationRequest._();
    if (signalId != null) result.signalId = signalId;
    if (scale != null) result.scale = scale;
    if (offset != null) result.offset = offset;
    return result;
  }

  SetCalibrationRequest._();

  factory SetCalibrationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetCalibrationRequest()..mergeFromBuffer(data, registry);
  factory SetCalibrationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetCalibrationRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetCalibrationRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: SetCalibrationRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'signalId')
    ..aD(2, _omitFieldNames ? '' : 'scale')
    ..aD(3, _omitFieldNames ? '' : 'offset')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetCalibrationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetCalibrationRequest copyWith(
          void Function(SetCalibrationRequest) updates) =>
      super.copyWith((message) => updates(message as SetCalibrationRequest))
          as SetCalibrationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SetCalibrationRequest() / SetCalibrationRequest.new instead')
  static SetCalibrationRequest create() => SetCalibrationRequest._();
  static $pb.GeneratedMessage $_createMessage() => SetCalibrationRequest._();
  @$core.override
  SetCalibrationRequest createEmptyInstance() => SetCalibrationRequest._();
  @$core.pragma('dart2js:noInline')
  static SetCalibrationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetCalibrationRequest>(
          SetCalibrationRequest.$_createMessage);
  static SetCalibrationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get signalId => $_getSZ(0);
  @$pb.TagNumber(1)
  set signalId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSignalId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSignalId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get scale => $_getN(1);
  @$pb.TagNumber(2)
  set scale($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasScale() => $_has(1);
  @$pb.TagNumber(2)
  void clearScale() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get offset => $_getN(2);
  @$pb.TagNumber(3)
  set offset($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOffset() => $_has(2);
  @$pb.TagNumber(3)
  void clearOffset() => $_clearField(3);
}

class SetCalibrationResponse extends $pb.GeneratedMessage {
  factory SetCalibrationResponse({
    SignalDefinition? signal,
  }) {
    final result = SetCalibrationResponse._();
    if (signal != null) result.signal = signal;
    return result;
  }

  SetCalibrationResponse._();

  factory SetCalibrationResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetCalibrationResponse()..mergeFromBuffer(data, registry);
  factory SetCalibrationResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetCalibrationResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetCalibrationResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.vehicle.v1'),
      createEmptyInstance: SetCalibrationResponse.$_createMessage)
    ..aOM<SignalDefinition>(1, _omitFieldNames ? '' : 'signal',
        subBuilder: SignalDefinition.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetCalibrationResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetCalibrationResponse copyWith(
          void Function(SetCalibrationResponse) updates) =>
      super.copyWith((message) => updates(message as SetCalibrationResponse))
          as SetCalibrationResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SetCalibrationResponse() / SetCalibrationResponse.new instead')
  static SetCalibrationResponse create() => SetCalibrationResponse._();
  static $pb.GeneratedMessage $_createMessage() => SetCalibrationResponse._();
  @$core.override
  SetCalibrationResponse createEmptyInstance() => SetCalibrationResponse._();
  @$core.pragma('dart2js:noInline')
  static SetCalibrationResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetCalibrationResponse>(
          SetCalibrationResponse.$_createMessage);
  static SetCalibrationResponse? _defaultInstance;

  @$pb.TagNumber(1)
  SignalDefinition get signal => $_getN(0);
  @$pb.TagNumber(1)
  set signal(SignalDefinition value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSignal() => $_has(0);
  @$pb.TagNumber(1)
  void clearSignal() => $_clearField(1);
  @$pb.TagNumber(1)
  SignalDefinition ensureSignal() => $_ensure(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
