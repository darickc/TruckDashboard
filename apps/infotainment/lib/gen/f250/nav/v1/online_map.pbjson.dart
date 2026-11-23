// This is a generated file - do not edit.
//
// Generated from f250/nav/v1/online_map.proto.

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

@$core.Deprecated('Use mapStyleDescriptor instead')
const MapStyle$json = {
  '1': 'MapStyle',
  '2': [
    {'1': 'MAP_STYLE_UNSPECIFIED', '2': 0},
    {'1': 'MAP_STYLE_DAY', '2': 1},
    {'1': 'MAP_STYLE_NIGHT', '2': 2},
  ],
};

/// Descriptor for `MapStyle`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List mapStyleDescriptor = $convert.base64Decode(
    'CghNYXBTdHlsZRIZChVNQVBfU1RZTEVfVU5TUEVDSUZJRUQQABIRCg1NQVBfU1RZTEVfREFZEA'
    'ESEwoPTUFQX1NUWUxFX05JR0hUEAI=');

@$core.Deprecated('Use getOnlineMapStatusRequestDescriptor instead')
const GetOnlineMapStatusRequest$json = {
  '1': 'GetOnlineMapStatusRequest',
};

/// Descriptor for `GetOnlineMapStatusRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getOnlineMapStatusRequestDescriptor =
    $convert.base64Decode('ChlHZXRPbmxpbmVNYXBTdGF0dXNSZXF1ZXN0');

@$core.Deprecated('Use getOnlineMapStatusResponseDescriptor instead')
const GetOnlineMapStatusResponse$json = {
  '1': 'GetOnlineMapStatusResponse',
  '2': [
    {'1': 'configured', '3': 1, '4': 1, '5': 8, '10': 'configured'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
    {'1': 'attribution', '3': 3, '4': 1, '5': 9, '10': 'attribution'},
    {'1': 'tile_size', '3': 4, '4': 1, '5': 13, '10': 'tileSize'},
    {'1': 'max_zoom', '3': 5, '4': 1, '5': 13, '10': 'maxZoom'},
    {'1': 'routing_online', '3': 6, '4': 1, '5': 8, '10': 'routingOnline'},
  ],
};

/// Descriptor for `GetOnlineMapStatusResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getOnlineMapStatusResponseDescriptor = $convert.base64Decode(
    'ChpHZXRPbmxpbmVNYXBTdGF0dXNSZXNwb25zZRIeCgpjb25maWd1cmVkGAEgASgIUgpjb25maW'
    'd1cmVkEhYKBmRldGFpbBgCIAEoCVIGZGV0YWlsEiAKC2F0dHJpYnV0aW9uGAMgASgJUgthdHRy'
    'aWJ1dGlvbhIbCgl0aWxlX3NpemUYBCABKA1SCHRpbGVTaXplEhkKCG1heF96b29tGAUgASgNUg'
    'dtYXhab29tEiUKDnJvdXRpbmdfb25saW5lGAYgASgIUg1yb3V0aW5nT25saW5l');

@$core.Deprecated('Use getTileRequestDescriptor instead')
const GetTileRequest$json = {
  '1': 'GetTileRequest',
  '2': [
    {
      '1': 'style',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.f250.nav.v1.MapStyle',
      '10': 'style'
    },
    {'1': 'z', '3': 2, '4': 1, '5': 13, '10': 'z'},
    {'1': 'x', '3': 3, '4': 1, '5': 13, '10': 'x'},
    {'1': 'y', '3': 4, '4': 1, '5': 13, '10': 'y'},
  ],
};

/// Descriptor for `GetTileRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getTileRequestDescriptor = $convert.base64Decode(
    'Cg5HZXRUaWxlUmVxdWVzdBIrCgVzdHlsZRgBIAEoDjIVLmYyNTAubmF2LnYxLk1hcFN0eWxlUg'
    'VzdHlsZRIMCgF6GAIgASgNUgF6EgwKAXgYAyABKA1SAXgSDAoBeRgEIAEoDVIBeQ==');

@$core.Deprecated('Use getTileResponseDescriptor instead')
const GetTileResponse$json = {
  '1': 'GetTileResponse',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
    {'1': 'content_type', '3': 2, '4': 1, '5': 9, '10': 'contentType'},
  ],
};

/// Descriptor for `GetTileResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getTileResponseDescriptor = $convert.base64Decode(
    'Cg9HZXRUaWxlUmVzcG9uc2USEgoEZGF0YRgBIAEoDFIEZGF0YRIhCgxjb250ZW50X3R5cGUYAi'
    'ABKAlSC2NvbnRlbnRUeXBl');
