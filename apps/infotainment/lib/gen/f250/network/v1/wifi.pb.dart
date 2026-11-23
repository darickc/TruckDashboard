// This is a generated file - do not edit.
//
// Generated from f250/network/v1/wifi.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'wifi.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'wifi.pbenum.dart';

class WifiNetwork extends $pb.GeneratedMessage {
  factory WifiNetwork({
    $core.String? id,
    $core.String? name,
    $core.int? strength,
    Security? security,
    $core.bool? saved,
    NetworkState? state,
    $core.String? error,
  }) {
    final result = WifiNetwork._();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (strength != null) result.strength = strength;
    if (security != null) result.security = security;
    if (saved != null) result.saved = saved;
    if (state != null) result.state = state;
    if (error != null) result.error = error;
    return result;
  }

  WifiNetwork._();

  factory WifiNetwork.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WifiNetwork()..mergeFromBuffer(data, registry);
  factory WifiNetwork.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WifiNetwork()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WifiNetwork',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.network.v1'),
      createEmptyInstance: WifiNetwork.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aI(3, _omitFieldNames ? '' : 'strength', fieldType: $pb.PbFieldType.OU3)
    ..aE<Security>(4, _omitFieldNames ? '' : 'security',
        enumValues: Security.values)
    ..aOB(5, _omitFieldNames ? '' : 'saved')
    ..aE<NetworkState>(6, _omitFieldNames ? '' : 'state',
        enumValues: NetworkState.values)
    ..aOS(7, _omitFieldNames ? '' : 'error')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WifiNetwork clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WifiNetwork copyWith(void Function(WifiNetwork) updates) =>
      super.copyWith((message) => updates(message as WifiNetwork))
          as WifiNetwork;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WifiNetwork() / WifiNetwork.new instead')
  static WifiNetwork create() => WifiNetwork._();
  static $pb.GeneratedMessage $_createMessage() => WifiNetwork._();
  @$core.override
  WifiNetwork createEmptyInstance() => WifiNetwork._();
  @$core.pragma('dart2js:noInline')
  static WifiNetwork getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WifiNetwork>(
          WifiNetwork.$_createMessage);
  static WifiNetwork? _defaultInstance;

  /// connman's service id ("wifi_…_managed_psk"): what the calls take.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// The SSID. Hidden networks aren't listed.
  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  /// 0–100.
  @$pb.TagNumber(3)
  $core.int get strength => $_getIZ(2);
  @$pb.TagNumber(3)
  set strength($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStrength() => $_has(2);
  @$pb.TagNumber(3)
  void clearStrength() => $_clearField(3);

  @$pb.TagNumber(4)
  Security get security => $_getN(3);
  @$pb.TagNumber(4)
  set security(Security value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasSecurity() => $_has(3);
  @$pb.TagNumber(4)
  void clearSecurity() => $_clearField(4);

  /// connman remembers it (and its passphrase), and joins it by itself.
  @$pb.TagNumber(5)
  $core.bool get saved => $_getBF(4);
  @$pb.TagNumber(5)
  set saved($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSaved() => $_has(4);
  @$pb.TagNumber(5)
  void clearSaved() => $_clearField(5);

  @$pb.TagNumber(6)
  NetworkState get state => $_getN(5);
  @$pb.TagNumber(6)
  set state(NetworkState value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasState() => $_has(5);
  @$pb.TagNumber(6)
  void clearState() => $_clearField(6);

  /// connman's error after a failure ("invalid-key", "connect-failed").
  @$pb.TagNumber(7)
  $core.String get error => $_getSZ(6);
  @$pb.TagNumber(7)
  set error($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasError() => $_has(6);
  @$pb.TagNumber(7)
  void clearError() => $_clearField(7);
}

class WifiStatus extends $pb.GeneratedMessage {
  factory WifiStatus({
    $core.bool? available,
    $core.bool? enabled,
    Connectivity? connectivity,
    $core.Iterable<WifiNetwork>? networks,
    $core.String? detail,
    $core.bool? simulated,
    $core.String? address,
    $core.bool? scanning,
  }) {
    final result = WifiStatus._();
    if (available != null) result.available = available;
    if (enabled != null) result.enabled = enabled;
    if (connectivity != null) result.connectivity = connectivity;
    if (networks != null) result.networks.addAll(networks);
    if (detail != null) result.detail = detail;
    if (simulated != null) result.simulated = simulated;
    if (address != null) result.address = address;
    if (scanning != null) result.scanning = scanning;
    return result;
  }

  WifiStatus._();

  factory WifiStatus.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WifiStatus()..mergeFromBuffer(data, registry);
  factory WifiStatus.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WifiStatus()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WifiStatus',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.network.v1'),
      createEmptyInstance: WifiStatus.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'available')
    ..aOB(2, _omitFieldNames ? '' : 'enabled')
    ..aE<Connectivity>(3, _omitFieldNames ? '' : 'connectivity',
        enumValues: Connectivity.values)
    ..pPM<WifiNetwork>(4, _omitFieldNames ? '' : 'networks',
        subBuilder: WifiNetwork.$_createMessage)
    ..aOS(5, _omitFieldNames ? '' : 'detail')
    ..aOB(6, _omitFieldNames ? '' : 'simulated')
    ..aOS(7, _omitFieldNames ? '' : 'address')
    ..aOB(8, _omitFieldNames ? '' : 'scanning')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WifiStatus clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WifiStatus copyWith(void Function(WifiStatus) updates) =>
      super.copyWith((message) => updates(message as WifiStatus)) as WifiStatus;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WifiStatus() / WifiStatus.new instead')
  static WifiStatus create() => WifiStatus._();
  static $pb.GeneratedMessage $_createMessage() => WifiStatus._();
  @$core.override
  WifiStatus createEmptyInstance() => WifiStatus._();
  @$core.pragma('dart2js:noInline')
  static WifiStatus getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WifiStatus>(WifiStatus.$_createMessage);
  static WifiStatus? _defaultInstance;

  /// The service reaches connman and there is a Wi-Fi device. `detail` says
  /// why not.
  @$pb.TagNumber(1)
  $core.bool get available => $_getBF(0);
  @$pb.TagNumber(1)
  set available($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAvailable() => $_has(0);
  @$pb.TagNumber(1)
  void clearAvailable() => $_clearField(1);

  /// The radio is on.
  @$pb.TagNumber(2)
  $core.bool get enabled => $_getBF(1);
  @$pb.TagNumber(2)
  set enabled($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEnabled() => $_has(1);
  @$pb.TagNumber(2)
  void clearEnabled() => $_clearField(2);

  @$pb.TagNumber(3)
  Connectivity get connectivity => $_getN(2);
  @$pb.TagNumber(3)
  set connectivity(Connectivity value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasConnectivity() => $_has(2);
  @$pb.TagNumber(3)
  void clearConnectivity() => $_clearField(3);

  /// The connected network first, then saved ones, then by strength.
  @$pb.TagNumber(4)
  $pb.PbList<WifiNetwork> get networks => $_getList(3);

  @$pb.TagNumber(5)
  $core.String get detail => $_getSZ(4);
  @$pb.TagNumber(5)
  set detail($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDetail() => $_has(4);
  @$pb.TagNumber(5)
  void clearDetail() => $_clearField(5);

  /// Made-up networks (--simulate): the screen says so.
  @$pb.TagNumber(6)
  $core.bool get simulated => $_getBF(5);
  @$pb.TagNumber(6)
  set simulated($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSimulated() => $_has(5);
  @$pb.TagNumber(6)
  void clearSimulated() => $_clearField(6);

  /// The connected network's IPv4 address, if any.
  @$pb.TagNumber(7)
  $core.String get address => $_getSZ(6);
  @$pb.TagNumber(7)
  set address($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasAddress() => $_has(6);
  @$pb.TagNumber(7)
  void clearAddress() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get scanning => $_getBF(7);
  @$pb.TagNumber(8)
  set scanning($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasScanning() => $_has(7);
  @$pb.TagNumber(8)
  void clearScanning() => $_clearField(8);
}

class WatchWifiRequest extends $pb.GeneratedMessage {
  factory WatchWifiRequest() => WatchWifiRequest._();

  WatchWifiRequest._();

  factory WatchWifiRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchWifiRequest()..mergeFromBuffer(data, registry);
  factory WatchWifiRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchWifiRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchWifiRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.network.v1'),
      createEmptyInstance: WatchWifiRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchWifiRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchWifiRequest copyWith(void Function(WatchWifiRequest) updates) =>
      super.copyWith((message) => updates(message as WatchWifiRequest))
          as WatchWifiRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WatchWifiRequest() / WatchWifiRequest.new instead')
  static WatchWifiRequest create() => WatchWifiRequest._();
  static $pb.GeneratedMessage $_createMessage() => WatchWifiRequest._();
  @$core.override
  WatchWifiRequest createEmptyInstance() => WatchWifiRequest._();
  @$core.pragma('dart2js:noInline')
  static WatchWifiRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WatchWifiRequest>(
          WatchWifiRequest.$_createMessage);
  static WatchWifiRequest? _defaultInstance;
}

class WatchWifiResponse extends $pb.GeneratedMessage {
  factory WatchWifiResponse({
    WifiStatus? status,
  }) {
    final result = WatchWifiResponse._();
    if (status != null) result.status = status;
    return result;
  }

  WatchWifiResponse._();

  factory WatchWifiResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchWifiResponse()..mergeFromBuffer(data, registry);
  factory WatchWifiResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchWifiResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchWifiResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.network.v1'),
      createEmptyInstance: WatchWifiResponse.$_createMessage)
    ..aOM<WifiStatus>(1, _omitFieldNames ? '' : 'status',
        subBuilder: WifiStatus.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchWifiResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchWifiResponse copyWith(void Function(WatchWifiResponse) updates) =>
      super.copyWith((message) => updates(message as WatchWifiResponse))
          as WatchWifiResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WatchWifiResponse() / WatchWifiResponse.new instead')
  static WatchWifiResponse create() => WatchWifiResponse._();
  static $pb.GeneratedMessage $_createMessage() => WatchWifiResponse._();
  @$core.override
  WatchWifiResponse createEmptyInstance() => WatchWifiResponse._();
  @$core.pragma('dart2js:noInline')
  static WatchWifiResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WatchWifiResponse>(
          WatchWifiResponse.$_createMessage);
  static WatchWifiResponse? _defaultInstance;

  @$pb.TagNumber(1)
  WifiStatus get status => $_getN(0);
  @$pb.TagNumber(1)
  set status(WifiStatus value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasStatus() => $_has(0);
  @$pb.TagNumber(1)
  void clearStatus() => $_clearField(1);
  @$pb.TagNumber(1)
  WifiStatus ensureStatus() => $_ensure(0);
}

class SetWifiEnabledRequest extends $pb.GeneratedMessage {
  factory SetWifiEnabledRequest({
    $core.bool? enabled,
  }) {
    final result = SetWifiEnabledRequest._();
    if (enabled != null) result.enabled = enabled;
    return result;
  }

  SetWifiEnabledRequest._();

  factory SetWifiEnabledRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetWifiEnabledRequest()..mergeFromBuffer(data, registry);
  factory SetWifiEnabledRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetWifiEnabledRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetWifiEnabledRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.network.v1'),
      createEmptyInstance: SetWifiEnabledRequest.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'enabled')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetWifiEnabledRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetWifiEnabledRequest copyWith(
          void Function(SetWifiEnabledRequest) updates) =>
      super.copyWith((message) => updates(message as SetWifiEnabledRequest))
          as SetWifiEnabledRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SetWifiEnabledRequest() / SetWifiEnabledRequest.new instead')
  static SetWifiEnabledRequest create() => SetWifiEnabledRequest._();
  static $pb.GeneratedMessage $_createMessage() => SetWifiEnabledRequest._();
  @$core.override
  SetWifiEnabledRequest createEmptyInstance() => SetWifiEnabledRequest._();
  @$core.pragma('dart2js:noInline')
  static SetWifiEnabledRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetWifiEnabledRequest>(
          SetWifiEnabledRequest.$_createMessage);
  static SetWifiEnabledRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get enabled => $_getBF(0);
  @$pb.TagNumber(1)
  set enabled($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEnabled() => $_has(0);
  @$pb.TagNumber(1)
  void clearEnabled() => $_clearField(1);
}

class SetWifiEnabledResponse extends $pb.GeneratedMessage {
  factory SetWifiEnabledResponse() => SetWifiEnabledResponse._();

  SetWifiEnabledResponse._();

  factory SetWifiEnabledResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetWifiEnabledResponse()..mergeFromBuffer(data, registry);
  factory SetWifiEnabledResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetWifiEnabledResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetWifiEnabledResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.network.v1'),
      createEmptyInstance: SetWifiEnabledResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetWifiEnabledResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetWifiEnabledResponse copyWith(
          void Function(SetWifiEnabledResponse) updates) =>
      super.copyWith((message) => updates(message as SetWifiEnabledResponse))
          as SetWifiEnabledResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SetWifiEnabledResponse() / SetWifiEnabledResponse.new instead')
  static SetWifiEnabledResponse create() => SetWifiEnabledResponse._();
  static $pb.GeneratedMessage $_createMessage() => SetWifiEnabledResponse._();
  @$core.override
  SetWifiEnabledResponse createEmptyInstance() => SetWifiEnabledResponse._();
  @$core.pragma('dart2js:noInline')
  static SetWifiEnabledResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetWifiEnabledResponse>(
          SetWifiEnabledResponse.$_createMessage);
  static SetWifiEnabledResponse? _defaultInstance;
}

class ScanWifiRequest extends $pb.GeneratedMessage {
  factory ScanWifiRequest() => ScanWifiRequest._();

  ScanWifiRequest._();

  factory ScanWifiRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ScanWifiRequest()..mergeFromBuffer(data, registry);
  factory ScanWifiRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ScanWifiRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ScanWifiRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.network.v1'),
      createEmptyInstance: ScanWifiRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ScanWifiRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ScanWifiRequest copyWith(void Function(ScanWifiRequest) updates) =>
      super.copyWith((message) => updates(message as ScanWifiRequest))
          as ScanWifiRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ScanWifiRequest() / ScanWifiRequest.new instead')
  static ScanWifiRequest create() => ScanWifiRequest._();
  static $pb.GeneratedMessage $_createMessage() => ScanWifiRequest._();
  @$core.override
  ScanWifiRequest createEmptyInstance() => ScanWifiRequest._();
  @$core.pragma('dart2js:noInline')
  static ScanWifiRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ScanWifiRequest>(
          ScanWifiRequest.$_createMessage);
  static ScanWifiRequest? _defaultInstance;
}

class ScanWifiResponse extends $pb.GeneratedMessage {
  factory ScanWifiResponse() => ScanWifiResponse._();

  ScanWifiResponse._();

  factory ScanWifiResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ScanWifiResponse()..mergeFromBuffer(data, registry);
  factory ScanWifiResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ScanWifiResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ScanWifiResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.network.v1'),
      createEmptyInstance: ScanWifiResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ScanWifiResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ScanWifiResponse copyWith(void Function(ScanWifiResponse) updates) =>
      super.copyWith((message) => updates(message as ScanWifiResponse))
          as ScanWifiResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ScanWifiResponse() / ScanWifiResponse.new instead')
  static ScanWifiResponse create() => ScanWifiResponse._();
  static $pb.GeneratedMessage $_createMessage() => ScanWifiResponse._();
  @$core.override
  ScanWifiResponse createEmptyInstance() => ScanWifiResponse._();
  @$core.pragma('dart2js:noInline')
  static ScanWifiResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ScanWifiResponse>(
          ScanWifiResponse.$_createMessage);
  static ScanWifiResponse? _defaultInstance;
}

class ConnectWifiRequest extends $pb.GeneratedMessage {
  factory ConnectWifiRequest({
    $core.String? id,
    $core.String? passphrase,
  }) {
    final result = ConnectWifiRequest._();
    if (id != null) result.id = id;
    if (passphrase != null) result.passphrase = passphrase;
    return result;
  }

  ConnectWifiRequest._();

  factory ConnectWifiRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ConnectWifiRequest()..mergeFromBuffer(data, registry);
  factory ConnectWifiRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ConnectWifiRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectWifiRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.network.v1'),
      createEmptyInstance: ConnectWifiRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'passphrase')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectWifiRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectWifiRequest copyWith(void Function(ConnectWifiRequest) updates) =>
      super.copyWith((message) => updates(message as ConnectWifiRequest))
          as ConnectWifiRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ConnectWifiRequest() / ConnectWifiRequest.new instead')
  static ConnectWifiRequest create() => ConnectWifiRequest._();
  static $pb.GeneratedMessage $_createMessage() => ConnectWifiRequest._();
  @$core.override
  ConnectWifiRequest createEmptyInstance() => ConnectWifiRequest._();
  @$core.pragma('dart2js:noInline')
  static ConnectWifiRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectWifiRequest>(
          ConnectWifiRequest.$_createMessage);
  static ConnectWifiRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get passphrase => $_getSZ(1);
  @$pb.TagNumber(2)
  set passphrase($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPassphrase() => $_has(1);
  @$pb.TagNumber(2)
  void clearPassphrase() => $_clearField(2);
}

/// The outcome of one attempt. A failure is an answer, not an RPC error:
/// `detail` says what to tell the driver ("Wrong passphrase").
class ConnectWifiResponse extends $pb.GeneratedMessage {
  factory ConnectWifiResponse({
    $core.bool? connected,
    $core.String? detail,
  }) {
    final result = ConnectWifiResponse._();
    if (connected != null) result.connected = connected;
    if (detail != null) result.detail = detail;
    return result;
  }

  ConnectWifiResponse._();

  factory ConnectWifiResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ConnectWifiResponse()..mergeFromBuffer(data, registry);
  factory ConnectWifiResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ConnectWifiResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectWifiResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.network.v1'),
      createEmptyInstance: ConnectWifiResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'connected')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectWifiResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectWifiResponse copyWith(void Function(ConnectWifiResponse) updates) =>
      super.copyWith((message) => updates(message as ConnectWifiResponse))
          as ConnectWifiResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ConnectWifiResponse() / ConnectWifiResponse.new instead')
  static ConnectWifiResponse create() => ConnectWifiResponse._();
  static $pb.GeneratedMessage $_createMessage() => ConnectWifiResponse._();
  @$core.override
  ConnectWifiResponse createEmptyInstance() => ConnectWifiResponse._();
  @$core.pragma('dart2js:noInline')
  static ConnectWifiResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectWifiResponse>(
          ConnectWifiResponse.$_createMessage);
  static ConnectWifiResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get connected => $_getBF(0);
  @$pb.TagNumber(1)
  set connected($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConnected() => $_has(0);
  @$pb.TagNumber(1)
  void clearConnected() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);
}

class DisconnectWifiRequest extends $pb.GeneratedMessage {
  factory DisconnectWifiRequest({
    $core.String? id,
  }) {
    final result = DisconnectWifiRequest._();
    if (id != null) result.id = id;
    return result;
  }

  DisconnectWifiRequest._();

  factory DisconnectWifiRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DisconnectWifiRequest()..mergeFromBuffer(data, registry);
  factory DisconnectWifiRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DisconnectWifiRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DisconnectWifiRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.network.v1'),
      createEmptyInstance: DisconnectWifiRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DisconnectWifiRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DisconnectWifiRequest copyWith(
          void Function(DisconnectWifiRequest) updates) =>
      super.copyWith((message) => updates(message as DisconnectWifiRequest))
          as DisconnectWifiRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DisconnectWifiRequest() / DisconnectWifiRequest.new instead')
  static DisconnectWifiRequest create() => DisconnectWifiRequest._();
  static $pb.GeneratedMessage $_createMessage() => DisconnectWifiRequest._();
  @$core.override
  DisconnectWifiRequest createEmptyInstance() => DisconnectWifiRequest._();
  @$core.pragma('dart2js:noInline')
  static DisconnectWifiRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DisconnectWifiRequest>(
          DisconnectWifiRequest.$_createMessage);
  static DisconnectWifiRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

class DisconnectWifiResponse extends $pb.GeneratedMessage {
  factory DisconnectWifiResponse() => DisconnectWifiResponse._();

  DisconnectWifiResponse._();

  factory DisconnectWifiResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DisconnectWifiResponse()..mergeFromBuffer(data, registry);
  factory DisconnectWifiResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DisconnectWifiResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DisconnectWifiResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.network.v1'),
      createEmptyInstance: DisconnectWifiResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DisconnectWifiResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DisconnectWifiResponse copyWith(
          void Function(DisconnectWifiResponse) updates) =>
      super.copyWith((message) => updates(message as DisconnectWifiResponse))
          as DisconnectWifiResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DisconnectWifiResponse() / DisconnectWifiResponse.new instead')
  static DisconnectWifiResponse create() => DisconnectWifiResponse._();
  static $pb.GeneratedMessage $_createMessage() => DisconnectWifiResponse._();
  @$core.override
  DisconnectWifiResponse createEmptyInstance() => DisconnectWifiResponse._();
  @$core.pragma('dart2js:noInline')
  static DisconnectWifiResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DisconnectWifiResponse>(
          DisconnectWifiResponse.$_createMessage);
  static DisconnectWifiResponse? _defaultInstance;
}

class ForgetWifiRequest extends $pb.GeneratedMessage {
  factory ForgetWifiRequest({
    $core.String? id,
  }) {
    final result = ForgetWifiRequest._();
    if (id != null) result.id = id;
    return result;
  }

  ForgetWifiRequest._();

  factory ForgetWifiRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ForgetWifiRequest()..mergeFromBuffer(data, registry);
  factory ForgetWifiRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ForgetWifiRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ForgetWifiRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.network.v1'),
      createEmptyInstance: ForgetWifiRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ForgetWifiRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ForgetWifiRequest copyWith(void Function(ForgetWifiRequest) updates) =>
      super.copyWith((message) => updates(message as ForgetWifiRequest))
          as ForgetWifiRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ForgetWifiRequest() / ForgetWifiRequest.new instead')
  static ForgetWifiRequest create() => ForgetWifiRequest._();
  static $pb.GeneratedMessage $_createMessage() => ForgetWifiRequest._();
  @$core.override
  ForgetWifiRequest createEmptyInstance() => ForgetWifiRequest._();
  @$core.pragma('dart2js:noInline')
  static ForgetWifiRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ForgetWifiRequest>(
          ForgetWifiRequest.$_createMessage);
  static ForgetWifiRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

class ForgetWifiResponse extends $pb.GeneratedMessage {
  factory ForgetWifiResponse() => ForgetWifiResponse._();

  ForgetWifiResponse._();

  factory ForgetWifiResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ForgetWifiResponse()..mergeFromBuffer(data, registry);
  factory ForgetWifiResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ForgetWifiResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ForgetWifiResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'f250.network.v1'),
      createEmptyInstance: ForgetWifiResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ForgetWifiResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ForgetWifiResponse copyWith(void Function(ForgetWifiResponse) updates) =>
      super.copyWith((message) => updates(message as ForgetWifiResponse))
          as ForgetWifiResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ForgetWifiResponse() / ForgetWifiResponse.new instead')
  static ForgetWifiResponse create() => ForgetWifiResponse._();
  static $pb.GeneratedMessage $_createMessage() => ForgetWifiResponse._();
  @$core.override
  ForgetWifiResponse createEmptyInstance() => ForgetWifiResponse._();
  @$core.pragma('dart2js:noInline')
  static ForgetWifiResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ForgetWifiResponse>(
          ForgetWifiResponse.$_createMessage);
  static ForgetWifiResponse? _defaultInstance;
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
