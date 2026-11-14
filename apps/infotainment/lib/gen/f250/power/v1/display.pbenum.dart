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

class DisplayMode extends $pb.ProtobufEnum {
  static const DisplayMode DISPLAY_MODE_UNSPECIFIED =
      DisplayMode._(0, _omitEnumNames ? '' : 'DISPLAY_MODE_UNSPECIFIED');
  static const DisplayMode DISPLAY_MODE_DAY =
      DisplayMode._(1, _omitEnumNames ? '' : 'DISPLAY_MODE_DAY');
  static const DisplayMode DISPLAY_MODE_NIGHT =
      DisplayMode._(2, _omitEnumNames ? '' : 'DISPLAY_MODE_NIGHT');

  static const $core.List<DisplayMode> values = <DisplayMode>[
    DISPLAY_MODE_UNSPECIFIED,
    DISPLAY_MODE_DAY,
    DISPLAY_MODE_NIGHT,
  ];

  static final $core.List<DisplayMode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static DisplayMode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const DisplayMode._(super.value, super.name);
}

/// The driver's setting.
class DisplayChoice extends $pb.ProtobufEnum {
  static const DisplayChoice DISPLAY_CHOICE_UNSPECIFIED =
      DisplayChoice._(0, _omitEnumNames ? '' : 'DISPLAY_CHOICE_UNSPECIFIED');
  static const DisplayChoice DISPLAY_CHOICE_AUTO =
      DisplayChoice._(1, _omitEnumNames ? '' : 'DISPLAY_CHOICE_AUTO');
  static const DisplayChoice DISPLAY_CHOICE_DAY =
      DisplayChoice._(2, _omitEnumNames ? '' : 'DISPLAY_CHOICE_DAY');
  static const DisplayChoice DISPLAY_CHOICE_NIGHT =
      DisplayChoice._(3, _omitEnumNames ? '' : 'DISPLAY_CHOICE_NIGHT');

  static const $core.List<DisplayChoice> values = <DisplayChoice>[
    DISPLAY_CHOICE_UNSPECIFIED,
    DISPLAY_CHOICE_AUTO,
    DISPLAY_CHOICE_DAY,
    DISPLAY_CHOICE_NIGHT,
  ];

  static final $core.List<DisplayChoice?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static DisplayChoice? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const DisplayChoice._(super.value, super.name);
}

/// What decided the mode.
class ModeBasis extends $pb.ProtobufEnum {
  static const ModeBasis MODE_BASIS_UNSPECIFIED =
      ModeBasis._(0, _omitEnumNames ? '' : 'MODE_BASIS_UNSPECIFIED');

  /// Auto, following the sun.
  static const ModeBasis MODE_BASIS_SUN =
      ModeBasis._(1, _omitEnumNames ? '' : 'MODE_BASIS_SUN');

  /// The driver chose Day or Night.
  static const ModeBasis MODE_BASIS_MANUAL =
      ModeBasis._(2, _omitEnumNames ? '' : 'MODE_BASIS_MANUAL');

  /// Auto, but the sun is unknown (`sun` says why): the configured fallback.
  static const ModeBasis MODE_BASIS_FALLBACK =
      ModeBasis._(3, _omitEnumNames ? '' : 'MODE_BASIS_FALLBACK');

  static const $core.List<ModeBasis> values = <ModeBasis>[
    MODE_BASIS_UNSPECIFIED,
    MODE_BASIS_SUN,
    MODE_BASIS_MANUAL,
    MODE_BASIS_FALLBACK,
  ];

  static final $core.List<ModeBasis?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static ModeBasis? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ModeBasis._(super.value, super.name);
}

/// Whether the sun's position is known, and if not, why.
class SunStatus extends $pb.ProtobufEnum {
  static const SunStatus SUN_STATUS_UNSPECIFIED =
      SunStatus._(0, _omitEnumNames ? '' : 'SUN_STATUS_UNSPECIFIED');
  static const SunStatus SUN_STATUS_KNOWN =
      SunStatus._(1, _omitEnumNames ? '' : 'SUN_STATUS_KNOWN');

  /// No location: no GPS position yet, none saved, and none configured
  /// (DISPLAY_LATITUDE/LONGITUDE).
  static const SunStatus SUN_STATUS_NO_LOCATION =
      SunStatus._(2, _omitEnumNames ? '' : 'SUN_STATUS_NO_LOCATION');

  /// The system doesn't report the clock synchronized, and there is no GPS
  /// time either.
  static const SunStatus SUN_STATUS_CLOCK_NOT_SYNCHRONIZED =
      SunStatus._(3, _omitEnumNames ? '' : 'SUN_STATUS_CLOCK_NOT_SYNCHRONIZED');

  /// The clock reads before 2026: never set.
  static const SunStatus SUN_STATUS_CLOCK_NOT_SET =
      SunStatus._(4, _omitEnumNames ? '' : 'SUN_STATUS_CLOCK_NOT_SET');

  static const $core.List<SunStatus> values = <SunStatus>[
    SUN_STATUS_UNSPECIFIED,
    SUN_STATUS_KNOWN,
    SUN_STATUS_NO_LOCATION,
    SUN_STATUS_CLOCK_NOT_SYNCHRONIZED,
    SUN_STATUS_CLOCK_NOT_SET,
  ];

  static final $core.List<SunStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static SunStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const SunStatus._(super.value, super.name);
}

/// Where the location for the sun comes from (ADR-0028 amendment,
/// 2026-11-14), in this order of preference.
class LocationSource extends $pb.ProtobufEnum {
  static const LocationSource LOCATION_SOURCE_UNSPECIFIED =
      LocationSource._(0, _omitEnumNames ? '' : 'LOCATION_SOURCE_UNSPECIFIED');

  /// Nothing: no GPS position yet, none saved, none configured.
  static const LocationSource LOCATION_SOURCE_NONE =
      LocationSource._(1, _omitEnumNames ? '' : 'LOCATION_SOURCE_NONE');

  /// The receiver's latest fix, through navigation (current or not: the
  /// truck can't be far from its last fix).
  static const LocationSource LOCATION_SOURCE_GPS =
      LocationSource._(2, _omitEnumNames ? '' : 'LOCATION_SOURCE_GPS');

  /// The last GPS position power-manager saved (to 0.1°), while navigation
  /// has given none since power-manager started.
  static const LocationSource LOCATION_SOURCE_GPS_SAVED =
      LocationSource._(3, _omitEnumNames ? '' : 'LOCATION_SOURCE_GPS_SAVED');

  /// DISPLAY_LATITUDE/LONGITUDE: no GPS position yet and none saved.
  static const LocationSource LOCATION_SOURCE_CONFIGURED =
      LocationSource._(4, _omitEnumNames ? '' : 'LOCATION_SOURCE_CONFIGURED');

  /// navigation's simulated receiver: never the truck. Accepted only with
  /// power-manager's --gps-accept-simulated, for development.
  static const LocationSource LOCATION_SOURCE_GPS_SIMULATED = LocationSource._(
      5, _omitEnumNames ? '' : 'LOCATION_SOURCE_GPS_SIMULATED');

  static const $core.List<LocationSource> values = <LocationSource>[
    LOCATION_SOURCE_UNSPECIFIED,
    LOCATION_SOURCE_NONE,
    LOCATION_SOURCE_GPS,
    LOCATION_SOURCE_GPS_SAVED,
    LOCATION_SOURCE_CONFIGURED,
    LOCATION_SOURCE_GPS_SIMULATED,
  ];

  static final $core.List<LocationSource?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static LocationSource? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const LocationSource._(super.value, super.name);
}

/// Which clock the sun is worked out from, in this order of preference.
class ClockSource extends $pb.ProtobufEnum {
  static const ClockSource CLOCK_SOURCE_UNSPECIFIED =
      ClockSource._(0, _omitEnumNames ? '' : 'CLOCK_SOURCE_UNSPECIFIED');

  /// None believed: the sun isn't worked out.
  static const ClockSource CLOCK_SOURCE_NONE =
      ClockSource._(1, _omitEnumNames ? '' : 'CLOCK_SOURCE_NONE');

  /// The system reports the clock synchronized.
  static const ClockSource CLOCK_SOURCE_SYSTEM =
      ClockSource._(2, _omitEnumNames ? '' : 'CLOCK_SOURCE_SYSTEM');

  /// A current GPS fix's UTC time, carried on with the monotonic clock. The
  /// system clock itself isn't changed.
  static const ClockSource CLOCK_SOURCE_GPS =
      ClockSource._(3, _omitEnumNames ? '' : 'CLOCK_SOURCE_GPS');

  /// The system clock, unsynchronized, trusted by DISPLAY_TRUST_CLOCK=always.
  static const ClockSource CLOCK_SOURCE_TRUSTED =
      ClockSource._(4, _omitEnumNames ? '' : 'CLOCK_SOURCE_TRUSTED');

  static const $core.List<ClockSource> values = <ClockSource>[
    CLOCK_SOURCE_UNSPECIFIED,
    CLOCK_SOURCE_NONE,
    CLOCK_SOURCE_SYSTEM,
    CLOCK_SOURCE_GPS,
    CLOCK_SOURCE_TRUSTED,
  ];

  static final $core.List<ClockSource?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static ClockSource? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ClockSource._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
