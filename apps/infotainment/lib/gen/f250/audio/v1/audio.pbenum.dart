// This is a generated file - do not edit.
//
// Generated from f250/audio/v1/audio.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// Whether Bluetooth itself is usable.
class BluetoothState extends $pb.ProtobufEnum {
  static const BluetoothState BLUETOOTH_STATE_UNSPECIFIED =
      BluetoothState._(0, _omitEnumNames ? '' : 'BLUETOOTH_STATE_UNSPECIFIED');

  /// BlueZ answers and its adapter is powered.
  static const BluetoothState BLUETOOTH_STATE_READY =
      BluetoothState._(1, _omitEnumNames ? '' : 'BLUETOOTH_STATE_READY');

  /// No adapter, it is off, or BlueZ doesn't answer (`detail` says which).
  static const BluetoothState BLUETOOTH_STATE_UNAVAILABLE =
      BluetoothState._(2, _omitEnumNames ? '' : 'BLUETOOTH_STATE_UNAVAILABLE');

  static const $core.List<BluetoothState> values = <BluetoothState>[
    BLUETOOTH_STATE_UNSPECIFIED,
    BLUETOOTH_STATE_READY,
    BLUETOOTH_STATE_UNAVAILABLE,
  ];

  static final $core.List<BluetoothState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static BluetoothState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const BluetoothState._(super.value, super.name);
}

class PlayState extends $pb.ProtobufEnum {
  static const PlayState PLAY_STATE_UNSPECIFIED =
      PlayState._(0, _omitEnumNames ? '' : 'PLAY_STATE_UNSPECIFIED');
  static const PlayState PLAY_STATE_STOPPED =
      PlayState._(1, _omitEnumNames ? '' : 'PLAY_STATE_STOPPED');
  static const PlayState PLAY_STATE_PLAYING =
      PlayState._(2, _omitEnumNames ? '' : 'PLAY_STATE_PLAYING');
  static const PlayState PLAY_STATE_PAUSED =
      PlayState._(3, _omitEnumNames ? '' : 'PLAY_STATE_PAUSED');
  static const PlayState PLAY_STATE_FORWARD_SEEK =
      PlayState._(4, _omitEnumNames ? '' : 'PLAY_STATE_FORWARD_SEEK');
  static const PlayState PLAY_STATE_REVERSE_SEEK =
      PlayState._(5, _omitEnumNames ? '' : 'PLAY_STATE_REVERSE_SEEK');

  /// The phone reported an error.
  static const PlayState PLAY_STATE_ERROR =
      PlayState._(6, _omitEnumNames ? '' : 'PLAY_STATE_ERROR');

  static const $core.List<PlayState> values = <PlayState>[
    PLAY_STATE_UNSPECIFIED,
    PLAY_STATE_STOPPED,
    PLAY_STATE_PLAYING,
    PLAY_STATE_PAUSED,
    PLAY_STATE_FORWARD_SEEK,
    PLAY_STATE_REVERSE_SEEK,
    PLAY_STATE_ERROR,
  ];

  static final $core.List<PlayState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static PlayState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PlayState._(super.value, super.name);
}

class PairingState extends $pb.ProtobufEnum {
  static const PairingState PAIRING_STATE_UNSPECIFIED =
      PairingState._(0, _omitEnumNames ? '' : 'PAIRING_STATE_UNSPECIFIED');

  /// Not discoverable; new phones are refused.
  static const PairingState PAIRING_STATE_CLOSED =
      PairingState._(1, _omitEnumNames ? '' : 'PAIRING_STATE_CLOSED');

  /// Asked BlueZ to become discoverable and pairable; not confirmed yet.
  static const PairingState PAIRING_STATE_OPENING =
      PairingState._(2, _omitEnumNames ? '' : 'PAIRING_STATE_OPENING');

  /// Discoverable and pairable until the countdown ends.
  static const PairingState PAIRING_STATE_OPEN =
      PairingState._(3, _omitEnumNames ? '' : 'PAIRING_STATE_OPEN');

  /// Asked BlueZ to stop being discoverable and pairable.
  static const PairingState PAIRING_STATE_CLOSING =
      PairingState._(4, _omitEnumNames ? '' : 'PAIRING_STATE_CLOSING');

  /// BlueZ refused to open (or close) the window: `detail` says why.
  static const PairingState PAIRING_STATE_FAILED =
      PairingState._(5, _omitEnumNames ? '' : 'PAIRING_STATE_FAILED');

  static const $core.List<PairingState> values = <PairingState>[
    PAIRING_STATE_UNSPECIFIED,
    PAIRING_STATE_CLOSED,
    PAIRING_STATE_OPENING,
    PAIRING_STATE_OPEN,
    PAIRING_STATE_CLOSING,
    PAIRING_STATE_FAILED,
  ];

  static final $core.List<PairingState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static PairingState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PairingState._(super.value, super.name);
}

/// Whether the speaker settings are in effect.
class DspState extends $pb.ProtobufEnum {
  static const DspState DSP_STATE_UNSPECIFIED =
      DspState._(0, _omitEnumNames ? '' : 'DSP_STATE_UNSPECIFIED');

  /// The filter-chain runs with the current settings.
  static const DspState DSP_STATE_APPLIED =
      DspState._(1, _omitEnumNames ? '' : 'DSP_STATE_APPLIED');

  /// Starting or restarting the filter-chain.
  static const DspState DSP_STATE_STARTING =
      DspState._(2, _omitEnumNames ? '' : 'DSP_STATE_STARTING');

  /// Not running: `detail` says why (no PipeWire, the simulation).
  static const DspState DSP_STATE_NOT_RUNNING =
      DspState._(3, _omitEnumNames ? '' : 'DSP_STATE_NOT_RUNNING');

  static const $core.List<DspState> values = <DspState>[
    DSP_STATE_UNSPECIFIED,
    DSP_STATE_APPLIED,
    DSP_STATE_STARTING,
    DSP_STATE_NOT_RUNNING,
  ];

  static final $core.List<DspState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static DspState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const DspState._(super.value, super.name);
}

/// Where a call is, as the phone's hands-free gateway reports it (PipeWire's
/// org.pipewire.Telephony.Call1 State).
class CallState extends $pb.ProtobufEnum {
  static const CallState CALL_STATE_UNSPECIFIED =
      CallState._(0, _omitEnumNames ? '' : 'CALL_STATE_UNSPECIFIED');

  /// Ringing: Answer or decline.
  static const CallState CALL_STATE_INCOMING =
      CallState._(1, _omitEnumNames ? '' : 'CALL_STATE_INCOMING');

  /// Another call rings during this one: decline here, answer on the phone.
  static const CallState CALL_STATE_WAITING =
      CallState._(2, _omitEnumNames ? '' : 'CALL_STATE_WAITING');

  /// An outgoing call (made on the phone) being set up.
  static const CallState CALL_STATE_DIALING =
      CallState._(3, _omitEnumNames ? '' : 'CALL_STATE_DIALING');

  /// An outgoing call, the other phone ringing.
  static const CallState CALL_STATE_ALERTING =
      CallState._(4, _omitEnumNames ? '' : 'CALL_STATE_ALERTING');
  static const CallState CALL_STATE_ACTIVE =
      CallState._(5, _omitEnumNames ? '' : 'CALL_STATE_ACTIVE');
  static const CallState CALL_STATE_HELD =
      CallState._(6, _omitEnumNames ? '' : 'CALL_STATE_HELD');

  static const $core.List<CallState> values = <CallState>[
    CALL_STATE_UNSPECIFIED,
    CALL_STATE_INCOMING,
    CALL_STATE_WAITING,
    CALL_STATE_DIALING,
    CALL_STATE_ALERTING,
    CALL_STATE_ACTIVE,
    CALL_STATE_HELD,
  ];

  static final $core.List<CallState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static CallState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const CallState._(super.value, super.name);
}

class Command extends $pb.ProtobufEnum {
  static const Command COMMAND_UNSPECIFIED =
      Command._(0, _omitEnumNames ? '' : 'COMMAND_UNSPECIFIED');
  static const Command COMMAND_PLAY =
      Command._(1, _omitEnumNames ? '' : 'COMMAND_PLAY');
  static const Command COMMAND_PAUSE =
      Command._(2, _omitEnumNames ? '' : 'COMMAND_PAUSE');
  static const Command COMMAND_NEXT =
      Command._(3, _omitEnumNames ? '' : 'COMMAND_NEXT');
  static const Command COMMAND_PREVIOUS =
      Command._(4, _omitEnumNames ? '' : 'COMMAND_PREVIOUS');

  static const $core.List<Command> values = <Command>[
    COMMAND_UNSPECIFIED,
    COMMAND_PLAY,
    COMMAND_PAUSE,
    COMMAND_NEXT,
    COMMAND_PREVIOUS,
  ];

  static final $core.List<Command?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static Command? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Command._(super.value, super.name);
}

class MuteChange extends $pb.ProtobufEnum {
  static const MuteChange MUTE_CHANGE_UNSPECIFIED =
      MuteChange._(0, _omitEnumNames ? '' : 'MUTE_CHANGE_UNSPECIFIED');
  static const MuteChange MUTE_CHANGE_MUTE =
      MuteChange._(1, _omitEnumNames ? '' : 'MUTE_CHANGE_MUTE');
  static const MuteChange MUTE_CHANGE_UNMUTE =
      MuteChange._(2, _omitEnumNames ? '' : 'MUTE_CHANGE_UNMUTE');
  static const MuteChange MUTE_CHANGE_TOGGLE =
      MuteChange._(3, _omitEnumNames ? '' : 'MUTE_CHANGE_TOGGLE');

  static const $core.List<MuteChange> values = <MuteChange>[
    MUTE_CHANGE_UNSPECIFIED,
    MUTE_CHANGE_MUTE,
    MUTE_CHANGE_UNMUTE,
    MUTE_CHANGE_TOGGLE,
  ];

  static final $core.List<MuteChange?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static MuteChange? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const MuteChange._(super.value, super.name);
}

class PhonebookState extends $pb.ProtobufEnum {
  static const PhonebookState PHONEBOOK_STATE_UNSPECIFIED =
      PhonebookState._(0, _omitEnumNames ? '' : 'PHONEBOOK_STATE_UNSPECIFIED');

  /// No phone connected: nothing to read.
  static const PhonebookState PHONEBOOK_STATE_NONE =
      PhonebookState._(1, _omitEnumNames ? '' : 'PHONEBOOK_STATE_NONE');

  /// Being read from the phone.
  static const PhonebookState PHONEBOOK_STATE_LOADING =
      PhonebookState._(2, _omitEnumNames ? '' : 'PHONEBOOK_STATE_LOADING');
  static const PhonebookState PHONEBOOK_STATE_READY =
      PhonebookState._(3, _omitEnumNames ? '' : 'PHONEBOOK_STATE_READY');

  /// The phone didn't share them: `detail` says why.
  static const PhonebookState PHONEBOOK_STATE_FAILED =
      PhonebookState._(4, _omitEnumNames ? '' : 'PHONEBOOK_STATE_FAILED');

  /// Not configured on this head unit: `detail` says why.
  static const PhonebookState PHONEBOOK_STATE_OFF =
      PhonebookState._(5, _omitEnumNames ? '' : 'PHONEBOOK_STATE_OFF');

  static const $core.List<PhonebookState> values = <PhonebookState>[
    PHONEBOOK_STATE_UNSPECIFIED,
    PHONEBOOK_STATE_NONE,
    PHONEBOOK_STATE_LOADING,
    PHONEBOOK_STATE_READY,
    PHONEBOOK_STATE_FAILED,
    PHONEBOOK_STATE_OFF,
  ];

  static final $core.List<PhonebookState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static PhonebookState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PhonebookState._(super.value, super.name);
}

class RecentKind extends $pb.ProtobufEnum {
  static const RecentKind RECENT_KIND_UNSPECIFIED =
      RecentKind._(0, _omitEnumNames ? '' : 'RECENT_KIND_UNSPECIFIED');
  static const RecentKind RECENT_KIND_RECEIVED =
      RecentKind._(1, _omitEnumNames ? '' : 'RECENT_KIND_RECEIVED');
  static const RecentKind RECENT_KIND_DIALED =
      RecentKind._(2, _omitEnumNames ? '' : 'RECENT_KIND_DIALED');
  static const RecentKind RECENT_KIND_MISSED =
      RecentKind._(3, _omitEnumNames ? '' : 'RECENT_KIND_MISSED');

  static const $core.List<RecentKind> values = <RecentKind>[
    RECENT_KIND_UNSPECIFIED,
    RECENT_KIND_RECEIVED,
    RECENT_KIND_DIALED,
    RECENT_KIND_MISSED,
  ];

  static final $core.List<RecentKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static RecentKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const RecentKind._(super.value, super.name);
}

class MediaKey extends $pb.ProtobufEnum {
  static const MediaKey MEDIA_KEY_UNSPECIFIED =
      MediaKey._(0, _omitEnumNames ? '' : 'MEDIA_KEY_UNSPECIFIED');
  static const MediaKey MEDIA_KEY_PLAY_PAUSE =
      MediaKey._(1, _omitEnumNames ? '' : 'MEDIA_KEY_PLAY_PAUSE');
  static const MediaKey MEDIA_KEY_NEXT =
      MediaKey._(2, _omitEnumNames ? '' : 'MEDIA_KEY_NEXT');
  static const MediaKey MEDIA_KEY_PREVIOUS =
      MediaKey._(3, _omitEnumNames ? '' : 'MEDIA_KEY_PREVIOUS');
  static const MediaKey MEDIA_KEY_VOLUME_UP =
      MediaKey._(4, _omitEnumNames ? '' : 'MEDIA_KEY_VOLUME_UP');
  static const MediaKey MEDIA_KEY_VOLUME_DOWN =
      MediaKey._(5, _omitEnumNames ? '' : 'MEDIA_KEY_VOLUME_DOWN');

  static const $core.List<MediaKey> values = <MediaKey>[
    MEDIA_KEY_UNSPECIFIED,
    MEDIA_KEY_PLAY_PAUSE,
    MEDIA_KEY_NEXT,
    MEDIA_KEY_PREVIOUS,
    MEDIA_KEY_VOLUME_UP,
    MEDIA_KEY_VOLUME_DOWN,
  ];

  static final $core.List<MediaKey?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static MediaKey? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const MediaKey._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
