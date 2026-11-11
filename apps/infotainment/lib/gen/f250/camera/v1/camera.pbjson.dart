// This is a generated file - do not edit.
//
// Generated from f250/camera/v1/camera.proto.

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

@$core.Deprecated('Use cameraDescriptor instead')
const Camera$json = {
  '1': 'Camera',
  '2': [
    {'1': 'CAMERA_UNSPECIFIED', '2': 0},
    {'1': 'CAMERA_LEFT', '2': 1},
    {'1': 'CAMERA_RIGHT', '2': 2},
    {'1': 'CAMERA_REAR', '2': 3},
    {'1': 'CAMERA_FRONT', '2': 4},
  ],
};

/// Descriptor for `Camera`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List cameraDescriptor = $convert.base64Decode(
    'CgZDYW1lcmESFgoSQ0FNRVJBX1VOU1BFQ0lGSUVEEAASDwoLQ0FNRVJBX0xFRlQQARIQCgxDQU'
    '1FUkFfUklHSFQQAhIPCgtDQU1FUkFfUkVBUhADEhAKDENBTUVSQV9GUk9OVBAE');

@$core.Deprecated('Use switchMoveDescriptor instead')
const SwitchMove$json = {
  '1': 'SwitchMove',
  '2': [
    {'1': 'SWITCH_MOVE_UNSPECIFIED', '2': 0},
    {'1': 'SWITCH_MOVE_LEFT', '2': 1},
    {'1': 'SWITCH_MOVE_RIGHT', '2': 2},
    {'1': 'SWITCH_MOVE_BACK', '2': 3},
    {'1': 'SWITCH_MOVE_FORWARD', '2': 4},
    {'1': 'SWITCH_MOVE_PRESS', '2': 5},
  ],
};

/// Descriptor for `SwitchMove`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List switchMoveDescriptor = $convert.base64Decode(
    'CgpTd2l0Y2hNb3ZlEhsKF1NXSVRDSF9NT1ZFX1VOU1BFQ0lGSUVEEAASFAoQU1dJVENIX01PVk'
    'VfTEVGVBABEhUKEVNXSVRDSF9NT1ZFX1JJR0hUEAISFAoQU1dJVENIX01PVkVfQkFDSxADEhcK'
    'E1NXSVRDSF9NT1ZFX0ZPUldBUkQQBBIVChFTV0lUQ0hfTU9WRV9QUkVTUxAF');

@$core.Deprecated('Use reasonDescriptor instead')
const Reason$json = {
  '1': 'Reason',
  '2': [
    {'1': 'REASON_UNSPECIFIED', '2': 0},
    {'1': 'REASON_REVERSE', '2': 1},
    {'1': 'REASON_SWITCH', '2': 2},
  ],
};

/// Descriptor for `Reason`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List reasonDescriptor = $convert.base64Decode(
    'CgZSZWFzb24SFgoSUkVBU09OX1VOU1BFQ0lGSUVEEAASEgoOUkVBU09OX1JFVkVSU0UQARIRCg'
    '1SRUFTT05fU1dJVENIEAI=');

@$core.Deprecated('Use reverseStatusDescriptor instead')
const ReverseStatus$json = {
  '1': 'ReverseStatus',
  '2': [
    {'1': 'REVERSE_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'REVERSE_STATUS_OFF', '2': 1},
    {'1': 'REVERSE_STATUS_UNKNOWN', '2': 2},
    {'1': 'REVERSE_STATUS_NOT_ENGAGED', '2': 3},
    {'1': 'REVERSE_STATUS_ENGAGED', '2': 4},
  ],
};

/// Descriptor for `ReverseStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List reverseStatusDescriptor = $convert.base64Decode(
    'Cg1SZXZlcnNlU3RhdHVzEh4KGlJFVkVSU0VfU1RBVFVTX1VOU1BFQ0lGSUVEEAASFgoSUkVWRV'
    'JTRV9TVEFUVVNfT0ZGEAESGgoWUkVWRVJTRV9TVEFUVVNfVU5LTk9XThACEh4KGlJFVkVSU0Vf'
    'U1RBVFVTX05PVF9FTkdBR0VEEAMSGgoWUkVWRVJTRV9TVEFUVVNfRU5HQUdFRBAE');

@$core.Deprecated('Use feedStateDescriptor instead')
const FeedState$json = {
  '1': 'FeedState',
  '2': [
    {'1': 'FEED_STATE_UNSPECIFIED', '2': 0},
    {'1': 'FEED_STATE_STARTING', '2': 1},
    {'1': 'FEED_STATE_LIVE', '2': 2},
    {'1': 'FEED_STATE_UNAVAILABLE', '2': 3},
  ],
};

/// Descriptor for `FeedState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List feedStateDescriptor = $convert.base64Decode(
    'CglGZWVkU3RhdGUSGgoWRkVFRF9TVEFURV9VTlNQRUNJRklFRBAAEhcKE0ZFRURfU1RBVEVfU1'
    'RBUlRJTkcQARITCg9GRUVEX1NUQVRFX0xJVkUQAhIaChZGRUVEX1NUQVRFX1VOQVZBSUxBQkxF'
    'EAM=');

@$core.Deprecated('Use recordingStateDescriptor instead')
const RecordingState$json = {
  '1': 'RecordingState',
  '2': [
    {'1': 'RECORDING_STATE_UNSPECIFIED', '2': 0},
    {'1': 'RECORDING_STATE_STARTING', '2': 1},
    {'1': 'RECORDING_STATE_RECORDING', '2': 2},
    {'1': 'RECORDING_STATE_NOT_RECORDING', '2': 3},
  ],
};

/// Descriptor for `RecordingState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List recordingStateDescriptor = $convert.base64Decode(
    'Cg5SZWNvcmRpbmdTdGF0ZRIfChtSRUNPUkRJTkdfU1RBVEVfVU5TUEVDSUZJRUQQABIcChhSRU'
    'NPUkRJTkdfU1RBVEVfU1RBUlRJTkcQARIdChlSRUNPUkRJTkdfU1RBVEVfUkVDT1JESU5HEAIS'
    'IQodUkVDT1JESU5HX1NUQVRFX05PVF9SRUNPUkRJTkcQAw==');

@$core.Deprecated('Use viewDescriptor instead')
const View$json = {
  '1': 'View',
  '2': [
    {
      '1': 'camera',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.f250.camera.v1.Camera',
      '10': 'camera'
    },
    {
      '1': 'reason',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.f250.camera.v1.Reason',
      '10': 'reason'
    },
    {
      '1': 'feed',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.f250.camera.v1.FeedState',
      '10': 'feed'
    },
    {'1': 'feed_detail', '3': 4, '4': 1, '5': 9, '10': 'feedDetail'},
    {
      '1': 'reverse',
      '3': 5,
      '4': 1,
      '5': 14,
      '6': '.f250.camera.v1.ReverseStatus',
      '10': 'reverse'
    },
    {'1': 'blocked_by_speed', '3': 6, '4': 1, '5': 8, '10': 'blockedBySpeed'},
  ],
};

/// Descriptor for `View`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List viewDescriptor = $convert.base64Decode(
    'CgRWaWV3Ei4KBmNhbWVyYRgBIAEoDjIWLmYyNTAuY2FtZXJhLnYxLkNhbWVyYVIGY2FtZXJhEi'
    '4KBnJlYXNvbhgCIAEoDjIWLmYyNTAuY2FtZXJhLnYxLlJlYXNvblIGcmVhc29uEi0KBGZlZWQY'
    'AyABKA4yGS5mMjUwLmNhbWVyYS52MS5GZWVkU3RhdGVSBGZlZWQSHwoLZmVlZF9kZXRhaWwYBC'
    'ABKAlSCmZlZWREZXRhaWwSNwoHcmV2ZXJzZRgFIAEoDjIdLmYyNTAuY2FtZXJhLnYxLlJldmVy'
    'c2VTdGF0dXNSB3JldmVyc2USKAoQYmxvY2tlZF9ieV9zcGVlZBgGIAEoCFIOYmxvY2tlZEJ5U3'
    'BlZWQ=');

@$core.Deprecated('Use watchViewRequestDescriptor instead')
const WatchViewRequest$json = {
  '1': 'WatchViewRequest',
};

/// Descriptor for `WatchViewRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchViewRequestDescriptor =
    $convert.base64Decode('ChBXYXRjaFZpZXdSZXF1ZXN0');

@$core.Deprecated('Use watchViewResponseDescriptor instead')
const WatchViewResponse$json = {
  '1': 'WatchViewResponse',
  '2': [
    {
      '1': 'view',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.camera.v1.View',
      '10': 'view'
    },
  ],
};

/// Descriptor for `WatchViewResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchViewResponseDescriptor = $convert.base64Decode(
    'ChFXYXRjaFZpZXdSZXNwb25zZRIoCgR2aWV3GAEgASgLMhQuZjI1MC5jYW1lcmEudjEuVmlld1'
    'IEdmlldw==');

@$core.Deprecated('Use moveRequestDescriptor instead')
const MoveRequest$json = {
  '1': 'MoveRequest',
  '2': [
    {
      '1': 'move',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.f250.camera.v1.SwitchMove',
      '10': 'move'
    },
    {'1': 'source', '3': 2, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `MoveRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List moveRequestDescriptor = $convert.base64Decode(
    'CgtNb3ZlUmVxdWVzdBIuCgRtb3ZlGAEgASgOMhouZjI1MC5jYW1lcmEudjEuU3dpdGNoTW92ZV'
    'IEbW92ZRIWCgZzb3VyY2UYAiABKAlSBnNvdXJjZQ==');

@$core.Deprecated('Use moveResponseDescriptor instead')
const MoveResponse$json = {
  '1': 'MoveResponse',
  '2': [
    {
      '1': 'view',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.camera.v1.View',
      '10': 'view'
    },
  ],
};

/// Descriptor for `MoveResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List moveResponseDescriptor = $convert.base64Decode(
    'CgxNb3ZlUmVzcG9uc2USKAoEdmlldxgBIAEoCzIULmYyNTAuY2FtZXJhLnYxLlZpZXdSBHZpZX'
    'c=');

@$core.Deprecated('Use cameraRecordingDescriptor instead')
const CameraRecording$json = {
  '1': 'CameraRecording',
  '2': [
    {
      '1': 'camera',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.f250.camera.v1.Camera',
      '10': 'camera'
    },
    {
      '1': 'state',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.f250.camera.v1.RecordingState',
      '10': 'state'
    },
    {'1': 'detail', '3': 3, '4': 1, '5': 9, '10': 'detail'},
    {'1': 'segment', '3': 4, '4': 1, '5': 9, '10': 'segment'},
  ],
};

/// Descriptor for `CameraRecording`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List cameraRecordingDescriptor = $convert.base64Decode(
    'Cg9DYW1lcmFSZWNvcmRpbmcSLgoGY2FtZXJhGAEgASgOMhYuZjI1MC5jYW1lcmEudjEuQ2FtZX'
    'JhUgZjYW1lcmESNAoFc3RhdGUYAiABKA4yHi5mMjUwLmNhbWVyYS52MS5SZWNvcmRpbmdTdGF0'
    'ZVIFc3RhdGUSFgoGZGV0YWlsGAMgASgJUgZkZXRhaWwSGAoHc2VnbWVudBgEIAEoCVIHc2VnbW'
    'VudA==');

@$core.Deprecated('Use recordingDescriptor instead')
const Recording$json = {
  '1': 'Recording',
  '2': [
    {
      '1': 'cameras',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.f250.camera.v1.CameraRecording',
      '10': 'cameras'
    },
    {'1': 'drive_mounted', '3': 2, '4': 1, '5': 8, '10': 'driveMounted'},
    {'1': 'drive_free_bytes', '3': 3, '4': 1, '5': 4, '10': 'driveFreeBytes'},
    {'1': 'recorded_bytes', '3': 4, '4': 1, '5': 4, '10': 'recordedBytes'},
    {'1': 'protected_bytes', '3': 5, '4': 1, '5': 4, '10': 'protectedBytes'},
    {
      '1': 'protected_max_bytes',
      '3': 6,
      '4': 1,
      '5': 4,
      '10': 'protectedMaxBytes'
    },
    {
      '1': 'clip_segments_pending',
      '3': 7,
      '4': 1,
      '5': 13,
      '10': 'clipSegmentsPending'
    },
    {'1': 'clock_trusted', '3': 8, '4': 1, '5': 8, '10': 'clockTrusted'},
    {'1': 'problem', '3': 9, '4': 1, '5': 9, '10': 'problem'},
  ],
};

/// Descriptor for `Recording`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List recordingDescriptor = $convert.base64Decode(
    'CglSZWNvcmRpbmcSOQoHY2FtZXJhcxgBIAMoCzIfLmYyNTAuY2FtZXJhLnYxLkNhbWVyYVJlY2'
    '9yZGluZ1IHY2FtZXJhcxIjCg1kcml2ZV9tb3VudGVkGAIgASgIUgxkcml2ZU1vdW50ZWQSKAoQ'
    'ZHJpdmVfZnJlZV9ieXRlcxgDIAEoBFIOZHJpdmVGcmVlQnl0ZXMSJQoOcmVjb3JkZWRfYnl0ZX'
    'MYBCABKARSDXJlY29yZGVkQnl0ZXMSJwoPcHJvdGVjdGVkX2J5dGVzGAUgASgEUg5wcm90ZWN0'
    'ZWRCeXRlcxIuChNwcm90ZWN0ZWRfbWF4X2J5dGVzGAYgASgEUhFwcm90ZWN0ZWRNYXhCeXRlcx'
    'IyChVjbGlwX3NlZ21lbnRzX3BlbmRpbmcYByABKA1SE2NsaXBTZWdtZW50c1BlbmRpbmcSIwoN'
    'Y2xvY2tfdHJ1c3RlZBgIIAEoCFIMY2xvY2tUcnVzdGVkEhgKB3Byb2JsZW0YCSABKAlSB3Byb2'
    'JsZW0=');

@$core.Deprecated('Use watchRecordingRequestDescriptor instead')
const WatchRecordingRequest$json = {
  '1': 'WatchRecordingRequest',
};

/// Descriptor for `WatchRecordingRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchRecordingRequestDescriptor =
    $convert.base64Decode('ChVXYXRjaFJlY29yZGluZ1JlcXVlc3Q=');

@$core.Deprecated('Use watchRecordingResponseDescriptor instead')
const WatchRecordingResponse$json = {
  '1': 'WatchRecordingResponse',
  '2': [
    {
      '1': 'recording',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.camera.v1.Recording',
      '10': 'recording'
    },
  ],
};

/// Descriptor for `WatchRecordingResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchRecordingResponseDescriptor =
    $convert.base64Decode(
        'ChZXYXRjaFJlY29yZGluZ1Jlc3BvbnNlEjcKCXJlY29yZGluZxgBIAEoCzIZLmYyNTAuY2FtZX'
        'JhLnYxLlJlY29yZGluZ1IJcmVjb3JkaW5n');

@$core.Deprecated('Use saveClipRequestDescriptor instead')
const SaveClipRequest$json = {
  '1': 'SaveClipRequest',
  '2': [
    {'1': 'source', '3': 1, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `SaveClipRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List saveClipRequestDescriptor = $convert
    .base64Decode('Cg9TYXZlQ2xpcFJlcXVlc3QSFgoGc291cmNlGAEgASgJUgZzb3VyY2U=');

@$core.Deprecated('Use saveClipResponseDescriptor instead')
const SaveClipResponse$json = {
  '1': 'SaveClipResponse',
  '2': [
    {'1': 'saved', '3': 1, '4': 1, '5': 8, '10': 'saved'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
    {
      '1': 'segments_protected',
      '3': 3,
      '4': 1,
      '5': 13,
      '10': 'segmentsProtected'
    },
    {'1': 'segments_to_come', '3': 4, '4': 1, '5': 13, '10': 'segmentsToCome'},
  ],
};

/// Descriptor for `SaveClipResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List saveClipResponseDescriptor = $convert.base64Decode(
    'ChBTYXZlQ2xpcFJlc3BvbnNlEhQKBXNhdmVkGAEgASgIUgVzYXZlZBIWCgZkZXRhaWwYAiABKA'
    'lSBmRldGFpbBItChJzZWdtZW50c19wcm90ZWN0ZWQYAyABKA1SEXNlZ21lbnRzUHJvdGVjdGVk'
    'EigKEHNlZ21lbnRzX3RvX2NvbWUYBCABKA1SDnNlZ21lbnRzVG9Db21l');
