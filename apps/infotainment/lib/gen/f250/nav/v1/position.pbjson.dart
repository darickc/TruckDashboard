// This is a generated file - do not edit.
//
// Generated from f250/nav/v1/position.proto.

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

@$core.Deprecated('Use fixStatusDescriptor instead')
const FixStatus$json = {
  '1': 'FixStatus',
  '2': [
    {'1': 'FIX_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'FIX_STATUS_UNAVAILABLE', '2': 1},
    {'1': 'FIX_STATUS_NO_RECEIVER', '2': 2},
    {'1': 'FIX_STATUS_RECEIVER_SILENT', '2': 3},
    {'1': 'FIX_STATUS_NO_FIX', '2': 4},
    {'1': 'FIX_STATUS_FIX_2D', '2': 5},
    {'1': 'FIX_STATUS_FIX_3D', '2': 6},
  ],
};

/// Descriptor for `FixStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List fixStatusDescriptor = $convert.base64Decode(
    'CglGaXhTdGF0dXMSGgoWRklYX1NUQVRVU19VTlNQRUNJRklFRBAAEhoKFkZJWF9TVEFUVVNfVU'
    '5BVkFJTEFCTEUQARIaChZGSVhfU1RBVFVTX05PX1JFQ0VJVkVSEAISHgoaRklYX1NUQVRVU19S'
    'RUNFSVZFUl9TSUxFTlQQAxIVChFGSVhfU1RBVFVTX05PX0ZJWBAEEhUKEUZJWF9TVEFUVVNfRk'
    'lYXzJEEAUSFQoRRklYX1NUQVRVU19GSVhfM0QQBg==');

@$core.Deprecated('Use fixDescriptor instead')
const Fix$json = {
  '1': 'Fix',
  '2': [
    {'1': 'latitude_deg', '3': 1, '4': 1, '5': 1, '10': 'latitudeDeg'},
    {'1': 'longitude_deg', '3': 2, '4': 1, '5': 1, '10': 'longitudeDeg'},
    {'1': 'age_ms', '3': 3, '4': 1, '5': 4, '10': 'ageMs'},
    {
      '1': 'altitude_msl_m',
      '3': 4,
      '4': 1,
      '5': 1,
      '9': 0,
      '10': 'altitudeMslM',
      '17': true
    },
    {
      '1': 'speed_mps',
      '3': 5,
      '4': 1,
      '5': 1,
      '9': 1,
      '10': 'speedMps',
      '17': true
    },
    {
      '1': 'track_deg',
      '3': 6,
      '4': 1,
      '5': 1,
      '9': 2,
      '10': 'trackDeg',
      '17': true
    },
    {
      '1': 'horizontal_error_m',
      '3': 7,
      '4': 1,
      '5': 1,
      '9': 3,
      '10': 'horizontalErrorM',
      '17': true
    },
    {
      '1': 'utc_time_ms',
      '3': 8,
      '4': 1,
      '5': 3,
      '9': 4,
      '10': 'utcTimeMs',
      '17': true
    },
  ],
  '8': [
    {'1': '_altitude_msl_m'},
    {'1': '_speed_mps'},
    {'1': '_track_deg'},
    {'1': '_horizontal_error_m'},
    {'1': '_utc_time_ms'},
  ],
};

/// Descriptor for `Fix`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fixDescriptor = $convert.base64Decode(
    'CgNGaXgSIQoMbGF0aXR1ZGVfZGVnGAEgASgBUgtsYXRpdHVkZURlZxIjCg1sb25naXR1ZGVfZG'
    'VnGAIgASgBUgxsb25naXR1ZGVEZWcSFQoGYWdlX21zGAMgASgEUgVhZ2VNcxIpCg5hbHRpdHVk'
    'ZV9tc2xfbRgEIAEoAUgAUgxhbHRpdHVkZU1zbE2IAQESIAoJc3BlZWRfbXBzGAUgASgBSAFSCH'
    'NwZWVkTXBziAEBEiAKCXRyYWNrX2RlZxgGIAEoAUgCUgh0cmFja0RlZ4gBARIxChJob3Jpem9u'
    'dGFsX2Vycm9yX20YByABKAFIA1IQaG9yaXpvbnRhbEVycm9yTYgBARIjCgt1dGNfdGltZV9tcx'
    'gIIAEoA0gEUgl1dGNUaW1lTXOIAQFCEQoPX2FsdGl0dWRlX21zbF9tQgwKCl9zcGVlZF9tcHNC'
    'DAoKX3RyYWNrX2RlZ0IVChNfaG9yaXpvbnRhbF9lcnJvcl9tQg4KDF91dGNfdGltZV9tcw==');

@$core.Deprecated('Use positionDescriptor instead')
const Position$json = {
  '1': 'Position',
  '2': [
    {
      '1': 'status',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.f250.nav.v1.FixStatus',
      '10': 'status'
    },
    {'1': 'fix', '3': 2, '4': 1, '5': 11, '6': '.f250.nav.v1.Fix', '10': 'fix'},
    {'1': 'current', '3': 3, '4': 1, '5': 8, '10': 'current'},
    {'1': 'stale_after_ms', '3': 4, '4': 1, '5': 4, '10': 'staleAfterMs'},
    {
      '1': 'satellites_used',
      '3': 5,
      '4': 1,
      '5': 13,
      '9': 0,
      '10': 'satellitesUsed',
      '17': true
    },
    {
      '1': 'satellites_visible',
      '3': 6,
      '4': 1,
      '5': 13,
      '9': 1,
      '10': 'satellitesVisible',
      '17': true
    },
    {'1': 'source', '3': 7, '4': 1, '5': 9, '10': 'source'},
    {'1': 'simulated', '3': 8, '4': 1, '5': 8, '10': 'simulated'},
    {'1': 'detail', '3': 9, '4': 1, '5': 9, '10': 'detail'},
  ],
  '8': [
    {'1': '_satellites_used'},
    {'1': '_satellites_visible'},
  ],
};

/// Descriptor for `Position`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List positionDescriptor = $convert.base64Decode(
    'CghQb3NpdGlvbhIuCgZzdGF0dXMYASABKA4yFi5mMjUwLm5hdi52MS5GaXhTdGF0dXNSBnN0YX'
    'R1cxIiCgNmaXgYAiABKAsyEC5mMjUwLm5hdi52MS5GaXhSA2ZpeBIYCgdjdXJyZW50GAMgASgI'
    'UgdjdXJyZW50EiQKDnN0YWxlX2FmdGVyX21zGAQgASgEUgxzdGFsZUFmdGVyTXMSLAoPc2F0ZW'
    'xsaXRlc191c2VkGAUgASgNSABSDnNhdGVsbGl0ZXNVc2VkiAEBEjIKEnNhdGVsbGl0ZXNfdmlz'
    'aWJsZRgGIAEoDUgBUhFzYXRlbGxpdGVzVmlzaWJsZYgBARIWCgZzb3VyY2UYByABKAlSBnNvdX'
    'JjZRIcCglzaW11bGF0ZWQYCCABKAhSCXNpbXVsYXRlZBIWCgZkZXRhaWwYCSABKAlSBmRldGFp'
    'bEISChBfc2F0ZWxsaXRlc191c2VkQhUKE19zYXRlbGxpdGVzX3Zpc2libGU=');

@$core.Deprecated('Use watchPositionRequestDescriptor instead')
const WatchPositionRequest$json = {
  '1': 'WatchPositionRequest',
};

/// Descriptor for `WatchPositionRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchPositionRequestDescriptor =
    $convert.base64Decode('ChRXYXRjaFBvc2l0aW9uUmVxdWVzdA==');

@$core.Deprecated('Use watchPositionResponseDescriptor instead')
const WatchPositionResponse$json = {
  '1': 'WatchPositionResponse',
  '2': [
    {
      '1': 'position',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.nav.v1.Position',
      '10': 'position'
    },
  ],
};

/// Descriptor for `WatchPositionResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchPositionResponseDescriptor = $convert.base64Decode(
    'ChVXYXRjaFBvc2l0aW9uUmVzcG9uc2USMQoIcG9zaXRpb24YASABKAsyFS5mMjUwLm5hdi52MS'
    '5Qb3NpdGlvblIIcG9zaXRpb24=');
