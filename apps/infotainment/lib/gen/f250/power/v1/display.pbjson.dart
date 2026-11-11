// This is a generated file - do not edit.
//
// Generated from f250/power/v1/display.proto.

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

@$core.Deprecated('Use displayModeDescriptor instead')
const DisplayMode$json = {
  '1': 'DisplayMode',
  '2': [
    {'1': 'DISPLAY_MODE_UNSPECIFIED', '2': 0},
    {'1': 'DISPLAY_MODE_DAY', '2': 1},
    {'1': 'DISPLAY_MODE_NIGHT', '2': 2},
  ],
};

/// Descriptor for `DisplayMode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List displayModeDescriptor = $convert.base64Decode(
    'CgtEaXNwbGF5TW9kZRIcChhESVNQTEFZX01PREVfVU5TUEVDSUZJRUQQABIUChBESVNQTEFZX0'
    '1PREVfREFZEAESFgoSRElTUExBWV9NT0RFX05JR0hUEAI=');

@$core.Deprecated('Use displayChoiceDescriptor instead')
const DisplayChoice$json = {
  '1': 'DisplayChoice',
  '2': [
    {'1': 'DISPLAY_CHOICE_UNSPECIFIED', '2': 0},
    {'1': 'DISPLAY_CHOICE_AUTO', '2': 1},
    {'1': 'DISPLAY_CHOICE_DAY', '2': 2},
    {'1': 'DISPLAY_CHOICE_NIGHT', '2': 3},
  ],
};

/// Descriptor for `DisplayChoice`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List displayChoiceDescriptor = $convert.base64Decode(
    'Cg1EaXNwbGF5Q2hvaWNlEh4KGkRJU1BMQVlfQ0hPSUNFX1VOU1BFQ0lGSUVEEAASFwoTRElTUE'
    'xBWV9DSE9JQ0VfQVVUTxABEhYKEkRJU1BMQVlfQ0hPSUNFX0RBWRACEhgKFERJU1BMQVlfQ0hP'
    'SUNFX05JR0hUEAM=');

@$core.Deprecated('Use modeBasisDescriptor instead')
const ModeBasis$json = {
  '1': 'ModeBasis',
  '2': [
    {'1': 'MODE_BASIS_UNSPECIFIED', '2': 0},
    {'1': 'MODE_BASIS_SUN', '2': 1},
    {'1': 'MODE_BASIS_MANUAL', '2': 2},
    {'1': 'MODE_BASIS_FALLBACK', '2': 3},
  ],
};

/// Descriptor for `ModeBasis`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modeBasisDescriptor = $convert.base64Decode(
    'CglNb2RlQmFzaXMSGgoWTU9ERV9CQVNJU19VTlNQRUNJRklFRBAAEhIKDk1PREVfQkFTSVNfU1'
    'VOEAESFQoRTU9ERV9CQVNJU19NQU5VQUwQAhIXChNNT0RFX0JBU0lTX0ZBTExCQUNLEAM=');

@$core.Deprecated('Use sunStatusDescriptor instead')
const SunStatus$json = {
  '1': 'SunStatus',
  '2': [
    {'1': 'SUN_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'SUN_STATUS_KNOWN', '2': 1},
    {'1': 'SUN_STATUS_NO_LOCATION', '2': 2},
    {'1': 'SUN_STATUS_CLOCK_NOT_SYNCHRONIZED', '2': 3},
    {'1': 'SUN_STATUS_CLOCK_NOT_SET', '2': 4},
  ],
};

/// Descriptor for `SunStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List sunStatusDescriptor = $convert.base64Decode(
    'CglTdW5TdGF0dXMSGgoWU1VOX1NUQVRVU19VTlNQRUNJRklFRBAAEhQKEFNVTl9TVEFUVVNfS0'
    '5PV04QARIaChZTVU5fU1RBVFVTX05PX0xPQ0FUSU9OEAISJQohU1VOX1NUQVRVU19DTE9DS19O'
    'T1RfU1lOQ0hST05JWkVEEAMSHAoYU1VOX1NUQVRVU19DTE9DS19OT1RfU0VUEAQ=');

@$core.Deprecated('Use displayDescriptor instead')
const Display$json = {
  '1': 'Display',
  '2': [
    {
      '1': 'mode',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.f250.power.v1.DisplayMode',
      '10': 'mode'
    },
    {
      '1': 'choice',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.f250.power.v1.DisplayChoice',
      '10': 'choice'
    },
    {
      '1': 'basis',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.f250.power.v1.ModeBasis',
      '10': 'basis'
    },
    {
      '1': 'sun',
      '3': 4,
      '4': 1,
      '5': 14,
      '6': '.f250.power.v1.SunStatus',
      '10': 'sun'
    },
    {'1': 'sun_elevation_deg', '3': 5, '4': 1, '5': 1, '10': 'sunElevationDeg'},
    {
      '1': 'day_brightness_pct',
      '3': 6,
      '4': 1,
      '5': 13,
      '10': 'dayBrightnessPct'
    },
    {
      '1': 'night_brightness_pct',
      '3': 7,
      '4': 1,
      '5': 13,
      '10': 'nightBrightnessPct'
    },
    {
      '1': 'min_brightness_pct',
      '3': 8,
      '4': 1,
      '5': 13,
      '10': 'minBrightnessPct'
    },
    {
      '1': 'backlight_present',
      '3': 9,
      '4': 1,
      '5': 8,
      '10': 'backlightPresent'
    },
    {'1': 'backlight', '3': 10, '4': 1, '5': 9, '10': 'backlight'},
    {'1': 'brightness_pct', '3': 11, '4': 1, '5': 13, '10': 'brightnessPct'},
    {
      '1': 'backlight_problem',
      '3': 12,
      '4': 1,
      '5': 9,
      '10': 'backlightProblem'
    },
  ],
};

/// Descriptor for `Display`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List displayDescriptor = $convert.base64Decode(
    'CgdEaXNwbGF5Ei4KBG1vZGUYASABKA4yGi5mMjUwLnBvd2VyLnYxLkRpc3BsYXlNb2RlUgRtb2'
    'RlEjQKBmNob2ljZRgCIAEoDjIcLmYyNTAucG93ZXIudjEuRGlzcGxheUNob2ljZVIGY2hvaWNl'
    'Ei4KBWJhc2lzGAMgASgOMhguZjI1MC5wb3dlci52MS5Nb2RlQmFzaXNSBWJhc2lzEioKA3N1bh'
    'gEIAEoDjIYLmYyNTAucG93ZXIudjEuU3VuU3RhdHVzUgNzdW4SKgoRc3VuX2VsZXZhdGlvbl9k'
    'ZWcYBSABKAFSD3N1bkVsZXZhdGlvbkRlZxIsChJkYXlfYnJpZ2h0bmVzc19wY3QYBiABKA1SEG'
    'RheUJyaWdodG5lc3NQY3QSMAoUbmlnaHRfYnJpZ2h0bmVzc19wY3QYByABKA1SEm5pZ2h0QnJp'
    'Z2h0bmVzc1BjdBIsChJtaW5fYnJpZ2h0bmVzc19wY3QYCCABKA1SEG1pbkJyaWdodG5lc3NQY3'
    'QSKwoRYmFja2xpZ2h0X3ByZXNlbnQYCSABKAhSEGJhY2tsaWdodFByZXNlbnQSHAoJYmFja2xp'
    'Z2h0GAogASgJUgliYWNrbGlnaHQSJQoOYnJpZ2h0bmVzc19wY3QYCyABKA1SDWJyaWdodG5lc3'
    'NQY3QSKwoRYmFja2xpZ2h0X3Byb2JsZW0YDCABKAlSEGJhY2tsaWdodFByb2JsZW0=');

@$core.Deprecated('Use watchDisplayRequestDescriptor instead')
const WatchDisplayRequest$json = {
  '1': 'WatchDisplayRequest',
};

/// Descriptor for `WatchDisplayRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchDisplayRequestDescriptor =
    $convert.base64Decode('ChNXYXRjaERpc3BsYXlSZXF1ZXN0');

@$core.Deprecated('Use watchDisplayResponseDescriptor instead')
const WatchDisplayResponse$json = {
  '1': 'WatchDisplayResponse',
  '2': [
    {
      '1': 'display',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.power.v1.Display',
      '10': 'display'
    },
  ],
};

/// Descriptor for `WatchDisplayResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchDisplayResponseDescriptor = $convert.base64Decode(
    'ChRXYXRjaERpc3BsYXlSZXNwb25zZRIwCgdkaXNwbGF5GAEgASgLMhYuZjI1MC5wb3dlci52MS'
    '5EaXNwbGF5UgdkaXNwbGF5');

@$core.Deprecated('Use setDisplayRequestDescriptor instead')
const SetDisplayRequest$json = {
  '1': 'SetDisplayRequest',
  '2': [
    {
      '1': 'choice',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.f250.power.v1.DisplayChoice',
      '10': 'choice'
    },
    {
      '1': 'day_brightness_pct',
      '3': 2,
      '4': 1,
      '5': 13,
      '10': 'dayBrightnessPct'
    },
    {
      '1': 'night_brightness_pct',
      '3': 3,
      '4': 1,
      '5': 13,
      '10': 'nightBrightnessPct'
    },
    {'1': 'source', '3': 4, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `SetDisplayRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setDisplayRequestDescriptor = $convert.base64Decode(
    'ChFTZXREaXNwbGF5UmVxdWVzdBI0CgZjaG9pY2UYASABKA4yHC5mMjUwLnBvd2VyLnYxLkRpc3'
    'BsYXlDaG9pY2VSBmNob2ljZRIsChJkYXlfYnJpZ2h0bmVzc19wY3QYAiABKA1SEGRheUJyaWdo'
    'dG5lc3NQY3QSMAoUbmlnaHRfYnJpZ2h0bmVzc19wY3QYAyABKA1SEm5pZ2h0QnJpZ2h0bmVzc1'
    'BjdBIWCgZzb3VyY2UYBCABKAlSBnNvdXJjZQ==');

@$core.Deprecated('Use setDisplayResponseDescriptor instead')
const SetDisplayResponse$json = {
  '1': 'SetDisplayResponse',
  '2': [
    {
      '1': 'display',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.power.v1.Display',
      '10': 'display'
    },
  ],
};

/// Descriptor for `SetDisplayResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setDisplayResponseDescriptor = $convert.base64Decode(
    'ChJTZXREaXNwbGF5UmVzcG9uc2USMAoHZGlzcGxheRgBIAEoCzIWLmYyNTAucG93ZXIudjEuRG'
    'lzcGxheVIHZGlzcGxheQ==');
