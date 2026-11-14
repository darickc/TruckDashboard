// This is a generated file - do not edit.
//
// Generated from f250/audio/v1/audio.proto.

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

@$core.Deprecated('Use bluetoothStateDescriptor instead')
const BluetoothState$json = {
  '1': 'BluetoothState',
  '2': [
    {'1': 'BLUETOOTH_STATE_UNSPECIFIED', '2': 0},
    {'1': 'BLUETOOTH_STATE_READY', '2': 1},
    {'1': 'BLUETOOTH_STATE_UNAVAILABLE', '2': 2},
  ],
};

/// Descriptor for `BluetoothState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List bluetoothStateDescriptor = $convert.base64Decode(
    'Cg5CbHVldG9vdGhTdGF0ZRIfChtCTFVFVE9PVEhfU1RBVEVfVU5TUEVDSUZJRUQQABIZChVCTF'
    'VFVE9PVEhfU1RBVEVfUkVBRFkQARIfChtCTFVFVE9PVEhfU1RBVEVfVU5BVkFJTEFCTEUQAg==');

@$core.Deprecated('Use playStateDescriptor instead')
const PlayState$json = {
  '1': 'PlayState',
  '2': [
    {'1': 'PLAY_STATE_UNSPECIFIED', '2': 0},
    {'1': 'PLAY_STATE_STOPPED', '2': 1},
    {'1': 'PLAY_STATE_PLAYING', '2': 2},
    {'1': 'PLAY_STATE_PAUSED', '2': 3},
    {'1': 'PLAY_STATE_FORWARD_SEEK', '2': 4},
    {'1': 'PLAY_STATE_REVERSE_SEEK', '2': 5},
    {'1': 'PLAY_STATE_ERROR', '2': 6},
  ],
};

/// Descriptor for `PlayState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List playStateDescriptor = $convert.base64Decode(
    'CglQbGF5U3RhdGUSGgoWUExBWV9TVEFURV9VTlNQRUNJRklFRBAAEhYKElBMQVlfU1RBVEVfU1'
    'RPUFBFRBABEhYKElBMQVlfU1RBVEVfUExBWUlORxACEhUKEVBMQVlfU1RBVEVfUEFVU0VEEAMS'
    'GwoXUExBWV9TVEFURV9GT1JXQVJEX1NFRUsQBBIbChdQTEFZX1NUQVRFX1JFVkVSU0VfU0VFSx'
    'AFEhQKEFBMQVlfU1RBVEVfRVJST1IQBg==');

@$core.Deprecated('Use pairingStateDescriptor instead')
const PairingState$json = {
  '1': 'PairingState',
  '2': [
    {'1': 'PAIRING_STATE_UNSPECIFIED', '2': 0},
    {'1': 'PAIRING_STATE_CLOSED', '2': 1},
    {'1': 'PAIRING_STATE_OPENING', '2': 2},
    {'1': 'PAIRING_STATE_OPEN', '2': 3},
    {'1': 'PAIRING_STATE_CLOSING', '2': 4},
    {'1': 'PAIRING_STATE_FAILED', '2': 5},
  ],
};

/// Descriptor for `PairingState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List pairingStateDescriptor = $convert.base64Decode(
    'CgxQYWlyaW5nU3RhdGUSHQoZUEFJUklOR19TVEFURV9VTlNQRUNJRklFRBAAEhgKFFBBSVJJTk'
    'dfU1RBVEVfQ0xPU0VEEAESGQoVUEFJUklOR19TVEFURV9PUEVOSU5HEAISFgoSUEFJUklOR19T'
    'VEFURV9PUEVOEAMSGQoVUEFJUklOR19TVEFURV9DTE9TSU5HEAQSGAoUUEFJUklOR19TVEFURV'
    '9GQUlMRUQQBQ==');

@$core.Deprecated('Use dspStateDescriptor instead')
const DspState$json = {
  '1': 'DspState',
  '2': [
    {'1': 'DSP_STATE_UNSPECIFIED', '2': 0},
    {'1': 'DSP_STATE_APPLIED', '2': 1},
    {'1': 'DSP_STATE_STARTING', '2': 2},
    {'1': 'DSP_STATE_NOT_RUNNING', '2': 3},
  ],
};

/// Descriptor for `DspState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List dspStateDescriptor = $convert.base64Decode(
    'CghEc3BTdGF0ZRIZChVEU1BfU1RBVEVfVU5TUEVDSUZJRUQQABIVChFEU1BfU1RBVEVfQVBQTE'
    'lFRBABEhYKEkRTUF9TVEFURV9TVEFSVElORxACEhkKFURTUF9TVEFURV9OT1RfUlVOTklORxAD');

@$core.Deprecated('Use callStateDescriptor instead')
const CallState$json = {
  '1': 'CallState',
  '2': [
    {'1': 'CALL_STATE_UNSPECIFIED', '2': 0},
    {'1': 'CALL_STATE_INCOMING', '2': 1},
    {'1': 'CALL_STATE_WAITING', '2': 2},
    {'1': 'CALL_STATE_DIALING', '2': 3},
    {'1': 'CALL_STATE_ALERTING', '2': 4},
    {'1': 'CALL_STATE_ACTIVE', '2': 5},
    {'1': 'CALL_STATE_HELD', '2': 6},
  ],
};

/// Descriptor for `CallState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List callStateDescriptor = $convert.base64Decode(
    'CglDYWxsU3RhdGUSGgoWQ0FMTF9TVEFURV9VTlNQRUNJRklFRBAAEhcKE0NBTExfU1RBVEVfSU'
    '5DT01JTkcQARIWChJDQUxMX1NUQVRFX1dBSVRJTkcQAhIWChJDQUxMX1NUQVRFX0RJQUxJTkcQ'
    'AxIXChNDQUxMX1NUQVRFX0FMRVJUSU5HEAQSFQoRQ0FMTF9TVEFURV9BQ1RJVkUQBRITCg9DQU'
    'xMX1NUQVRFX0hFTEQQBg==');

@$core.Deprecated('Use commandDescriptor instead')
const Command$json = {
  '1': 'Command',
  '2': [
    {'1': 'COMMAND_UNSPECIFIED', '2': 0},
    {'1': 'COMMAND_PLAY', '2': 1},
    {'1': 'COMMAND_PAUSE', '2': 2},
    {'1': 'COMMAND_NEXT', '2': 3},
    {'1': 'COMMAND_PREVIOUS', '2': 4},
  ],
};

/// Descriptor for `Command`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List commandDescriptor = $convert.base64Decode(
    'CgdDb21tYW5kEhcKE0NPTU1BTkRfVU5TUEVDSUZJRUQQABIQCgxDT01NQU5EX1BMQVkQARIRCg'
    '1DT01NQU5EX1BBVVNFEAISEAoMQ09NTUFORF9ORVhUEAMSFAoQQ09NTUFORF9QUkVWSU9VUxAE');

@$core.Deprecated('Use muteChangeDescriptor instead')
const MuteChange$json = {
  '1': 'MuteChange',
  '2': [
    {'1': 'MUTE_CHANGE_UNSPECIFIED', '2': 0},
    {'1': 'MUTE_CHANGE_MUTE', '2': 1},
    {'1': 'MUTE_CHANGE_UNMUTE', '2': 2},
    {'1': 'MUTE_CHANGE_TOGGLE', '2': 3},
  ],
};

/// Descriptor for `MuteChange`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List muteChangeDescriptor = $convert.base64Decode(
    'CgpNdXRlQ2hhbmdlEhsKF01VVEVfQ0hBTkdFX1VOU1BFQ0lGSUVEEAASFAoQTVVURV9DSEFOR0'
    'VfTVVURRABEhYKEk1VVEVfQ0hBTkdFX1VOTVVURRACEhYKEk1VVEVfQ0hBTkdFX1RPR0dMRRAD');

@$core.Deprecated('Use watchAudioRequestDescriptor instead')
const WatchAudioRequest$json = {
  '1': 'WatchAudioRequest',
};

/// Descriptor for `WatchAudioRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchAudioRequestDescriptor =
    $convert.base64Decode('ChFXYXRjaEF1ZGlvUmVxdWVzdA==');

@$core.Deprecated('Use phoneDescriptor instead')
const Phone$json = {
  '1': 'Phone',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'connected', '3': 3, '4': 1, '5': 8, '10': 'connected'},
    {'1': 'paired', '3': 4, '4': 1, '5': 8, '10': 'paired'},
    {'1': 'last', '3': 5, '4': 1, '5': 8, '10': 'last'},
  ],
};

/// Descriptor for `Phone`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List phoneDescriptor = $convert.base64Decode(
    'CgVQaG9uZRIYCgdhZGRyZXNzGAEgASgJUgdhZGRyZXNzEhIKBG5hbWUYAiABKAlSBG5hbWUSHA'
    'oJY29ubmVjdGVkGAMgASgIUgljb25uZWN0ZWQSFgoGcGFpcmVkGAQgASgIUgZwYWlyZWQSEgoE'
    'bGFzdBgFIAEoCFIEbGFzdA==');

@$core.Deprecated('Use connectAttemptDescriptor instead')
const ConnectAttempt$json = {
  '1': 'ConnectAttempt',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'automatic', '3': 3, '4': 1, '5': 8, '10': 'automatic'},
    {'1': 'detail', '3': 4, '4': 1, '5': 9, '10': 'detail'},
  ],
};

/// Descriptor for `ConnectAttempt`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List connectAttemptDescriptor = $convert.base64Decode(
    'Cg5Db25uZWN0QXR0ZW1wdBIYCgdhZGRyZXNzGAEgASgJUgdhZGRyZXNzEhIKBG5hbWUYAiABKA'
    'lSBG5hbWUSHAoJYXV0b21hdGljGAMgASgIUglhdXRvbWF0aWMSFgoGZGV0YWlsGAQgASgJUgZk'
    'ZXRhaWw=');

@$core.Deprecated('Use nowPlayingDescriptor instead')
const NowPlaying$json = {
  '1': 'NowPlaying',
  '2': [
    {'1': 'title', '3': 1, '4': 1, '5': 9, '10': 'title'},
    {'1': 'artist', '3': 2, '4': 1, '5': 9, '10': 'artist'},
    {'1': 'album', '3': 3, '4': 1, '5': 9, '10': 'album'},
    {
      '1': 'state',
      '3': 4,
      '4': 1,
      '5': 14,
      '6': '.f250.audio.v1.PlayState',
      '10': 'state'
    },
    {'1': 'duration_ms', '3': 5, '4': 1, '5': 13, '10': 'durationMs'},
    {'1': 'has_position', '3': 6, '4': 1, '5': 8, '10': 'hasPosition'},
    {'1': 'position_ms', '3': 7, '4': 1, '5': 13, '10': 'positionMs'},
    {'1': 'player_name', '3': 8, '4': 1, '5': 9, '10': 'playerName'},
    {'1': 'cover_art_id', '3': 9, '4': 1, '5': 9, '10': 'coverArtId'},
    {'1': 'cover_art_detail', '3': 10, '4': 1, '5': 9, '10': 'coverArtDetail'},
  ],
};

/// Descriptor for `NowPlaying`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List nowPlayingDescriptor = $convert.base64Decode(
    'CgpOb3dQbGF5aW5nEhQKBXRpdGxlGAEgASgJUgV0aXRsZRIWCgZhcnRpc3QYAiABKAlSBmFydG'
    'lzdBIUCgVhbGJ1bRgDIAEoCVIFYWxidW0SLgoFc3RhdGUYBCABKA4yGC5mMjUwLmF1ZGlvLnYx'
    'LlBsYXlTdGF0ZVIFc3RhdGUSHwoLZHVyYXRpb25fbXMYBSABKA1SCmR1cmF0aW9uTXMSIQoMaG'
    'FzX3Bvc2l0aW9uGAYgASgIUgtoYXNQb3NpdGlvbhIfCgtwb3NpdGlvbl9tcxgHIAEoDVIKcG9z'
    'aXRpb25NcxIfCgtwbGF5ZXJfbmFtZRgIIAEoCVIKcGxheWVyTmFtZRIgCgxjb3Zlcl9hcnRfaW'
    'QYCSABKAlSCmNvdmVyQXJ0SWQSKAoQY292ZXJfYXJ0X2RldGFpbBgKIAEoCVIOY292ZXJBcnRE'
    'ZXRhaWw=');

@$core.Deprecated('Use passkeyQuestionDescriptor instead')
const PasskeyQuestion$json = {
  '1': 'PasskeyQuestion',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 4, '10': 'id'},
    {'1': 'phone_name', '3': 2, '4': 1, '5': 9, '10': 'phoneName'},
    {'1': 'address', '3': 3, '4': 1, '5': 9, '10': 'address'},
    {'1': 'passkey', '3': 4, '4': 1, '5': 13, '10': 'passkey'},
    {'1': 'seconds_left', '3': 5, '4': 1, '5': 13, '10': 'secondsLeft'},
    {'1': 'shows_passkey', '3': 6, '4': 1, '5': 8, '10': 'showsPasskey'},
  ],
};

/// Descriptor for `PasskeyQuestion`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List passkeyQuestionDescriptor = $convert.base64Decode(
    'Cg9QYXNza2V5UXVlc3Rpb24SDgoCaWQYASABKARSAmlkEh0KCnBob25lX25hbWUYAiABKAlSCX'
    'Bob25lTmFtZRIYCgdhZGRyZXNzGAMgASgJUgdhZGRyZXNzEhgKB3Bhc3NrZXkYBCABKA1SB3Bh'
    'c3NrZXkSIQoMc2Vjb25kc19sZWZ0GAUgASgNUgtzZWNvbmRzTGVmdBIjCg1zaG93c19wYXNza2'
    'V5GAYgASgIUgxzaG93c1Bhc3NrZXk=');

@$core.Deprecated('Use pairingDescriptor instead')
const Pairing$json = {
  '1': 'Pairing',
  '2': [
    {
      '1': 'state',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.f250.audio.v1.PairingState',
      '10': 'state'
    },
    {'1': 'seconds_left', '3': 2, '4': 1, '5': 13, '10': 'secondsLeft'},
    {'1': 'detail', '3': 3, '4': 1, '5': 9, '10': 'detail'},
    {
      '1': 'question',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.f250.audio.v1.PasskeyQuestion',
      '10': 'question'
    },
    {'1': 'name', '3': 5, '4': 1, '5': 9, '10': 'name'},
  ],
};

/// Descriptor for `Pairing`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pairingDescriptor = $convert.base64Decode(
    'CgdQYWlyaW5nEjEKBXN0YXRlGAEgASgOMhsuZjI1MC5hdWRpby52MS5QYWlyaW5nU3RhdGVSBX'
    'N0YXRlEiEKDHNlY29uZHNfbGVmdBgCIAEoDVILc2Vjb25kc0xlZnQSFgoGZGV0YWlsGAMgASgJ'
    'UgZkZXRhaWwSOgoIcXVlc3Rpb24YBCABKAsyHi5mMjUwLmF1ZGlvLnYxLlBhc3NrZXlRdWVzdG'
    'lvblIIcXVlc3Rpb24SEgoEbmFtZRgFIAEoCVIEbmFtZQ==');

@$core.Deprecated('Use watchAudioResponseDescriptor instead')
const WatchAudioResponse$json = {
  '1': 'WatchAudioResponse',
  '2': [
    {
      '1': 'bluetooth',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.f250.audio.v1.BluetoothState',
      '10': 'bluetooth'
    },
    {'1': 'bluetooth_detail', '3': 2, '4': 1, '5': 9, '10': 'bluetoothDetail'},
    {
      '1': 'phone',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.f250.audio.v1.Phone',
      '10': 'phone'
    },
    {
      '1': 'known',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.f250.audio.v1.Phone',
      '10': 'known'
    },
    {
      '1': 'now_playing',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.f250.audio.v1.NowPlaying',
      '10': 'nowPlaying'
    },
    {'1': 'streaming', '3': 6, '4': 1, '5': 8, '10': 'streaming'},
    {
      '1': 'pairing',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.f250.audio.v1.Pairing',
      '10': 'pairing'
    },
    {
      '1': 'dsp',
      '3': 8,
      '4': 1,
      '5': 14,
      '6': '.f250.audio.v1.DspState',
      '10': 'dsp'
    },
    {'1': 'dsp_detail', '3': 9, '4': 1, '5': 9, '10': 'dspDetail'},
    {'1': 'simulated', '3': 10, '4': 1, '5': 8, '10': 'simulated'},
    {
      '1': 'prompts',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.f250.audio.v1.Prompts',
      '10': 'prompts'
    },
    {
      '1': 'connect',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.f250.audio.v1.ConnectAttempt',
      '10': 'connect'
    },
    {
      '1': 'volume',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.f250.audio.v1.Volume',
      '10': 'volume'
    },
    {
      '1': 'calls',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.f250.audio.v1.Calls',
      '10': 'calls'
    },
  ],
};

/// Descriptor for `WatchAudioResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchAudioResponseDescriptor = $convert.base64Decode(
    'ChJXYXRjaEF1ZGlvUmVzcG9uc2USOwoJYmx1ZXRvb3RoGAEgASgOMh0uZjI1MC5hdWRpby52MS'
    '5CbHVldG9vdGhTdGF0ZVIJYmx1ZXRvb3RoEikKEGJsdWV0b290aF9kZXRhaWwYAiABKAlSD2Js'
    'dWV0b290aERldGFpbBIqCgVwaG9uZRgDIAEoCzIULmYyNTAuYXVkaW8udjEuUGhvbmVSBXBob2'
    '5lEioKBWtub3duGAQgAygLMhQuZjI1MC5hdWRpby52MS5QaG9uZVIFa25vd24SOgoLbm93X3Bs'
    'YXlpbmcYBSABKAsyGS5mMjUwLmF1ZGlvLnYxLk5vd1BsYXlpbmdSCm5vd1BsYXlpbmcSHAoJc3'
    'RyZWFtaW5nGAYgASgIUglzdHJlYW1pbmcSMAoHcGFpcmluZxgHIAEoCzIWLmYyNTAuYXVkaW8u'
    'djEuUGFpcmluZ1IHcGFpcmluZxIpCgNkc3AYCCABKA4yFy5mMjUwLmF1ZGlvLnYxLkRzcFN0YX'
    'RlUgNkc3ASHQoKZHNwX2RldGFpbBgJIAEoCVIJZHNwRGV0YWlsEhwKCXNpbXVsYXRlZBgKIAEo'
    'CFIJc2ltdWxhdGVkEjAKB3Byb21wdHMYCyABKAsyFi5mMjUwLmF1ZGlvLnYxLlByb21wdHNSB3'
    'Byb21wdHMSNwoHY29ubmVjdBgMIAEoCzIdLmYyNTAuYXVkaW8udjEuQ29ubmVjdEF0dGVtcHRS'
    'B2Nvbm5lY3QSLQoGdm9sdW1lGA0gASgLMhUuZjI1MC5hdWRpby52MS5Wb2x1bWVSBnZvbHVtZR'
    'IqCgVjYWxscxgOIAEoCzIULmYyNTAuYXVkaW8udjEuQ2FsbHNSBWNhbGxz');

@$core.Deprecated('Use callDescriptor instead')
const Call$json = {
  '1': 'Call',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 4, '10': 'id'},
    {
      '1': 'state',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.f250.audio.v1.CallState',
      '10': 'state'
    },
    {'1': 'number', '3': 3, '4': 1, '5': 9, '10': 'number'},
    {'1': 'name', '3': 4, '4': 1, '5': 9, '10': 'name'},
    {'1': 'withheld', '3': 5, '4': 1, '5': 8, '10': 'withheld'},
    {'1': 'active_s', '3': 6, '4': 1, '5': 13, '10': 'activeS'},
    {'1': 'multiparty', '3': 7, '4': 1, '5': 8, '10': 'multiparty'},
  ],
};

/// Descriptor for `Call`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callDescriptor = $convert.base64Decode(
    'CgRDYWxsEg4KAmlkGAEgASgEUgJpZBIuCgVzdGF0ZRgCIAEoDjIYLmYyNTAuYXVkaW8udjEuQ2'
    'FsbFN0YXRlUgVzdGF0ZRIWCgZudW1iZXIYAyABKAlSBm51bWJlchISCgRuYW1lGAQgASgJUgRu'
    'YW1lEhoKCHdpdGhoZWxkGAUgASgIUgh3aXRoaGVsZBIZCghhY3RpdmVfcxgGIAEoDVIHYWN0aX'
    'ZlUxIeCgptdWx0aXBhcnR5GAcgASgIUgptdWx0aXBhcnR5');

@$core.Deprecated('Use callsDescriptor instead')
const Calls$json = {
  '1': 'Calls',
  '2': [
    {'1': 'available', '3': 1, '4': 1, '5': 8, '10': 'available'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
    {
      '1': 'call',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.f250.audio.v1.Call',
      '10': 'call'
    },
    {'1': 'other_calls', '3': 4, '4': 1, '5': 13, '10': 'otherCalls'},
    {'1': 'mic_muted', '3': 5, '4': 1, '5': 8, '10': 'micMuted'},
    {'1': 'phone_name', '3': 6, '4': 1, '5': 9, '10': 'phoneName'},
  ],
};

/// Descriptor for `Calls`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callsDescriptor = $convert.base64Decode(
    'CgVDYWxscxIcCglhdmFpbGFibGUYASABKAhSCWF2YWlsYWJsZRIWCgZkZXRhaWwYAiABKAlSBm'
    'RldGFpbBInCgRjYWxsGAMgASgLMhMuZjI1MC5hdWRpby52MS5DYWxsUgRjYWxsEh8KC290aGVy'
    'X2NhbGxzGAQgASgNUgpvdGhlckNhbGxzEhsKCW1pY19tdXRlZBgFIAEoCFIIbWljTXV0ZWQSHQ'
    'oKcGhvbmVfbmFtZRgGIAEoCVIJcGhvbmVOYW1l');

@$core.Deprecated('Use promptsDescriptor instead')
const Prompts$json = {
  '1': 'Prompts',
  '2': [
    {'1': 'available', '3': 1, '4': 1, '5': 8, '10': 'available'},
    {'1': 'speaking', '3': 2, '4': 1, '5': 8, '10': 'speaking'},
    {'1': 'music_paused', '3': 3, '4': 1, '5': 8, '10': 'musicPaused'},
    {'1': 'detail', '3': 4, '4': 1, '5': 9, '10': 'detail'},
  ],
};

/// Descriptor for `Prompts`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List promptsDescriptor = $convert.base64Decode(
    'CgdQcm9tcHRzEhwKCWF2YWlsYWJsZRgBIAEoCFIJYXZhaWxhYmxlEhoKCHNwZWFraW5nGAIgAS'
    'gIUghzcGVha2luZxIhCgxtdXNpY19wYXVzZWQYAyABKAhSC211c2ljUGF1c2VkEhYKBmRldGFp'
    'bBgEIAEoCVIGZGV0YWls');

@$core.Deprecated('Use controlRequestDescriptor instead')
const ControlRequest$json = {
  '1': 'ControlRequest',
  '2': [
    {
      '1': 'command',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.f250.audio.v1.Command',
      '10': 'command'
    },
    {'1': 'source', '3': 2, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `ControlRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List controlRequestDescriptor = $convert.base64Decode(
    'Cg5Db250cm9sUmVxdWVzdBIwCgdjb21tYW5kGAEgASgOMhYuZjI1MC5hdWRpby52MS5Db21tYW'
    '5kUgdjb21tYW5kEhYKBnNvdXJjZRgCIAEoCVIGc291cmNl');

@$core.Deprecated('Use controlResponseDescriptor instead')
const ControlResponse$json = {
  '1': 'ControlResponse',
  '2': [
    {'1': 'sent', '3': 1, '4': 1, '5': 8, '10': 'sent'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
  ],
};

/// Descriptor for `ControlResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List controlResponseDescriptor = $convert.base64Decode(
    'Cg9Db250cm9sUmVzcG9uc2USEgoEc2VudBgBIAEoCFIEc2VudBIWCgZkZXRhaWwYAiABKAlSBm'
    'RldGFpbA==');

@$core.Deprecated('Use openPairingRequestDescriptor instead')
const OpenPairingRequest$json = {
  '1': 'OpenPairingRequest',
  '2': [
    {'1': 'seconds', '3': 1, '4': 1, '5': 13, '10': 'seconds'},
    {'1': 'source', '3': 2, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `OpenPairingRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List openPairingRequestDescriptor = $convert.base64Decode(
    'ChJPcGVuUGFpcmluZ1JlcXVlc3QSGAoHc2Vjb25kcxgBIAEoDVIHc2Vjb25kcxIWCgZzb3VyY2'
    'UYAiABKAlSBnNvdXJjZQ==');

@$core.Deprecated('Use openPairingResponseDescriptor instead')
const OpenPairingResponse$json = {
  '1': 'OpenPairingResponse',
  '2': [
    {'1': 'accepted', '3': 1, '4': 1, '5': 8, '10': 'accepted'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
  ],
};

/// Descriptor for `OpenPairingResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List openPairingResponseDescriptor = $convert.base64Decode(
    'ChNPcGVuUGFpcmluZ1Jlc3BvbnNlEhoKCGFjY2VwdGVkGAEgASgIUghhY2NlcHRlZBIWCgZkZX'
    'RhaWwYAiABKAlSBmRldGFpbA==');

@$core.Deprecated('Use closePairingRequestDescriptor instead')
const ClosePairingRequest$json = {
  '1': 'ClosePairingRequest',
  '2': [
    {'1': 'source', '3': 1, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `ClosePairingRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List closePairingRequestDescriptor =
    $convert.base64Decode(
        'ChNDbG9zZVBhaXJpbmdSZXF1ZXN0EhYKBnNvdXJjZRgBIAEoCVIGc291cmNl');

@$core.Deprecated('Use closePairingResponseDescriptor instead')
const ClosePairingResponse$json = {
  '1': 'ClosePairingResponse',
  '2': [
    {'1': 'closing', '3': 1, '4': 1, '5': 8, '10': 'closing'},
  ],
};

/// Descriptor for `ClosePairingResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List closePairingResponseDescriptor =
    $convert.base64Decode(
        'ChRDbG9zZVBhaXJpbmdSZXNwb25zZRIYCgdjbG9zaW5nGAEgASgIUgdjbG9zaW5n');

@$core.Deprecated('Use connectPhoneRequestDescriptor instead')
const ConnectPhoneRequest$json = {
  '1': 'ConnectPhoneRequest',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
    {'1': 'source', '3': 2, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `ConnectPhoneRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List connectPhoneRequestDescriptor = $convert.base64Decode(
    'ChNDb25uZWN0UGhvbmVSZXF1ZXN0EhgKB2FkZHJlc3MYASABKAlSB2FkZHJlc3MSFgoGc291cm'
    'NlGAIgASgJUgZzb3VyY2U=');

@$core.Deprecated('Use connectPhoneResponseDescriptor instead')
const ConnectPhoneResponse$json = {
  '1': 'ConnectPhoneResponse',
  '2': [
    {'1': 'accepted', '3': 1, '4': 1, '5': 8, '10': 'accepted'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
  ],
};

/// Descriptor for `ConnectPhoneResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List connectPhoneResponseDescriptor = $convert.base64Decode(
    'ChRDb25uZWN0UGhvbmVSZXNwb25zZRIaCghhY2NlcHRlZBgBIAEoCFIIYWNjZXB0ZWQSFgoGZG'
    'V0YWlsGAIgASgJUgZkZXRhaWw=');

@$core.Deprecated('Use disconnectPhoneRequestDescriptor instead')
const DisconnectPhoneRequest$json = {
  '1': 'DisconnectPhoneRequest',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
    {'1': 'source', '3': 2, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `DisconnectPhoneRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List disconnectPhoneRequestDescriptor =
    $convert.base64Decode(
        'ChZEaXNjb25uZWN0UGhvbmVSZXF1ZXN0EhgKB2FkZHJlc3MYASABKAlSB2FkZHJlc3MSFgoGc2'
        '91cmNlGAIgASgJUgZzb3VyY2U=');

@$core.Deprecated('Use disconnectPhoneResponseDescriptor instead')
const DisconnectPhoneResponse$json = {
  '1': 'DisconnectPhoneResponse',
  '2': [
    {'1': 'accepted', '3': 1, '4': 1, '5': 8, '10': 'accepted'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
  ],
};

/// Descriptor for `DisconnectPhoneResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List disconnectPhoneResponseDescriptor =
    $convert.base64Decode(
        'ChdEaXNjb25uZWN0UGhvbmVSZXNwb25zZRIaCghhY2NlcHRlZBgBIAEoCFIIYWNjZXB0ZWQSFg'
        'oGZGV0YWlsGAIgASgJUgZkZXRhaWw=');

@$core.Deprecated('Use forgetPhoneRequestDescriptor instead')
const ForgetPhoneRequest$json = {
  '1': 'ForgetPhoneRequest',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
    {'1': 'source', '3': 2, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `ForgetPhoneRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List forgetPhoneRequestDescriptor = $convert.base64Decode(
    'ChJGb3JnZXRQaG9uZVJlcXVlc3QSGAoHYWRkcmVzcxgBIAEoCVIHYWRkcmVzcxIWCgZzb3VyY2'
    'UYAiABKAlSBnNvdXJjZQ==');

@$core.Deprecated('Use forgetPhoneResponseDescriptor instead')
const ForgetPhoneResponse$json = {
  '1': 'ForgetPhoneResponse',
  '2': [
    {'1': 'accepted', '3': 1, '4': 1, '5': 8, '10': 'accepted'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
  ],
};

/// Descriptor for `ForgetPhoneResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List forgetPhoneResponseDescriptor = $convert.base64Decode(
    'ChNGb3JnZXRQaG9uZVJlc3BvbnNlEhoKCGFjY2VwdGVkGAEgASgIUghhY2NlcHRlZBIWCgZkZX'
    'RhaWwYAiABKAlSBmRldGFpbA==');

@$core.Deprecated('Use confirmPairingRequestDescriptor instead')
const ConfirmPairingRequest$json = {
  '1': 'ConfirmPairingRequest',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 4, '10': 'id'},
    {'1': 'accept', '3': 2, '4': 1, '5': 8, '10': 'accept'},
    {'1': 'source', '3': 3, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `ConfirmPairingRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List confirmPairingRequestDescriptor = $convert.base64Decode(
    'ChVDb25maXJtUGFpcmluZ1JlcXVlc3QSDgoCaWQYASABKARSAmlkEhYKBmFjY2VwdBgCIAEoCF'
    'IGYWNjZXB0EhYKBnNvdXJjZRgDIAEoCVIGc291cmNl');

@$core.Deprecated('Use confirmPairingResponseDescriptor instead')
const ConfirmPairingResponse$json = {
  '1': 'ConfirmPairingResponse',
  '2': [
    {'1': 'answered', '3': 1, '4': 1, '5': 8, '10': 'answered'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
  ],
};

/// Descriptor for `ConfirmPairingResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List confirmPairingResponseDescriptor =
    $convert.base64Decode(
        'ChZDb25maXJtUGFpcmluZ1Jlc3BvbnNlEhoKCGFuc3dlcmVkGAEgASgIUghhbnN3ZXJlZBIWCg'
        'ZkZXRhaWwYAiABKAlSBmRldGFpbA==');

@$core.Deprecated('Use speakerSettingsDescriptor instead')
const SpeakerSettings$json = {
  '1': 'SpeakerSettings',
  '2': [
    {'1': 'fader', '3': 1, '4': 1, '5': 5, '10': 'fader'},
    {'1': 'balance', '3': 2, '4': 1, '5': 5, '10': 'balance'},
    {'1': 'sub_level_db', '3': 3, '4': 1, '5': 5, '10': 'subLevelDb'},
    {'1': 'crossover_hz', '3': 4, '4': 1, '5': 13, '10': 'crossoverHz'},
  ],
};

/// Descriptor for `SpeakerSettings`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List speakerSettingsDescriptor = $convert.base64Decode(
    'Cg9TcGVha2VyU2V0dGluZ3MSFAoFZmFkZXIYASABKAVSBWZhZGVyEhgKB2JhbGFuY2UYAiABKA'
    'VSB2JhbGFuY2USIAoMc3ViX2xldmVsX2RiGAMgASgFUgpzdWJMZXZlbERiEiEKDGNyb3Nzb3Zl'
    'cl9oehgEIAEoDVILY3Jvc3NvdmVySHo=');

@$core.Deprecated('Use speakerLimitsDescriptor instead')
const SpeakerLimits$json = {
  '1': 'SpeakerLimits',
  '2': [
    {'1': 'steps', '3': 1, '4': 1, '5': 5, '10': 'steps'},
    {'1': 'step_db', '3': 2, '4': 1, '5': 2, '10': 'stepDb'},
    {'1': 'sub_min_db', '3': 3, '4': 1, '5': 5, '10': 'subMinDb'},
    {'1': 'sub_max_db', '3': 4, '4': 1, '5': 5, '10': 'subMaxDb'},
    {'1': 'crossover_min_hz', '3': 5, '4': 1, '5': 13, '10': 'crossoverMinHz'},
    {'1': 'crossover_max_hz', '3': 6, '4': 1, '5': 13, '10': 'crossoverMaxHz'},
    {
      '1': 'crossover_step_hz',
      '3': 7,
      '4': 1,
      '5': 13,
      '10': 'crossoverStepHz'
    },
  ],
};

/// Descriptor for `SpeakerLimits`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List speakerLimitsDescriptor = $convert.base64Decode(
    'Cg1TcGVha2VyTGltaXRzEhQKBXN0ZXBzGAEgASgFUgVzdGVwcxIXCgdzdGVwX2RiGAIgASgCUg'
    'ZzdGVwRGISHAoKc3ViX21pbl9kYhgDIAEoBVIIc3ViTWluRGISHAoKc3ViX21heF9kYhgEIAEo'
    'BVIIc3ViTWF4RGISKAoQY3Jvc3NvdmVyX21pbl9oehgFIAEoDVIOY3Jvc3NvdmVyTWluSHoSKA'
    'oQY3Jvc3NvdmVyX21heF9oehgGIAEoDVIOY3Jvc3NvdmVyTWF4SHoSKgoRY3Jvc3NvdmVyX3N0'
    'ZXBfaHoYByABKA1SD2Nyb3Nzb3ZlclN0ZXBIeg==');

@$core.Deprecated('Use getSpeakerSettingsRequestDescriptor instead')
const GetSpeakerSettingsRequest$json = {
  '1': 'GetSpeakerSettingsRequest',
};

/// Descriptor for `GetSpeakerSettingsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getSpeakerSettingsRequestDescriptor =
    $convert.base64Decode('ChlHZXRTcGVha2VyU2V0dGluZ3NSZXF1ZXN0');

@$core.Deprecated('Use getSpeakerSettingsResponseDescriptor instead')
const GetSpeakerSettingsResponse$json = {
  '1': 'GetSpeakerSettingsResponse',
  '2': [
    {
      '1': 'settings',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.audio.v1.SpeakerSettings',
      '10': 'settings'
    },
    {
      '1': 'limits',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.f250.audio.v1.SpeakerLimits',
      '10': 'limits'
    },
    {
      '1': 'defaults',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.f250.audio.v1.SpeakerSettings',
      '10': 'defaults'
    },
  ],
};

/// Descriptor for `GetSpeakerSettingsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getSpeakerSettingsResponseDescriptor = $convert.base64Decode(
    'ChpHZXRTcGVha2VyU2V0dGluZ3NSZXNwb25zZRI6CghzZXR0aW5ncxgBIAEoCzIeLmYyNTAuYX'
    'VkaW8udjEuU3BlYWtlclNldHRpbmdzUghzZXR0aW5ncxI0CgZsaW1pdHMYAiABKAsyHC5mMjUw'
    'LmF1ZGlvLnYxLlNwZWFrZXJMaW1pdHNSBmxpbWl0cxI6CghkZWZhdWx0cxgDIAEoCzIeLmYyNT'
    'AuYXVkaW8udjEuU3BlYWtlclNldHRpbmdzUghkZWZhdWx0cw==');

@$core.Deprecated('Use setSpeakerSettingsRequestDescriptor instead')
const SetSpeakerSettingsRequest$json = {
  '1': 'SetSpeakerSettingsRequest',
  '2': [
    {
      '1': 'settings',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.audio.v1.SpeakerSettings',
      '10': 'settings'
    },
    {'1': 'source', '3': 2, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `SetSpeakerSettingsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setSpeakerSettingsRequestDescriptor = $convert.base64Decode(
    'ChlTZXRTcGVha2VyU2V0dGluZ3NSZXF1ZXN0EjoKCHNldHRpbmdzGAEgASgLMh4uZjI1MC5hdW'
    'Rpby52MS5TcGVha2VyU2V0dGluZ3NSCHNldHRpbmdzEhYKBnNvdXJjZRgCIAEoCVIGc291cmNl');

@$core.Deprecated('Use setSpeakerSettingsResponseDescriptor instead')
const SetSpeakerSettingsResponse$json = {
  '1': 'SetSpeakerSettingsResponse',
  '2': [
    {'1': 'applied', '3': 1, '4': 1, '5': 8, '10': 'applied'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
    {
      '1': 'settings',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.f250.audio.v1.SpeakerSettings',
      '10': 'settings'
    },
  ],
};

/// Descriptor for `SetSpeakerSettingsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setSpeakerSettingsResponseDescriptor =
    $convert.base64Decode(
        'ChpTZXRTcGVha2VyU2V0dGluZ3NSZXNwb25zZRIYCgdhcHBsaWVkGAEgASgIUgdhcHBsaWVkEh'
        'YKBmRldGFpbBgCIAEoCVIGZGV0YWlsEjoKCHNldHRpbmdzGAMgASgLMh4uZjI1MC5hdWRpby52'
        'MS5TcGVha2VyU2V0dGluZ3NSCHNldHRpbmdz');

@$core.Deprecated('Use speakRequestDescriptor instead')
const SpeakRequest$json = {
  '1': 'SpeakRequest',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'source', '3': 2, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `SpeakRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List speakRequestDescriptor = $convert.base64Decode(
    'CgxTcGVha1JlcXVlc3QSEgoEdGV4dBgBIAEoCVIEdGV4dBIWCgZzb3VyY2UYAiABKAlSBnNvdX'
    'JjZQ==');

@$core.Deprecated('Use speakResponseDescriptor instead')
const SpeakResponse$json = {
  '1': 'SpeakResponse',
  '2': [
    {'1': 'accepted', '3': 1, '4': 1, '5': 8, '10': 'accepted'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
  ],
};

/// Descriptor for `SpeakResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List speakResponseDescriptor = $convert.base64Decode(
    'Cg1TcGVha1Jlc3BvbnNlEhoKCGFjY2VwdGVkGAEgASgIUghhY2NlcHRlZBIWCgZkZXRhaWwYAi'
    'ABKAlSBmRldGFpbA==');

@$core.Deprecated('Use stopSpeakingRequestDescriptor instead')
const StopSpeakingRequest$json = {
  '1': 'StopSpeakingRequest',
  '2': [
    {'1': 'source', '3': 1, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `StopSpeakingRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List stopSpeakingRequestDescriptor =
    $convert.base64Decode(
        'ChNTdG9wU3BlYWtpbmdSZXF1ZXN0EhYKBnNvdXJjZRgBIAEoCVIGc291cmNl');

@$core.Deprecated('Use stopSpeakingResponseDescriptor instead')
const StopSpeakingResponse$json = {
  '1': 'StopSpeakingResponse',
  '2': [
    {'1': 'stopped', '3': 1, '4': 1, '5': 8, '10': 'stopped'},
  ],
};

/// Descriptor for `StopSpeakingResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List stopSpeakingResponseDescriptor =
    $convert.base64Decode(
        'ChRTdG9wU3BlYWtpbmdSZXNwb25zZRIYCgdzdG9wcGVkGAEgASgIUgdzdG9wcGVk');

@$core.Deprecated('Use getCoverArtRequestDescriptor instead')
const GetCoverArtRequest$json = {
  '1': 'GetCoverArtRequest',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
  ],
};

/// Descriptor for `GetCoverArtRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getCoverArtRequestDescriptor =
    $convert.base64Decode('ChJHZXRDb3ZlckFydFJlcXVlc3QSDgoCaWQYASABKAlSAmlk');

@$core.Deprecated('Use getCoverArtResponseDescriptor instead')
const GetCoverArtResponse$json = {
  '1': 'GetCoverArtResponse',
  '2': [
    {'1': 'found', '3': 1, '4': 1, '5': 8, '10': 'found'},
    {'1': 'image', '3': 2, '4': 1, '5': 12, '10': 'image'},
    {'1': 'mime_type', '3': 3, '4': 1, '5': 9, '10': 'mimeType'},
  ],
};

/// Descriptor for `GetCoverArtResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getCoverArtResponseDescriptor = $convert.base64Decode(
    'ChNHZXRDb3ZlckFydFJlc3BvbnNlEhQKBWZvdW5kGAEgASgIUgVmb3VuZBIUCgVpbWFnZRgCIA'
    'EoDFIFaW1hZ2USGwoJbWltZV90eXBlGAMgASgJUghtaW1lVHlwZQ==');

@$core.Deprecated('Use volumeDescriptor instead')
const Volume$json = {
  '1': 'Volume',
  '2': [
    {'1': 'level', '3': 1, '4': 1, '5': 13, '10': 'level'},
    {'1': 'max', '3': 2, '4': 1, '5': 13, '10': 'max'},
    {'1': 'steps', '3': 3, '4': 1, '5': 13, '10': 'steps'},
    {'1': 'muted', '3': 4, '4': 1, '5': 8, '10': 'muted'},
    {'1': 'applied', '3': 5, '4': 1, '5': 8, '10': 'applied'},
    {'1': 'detail', '3': 6, '4': 1, '5': 9, '10': 'detail'},
  ],
};

/// Descriptor for `Volume`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List volumeDescriptor = $convert.base64Decode(
    'CgZWb2x1bWUSFAoFbGV2ZWwYASABKA1SBWxldmVsEhAKA21heBgCIAEoDVIDbWF4EhQKBXN0ZX'
    'BzGAMgASgNUgVzdGVwcxIUCgVtdXRlZBgEIAEoCFIFbXV0ZWQSGAoHYXBwbGllZBgFIAEoCFIH'
    'YXBwbGllZBIWCgZkZXRhaWwYBiABKAlSBmRldGFpbA==');

@$core.Deprecated('Use setVolumeRequestDescriptor instead')
const SetVolumeRequest$json = {
  '1': 'SetVolumeRequest',
  '2': [
    {'1': 'level', '3': 1, '4': 1, '5': 13, '9': 0, '10': 'level'},
    {'1': 'steps', '3': 2, '4': 1, '5': 5, '9': 0, '10': 'steps'},
    {
      '1': 'mute',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.f250.audio.v1.MuteChange',
      '9': 0,
      '10': 'mute'
    },
    {'1': 'source', '3': 4, '4': 1, '5': 9, '10': 'source'},
  ],
  '8': [
    {'1': 'change'},
  ],
};

/// Descriptor for `SetVolumeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setVolumeRequestDescriptor = $convert.base64Decode(
    'ChBTZXRWb2x1bWVSZXF1ZXN0EhYKBWxldmVsGAEgASgNSABSBWxldmVsEhYKBXN0ZXBzGAIgAS'
    'gFSABSBXN0ZXBzEi8KBG11dGUYAyABKA4yGS5mMjUwLmF1ZGlvLnYxLk11dGVDaGFuZ2VIAFIE'
    'bXV0ZRIWCgZzb3VyY2UYBCABKAlSBnNvdXJjZUIICgZjaGFuZ2U=');

@$core.Deprecated('Use answerCallRequestDescriptor instead')
const AnswerCallRequest$json = {
  '1': 'AnswerCallRequest',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 4, '10': 'id'},
    {'1': 'source', '3': 2, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `AnswerCallRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List answerCallRequestDescriptor = $convert.base64Decode(
    'ChFBbnN3ZXJDYWxsUmVxdWVzdBIOCgJpZBgBIAEoBFICaWQSFgoGc291cmNlGAIgASgJUgZzb3'
    'VyY2U=');

@$core.Deprecated('Use answerCallResponseDescriptor instead')
const AnswerCallResponse$json = {
  '1': 'AnswerCallResponse',
  '2': [
    {'1': 'accepted', '3': 1, '4': 1, '5': 8, '10': 'accepted'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
  ],
};

/// Descriptor for `AnswerCallResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List answerCallResponseDescriptor = $convert.base64Decode(
    'ChJBbnN3ZXJDYWxsUmVzcG9uc2USGgoIYWNjZXB0ZWQYASABKAhSCGFjY2VwdGVkEhYKBmRldG'
    'FpbBgCIAEoCVIGZGV0YWls');

@$core.Deprecated('Use hangUpRequestDescriptor instead')
const HangUpRequest$json = {
  '1': 'HangUpRequest',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 4, '10': 'id'},
    {'1': 'source', '3': 2, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `HangUpRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List hangUpRequestDescriptor = $convert.base64Decode(
    'Cg1IYW5nVXBSZXF1ZXN0Eg4KAmlkGAEgASgEUgJpZBIWCgZzb3VyY2UYAiABKAlSBnNvdXJjZQ'
    '==');

@$core.Deprecated('Use hangUpResponseDescriptor instead')
const HangUpResponse$json = {
  '1': 'HangUpResponse',
  '2': [
    {'1': 'accepted', '3': 1, '4': 1, '5': 8, '10': 'accepted'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
  ],
};

/// Descriptor for `HangUpResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List hangUpResponseDescriptor = $convert.base64Decode(
    'Cg5IYW5nVXBSZXNwb25zZRIaCghhY2NlcHRlZBgBIAEoCFIIYWNjZXB0ZWQSFgoGZGV0YWlsGA'
    'IgASgJUgZkZXRhaWw=');

@$core.Deprecated('Use setMicMutedRequestDescriptor instead')
const SetMicMutedRequest$json = {
  '1': 'SetMicMutedRequest',
  '2': [
    {'1': 'muted', '3': 1, '4': 1, '5': 8, '10': 'muted'},
    {'1': 'source', '3': 2, '4': 1, '5': 9, '10': 'source'},
  ],
};

/// Descriptor for `SetMicMutedRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setMicMutedRequestDescriptor = $convert.base64Decode(
    'ChJTZXRNaWNNdXRlZFJlcXVlc3QSFAoFbXV0ZWQYASABKAhSBW11dGVkEhYKBnNvdXJjZRgCIA'
    'EoCVIGc291cmNl');

@$core.Deprecated('Use setMicMutedResponseDescriptor instead')
const SetMicMutedResponse$json = {
  '1': 'SetMicMutedResponse',
  '2': [
    {'1': 'applied', '3': 1, '4': 1, '5': 8, '10': 'applied'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
  ],
};

/// Descriptor for `SetMicMutedResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setMicMutedResponseDescriptor = $convert.base64Decode(
    'ChNTZXRNaWNNdXRlZFJlc3BvbnNlEhgKB2FwcGxpZWQYASABKAhSB2FwcGxpZWQSFgoGZGV0YW'
    'lsGAIgASgJUgZkZXRhaWw=');

@$core.Deprecated('Use setVolumeResponseDescriptor instead')
const SetVolumeResponse$json = {
  '1': 'SetVolumeResponse',
  '2': [
    {'1': 'applied', '3': 1, '4': 1, '5': 8, '10': 'applied'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
    {
      '1': 'volume',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.f250.audio.v1.Volume',
      '10': 'volume'
    },
  ],
};

/// Descriptor for `SetVolumeResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setVolumeResponseDescriptor = $convert.base64Decode(
    'ChFTZXRWb2x1bWVSZXNwb25zZRIYCgdhcHBsaWVkGAEgASgIUgdhcHBsaWVkEhYKBmRldGFpbB'
    'gCIAEoCVIGZGV0YWlsEi0KBnZvbHVtZRgDIAEoCzIVLmYyNTAuYXVkaW8udjEuVm9sdW1lUgZ2'
    'b2x1bWU=');
