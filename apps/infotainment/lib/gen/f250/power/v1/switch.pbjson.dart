// This is a generated file - do not edit.
//
// Generated from f250/power/v1/switch.proto.

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

@$core.Deprecated('Use wireDescriptor instead')
const Wire$json = {
  '1': 'Wire',
  '2': [
    {'1': 'WIRE_UNSPECIFIED', '2': 0},
    {'1': 'WIRE_F13', '2': 1},
    {'1': 'WIRE_F14', '2': 2},
    {'1': 'WIRE_F15', '2': 3},
    {'1': 'WIRE_F16', '2': 4},
    {'1': 'WIRE_F17', '2': 5},
  ],
};

/// Descriptor for `Wire`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List wireDescriptor = $convert.base64Decode(
    'CgRXaXJlEhQKEFdJUkVfVU5TUEVDSUZJRUQQABIMCghXSVJFX0YxMxABEgwKCFdJUkVfRjE0EA'
    'ISDAoIV0lSRV9GMTUQAxIMCghXSVJFX0YxNhAEEgwKCFdJUkVfRjE3EAU=');

@$core.Deprecated('Use roleDescriptor instead')
const Role$json = {
  '1': 'Role',
  '2': [
    {'1': 'ROLE_UNSPECIFIED', '2': 0},
    {'1': 'ROLE_UP', '2': 1},
    {'1': 'ROLE_DOWN', '2': 2},
    {'1': 'ROLE_LEFT', '2': 3},
    {'1': 'ROLE_RIGHT', '2': 4},
    {'1': 'ROLE_PRESS', '2': 5},
  ],
};

/// Descriptor for `Role`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List roleDescriptor = $convert.base64Decode(
    'CgRSb2xlEhQKEFJPTEVfVU5TUEVDSUZJRUQQABILCgdST0xFX1VQEAESDQoJUk9MRV9ET1dOEA'
    'ISDQoJUk9MRV9MRUZUEAMSDgoKUk9MRV9SSUdIVBAEEg4KClJPTEVfUFJFU1MQBQ==');

@$core.Deprecated('Use pressKindDescriptor instead')
const PressKind$json = {
  '1': 'PressKind',
  '2': [
    {'1': 'PRESS_KIND_UNSPECIFIED', '2': 0},
    {'1': 'PRESS_KIND_SHORT', '2': 1},
    {'1': 'PRESS_KIND_LONG', '2': 2},
  ],
};

/// Descriptor for `PressKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List pressKindDescriptor = $convert.base64Decode(
    'CglQcmVzc0tpbmQSGgoWUFJFU1NfS0lORF9VTlNQRUNJRklFRBAAEhQKEFBSRVNTX0tJTkRfU0'
    'hPUlQQARITCg9QUkVTU19LSU5EX0xPTkcQAg==');

@$core.Deprecated('Use wireInfoDescriptor instead')
const WireInfo$json = {
  '1': 'WireInfo',
  '2': [
    {
      '1': 'wire',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.f250.power.v1.Wire',
      '10': 'wire'
    },
    {'1': 'pin', '3': 2, '4': 1, '5': 9, '10': 'pin'},
    {
      '1': 'role',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.f250.power.v1.Role',
      '10': 'role'
    },
    {'1': 'present', '3': 4, '4': 1, '5': 8, '10': 'present'},
  ],
};

/// Descriptor for `WireInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List wireInfoDescriptor = $convert.base64Decode(
    'CghXaXJlSW5mbxInCgR3aXJlGAEgASgOMhMuZjI1MC5wb3dlci52MS5XaXJlUgR3aXJlEhAKA3'
    'BpbhgCIAEoCVIDcGluEicKBHJvbGUYAyABKA4yEy5mMjUwLnBvd2VyLnYxLlJvbGVSBHJvbGUS'
    'GAoHcHJlc2VudBgEIAEoCFIHcHJlc2VudA==');

@$core.Deprecated('Use switchStateDescriptor instead')
const SwitchState$json = {
  '1': 'SwitchState',
  '2': [
    {
      '1': 'wires',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.f250.power.v1.WireInfo',
      '10': 'wires'
    },
    {'1': 'learning', '3': 2, '4': 1, '5': 8, '10': 'learning'},
    {
      '1': 'learning_timeout_s',
      '3': 3,
      '4': 1,
      '5': 13,
      '10': 'learningTimeoutS'
    },
    {'1': 'long_press_ms', '3': 4, '4': 1, '5': 13, '10': 'longPressMs'},
    {'1': 'default_mapping', '3': 5, '4': 1, '5': 8, '10': 'defaultMapping'},
    {'1': 'problem', '3': 6, '4': 1, '5': 9, '10': 'problem'},
  ],
};

/// Descriptor for `SwitchState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List switchStateDescriptor = $convert.base64Decode(
    'CgtTd2l0Y2hTdGF0ZRItCgV3aXJlcxgBIAMoCzIXLmYyNTAucG93ZXIudjEuV2lyZUluZm9SBX'
    'dpcmVzEhoKCGxlYXJuaW5nGAIgASgIUghsZWFybmluZxIsChJsZWFybmluZ190aW1lb3V0X3MY'
    'AyABKA1SEGxlYXJuaW5nVGltZW91dFMSIgoNbG9uZ19wcmVzc19tcxgEIAEoDVILbG9uZ1ByZX'
    'NzTXMSJwoPZGVmYXVsdF9tYXBwaW5nGAUgASgIUg5kZWZhdWx0TWFwcGluZxIYCgdwcm9ibGVt'
    'GAYgASgJUgdwcm9ibGVt');

@$core.Deprecated('Use pressDescriptor instead')
const Press$json = {
  '1': 'Press',
  '2': [
    {
      '1': 'wire',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.f250.power.v1.Wire',
      '10': 'wire'
    },
    {
      '1': 'role',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.f250.power.v1.Role',
      '10': 'role'
    },
    {
      '1': 'kind',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.f250.power.v1.PressKind',
      '10': 'kind'
    },
    {'1': 'result', '3': 4, '4': 1, '5': 9, '10': 'result'},
    {'1': 'seq', '3': 5, '4': 1, '5': 4, '10': 'seq'},
  ],
};

/// Descriptor for `Press`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pressDescriptor = $convert.base64Decode(
    'CgVQcmVzcxInCgR3aXJlGAEgASgOMhMuZjI1MC5wb3dlci52MS5XaXJlUgR3aXJlEicKBHJvbG'
    'UYAiABKA4yEy5mMjUwLnBvd2VyLnYxLlJvbGVSBHJvbGUSLAoEa2luZBgDIAEoDjIYLmYyNTAu'
    'cG93ZXIudjEuUHJlc3NLaW5kUgRraW5kEhYKBnJlc3VsdBgEIAEoCVIGcmVzdWx0EhAKA3NlcR'
    'gFIAEoBFIDc2Vx');

@$core.Deprecated('Use watchSwitchRequestDescriptor instead')
const WatchSwitchRequest$json = {
  '1': 'WatchSwitchRequest',
};

/// Descriptor for `WatchSwitchRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchSwitchRequestDescriptor =
    $convert.base64Decode('ChJXYXRjaFN3aXRjaFJlcXVlc3Q=');

@$core.Deprecated('Use watchSwitchResponseDescriptor instead')
const WatchSwitchResponse$json = {
  '1': 'WatchSwitchResponse',
  '2': [
    {
      '1': 'state',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.power.v1.SwitchState',
      '9': 0,
      '10': 'state'
    },
    {
      '1': 'press',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.f250.power.v1.Press',
      '9': 0,
      '10': 'press'
    },
  ],
  '8': [
    {'1': 'event'},
  ],
};

/// Descriptor for `WatchSwitchResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchSwitchResponseDescriptor = $convert.base64Decode(
    'ChNXYXRjaFN3aXRjaFJlc3BvbnNlEjIKBXN0YXRlGAEgASgLMhouZjI1MC5wb3dlci52MS5Td2'
    'l0Y2hTdGF0ZUgAUgVzdGF0ZRIsCgVwcmVzcxgCIAEoCzIULmYyNTAucG93ZXIudjEuUHJlc3NI'
    'AFIFcHJlc3NCBwoFZXZlbnQ=');

@$core.Deprecated('Use setLearningRequestDescriptor instead')
const SetLearningRequest$json = {
  '1': 'SetLearningRequest',
  '2': [
    {'1': 'on', '3': 1, '4': 1, '5': 8, '10': 'on'},
    {'1': 'source', '3': 2, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `SetLearningRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setLearningRequestDescriptor = $convert.base64Decode(
    'ChJTZXRMZWFybmluZ1JlcXVlc3QSDgoCb24YASABKAhSAm9uEhYKBnNvdXJjZRgCIAEoCVIGc2'
    '91cmNl');

@$core.Deprecated('Use setLearningResponseDescriptor instead')
const SetLearningResponse$json = {
  '1': 'SetLearningResponse',
  '2': [
    {
      '1': 'state',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.power.v1.SwitchState',
      '10': 'state'
    },
  ],
};

/// Descriptor for `SetLearningResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setLearningResponseDescriptor = $convert.base64Decode(
    'ChNTZXRMZWFybmluZ1Jlc3BvbnNlEjAKBXN0YXRlGAEgASgLMhouZjI1MC5wb3dlci52MS5Td2'
    'l0Y2hTdGF0ZVIFc3RhdGU=');

@$core.Deprecated('Use wireRoleDescriptor instead')
const WireRole$json = {
  '1': 'WireRole',
  '2': [
    {
      '1': 'wire',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.f250.power.v1.Wire',
      '10': 'wire'
    },
    {
      '1': 'role',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.f250.power.v1.Role',
      '10': 'role'
    },
  ],
};

/// Descriptor for `WireRole`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List wireRoleDescriptor = $convert.base64Decode(
    'CghXaXJlUm9sZRInCgR3aXJlGAEgASgOMhMuZjI1MC5wb3dlci52MS5XaXJlUgR3aXJlEicKBH'
    'JvbGUYAiABKA4yEy5mMjUwLnBvd2VyLnYxLlJvbGVSBHJvbGU=');

@$core.Deprecated('Use setMappingRequestDescriptor instead')
const SetMappingRequest$json = {
  '1': 'SetMappingRequest',
  '2': [
    {
      '1': 'wires',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.f250.power.v1.WireRole',
      '10': 'wires'
    },
    {'1': 'source', '3': 2, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `SetMappingRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setMappingRequestDescriptor = $convert.base64Decode(
    'ChFTZXRNYXBwaW5nUmVxdWVzdBItCgV3aXJlcxgBIAMoCzIXLmYyNTAucG93ZXIudjEuV2lyZV'
    'JvbGVSBXdpcmVzEhYKBnNvdXJjZRgCIAEoCVIGc291cmNl');

@$core.Deprecated('Use setMappingResponseDescriptor instead')
const SetMappingResponse$json = {
  '1': 'SetMappingResponse',
  '2': [
    {'1': 'saved', '3': 1, '4': 1, '5': 8, '10': 'saved'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
    {
      '1': 'state',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.f250.power.v1.SwitchState',
      '10': 'state'
    },
  ],
};

/// Descriptor for `SetMappingResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setMappingResponseDescriptor = $convert.base64Decode(
    'ChJTZXRNYXBwaW5nUmVzcG9uc2USFAoFc2F2ZWQYASABKAhSBXNhdmVkEhYKBmRldGFpbBgCIA'
    'EoCVIGZGV0YWlsEjAKBXN0YXRlGAMgASgLMhouZjI1MC5wb3dlci52MS5Td2l0Y2hTdGF0ZVIF'
    'c3RhdGU=');

@$core.Deprecated('Use resetMappingRequestDescriptor instead')
const ResetMappingRequest$json = {
  '1': 'ResetMappingRequest',
  '2': [
    {'1': 'source', '3': 1, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `ResetMappingRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resetMappingRequestDescriptor =
    $convert.base64Decode(
        'ChNSZXNldE1hcHBpbmdSZXF1ZXN0EhYKBnNvdXJjZRgBIAEoCVIGc291cmNl');

@$core.Deprecated('Use resetMappingResponseDescriptor instead')
const ResetMappingResponse$json = {
  '1': 'ResetMappingResponse',
  '2': [
    {'1': 'saved', '3': 1, '4': 1, '5': 8, '10': 'saved'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
    {
      '1': 'state',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.f250.power.v1.SwitchState',
      '10': 'state'
    },
  ],
};

/// Descriptor for `ResetMappingResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resetMappingResponseDescriptor = $convert.base64Decode(
    'ChRSZXNldE1hcHBpbmdSZXNwb25zZRIUCgVzYXZlZBgBIAEoCFIFc2F2ZWQSFgoGZGV0YWlsGA'
    'IgASgJUgZkZXRhaWwSMAoFc3RhdGUYAyABKAsyGi5mMjUwLnBvd2VyLnYxLlN3aXRjaFN0YXRl'
    'UgVzdGF0ZQ==');
