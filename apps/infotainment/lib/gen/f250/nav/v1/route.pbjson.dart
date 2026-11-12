// This is a generated file - do not edit.
//
// Generated from f250/nav/v1/route.proto.

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

@$core.Deprecated('Use routeStateDescriptor instead')
const RouteState$json = {
  '1': 'RouteState',
  '2': [
    {'1': 'ROUTE_STATE_UNSPECIFIED', '2': 0},
    {'1': 'ROUTE_STATE_UNAVAILABLE', '2': 1},
    {'1': 'ROUTE_STATE_IDLE', '2': 2},
    {'1': 'ROUTE_STATE_ROUTING', '2': 3},
    {'1': 'ROUTE_STATE_ACTIVE', '2': 4},
    {'1': 'ROUTE_STATE_FAILED', '2': 5},
    {'1': 'ROUTE_STATE_ARRIVED', '2': 6},
  ],
};

/// Descriptor for `RouteState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List routeStateDescriptor = $convert.base64Decode(
    'CgpSb3V0ZVN0YXRlEhsKF1JPVVRFX1NUQVRFX1VOU1BFQ0lGSUVEEAASGwoXUk9VVEVfU1RBVE'
    'VfVU5BVkFJTEFCTEUQARIUChBST1VURV9TVEFURV9JRExFEAISFwoTUk9VVEVfU1RBVEVfUk9V'
    'VElORxADEhYKElJPVVRFX1NUQVRFX0FDVElWRRAEEhYKElJPVVRFX1NUQVRFX0ZBSUxFRBAFEh'
    'cKE1JPVVRFX1NUQVRFX0FSUklWRUQQBg==');

@$core.Deprecated('Use latLonDescriptor instead')
const LatLon$json = {
  '1': 'LatLon',
  '2': [
    {'1': 'latitude_deg', '3': 1, '4': 1, '5': 1, '10': 'latitudeDeg'},
    {'1': 'longitude_deg', '3': 2, '4': 1, '5': 1, '10': 'longitudeDeg'},
  ],
};

/// Descriptor for `LatLon`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List latLonDescriptor = $convert.base64Decode(
    'CgZMYXRMb24SIQoMbGF0aXR1ZGVfZGVnGAEgASgBUgtsYXRpdHVkZURlZxIjCg1sb25naXR1ZG'
    'VfZGVnGAIgASgBUgxsb25naXR1ZGVEZWc=');

@$core.Deprecated('Use maneuverDescriptor instead')
const Maneuver$json = {
  '1': 'Maneuver',
  '2': [
    {'1': 'type', '3': 1, '4': 1, '5': 13, '10': 'type'},
    {'1': 'instruction', '3': 2, '4': 1, '5': 9, '10': 'instruction'},
    {'1': 'street_names', '3': 3, '4': 3, '5': 9, '10': 'streetNames'},
    {'1': 'length_m', '3': 4, '4': 1, '5': 1, '10': 'lengthM'},
    {'1': 'time_s', '3': 5, '4': 1, '5': 1, '10': 'timeS'},
    {
      '1': 'begin_shape_index',
      '3': 6,
      '4': 1,
      '5': 13,
      '10': 'beginShapeIndex'
    },
    {'1': 'start_m', '3': 7, '4': 1, '5': 1, '10': 'startM'},
  ],
};

/// Descriptor for `Maneuver`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List maneuverDescriptor = $convert.base64Decode(
    'CghNYW5ldXZlchISCgR0eXBlGAEgASgNUgR0eXBlEiAKC2luc3RydWN0aW9uGAIgASgJUgtpbn'
    'N0cnVjdGlvbhIhCgxzdHJlZXRfbmFtZXMYAyADKAlSC3N0cmVldE5hbWVzEhkKCGxlbmd0aF9t'
    'GAQgASgBUgdsZW5ndGhNEhUKBnRpbWVfcxgFIAEoAVIFdGltZVMSKgoRYmVnaW5fc2hhcGVfaW'
    '5kZXgYBiABKA1SD2JlZ2luU2hhcGVJbmRleBIXCgdzdGFydF9tGAcgASgBUgZzdGFydE0=');

@$core.Deprecated('Use routeDescriptor instead')
const Route$json = {
  '1': 'Route',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 4, '10': 'id'},
    {
      '1': 'shape',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.f250.nav.v1.LatLon',
      '10': 'shape'
    },
    {
      '1': 'maneuvers',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.f250.nav.v1.Maneuver',
      '10': 'maneuvers'
    },
    {'1': 'length_m', '3': 4, '4': 1, '5': 1, '10': 'lengthM'},
    {'1': 'time_s', '3': 5, '4': 1, '5': 1, '10': 'timeS'},
    {
      '1': 'destination',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.f250.nav.v1.LatLon',
      '10': 'destination'
    },
    {'1': 'costing', '3': 7, '4': 1, '5': 9, '10': 'costing'},
    {'1': 'has_toll', '3': 8, '4': 1, '5': 8, '10': 'hasToll'},
    {'1': 'has_highway', '3': 9, '4': 1, '5': 8, '10': 'hasHighway'},
    {'1': 'has_ferry', '3': 10, '4': 1, '5': 8, '10': 'hasFerry'},
  ],
};

/// Descriptor for `Route`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List routeDescriptor = $convert.base64Decode(
    'CgVSb3V0ZRIOCgJpZBgBIAEoBFICaWQSKQoFc2hhcGUYAiADKAsyEy5mMjUwLm5hdi52MS5MYX'
    'RMb25SBXNoYXBlEjMKCW1hbmV1dmVycxgDIAMoCzIVLmYyNTAubmF2LnYxLk1hbmV1dmVyUglt'
    'YW5ldXZlcnMSGQoIbGVuZ3RoX20YBCABKAFSB2xlbmd0aE0SFQoGdGltZV9zGAUgASgBUgV0aW'
    '1lUxI1CgtkZXN0aW5hdGlvbhgGIAEoCzITLmYyNTAubmF2LnYxLkxhdExvblILZGVzdGluYXRp'
    'b24SGAoHY29zdGluZxgHIAEoCVIHY29zdGluZxIZCghoYXNfdG9sbBgIIAEoCFIHaGFzVG9sbB'
    'IfCgtoYXNfaGlnaHdheRgJIAEoCFIKaGFzSGlnaHdheRIbCgloYXNfZmVycnkYCiABKAhSCGhh'
    'c0ZlcnJ5');

@$core.Deprecated('Use progressDescriptor instead')
const Progress$json = {
  '1': 'Progress',
  '2': [
    {'1': 'maneuver_index', '3': 1, '4': 1, '5': 13, '10': 'maneuverIndex'},
    {'1': 'to_maneuver_m', '3': 2, '4': 1, '5': 1, '10': 'toManeuverM'},
    {'1': 'remaining_m', '3': 3, '4': 1, '5': 1, '10': 'remainingM'},
    {'1': 'remaining_s', '3': 4, '4': 1, '5': 1, '10': 'remainingS'},
    {'1': 'off_route_m', '3': 5, '4': 1, '5': 1, '10': 'offRouteM'},
    {'1': 'off_route', '3': 6, '4': 1, '5': 8, '10': 'offRoute'},
  ],
};

/// Descriptor for `Progress`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List progressDescriptor = $convert.base64Decode(
    'CghQcm9ncmVzcxIlCg5tYW5ldXZlcl9pbmRleBgBIAEoDVINbWFuZXV2ZXJJbmRleBIiCg10b1'
    '9tYW5ldXZlcl9tGAIgASgBUgt0b01hbmV1dmVyTRIfCgtyZW1haW5pbmdfbRgDIAEoAVIKcmVt'
    'YWluaW5nTRIfCgtyZW1haW5pbmdfcxgEIAEoAVIKcmVtYWluaW5nUxIeCgtvZmZfcm91dGVfbR'
    'gFIAEoAVIJb2ZmUm91dGVNEhsKCW9mZl9yb3V0ZRgGIAEoCFIIb2ZmUm91dGU=');

@$core.Deprecated('Use guidanceDescriptor instead')
const Guidance$json = {
  '1': 'Guidance',
  '2': [
    {
      '1': 'state',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.f250.nav.v1.RouteState',
      '10': 'state'
    },
    {'1': 'route_id', '3': 2, '4': 1, '5': 4, '10': 'routeId'},
    {
      '1': 'destination',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.f250.nav.v1.LatLon',
      '10': 'destination'
    },
    {
      '1': 'progress',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.f250.nav.v1.Progress',
      '10': 'progress'
    },
    {'1': 'detail', '3': 5, '4': 1, '5': 9, '10': 'detail'},
    {'1': 'reroutes', '3': 6, '4': 1, '5': 13, '10': 'reroutes'},
  ],
};

/// Descriptor for `Guidance`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List guidanceDescriptor = $convert.base64Decode(
    'CghHdWlkYW5jZRItCgVzdGF0ZRgBIAEoDjIXLmYyNTAubmF2LnYxLlJvdXRlU3RhdGVSBXN0YX'
    'RlEhkKCHJvdXRlX2lkGAIgASgEUgdyb3V0ZUlkEjUKC2Rlc3RpbmF0aW9uGAMgASgLMhMuZjI1'
    'MC5uYXYudjEuTGF0TG9uUgtkZXN0aW5hdGlvbhIxCghwcm9ncmVzcxgEIAEoCzIVLmYyNTAubm'
    'F2LnYxLlByb2dyZXNzUghwcm9ncmVzcxIWCgZkZXRhaWwYBSABKAlSBmRldGFpbBIaCghyZXJv'
    'dXRlcxgGIAEoDVIIcmVyb3V0ZXM=');

@$core.Deprecated('Use setDestinationRequestDescriptor instead')
const SetDestinationRequest$json = {
  '1': 'SetDestinationRequest',
  '2': [
    {
      '1': 'destination',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.nav.v1.LatLon',
      '10': 'destination'
    },
  ],
};

/// Descriptor for `SetDestinationRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setDestinationRequestDescriptor = $convert.base64Decode(
    'ChVTZXREZXN0aW5hdGlvblJlcXVlc3QSNQoLZGVzdGluYXRpb24YASABKAsyEy5mMjUwLm5hdi'
    '52MS5MYXRMb25SC2Rlc3RpbmF0aW9u');

@$core.Deprecated('Use setDestinationResponseDescriptor instead')
const SetDestinationResponse$json = {
  '1': 'SetDestinationResponse',
};

/// Descriptor for `SetDestinationResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setDestinationResponseDescriptor =
    $convert.base64Decode('ChZTZXREZXN0aW5hdGlvblJlc3BvbnNl');

@$core.Deprecated('Use clearRouteRequestDescriptor instead')
const ClearRouteRequest$json = {
  '1': 'ClearRouteRequest',
};

/// Descriptor for `ClearRouteRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List clearRouteRequestDescriptor =
    $convert.base64Decode('ChFDbGVhclJvdXRlUmVxdWVzdA==');

@$core.Deprecated('Use clearRouteResponseDescriptor instead')
const ClearRouteResponse$json = {
  '1': 'ClearRouteResponse',
};

/// Descriptor for `ClearRouteResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List clearRouteResponseDescriptor =
    $convert.base64Decode('ChJDbGVhclJvdXRlUmVzcG9uc2U=');

@$core.Deprecated('Use watchGuidanceRequestDescriptor instead')
const WatchGuidanceRequest$json = {
  '1': 'WatchGuidanceRequest',
};

/// Descriptor for `WatchGuidanceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchGuidanceRequestDescriptor =
    $convert.base64Decode('ChRXYXRjaEd1aWRhbmNlUmVxdWVzdA==');

@$core.Deprecated('Use watchGuidanceResponseDescriptor instead')
const WatchGuidanceResponse$json = {
  '1': 'WatchGuidanceResponse',
  '2': [
    {
      '1': 'guidance',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.nav.v1.Guidance',
      '10': 'guidance'
    },
  ],
};

/// Descriptor for `WatchGuidanceResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchGuidanceResponseDescriptor = $convert.base64Decode(
    'ChVXYXRjaEd1aWRhbmNlUmVzcG9uc2USMQoIZ3VpZGFuY2UYASABKAsyFS5mMjUwLm5hdi52MS'
    '5HdWlkYW5jZVIIZ3VpZGFuY2U=');

@$core.Deprecated('Use getRouteRequestDescriptor instead')
const GetRouteRequest$json = {
  '1': 'GetRouteRequest',
  '2': [
    {'1': 'route_id', '3': 1, '4': 1, '5': 4, '10': 'routeId'},
  ],
};

/// Descriptor for `GetRouteRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getRouteRequestDescriptor = $convert.base64Decode(
    'Cg9HZXRSb3V0ZVJlcXVlc3QSGQoIcm91dGVfaWQYASABKARSB3JvdXRlSWQ=');

@$core.Deprecated('Use getRouteResponseDescriptor instead')
const GetRouteResponse$json = {
  '1': 'GetRouteResponse',
  '2': [
    {
      '1': 'route',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.nav.v1.Route',
      '10': 'route'
    },
  ],
};

/// Descriptor for `GetRouteResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getRouteResponseDescriptor = $convert.base64Decode(
    'ChBHZXRSb3V0ZVJlc3BvbnNlEigKBXJvdXRlGAEgASgLMhIuZjI1MC5uYXYudjEuUm91dGVSBX'
    'JvdXRl');
