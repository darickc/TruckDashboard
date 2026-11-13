// This is a generated file - do not edit.
//
// Generated from f250/nav/v1/search.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class MatchKind extends $pb.ProtobufEnum {
  static const MatchKind MATCH_KIND_UNSPECIFIED =
      MatchKind._(0, _omitEnumNames ? '' : 'MATCH_KIND_UNSPECIFIED');

  /// The house number asked for, on that street.
  static const MatchKind MATCH_KIND_ADDRESS =
      MatchKind._(1, _omitEnumNames ? '' : 'MATCH_KIND_ADDRESS');

  /// A street. With `house_number_missing`, the query's house number isn't in
  /// the data and the street is the closest it gets.
  static const MatchKind MATCH_KIND_STREET =
      MatchKind._(2, _omitEnumNames ? '' : 'MATCH_KIND_STREET');

  /// A city, town or other named place, and nothing finer.
  static const MatchKind MATCH_KIND_LOCALITY =
      MatchKind._(3, _omitEnumNames ? '' : 'MATCH_KIND_LOCALITY');

  /// A named business, park, school…
  static const MatchKind MATCH_KIND_PLACE =
      MatchKind._(4, _omitEnumNames ? '' : 'MATCH_KIND_PLACE');

  /// The house number asked for, placed along its street by interpolating
  /// the US Census Bureau's address ranges (TIGER/Line, ADR-0041): an
  /// estimate of where the house is, not a mapped address. The subtitle ends
  /// with the range's ZIP code when it has one.
  static const MatchKind MATCH_KIND_ESTIMATED_ADDRESS =
      MatchKind._(5, _omitEnumNames ? '' : 'MATCH_KIND_ESTIMATED_ADDRESS');

  static const $core.List<MatchKind> values = <MatchKind>[
    MATCH_KIND_UNSPECIFIED,
    MATCH_KIND_ADDRESS,
    MATCH_KIND_STREET,
    MATCH_KIND_LOCALITY,
    MATCH_KIND_PLACE,
    MATCH_KIND_ESTIMATED_ADDRESS,
  ];

  static final $core.List<MatchKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static MatchKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const MatchKind._(super.value, super.name);
}

class RankedFrom extends $pb.ProtobufEnum {
  static const RankedFrom RANKED_FROM_UNSPECIFIED =
      RankedFrom._(0, _omitEnumNames ? '' : 'RANKED_FROM_UNSPECIFIED');

  /// No position: results are not ordered by distance.
  static const RankedFrom RANKED_FROM_NONE =
      RankedFrom._(1, _omitEnumNames ? '' : 'RANKED_FROM_NONE');

  /// The current fix.
  static const RankedFrom RANKED_FROM_CURRENT =
      RankedFrom._(2, _omitEnumNames ? '' : 'RANKED_FROM_CURRENT');

  /// The last known fix, `position_age_s` old.
  static const RankedFrom RANKED_FROM_LAST_KNOWN =
      RankedFrom._(3, _omitEnumNames ? '' : 'RANKED_FROM_LAST_KNOWN');

  /// The ZIP code the query ended with (`postcode`): the middle of its
  /// addresses in the data.
  static const RankedFrom RANKED_FROM_POSTCODE =
      RankedFrom._(4, _omitEnumNames ? '' : 'RANKED_FROM_POSTCODE');

  static const $core.List<RankedFrom> values = <RankedFrom>[
    RANKED_FROM_UNSPECIFIED,
    RANKED_FROM_NONE,
    RANKED_FROM_CURRENT,
    RANKED_FROM_LAST_KNOWN,
    RANKED_FROM_POSTCODE,
  ];

  static final $core.List<RankedFrom?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static RankedFrom? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const RankedFrom._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
