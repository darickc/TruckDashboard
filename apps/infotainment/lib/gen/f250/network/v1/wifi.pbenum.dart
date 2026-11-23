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

/// How far the Pi's network reaches.
class Connectivity extends $pb.ProtobufEnum {
  static const Connectivity CONNECTIVITY_UNSPECIFIED =
      Connectivity._(0, _omitEnumNames ? '' : 'CONNECTIVITY_UNSPECIFIED');

  /// No network.
  static const Connectivity CONNECTIVITY_OFFLINE =
      Connectivity._(1, _omitEnumNames ? '' : 'CONNECTIVITY_OFFLINE');

  /// On a network (connman's "ready"). The internet may or may not be
  /// there: connman's own check may be off, so this is not "offline".
  static const Connectivity CONNECTIVITY_CONNECTED =
      Connectivity._(2, _omitEnumNames ? '' : 'CONNECTIVITY_CONNECTED');

  /// connman's check reached the internet ("online").
  static const Connectivity CONNECTIVITY_ONLINE =
      Connectivity._(3, _omitEnumNames ? '' : 'CONNECTIVITY_ONLINE');

  static const $core.List<Connectivity> values = <Connectivity>[
    CONNECTIVITY_UNSPECIFIED,
    CONNECTIVITY_OFFLINE,
    CONNECTIVITY_CONNECTED,
    CONNECTIVITY_ONLINE,
  ];

  static final $core.List<Connectivity?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static Connectivity? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Connectivity._(super.value, super.name);
}

class Security extends $pb.ProtobufEnum {
  static const Security SECURITY_UNSPECIFIED =
      Security._(0, _omitEnumNames ? '' : 'SECURITY_UNSPECIFIED');
  static const Security SECURITY_OPEN =
      Security._(1, _omitEnumNames ? '' : 'SECURITY_OPEN');

  /// WPA/WPA2/WPA3 personal: a passphrase.
  static const Security SECURITY_PSK =
      Security._(2, _omitEnumNames ? '' : 'SECURITY_PSK');
  static const Security SECURITY_WEP =
      Security._(3, _omitEnumNames ? '' : 'SECURITY_WEP');

  /// 802.1X: not joinable from the dashboard.
  static const Security SECURITY_ENTERPRISE =
      Security._(4, _omitEnumNames ? '' : 'SECURITY_ENTERPRISE');

  static const $core.List<Security> values = <Security>[
    SECURITY_UNSPECIFIED,
    SECURITY_OPEN,
    SECURITY_PSK,
    SECURITY_WEP,
    SECURITY_ENTERPRISE,
  ];

  static final $core.List<Security?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static Security? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Security._(super.value, super.name);
}

class NetworkState extends $pb.ProtobufEnum {
  static const NetworkState NETWORK_STATE_UNSPECIFIED =
      NetworkState._(0, _omitEnumNames ? '' : 'NETWORK_STATE_UNSPECIFIED');
  static const NetworkState NETWORK_STATE_IDLE =
      NetworkState._(1, _omitEnumNames ? '' : 'NETWORK_STATE_IDLE');

  /// Associating or getting an address.
  static const NetworkState NETWORK_STATE_CONNECTING =
      NetworkState._(2, _omitEnumNames ? '' : 'NETWORK_STATE_CONNECTING');
  static const NetworkState NETWORK_STATE_CONNECTED =
      NetworkState._(3, _omitEnumNames ? '' : 'NETWORK_STATE_CONNECTED');
  static const NetworkState NETWORK_STATE_ONLINE =
      NetworkState._(4, _omitEnumNames ? '' : 'NETWORK_STATE_ONLINE');
  static const NetworkState NETWORK_STATE_DISCONNECTING =
      NetworkState._(5, _omitEnumNames ? '' : 'NETWORK_STATE_DISCONNECTING');

  /// The last attempt failed; `error` says why.
  static const NetworkState NETWORK_STATE_FAILED =
      NetworkState._(6, _omitEnumNames ? '' : 'NETWORK_STATE_FAILED');

  static const $core.List<NetworkState> values = <NetworkState>[
    NETWORK_STATE_UNSPECIFIED,
    NETWORK_STATE_IDLE,
    NETWORK_STATE_CONNECTING,
    NETWORK_STATE_CONNECTED,
    NETWORK_STATE_ONLINE,
    NETWORK_STATE_DISCONNECTING,
    NETWORK_STATE_FAILED,
  ];

  static final $core.List<NetworkState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static NetworkState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const NetworkState._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
