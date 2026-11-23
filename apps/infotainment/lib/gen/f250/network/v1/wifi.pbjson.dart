// This is a generated file - do not edit.
//
// Generated from f250/network/v1/wifi.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use connectivityDescriptor instead')
const Connectivity$json = {
  '1': 'Connectivity',
  '2': [
    {'1': 'CONNECTIVITY_UNSPECIFIED', '2': 0},
    {'1': 'CONNECTIVITY_OFFLINE', '2': 1},
    {'1': 'CONNECTIVITY_CONNECTED', '2': 2},
    {'1': 'CONNECTIVITY_ONLINE', '2': 3},
  ],
};

/// Descriptor for `Connectivity`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List connectivityDescriptor = $convert.base64Decode(
    'CgxDb25uZWN0aXZpdHkSHAoYQ09OTkVDVElWSVRZX1VOU1BFQ0lGSUVEEAASGAoUQ09OTkVDVE'
    'lWSVRZX09GRkxJTkUQARIaChZDT05ORUNUSVZJVFlfQ09OTkVDVEVEEAISFwoTQ09OTkVDVElW'
    'SVRZX09OTElORRAD');

@$core.Deprecated('Use securityDescriptor instead')
const Security$json = {
  '1': 'Security',
  '2': [
    {'1': 'SECURITY_UNSPECIFIED', '2': 0},
    {'1': 'SECURITY_OPEN', '2': 1},
    {'1': 'SECURITY_PSK', '2': 2},
    {'1': 'SECURITY_WEP', '2': 3},
    {'1': 'SECURITY_ENTERPRISE', '2': 4},
  ],
};

/// Descriptor for `Security`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List securityDescriptor = $convert.base64Decode(
    'CghTZWN1cml0eRIYChRTRUNVUklUWV9VTlNQRUNJRklFRBAAEhEKDVNFQ1VSSVRZX09QRU4QAR'
    'IQCgxTRUNVUklUWV9QU0sQAhIQCgxTRUNVUklUWV9XRVAQAxIXChNTRUNVUklUWV9FTlRFUlBS'
    'SVNFEAQ=');

@$core.Deprecated('Use networkStateDescriptor instead')
const NetworkState$json = {
  '1': 'NetworkState',
  '2': [
    {'1': 'NETWORK_STATE_UNSPECIFIED', '2': 0},
    {'1': 'NETWORK_STATE_IDLE', '2': 1},
    {'1': 'NETWORK_STATE_CONNECTING', '2': 2},
    {'1': 'NETWORK_STATE_CONNECTED', '2': 3},
    {'1': 'NETWORK_STATE_ONLINE', '2': 4},
    {'1': 'NETWORK_STATE_DISCONNECTING', '2': 5},
    {'1': 'NETWORK_STATE_FAILED', '2': 6},
  ],
};

/// Descriptor for `NetworkState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List networkStateDescriptor = $convert.base64Decode(
    'CgxOZXR3b3JrU3RhdGUSHQoZTkVUV09SS19TVEFURV9VTlNQRUNJRklFRBAAEhYKEk5FVFdPUk'
    'tfU1RBVEVfSURMRRABEhwKGE5FVFdPUktfU1RBVEVfQ09OTkVDVElORxACEhsKF05FVFdPUktf'
    'U1RBVEVfQ09OTkVDVEVEEAMSGAoUTkVUV09SS19TVEFURV9PTkxJTkUQBBIfChtORVRXT1JLX1'
    'NUQVRFX0RJU0NPTk5FQ1RJTkcQBRIYChRORVRXT1JLX1NUQVRFX0ZBSUxFRBAG');

@$core.Deprecated('Use wifiNetworkDescriptor instead')
const WifiNetwork$json = {
  '1': 'WifiNetwork',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'strength', '3': 3, '4': 1, '5': 13, '10': 'strength'},
    {
      '1': 'security',
      '3': 4,
      '4': 1,
      '5': 14,
      '6': '.f250.network.v1.Security',
      '10': 'security'
    },
    {'1': 'saved', '3': 5, '4': 1, '5': 8, '10': 'saved'},
    {
      '1': 'state',
      '3': 6,
      '4': 1,
      '5': 14,
      '6': '.f250.network.v1.NetworkState',
      '10': 'state'
    },
    {'1': 'error', '3': 7, '4': 1, '5': 9, '10': 'error'},
  ],
};

/// Descriptor for `WifiNetwork`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List wifiNetworkDescriptor = $convert.base64Decode(
    'CgtXaWZpTmV0d29yaxIOCgJpZBgBIAEoCVICaWQSEgoEbmFtZRgCIAEoCVIEbmFtZRIaCghzdH'
    'Jlbmd0aBgDIAEoDVIIc3RyZW5ndGgSNQoIc2VjdXJpdHkYBCABKA4yGS5mMjUwLm5ldHdvcmsu'
    'djEuU2VjdXJpdHlSCHNlY3VyaXR5EhQKBXNhdmVkGAUgASgIUgVzYXZlZBIzCgVzdGF0ZRgGIA'
    'EoDjIdLmYyNTAubmV0d29yay52MS5OZXR3b3JrU3RhdGVSBXN0YXRlEhQKBWVycm9yGAcgASgJ'
    'UgVlcnJvcg==');

@$core.Deprecated('Use wifiStatusDescriptor instead')
const WifiStatus$json = {
  '1': 'WifiStatus',
  '2': [
    {'1': 'available', '3': 1, '4': 1, '5': 8, '10': 'available'},
    {'1': 'enabled', '3': 2, '4': 1, '5': 8, '10': 'enabled'},
    {
      '1': 'connectivity',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.f250.network.v1.Connectivity',
      '10': 'connectivity'
    },
    {
      '1': 'networks',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.f250.network.v1.WifiNetwork',
      '10': 'networks'
    },
    {'1': 'detail', '3': 5, '4': 1, '5': 9, '10': 'detail'},
    {'1': 'simulated', '3': 6, '4': 1, '5': 8, '10': 'simulated'},
    {'1': 'address', '3': 7, '4': 1, '5': 9, '10': 'address'},
    {'1': 'scanning', '3': 8, '4': 1, '5': 8, '10': 'scanning'},
  ],
};

/// Descriptor for `WifiStatus`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List wifiStatusDescriptor = $convert.base64Decode(
    'CgpXaWZpU3RhdHVzEhwKCWF2YWlsYWJsZRgBIAEoCFIJYXZhaWxhYmxlEhgKB2VuYWJsZWQYAi'
    'ABKAhSB2VuYWJsZWQSQQoMY29ubmVjdGl2aXR5GAMgASgOMh0uZjI1MC5uZXR3b3JrLnYxLkNv'
    'bm5lY3Rpdml0eVIMY29ubmVjdGl2aXR5EjgKCG5ldHdvcmtzGAQgAygLMhwuZjI1MC5uZXR3b3'
    'JrLnYxLldpZmlOZXR3b3JrUghuZXR3b3JrcxIWCgZkZXRhaWwYBSABKAlSBmRldGFpbBIcCglz'
    'aW11bGF0ZWQYBiABKAhSCXNpbXVsYXRlZBIYCgdhZGRyZXNzGAcgASgJUgdhZGRyZXNzEhoKCH'
    'NjYW5uaW5nGAggASgIUghzY2FubmluZw==');

@$core.Deprecated('Use watchWifiRequestDescriptor instead')
const WatchWifiRequest$json = {
  '1': 'WatchWifiRequest',
};

/// Descriptor for `WatchWifiRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchWifiRequestDescriptor =
    $convert.base64Decode('ChBXYXRjaFdpZmlSZXF1ZXN0');

@$core.Deprecated('Use watchWifiResponseDescriptor instead')
const WatchWifiResponse$json = {
  '1': 'WatchWifiResponse',
  '2': [
    {
      '1': 'status',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.network.v1.WifiStatus',
      '10': 'status'
    },
  ],
};

/// Descriptor for `WatchWifiResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchWifiResponseDescriptor = $convert.base64Decode(
    'ChFXYXRjaFdpZmlSZXNwb25zZRIzCgZzdGF0dXMYASABKAsyGy5mMjUwLm5ldHdvcmsudjEuV2'
    'lmaVN0YXR1c1IGc3RhdHVz');

@$core.Deprecated('Use setWifiEnabledRequestDescriptor instead')
const SetWifiEnabledRequest$json = {
  '1': 'SetWifiEnabledRequest',
  '2': [
    {'1': 'enabled', '3': 1, '4': 1, '5': 8, '10': 'enabled'},
  ],
};

/// Descriptor for `SetWifiEnabledRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setWifiEnabledRequestDescriptor =
    $convert.base64Decode(
        'ChVTZXRXaWZpRW5hYmxlZFJlcXVlc3QSGAoHZW5hYmxlZBgBIAEoCFIHZW5hYmxlZA==');

@$core.Deprecated('Use setWifiEnabledResponseDescriptor instead')
const SetWifiEnabledResponse$json = {
  '1': 'SetWifiEnabledResponse',
};

/// Descriptor for `SetWifiEnabledResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setWifiEnabledResponseDescriptor =
    $convert.base64Decode('ChZTZXRXaWZpRW5hYmxlZFJlc3BvbnNl');

@$core.Deprecated('Use scanWifiRequestDescriptor instead')
const ScanWifiRequest$json = {
  '1': 'ScanWifiRequest',
};

/// Descriptor for `ScanWifiRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List scanWifiRequestDescriptor =
    $convert.base64Decode('Cg9TY2FuV2lmaVJlcXVlc3Q=');

@$core.Deprecated('Use scanWifiResponseDescriptor instead')
const ScanWifiResponse$json = {
  '1': 'ScanWifiResponse',
};

/// Descriptor for `ScanWifiResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List scanWifiResponseDescriptor =
    $convert.base64Decode('ChBTY2FuV2lmaVJlc3BvbnNl');

@$core.Deprecated('Use connectWifiRequestDescriptor instead')
const ConnectWifiRequest$json = {
  '1': 'ConnectWifiRequest',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'passphrase', '3': 2, '4': 1, '5': 9, '10': 'passphrase'},
  ],
};

/// Descriptor for `ConnectWifiRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List connectWifiRequestDescriptor = $convert.base64Decode(
    'ChJDb25uZWN0V2lmaVJlcXVlc3QSDgoCaWQYASABKAlSAmlkEh4KCnBhc3NwaHJhc2UYAiABKA'
    'lSCnBhc3NwaHJhc2U=');

@$core.Deprecated('Use connectWifiResponseDescriptor instead')
const ConnectWifiResponse$json = {
  '1': 'ConnectWifiResponse',
  '2': [
    {'1': 'connected', '3': 1, '4': 1, '5': 8, '10': 'connected'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
  ],
};

/// Descriptor for `ConnectWifiResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List connectWifiResponseDescriptor = $convert.base64Decode(
    'ChNDb25uZWN0V2lmaVJlc3BvbnNlEhwKCWNvbm5lY3RlZBgBIAEoCFIJY29ubmVjdGVkEhYKBm'
    'RldGFpbBgCIAEoCVIGZGV0YWls');

@$core.Deprecated('Use disconnectWifiRequestDescriptor instead')
const DisconnectWifiRequest$json = {
  '1': 'DisconnectWifiRequest',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
  ],
};

/// Descriptor for `DisconnectWifiRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List disconnectWifiRequestDescriptor = $convert
    .base64Decode('ChVEaXNjb25uZWN0V2lmaVJlcXVlc3QSDgoCaWQYASABKAlSAmlk');

@$core.Deprecated('Use disconnectWifiResponseDescriptor instead')
const DisconnectWifiResponse$json = {
  '1': 'DisconnectWifiResponse',
};

/// Descriptor for `DisconnectWifiResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List disconnectWifiResponseDescriptor =
    $convert.base64Decode('ChZEaXNjb25uZWN0V2lmaVJlc3BvbnNl');

@$core.Deprecated('Use forgetWifiRequestDescriptor instead')
const ForgetWifiRequest$json = {
  '1': 'ForgetWifiRequest',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
  ],
};

/// Descriptor for `ForgetWifiRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List forgetWifiRequestDescriptor =
    $convert.base64Decode('ChFGb3JnZXRXaWZpUmVxdWVzdBIOCgJpZBgBIAEoCVICaWQ=');

@$core.Deprecated('Use forgetWifiResponseDescriptor instead')
const ForgetWifiResponse$json = {
  '1': 'ForgetWifiResponse',
};

/// Descriptor for `ForgetWifiResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List forgetWifiResponseDescriptor =
    $convert.base64Decode('ChJGb3JnZXRXaWZpUmVzcG9uc2U=');
