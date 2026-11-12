// This is a generated file - do not edit.
//
// Generated from f250/export/v1/export.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'export.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'export.pbenum.dart';

/// One segment file on the data drive (crates/recording's names, ADR-0027
/// decision 10).
class Recording extends $pb.GeneratedMessage {
  factory Recording({
    $core.String? camera,
    $core.String? fileName,
    $core.bool? protected,
    $fixnum.Int64? bytes,
    $core.int? boot,
    $core.int? seq,
    $fixnum.Int64? wallTime,
    $core.bool? beingWritten,
  }) {
    final result = Recording._();
    if (camera != null) result.camera = camera;
    if (fileName != null) result.fileName = fileName;
    if (protected != null) result.protected = protected;
    if (bytes != null) result.bytes = bytes;
    if (boot != null) result.boot = boot;
    if (seq != null) result.seq = seq;
    if (wallTime != null) result.wallTime = wallTime;
    if (beingWritten != null) result.beingWritten = beingWritten;
    return result;
  }

  Recording._();

  factory Recording.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Recording()..mergeFromBuffer(data, registry);
  factory Recording.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Recording()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Recording',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.export.v1'),
      createEmptyInstance: Recording.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'camera')
    ..aOS(2, _omitFieldNames ? '' : 'fileName')
    ..aOB(3, _omitFieldNames ? '' : 'protected')
    ..a<$fixnum.Int64>(4, _omitFieldNames ? '' : 'bytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(5, _omitFieldNames ? '' : 'boot', fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'seq', fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(
        7, _omitFieldNames ? '' : 'wallTime', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(8, _omitFieldNames ? '' : 'beingWritten')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Recording clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Recording copyWith(void Function(Recording) updates) =>
      super.copyWith((message) => updates(message as Recording)) as Recording;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Recording() / Recording.new instead')
  static Recording create() => Recording._();
  static $pb.GeneratedMessage $_createMessage() => Recording._();
  @$core.override
  Recording createEmptyInstance() => Recording._();
  @$core.pragma('dart2js:noInline')
  static Recording getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Recording>(Recording.$_createMessage);
  static Recording? _defaultInstance;

  /// The camera's directory: "front" or "rear".
  @$pb.TagNumber(1)
  $core.String get camera => $_getSZ(0);
  @$pb.TagNumber(1)
  set camera($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCamera() => $_has(0);
  @$pb.TagNumber(1)
  void clearCamera() => $_clearField(1);

  /// b00042-s000317.mkv or b00042-s000317-20261110T143000Z.mkv.
  @$pb.TagNumber(2)
  $core.String get fileName => $_getSZ(1);
  @$pb.TagNumber(2)
  set fileName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFileName() => $_has(1);
  @$pb.TagNumber(2)
  void clearFileName() => $_clearField(2);

  /// A saved clip (in protected/): kept from retention by "Save clip".
  @$pb.TagNumber(3)
  $core.bool get protected => $_getBF(2);
  @$pb.TagNumber(3)
  set protected($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasProtected() => $_has(2);
  @$pb.TagNumber(3)
  void clearProtected() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get bytes => $_getI64(3);
  @$pb.TagNumber(4)
  set bytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearBytes() => $_clearField(4);

  /// The head unit's run and the segment's place in it: they order the
  /// recordings whatever the clock said.
  @$pb.TagNumber(5)
  $core.int get boot => $_getIZ(4);
  @$pb.TagNumber(5)
  set boot($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasBoot() => $_has(4);
  @$pb.TagNumber(5)
  void clearBoot() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get seq => $_getIZ(5);
  @$pb.TagNumber(6)
  set seq($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSeq() => $_has(5);
  @$pb.TagNumber(6)
  void clearSeq() => $_clearField(6);

  /// UTC seconds when the segment started, only when the clock was trusted
  /// while it was recorded; 0: the time isn't known.
  @$pb.TagNumber(7)
  $fixnum.Int64 get wallTime => $_getI64(6);
  @$pb.TagNumber(7)
  set wallTime($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasWallTime() => $_has(6);
  @$pb.TagNumber(7)
  void clearWallTime() => $_clearField(7);

  /// Probably still being written (the newest of its camera, changed in the
  /// last few seconds): it can't be copied yet.
  @$pb.TagNumber(8)
  $core.bool get beingWritten => $_getBF(7);
  @$pb.TagNumber(8)
  set beingWritten($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasBeingWritten() => $_has(7);
  @$pb.TagNumber(8)
  void clearBeingWritten() => $_clearField(8);
}

class ListRecordingsRequest extends $pb.GeneratedMessage {
  factory ListRecordingsRequest() => ListRecordingsRequest._();

  ListRecordingsRequest._();

  factory ListRecordingsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListRecordingsRequest()..mergeFromBuffer(data, registry);
  factory ListRecordingsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListRecordingsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListRecordingsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.export.v1'),
      createEmptyInstance: ListRecordingsRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListRecordingsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListRecordingsRequest copyWith(
          void Function(ListRecordingsRequest) updates) =>
      super.copyWith((message) => updates(message as ListRecordingsRequest))
          as ListRecordingsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ListRecordingsRequest() / ListRecordingsRequest.new instead')
  static ListRecordingsRequest create() => ListRecordingsRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListRecordingsRequest._();
  @$core.override
  ListRecordingsRequest createEmptyInstance() => ListRecordingsRequest._();
  @$core.pragma('dart2js:noInline')
  static ListRecordingsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListRecordingsRequest>(
          ListRecordingsRequest.$_createMessage);
  static ListRecordingsRequest? _defaultInstance;
}

class ListRecordingsResponse extends $pb.GeneratedMessage {
  factory ListRecordingsResponse({
    $core.Iterable<Recording>? recordings,
    $core.bool? driveMounted,
    $core.String? problem,
  }) {
    final result = ListRecordingsResponse._();
    if (recordings != null) result.recordings.addAll(recordings);
    if (driveMounted != null) result.driveMounted = driveMounted;
    if (problem != null) result.problem = problem;
    return result;
  }

  ListRecordingsResponse._();

  factory ListRecordingsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListRecordingsResponse()..mergeFromBuffer(data, registry);
  factory ListRecordingsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListRecordingsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListRecordingsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.export.v1'),
      createEmptyInstance: ListRecordingsResponse.$_createMessage)
    ..pPM<Recording>(1, _omitFieldNames ? '' : 'recordings',
        subBuilder: Recording.$_createMessage)
    ..aOB(2, _omitFieldNames ? '' : 'driveMounted')
    ..aOS(3, _omitFieldNames ? '' : 'problem')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListRecordingsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListRecordingsResponse copyWith(
          void Function(ListRecordingsResponse) updates) =>
      super.copyWith((message) => updates(message as ListRecordingsResponse))
          as ListRecordingsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ListRecordingsResponse() / ListRecordingsResponse.new instead')
  static ListRecordingsResponse create() => ListRecordingsResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListRecordingsResponse._();
  @$core.override
  ListRecordingsResponse createEmptyInstance() => ListRecordingsResponse._();
  @$core.pragma('dart2js:noInline')
  static ListRecordingsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListRecordingsResponse>(
          ListRecordingsResponse.$_createMessage);
  static ListRecordingsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Recording> get recordings => $_getList(0);

  /// The data drive is mounted. Without it there are no recordings.
  @$pb.TagNumber(2)
  $core.bool get driveMounted => $_getBF(1);
  @$pb.TagNumber(2)
  set driveMounted($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDriveMounted() => $_has(1);
  @$pb.TagNumber(2)
  void clearDriveMounted() => $_clearField(2);

  /// Why the list may be incomplete or empty, in words for the screen; empty
  /// when nothing is wrong.
  @$pb.TagNumber(3)
  $core.String get problem => $_getSZ(2);
  @$pb.TagNumber(3)
  set problem($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasProblem() => $_has(2);
  @$pb.TagNumber(3)
  void clearProblem() => $_clearField(3);
}

class Stick extends $pb.GeneratedMessage {
  factory Stick({
    $core.String? device,
    $core.String? label,
    $core.String? model,
    $core.String? filesystem,
    StickRole? role,
    $fixnum.Int64? freeBytes,
    $fixnum.Int64? totalBytes,
    $fixnum.Int64? maxFileBytes,
    $core.bool? readOnly,
    $core.String? detail,
  }) {
    final result = Stick._();
    if (device != null) result.device = device;
    if (label != null) result.label = label;
    if (model != null) result.model = model;
    if (filesystem != null) result.filesystem = filesystem;
    if (role != null) result.role = role;
    if (freeBytes != null) result.freeBytes = freeBytes;
    if (totalBytes != null) result.totalBytes = totalBytes;
    if (maxFileBytes != null) result.maxFileBytes = maxFileBytes;
    if (readOnly != null) result.readOnly = readOnly;
    if (detail != null) result.detail = detail;
    return result;
  }

  Stick._();

  factory Stick.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Stick()..mergeFromBuffer(data, registry);
  factory Stick.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Stick()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Stick',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.export.v1'),
      createEmptyInstance: Stick.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'device')
    ..aOS(2, _omitFieldNames ? '' : 'label')
    ..aOS(3, _omitFieldNames ? '' : 'model')
    ..aOS(4, _omitFieldNames ? '' : 'filesystem')
    ..aE<StickRole>(5, _omitFieldNames ? '' : 'role',
        enumValues: StickRole.values)
    ..a<$fixnum.Int64>(
        6, _omitFieldNames ? '' : 'freeBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        7, _omitFieldNames ? '' : 'totalBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        8, _omitFieldNames ? '' : 'maxFileBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(9, _omitFieldNames ? '' : 'readOnly')
    ..aOS(10, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Stick clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Stick copyWith(void Function(Stick) updates) =>
      super.copyWith((message) => updates(message as Stick)) as Stick;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Stick() / Stick.new instead')
  static Stick create() => Stick._();
  static $pb.GeneratedMessage $_createMessage() => Stick._();
  @$core.override
  Stick createEmptyInstance() => Stick._();
  @$core.pragma('dart2js:noInline')
  static Stick getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Stick>(Stick.$_createMessage);
  static Stick? _defaultInstance;

  /// The kernel's name for the filesystem's device ("sda1", or "sda" for a
  /// stick without a partition table). Names the stick in StartCopy.
  @$pb.TagNumber(1)
  $core.String get device => $_getSZ(0);
  @$pb.TagNumber(1)
  set device($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDevice() => $_has(0);
  @$pb.TagNumber(1)
  void clearDevice() => $_clearField(1);

  /// The filesystem's label, and the stick's vendor and model, for the
  /// screen; any may be empty.
  @$pb.TagNumber(2)
  $core.String get label => $_getSZ(1);
  @$pb.TagNumber(2)
  set label($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLabel() => $_has(1);
  @$pb.TagNumber(2)
  void clearLabel() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get model => $_getSZ(2);
  @$pb.TagNumber(3)
  set model($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasModel() => $_has(2);
  @$pb.TagNumber(3)
  void clearModel() => $_clearField(3);

  /// "exfat", "vfat", ... as udev reports it.
  @$pb.TagNumber(4)
  $core.String get filesystem => $_getSZ(3);
  @$pb.TagNumber(4)
  set filesystem($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFilesystem() => $_has(3);
  @$pb.TagNumber(4)
  void clearFilesystem() => $_clearField(4);

  @$pb.TagNumber(5)
  StickRole get role => $_getN(4);
  @$pb.TagNumber(5)
  set role(StickRole value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasRole() => $_has(4);
  @$pb.TagNumber(5)
  void clearRole() => $_clearField(5);

  /// From the last check (when it was plugged in, and after each copy).
  @$pb.TagNumber(6)
  $fixnum.Int64 get freeBytes => $_getI64(5);
  @$pb.TagNumber(6)
  set freeBytes($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasFreeBytes() => $_has(5);
  @$pb.TagNumber(6)
  void clearFreeBytes() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get totalBytes => $_getI64(6);
  @$pb.TagNumber(7)
  set totalBytes($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTotalBytes() => $_has(6);
  @$pb.TagNumber(7)
  void clearTotalBytes() => $_clearField(7);

  /// The largest file the filesystem holds (4 GiB - 1 on FAT); 0: no limit
  /// that matters.
  @$pb.TagNumber(8)
  $fixnum.Int64 get maxFileBytes => $_getI64(7);
  @$pb.TagNumber(8)
  set maxFileBytes($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasMaxFileBytes() => $_has(7);
  @$pb.TagNumber(8)
  void clearMaxFileBytes() => $_clearField(8);

  /// The device's write-protect switch is on (read-only), as the kernel
  /// reports it.
  @$pb.TagNumber(9)
  $core.bool get readOnly => $_getBF(8);
  @$pb.TagNumber(9)
  set readOnly($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasReadOnly() => $_has(8);
  @$pb.TagNumber(9)
  void clearReadOnly() => $_clearField(9);

  /// Why it is unusable or what it is, in words for the screen.
  @$pb.TagNumber(10)
  $core.String get detail => $_getSZ(9);
  @$pb.TagNumber(10)
  set detail($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasDetail() => $_has(9);
  @$pb.TagNumber(10)
  void clearDetail() => $_clearField(10);
}

class Copy extends $pb.GeneratedMessage {
  factory Copy({
    CopyState? state,
    $core.String? device,
    $core.int? filesTotal,
    $core.int? filesDone,
    $core.int? filesSkipped,
    $core.int? filesMissing,
    $fixnum.Int64? bytesTotal,
    $fixnum.Int64? bytesDone,
    $core.String? current,
    $core.String? detail,
    $core.bool? safeToUnplug,
    $core.String? folder,
    $fixnum.Int64? id,
  }) {
    final result = Copy._();
    if (state != null) result.state = state;
    if (device != null) result.device = device;
    if (filesTotal != null) result.filesTotal = filesTotal;
    if (filesDone != null) result.filesDone = filesDone;
    if (filesSkipped != null) result.filesSkipped = filesSkipped;
    if (filesMissing != null) result.filesMissing = filesMissing;
    if (bytesTotal != null) result.bytesTotal = bytesTotal;
    if (bytesDone != null) result.bytesDone = bytesDone;
    if (current != null) result.current = current;
    if (detail != null) result.detail = detail;
    if (safeToUnplug != null) result.safeToUnplug = safeToUnplug;
    if (folder != null) result.folder = folder;
    if (id != null) result.id = id;
    return result;
  }

  Copy._();

  factory Copy.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Copy()..mergeFromBuffer(data, registry);
  factory Copy.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Copy()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Copy',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.export.v1'),
      createEmptyInstance: Copy.$_createMessage)
    ..aE<CopyState>(1, _omitFieldNames ? '' : 'state',
        enumValues: CopyState.values)
    ..aOS(2, _omitFieldNames ? '' : 'device')
    ..aI(3, _omitFieldNames ? '' : 'filesTotal', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'filesDone', fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'filesSkipped',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'filesMissing',
        fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(
        7, _omitFieldNames ? '' : 'bytesTotal', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        8, _omitFieldNames ? '' : 'bytesDone', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(9, _omitFieldNames ? '' : 'current')
    ..aOS(10, _omitFieldNames ? '' : 'detail')
    ..aOB(11, _omitFieldNames ? '' : 'safeToUnplug')
    ..aOS(12, _omitFieldNames ? '' : 'folder')
    ..a<$fixnum.Int64>(13, _omitFieldNames ? '' : 'id', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Copy clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Copy copyWith(void Function(Copy) updates) =>
      super.copyWith((message) => updates(message as Copy)) as Copy;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Copy() / Copy.new instead')
  static Copy create() => Copy._();
  static $pb.GeneratedMessage $_createMessage() => Copy._();
  @$core.override
  Copy createEmptyInstance() => Copy._();
  @$core.pragma('dart2js:noInline')
  static Copy getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Copy>(Copy.$_createMessage);
  static Copy? _defaultInstance;

  @$pb.TagNumber(1)
  CopyState get state => $_getN(0);
  @$pb.TagNumber(1)
  set state(CopyState value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasState() => $_has(0);
  @$pb.TagNumber(1)
  void clearState() => $_clearField(1);

  /// The stick (Stick.device).
  @$pb.TagNumber(2)
  $core.String get device => $_getSZ(1);
  @$pb.TagNumber(2)
  set device($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDevice() => $_has(1);
  @$pb.TagNumber(2)
  void clearDevice() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get filesTotal => $_getIZ(2);
  @$pb.TagNumber(3)
  set filesTotal($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFilesTotal() => $_has(2);
  @$pb.TagNumber(3)
  void clearFilesTotal() => $_clearField(3);

  /// Finished, counting the ones skipped below.
  @$pb.TagNumber(4)
  $core.int get filesDone => $_getIZ(3);
  @$pb.TagNumber(4)
  set filesDone($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFilesDone() => $_has(3);
  @$pb.TagNumber(4)
  void clearFilesDone() => $_clearField(4);

  /// Already on the stick with the same size: not copied again.
  @$pb.TagNumber(5)
  $core.int get filesSkipped => $_getIZ(4);
  @$pb.TagNumber(5)
  set filesSkipped($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasFilesSkipped() => $_has(4);
  @$pb.TagNumber(5)
  void clearFilesSkipped() => $_clearField(5);

  /// Gone from the data drive before they were copied (retention).
  @$pb.TagNumber(6)
  $core.int get filesMissing => $_getIZ(5);
  @$pb.TagNumber(6)
  set filesMissing($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasFilesMissing() => $_has(5);
  @$pb.TagNumber(6)
  void clearFilesMissing() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get bytesTotal => $_getI64(6);
  @$pb.TagNumber(7)
  set bytesTotal($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasBytesTotal() => $_has(6);
  @$pb.TagNumber(7)
  void clearBytesTotal() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get bytesDone => $_getI64(7);
  @$pb.TagNumber(8)
  set bytesDone($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasBytesDone() => $_has(7);
  @$pb.TagNumber(8)
  void clearBytesDone() => $_clearField(8);

  /// The file being copied, as camera/file_name.
  @$pb.TagNumber(9)
  $core.String get current => $_getSZ(8);
  @$pb.TagNumber(9)
  set current($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasCurrent() => $_has(8);
  @$pb.TagNumber(9)
  void clearCurrent() => $_clearField(9);

  /// What happened, in words for the screen.
  @$pb.TagNumber(10)
  $core.String get detail => $_getSZ(9);
  @$pb.TagNumber(10)
  set detail($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasDetail() => $_has(9);
  @$pb.TagNumber(10)
  void clearDetail() => $_clearField(10);

  /// The stick is synced and unmounted (or was never mounted): it can be
  /// pulled out. False while copying or finishing, and after a failure that
  /// couldn't unmount it.
  @$pb.TagNumber(11)
  $core.bool get safeToUnplug => $_getBF(10);
  @$pb.TagNumber(11)
  set safeToUnplug($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(11)
  $core.bool hasSafeToUnplug() => $_has(10);
  @$pb.TagNumber(11)
  void clearSafeToUnplug() => $_clearField(11);

  /// The folder on the stick the recordings go to.
  @$pb.TagNumber(12)
  $core.String get folder => $_getSZ(11);
  @$pb.TagNumber(12)
  set folder($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasFolder() => $_has(11);
  @$pb.TagNumber(12)
  void clearFolder() => $_clearField(12);

  /// Counts up with each copy started, so a client can tell copies apart.
  @$pb.TagNumber(13)
  $fixnum.Int64 get id => $_getI64(12);
  @$pb.TagNumber(13)
  set id($fixnum.Int64 value) => $_setInt64(12, value);
  @$pb.TagNumber(13)
  $core.bool hasId() => $_has(12);
  @$pb.TagNumber(13)
  void clearId() => $_clearField(13);
}

class WatchExportRequest extends $pb.GeneratedMessage {
  factory WatchExportRequest() => WatchExportRequest._();

  WatchExportRequest._();

  factory WatchExportRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchExportRequest()..mergeFromBuffer(data, registry);
  factory WatchExportRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchExportRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchExportRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.export.v1'),
      createEmptyInstance: WatchExportRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchExportRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchExportRequest copyWith(void Function(WatchExportRequest) updates) =>
      super.copyWith((message) => updates(message as WatchExportRequest))
          as WatchExportRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WatchExportRequest() / WatchExportRequest.new instead')
  static WatchExportRequest create() => WatchExportRequest._();
  static $pb.GeneratedMessage $_createMessage() => WatchExportRequest._();
  @$core.override
  WatchExportRequest createEmptyInstance() => WatchExportRequest._();
  @$core.pragma('dart2js:noInline')
  static WatchExportRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WatchExportRequest>(
          WatchExportRequest.$_createMessage);
  static WatchExportRequest? _defaultInstance;
}

class WatchExportResponse extends $pb.GeneratedMessage {
  factory WatchExportResponse({
    $core.Iterable<Stick>? sticks,
    Copy? copy,
  }) {
    final result = WatchExportResponse._();
    if (sticks != null) result.sticks.addAll(sticks);
    if (copy != null) result.copy = copy;
    return result;
  }

  WatchExportResponse._();

  factory WatchExportResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchExportResponse()..mergeFromBuffer(data, registry);
  factory WatchExportResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchExportResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchExportResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.export.v1'),
      createEmptyInstance: WatchExportResponse.$_createMessage)
    ..pPM<Stick>(1, _omitFieldNames ? '' : 'sticks',
        subBuilder: Stick.$_createMessage)
    ..aOM<Copy>(2, _omitFieldNames ? '' : 'copy',
        subBuilder: Copy.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchExportResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchExportResponse copyWith(void Function(WatchExportResponse) updates) =>
      super.copyWith((message) => updates(message as WatchExportResponse))
          as WatchExportResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use WatchExportResponse() / WatchExportResponse.new instead')
  static WatchExportResponse create() => WatchExportResponse._();
  static $pb.GeneratedMessage $_createMessage() => WatchExportResponse._();
  @$core.override
  WatchExportResponse createEmptyInstance() => WatchExportResponse._();
  @$core.pragma('dart2js:noInline')
  static WatchExportResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WatchExportResponse>(
          WatchExportResponse.$_createMessage);
  static WatchExportResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Stick> get sticks => $_getList(0);

  @$pb.TagNumber(2)
  Copy get copy => $_getN(1);
  @$pb.TagNumber(2)
  set copy(Copy value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasCopy() => $_has(1);
  @$pb.TagNumber(2)
  void clearCopy() => $_clearField(2);
  @$pb.TagNumber(2)
  Copy ensureCopy() => $_ensure(1);
}

/// A recording to copy, as ListRecordings named it. The service finds it on
/// the drive itself; nothing here is used as a path.
class RecordingRef extends $pb.GeneratedMessage {
  factory RecordingRef({
    $core.String? camera,
    $core.String? fileName,
    $core.bool? protected,
  }) {
    final result = RecordingRef._();
    if (camera != null) result.camera = camera;
    if (fileName != null) result.fileName = fileName;
    if (protected != null) result.protected = protected;
    return result;
  }

  RecordingRef._();

  factory RecordingRef.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RecordingRef()..mergeFromBuffer(data, registry);
  factory RecordingRef.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RecordingRef()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RecordingRef',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.export.v1'),
      createEmptyInstance: RecordingRef.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'camera')
    ..aOS(2, _omitFieldNames ? '' : 'fileName')
    ..aOB(3, _omitFieldNames ? '' : 'protected')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RecordingRef clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RecordingRef copyWith(void Function(RecordingRef) updates) =>
      super.copyWith((message) => updates(message as RecordingRef))
          as RecordingRef;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RecordingRef() / RecordingRef.new instead')
  static RecordingRef create() => RecordingRef._();
  static $pb.GeneratedMessage $_createMessage() => RecordingRef._();
  @$core.override
  RecordingRef createEmptyInstance() => RecordingRef._();
  @$core.pragma('dart2js:noInline')
  static RecordingRef getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RecordingRef>(
          RecordingRef.$_createMessage);
  static RecordingRef? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get camera => $_getSZ(0);
  @$pb.TagNumber(1)
  set camera($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCamera() => $_has(0);
  @$pb.TagNumber(1)
  void clearCamera() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get fileName => $_getSZ(1);
  @$pb.TagNumber(2)
  set fileName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFileName() => $_has(1);
  @$pb.TagNumber(2)
  void clearFileName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get protected => $_getBF(2);
  @$pb.TagNumber(3)
  set protected($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasProtected() => $_has(2);
  @$pb.TagNumber(3)
  void clearProtected() => $_clearField(3);
}

class StartCopyRequest extends $pb.GeneratedMessage {
  factory StartCopyRequest({
    $core.String? device,
    $core.Iterable<RecordingRef>? recordings,
    $core.String? source,
  }) {
    final result = StartCopyRequest._();
    if (device != null) result.device = device;
    if (recordings != null) result.recordings.addAll(recordings);
    if (source != null) result.source = source;
    return result;
  }

  StartCopyRequest._();

  factory StartCopyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartCopyRequest()..mergeFromBuffer(data, registry);
  factory StartCopyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartCopyRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartCopyRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.export.v1'),
      createEmptyInstance: StartCopyRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'device')
    ..pPM<RecordingRef>(2, _omitFieldNames ? '' : 'recordings',
        subBuilder: RecordingRef.$_createMessage)
    ..aOS(3, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartCopyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartCopyRequest copyWith(void Function(StartCopyRequest) updates) =>
      super.copyWith((message) => updates(message as StartCopyRequest))
          as StartCopyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use StartCopyRequest() / StartCopyRequest.new instead')
  static StartCopyRequest create() => StartCopyRequest._();
  static $pb.GeneratedMessage $_createMessage() => StartCopyRequest._();
  @$core.override
  StartCopyRequest createEmptyInstance() => StartCopyRequest._();
  @$core.pragma('dart2js:noInline')
  static StartCopyRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StartCopyRequest>(
          StartCopyRequest.$_createMessage);
  static StartCopyRequest? _defaultInstance;

  /// Stick.device.
  @$pb.TagNumber(1)
  $core.String get device => $_getSZ(0);
  @$pb.TagNumber(1)
  set device($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDevice() => $_has(0);
  @$pb.TagNumber(1)
  void clearDevice() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<RecordingRef> get recordings => $_getList(1);

  /// Who asked ("dashboard"), for the log.
  @$pb.TagNumber(3)
  $core.String get source => $_getSZ(2);
  @$pb.TagNumber(3)
  set source($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSource() => $_has(2);
  @$pb.TagNumber(3)
  void clearSource() => $_clearField(3);
}

class StartCopyResponse extends $pb.GeneratedMessage {
  factory StartCopyResponse({
    $core.bool? started,
    $core.String? detail,
    $fixnum.Int64? id,
  }) {
    final result = StartCopyResponse._();
    if (started != null) result.started = started;
    if (detail != null) result.detail = detail;
    if (id != null) result.id = id;
    return result;
  }

  StartCopyResponse._();

  factory StartCopyResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartCopyResponse()..mergeFromBuffer(data, registry);
  factory StartCopyResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartCopyResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartCopyResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.export.v1'),
      createEmptyInstance: StartCopyResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'started')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'id', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartCopyResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartCopyResponse copyWith(void Function(StartCopyResponse) updates) =>
      super.copyWith((message) => updates(message as StartCopyResponse))
          as StartCopyResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use StartCopyResponse() / StartCopyResponse.new instead')
  static StartCopyResponse create() => StartCopyResponse._();
  static $pb.GeneratedMessage $_createMessage() => StartCopyResponse._();
  @$core.override
  StartCopyResponse createEmptyInstance() => StartCopyResponse._();
  @$core.pragma('dart2js:noInline')
  static StartCopyResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StartCopyResponse>(
          StartCopyResponse.$_createMessage);
  static StartCopyResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get started => $_getBF(0);
  @$pb.TagNumber(1)
  set started($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStarted() => $_has(0);
  @$pb.TagNumber(1)
  void clearStarted() => $_clearField(1);

  /// Why not, in words for the screen.
  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get id => $_getI64(2);
  @$pb.TagNumber(3)
  set id($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasId() => $_has(2);
  @$pb.TagNumber(3)
  void clearId() => $_clearField(3);
}

class CancelCopyRequest extends $pb.GeneratedMessage {
  factory CancelCopyRequest({
    $core.String? source,
  }) {
    final result = CancelCopyRequest._();
    if (source != null) result.source = source;
    return result;
  }

  CancelCopyRequest._();

  factory CancelCopyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CancelCopyRequest()..mergeFromBuffer(data, registry);
  factory CancelCopyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CancelCopyRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CancelCopyRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.export.v1'),
      createEmptyInstance: CancelCopyRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CancelCopyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CancelCopyRequest copyWith(void Function(CancelCopyRequest) updates) =>
      super.copyWith((message) => updates(message as CancelCopyRequest))
          as CancelCopyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CancelCopyRequest() / CancelCopyRequest.new instead')
  static CancelCopyRequest create() => CancelCopyRequest._();
  static $pb.GeneratedMessage $_createMessage() => CancelCopyRequest._();
  @$core.override
  CancelCopyRequest createEmptyInstance() => CancelCopyRequest._();
  @$core.pragma('dart2js:noInline')
  static CancelCopyRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CancelCopyRequest>(
          CancelCopyRequest.$_createMessage);
  static CancelCopyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get source => $_getSZ(0);
  @$pb.TagNumber(1)
  set source($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSource() => $_has(0);
  @$pb.TagNumber(1)
  void clearSource() => $_clearField(1);
}

class CancelCopyResponse extends $pb.GeneratedMessage {
  factory CancelCopyResponse({
    $core.bool? cancelling,
  }) {
    final result = CancelCopyResponse._();
    if (cancelling != null) result.cancelling = cancelling;
    return result;
  }

  CancelCopyResponse._();

  factory CancelCopyResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CancelCopyResponse()..mergeFromBuffer(data, registry);
  factory CancelCopyResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CancelCopyResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CancelCopyResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.export.v1'),
      createEmptyInstance: CancelCopyResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'cancelling')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CancelCopyResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CancelCopyResponse copyWith(void Function(CancelCopyResponse) updates) =>
      super.copyWith((message) => updates(message as CancelCopyResponse))
          as CancelCopyResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CancelCopyResponse() / CancelCopyResponse.new instead')
  static CancelCopyResponse create() => CancelCopyResponse._();
  static $pb.GeneratedMessage $_createMessage() => CancelCopyResponse._();
  @$core.override
  CancelCopyResponse createEmptyInstance() => CancelCopyResponse._();
  @$core.pragma('dart2js:noInline')
  static CancelCopyResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CancelCopyResponse>(
          CancelCopyResponse.$_createMessage);
  static CancelCopyResponse? _defaultInstance;

  /// False: no copy was running.
  @$pb.TagNumber(1)
  $core.bool get cancelling => $_getBF(0);
  @$pb.TagNumber(1)
  set cancelling($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCancelling() => $_has(0);
  @$pb.TagNumber(1)
  void clearCancelling() => $_clearField(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
