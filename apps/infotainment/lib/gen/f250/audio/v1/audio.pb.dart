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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'audio.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'audio.pbenum.dart';

class WatchAudioRequest extends $pb.GeneratedMessage {
  factory WatchAudioRequest() => WatchAudioRequest._();

  WatchAudioRequest._();

  factory WatchAudioRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchAudioRequest()..mergeFromBuffer(data, registry);
  factory WatchAudioRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchAudioRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchAudioRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: WatchAudioRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchAudioRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchAudioRequest copyWith(void Function(WatchAudioRequest) updates) =>
      super.copyWith((message) => updates(message as WatchAudioRequest))
          as WatchAudioRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WatchAudioRequest() / WatchAudioRequest.new instead')
  static WatchAudioRequest create() => WatchAudioRequest._();
  static $pb.GeneratedMessage $_createMessage() => WatchAudioRequest._();
  @$core.override
  WatchAudioRequest createEmptyInstance() => WatchAudioRequest._();
  @$core.pragma('dart2js:noInline')
  static WatchAudioRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WatchAudioRequest>(
          WatchAudioRequest.$_createMessage);
  static WatchAudioRequest? _defaultInstance;
}

/// A paired or connected phone.
class Phone extends $pb.GeneratedMessage {
  factory Phone({
    $core.String? address,
    $core.String? name,
    $core.bool? connected,
    $core.bool? paired,
    $core.bool? last,
  }) {
    final result = Phone._();
    if (address != null) result.address = address;
    if (name != null) result.name = name;
    if (connected != null) result.connected = connected;
    if (paired != null) result.paired = paired;
    if (last != null) result.last = last;
    return result;
  }

  Phone._();

  factory Phone.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Phone()..mergeFromBuffer(data, registry);
  factory Phone.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Phone()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Phone',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: Phone.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOB(3, _omitFieldNames ? '' : 'connected')
    ..aOB(4, _omitFieldNames ? '' : 'paired')
    ..aOB(5, _omitFieldNames ? '' : 'last')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Phone clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Phone copyWith(void Function(Phone) updates) =>
      super.copyWith((message) => updates(message as Phone)) as Phone;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Phone() / Phone.new instead')
  static Phone create() => Phone._();
  static $pb.GeneratedMessage $_createMessage() => Phone._();
  @$core.override
  Phone createEmptyInstance() => Phone._();
  @$core.pragma('dart2js:noInline')
  static Phone getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Phone>(Phone.$_createMessage);
  static Phone? _defaultInstance;

  /// The Bluetooth address, AA:BB:CC:DD:EE:FF.
  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);

  /// What the phone calls itself (BlueZ's Alias), for the screen.
  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get connected => $_getBF(2);
  @$pb.TagNumber(3)
  set connected($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasConnected() => $_has(2);
  @$pb.TagNumber(3)
  void clearConnected() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get paired => $_getBF(3);
  @$pb.TagNumber(4)
  set paired($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPaired() => $_has(3);
  @$pb.TagNumber(4)
  void clearPaired() => $_clearField(4);

  /// The phone connected most recently: the one audio-manager reconnects to
  /// by itself (at start, and after the link drops, for a limited time).
  @$pb.TagNumber(5)
  $core.bool get last => $_getBF(4);
  @$pb.TagNumber(5)
  set last($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasLast() => $_has(4);
  @$pb.TagNumber(5)
  void clearLast() => $_clearField(5);
}

/// A connection to a paired phone being tried (ConnectPhone, or
/// audio-manager reconnecting the last phone by itself), and how the last one
/// went.
class ConnectAttempt extends $pb.GeneratedMessage {
  factory ConnectAttempt({
    $core.String? address,
    $core.String? name,
    $core.bool? automatic,
    $core.String? detail,
  }) {
    final result = ConnectAttempt._();
    if (address != null) result.address = address;
    if (name != null) result.name = name;
    if (automatic != null) result.automatic = automatic;
    if (detail != null) result.detail = detail;
    return result;
  }

  ConnectAttempt._();

  factory ConnectAttempt.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ConnectAttempt()..mergeFromBuffer(data, registry);
  factory ConnectAttempt.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ConnectAttempt()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectAttempt',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: ConnectAttempt.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOB(3, _omitFieldNames ? '' : 'automatic')
    ..aOS(4, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectAttempt clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectAttempt copyWith(void Function(ConnectAttempt) updates) =>
      super.copyWith((message) => updates(message as ConnectAttempt))
          as ConnectAttempt;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ConnectAttempt() / ConnectAttempt.new instead')
  static ConnectAttempt create() => ConnectAttempt._();
  static $pb.GeneratedMessage $_createMessage() => ConnectAttempt._();
  @$core.override
  ConnectAttempt createEmptyInstance() => ConnectAttempt._();
  @$core.pragma('dart2js:noInline')
  static ConnectAttempt getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ConnectAttempt>(
          ConnectAttempt.$_createMessage);
  static ConnectAttempt? _defaultInstance;

  /// The phone being connected now; empty: none.
  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  /// audio-manager is trying by itself, not because the driver asked.
  @$pb.TagNumber(3)
  $core.bool get automatic => $_getBF(2);
  @$pb.TagNumber(3)
  set automatic($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAutomatic() => $_has(2);
  @$pb.TagNumber(3)
  void clearAutomatic() => $_clearField(3);

  /// What happened last ("Couldn't reach Pixel 8: …"), for the screen; may
  /// be empty.
  @$pb.TagNumber(4)
  $core.String get detail => $_getSZ(3);
  @$pb.TagNumber(4)
  set detail($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDetail() => $_has(3);
  @$pb.TagNumber(4)
  void clearDetail() => $_clearField(4);
}

/// The connected phone's player (AVRCP, BlueZ MediaPlayer1). Present only
/// while that phone is connected and has a player: never the last track of
/// a phone that has gone.
class NowPlaying extends $pb.GeneratedMessage {
  factory NowPlaying({
    $core.String? title,
    $core.String? artist,
    $core.String? album,
    PlayState? state,
    $core.int? durationMs,
    $core.bool? hasPosition,
    $core.int? positionMs,
    $core.String? playerName,
    $core.String? coverArtId,
    $core.String? coverArtDetail,
  }) {
    final result = NowPlaying._();
    if (title != null) result.title = title;
    if (artist != null) result.artist = artist;
    if (album != null) result.album = album;
    if (state != null) result.state = state;
    if (durationMs != null) result.durationMs = durationMs;
    if (hasPosition != null) result.hasPosition = hasPosition;
    if (positionMs != null) result.positionMs = positionMs;
    if (playerName != null) result.playerName = playerName;
    if (coverArtId != null) result.coverArtId = coverArtId;
    if (coverArtDetail != null) result.coverArtDetail = coverArtDetail;
    return result;
  }

  NowPlaying._();

  factory NowPlaying.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NowPlaying()..mergeFromBuffer(data, registry);
  factory NowPlaying.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NowPlaying()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NowPlaying',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: NowPlaying.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'title')
    ..aOS(2, _omitFieldNames ? '' : 'artist')
    ..aOS(3, _omitFieldNames ? '' : 'album')
    ..aE<PlayState>(4, _omitFieldNames ? '' : 'state',
        enumValues: PlayState.values)
    ..aI(5, _omitFieldNames ? '' : 'durationMs', fieldType: $pb.PbFieldType.OU3)
    ..aOB(6, _omitFieldNames ? '' : 'hasPosition')
    ..aI(7, _omitFieldNames ? '' : 'positionMs', fieldType: $pb.PbFieldType.OU3)
    ..aOS(8, _omitFieldNames ? '' : 'playerName')
    ..aOS(9, _omitFieldNames ? '' : 'coverArtId')
    ..aOS(10, _omitFieldNames ? '' : 'coverArtDetail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NowPlaying clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NowPlaying copyWith(void Function(NowPlaying) updates) =>
      super.copyWith((message) => updates(message as NowPlaying)) as NowPlaying;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use NowPlaying() / NowPlaying.new instead')
  static NowPlaying create() => NowPlaying._();
  static $pb.GeneratedMessage $_createMessage() => NowPlaying._();
  @$core.override
  NowPlaying createEmptyInstance() => NowPlaying._();
  @$core.pragma('dart2js:noInline')
  static NowPlaying getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NowPlaying>(NowPlaying.$_createMessage);
  static NowPlaying? _defaultInstance;

  /// Empty when the phone doesn't say.
  @$pb.TagNumber(1)
  $core.String get title => $_getSZ(0);
  @$pb.TagNumber(1)
  set title($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTitle() => $_has(0);
  @$pb.TagNumber(1)
  void clearTitle() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get artist => $_getSZ(1);
  @$pb.TagNumber(2)
  set artist($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasArtist() => $_has(1);
  @$pb.TagNumber(2)
  void clearArtist() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get album => $_getSZ(2);
  @$pb.TagNumber(3)
  set album($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAlbum() => $_has(2);
  @$pb.TagNumber(3)
  void clearAlbum() => $_clearField(3);

  @$pb.TagNumber(4)
  PlayState get state => $_getN(3);
  @$pb.TagNumber(4)
  set state(PlayState value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasState() => $_has(3);
  @$pb.TagNumber(4)
  void clearState() => $_clearField(4);

  /// Milliseconds; 0: the phone doesn't say.
  @$pb.TagNumber(5)
  $core.int get durationMs => $_getIZ(4);
  @$pb.TagNumber(5)
  set durationMs($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDurationMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearDurationMs() => $_clearField(5);

  /// Milliseconds into the track, as of this message (the service counts on
  /// from the phone's last report while playing). False: unknown.
  @$pb.TagNumber(6)
  $core.bool get hasPosition => $_getBF(5);
  @$pb.TagNumber(6)
  set hasPosition($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasHasPosition() => $_has(5);
  @$pb.TagNumber(6)
  void clearHasPosition() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get positionMs => $_getIZ(6);
  @$pb.TagNumber(7)
  set positionMs($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPositionMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearPositionMs() => $_clearField(7);

  /// The player's name (the phone's app), when it gives one.
  @$pb.TagNumber(8)
  $core.String get playerName => $_getSZ(7);
  @$pb.TagNumber(8)
  set playerName($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasPlayerName() => $_has(7);
  @$pb.TagNumber(8)
  void clearPlayerName() => $_clearField(8);

  /// The track's picture (AVRCP 1.6 cover art, fetched from the phone over
  /// OBEX BIP by audio-manager; ADR-0042), to fetch with GetCoverArt. Empty:
  /// no picture for this track. A new track (or a new picture) gets a new id;
  /// the id never names another track's picture.
  @$pb.TagNumber(9)
  $core.String get coverArtId => $_getSZ(8);
  @$pb.TagNumber(9)
  set coverArtId($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasCoverArtId() => $_has(8);
  @$pb.TagNumber(9)
  void clearCoverArtId() => $_clearField(9);

  /// Why there is no picture, in words for the screen ("The phone doesn't
  /// offer cover art"); empty while there is one, or nothing to say.
  @$pb.TagNumber(10)
  $core.String get coverArtDetail => $_getSZ(9);
  @$pb.TagNumber(10)
  set coverArtDetail($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasCoverArtDetail() => $_has(9);
  @$pb.TagNumber(10)
  void clearCoverArtDetail() => $_clearField(10);
}

/// A phone asking to pair, showing a six-digit code. The driver accepts
/// only if the phone shows the same code.
class PasskeyQuestion extends $pb.GeneratedMessage {
  factory PasskeyQuestion({
    $fixnum.Int64? id,
    $core.String? phoneName,
    $core.String? address,
    $core.int? passkey,
    $core.int? secondsLeft,
    $core.bool? showsPasskey,
  }) {
    final result = PasskeyQuestion._();
    if (id != null) result.id = id;
    if (phoneName != null) result.phoneName = phoneName;
    if (address != null) result.address = address;
    if (passkey != null) result.passkey = passkey;
    if (secondsLeft != null) result.secondsLeft = secondsLeft;
    if (showsPasskey != null) result.showsPasskey = showsPasskey;
    return result;
  }

  PasskeyQuestion._();

  factory PasskeyQuestion.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PasskeyQuestion()..mergeFromBuffer(data, registry);
  factory PasskeyQuestion.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PasskeyQuestion()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PasskeyQuestion',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: PasskeyQuestion.$_createMessage)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'id', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(2, _omitFieldNames ? '' : 'phoneName')
    ..aOS(3, _omitFieldNames ? '' : 'address')
    ..aI(4, _omitFieldNames ? '' : 'passkey', fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'secondsLeft',
        fieldType: $pb.PbFieldType.OU3)
    ..aOB(6, _omitFieldNames ? '' : 'showsPasskey')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PasskeyQuestion clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PasskeyQuestion copyWith(void Function(PasskeyQuestion) updates) =>
      super.copyWith((message) => updates(message as PasskeyQuestion))
          as PasskeyQuestion;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PasskeyQuestion() / PasskeyQuestion.new instead')
  static PasskeyQuestion create() => PasskeyQuestion._();
  static $pb.GeneratedMessage $_createMessage() => PasskeyQuestion._();
  @$core.override
  PasskeyQuestion createEmptyInstance() => PasskeyQuestion._();
  @$core.pragma('dart2js:noInline')
  static PasskeyQuestion getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PasskeyQuestion>(
          PasskeyQuestion.$_createMessage);
  static PasskeyQuestion? _defaultInstance;

  /// Names this question in ConfirmPairing.
  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get phoneName => $_getSZ(1);
  @$pb.TagNumber(2)
  set phoneName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPhoneName() => $_has(1);
  @$pb.TagNumber(2)
  void clearPhoneName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get address => $_getSZ(2);
  @$pb.TagNumber(3)
  set address($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAddress() => $_has(2);
  @$pb.TagNumber(3)
  void clearAddress() => $_clearField(3);

  /// Six digits, shown with leading zeros; only when shows_passkey.
  @$pb.TagNumber(4)
  $core.int get passkey => $_getIZ(3);
  @$pb.TagNumber(4)
  set passkey($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPasskey() => $_has(3);
  @$pb.TagNumber(4)
  void clearPasskey() => $_clearField(4);

  /// The question is refused by itself when this reaches 0.
  @$pb.TagNumber(5)
  $core.int get secondsLeft => $_getIZ(4);
  @$pb.TagNumber(5)
  set secondsLeft($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSecondsLeft() => $_has(4);
  @$pb.TagNumber(5)
  void clearSecondsLeft() => $_clearField(5);

  /// False: the phone asks to pair without a code; accept only if it is
  /// the phone in your hand.
  @$pb.TagNumber(6)
  $core.bool get showsPasskey => $_getBF(5);
  @$pb.TagNumber(6)
  set showsPasskey($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasShowsPasskey() => $_has(5);
  @$pb.TagNumber(6)
  void clearShowsPasskey() => $_clearField(6);
}

class Pairing extends $pb.GeneratedMessage {
  factory Pairing({
    PairingState? state,
    $core.int? secondsLeft,
    $core.String? detail,
    PasskeyQuestion? question,
    $core.String? name,
  }) {
    final result = Pairing._();
    if (state != null) result.state = state;
    if (secondsLeft != null) result.secondsLeft = secondsLeft;
    if (detail != null) result.detail = detail;
    if (question != null) result.question = question;
    if (name != null) result.name = name;
    return result;
  }

  Pairing._();

  factory Pairing.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Pairing()..mergeFromBuffer(data, registry);
  factory Pairing.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Pairing()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Pairing',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: Pairing.$_createMessage)
    ..aE<PairingState>(1, _omitFieldNames ? '' : 'state',
        enumValues: PairingState.values)
    ..aI(2, _omitFieldNames ? '' : 'secondsLeft',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(3, _omitFieldNames ? '' : 'detail')
    ..aOM<PasskeyQuestion>(4, _omitFieldNames ? '' : 'question',
        subBuilder: PasskeyQuestion.$_createMessage)
    ..aOS(5, _omitFieldNames ? '' : 'name')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Pairing clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Pairing copyWith(void Function(Pairing) updates) =>
      super.copyWith((message) => updates(message as Pairing)) as Pairing;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Pairing() / Pairing.new instead')
  static Pairing create() => Pairing._();
  static $pb.GeneratedMessage $_createMessage() => Pairing._();
  @$core.override
  Pairing createEmptyInstance() => Pairing._();
  @$core.pragma('dart2js:noInline')
  static Pairing getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Pairing>(Pairing.$_createMessage);
  static Pairing? _defaultInstance;

  @$pb.TagNumber(1)
  PairingState get state => $_getN(0);
  @$pb.TagNumber(1)
  set state(PairingState value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasState() => $_has(0);
  @$pb.TagNumber(1)
  void clearState() => $_clearField(1);

  /// While open: seconds until it closes by itself.
  @$pb.TagNumber(2)
  $core.int get secondsLeft => $_getIZ(1);
  @$pb.TagNumber(2)
  set secondsLeft($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSecondsLeft() => $_has(1);
  @$pb.TagNumber(2)
  void clearSecondsLeft() => $_clearField(2);

  /// What happened (paired a phone, closed by itself, refused), for the
  /// screen; may be empty.
  @$pb.TagNumber(3)
  $core.String get detail => $_getSZ(2);
  @$pb.TagNumber(3)
  set detail($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDetail() => $_has(2);
  @$pb.TagNumber(3)
  void clearDetail() => $_clearField(3);

  /// A phone waiting for the driver's answer, if any.
  @$pb.TagNumber(4)
  PasskeyQuestion get question => $_getN(3);
  @$pb.TagNumber(4)
  set question(PasskeyQuestion value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasQuestion() => $_has(3);
  @$pb.TagNumber(4)
  void clearQuestion() => $_clearField(4);
  @$pb.TagNumber(4)
  PasskeyQuestion ensureQuestion() => $_ensure(3);

  /// The name phones see.
  @$pb.TagNumber(5)
  $core.String get name => $_getSZ(4);
  @$pb.TagNumber(5)
  set name($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasName() => $_has(4);
  @$pb.TagNumber(5)
  void clearName() => $_clearField(5);
}

class WatchAudioResponse extends $pb.GeneratedMessage {
  factory WatchAudioResponse({
    BluetoothState? bluetooth,
    $core.String? bluetoothDetail,
    Phone? phone,
    $core.Iterable<Phone>? known,
    NowPlaying? nowPlaying,
    $core.bool? streaming,
    Pairing? pairing,
    DspState? dsp,
    $core.String? dspDetail,
    $core.bool? simulated,
    Prompts? prompts,
    ConnectAttempt? connect,
  }) {
    final result = WatchAudioResponse._();
    if (bluetooth != null) result.bluetooth = bluetooth;
    if (bluetoothDetail != null) result.bluetoothDetail = bluetoothDetail;
    if (phone != null) result.phone = phone;
    if (known != null) result.known.addAll(known);
    if (nowPlaying != null) result.nowPlaying = nowPlaying;
    if (streaming != null) result.streaming = streaming;
    if (pairing != null) result.pairing = pairing;
    if (dsp != null) result.dsp = dsp;
    if (dspDetail != null) result.dspDetail = dspDetail;
    if (simulated != null) result.simulated = simulated;
    if (prompts != null) result.prompts = prompts;
    if (connect != null) result.connect = connect;
    return result;
  }

  WatchAudioResponse._();

  factory WatchAudioResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchAudioResponse()..mergeFromBuffer(data, registry);
  factory WatchAudioResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchAudioResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchAudioResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: WatchAudioResponse.$_createMessage)
    ..aE<BluetoothState>(1, _omitFieldNames ? '' : 'bluetooth',
        enumValues: BluetoothState.values)
    ..aOS(2, _omitFieldNames ? '' : 'bluetoothDetail')
    ..aOM<Phone>(3, _omitFieldNames ? '' : 'phone',
        subBuilder: Phone.$_createMessage)
    ..pPM<Phone>(4, _omitFieldNames ? '' : 'known',
        subBuilder: Phone.$_createMessage)
    ..aOM<NowPlaying>(5, _omitFieldNames ? '' : 'nowPlaying',
        subBuilder: NowPlaying.$_createMessage)
    ..aOB(6, _omitFieldNames ? '' : 'streaming')
    ..aOM<Pairing>(7, _omitFieldNames ? '' : 'pairing',
        subBuilder: Pairing.$_createMessage)
    ..aE<DspState>(8, _omitFieldNames ? '' : 'dsp', enumValues: DspState.values)
    ..aOS(9, _omitFieldNames ? '' : 'dspDetail')
    ..aOB(10, _omitFieldNames ? '' : 'simulated')
    ..aOM<Prompts>(11, _omitFieldNames ? '' : 'prompts',
        subBuilder: Prompts.$_createMessage)
    ..aOM<ConnectAttempt>(12, _omitFieldNames ? '' : 'connect',
        subBuilder: ConnectAttempt.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchAudioResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchAudioResponse copyWith(void Function(WatchAudioResponse) updates) =>
      super.copyWith((message) => updates(message as WatchAudioResponse))
          as WatchAudioResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WatchAudioResponse() / WatchAudioResponse.new instead')
  static WatchAudioResponse create() => WatchAudioResponse._();
  static $pb.GeneratedMessage $_createMessage() => WatchAudioResponse._();
  @$core.override
  WatchAudioResponse createEmptyInstance() => WatchAudioResponse._();
  @$core.pragma('dart2js:noInline')
  static WatchAudioResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WatchAudioResponse>(
          WatchAudioResponse.$_createMessage);
  static WatchAudioResponse? _defaultInstance;

  @$pb.TagNumber(1)
  BluetoothState get bluetooth => $_getN(0);
  @$pb.TagNumber(1)
  set bluetooth(BluetoothState value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasBluetooth() => $_has(0);
  @$pb.TagNumber(1)
  void clearBluetooth() => $_clearField(1);

  /// Why Bluetooth is unavailable, or what it is doing.
  @$pb.TagNumber(2)
  $core.String get bluetoothDetail => $_getSZ(1);
  @$pb.TagNumber(2)
  set bluetoothDetail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBluetoothDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearBluetoothDetail() => $_clearField(2);

  /// The phone streaming or connected now, if any.
  @$pb.TagNumber(3)
  Phone get phone => $_getN(2);
  @$pb.TagNumber(3)
  set phone(Phone value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasPhone() => $_has(2);
  @$pb.TagNumber(3)
  void clearPhone() => $_clearField(3);
  @$pb.TagNumber(3)
  Phone ensurePhone() => $_ensure(2);

  /// Phones paired before and not connected.
  @$pb.TagNumber(4)
  $pb.PbList<Phone> get known => $_getList(3);

  @$pb.TagNumber(5)
  NowPlaying get nowPlaying => $_getN(4);
  @$pb.TagNumber(5)
  set nowPlaying(NowPlaying value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasNowPlaying() => $_has(4);
  @$pb.TagNumber(5)
  void clearNowPlaying() => $_clearField(5);
  @$pb.TagNumber(5)
  NowPlaying ensureNowPlaying() => $_ensure(4);

  /// Audio is arriving from the phone now (BlueZ MediaTransport1 active).
  @$pb.TagNumber(6)
  $core.bool get streaming => $_getBF(5);
  @$pb.TagNumber(6)
  set streaming($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasStreaming() => $_has(5);
  @$pb.TagNumber(6)
  void clearStreaming() => $_clearField(6);

  @$pb.TagNumber(7)
  Pairing get pairing => $_getN(6);
  @$pb.TagNumber(7)
  set pairing(Pairing value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasPairing() => $_has(6);
  @$pb.TagNumber(7)
  void clearPairing() => $_clearField(7);
  @$pb.TagNumber(7)
  Pairing ensurePairing() => $_ensure(6);

  @$pb.TagNumber(8)
  DspState get dsp => $_getN(7);
  @$pb.TagNumber(8)
  set dsp(DspState value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasDsp() => $_has(7);
  @$pb.TagNumber(8)
  void clearDsp() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get dspDetail => $_getSZ(8);
  @$pb.TagNumber(9)
  set dspDetail($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasDspDetail() => $_has(8);
  @$pb.TagNumber(9)
  void clearDspDetail() => $_clearField(9);

  /// The service runs a simulated phone: nothing is real.
  @$pb.TagNumber(10)
  $core.bool get simulated => $_getBF(9);
  @$pb.TagNumber(10)
  set simulated($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(10)
  $core.bool hasSimulated() => $_has(9);
  @$pb.TagNumber(10)
  void clearSimulated() => $_clearField(10);

  @$pb.TagNumber(11)
  Prompts get prompts => $_getN(10);
  @$pb.TagNumber(11)
  set prompts(Prompts value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasPrompts() => $_has(10);
  @$pb.TagNumber(11)
  void clearPrompts() => $_clearField(11);
  @$pb.TagNumber(11)
  Prompts ensurePrompts() => $_ensure(10);

  @$pb.TagNumber(12)
  ConnectAttempt get connect => $_getN(11);
  @$pb.TagNumber(12)
  set connect(ConnectAttempt value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasConnect() => $_has(11);
  @$pb.TagNumber(12)
  void clearConnect() => $_clearField(12);
  @$pb.TagNumber(12)
  ConnectAttempt ensureConnect() => $_ensure(11);
}

/// Spoken prompts (Speak).
class Prompts extends $pb.GeneratedMessage {
  factory Prompts({
    $core.bool? available,
    $core.bool? speaking,
    $core.bool? musicPaused,
    $core.String? detail,
  }) {
    final result = Prompts._();
    if (available != null) result.available = available;
    if (speaking != null) result.speaking = speaking;
    if (musicPaused != null) result.musicPaused = musicPaused;
    if (detail != null) result.detail = detail;
    return result;
  }

  Prompts._();

  factory Prompts.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Prompts()..mergeFromBuffer(data, registry);
  factory Prompts.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Prompts()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Prompts',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: Prompts.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'available')
    ..aOB(2, _omitFieldNames ? '' : 'speaking')
    ..aOB(3, _omitFieldNames ? '' : 'musicPaused')
    ..aOS(4, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Prompts clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Prompts copyWith(void Function(Prompts) updates) =>
      super.copyWith((message) => updates(message as Prompts)) as Prompts;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Prompts() / Prompts.new instead')
  static Prompts create() => Prompts._();
  static $pb.GeneratedMessage $_createMessage() => Prompts._();
  @$core.override
  Prompts createEmptyInstance() => Prompts._();
  @$core.pragma('dart2js:noInline')
  static Prompts getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Prompts>(Prompts.$_createMessage);
  static Prompts? _defaultInstance;

  /// A voice is configured and can be heard. False: Speak is refused, and
  /// `detail` says why.
  @$pb.TagNumber(1)
  $core.bool get available => $_getBF(0);
  @$pb.TagNumber(1)
  set available($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAvailable() => $_has(0);
  @$pb.TagNumber(1)
  void clearAvailable() => $_clearField(1);

  /// A prompt is being said now.
  @$pb.TagNumber(2)
  $core.bool get speaking => $_getBF(1);
  @$pb.TagNumber(2)
  set speaking($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSpeaking() => $_has(1);
  @$pb.TagNumber(2)
  void clearSpeaking() => $_clearField(2);

  /// audio-manager has paused the phone for prompts and will resume it.
  @$pb.TagNumber(3)
  $core.bool get musicPaused => $_getBF(2);
  @$pb.TagNumber(3)
  set musicPaused($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMusicPaused() => $_has(2);
  @$pb.TagNumber(3)
  void clearMusicPaused() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get detail => $_getSZ(3);
  @$pb.TagNumber(4)
  set detail($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDetail() => $_has(3);
  @$pb.TagNumber(4)
  void clearDetail() => $_clearField(4);
}

class ControlRequest extends $pb.GeneratedMessage {
  factory ControlRequest({
    Command? command,
    $core.String? source,
  }) {
    final result = ControlRequest._();
    if (command != null) result.command = command;
    if (source != null) result.source = source;
    return result;
  }

  ControlRequest._();

  factory ControlRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ControlRequest()..mergeFromBuffer(data, registry);
  factory ControlRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ControlRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ControlRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: ControlRequest.$_createMessage)
    ..aE<Command>(1, _omitFieldNames ? '' : 'command',
        enumValues: Command.values)
    ..aOS(2, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ControlRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ControlRequest copyWith(void Function(ControlRequest) updates) =>
      super.copyWith((message) => updates(message as ControlRequest))
          as ControlRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ControlRequest() / ControlRequest.new instead')
  static ControlRequest create() => ControlRequest._();
  static $pb.GeneratedMessage $_createMessage() => ControlRequest._();
  @$core.override
  ControlRequest createEmptyInstance() => ControlRequest._();
  @$core.pragma('dart2js:noInline')
  static ControlRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ControlRequest>(
          ControlRequest.$_createMessage);
  static ControlRequest? _defaultInstance;

  @$pb.TagNumber(1)
  Command get command => $_getN(0);
  @$pb.TagNumber(1)
  set command(Command value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCommand() => $_has(0);
  @$pb.TagNumber(1)
  void clearCommand() => $_clearField(1);

  /// Who asked ("dashboard"), for the log.
  @$pb.TagNumber(2)
  $core.String get source => $_getSZ(1);
  @$pb.TagNumber(2)
  set source($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearSource() => $_clearField(2);
}

class ControlResponse extends $pb.GeneratedMessage {
  factory ControlResponse({
    $core.bool? sent,
    $core.String? detail,
  }) {
    final result = ControlResponse._();
    if (sent != null) result.sent = sent;
    if (detail != null) result.detail = detail;
    return result;
  }

  ControlResponse._();

  factory ControlResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ControlResponse()..mergeFromBuffer(data, registry);
  factory ControlResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ControlResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ControlResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: ControlResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'sent')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ControlResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ControlResponse copyWith(void Function(ControlResponse) updates) =>
      super.copyWith((message) => updates(message as ControlResponse))
          as ControlResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ControlResponse() / ControlResponse.new instead')
  static ControlResponse create() => ControlResponse._();
  static $pb.GeneratedMessage $_createMessage() => ControlResponse._();
  @$core.override
  ControlResponse createEmptyInstance() => ControlResponse._();
  @$core.pragma('dart2js:noInline')
  static ControlResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ControlResponse>(
          ControlResponse.$_createMessage);
  static ControlResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get sent => $_getBF(0);
  @$pb.TagNumber(1)
  set sent($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSent() => $_has(0);
  @$pb.TagNumber(1)
  void clearSent() => $_clearField(1);

  /// Why not, in words for the screen.
  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);
}

class OpenPairingRequest extends $pb.GeneratedMessage {
  factory OpenPairingRequest({
    $core.int? seconds,
    $core.String? source,
  }) {
    final result = OpenPairingRequest._();
    if (seconds != null) result.seconds = seconds;
    if (source != null) result.source = source;
    return result;
  }

  OpenPairingRequest._();

  factory OpenPairingRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpenPairingRequest()..mergeFromBuffer(data, registry);
  factory OpenPairingRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpenPairingRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OpenPairingRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: OpenPairingRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'seconds', fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpenPairingRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpenPairingRequest copyWith(void Function(OpenPairingRequest) updates) =>
      super.copyWith((message) => updates(message as OpenPairingRequest))
          as OpenPairingRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use OpenPairingRequest() / OpenPairingRequest.new instead')
  static OpenPairingRequest create() => OpenPairingRequest._();
  static $pb.GeneratedMessage $_createMessage() => OpenPairingRequest._();
  @$core.override
  OpenPairingRequest createEmptyInstance() => OpenPairingRequest._();
  @$core.pragma('dart2js:noInline')
  static OpenPairingRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<OpenPairingRequest>(
          OpenPairingRequest.$_createMessage);
  static OpenPairingRequest? _defaultInstance;

  /// 0: the configured default.
  @$pb.TagNumber(1)
  $core.int get seconds => $_getIZ(0);
  @$pb.TagNumber(1)
  set seconds($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSeconds() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeconds() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get source => $_getSZ(1);
  @$pb.TagNumber(2)
  set source($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearSource() => $_clearField(2);
}

class OpenPairingResponse extends $pb.GeneratedMessage {
  factory OpenPairingResponse({
    $core.bool? accepted,
    $core.String? detail,
  }) {
    final result = OpenPairingResponse._();
    if (accepted != null) result.accepted = accepted;
    if (detail != null) result.detail = detail;
    return result;
  }

  OpenPairingResponse._();

  factory OpenPairingResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpenPairingResponse()..mergeFromBuffer(data, registry);
  factory OpenPairingResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpenPairingResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OpenPairingResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: OpenPairingResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpenPairingResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpenPairingResponse copyWith(void Function(OpenPairingResponse) updates) =>
      super.copyWith((message) => updates(message as OpenPairingResponse))
          as OpenPairingResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use OpenPairingResponse() / OpenPairingResponse.new instead')
  static OpenPairingResponse create() => OpenPairingResponse._();
  static $pb.GeneratedMessage $_createMessage() => OpenPairingResponse._();
  @$core.override
  OpenPairingResponse createEmptyInstance() => OpenPairingResponse._();
  @$core.pragma('dart2js:noInline')
  static OpenPairingResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<OpenPairingResponse>(
          OpenPairingResponse.$_createMessage);
  static OpenPairingResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get accepted => $_getBF(0);
  @$pb.TagNumber(1)
  set accepted($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccepted() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccepted() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);
}

class ClosePairingRequest extends $pb.GeneratedMessage {
  factory ClosePairingRequest({
    $core.String? source,
  }) {
    final result = ClosePairingRequest._();
    if (source != null) result.source = source;
    return result;
  }

  ClosePairingRequest._();

  factory ClosePairingRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ClosePairingRequest()..mergeFromBuffer(data, registry);
  factory ClosePairingRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ClosePairingRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ClosePairingRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: ClosePairingRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClosePairingRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClosePairingRequest copyWith(void Function(ClosePairingRequest) updates) =>
      super.copyWith((message) => updates(message as ClosePairingRequest))
          as ClosePairingRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ClosePairingRequest() / ClosePairingRequest.new instead')
  static ClosePairingRequest create() => ClosePairingRequest._();
  static $pb.GeneratedMessage $_createMessage() => ClosePairingRequest._();
  @$core.override
  ClosePairingRequest createEmptyInstance() => ClosePairingRequest._();
  @$core.pragma('dart2js:noInline')
  static ClosePairingRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ClosePairingRequest>(
          ClosePairingRequest.$_createMessage);
  static ClosePairingRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get source => $_getSZ(0);
  @$pb.TagNumber(1)
  set source($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSource() => $_has(0);
  @$pb.TagNumber(1)
  void clearSource() => $_clearField(1);
}

class ClosePairingResponse extends $pb.GeneratedMessage {
  factory ClosePairingResponse({
    $core.bool? closing,
  }) {
    final result = ClosePairingResponse._();
    if (closing != null) result.closing = closing;
    return result;
  }

  ClosePairingResponse._();

  factory ClosePairingResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ClosePairingResponse()..mergeFromBuffer(data, registry);
  factory ClosePairingResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ClosePairingResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ClosePairingResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: ClosePairingResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'closing')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClosePairingResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClosePairingResponse copyWith(void Function(ClosePairingResponse) updates) =>
      super.copyWith((message) => updates(message as ClosePairingResponse))
          as ClosePairingResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ClosePairingResponse() / ClosePairingResponse.new instead')
  static ClosePairingResponse create() => ClosePairingResponse._();
  static $pb.GeneratedMessage $_createMessage() => ClosePairingResponse._();
  @$core.override
  ClosePairingResponse createEmptyInstance() => ClosePairingResponse._();
  @$core.pragma('dart2js:noInline')
  static ClosePairingResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ClosePairingResponse>(
          ClosePairingResponse.$_createMessage);
  static ClosePairingResponse? _defaultInstance;

  /// False: it wasn't open.
  @$pb.TagNumber(1)
  $core.bool get closing => $_getBF(0);
  @$pb.TagNumber(1)
  set closing($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasClosing() => $_has(0);
  @$pb.TagNumber(1)
  void clearClosing() => $_clearField(1);
}

class ConnectPhoneRequest extends $pb.GeneratedMessage {
  factory ConnectPhoneRequest({
    $core.String? address,
    $core.String? source,
  }) {
    final result = ConnectPhoneRequest._();
    if (address != null) result.address = address;
    if (source != null) result.source = source;
    return result;
  }

  ConnectPhoneRequest._();

  factory ConnectPhoneRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ConnectPhoneRequest()..mergeFromBuffer(data, registry);
  factory ConnectPhoneRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ConnectPhoneRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectPhoneRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: ConnectPhoneRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..aOS(2, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectPhoneRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectPhoneRequest copyWith(void Function(ConnectPhoneRequest) updates) =>
      super.copyWith((message) => updates(message as ConnectPhoneRequest))
          as ConnectPhoneRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ConnectPhoneRequest() / ConnectPhoneRequest.new instead')
  static ConnectPhoneRequest create() => ConnectPhoneRequest._();
  static $pb.GeneratedMessage $_createMessage() => ConnectPhoneRequest._();
  @$core.override
  ConnectPhoneRequest createEmptyInstance() => ConnectPhoneRequest._();
  @$core.pragma('dart2js:noInline')
  static ConnectPhoneRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectPhoneRequest>(
          ConnectPhoneRequest.$_createMessage);
  static ConnectPhoneRequest? _defaultInstance;

  /// Phone.address of a phone in `known`.
  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get source => $_getSZ(1);
  @$pb.TagNumber(2)
  set source($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearSource() => $_clearField(2);
}

class ConnectPhoneResponse extends $pb.GeneratedMessage {
  factory ConnectPhoneResponse({
    $core.bool? accepted,
    $core.String? detail,
  }) {
    final result = ConnectPhoneResponse._();
    if (accepted != null) result.accepted = accepted;
    if (detail != null) result.detail = detail;
    return result;
  }

  ConnectPhoneResponse._();

  factory ConnectPhoneResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ConnectPhoneResponse()..mergeFromBuffer(data, registry);
  factory ConnectPhoneResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ConnectPhoneResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectPhoneResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: ConnectPhoneResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectPhoneResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectPhoneResponse copyWith(void Function(ConnectPhoneResponse) updates) =>
      super.copyWith((message) => updates(message as ConnectPhoneResponse))
          as ConnectPhoneResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ConnectPhoneResponse() / ConnectPhoneResponse.new instead')
  static ConnectPhoneResponse create() => ConnectPhoneResponse._();
  static $pb.GeneratedMessage $_createMessage() => ConnectPhoneResponse._();
  @$core.override
  ConnectPhoneResponse createEmptyInstance() => ConnectPhoneResponse._();
  @$core.pragma('dart2js:noInline')
  static ConnectPhoneResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectPhoneResponse>(
          ConnectPhoneResponse.$_createMessage);
  static ConnectPhoneResponse? _defaultInstance;

  /// True: the attempt has started.
  @$pb.TagNumber(1)
  $core.bool get accepted => $_getBF(0);
  @$pb.TagNumber(1)
  set accepted($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccepted() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccepted() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);
}

class DisconnectPhoneRequest extends $pb.GeneratedMessage {
  factory DisconnectPhoneRequest({
    $core.String? address,
    $core.String? source,
  }) {
    final result = DisconnectPhoneRequest._();
    if (address != null) result.address = address;
    if (source != null) result.source = source;
    return result;
  }

  DisconnectPhoneRequest._();

  factory DisconnectPhoneRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DisconnectPhoneRequest()..mergeFromBuffer(data, registry);
  factory DisconnectPhoneRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DisconnectPhoneRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DisconnectPhoneRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: DisconnectPhoneRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..aOS(2, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DisconnectPhoneRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DisconnectPhoneRequest copyWith(
          void Function(DisconnectPhoneRequest) updates) =>
      super.copyWith((message) => updates(message as DisconnectPhoneRequest))
          as DisconnectPhoneRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DisconnectPhoneRequest() / DisconnectPhoneRequest.new instead')
  static DisconnectPhoneRequest create() => DisconnectPhoneRequest._();
  static $pb.GeneratedMessage $_createMessage() => DisconnectPhoneRequest._();
  @$core.override
  DisconnectPhoneRequest createEmptyInstance() => DisconnectPhoneRequest._();
  @$core.pragma('dart2js:noInline')
  static DisconnectPhoneRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DisconnectPhoneRequest>(
          DisconnectPhoneRequest.$_createMessage);
  static DisconnectPhoneRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get source => $_getSZ(1);
  @$pb.TagNumber(2)
  set source($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearSource() => $_clearField(2);
}

class DisconnectPhoneResponse extends $pb.GeneratedMessage {
  factory DisconnectPhoneResponse({
    $core.bool? accepted,
    $core.String? detail,
  }) {
    final result = DisconnectPhoneResponse._();
    if (accepted != null) result.accepted = accepted;
    if (detail != null) result.detail = detail;
    return result;
  }

  DisconnectPhoneResponse._();

  factory DisconnectPhoneResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DisconnectPhoneResponse()..mergeFromBuffer(data, registry);
  factory DisconnectPhoneResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DisconnectPhoneResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DisconnectPhoneResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: DisconnectPhoneResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DisconnectPhoneResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DisconnectPhoneResponse copyWith(
          void Function(DisconnectPhoneResponse) updates) =>
      super.copyWith((message) => updates(message as DisconnectPhoneResponse))
          as DisconnectPhoneResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DisconnectPhoneResponse() / DisconnectPhoneResponse.new instead')
  static DisconnectPhoneResponse create() => DisconnectPhoneResponse._();
  static $pb.GeneratedMessage $_createMessage() => DisconnectPhoneResponse._();
  @$core.override
  DisconnectPhoneResponse createEmptyInstance() => DisconnectPhoneResponse._();
  @$core.pragma('dart2js:noInline')
  static DisconnectPhoneResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DisconnectPhoneResponse>(
          DisconnectPhoneResponse.$_createMessage);
  static DisconnectPhoneResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get accepted => $_getBF(0);
  @$pb.TagNumber(1)
  set accepted($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccepted() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccepted() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);
}

class ForgetPhoneRequest extends $pb.GeneratedMessage {
  factory ForgetPhoneRequest({
    $core.String? address,
    $core.String? source,
  }) {
    final result = ForgetPhoneRequest._();
    if (address != null) result.address = address;
    if (source != null) result.source = source;
    return result;
  }

  ForgetPhoneRequest._();

  factory ForgetPhoneRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ForgetPhoneRequest()..mergeFromBuffer(data, registry);
  factory ForgetPhoneRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ForgetPhoneRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ForgetPhoneRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: ForgetPhoneRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..aOS(2, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ForgetPhoneRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ForgetPhoneRequest copyWith(void Function(ForgetPhoneRequest) updates) =>
      super.copyWith((message) => updates(message as ForgetPhoneRequest))
          as ForgetPhoneRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ForgetPhoneRequest() / ForgetPhoneRequest.new instead')
  static ForgetPhoneRequest create() => ForgetPhoneRequest._();
  static $pb.GeneratedMessage $_createMessage() => ForgetPhoneRequest._();
  @$core.override
  ForgetPhoneRequest createEmptyInstance() => ForgetPhoneRequest._();
  @$core.pragma('dart2js:noInline')
  static ForgetPhoneRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ForgetPhoneRequest>(
          ForgetPhoneRequest.$_createMessage);
  static ForgetPhoneRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get source => $_getSZ(1);
  @$pb.TagNumber(2)
  set source($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearSource() => $_clearField(2);
}

class ForgetPhoneResponse extends $pb.GeneratedMessage {
  factory ForgetPhoneResponse({
    $core.bool? accepted,
    $core.String? detail,
  }) {
    final result = ForgetPhoneResponse._();
    if (accepted != null) result.accepted = accepted;
    if (detail != null) result.detail = detail;
    return result;
  }

  ForgetPhoneResponse._();

  factory ForgetPhoneResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ForgetPhoneResponse()..mergeFromBuffer(data, registry);
  factory ForgetPhoneResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ForgetPhoneResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ForgetPhoneResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: ForgetPhoneResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ForgetPhoneResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ForgetPhoneResponse copyWith(void Function(ForgetPhoneResponse) updates) =>
      super.copyWith((message) => updates(message as ForgetPhoneResponse))
          as ForgetPhoneResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ForgetPhoneResponse() / ForgetPhoneResponse.new instead')
  static ForgetPhoneResponse create() => ForgetPhoneResponse._();
  static $pb.GeneratedMessage $_createMessage() => ForgetPhoneResponse._();
  @$core.override
  ForgetPhoneResponse createEmptyInstance() => ForgetPhoneResponse._();
  @$core.pragma('dart2js:noInline')
  static ForgetPhoneResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ForgetPhoneResponse>(
          ForgetPhoneResponse.$_createMessage);
  static ForgetPhoneResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get accepted => $_getBF(0);
  @$pb.TagNumber(1)
  set accepted($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccepted() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccepted() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);
}

class ConfirmPairingRequest extends $pb.GeneratedMessage {
  factory ConfirmPairingRequest({
    $fixnum.Int64? id,
    $core.bool? accept,
    $core.String? source,
  }) {
    final result = ConfirmPairingRequest._();
    if (id != null) result.id = id;
    if (accept != null) result.accept = accept;
    if (source != null) result.source = source;
    return result;
  }

  ConfirmPairingRequest._();

  factory ConfirmPairingRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ConfirmPairingRequest()..mergeFromBuffer(data, registry);
  factory ConfirmPairingRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ConfirmPairingRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConfirmPairingRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: ConfirmPairingRequest.$_createMessage)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'id', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(2, _omitFieldNames ? '' : 'accept')
    ..aOS(3, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfirmPairingRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfirmPairingRequest copyWith(
          void Function(ConfirmPairingRequest) updates) =>
      super.copyWith((message) => updates(message as ConfirmPairingRequest))
          as ConfirmPairingRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ConfirmPairingRequest() / ConfirmPairingRequest.new instead')
  static ConfirmPairingRequest create() => ConfirmPairingRequest._();
  static $pb.GeneratedMessage $_createMessage() => ConfirmPairingRequest._();
  @$core.override
  ConfirmPairingRequest createEmptyInstance() => ConfirmPairingRequest._();
  @$core.pragma('dart2js:noInline')
  static ConfirmPairingRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConfirmPairingRequest>(
          ConfirmPairingRequest.$_createMessage);
  static ConfirmPairingRequest? _defaultInstance;

  /// PasskeyQuestion.id.
  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// True: the codes match.
  @$pb.TagNumber(2)
  $core.bool get accept => $_getBF(1);
  @$pb.TagNumber(2)
  set accept($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAccept() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccept() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get source => $_getSZ(2);
  @$pb.TagNumber(3)
  set source($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSource() => $_has(2);
  @$pb.TagNumber(3)
  void clearSource() => $_clearField(3);
}

class ConfirmPairingResponse extends $pb.GeneratedMessage {
  factory ConfirmPairingResponse({
    $core.bool? answered,
    $core.String? detail,
  }) {
    final result = ConfirmPairingResponse._();
    if (answered != null) result.answered = answered;
    if (detail != null) result.detail = detail;
    return result;
  }

  ConfirmPairingResponse._();

  factory ConfirmPairingResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ConfirmPairingResponse()..mergeFromBuffer(data, registry);
  factory ConfirmPairingResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ConfirmPairingResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConfirmPairingResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: ConfirmPairingResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'answered')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfirmPairingResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfirmPairingResponse copyWith(
          void Function(ConfirmPairingResponse) updates) =>
      super.copyWith((message) => updates(message as ConfirmPairingResponse))
          as ConfirmPairingResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ConfirmPairingResponse() / ConfirmPairingResponse.new instead')
  static ConfirmPairingResponse create() => ConfirmPairingResponse._();
  static $pb.GeneratedMessage $_createMessage() => ConfirmPairingResponse._();
  @$core.override
  ConfirmPairingResponse createEmptyInstance() => ConfirmPairingResponse._();
  @$core.pragma('dart2js:noInline')
  static ConfirmPairingResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConfirmPairingResponse>(
          ConfirmPairingResponse.$_createMessage);
  static ConfirmPairingResponse? _defaultInstance;

  /// False: no such question (answered, timed out or cancelled).
  @$pb.TagNumber(1)
  $core.bool get answered => $_getBF(0);
  @$pb.TagNumber(1)
  set answered($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAnswered() => $_has(0);
  @$pb.TagNumber(1)
  void clearAnswered() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);
}

/// The driver's speaker settings. Each is limited by SpeakerLimits.
class SpeakerSettings extends $pb.GeneratedMessage {
  factory SpeakerSettings({
    $core.int? fader,
    $core.int? balance,
    $core.int? subLevelDb,
    $core.int? crossoverHz,
  }) {
    final result = SpeakerSettings._();
    if (fader != null) result.fader = fader;
    if (balance != null) result.balance = balance;
    if (subLevelDb != null) result.subLevelDb = subLevelDb;
    if (crossoverHz != null) result.crossoverHz = crossoverHz;
    return result;
  }

  SpeakerSettings._();

  factory SpeakerSettings.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SpeakerSettings()..mergeFromBuffer(data, registry);
  factory SpeakerSettings.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SpeakerSettings()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SpeakerSettings',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: SpeakerSettings.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'fader')
    ..aI(2, _omitFieldNames ? '' : 'balance')
    ..aI(3, _omitFieldNames ? '' : 'subLevelDb')
    ..aI(4, _omitFieldNames ? '' : 'crossoverHz',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SpeakerSettings clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SpeakerSettings copyWith(void Function(SpeakerSettings) updates) =>
      super.copyWith((message) => updates(message as SpeakerSettings))
          as SpeakerSettings;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SpeakerSettings() / SpeakerSettings.new instead')
  static SpeakerSettings create() => SpeakerSettings._();
  static $pb.GeneratedMessage $_createMessage() => SpeakerSettings._();
  @$core.override
  SpeakerSettings createEmptyInstance() => SpeakerSettings._();
  @$core.pragma('dart2js:noInline')
  static SpeakerSettings getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SpeakerSettings>(
          SpeakerSettings.$_createMessage);
  static SpeakerSettings? _defaultInstance;

  /// Negative: towards the rear; positive: towards the front. Each step
  /// turns the other pair down by `step_db`; the last step mutes it.
  @$pb.TagNumber(1)
  $core.int get fader => $_getIZ(0);
  @$pb.TagNumber(1)
  set fader($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFader() => $_has(0);
  @$pb.TagNumber(1)
  void clearFader() => $_clearField(1);

  /// Negative: towards the left; positive: towards the right.
  @$pb.TagNumber(2)
  $core.int get balance => $_getIZ(1);
  @$pb.TagNumber(2)
  set balance($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBalance() => $_has(1);
  @$pb.TagNumber(2)
  void clearBalance() => $_clearField(2);

  /// The sub's level in dB, relative to the configured reference.
  @$pb.TagNumber(3)
  $core.int get subLevelDb => $_getIZ(2);
  @$pb.TagNumber(3)
  set subLevelDb($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSubLevelDb() => $_has(2);
  @$pb.TagNumber(3)
  void clearSubLevelDb() => $_clearField(3);

  /// Where the speakers hand over to the sub, in Hz (example values only;
  /// tune in the truck, CLAUDE.md rule 10).
  @$pb.TagNumber(4)
  $core.int get crossoverHz => $_getIZ(3);
  @$pb.TagNumber(4)
  set crossoverHz($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCrossoverHz() => $_has(3);
  @$pb.TagNumber(4)
  void clearCrossoverHz() => $_clearField(4);
}

/// The configured limits (examples from audio-manager's configuration, not
/// recommendations).
class SpeakerLimits extends $pb.GeneratedMessage {
  factory SpeakerLimits({
    $core.int? steps,
    $core.double? stepDb,
    $core.int? subMinDb,
    $core.int? subMaxDb,
    $core.int? crossoverMinHz,
    $core.int? crossoverMaxHz,
    $core.int? crossoverStepHz,
  }) {
    final result = SpeakerLimits._();
    if (steps != null) result.steps = steps;
    if (stepDb != null) result.stepDb = stepDb;
    if (subMinDb != null) result.subMinDb = subMinDb;
    if (subMaxDb != null) result.subMaxDb = subMaxDb;
    if (crossoverMinHz != null) result.crossoverMinHz = crossoverMinHz;
    if (crossoverMaxHz != null) result.crossoverMaxHz = crossoverMaxHz;
    if (crossoverStepHz != null) result.crossoverStepHz = crossoverStepHz;
    return result;
  }

  SpeakerLimits._();

  factory SpeakerLimits.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SpeakerLimits()..mergeFromBuffer(data, registry);
  factory SpeakerLimits.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SpeakerLimits()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SpeakerLimits',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: SpeakerLimits.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'steps')
    ..aD(2, _omitFieldNames ? '' : 'stepDb', fieldType: $pb.PbFieldType.OF)
    ..aI(3, _omitFieldNames ? '' : 'subMinDb')
    ..aI(4, _omitFieldNames ? '' : 'subMaxDb')
    ..aI(5, _omitFieldNames ? '' : 'crossoverMinHz',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'crossoverMaxHz',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'crossoverStepHz',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SpeakerLimits clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SpeakerLimits copyWith(void Function(SpeakerLimits) updates) =>
      super.copyWith((message) => updates(message as SpeakerLimits))
          as SpeakerLimits;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SpeakerLimits() / SpeakerLimits.new instead')
  static SpeakerLimits create() => SpeakerLimits._();
  static $pb.GeneratedMessage $_createMessage() => SpeakerLimits._();
  @$core.override
  SpeakerLimits createEmptyInstance() => SpeakerLimits._();
  @$core.pragma('dart2js:noInline')
  static SpeakerLimits getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SpeakerLimits>(
          SpeakerLimits.$_createMessage);
  static SpeakerLimits? _defaultInstance;

  /// fader and balance run from -steps to +steps.
  @$pb.TagNumber(1)
  $core.int get steps => $_getIZ(0);
  @$pb.TagNumber(1)
  set steps($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSteps() => $_has(0);
  @$pb.TagNumber(1)
  void clearSteps() => $_clearField(1);

  /// dB per step.
  @$pb.TagNumber(2)
  $core.double get stepDb => $_getN(1);
  @$pb.TagNumber(2)
  set stepDb($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStepDb() => $_has(1);
  @$pb.TagNumber(2)
  void clearStepDb() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get subMinDb => $_getIZ(2);
  @$pb.TagNumber(3)
  set subMinDb($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSubMinDb() => $_has(2);
  @$pb.TagNumber(3)
  void clearSubMinDb() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get subMaxDb => $_getIZ(3);
  @$pb.TagNumber(4)
  set subMaxDb($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSubMaxDb() => $_has(3);
  @$pb.TagNumber(4)
  void clearSubMaxDb() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get crossoverMinHz => $_getIZ(4);
  @$pb.TagNumber(5)
  set crossoverMinHz($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCrossoverMinHz() => $_has(4);
  @$pb.TagNumber(5)
  void clearCrossoverMinHz() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get crossoverMaxHz => $_getIZ(5);
  @$pb.TagNumber(6)
  set crossoverMaxHz($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCrossoverMaxHz() => $_has(5);
  @$pb.TagNumber(6)
  void clearCrossoverMaxHz() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get crossoverStepHz => $_getIZ(6);
  @$pb.TagNumber(7)
  set crossoverStepHz($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasCrossoverStepHz() => $_has(6);
  @$pb.TagNumber(7)
  void clearCrossoverStepHz() => $_clearField(7);
}

class GetSpeakerSettingsRequest extends $pb.GeneratedMessage {
  factory GetSpeakerSettingsRequest() => GetSpeakerSettingsRequest._();

  GetSpeakerSettingsRequest._();

  factory GetSpeakerSettingsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetSpeakerSettingsRequest()..mergeFromBuffer(data, registry);
  factory GetSpeakerSettingsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetSpeakerSettingsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetSpeakerSettingsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: GetSpeakerSettingsRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetSpeakerSettingsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetSpeakerSettingsRequest copyWith(
          void Function(GetSpeakerSettingsRequest) updates) =>
      super.copyWith((message) => updates(message as GetSpeakerSettingsRequest))
          as GetSpeakerSettingsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetSpeakerSettingsRequest() / GetSpeakerSettingsRequest.new instead')
  static GetSpeakerSettingsRequest create() => GetSpeakerSettingsRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      GetSpeakerSettingsRequest._();
  @$core.override
  GetSpeakerSettingsRequest createEmptyInstance() =>
      GetSpeakerSettingsRequest._();
  @$core.pragma('dart2js:noInline')
  static GetSpeakerSettingsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetSpeakerSettingsRequest>(
          GetSpeakerSettingsRequest.$_createMessage);
  static GetSpeakerSettingsRequest? _defaultInstance;
}

class GetSpeakerSettingsResponse extends $pb.GeneratedMessage {
  factory GetSpeakerSettingsResponse({
    SpeakerSettings? settings,
    SpeakerLimits? limits,
    SpeakerSettings? defaults,
  }) {
    final result = GetSpeakerSettingsResponse._();
    if (settings != null) result.settings = settings;
    if (limits != null) result.limits = limits;
    if (defaults != null) result.defaults = defaults;
    return result;
  }

  GetSpeakerSettingsResponse._();

  factory GetSpeakerSettingsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetSpeakerSettingsResponse()..mergeFromBuffer(data, registry);
  factory GetSpeakerSettingsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetSpeakerSettingsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetSpeakerSettingsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: GetSpeakerSettingsResponse.$_createMessage)
    ..aOM<SpeakerSettings>(1, _omitFieldNames ? '' : 'settings',
        subBuilder: SpeakerSettings.$_createMessage)
    ..aOM<SpeakerLimits>(2, _omitFieldNames ? '' : 'limits',
        subBuilder: SpeakerLimits.$_createMessage)
    ..aOM<SpeakerSettings>(3, _omitFieldNames ? '' : 'defaults',
        subBuilder: SpeakerSettings.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetSpeakerSettingsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetSpeakerSettingsResponse copyWith(
          void Function(GetSpeakerSettingsResponse) updates) =>
      super.copyWith(
              (message) => updates(message as GetSpeakerSettingsResponse))
          as GetSpeakerSettingsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetSpeakerSettingsResponse() / GetSpeakerSettingsResponse.new instead')
  static GetSpeakerSettingsResponse create() => GetSpeakerSettingsResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      GetSpeakerSettingsResponse._();
  @$core.override
  GetSpeakerSettingsResponse createEmptyInstance() =>
      GetSpeakerSettingsResponse._();
  @$core.pragma('dart2js:noInline')
  static GetSpeakerSettingsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetSpeakerSettingsResponse>(
          GetSpeakerSettingsResponse.$_createMessage);
  static GetSpeakerSettingsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  SpeakerSettings get settings => $_getN(0);
  @$pb.TagNumber(1)
  set settings(SpeakerSettings value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSettings() => $_has(0);
  @$pb.TagNumber(1)
  void clearSettings() => $_clearField(1);
  @$pb.TagNumber(1)
  SpeakerSettings ensureSettings() => $_ensure(0);

  @$pb.TagNumber(2)
  SpeakerLimits get limits => $_getN(1);
  @$pb.TagNumber(2)
  set limits(SpeakerLimits value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasLimits() => $_has(1);
  @$pb.TagNumber(2)
  void clearLimits() => $_clearField(2);
  @$pb.TagNumber(2)
  SpeakerLimits ensureLimits() => $_ensure(1);

  /// The configured defaults (Reset).
  @$pb.TagNumber(3)
  SpeakerSettings get defaults => $_getN(2);
  @$pb.TagNumber(3)
  set defaults(SpeakerSettings value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasDefaults() => $_has(2);
  @$pb.TagNumber(3)
  void clearDefaults() => $_clearField(3);
  @$pb.TagNumber(3)
  SpeakerSettings ensureDefaults() => $_ensure(2);
}

class SetSpeakerSettingsRequest extends $pb.GeneratedMessage {
  factory SetSpeakerSettingsRequest({
    SpeakerSettings? settings,
    $core.String? source,
  }) {
    final result = SetSpeakerSettingsRequest._();
    if (settings != null) result.settings = settings;
    if (source != null) result.source = source;
    return result;
  }

  SetSpeakerSettingsRequest._();

  factory SetSpeakerSettingsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetSpeakerSettingsRequest()..mergeFromBuffer(data, registry);
  factory SetSpeakerSettingsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetSpeakerSettingsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetSpeakerSettingsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: SetSpeakerSettingsRequest.$_createMessage)
    ..aOM<SpeakerSettings>(1, _omitFieldNames ? '' : 'settings',
        subBuilder: SpeakerSettings.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetSpeakerSettingsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetSpeakerSettingsRequest copyWith(
          void Function(SetSpeakerSettingsRequest) updates) =>
      super.copyWith((message) => updates(message as SetSpeakerSettingsRequest))
          as SetSpeakerSettingsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SetSpeakerSettingsRequest() / SetSpeakerSettingsRequest.new instead')
  static SetSpeakerSettingsRequest create() => SetSpeakerSettingsRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      SetSpeakerSettingsRequest._();
  @$core.override
  SetSpeakerSettingsRequest createEmptyInstance() =>
      SetSpeakerSettingsRequest._();
  @$core.pragma('dart2js:noInline')
  static SetSpeakerSettingsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetSpeakerSettingsRequest>(
          SetSpeakerSettingsRequest.$_createMessage);
  static SetSpeakerSettingsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  SpeakerSettings get settings => $_getN(0);
  @$pb.TagNumber(1)
  set settings(SpeakerSettings value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSettings() => $_has(0);
  @$pb.TagNumber(1)
  void clearSettings() => $_clearField(1);
  @$pb.TagNumber(1)
  SpeakerSettings ensureSettings() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get source => $_getSZ(1);
  @$pb.TagNumber(2)
  set source($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearSource() => $_clearField(2);
}

class SetSpeakerSettingsResponse extends $pb.GeneratedMessage {
  factory SetSpeakerSettingsResponse({
    $core.bool? applied,
    $core.String? detail,
    SpeakerSettings? settings,
  }) {
    final result = SetSpeakerSettingsResponse._();
    if (applied != null) result.applied = applied;
    if (detail != null) result.detail = detail;
    if (settings != null) result.settings = settings;
    return result;
  }

  SetSpeakerSettingsResponse._();

  factory SetSpeakerSettingsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetSpeakerSettingsResponse()..mergeFromBuffer(data, registry);
  factory SetSpeakerSettingsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetSpeakerSettingsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetSpeakerSettingsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: SetSpeakerSettingsResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'applied')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..aOM<SpeakerSettings>(3, _omitFieldNames ? '' : 'settings',
        subBuilder: SpeakerSettings.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetSpeakerSettingsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetSpeakerSettingsResponse copyWith(
          void Function(SetSpeakerSettingsResponse) updates) =>
      super.copyWith(
              (message) => updates(message as SetSpeakerSettingsResponse))
          as SetSpeakerSettingsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SetSpeakerSettingsResponse() / SetSpeakerSettingsResponse.new instead')
  static SetSpeakerSettingsResponse create() => SetSpeakerSettingsResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      SetSpeakerSettingsResponse._();
  @$core.override
  SetSpeakerSettingsResponse createEmptyInstance() =>
      SetSpeakerSettingsResponse._();
  @$core.pragma('dart2js:noInline')
  static SetSpeakerSettingsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetSpeakerSettingsResponse>(
          SetSpeakerSettingsResponse.$_createMessage);
  static SetSpeakerSettingsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get applied => $_getBF(0);
  @$pb.TagNumber(1)
  set applied($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasApplied() => $_has(0);
  @$pb.TagNumber(1)
  void clearApplied() => $_clearField(1);

  /// Why not, or what happened (e.g. a failed live change was applied by
  /// restarting the filter-chain).
  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);

  @$pb.TagNumber(3)
  SpeakerSettings get settings => $_getN(2);
  @$pb.TagNumber(3)
  set settings(SpeakerSettings value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasSettings() => $_has(2);
  @$pb.TagNumber(3)
  void clearSettings() => $_clearField(3);
  @$pb.TagNumber(3)
  SpeakerSettings ensureSettings() => $_ensure(2);
}

class SpeakRequest extends $pb.GeneratedMessage {
  factory SpeakRequest({
    $core.String? text,
    $core.String? source,
  }) {
    final result = SpeakRequest._();
    if (text != null) result.text = text;
    if (source != null) result.source = source;
    return result;
  }

  SpeakRequest._();

  factory SpeakRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SpeakRequest()..mergeFromBuffer(data, registry);
  factory SpeakRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SpeakRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SpeakRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: SpeakRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOS(2, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SpeakRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SpeakRequest copyWith(void Function(SpeakRequest) updates) =>
      super.copyWith((message) => updates(message as SpeakRequest))
          as SpeakRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SpeakRequest() / SpeakRequest.new instead')
  static SpeakRequest create() => SpeakRequest._();
  static $pb.GeneratedMessage $_createMessage() => SpeakRequest._();
  @$core.override
  SpeakRequest createEmptyInstance() => SpeakRequest._();
  @$core.pragma('dart2js:noInline')
  static SpeakRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SpeakRequest>(
          SpeakRequest.$_createMessage);
  static SpeakRequest? _defaultInstance;

  /// At most 500 characters; control characters are dropped.
  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  /// Who asked ("navigation"), for the log.
  @$pb.TagNumber(2)
  $core.String get source => $_getSZ(1);
  @$pb.TagNumber(2)
  set source($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearSource() => $_clearField(2);
}

class SpeakResponse extends $pb.GeneratedMessage {
  factory SpeakResponse({
    $core.bool? accepted,
    $core.String? detail,
  }) {
    final result = SpeakResponse._();
    if (accepted != null) result.accepted = accepted;
    if (detail != null) result.detail = detail;
    return result;
  }

  SpeakResponse._();

  factory SpeakResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SpeakResponse()..mergeFromBuffer(data, registry);
  factory SpeakResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SpeakResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SpeakResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: SpeakResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SpeakResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SpeakResponse copyWith(void Function(SpeakResponse) updates) =>
      super.copyWith((message) => updates(message as SpeakResponse))
          as SpeakResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SpeakResponse() / SpeakResponse.new instead')
  static SpeakResponse create() => SpeakResponse._();
  static $pb.GeneratedMessage $_createMessage() => SpeakResponse._();
  @$core.override
  SpeakResponse createEmptyInstance() => SpeakResponse._();
  @$core.pragma('dart2js:noInline')
  static SpeakResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SpeakResponse>(
          SpeakResponse.$_createMessage);
  static SpeakResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get accepted => $_getBF(0);
  @$pb.TagNumber(1)
  set accepted($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccepted() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccepted() => $_clearField(1);

  /// Why not, in words for the screen.
  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);
}

class StopSpeakingRequest extends $pb.GeneratedMessage {
  factory StopSpeakingRequest({
    $core.String? source,
  }) {
    final result = StopSpeakingRequest._();
    if (source != null) result.source = source;
    return result;
  }

  StopSpeakingRequest._();

  factory StopSpeakingRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StopSpeakingRequest()..mergeFromBuffer(data, registry);
  factory StopSpeakingRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StopSpeakingRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StopSpeakingRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: StopSpeakingRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StopSpeakingRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StopSpeakingRequest copyWith(void Function(StopSpeakingRequest) updates) =>
      super.copyWith((message) => updates(message as StopSpeakingRequest))
          as StopSpeakingRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use StopSpeakingRequest() / StopSpeakingRequest.new instead')
  static StopSpeakingRequest create() => StopSpeakingRequest._();
  static $pb.GeneratedMessage $_createMessage() => StopSpeakingRequest._();
  @$core.override
  StopSpeakingRequest createEmptyInstance() => StopSpeakingRequest._();
  @$core.pragma('dart2js:noInline')
  static StopSpeakingRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StopSpeakingRequest>(
          StopSpeakingRequest.$_createMessage);
  static StopSpeakingRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get source => $_getSZ(0);
  @$pb.TagNumber(1)
  set source($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSource() => $_has(0);
  @$pb.TagNumber(1)
  void clearSource() => $_clearField(1);
}

class StopSpeakingResponse extends $pb.GeneratedMessage {
  factory StopSpeakingResponse({
    $core.bool? stopped,
  }) {
    final result = StopSpeakingResponse._();
    if (stopped != null) result.stopped = stopped;
    return result;
  }

  StopSpeakingResponse._();

  factory StopSpeakingResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StopSpeakingResponse()..mergeFromBuffer(data, registry);
  factory StopSpeakingResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StopSpeakingResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StopSpeakingResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: StopSpeakingResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'stopped')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StopSpeakingResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StopSpeakingResponse copyWith(void Function(StopSpeakingResponse) updates) =>
      super.copyWith((message) => updates(message as StopSpeakingResponse))
          as StopSpeakingResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use StopSpeakingResponse() / StopSpeakingResponse.new instead')
  static StopSpeakingResponse create() => StopSpeakingResponse._();
  static $pb.GeneratedMessage $_createMessage() => StopSpeakingResponse._();
  @$core.override
  StopSpeakingResponse createEmptyInstance() => StopSpeakingResponse._();
  @$core.pragma('dart2js:noInline')
  static StopSpeakingResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StopSpeakingResponse>(
          StopSpeakingResponse.$_createMessage);
  static StopSpeakingResponse? _defaultInstance;

  /// False: nothing was being said.
  @$pb.TagNumber(1)
  $core.bool get stopped => $_getBF(0);
  @$pb.TagNumber(1)
  set stopped($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStopped() => $_has(0);
  @$pb.TagNumber(1)
  void clearStopped() => $_clearField(1);
}

class GetCoverArtRequest extends $pb.GeneratedMessage {
  factory GetCoverArtRequest({
    $core.String? id,
  }) {
    final result = GetCoverArtRequest._();
    if (id != null) result.id = id;
    return result;
  }

  GetCoverArtRequest._();

  factory GetCoverArtRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetCoverArtRequest()..mergeFromBuffer(data, registry);
  factory GetCoverArtRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetCoverArtRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetCoverArtRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: GetCoverArtRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetCoverArtRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetCoverArtRequest copyWith(void Function(GetCoverArtRequest) updates) =>
      super.copyWith((message) => updates(message as GetCoverArtRequest))
          as GetCoverArtRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetCoverArtRequest() / GetCoverArtRequest.new instead')
  static GetCoverArtRequest create() => GetCoverArtRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetCoverArtRequest._();
  @$core.override
  GetCoverArtRequest createEmptyInstance() => GetCoverArtRequest._();
  @$core.pragma('dart2js:noInline')
  static GetCoverArtRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetCoverArtRequest>(
          GetCoverArtRequest.$_createMessage);
  static GetCoverArtRequest? _defaultInstance;

  /// NowPlaying.cover_art_id.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

class GetCoverArtResponse extends $pb.GeneratedMessage {
  factory GetCoverArtResponse({
    $core.bool? found,
    $core.List<$core.int>? image,
    $core.String? mimeType,
  }) {
    final result = GetCoverArtResponse._();
    if (found != null) result.found = found;
    if (image != null) result.image = image;
    if (mimeType != null) result.mimeType = mimeType;
    return result;
  }

  GetCoverArtResponse._();

  factory GetCoverArtResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetCoverArtResponse()..mergeFromBuffer(data, registry);
  factory GetCoverArtResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetCoverArtResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetCoverArtResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: GetCoverArtResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'found')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'image', $pb.PbFieldType.OY)
    ..aOS(3, _omitFieldNames ? '' : 'mimeType')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetCoverArtResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetCoverArtResponse copyWith(void Function(GetCoverArtResponse) updates) =>
      super.copyWith((message) => updates(message as GetCoverArtResponse))
          as GetCoverArtResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use GetCoverArtResponse() / GetCoverArtResponse.new instead')
  static GetCoverArtResponse create() => GetCoverArtResponse._();
  static $pb.GeneratedMessage $_createMessage() => GetCoverArtResponse._();
  @$core.override
  GetCoverArtResponse createEmptyInstance() => GetCoverArtResponse._();
  @$core.pragma('dart2js:noInline')
  static GetCoverArtResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetCoverArtResponse>(
          GetCoverArtResponse.$_createMessage);
  static GetCoverArtResponse? _defaultInstance;

  /// False: not the current picture (the track changed, or the phone went).
  @$pb.TagNumber(1)
  $core.bool get found => $_getBF(0);
  @$pb.TagNumber(1)
  set found($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFound() => $_has(0);
  @$pb.TagNumber(1)
  void clearFound() => $_clearField(1);

  /// The picture's bytes, as the phone sent them (a JPEG from a phone; at
  /// most 1 MiB).
  @$pb.TagNumber(2)
  $core.List<$core.int> get image => $_getN(1);
  @$pb.TagNumber(2)
  set image($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasImage() => $_has(1);
  @$pb.TagNumber(2)
  void clearImage() => $_clearField(2);

  /// "image/jpeg", "image/png" or "image/bmp" (the simulated phone).
  @$pb.TagNumber(3)
  $core.String get mimeType => $_getSZ(2);
  @$pb.TagNumber(3)
  set mimeType($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMimeType() => $_has(2);
  @$pb.TagNumber(3)
  void clearMimeType() => $_clearField(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
