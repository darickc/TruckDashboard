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
    Volume? volume,
    Calls? calls,
    Phonebook? phonebook,
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
    if (volume != null) result.volume = volume;
    if (calls != null) result.calls = calls;
    if (phonebook != null) result.phonebook = phonebook;
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
    ..aOM<Volume>(13, _omitFieldNames ? '' : 'volume',
        subBuilder: Volume.$_createMessage)
    ..aOM<Calls>(14, _omitFieldNames ? '' : 'calls',
        subBuilder: Calls.$_createMessage)
    ..aOM<Phonebook>(15, _omitFieldNames ? '' : 'phonebook',
        subBuilder: Phonebook.$_createMessage)
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

  /// The master volume (ADR-0043).
  @$pb.TagNumber(13)
  Volume get volume => $_getN(12);
  @$pb.TagNumber(13)
  set volume(Volume value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasVolume() => $_has(12);
  @$pb.TagNumber(13)
  void clearVolume() => $_clearField(13);
  @$pb.TagNumber(13)
  Volume ensureVolume() => $_ensure(12);

  /// Phone calls (ADR-0045). Absent from an audio-manager without calls.
  @$pb.TagNumber(14)
  Calls get calls => $_getN(13);
  @$pb.TagNumber(14)
  set calls(Calls value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasCalls() => $_has(13);
  @$pb.TagNumber(14)
  void clearCalls() => $_clearField(14);
  @$pb.TagNumber(14)
  Calls ensureCalls() => $_ensure(13);

  /// The connected phone's contacts and recent calls (ADR-0045 phase 2).
  /// Absent from an audio-manager without them.
  @$pb.TagNumber(15)
  Phonebook get phonebook => $_getN(14);
  @$pb.TagNumber(15)
  set phonebook(Phonebook value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasPhonebook() => $_has(14);
  @$pb.TagNumber(15)
  void clearPhonebook() => $_clearField(15);
  @$pb.TagNumber(15)
  Phonebook ensurePhonebook() => $_ensure(14);
}

/// One call on the connected phone. Never a call of a phone that isn't
/// connected.
class Call extends $pb.GeneratedMessage {
  factory Call({
    $fixnum.Int64? id,
    CallState? state,
    $core.String? number,
    $core.String? name,
    $core.bool? withheld,
    $core.int? activeS,
    $core.bool? multiparty,
  }) {
    final result = Call._();
    if (id != null) result.id = id;
    if (state != null) result.state = state;
    if (number != null) result.number = number;
    if (name != null) result.name = name;
    if (withheld != null) result.withheld = withheld;
    if (activeS != null) result.activeS = activeS;
    if (multiparty != null) result.multiparty = multiparty;
    return result;
  }

  Call._();

  factory Call.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Call()..mergeFromBuffer(data, registry);
  factory Call.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Call()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Call',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: Call.$_createMessage)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'id', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aE<CallState>(2, _omitFieldNames ? '' : 'state',
        enumValues: CallState.values)
    ..aOS(3, _omitFieldNames ? '' : 'number')
    ..aOS(4, _omitFieldNames ? '' : 'name')
    ..aOB(5, _omitFieldNames ? '' : 'withheld')
    ..aI(6, _omitFieldNames ? '' : 'activeS', fieldType: $pb.PbFieldType.OU3)
    ..aOB(7, _omitFieldNames ? '' : 'multiparty')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Call clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Call copyWith(void Function(Call) updates) =>
      super.copyWith((message) => updates(message as Call)) as Call;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Call() / Call.new instead')
  static Call create() => Call._();
  static $pb.GeneratedMessage $_createMessage() => Call._();
  @$core.override
  Call createEmptyInstance() => Call._();
  @$core.pragma('dart2js:noInline')
  static Call getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Call>(Call.$_createMessage);
  static Call? _defaultInstance;

  /// Names this call in AnswerCall and HangUp; a new call gets a new id.
  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  CallState get state => $_getN(1);
  @$pb.TagNumber(2)
  set state(CallState value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasState() => $_has(1);
  @$pb.TagNumber(2)
  void clearState() => $_clearField(2);

  /// The number as the phone gives it (caller ID); empty: none given.
  @$pb.TagNumber(3)
  $core.String get number => $_getSZ(2);
  @$pb.TagNumber(3)
  set number($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasNumber() => $_has(2);
  @$pb.TagNumber(3)
  void clearNumber() => $_clearField(3);

  /// The name as the phone gives it (its contacts, or the network's); empty:
  /// none given.
  @$pb.TagNumber(4)
  $core.String get name => $_getSZ(3);
  @$pb.TagNumber(4)
  set name($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasName() => $_has(3);
  @$pb.TagNumber(4)
  void clearName() => $_clearField(4);

  /// The caller withheld their number.
  @$pb.TagNumber(5)
  $core.bool get withheld => $_getBF(4);
  @$pb.TagNumber(5)
  set withheld($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasWithheld() => $_has(4);
  @$pb.TagNumber(5)
  void clearWithheld() => $_clearField(5);

  /// Seconds since it became active, as of this message; 0 before.
  @$pb.TagNumber(6)
  $core.int get activeS => $_getIZ(5);
  @$pb.TagNumber(6)
  set activeS($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasActiveS() => $_has(5);
  @$pb.TagNumber(6)
  void clearActiveS() => $_clearField(6);

  /// Part of a conference call.
  @$pb.TagNumber(7)
  $core.bool get multiparty => $_getBF(6);
  @$pb.TagNumber(7)
  set multiparty($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasMultiparty() => $_has(6);
  @$pb.TagNumber(7)
  void clearMultiparty() => $_clearField(7);
}

class Calls extends $pb.GeneratedMessage {
  factory Calls({
    $core.bool? available,
    $core.String? detail,
    Call? call,
    $core.int? otherCalls,
    $core.bool? micMuted,
    $core.String? phoneName,
    $core.bool? localRing,
  }) {
    final result = Calls._();
    if (available != null) result.available = available;
    if (detail != null) result.detail = detail;
    if (call != null) result.call = call;
    if (otherCalls != null) result.otherCalls = otherCalls;
    if (micMuted != null) result.micMuted = micMuted;
    if (phoneName != null) result.phoneName = phoneName;
    if (localRing != null) result.localRing = localRing;
    return result;
  }

  Calls._();

  factory Calls.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Calls()..mergeFromBuffer(data, registry);
  factory Calls.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Calls()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Calls',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: Calls.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'available')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..aOM<Call>(3, _omitFieldNames ? '' : 'call',
        subBuilder: Call.$_createMessage)
    ..aI(4, _omitFieldNames ? '' : 'otherCalls', fieldType: $pb.PbFieldType.OU3)
    ..aOB(5, _omitFieldNames ? '' : 'micMuted')
    ..aOS(6, _omitFieldNames ? '' : 'phoneName')
    ..aOB(7, _omitFieldNames ? '' : 'localRing')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Calls clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Calls copyWith(void Function(Calls) updates) =>
      super.copyWith((message) => updates(message as Calls)) as Calls;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Calls() / Calls.new instead')
  static Calls create() => Calls._();
  static $pb.GeneratedMessage $_createMessage() => Calls._();
  @$core.override
  Calls createEmptyInstance() => Calls._();
  @$core.pragma('dart2js:noInline')
  static Calls getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Calls>(Calls.$_createMessage);
  static Calls? _defaultInstance;

  /// Calls come to the head unit: a microphone is configured and the phone's
  /// hands-free gateway answers. False: `detail` says why (calls stay on the
  /// phone).
  @$pb.TagNumber(1)
  $core.bool get available => $_getBF(0);
  @$pb.TagNumber(1)
  set available($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAvailable() => $_has(0);
  @$pb.TagNumber(1)
  void clearAvailable() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);

  /// The call to show: one ringing (incoming or waiting) first, then the
  /// active one, then one being dialled, then a held one.
  @$pb.TagNumber(3)
  Call get call => $_getN(2);
  @$pb.TagNumber(3)
  set call(Call value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasCall() => $_has(2);
  @$pb.TagNumber(3)
  void clearCall() => $_clearField(3);
  @$pb.TagNumber(3)
  Call ensureCall() => $_ensure(2);

  /// Other calls on the phone (held ones, or the active one behind a waiting
  /// call).
  @$pb.TagNumber(4)
  $core.int get otherCalls => $_getIZ(3);
  @$pb.TagNumber(4)
  set otherCalls($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasOtherCalls() => $_has(3);
  @$pb.TagNumber(4)
  void clearOtherCalls() => $_clearField(4);

  /// The call microphone is muted (only during a call).
  @$pb.TagNumber(5)
  $core.bool get micMuted => $_getBF(4);
  @$pb.TagNumber(5)
  set micMuted($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMicMuted() => $_has(4);
  @$pb.TagNumber(5)
  void clearMicMuted() => $_clearField(5);

  /// The connected phone's name, for "on Pixel 8".
  @$pb.TagNumber(6)
  $core.String get phoneName => $_getSZ(5);
  @$pb.TagNumber(6)
  set phoneName($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPhoneName() => $_has(5);
  @$pb.TagNumber(6)
  void clearPhoneName() => $_clearField(6);

  /// audio-manager rings through the speakers: a call rings and the phone
  /// sends no ring tone of its own (ADR-0045 decision 7).
  @$pb.TagNumber(7)
  $core.bool get localRing => $_getBF(6);
  @$pb.TagNumber(7)
  set localRing($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasLocalRing() => $_has(6);
  @$pb.TagNumber(7)
  void clearLocalRing() => $_clearField(7);
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

/// The master volume (ADR-0043): a gain in the speakers' filter-chain on
/// every output, never above 0 dB. Step `steps` is 0 dB, each step below it
/// quieter (configuration, examples), 0 silent.
class Volume extends $pb.GeneratedMessage {
  factory Volume({
    $core.int? level,
    $core.int? max,
    $core.int? steps,
    $core.bool? muted,
    $core.bool? applied,
    $core.String? detail,
  }) {
    final result = Volume._();
    if (level != null) result.level = level;
    if (max != null) result.max = max;
    if (steps != null) result.steps = steps;
    if (muted != null) result.muted = muted;
    if (applied != null) result.applied = applied;
    if (detail != null) result.detail = detail;
    return result;
  }

  Volume._();

  factory Volume.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Volume()..mergeFromBuffer(data, registry);
  factory Volume.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Volume()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Volume',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: Volume.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'level', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'max', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'steps', fieldType: $pb.PbFieldType.OU3)
    ..aOB(4, _omitFieldNames ? '' : 'muted')
    ..aOB(5, _omitFieldNames ? '' : 'applied')
    ..aOS(6, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Volume clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Volume copyWith(void Function(Volume) updates) =>
      super.copyWith((message) => updates(message as Volume)) as Volume;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Volume() / Volume.new instead')
  static Volume create() => Volume._();
  static $pb.GeneratedMessage $_createMessage() => Volume._();
  @$core.override
  Volume createEmptyInstance() => Volume._();
  @$core.pragma('dart2js:noInline')
  static Volume getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Volume>(Volume.$_createMessage);
  static Volume? _defaultInstance;

  /// 0 ..= max.
  @$pb.TagNumber(1)
  $core.int get level => $_getIZ(0);
  @$pb.TagNumber(1)
  set level($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLevel() => $_has(0);
  @$pb.TagNumber(1)
  void clearLevel() => $_clearField(1);

  /// The cap: the driver can't go above it (configuration).
  @$pb.TagNumber(2)
  $core.int get max => $_getIZ(1);
  @$pb.TagNumber(2)
  set max($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMax() => $_has(1);
  @$pb.TagNumber(2)
  void clearMax() => $_clearField(2);

  /// The top step (0 dB).
  @$pb.TagNumber(3)
  $core.int get steps => $_getIZ(2);
  @$pb.TagNumber(3)
  set steps($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSteps() => $_has(2);
  @$pb.TagNumber(3)
  void clearSteps() => $_clearField(3);

  /// The level is kept while muted.
  @$pb.TagNumber(4)
  $core.bool get muted => $_getBF(3);
  @$pb.TagNumber(4)
  set muted($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMuted() => $_has(3);
  @$pb.TagNumber(4)
  void clearMuted() => $_clearField(4);

  /// False: kept and shown, not reaching the speakers (no filter-chain).
  @$pb.TagNumber(5)
  $core.bool get applied => $_getBF(4);
  @$pb.TagNumber(5)
  set applied($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasApplied() => $_has(4);
  @$pb.TagNumber(5)
  void clearApplied() => $_clearField(5);

  /// Why not applied.
  @$pb.TagNumber(6)
  $core.String get detail => $_getSZ(5);
  @$pb.TagNumber(6)
  set detail($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDetail() => $_has(5);
  @$pb.TagNumber(6)
  void clearDetail() => $_clearField(6);
}

enum SetVolumeRequest_Change { level, steps, mute, notSet }

class SetVolumeRequest extends $pb.GeneratedMessage {
  factory SetVolumeRequest({
    $core.int? level,
    $core.int? steps,
    MuteChange? mute,
    $core.String? source,
  }) {
    final result = SetVolumeRequest._();
    if (level != null) result.level = level;
    if (steps != null) result.steps = steps;
    if (mute != null) result.mute = mute;
    if (source != null) result.source = source;
    return result;
  }

  SetVolumeRequest._();

  factory SetVolumeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetVolumeRequest()..mergeFromBuffer(data, registry);
  factory SetVolumeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetVolumeRequest()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, SetVolumeRequest_Change>
      _SetVolumeRequest_ChangeByTag = {
    1: SetVolumeRequest_Change.level,
    2: SetVolumeRequest_Change.steps,
    3: SetVolumeRequest_Change.mute,
    0: SetVolumeRequest_Change.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetVolumeRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: SetVolumeRequest.$_createMessage)
    ..oo(0, [1, 2, 3])
    ..aI(1, _omitFieldNames ? '' : 'level', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'steps')
    ..aE<MuteChange>(3, _omitFieldNames ? '' : 'mute',
        enumValues: MuteChange.values)
    ..aOS(4, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetVolumeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetVolumeRequest copyWith(void Function(SetVolumeRequest) updates) =>
      super.copyWith((message) => updates(message as SetVolumeRequest))
          as SetVolumeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SetVolumeRequest() / SetVolumeRequest.new instead')
  static SetVolumeRequest create() => SetVolumeRequest._();
  static $pb.GeneratedMessage $_createMessage() => SetVolumeRequest._();
  @$core.override
  SetVolumeRequest createEmptyInstance() => SetVolumeRequest._();
  @$core.pragma('dart2js:noInline')
  static SetVolumeRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetVolumeRequest>(
          SetVolumeRequest.$_createMessage);
  static SetVolumeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  SetVolumeRequest_Change whichChange() =>
      _SetVolumeRequest_ChangeByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  void clearChange() => $_clearField($_whichOneof(0));

  /// Set to this level (unmutes); above the cap: the cap.
  @$pb.TagNumber(1)
  $core.int get level => $_getIZ(0);
  @$pb.TagNumber(1)
  set level($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLevel() => $_has(0);
  @$pb.TagNumber(1)
  void clearLevel() => $_clearField(1);

  /// Up (positive, unmutes) or down this many steps, within 0..=max.
  @$pb.TagNumber(2)
  $core.int get steps => $_getIZ(1);
  @$pb.TagNumber(2)
  set steps($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSteps() => $_has(1);
  @$pb.TagNumber(2)
  void clearSteps() => $_clearField(2);

  @$pb.TagNumber(3)
  MuteChange get mute => $_getN(2);
  @$pb.TagNumber(3)
  set mute(MuteChange value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasMute() => $_has(2);
  @$pb.TagNumber(3)
  void clearMute() => $_clearField(3);

  /// Who asked ("dashboard", "knob"), for the log.
  @$pb.TagNumber(4)
  $core.String get source => $_getSZ(3);
  @$pb.TagNumber(4)
  set source($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSource() => $_has(3);
  @$pb.TagNumber(4)
  void clearSource() => $_clearField(4);
}

class AnswerCallRequest extends $pb.GeneratedMessage {
  factory AnswerCallRequest({
    $fixnum.Int64? id,
    $core.String? source,
  }) {
    final result = AnswerCallRequest._();
    if (id != null) result.id = id;
    if (source != null) result.source = source;
    return result;
  }

  AnswerCallRequest._();

  factory AnswerCallRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AnswerCallRequest()..mergeFromBuffer(data, registry);
  factory AnswerCallRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AnswerCallRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AnswerCallRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: AnswerCallRequest.$_createMessage)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'id', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(2, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AnswerCallRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AnswerCallRequest copyWith(void Function(AnswerCallRequest) updates) =>
      super.copyWith((message) => updates(message as AnswerCallRequest))
          as AnswerCallRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AnswerCallRequest() / AnswerCallRequest.new instead')
  static AnswerCallRequest create() => AnswerCallRequest._();
  static $pb.GeneratedMessage $_createMessage() => AnswerCallRequest._();
  @$core.override
  AnswerCallRequest createEmptyInstance() => AnswerCallRequest._();
  @$core.pragma('dart2js:noInline')
  static AnswerCallRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AnswerCallRequest>(
          AnswerCallRequest.$_createMessage);
  static AnswerCallRequest? _defaultInstance;

  /// Call.id.
  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// Who asked ("dashboard", "knob"), for the log.
  @$pb.TagNumber(2)
  $core.String get source => $_getSZ(1);
  @$pb.TagNumber(2)
  set source($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearSource() => $_clearField(2);
}

class AnswerCallResponse extends $pb.GeneratedMessage {
  factory AnswerCallResponse({
    $core.bool? accepted,
    $core.String? detail,
  }) {
    final result = AnswerCallResponse._();
    if (accepted != null) result.accepted = accepted;
    if (detail != null) result.detail = detail;
    return result;
  }

  AnswerCallResponse._();

  factory AnswerCallResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AnswerCallResponse()..mergeFromBuffer(data, registry);
  factory AnswerCallResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AnswerCallResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AnswerCallResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: AnswerCallResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AnswerCallResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AnswerCallResponse copyWith(void Function(AnswerCallResponse) updates) =>
      super.copyWith((message) => updates(message as AnswerCallResponse))
          as AnswerCallResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AnswerCallResponse() / AnswerCallResponse.new instead')
  static AnswerCallResponse create() => AnswerCallResponse._();
  static $pb.GeneratedMessage $_createMessage() => AnswerCallResponse._();
  @$core.override
  AnswerCallResponse createEmptyInstance() => AnswerCallResponse._();
  @$core.pragma('dart2js:noInline')
  static AnswerCallResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AnswerCallResponse>(
          AnswerCallResponse.$_createMessage);
  static AnswerCallResponse? _defaultInstance;

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

class HangUpRequest extends $pb.GeneratedMessage {
  factory HangUpRequest({
    $fixnum.Int64? id,
    $core.String? source,
  }) {
    final result = HangUpRequest._();
    if (id != null) result.id = id;
    if (source != null) result.source = source;
    return result;
  }

  HangUpRequest._();

  factory HangUpRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HangUpRequest()..mergeFromBuffer(data, registry);
  factory HangUpRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HangUpRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HangUpRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: HangUpRequest.$_createMessage)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'id', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(2, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HangUpRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HangUpRequest copyWith(void Function(HangUpRequest) updates) =>
      super.copyWith((message) => updates(message as HangUpRequest))
          as HangUpRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use HangUpRequest() / HangUpRequest.new instead')
  static HangUpRequest create() => HangUpRequest._();
  static $pb.GeneratedMessage $_createMessage() => HangUpRequest._();
  @$core.override
  HangUpRequest createEmptyInstance() => HangUpRequest._();
  @$core.pragma('dart2js:noInline')
  static HangUpRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<HangUpRequest>(
          HangUpRequest.$_createMessage);
  static HangUpRequest? _defaultInstance;

  /// Call.id.
  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get source => $_getSZ(1);
  @$pb.TagNumber(2)
  set source($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearSource() => $_clearField(2);
}

class HangUpResponse extends $pb.GeneratedMessage {
  factory HangUpResponse({
    $core.bool? accepted,
    $core.String? detail,
  }) {
    final result = HangUpResponse._();
    if (accepted != null) result.accepted = accepted;
    if (detail != null) result.detail = detail;
    return result;
  }

  HangUpResponse._();

  factory HangUpResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HangUpResponse()..mergeFromBuffer(data, registry);
  factory HangUpResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HangUpResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HangUpResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: HangUpResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HangUpResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HangUpResponse copyWith(void Function(HangUpResponse) updates) =>
      super.copyWith((message) => updates(message as HangUpResponse))
          as HangUpResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use HangUpResponse() / HangUpResponse.new instead')
  static HangUpResponse create() => HangUpResponse._();
  static $pb.GeneratedMessage $_createMessage() => HangUpResponse._();
  @$core.override
  HangUpResponse createEmptyInstance() => HangUpResponse._();
  @$core.pragma('dart2js:noInline')
  static HangUpResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<HangUpResponse>(
          HangUpResponse.$_createMessage);
  static HangUpResponse? _defaultInstance;

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

class SetMicMutedRequest extends $pb.GeneratedMessage {
  factory SetMicMutedRequest({
    $core.bool? muted,
    $core.String? source,
  }) {
    final result = SetMicMutedRequest._();
    if (muted != null) result.muted = muted;
    if (source != null) result.source = source;
    return result;
  }

  SetMicMutedRequest._();

  factory SetMicMutedRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetMicMutedRequest()..mergeFromBuffer(data, registry);
  factory SetMicMutedRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetMicMutedRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetMicMutedRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: SetMicMutedRequest.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'muted')
    ..aOS(2, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetMicMutedRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetMicMutedRequest copyWith(void Function(SetMicMutedRequest) updates) =>
      super.copyWith((message) => updates(message as SetMicMutedRequest))
          as SetMicMutedRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SetMicMutedRequest() / SetMicMutedRequest.new instead')
  static SetMicMutedRequest create() => SetMicMutedRequest._();
  static $pb.GeneratedMessage $_createMessage() => SetMicMutedRequest._();
  @$core.override
  SetMicMutedRequest createEmptyInstance() => SetMicMutedRequest._();
  @$core.pragma('dart2js:noInline')
  static SetMicMutedRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetMicMutedRequest>(
          SetMicMutedRequest.$_createMessage);
  static SetMicMutedRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get muted => $_getBF(0);
  @$pb.TagNumber(1)
  set muted($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMuted() => $_has(0);
  @$pb.TagNumber(1)
  void clearMuted() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get source => $_getSZ(1);
  @$pb.TagNumber(2)
  set source($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearSource() => $_clearField(2);
}

class SetMicMutedResponse extends $pb.GeneratedMessage {
  factory SetMicMutedResponse({
    $core.bool? applied,
    $core.String? detail,
  }) {
    final result = SetMicMutedResponse._();
    if (applied != null) result.applied = applied;
    if (detail != null) result.detail = detail;
    return result;
  }

  SetMicMutedResponse._();

  factory SetMicMutedResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetMicMutedResponse()..mergeFromBuffer(data, registry);
  factory SetMicMutedResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetMicMutedResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetMicMutedResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: SetMicMutedResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'applied')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetMicMutedResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetMicMutedResponse copyWith(void Function(SetMicMutedResponse) updates) =>
      super.copyWith((message) => updates(message as SetMicMutedResponse))
          as SetMicMutedResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use SetMicMutedResponse() / SetMicMutedResponse.new instead')
  static SetMicMutedResponse create() => SetMicMutedResponse._();
  static $pb.GeneratedMessage $_createMessage() => SetMicMutedResponse._();
  @$core.override
  SetMicMutedResponse createEmptyInstance() => SetMicMutedResponse._();
  @$core.pragma('dart2js:noInline')
  static SetMicMutedResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetMicMutedResponse>(
          SetMicMutedResponse.$_createMessage);
  static SetMicMutedResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get applied => $_getBF(0);
  @$pb.TagNumber(1)
  set applied($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasApplied() => $_has(0);
  @$pb.TagNumber(1)
  void clearApplied() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);
}

class SetVolumeResponse extends $pb.GeneratedMessage {
  factory SetVolumeResponse({
    $core.bool? applied,
    $core.String? detail,
    Volume? volume,
  }) {
    final result = SetVolumeResponse._();
    if (applied != null) result.applied = applied;
    if (detail != null) result.detail = detail;
    if (volume != null) result.volume = volume;
    return result;
  }

  SetVolumeResponse._();

  factory SetVolumeResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetVolumeResponse()..mergeFromBuffer(data, registry);
  factory SetVolumeResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetVolumeResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetVolumeResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: SetVolumeResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'applied')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..aOM<Volume>(3, _omitFieldNames ? '' : 'volume',
        subBuilder: Volume.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetVolumeResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetVolumeResponse copyWith(void Function(SetVolumeResponse) updates) =>
      super.copyWith((message) => updates(message as SetVolumeResponse))
          as SetVolumeResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SetVolumeResponse() / SetVolumeResponse.new instead')
  static SetVolumeResponse create() => SetVolumeResponse._();
  static $pb.GeneratedMessage $_createMessage() => SetVolumeResponse._();
  @$core.override
  SetVolumeResponse createEmptyInstance() => SetVolumeResponse._();
  @$core.pragma('dart2js:noInline')
  static SetVolumeResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetVolumeResponse>(
          SetVolumeResponse.$_createMessage);
  static SetVolumeResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get applied => $_getBF(0);
  @$pb.TagNumber(1)
  set applied($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasApplied() => $_has(0);
  @$pb.TagNumber(1)
  void clearApplied() => $_clearField(1);

  /// What wasn't as asked ("The maximum is 24 (configuration)."); empty
  /// otherwise. Why it isn't applied is in volume.detail.
  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);

  @$pb.TagNumber(3)
  Volume get volume => $_getN(2);
  @$pb.TagNumber(3)
  set volume(Volume value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasVolume() => $_has(2);
  @$pb.TagNumber(3)
  void clearVolume() => $_clearField(3);
  @$pb.TagNumber(3)
  Volume ensureVolume() => $_ensure(2);
}

class DialRequest extends $pb.GeneratedMessage {
  factory DialRequest({
    $core.String? number,
    $core.String? source,
  }) {
    final result = DialRequest._();
    if (number != null) result.number = number;
    if (source != null) result.source = source;
    return result;
  }

  DialRequest._();

  factory DialRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DialRequest()..mergeFromBuffer(data, registry);
  factory DialRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DialRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DialRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: DialRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'number')
    ..aOS(2, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DialRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DialRequest copyWith(void Function(DialRequest) updates) =>
      super.copyWith((message) => updates(message as DialRequest))
          as DialRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DialRequest() / DialRequest.new instead')
  static DialRequest create() => DialRequest._();
  static $pb.GeneratedMessage $_createMessage() => DialRequest._();
  @$core.override
  DialRequest createEmptyInstance() => DialRequest._();
  @$core.pragma('dart2js:noInline')
  static DialRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DialRequest>(
          DialRequest.$_createMessage);
  static DialRequest? _defaultInstance;

  /// Digits, with an optional leading +, * and #; spaces, dashes, dots and
  /// brackets are ignored.
  @$pb.TagNumber(1)
  $core.String get number => $_getSZ(0);
  @$pb.TagNumber(1)
  set number($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNumber() => $_has(0);
  @$pb.TagNumber(1)
  void clearNumber() => $_clearField(1);

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

class DialResponse extends $pb.GeneratedMessage {
  factory DialResponse({
    $core.bool? accepted,
    $core.String? detail,
  }) {
    final result = DialResponse._();
    if (accepted != null) result.accepted = accepted;
    if (detail != null) result.detail = detail;
    return result;
  }

  DialResponse._();

  factory DialResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DialResponse()..mergeFromBuffer(data, registry);
  factory DialResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DialResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DialResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: DialResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DialResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DialResponse copyWith(void Function(DialResponse) updates) =>
      super.copyWith((message) => updates(message as DialResponse))
          as DialResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DialResponse() / DialResponse.new instead')
  static DialResponse create() => DialResponse._();
  static $pb.GeneratedMessage $_createMessage() => DialResponse._();
  @$core.override
  DialResponse createEmptyInstance() => DialResponse._();
  @$core.pragma('dart2js:noInline')
  static DialResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DialResponse>(
          DialResponse.$_createMessage);
  static DialResponse? _defaultInstance;

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

class Phonebook extends $pb.GeneratedMessage {
  factory Phonebook({
    PhonebookState? state,
    $core.String? detail,
    $fixnum.Int64? version,
    $core.int? contacts,
    $core.int? recentCalls,
  }) {
    final result = Phonebook._();
    if (state != null) result.state = state;
    if (detail != null) result.detail = detail;
    if (version != null) result.version = version;
    if (contacts != null) result.contacts = contacts;
    if (recentCalls != null) result.recentCalls = recentCalls;
    return result;
  }

  Phonebook._();

  factory Phonebook.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Phonebook()..mergeFromBuffer(data, registry);
  factory Phonebook.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Phonebook()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Phonebook',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: Phonebook.$_createMessage)
    ..aE<PhonebookState>(1, _omitFieldNames ? '' : 'state',
        enumValues: PhonebookState.values)
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'version', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(4, _omitFieldNames ? '' : 'contacts', fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'recentCalls',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Phonebook clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Phonebook copyWith(void Function(Phonebook) updates) =>
      super.copyWith((message) => updates(message as Phonebook)) as Phonebook;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Phonebook() / Phonebook.new instead')
  static Phonebook create() => Phonebook._();
  static $pb.GeneratedMessage $_createMessage() => Phonebook._();
  @$core.override
  Phonebook createEmptyInstance() => Phonebook._();
  @$core.pragma('dart2js:noInline')
  static Phonebook getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Phonebook>(Phonebook.$_createMessage);
  static Phonebook? _defaultInstance;

  @$pb.TagNumber(1)
  PhonebookState get state => $_getN(0);
  @$pb.TagNumber(1)
  set state(PhonebookState value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasState() => $_has(0);
  @$pb.TagNumber(1)
  void clearState() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);

  /// Changes whenever the lists do: fetch them again with GetPhonebook.
  @$pb.TagNumber(3)
  $fixnum.Int64 get version => $_getI64(2);
  @$pb.TagNumber(3)
  set version($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasVersion() => $_has(2);
  @$pb.TagNumber(3)
  void clearVersion() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get contacts => $_getIZ(3);
  @$pb.TagNumber(4)
  set contacts($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasContacts() => $_has(3);
  @$pb.TagNumber(4)
  void clearContacts() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get recentCalls => $_getIZ(4);
  @$pb.TagNumber(5)
  set recentCalls($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRecentCalls() => $_has(4);
  @$pb.TagNumber(5)
  void clearRecentCalls() => $_clearField(5);
}

class ContactNumber extends $pb.GeneratedMessage {
  factory ContactNumber({
    $core.String? number,
    $core.String? label,
  }) {
    final result = ContactNumber._();
    if (number != null) result.number = number;
    if (label != null) result.label = label;
    return result;
  }

  ContactNumber._();

  factory ContactNumber.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ContactNumber()..mergeFromBuffer(data, registry);
  factory ContactNumber.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ContactNumber()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ContactNumber',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: ContactNumber.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'number')
    ..aOS(2, _omitFieldNames ? '' : 'label')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ContactNumber clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ContactNumber copyWith(void Function(ContactNumber) updates) =>
      super.copyWith((message) => updates(message as ContactNumber))
          as ContactNumber;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ContactNumber() / ContactNumber.new instead')
  static ContactNumber create() => ContactNumber._();
  static $pb.GeneratedMessage $_createMessage() => ContactNumber._();
  @$core.override
  ContactNumber createEmptyInstance() => ContactNumber._();
  @$core.pragma('dart2js:noInline')
  static ContactNumber getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ContactNumber>(
          ContactNumber.$_createMessage);
  static ContactNumber? _defaultInstance;

  /// As the phone gives it.
  @$pb.TagNumber(1)
  $core.String get number => $_getSZ(0);
  @$pb.TagNumber(1)
  set number($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNumber() => $_has(0);
  @$pb.TagNumber(1)
  void clearNumber() => $_clearField(1);

  /// "Mobile", "Home", "Work", "Other"; empty: not given.
  @$pb.TagNumber(2)
  $core.String get label => $_getSZ(1);
  @$pb.TagNumber(2)
  set label($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLabel() => $_has(1);
  @$pb.TagNumber(2)
  void clearLabel() => $_clearField(2);
}

class Contact extends $pb.GeneratedMessage {
  factory Contact({
    $core.String? name,
    $core.Iterable<ContactNumber>? numbers,
  }) {
    final result = Contact._();
    if (name != null) result.name = name;
    if (numbers != null) result.numbers.addAll(numbers);
    return result;
  }

  Contact._();

  factory Contact.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Contact()..mergeFromBuffer(data, registry);
  factory Contact.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Contact()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Contact',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: Contact.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..pPM<ContactNumber>(2, _omitFieldNames ? '' : 'numbers',
        subBuilder: ContactNumber.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Contact clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Contact copyWith(void Function(Contact) updates) =>
      super.copyWith((message) => updates(message as Contact)) as Contact;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Contact() / Contact.new instead')
  static Contact create() => Contact._();
  static $pb.GeneratedMessage $_createMessage() => Contact._();
  @$core.override
  Contact createEmptyInstance() => Contact._();
  @$core.pragma('dart2js:noInline')
  static Contact getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Contact>(Contact.$_createMessage);
  static Contact? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<ContactNumber> get numbers => $_getList(1);
}

class RecentCall extends $pb.GeneratedMessage {
  factory RecentCall({
    $core.String? name,
    $core.String? number,
    RecentKind? kind,
    $core.String? time,
  }) {
    final result = RecentCall._();
    if (name != null) result.name = name;
    if (number != null) result.number = number;
    if (kind != null) result.kind = kind;
    if (time != null) result.time = time;
    return result;
  }

  RecentCall._();

  factory RecentCall.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RecentCall()..mergeFromBuffer(data, registry);
  factory RecentCall.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RecentCall()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RecentCall',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: RecentCall.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'number')
    ..aE<RecentKind>(3, _omitFieldNames ? '' : 'kind',
        enumValues: RecentKind.values)
    ..aOS(4, _omitFieldNames ? '' : 'time')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RecentCall clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RecentCall copyWith(void Function(RecentCall) updates) =>
      super.copyWith((message) => updates(message as RecentCall)) as RecentCall;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RecentCall() / RecentCall.new instead')
  static RecentCall create() => RecentCall._();
  static $pb.GeneratedMessage $_createMessage() => RecentCall._();
  @$core.override
  RecentCall createEmptyInstance() => RecentCall._();
  @$core.pragma('dart2js:noInline')
  static RecentCall getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RecentCall>(RecentCall.$_createMessage);
  static RecentCall? _defaultInstance;

  /// Empty: the phone has no name for the number.
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  /// Empty: withheld or not given.
  @$pb.TagNumber(2)
  $core.String get number => $_getSZ(1);
  @$pb.TagNumber(2)
  set number($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNumber() => $_has(1);
  @$pb.TagNumber(2)
  void clearNumber() => $_clearField(2);

  @$pb.TagNumber(3)
  RecentKind get kind => $_getN(2);
  @$pb.TagNumber(3)
  set kind(RecentKind value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasKind() => $_has(2);
  @$pb.TagNumber(3)
  void clearKind() => $_clearField(3);

  /// "YYYY-MM-DDTHH:MM:SS" in the phone's own local time, as the phone gives
  /// it; empty: not given.
  @$pb.TagNumber(4)
  $core.String get time => $_getSZ(3);
  @$pb.TagNumber(4)
  set time($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTime() => $_has(3);
  @$pb.TagNumber(4)
  void clearTime() => $_clearField(4);
}

class GetPhonebookRequest extends $pb.GeneratedMessage {
  factory GetPhonebookRequest() => GetPhonebookRequest._();

  GetPhonebookRequest._();

  factory GetPhonebookRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetPhonebookRequest()..mergeFromBuffer(data, registry);
  factory GetPhonebookRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetPhonebookRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetPhonebookRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: GetPhonebookRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPhonebookRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPhonebookRequest copyWith(void Function(GetPhonebookRequest) updates) =>
      super.copyWith((message) => updates(message as GetPhonebookRequest))
          as GetPhonebookRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use GetPhonebookRequest() / GetPhonebookRequest.new instead')
  static GetPhonebookRequest create() => GetPhonebookRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetPhonebookRequest._();
  @$core.override
  GetPhonebookRequest createEmptyInstance() => GetPhonebookRequest._();
  @$core.pragma('dart2js:noInline')
  static GetPhonebookRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetPhonebookRequest>(
          GetPhonebookRequest.$_createMessage);
  static GetPhonebookRequest? _defaultInstance;
}

class GetPhonebookResponse extends $pb.GeneratedMessage {
  factory GetPhonebookResponse({
    $fixnum.Int64? version,
    $core.Iterable<Contact>? contacts,
    $core.Iterable<RecentCall>? recentCalls,
  }) {
    final result = GetPhonebookResponse._();
    if (version != null) result.version = version;
    if (contacts != null) result.contacts.addAll(contacts);
    if (recentCalls != null) result.recentCalls.addAll(recentCalls);
    return result;
  }

  GetPhonebookResponse._();

  factory GetPhonebookResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetPhonebookResponse()..mergeFromBuffer(data, registry);
  factory GetPhonebookResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetPhonebookResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetPhonebookResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: GetPhonebookResponse.$_createMessage)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'version', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..pPM<Contact>(2, _omitFieldNames ? '' : 'contacts',
        subBuilder: Contact.$_createMessage)
    ..pPM<RecentCall>(3, _omitFieldNames ? '' : 'recentCalls',
        subBuilder: RecentCall.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPhonebookResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetPhonebookResponse copyWith(void Function(GetPhonebookResponse) updates) =>
      super.copyWith((message) => updates(message as GetPhonebookResponse))
          as GetPhonebookResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetPhonebookResponse() / GetPhonebookResponse.new instead')
  static GetPhonebookResponse create() => GetPhonebookResponse._();
  static $pb.GeneratedMessage $_createMessage() => GetPhonebookResponse._();
  @$core.override
  GetPhonebookResponse createEmptyInstance() => GetPhonebookResponse._();
  @$core.pragma('dart2js:noInline')
  static GetPhonebookResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetPhonebookResponse>(
          GetPhonebookResponse.$_createMessage);
  static GetPhonebookResponse? _defaultInstance;

  /// Phonebook.version of these lists.
  @$pb.TagNumber(1)
  $fixnum.Int64 get version => $_getI64(0);
  @$pb.TagNumber(1)
  set version($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearVersion() => $_clearField(1);

  /// By name.
  @$pb.TagNumber(2)
  $pb.PbList<Contact> get contacts => $_getList(1);

  /// Newest first.
  @$pb.TagNumber(3)
  $pb.PbList<RecentCall> get recentCalls => $_getList(2);
}

class RefreshPhonebookRequest extends $pb.GeneratedMessage {
  factory RefreshPhonebookRequest({
    $core.String? source,
  }) {
    final result = RefreshPhonebookRequest._();
    if (source != null) result.source = source;
    return result;
  }

  RefreshPhonebookRequest._();

  factory RefreshPhonebookRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RefreshPhonebookRequest()..mergeFromBuffer(data, registry);
  factory RefreshPhonebookRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RefreshPhonebookRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RefreshPhonebookRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: RefreshPhonebookRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RefreshPhonebookRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RefreshPhonebookRequest copyWith(
          void Function(RefreshPhonebookRequest) updates) =>
      super.copyWith((message) => updates(message as RefreshPhonebookRequest))
          as RefreshPhonebookRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RefreshPhonebookRequest() / RefreshPhonebookRequest.new instead')
  static RefreshPhonebookRequest create() => RefreshPhonebookRequest._();
  static $pb.GeneratedMessage $_createMessage() => RefreshPhonebookRequest._();
  @$core.override
  RefreshPhonebookRequest createEmptyInstance() => RefreshPhonebookRequest._();
  @$core.pragma('dart2js:noInline')
  static RefreshPhonebookRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RefreshPhonebookRequest>(
          RefreshPhonebookRequest.$_createMessage);
  static RefreshPhonebookRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get source => $_getSZ(0);
  @$pb.TagNumber(1)
  set source($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSource() => $_has(0);
  @$pb.TagNumber(1)
  void clearSource() => $_clearField(1);
}

class RefreshPhonebookResponse extends $pb.GeneratedMessage {
  factory RefreshPhonebookResponse({
    $core.bool? accepted,
    $core.String? detail,
  }) {
    final result = RefreshPhonebookResponse._();
    if (accepted != null) result.accepted = accepted;
    if (detail != null) result.detail = detail;
    return result;
  }

  RefreshPhonebookResponse._();

  factory RefreshPhonebookResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RefreshPhonebookResponse()..mergeFromBuffer(data, registry);
  factory RefreshPhonebookResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RefreshPhonebookResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RefreshPhonebookResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.audio.v1'),
      createEmptyInstance: RefreshPhonebookResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RefreshPhonebookResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RefreshPhonebookResponse copyWith(
          void Function(RefreshPhonebookResponse) updates) =>
      super.copyWith((message) => updates(message as RefreshPhonebookResponse))
          as RefreshPhonebookResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RefreshPhonebookResponse() / RefreshPhonebookResponse.new instead')
  static RefreshPhonebookResponse create() => RefreshPhonebookResponse._();
  static $pb.GeneratedMessage $_createMessage() => RefreshPhonebookResponse._();
  @$core.override
  RefreshPhonebookResponse createEmptyInstance() =>
      RefreshPhonebookResponse._();
  @$core.pragma('dart2js:noInline')
  static RefreshPhonebookResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RefreshPhonebookResponse>(
          RefreshPhonebookResponse.$_createMessage);
  static RefreshPhonebookResponse? _defaultInstance;

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

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
