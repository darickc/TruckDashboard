// This is a generated file - do not edit.
//
// Generated from f250/power/v1/display.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'display.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'display.pbenum.dart';

class Display extends $pb.GeneratedMessage {
  factory Display({
    DisplayMode? mode,
    DisplayChoice? choice,
    ModeBasis? basis,
    SunStatus? sun,
    $core.double? sunElevationDeg,
    $core.int? dayBrightnessPct,
    $core.int? nightBrightnessPct,
    $core.int? minBrightnessPct,
    $core.bool? backlightPresent,
    $core.String? backlight,
    $core.int? brightnessPct,
    $core.String? backlightProblem,
  }) {
    final result = Display._();
    if (mode != null) result.mode = mode;
    if (choice != null) result.choice = choice;
    if (basis != null) result.basis = basis;
    if (sun != null) result.sun = sun;
    if (sunElevationDeg != null) result.sunElevationDeg = sunElevationDeg;
    if (dayBrightnessPct != null) result.dayBrightnessPct = dayBrightnessPct;
    if (nightBrightnessPct != null)
      result.nightBrightnessPct = nightBrightnessPct;
    if (minBrightnessPct != null) result.minBrightnessPct = minBrightnessPct;
    if (backlightPresent != null) result.backlightPresent = backlightPresent;
    if (backlight != null) result.backlight = backlight;
    if (brightnessPct != null) result.brightnessPct = brightnessPct;
    if (backlightProblem != null) result.backlightProblem = backlightProblem;
    return result;
  }

  Display._();

  factory Display.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Display()..mergeFromBuffer(data, registry);
  factory Display.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Display()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Display',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.power.v1'),
      createEmptyInstance: Display.$_createMessage)
    ..aE<DisplayMode>(1, _omitFieldNames ? '' : 'mode',
        enumValues: DisplayMode.values)
    ..aE<DisplayChoice>(2, _omitFieldNames ? '' : 'choice',
        enumValues: DisplayChoice.values)
    ..aE<ModeBasis>(3, _omitFieldNames ? '' : 'basis',
        enumValues: ModeBasis.values)
    ..aE<SunStatus>(4, _omitFieldNames ? '' : 'sun',
        enumValues: SunStatus.values)
    ..aD(5, _omitFieldNames ? '' : 'sunElevationDeg')
    ..aI(6, _omitFieldNames ? '' : 'dayBrightnessPct',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'nightBrightnessPct',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(8, _omitFieldNames ? '' : 'minBrightnessPct',
        fieldType: $pb.PbFieldType.OU3)
    ..aOB(9, _omitFieldNames ? '' : 'backlightPresent')
    ..aOS(10, _omitFieldNames ? '' : 'backlight')
    ..aI(11, _omitFieldNames ? '' : 'brightnessPct',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(12, _omitFieldNames ? '' : 'backlightProblem')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Display clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Display copyWith(void Function(Display) updates) =>
      super.copyWith((message) => updates(message as Display)) as Display;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Display() / Display.new instead')
  static Display create() => Display._();
  static $pb.GeneratedMessage $_createMessage() => Display._();
  @$core.override
  Display createEmptyInstance() => Display._();
  @$core.pragma('dart2js:noInline')
  static Display getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Display>(Display.$_createMessage);
  static Display? _defaultInstance;

  @$pb.TagNumber(1)
  DisplayMode get mode => $_getN(0);
  @$pb.TagNumber(1)
  set mode(DisplayMode value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMode() => $_has(0);
  @$pb.TagNumber(1)
  void clearMode() => $_clearField(1);

  @$pb.TagNumber(2)
  DisplayChoice get choice => $_getN(1);
  @$pb.TagNumber(2)
  set choice(DisplayChoice value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasChoice() => $_has(1);
  @$pb.TagNumber(2)
  void clearChoice() => $_clearField(2);

  @$pb.TagNumber(3)
  ModeBasis get basis => $_getN(2);
  @$pb.TagNumber(3)
  set basis(ModeBasis value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasBasis() => $_has(2);
  @$pb.TagNumber(3)
  void clearBasis() => $_clearField(3);

  @$pb.TagNumber(4)
  SunStatus get sun => $_getN(3);
  @$pb.TagNumber(4)
  set sun(SunStatus value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasSun() => $_has(3);
  @$pb.TagNumber(4)
  void clearSun() => $_clearField(4);

  /// Degrees above the horizon; meaningful only while sun is KNOWN.
  @$pb.TagNumber(5)
  $core.double get sunElevationDeg => $_getN(4);
  @$pb.TagNumber(5)
  set sunElevationDeg($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSunElevationDeg() => $_has(4);
  @$pb.TagNumber(5)
  void clearSunElevationDeg() => $_clearField(5);

  /// The driver's levels, in percent, and the floor neither goes below.
  @$pb.TagNumber(6)
  $core.int get dayBrightnessPct => $_getIZ(5);
  @$pb.TagNumber(6)
  set dayBrightnessPct($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDayBrightnessPct() => $_has(5);
  @$pb.TagNumber(6)
  void clearDayBrightnessPct() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get nightBrightnessPct => $_getIZ(6);
  @$pb.TagNumber(7)
  set nightBrightnessPct($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasNightBrightnessPct() => $_has(6);
  @$pb.TagNumber(7)
  void clearNightBrightnessPct() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get minBrightnessPct => $_getIZ(7);
  @$pb.TagNumber(8)
  set minBrightnessPct($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasMinBrightnessPct() => $_has(7);
  @$pb.TagNumber(8)
  void clearMinBrightnessPct() => $_clearField(8);

  /// A backlight device was found (its name in `backlight`).
  @$pb.TagNumber(9)
  $core.bool get backlightPresent => $_getBF(8);
  @$pb.TagNumber(9)
  set backlightPresent($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasBacklightPresent() => $_has(8);
  @$pb.TagNumber(9)
  void clearBacklightPresent() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get backlight => $_getSZ(9);
  @$pb.TagNumber(10)
  set backlight($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasBacklight() => $_has(9);
  @$pb.TagNumber(10)
  void clearBacklight() => $_clearField(10);

  /// The level the backlight is being set to for the current mode, percent.
  @$pb.TagNumber(11)
  $core.int get brightnessPct => $_getIZ(10);
  @$pb.TagNumber(11)
  set brightnessPct($core.int value) => $_setUnsignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasBrightnessPct() => $_has(10);
  @$pb.TagNumber(11)
  void clearBrightnessPct() => $_clearField(11);

  /// Why the backlight isn't following (none found, a write failed). Empty
  /// when it is.
  @$pb.TagNumber(12)
  $core.String get backlightProblem => $_getSZ(11);
  @$pb.TagNumber(12)
  set backlightProblem($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasBacklightProblem() => $_has(11);
  @$pb.TagNumber(12)
  void clearBacklightProblem() => $_clearField(12);
}

class WatchDisplayRequest extends $pb.GeneratedMessage {
  factory WatchDisplayRequest() => WatchDisplayRequest._();

  WatchDisplayRequest._();

  factory WatchDisplayRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchDisplayRequest()..mergeFromBuffer(data, registry);
  factory WatchDisplayRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchDisplayRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchDisplayRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.power.v1'),
      createEmptyInstance: WatchDisplayRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchDisplayRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchDisplayRequest copyWith(void Function(WatchDisplayRequest) updates) =>
      super.copyWith((message) => updates(message as WatchDisplayRequest))
          as WatchDisplayRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use WatchDisplayRequest() / WatchDisplayRequest.new instead')
  static WatchDisplayRequest create() => WatchDisplayRequest._();
  static $pb.GeneratedMessage $_createMessage() => WatchDisplayRequest._();
  @$core.override
  WatchDisplayRequest createEmptyInstance() => WatchDisplayRequest._();
  @$core.pragma('dart2js:noInline')
  static WatchDisplayRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WatchDisplayRequest>(
          WatchDisplayRequest.$_createMessage);
  static WatchDisplayRequest? _defaultInstance;
}

class WatchDisplayResponse extends $pb.GeneratedMessage {
  factory WatchDisplayResponse({
    Display? display,
  }) {
    final result = WatchDisplayResponse._();
    if (display != null) result.display = display;
    return result;
  }

  WatchDisplayResponse._();

  factory WatchDisplayResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchDisplayResponse()..mergeFromBuffer(data, registry);
  factory WatchDisplayResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WatchDisplayResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchDisplayResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.power.v1'),
      createEmptyInstance: WatchDisplayResponse.$_createMessage)
    ..aOM<Display>(1, _omitFieldNames ? '' : 'display',
        subBuilder: Display.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchDisplayResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchDisplayResponse copyWith(void Function(WatchDisplayResponse) updates) =>
      super.copyWith((message) => updates(message as WatchDisplayResponse))
          as WatchDisplayResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use WatchDisplayResponse() / WatchDisplayResponse.new instead')
  static WatchDisplayResponse create() => WatchDisplayResponse._();
  static $pb.GeneratedMessage $_createMessage() => WatchDisplayResponse._();
  @$core.override
  WatchDisplayResponse createEmptyInstance() => WatchDisplayResponse._();
  @$core.pragma('dart2js:noInline')
  static WatchDisplayResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WatchDisplayResponse>(
          WatchDisplayResponse.$_createMessage);
  static WatchDisplayResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Display get display => $_getN(0);
  @$pb.TagNumber(1)
  set display(Display value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasDisplay() => $_has(0);
  @$pb.TagNumber(1)
  void clearDisplay() => $_clearField(1);
  @$pb.TagNumber(1)
  Display ensureDisplay() => $_ensure(0);
}

class SetDisplayRequest extends $pb.GeneratedMessage {
  factory SetDisplayRequest({
    DisplayChoice? choice,
    $core.int? dayBrightnessPct,
    $core.int? nightBrightnessPct,
    $core.String? source,
  }) {
    final result = SetDisplayRequest._();
    if (choice != null) result.choice = choice;
    if (dayBrightnessPct != null) result.dayBrightnessPct = dayBrightnessPct;
    if (nightBrightnessPct != null)
      result.nightBrightnessPct = nightBrightnessPct;
    if (source != null) result.source = source;
    return result;
  }

  SetDisplayRequest._();

  factory SetDisplayRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetDisplayRequest()..mergeFromBuffer(data, registry);
  factory SetDisplayRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetDisplayRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetDisplayRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.power.v1'),
      createEmptyInstance: SetDisplayRequest.$_createMessage)
    ..aE<DisplayChoice>(1, _omitFieldNames ? '' : 'choice',
        enumValues: DisplayChoice.values)
    ..aI(2, _omitFieldNames ? '' : 'dayBrightnessPct',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'nightBrightnessPct',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(4, _omitFieldNames ? '' : 'source')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetDisplayRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetDisplayRequest copyWith(void Function(SetDisplayRequest) updates) =>
      super.copyWith((message) => updates(message as SetDisplayRequest))
          as SetDisplayRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SetDisplayRequest() / SetDisplayRequest.new instead')
  static SetDisplayRequest create() => SetDisplayRequest._();
  static $pb.GeneratedMessage $_createMessage() => SetDisplayRequest._();
  @$core.override
  SetDisplayRequest createEmptyInstance() => SetDisplayRequest._();
  @$core.pragma('dart2js:noInline')
  static SetDisplayRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetDisplayRequest>(
          SetDisplayRequest.$_createMessage);
  static SetDisplayRequest? _defaultInstance;

  /// UNSPECIFIED: unchanged.
  @$pb.TagNumber(1)
  DisplayChoice get choice => $_getN(0);
  @$pb.TagNumber(1)
  set choice(DisplayChoice value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasChoice() => $_has(0);
  @$pb.TagNumber(1)
  void clearChoice() => $_clearField(1);

  /// 0: unchanged. Clamped to [min_brightness_pct, 100].
  @$pb.TagNumber(2)
  $core.int get dayBrightnessPct => $_getIZ(1);
  @$pb.TagNumber(2)
  set dayBrightnessPct($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDayBrightnessPct() => $_has(1);
  @$pb.TagNumber(2)
  void clearDayBrightnessPct() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get nightBrightnessPct => $_getIZ(2);
  @$pb.TagNumber(3)
  set nightBrightnessPct($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasNightBrightnessPct() => $_has(2);
  @$pb.TagNumber(3)
  void clearNightBrightnessPct() => $_clearField(3);

  /// Who sent it ("dashboard"), for the log.
  @$pb.TagNumber(4)
  $core.String get source => $_getSZ(3);
  @$pb.TagNumber(4)
  set source($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSource() => $_has(3);
  @$pb.TagNumber(4)
  void clearSource() => $_clearField(4);
}

class SetDisplayResponse extends $pb.GeneratedMessage {
  factory SetDisplayResponse({
    Display? display,
  }) {
    final result = SetDisplayResponse._();
    if (display != null) result.display = display;
    return result;
  }

  SetDisplayResponse._();

  factory SetDisplayResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetDisplayResponse()..mergeFromBuffer(data, registry);
  factory SetDisplayResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetDisplayResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetDisplayResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.power.v1'),
      createEmptyInstance: SetDisplayResponse.$_createMessage)
    ..aOM<Display>(1, _omitFieldNames ? '' : 'display',
        subBuilder: Display.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetDisplayResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetDisplayResponse copyWith(void Function(SetDisplayResponse) updates) =>
      super.copyWith((message) => updates(message as SetDisplayResponse))
          as SetDisplayResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SetDisplayResponse() / SetDisplayResponse.new instead')
  static SetDisplayResponse create() => SetDisplayResponse._();
  static $pb.GeneratedMessage $_createMessage() => SetDisplayResponse._();
  @$core.override
  SetDisplayResponse createEmptyInstance() => SetDisplayResponse._();
  @$core.pragma('dart2js:noInline')
  static SetDisplayResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetDisplayResponse>(
          SetDisplayResponse.$_createMessage);
  static SetDisplayResponse? _defaultInstance;

  /// The state right after the change.
  @$pb.TagNumber(1)
  Display get display => $_getN(0);
  @$pb.TagNumber(1)
  set display(Display value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasDisplay() => $_has(0);
  @$pb.TagNumber(1)
  void clearDisplay() => $_clearField(1);
  @$pb.TagNumber(1)
  Display ensureDisplay() => $_ensure(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
