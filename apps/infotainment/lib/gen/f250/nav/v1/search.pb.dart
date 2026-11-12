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

import 'route.pb.dart' as $1;
import 'search.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'search.pbenum.dart';

class SearchRequest extends $pb.GeneratedMessage {
  factory SearchRequest({
    $core.String? query,
    $core.int? limit,
  }) {
    final result = SearchRequest._();
    if (query != null) result.query = query;
    if (limit != null) result.limit = limit;
    return result;
  }

  SearchRequest._();

  factory SearchRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchRequest()..mergeFromBuffer(data, registry);
  factory SearchRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SearchRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: SearchRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'query')
    ..aI(2, _omitFieldNames ? '' : 'limit', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchRequest copyWith(void Function(SearchRequest) updates) =>
      super.copyWith((message) => updates(message as SearchRequest))
          as SearchRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SearchRequest() / SearchRequest.new instead')
  static SearchRequest create() => SearchRequest._();
  static $pb.GeneratedMessage $_createMessage() => SearchRequest._();
  @$core.override
  SearchRequest createEmptyInstance() => SearchRequest._();
  @$core.pragma('dart2js:noInline')
  static SearchRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SearchRequest>(
          SearchRequest.$_createMessage);
  static SearchRequest? _defaultInstance;

  /// As typed: "120 n main st fairview". The last word may be unfinished.
  @$pb.TagNumber(1)
  $core.String get query => $_getSZ(0);
  @$pb.TagNumber(1)
  set query($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasQuery() => $_has(0);
  @$pb.TagNumber(1)
  void clearQuery() => $_clearField(1);

  /// At most this many results; 0 for the service's default (8).
  @$pb.TagNumber(2)
  $core.int get limit => $_getIZ(1);
  @$pb.TagNumber(2)
  set limit($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLimit() => $_has(1);
  @$pb.TagNumber(2)
  void clearLimit() => $_clearField(2);
}

class SearchResult extends $pb.GeneratedMessage {
  factory SearchResult({
    MatchKind? kind,
    $core.String? title,
    $core.String? subtitle,
    $1.LatLon? location,
    $core.double? distanceM,
    $core.bool? houseNumberMissing,
    $core.Iterable<$core.String>? unmatchedWords,
  }) {
    final result = SearchResult._();
    if (kind != null) result.kind = kind;
    if (title != null) result.title = title;
    if (subtitle != null) result.subtitle = subtitle;
    if (location != null) result.location = location;
    if (distanceM != null) result.distanceM = distanceM;
    if (houseNumberMissing != null)
      result.houseNumberMissing = houseNumberMissing;
    if (unmatchedWords != null) result.unmatchedWords.addAll(unmatchedWords);
    return result;
  }

  SearchResult._();

  factory SearchResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchResult()..mergeFromBuffer(data, registry);
  factory SearchResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchResult()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SearchResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: SearchResult.$_createMessage)
    ..aE<MatchKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: MatchKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..aOS(3, _omitFieldNames ? '' : 'subtitle')
    ..aOM<$1.LatLon>(4, _omitFieldNames ? '' : 'location',
        subBuilder: $1.LatLon.$_createMessage)
    ..aD(5, _omitFieldNames ? '' : 'distanceM')
    ..aOB(6, _omitFieldNames ? '' : 'houseNumberMissing')
    ..pPS(7, _omitFieldNames ? '' : 'unmatchedWords')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchResult copyWith(void Function(SearchResult) updates) =>
      super.copyWith((message) => updates(message as SearchResult))
          as SearchResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SearchResult() / SearchResult.new instead')
  static SearchResult create() => SearchResult._();
  static $pb.GeneratedMessage $_createMessage() => SearchResult._();
  @$core.override
  SearchResult createEmptyInstance() => SearchResult._();
  @$core.pragma('dart2js:noInline')
  static SearchResult getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SearchResult>(
          SearchResult.$_createMessage);
  static SearchResult? _defaultInstance;

  @$pb.TagNumber(1)
  MatchKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(MatchKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  /// "120 North Main Street", "Casey's General Store", "Fairview".
  @$pb.TagNumber(2)
  $core.String get title => $_getSZ(1);
  @$pb.TagNumber(2)
  set title($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTitle() => $_has(1);
  @$pb.TagNumber(2)
  void clearTitle() => $_clearField(2);

  /// Its town ("Fairview", or "near Fairview" when that is only the nearest
  /// town), a category ("Fuel"), or the kind of place ("Town").
  @$pb.TagNumber(3)
  $core.String get subtitle => $_getSZ(2);
  @$pb.TagNumber(3)
  set subtitle($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSubtitle() => $_has(2);
  @$pb.TagNumber(3)
  void clearSubtitle() => $_clearField(3);

  /// Where a route to it ends: the address, a point on the street, the
  /// town's centre.
  @$pb.TagNumber(4)
  $1.LatLon get location => $_getN(3);
  @$pb.TagNumber(4)
  set location($1.LatLon value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasLocation() => $_has(3);
  @$pb.TagNumber(4)
  void clearLocation() => $_clearField(4);
  @$pb.TagNumber(4)
  $1.LatLon ensureLocation() => $_ensure(3);

  /// Straight-line distance from the position the search was ranked from;
  /// absent without one.
  @$pb.TagNumber(5)
  $core.double get distanceM => $_getN(4);
  @$pb.TagNumber(5)
  set distanceM($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDistanceM() => $_has(4);
  @$pb.TagNumber(5)
  void clearDistanceM() => $_clearField(5);

  /// The query had a house number and this result doesn't have it.
  @$pb.TagNumber(6)
  $core.bool get houseNumberMissing => $_getBF(5);
  @$pb.TagNumber(6)
  set houseNumberMissing($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasHouseNumberMissing() => $_has(5);
  @$pb.TagNumber(6)
  void clearHouseNumberMissing() => $_clearField(6);

  /// Query words this result doesn't match: only when nothing matched them
  /// all (e.g. a street found, but not in the town typed).
  @$pb.TagNumber(7)
  $pb.PbList<$core.String> get unmatchedWords => $_getList(6);
}

class SearchResponse extends $pb.GeneratedMessage {
  factory SearchResponse({
    $core.bool? available,
    $core.String? detail,
    $core.Iterable<SearchResult>? results,
    $core.Iterable<$core.String>? regions,
    $core.String? dataDate,
    RankedFrom? rankedFrom,
    $core.double? positionAgeS,
    $core.String? query,
  }) {
    final result = SearchResponse._();
    if (available != null) result.available = available;
    if (detail != null) result.detail = detail;
    if (results != null) result.results.addAll(results);
    if (regions != null) result.regions.addAll(regions);
    if (dataDate != null) result.dataDate = dataDate;
    if (rankedFrom != null) result.rankedFrom = rankedFrom;
    if (positionAgeS != null) result.positionAgeS = positionAgeS;
    if (query != null) result.query = query;
    return result;
  }

  SearchResponse._();

  factory SearchResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchResponse()..mergeFromBuffer(data, registry);
  factory SearchResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SearchResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: SearchResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'available')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..pPM<SearchResult>(3, _omitFieldNames ? '' : 'results',
        subBuilder: SearchResult.$_createMessage)
    ..pPS(4, _omitFieldNames ? '' : 'regions')
    ..aOS(5, _omitFieldNames ? '' : 'dataDate')
    ..aE<RankedFrom>(6, _omitFieldNames ? '' : 'rankedFrom',
        enumValues: RankedFrom.values)
    ..aD(7, _omitFieldNames ? '' : 'positionAgeS')
    ..aOS(8, _omitFieldNames ? '' : 'query')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchResponse copyWith(void Function(SearchResponse) updates) =>
      super.copyWith((message) => updates(message as SearchResponse))
          as SearchResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SearchResponse() / SearchResponse.new instead')
  static SearchResponse create() => SearchResponse._();
  static $pb.GeneratedMessage $_createMessage() => SearchResponse._();
  @$core.override
  SearchResponse createEmptyInstance() => SearchResponse._();
  @$core.pragma('dart2js:noInline')
  static SearchResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SearchResponse>(
          SearchResponse.$_createMessage);
  static SearchResponse? _defaultInstance;

  /// An index is installed and readable.
  @$pb.TagNumber(1)
  $core.bool get available => $_getBF(0);
  @$pb.TagNumber(1)
  set available($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAvailable() => $_has(0);
  @$pb.TagNumber(1)
  void clearAvailable() => $_clearField(1);

  /// Why not, when not available: "No search data: …".
  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<SearchResult> get results => $_getList(2);

  /// What the index covers, e.g. ["Kansas"], and its OpenStreetMap date
  /// (YYYY-MM-DD, empty if unknown).
  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get regions => $_getList(3);

  @$pb.TagNumber(5)
  $core.String get dataDate => $_getSZ(4);
  @$pb.TagNumber(5)
  set dataDate($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDataDate() => $_has(4);
  @$pb.TagNumber(5)
  void clearDataDate() => $_clearField(5);

  @$pb.TagNumber(6)
  RankedFrom get rankedFrom => $_getN(5);
  @$pb.TagNumber(6)
  set rankedFrom(RankedFrom value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasRankedFrom() => $_has(5);
  @$pb.TagNumber(6)
  void clearRankedFrom() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.double get positionAgeS => $_getN(6);
  @$pb.TagNumber(7)
  set positionAgeS($core.double value) => $_setDouble(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPositionAgeS() => $_has(6);
  @$pb.TagNumber(7)
  void clearPositionAgeS() => $_clearField(7);

  /// The query this answers, so a client typing fast can drop stale answers.
  @$pb.TagNumber(8)
  $core.String get query => $_getSZ(7);
  @$pb.TagNumber(8)
  set query($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasQuery() => $_has(7);
  @$pb.TagNumber(8)
  void clearQuery() => $_clearField(8);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
