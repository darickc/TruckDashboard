// This is a generated file - do not edit.
//
// Generated from f250/export/v1/export.proto.

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

@$core.Deprecated('Use stickRoleDescriptor instead')
const StickRole$json = {
  '1': 'StickRole',
  '2': [
    {'1': 'STICK_ROLE_UNSPECIFIED', '2': 0},
    {'1': 'STICK_ROLE_CHECKING', '2': 1},
    {'1': 'STICK_ROLE_EXPORT', '2': 2},
    {'1': 'STICK_ROLE_MAP', '2': 3},
    {'1': 'STICK_ROLE_UNUSABLE', '2': 4},
  ],
};

/// Descriptor for `StickRole`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List stickRoleDescriptor = $convert.base64Decode(
    'CglTdGlja1JvbGUSGgoWU1RJQ0tfUk9MRV9VTlNQRUNJRklFRBAAEhcKE1NUSUNLX1JPTEVfQ0'
    'hFQ0tJTkcQARIVChFTVElDS19ST0xFX0VYUE9SVBACEhIKDlNUSUNLX1JPTEVfTUFQEAMSFwoT'
    'U1RJQ0tfUk9MRV9VTlVTQUJMRRAE');

@$core.Deprecated('Use copyStateDescriptor instead')
const CopyState$json = {
  '1': 'CopyState',
  '2': [
    {'1': 'COPY_STATE_UNSPECIFIED', '2': 0},
    {'1': 'COPY_STATE_IDLE', '2': 1},
    {'1': 'COPY_STATE_PREPARING', '2': 2},
    {'1': 'COPY_STATE_COPYING', '2': 3},
    {'1': 'COPY_STATE_FINISHING', '2': 4},
    {'1': 'COPY_STATE_DONE', '2': 5},
    {'1': 'COPY_STATE_FAILED', '2': 6},
    {'1': 'COPY_STATE_CANCELLED', '2': 7},
  ],
};

/// Descriptor for `CopyState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List copyStateDescriptor = $convert.base64Decode(
    'CglDb3B5U3RhdGUSGgoWQ09QWV9TVEFURV9VTlNQRUNJRklFRBAAEhMKD0NPUFlfU1RBVEVfSU'
    'RMRRABEhgKFENPUFlfU1RBVEVfUFJFUEFSSU5HEAISFgoSQ09QWV9TVEFURV9DT1BZSU5HEAMS'
    'GAoUQ09QWV9TVEFURV9GSU5JU0hJTkcQBBITCg9DT1BZX1NUQVRFX0RPTkUQBRIVChFDT1BZX1'
    'NUQVRFX0ZBSUxFRBAGEhgKFENPUFlfU1RBVEVfQ0FOQ0VMTEVEEAc=');

@$core.Deprecated('Use recordingDescriptor instead')
const Recording$json = {
  '1': 'Recording',
  '2': [
    {'1': 'camera', '3': 1, '4': 1, '5': 9, '10': 'camera'},
    {'1': 'file_name', '3': 2, '4': 1, '5': 9, '10': 'fileName'},
    {'1': 'protected', '3': 3, '4': 1, '5': 8, '10': 'protected'},
    {'1': 'bytes', '3': 4, '4': 1, '5': 4, '10': 'bytes'},
    {'1': 'boot', '3': 5, '4': 1, '5': 13, '10': 'boot'},
    {'1': 'seq', '3': 6, '4': 1, '5': 13, '10': 'seq'},
    {'1': 'wall_time', '3': 7, '4': 1, '5': 4, '10': 'wallTime'},
    {'1': 'being_written', '3': 8, '4': 1, '5': 8, '10': 'beingWritten'},
  ],
};

/// Descriptor for `Recording`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List recordingDescriptor = $convert.base64Decode(
    'CglSZWNvcmRpbmcSFgoGY2FtZXJhGAEgASgJUgZjYW1lcmESGwoJZmlsZV9uYW1lGAIgASgJUg'
    'hmaWxlTmFtZRIcCglwcm90ZWN0ZWQYAyABKAhSCXByb3RlY3RlZBIUCgVieXRlcxgEIAEoBFIF'
    'Ynl0ZXMSEgoEYm9vdBgFIAEoDVIEYm9vdBIQCgNzZXEYBiABKA1SA3NlcRIbCgl3YWxsX3RpbW'
    'UYByABKARSCHdhbGxUaW1lEiMKDWJlaW5nX3dyaXR0ZW4YCCABKAhSDGJlaW5nV3JpdHRlbg==');

@$core.Deprecated('Use listRecordingsRequestDescriptor instead')
const ListRecordingsRequest$json = {
  '1': 'ListRecordingsRequest',
};

/// Descriptor for `ListRecordingsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listRecordingsRequestDescriptor =
    $convert.base64Decode('ChVMaXN0UmVjb3JkaW5nc1JlcXVlc3Q=');

@$core.Deprecated('Use listRecordingsResponseDescriptor instead')
const ListRecordingsResponse$json = {
  '1': 'ListRecordingsResponse',
  '2': [
    {
      '1': 'recordings',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.f250.export.v1.Recording',
      '10': 'recordings'
    },
    {'1': 'drive_mounted', '3': 2, '4': 1, '5': 8, '10': 'driveMounted'},
    {'1': 'problem', '3': 3, '4': 1, '5': 9, '10': 'problem'},
  ],
};

/// Descriptor for `ListRecordingsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listRecordingsResponseDescriptor = $convert.base64Decode(
    'ChZMaXN0UmVjb3JkaW5nc1Jlc3BvbnNlEjkKCnJlY29yZGluZ3MYASADKAsyGS5mMjUwLmV4cG'
    '9ydC52MS5SZWNvcmRpbmdSCnJlY29yZGluZ3MSIwoNZHJpdmVfbW91bnRlZBgCIAEoCFIMZHJp'
    'dmVNb3VudGVkEhgKB3Byb2JsZW0YAyABKAlSB3Byb2JsZW0=');

@$core.Deprecated('Use stickDescriptor instead')
const Stick$json = {
  '1': 'Stick',
  '2': [
    {'1': 'device', '3': 1, '4': 1, '5': 9, '10': 'device'},
    {'1': 'label', '3': 2, '4': 1, '5': 9, '10': 'label'},
    {'1': 'model', '3': 3, '4': 1, '5': 9, '10': 'model'},
    {'1': 'filesystem', '3': 4, '4': 1, '5': 9, '10': 'filesystem'},
    {
      '1': 'role',
      '3': 5,
      '4': 1,
      '5': 14,
      '6': '.f250.export.v1.StickRole',
      '10': 'role'
    },
    {'1': 'free_bytes', '3': 6, '4': 1, '5': 4, '10': 'freeBytes'},
    {'1': 'total_bytes', '3': 7, '4': 1, '5': 4, '10': 'totalBytes'},
    {'1': 'max_file_bytes', '3': 8, '4': 1, '5': 4, '10': 'maxFileBytes'},
    {'1': 'read_only', '3': 9, '4': 1, '5': 8, '10': 'readOnly'},
    {'1': 'detail', '3': 10, '4': 1, '5': 9, '10': 'detail'},
  ],
};

/// Descriptor for `Stick`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List stickDescriptor = $convert.base64Decode(
    'CgVTdGljaxIWCgZkZXZpY2UYASABKAlSBmRldmljZRIUCgVsYWJlbBgCIAEoCVIFbGFiZWwSFA'
    'oFbW9kZWwYAyABKAlSBW1vZGVsEh4KCmZpbGVzeXN0ZW0YBCABKAlSCmZpbGVzeXN0ZW0SLQoE'
    'cm9sZRgFIAEoDjIZLmYyNTAuZXhwb3J0LnYxLlN0aWNrUm9sZVIEcm9sZRIdCgpmcmVlX2J5dG'
    'VzGAYgASgEUglmcmVlQnl0ZXMSHwoLdG90YWxfYnl0ZXMYByABKARSCnRvdGFsQnl0ZXMSJAoO'
    'bWF4X2ZpbGVfYnl0ZXMYCCABKARSDG1heEZpbGVCeXRlcxIbCglyZWFkX29ubHkYCSABKAhSCH'
    'JlYWRPbmx5EhYKBmRldGFpbBgKIAEoCVIGZGV0YWls');

@$core.Deprecated('Use copyDescriptor instead')
const Copy$json = {
  '1': 'Copy',
  '2': [
    {
      '1': 'state',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.f250.export.v1.CopyState',
      '10': 'state'
    },
    {'1': 'device', '3': 2, '4': 1, '5': 9, '10': 'device'},
    {'1': 'files_total', '3': 3, '4': 1, '5': 13, '10': 'filesTotal'},
    {'1': 'files_done', '3': 4, '4': 1, '5': 13, '10': 'filesDone'},
    {'1': 'files_skipped', '3': 5, '4': 1, '5': 13, '10': 'filesSkipped'},
    {'1': 'files_missing', '3': 6, '4': 1, '5': 13, '10': 'filesMissing'},
    {'1': 'bytes_total', '3': 7, '4': 1, '5': 4, '10': 'bytesTotal'},
    {'1': 'bytes_done', '3': 8, '4': 1, '5': 4, '10': 'bytesDone'},
    {'1': 'current', '3': 9, '4': 1, '5': 9, '10': 'current'},
    {'1': 'detail', '3': 10, '4': 1, '5': 9, '10': 'detail'},
    {'1': 'safe_to_unplug', '3': 11, '4': 1, '5': 8, '10': 'safeToUnplug'},
    {'1': 'folder', '3': 12, '4': 1, '5': 9, '10': 'folder'},
    {'1': 'id', '3': 13, '4': 1, '5': 4, '10': 'id'},
  ],
};

/// Descriptor for `Copy`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List copyDescriptor = $convert.base64Decode(
    'CgRDb3B5Ei8KBXN0YXRlGAEgASgOMhkuZjI1MC5leHBvcnQudjEuQ29weVN0YXRlUgVzdGF0ZR'
    'IWCgZkZXZpY2UYAiABKAlSBmRldmljZRIfCgtmaWxlc190b3RhbBgDIAEoDVIKZmlsZXNUb3Rh'
    'bBIdCgpmaWxlc19kb25lGAQgASgNUglmaWxlc0RvbmUSIwoNZmlsZXNfc2tpcHBlZBgFIAEoDV'
    'IMZmlsZXNTa2lwcGVkEiMKDWZpbGVzX21pc3NpbmcYBiABKA1SDGZpbGVzTWlzc2luZxIfCgti'
    'eXRlc190b3RhbBgHIAEoBFIKYnl0ZXNUb3RhbBIdCgpieXRlc19kb25lGAggASgEUglieXRlc0'
    'RvbmUSGAoHY3VycmVudBgJIAEoCVIHY3VycmVudBIWCgZkZXRhaWwYCiABKAlSBmRldGFpbBIk'
    'Cg5zYWZlX3RvX3VucGx1ZxgLIAEoCFIMc2FmZVRvVW5wbHVnEhYKBmZvbGRlchgMIAEoCVIGZm'
    '9sZGVyEg4KAmlkGA0gASgEUgJpZA==');

@$core.Deprecated('Use watchExportRequestDescriptor instead')
const WatchExportRequest$json = {
  '1': 'WatchExportRequest',
};

/// Descriptor for `WatchExportRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchExportRequestDescriptor =
    $convert.base64Decode('ChJXYXRjaEV4cG9ydFJlcXVlc3Q=');

@$core.Deprecated('Use watchExportResponseDescriptor instead')
const WatchExportResponse$json = {
  '1': 'WatchExportResponse',
  '2': [
    {
      '1': 'sticks',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.f250.export.v1.Stick',
      '10': 'sticks'
    },
    {
      '1': 'copy',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.f250.export.v1.Copy',
      '10': 'copy'
    },
  ],
};

/// Descriptor for `WatchExportResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchExportResponseDescriptor = $convert.base64Decode(
    'ChNXYXRjaEV4cG9ydFJlc3BvbnNlEi0KBnN0aWNrcxgBIAMoCzIVLmYyNTAuZXhwb3J0LnYxLl'
    'N0aWNrUgZzdGlja3MSKAoEY29weRgCIAEoCzIULmYyNTAuZXhwb3J0LnYxLkNvcHlSBGNvcHk=');

@$core.Deprecated('Use recordingRefDescriptor instead')
const RecordingRef$json = {
  '1': 'RecordingRef',
  '2': [
    {'1': 'camera', '3': 1, '4': 1, '5': 9, '10': 'camera'},
    {'1': 'file_name', '3': 2, '4': 1, '5': 9, '10': 'fileName'},
    {'1': 'protected', '3': 3, '4': 1, '5': 8, '10': 'protected'},
  ],
};

/// Descriptor for `RecordingRef`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List recordingRefDescriptor = $convert.base64Decode(
    'CgxSZWNvcmRpbmdSZWYSFgoGY2FtZXJhGAEgASgJUgZjYW1lcmESGwoJZmlsZV9uYW1lGAIgAS'
    'gJUghmaWxlTmFtZRIcCglwcm90ZWN0ZWQYAyABKAhSCXByb3RlY3RlZA==');

@$core.Deprecated('Use startCopyRequestDescriptor instead')
const StartCopyRequest$json = {
  '1': 'StartCopyRequest',
  '2': [
    {'1': 'device', '3': 1, '4': 1, '5': 9, '10': 'device'},
    {
      '1': 'recordings',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.f250.export.v1.RecordingRef',
      '10': 'recordings'
    },
    {'1': 'source', '3': 3, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `StartCopyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startCopyRequestDescriptor = $convert.base64Decode(
    'ChBTdGFydENvcHlSZXF1ZXN0EhYKBmRldmljZRgBIAEoCVIGZGV2aWNlEjwKCnJlY29yZGluZ3'
    'MYAiADKAsyHC5mMjUwLmV4cG9ydC52MS5SZWNvcmRpbmdSZWZSCnJlY29yZGluZ3MSFgoGc291'
    'cmNlGAMgASgJUgZzb3VyY2U=');

@$core.Deprecated('Use startCopyResponseDescriptor instead')
const StartCopyResponse$json = {
  '1': 'StartCopyResponse',
  '2': [
    {'1': 'started', '3': 1, '4': 1, '5': 8, '10': 'started'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
    {'1': 'id', '3': 3, '4': 1, '5': 4, '10': 'id'},
  ],
};

/// Descriptor for `StartCopyResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startCopyResponseDescriptor = $convert.base64Decode(
    'ChFTdGFydENvcHlSZXNwb25zZRIYCgdzdGFydGVkGAEgASgIUgdzdGFydGVkEhYKBmRldGFpbB'
    'gCIAEoCVIGZGV0YWlsEg4KAmlkGAMgASgEUgJpZA==');

@$core.Deprecated('Use cancelCopyRequestDescriptor instead')
const CancelCopyRequest$json = {
  '1': 'CancelCopyRequest',
  '2': [
    {'1': 'source', '3': 1, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `CancelCopyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List cancelCopyRequestDescriptor = $convert.base64Decode(
    'ChFDYW5jZWxDb3B5UmVxdWVzdBIWCgZzb3VyY2UYASABKAlSBnNvdXJjZQ==');

@$core.Deprecated('Use cancelCopyResponseDescriptor instead')
const CancelCopyResponse$json = {
  '1': 'CancelCopyResponse',
  '2': [
    {'1': 'cancelling', '3': 1, '4': 1, '5': 8, '10': 'cancelling'},
  ],
};

/// Descriptor for `CancelCopyResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List cancelCopyResponseDescriptor = $convert.base64Decode(
    'ChJDYW5jZWxDb3B5UmVzcG9uc2USHgoKY2FuY2VsbGluZxgBIAEoCFIKY2FuY2VsbGluZw==');
