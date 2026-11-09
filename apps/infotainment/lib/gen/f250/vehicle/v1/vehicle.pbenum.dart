// This is a generated file - do not edit.
//
// Generated from f250/vehicle/v1/vehicle.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class Quantity extends $pb.ProtobufEnum {
  static const Quantity QUANTITY_UNSPECIFIED =
      Quantity._(0, _omitEnumNames ? '' : 'QUANTITY_UNSPECIFIED');
  static const Quantity QUANTITY_TEMPERATURE =
      Quantity._(1, _omitEnumNames ? '' : 'QUANTITY_TEMPERATURE');
  static const Quantity QUANTITY_TEMPERATURE_DELTA =
      Quantity._(2, _omitEnumNames ? '' : 'QUANTITY_TEMPERATURE_DELTA');
  static const Quantity QUANTITY_PRESSURE =
      Quantity._(3, _omitEnumNames ? '' : 'QUANTITY_PRESSURE');
  static const Quantity QUANTITY_VOLTAGE =
      Quantity._(4, _omitEnumNames ? '' : 'QUANTITY_VOLTAGE');
  static const Quantity QUANTITY_SPEED =
      Quantity._(5, _omitEnumNames ? '' : 'QUANTITY_SPEED');
  static const Quantity QUANTITY_ROTATION =
      Quantity._(6, _omitEnumNames ? '' : 'QUANTITY_ROTATION');
  static const Quantity QUANTITY_PERCENT =
      Quantity._(7, _omitEnumNames ? '' : 'QUANTITY_PERCENT');

  static const $core.List<Quantity> values = <Quantity>[
    QUANTITY_UNSPECIFIED,
    QUANTITY_TEMPERATURE,
    QUANTITY_TEMPERATURE_DELTA,
    QUANTITY_PRESSURE,
    QUANTITY_VOLTAGE,
    QUANTITY_SPEED,
    QUANTITY_ROTATION,
    QUANTITY_PERCENT,
  ];

  static final $core.List<Quantity?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 7);
  static Quantity? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Quantity._(super.value, super.name);
}

class Provenance extends $pb.ProtobufEnum {
  static const Provenance PROVENANCE_UNSPECIFIED =
      Provenance._(0, _omitEnumNames ? '' : 'PROVENANCE_UNSPECIFIED');

  /// Published SAE J1979 formula.
  static const Provenance PROVENANCE_SAE =
      Provenance._(1, _omitEnumNames ? '' : 'PROVENANCE_SAE');

  /// Confirmed on this truck; evidence in docs/diagnostics/VERIFICATION_LOG.md.
  static const Provenance PROVENANCE_VERIFIED_ON_TRUCK =
      Provenance._(2, _omitEnumNames ? '' : 'PROVENANCE_VERIFIED_ON_TRUCK');

  /// Imported (e.g. Torque export) and not yet confirmed on this truck.
  static const Provenance PROVENANCE_IMPORTED_UNVERIFIED =
      Provenance._(3, _omitEnumNames ? '' : 'PROVENANCE_IMPORTED_UNVERIFIED');
  static const Provenance PROVENANCE_COMPUTED =
      Provenance._(4, _omitEnumNames ? '' : 'PROVENANCE_COMPUTED');
  static const Provenance PROVENANCE_AUX_SENSOR =
      Provenance._(5, _omitEnumNames ? '' : 'PROVENANCE_AUX_SENSOR');
  static const Provenance PROVENANCE_BROADCAST_DECODED =
      Provenance._(6, _omitEnumNames ? '' : 'PROVENANCE_BROADCAST_DECODED');

  static const $core.List<Provenance> values = <Provenance>[
    PROVENANCE_UNSPECIFIED,
    PROVENANCE_SAE,
    PROVENANCE_VERIFIED_ON_TRUCK,
    PROVENANCE_IMPORTED_UNVERIFIED,
    PROVENANCE_COMPUTED,
    PROVENANCE_AUX_SENSOR,
    PROVENANCE_BROADCAST_DECODED,
  ];

  static final $core.List<Provenance?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static Provenance? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Provenance._(super.value, super.name);
}

class Validity extends $pb.ProtobufEnum {
  static const Validity VALIDITY_UNSPECIFIED =
      Validity._(0, _omitEnumNames ? '' : 'VALIDITY_UNSPECIFIED');
  static const Validity VALIDITY_VALID =
      Validity._(1, _omitEnumNames ? '' : 'VALIDITY_VALID');
  static const Validity VALIDITY_STALE =
      Validity._(2, _omitEnumNames ? '' : 'VALIDITY_STALE');
  static const Validity VALIDITY_NO_DATA =
      Validity._(3, _omitEnumNames ? '' : 'VALIDITY_NO_DATA');
  static const Validity VALIDITY_OUT_OF_RANGE =
      Validity._(4, _omitEnumNames ? '' : 'VALIDITY_OUT_OF_RANGE');
  static const Validity VALIDITY_DECODE_ERROR =
      Validity._(5, _omitEnumNames ? '' : 'VALIDITY_DECODE_ERROR');
  static const Validity VALIDITY_UNSUPPORTED =
      Validity._(6, _omitEnumNames ? '' : 'VALIDITY_UNSUPPORTED');
  static const Validity VALIDITY_DISABLED =
      Validity._(7, _omitEnumNames ? '' : 'VALIDITY_DISABLED');

  static const $core.List<Validity> values = <Validity>[
    VALIDITY_UNSPECIFIED,
    VALIDITY_VALID,
    VALIDITY_STALE,
    VALIDITY_NO_DATA,
    VALIDITY_OUT_OF_RANGE,
    VALIDITY_DECODE_ERROR,
    VALIDITY_UNSUPPORTED,
    VALIDITY_DISABLED,
  ];

  static final $core.List<Validity?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 7);
  static Validity? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Validity._(super.value, super.name);
}

class LinkState extends $pb.ProtobufEnum {
  static const LinkState LINK_STATE_UNSPECIFIED =
      LinkState._(0, _omitEnumNames ? '' : 'LINK_STATE_UNSPECIFIED');
  static const LinkState LINK_STATE_CONNECTING =
      LinkState._(1, _omitEnumNames ? '' : 'LINK_STATE_CONNECTING');
  static const LinkState LINK_STATE_UP =
      LinkState._(2, _omitEnumNames ? '' : 'LINK_STATE_UP');
  static const LinkState LINK_STATE_DEGRADED =
      LinkState._(3, _omitEnumNames ? '' : 'LINK_STATE_DEGRADED');
  static const LinkState LINK_STATE_DOWN =
      LinkState._(4, _omitEnumNames ? '' : 'LINK_STATE_DOWN');

  static const $core.List<LinkState> values = <LinkState>[
    LINK_STATE_UNSPECIFIED,
    LINK_STATE_CONNECTING,
    LINK_STATE_UP,
    LINK_STATE_DEGRADED,
    LINK_STATE_DOWN,
  ];

  static final $core.List<LinkState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static LinkState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const LinkState._(super.value, super.name);
}

class AlertLevel extends $pb.ProtobufEnum {
  static const AlertLevel ALERT_LEVEL_UNSPECIFIED =
      AlertLevel._(0, _omitEnumNames ? '' : 'ALERT_LEVEL_UNSPECIFIED');
  static const AlertLevel ALERT_LEVEL_ADVISORY =
      AlertLevel._(1, _omitEnumNames ? '' : 'ALERT_LEVEL_ADVISORY');
  static const AlertLevel ALERT_LEVEL_CRITICAL =
      AlertLevel._(2, _omitEnumNames ? '' : 'ALERT_LEVEL_CRITICAL');

  static const $core.List<AlertLevel> values = <AlertLevel>[
    ALERT_LEVEL_UNSPECIFIED,
    ALERT_LEVEL_ADVISORY,
    ALERT_LEVEL_CRITICAL,
  ];

  static final $core.List<AlertLevel?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static AlertLevel? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const AlertLevel._(super.value, super.name);
}

class AlertKind extends $pb.ProtobufEnum {
  static const AlertKind ALERT_KIND_UNSPECIFIED =
      AlertKind._(0, _omitEnumNames ? '' : 'ALERT_KIND_UNSPECIFIED');
  static const AlertKind ALERT_KIND_THRESHOLD =
      AlertKind._(1, _omitEnumNames ? '' : 'ALERT_KIND_THRESHOLD');
  static const AlertKind ALERT_KIND_SIGNAL_NOT_UPDATING =
      AlertKind._(2, _omitEnumNames ? '' : 'ALERT_KIND_SIGNAL_NOT_UPDATING');
  static const AlertKind ALERT_KIND_LINK_LOST =
      AlertKind._(3, _omitEnumNames ? '' : 'ALERT_KIND_LINK_LOST');

  static const $core.List<AlertKind> values = <AlertKind>[
    ALERT_KIND_UNSPECIFIED,
    ALERT_KIND_THRESHOLD,
    ALERT_KIND_SIGNAL_NOT_UPDATING,
    ALERT_KIND_LINK_LOST,
  ];

  static final $core.List<AlertKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static AlertKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const AlertKind._(super.value, super.name);
}

class EventSeverity extends $pb.ProtobufEnum {
  static const EventSeverity EVENT_SEVERITY_UNSPECIFIED =
      EventSeverity._(0, _omitEnumNames ? '' : 'EVENT_SEVERITY_UNSPECIFIED');
  static const EventSeverity EVENT_SEVERITY_INFO =
      EventSeverity._(1, _omitEnumNames ? '' : 'EVENT_SEVERITY_INFO');
  static const EventSeverity EVENT_SEVERITY_ADVISORY =
      EventSeverity._(2, _omitEnumNames ? '' : 'EVENT_SEVERITY_ADVISORY');
  static const EventSeverity EVENT_SEVERITY_CRITICAL =
      EventSeverity._(3, _omitEnumNames ? '' : 'EVENT_SEVERITY_CRITICAL');

  static const $core.List<EventSeverity> values = <EventSeverity>[
    EVENT_SEVERITY_UNSPECIFIED,
    EVENT_SEVERITY_INFO,
    EVENT_SEVERITY_ADVISORY,
    EVENT_SEVERITY_CRITICAL,
  ];

  static final $core.List<EventSeverity?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static EventSeverity? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const EventSeverity._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
