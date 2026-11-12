// This is a generated file - do not edit.
//
// Generated from f250/nav/v1/places.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'places.pbenum.dart';
import 'route.pb.dart' as $1;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'places.pbenum.dart';

class Place extends $pb.GeneratedMessage {
  factory Place({
    $fixnum.Int64? id,
    PlaceKind? kind,
    $core.String? name,
    $core.String? detail,
    $1.LatLon? location,
  }) {
    final result = Place._();
    if (id != null) result.id = id;
    if (kind != null) result.kind = kind;
    if (name != null) result.name = name;
    if (detail != null) result.detail = detail;
    if (location != null) result.location = location;
    return result;
  }

  Place._();

  factory Place.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Place()..mergeFromBuffer(data, registry);
  factory Place.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Place()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Place',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: Place.$_createMessage)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'id', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aE<PlaceKind>(2, _omitFieldNames ? '' : 'kind',
        enumValues: PlaceKind.values)
    ..aOS(3, _omitFieldNames ? '' : 'name')
    ..aOS(4, _omitFieldNames ? '' : 'detail')
    ..aOM<$1.LatLon>(5, _omitFieldNames ? '' : 'location',
        subBuilder: $1.LatLon.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Place clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Place copyWith(void Function(Place) updates) =>
      super.copyWith((message) => updates(message as Place)) as Place;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Place() / Place.new instead')
  static Place create() => Place._();
  static $pb.GeneratedMessage $_createMessage() => Place._();
  @$core.override
  Place createEmptyInstance() => Place._();
  @$core.pragma('dart2js:noInline')
  static Place getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Place>(Place.$_createMessage);
  static Place? _defaultInstance;

  /// Unique among this store's places; never reused.
  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  PlaceKind get kind => $_getN(1);
  @$pb.TagNumber(2)
  set kind(PlaceKind value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasKind() => $_has(1);
  @$pb.TagNumber(2)
  void clearKind() => $_clearField(2);

  /// "Home", "Feed store", "120 North Main Street"; a recent one may have
  /// none (a point on the map).
  @$pb.TagNumber(3)
  $core.String get name => $_getSZ(2);
  @$pb.TagNumber(3)
  set name($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasName() => $_has(2);
  @$pb.TagNumber(3)
  void clearName() => $_clearField(3);

  /// A second line: a town, a category.
  @$pb.TagNumber(4)
  $core.String get detail => $_getSZ(3);
  @$pb.TagNumber(4)
  set detail($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDetail() => $_has(3);
  @$pb.TagNumber(4)
  void clearDetail() => $_clearField(4);

  @$pb.TagNumber(5)
  $1.LatLon get location => $_getN(4);
  @$pb.TagNumber(5)
  set location($1.LatLon value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasLocation() => $_has(4);
  @$pb.TagNumber(5)
  void clearLocation() => $_clearField(5);
  @$pb.TagNumber(5)
  $1.LatLon ensureLocation() => $_ensure(4);
}

/// Where the places are kept, and anything wrong with them.
class PlacesStorage extends $pb.GeneratedMessage {
  factory PlacesStorage({
    $core.bool? writable,
    $core.String? location,
    $core.String? problem,
  }) {
    final result = PlacesStorage._();
    if (writable != null) result.writable = writable;
    if (location != null) result.location = location;
    if (problem != null) result.problem = problem;
    return result;
  }

  PlacesStorage._();

  factory PlacesStorage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PlacesStorage()..mergeFromBuffer(data, registry);
  factory PlacesStorage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PlacesStorage()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PlacesStorage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: PlacesStorage.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'writable')
    ..aOS(2, _omitFieldNames ? '' : 'location')
    ..aOS(3, _omitFieldNames ? '' : 'problem')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlacesStorage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlacesStorage copyWith(void Function(PlacesStorage) updates) =>
      super.copyWith((message) => updates(message as PlacesStorage))
          as PlacesStorage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PlacesStorage() / PlacesStorage.new instead')
  static PlacesStorage create() => PlacesStorage._();
  static $pb.GeneratedMessage $_createMessage() => PlacesStorage._();
  @$core.override
  PlacesStorage createEmptyInstance() => PlacesStorage._();
  @$core.pragma('dart2js:noInline')
  static PlacesStorage getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PlacesStorage>(
          PlacesStorage.$_createMessage);
  static PlacesStorage? _defaultInstance;

  /// The places can be read and changed.
  @$pb.TagNumber(1)
  $core.bool get writable => $_getBF(0);
  @$pb.TagNumber(1)
  set writable($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasWritable() => $_has(0);
  @$pb.TagNumber(1)
  void clearWritable() => $_clearField(1);

  /// "the data drive", "the SD card: the data drive isn't mounted".
  @$pb.TagNumber(2)
  $core.String get location => $_getSZ(1);
  @$pb.TagNumber(2)
  set location($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLocation() => $_has(1);
  @$pb.TagNumber(2)
  void clearLocation() => $_clearField(2);

  /// A problem worth showing: an unreadable file kept aside, entries
  /// dropped, a failed write. Empty when all is well.
  @$pb.TagNumber(3)
  $core.String get problem => $_getSZ(2);
  @$pb.TagNumber(3)
  set problem($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasProblem() => $_has(2);
  @$pb.TagNumber(3)
  void clearProblem() => $_clearField(3);
}

/// Every saved place, and how they are kept.
class Places extends $pb.GeneratedMessage {
  factory Places({
    Place? home,
    $core.Iterable<Place>? favourites,
    $core.Iterable<Place>? recents,
    PlacesStorage? storage,
    $core.int? maxFavourites,
    $core.int? maxRecents,
    $core.int? maxNameChars,
  }) {
    final result = Places._();
    if (home != null) result.home = home;
    if (favourites != null) result.favourites.addAll(favourites);
    if (recents != null) result.recents.addAll(recents);
    if (storage != null) result.storage = storage;
    if (maxFavourites != null) result.maxFavourites = maxFavourites;
    if (maxRecents != null) result.maxRecents = maxRecents;
    if (maxNameChars != null) result.maxNameChars = maxNameChars;
    return result;
  }

  Places._();

  factory Places.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Places()..mergeFromBuffer(data, registry);
  factory Places.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Places()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Places',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: Places.$_createMessage)
    ..aOM<Place>(1, _omitFieldNames ? '' : 'home',
        subBuilder: Place.$_createMessage)
    ..pPM<Place>(2, _omitFieldNames ? '' : 'favourites',
        subBuilder: Place.$_createMessage)
    ..pPM<Place>(3, _omitFieldNames ? '' : 'recents',
        subBuilder: Place.$_createMessage)
    ..aOM<PlacesStorage>(4, _omitFieldNames ? '' : 'storage',
        subBuilder: PlacesStorage.$_createMessage)
    ..aI(5, _omitFieldNames ? '' : 'maxFavourites',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'maxRecents', fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'maxNameChars',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Places clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Places copyWith(void Function(Places) updates) =>
      super.copyWith((message) => updates(message as Places)) as Places;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Places() / Places.new instead')
  static Places create() => Places._();
  static $pb.GeneratedMessage $_createMessage() => Places._();
  @$core.override
  Places createEmptyInstance() => Places._();
  @$core.pragma('dart2js:noInline')
  static Places getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Places>(Places.$_createMessage);
  static Places? _defaultInstance;

  /// Absent when none is saved.
  @$pb.TagNumber(1)
  Place get home => $_getN(0);
  @$pb.TagNumber(1)
  set home(Place value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasHome() => $_has(0);
  @$pb.TagNumber(1)
  void clearHome() => $_clearField(1);
  @$pb.TagNumber(1)
  Place ensureHome() => $_ensure(0);

  @$pb.TagNumber(2)
  $pb.PbList<Place> get favourites => $_getList(1);

  /// Newest first.
  @$pb.TagNumber(3)
  $pb.PbList<Place> get recents => $_getList(2);

  @$pb.TagNumber(4)
  PlacesStorage get storage => $_getN(3);
  @$pb.TagNumber(4)
  set storage(PlacesStorage value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasStorage() => $_has(3);
  @$pb.TagNumber(4)
  void clearStorage() => $_clearField(4);
  @$pb.TagNumber(4)
  PlacesStorage ensureStorage() => $_ensure(3);

  /// The limits this service keeps: more favourites are refused, older
  /// recents dropped, longer names refused.
  @$pb.TagNumber(5)
  $core.int get maxFavourites => $_getIZ(4);
  @$pb.TagNumber(5)
  set maxFavourites($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMaxFavourites() => $_has(4);
  @$pb.TagNumber(5)
  void clearMaxFavourites() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get maxRecents => $_getIZ(5);
  @$pb.TagNumber(6)
  set maxRecents($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMaxRecents() => $_has(5);
  @$pb.TagNumber(6)
  void clearMaxRecents() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get maxNameChars => $_getIZ(6);
  @$pb.TagNumber(7)
  set maxNameChars($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasMaxNameChars() => $_has(6);
  @$pb.TagNumber(7)
  void clearMaxNameChars() => $_clearField(7);
}

class ListPlacesRequest extends $pb.GeneratedMessage {
  factory ListPlacesRequest() => ListPlacesRequest._();

  ListPlacesRequest._();

  factory ListPlacesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListPlacesRequest()..mergeFromBuffer(data, registry);
  factory ListPlacesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListPlacesRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListPlacesRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: ListPlacesRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPlacesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPlacesRequest copyWith(void Function(ListPlacesRequest) updates) =>
      super.copyWith((message) => updates(message as ListPlacesRequest))
          as ListPlacesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListPlacesRequest() / ListPlacesRequest.new instead')
  static ListPlacesRequest create() => ListPlacesRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListPlacesRequest._();
  @$core.override
  ListPlacesRequest createEmptyInstance() => ListPlacesRequest._();
  @$core.pragma('dart2js:noInline')
  static ListPlacesRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ListPlacesRequest>(
          ListPlacesRequest.$_createMessage);
  static ListPlacesRequest? _defaultInstance;
}

class ListPlacesResponse extends $pb.GeneratedMessage {
  factory ListPlacesResponse({
    Places? places,
  }) {
    final result = ListPlacesResponse._();
    if (places != null) result.places = places;
    return result;
  }

  ListPlacesResponse._();

  factory ListPlacesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListPlacesResponse()..mergeFromBuffer(data, registry);
  factory ListPlacesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListPlacesResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListPlacesResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: ListPlacesResponse.$_createMessage)
    ..aOM<Places>(1, _omitFieldNames ? '' : 'places',
        subBuilder: Places.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPlacesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPlacesResponse copyWith(void Function(ListPlacesResponse) updates) =>
      super.copyWith((message) => updates(message as ListPlacesResponse))
          as ListPlacesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListPlacesResponse() / ListPlacesResponse.new instead')
  static ListPlacesResponse create() => ListPlacesResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListPlacesResponse._();
  @$core.override
  ListPlacesResponse createEmptyInstance() => ListPlacesResponse._();
  @$core.pragma('dart2js:noInline')
  static ListPlacesResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListPlacesResponse>(
          ListPlacesResponse.$_createMessage);
  static ListPlacesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Places get places => $_getN(0);
  @$pb.TagNumber(1)
  set places(Places value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPlaces() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlaces() => $_clearField(1);
  @$pb.TagNumber(1)
  Places ensurePlaces() => $_ensure(0);
}

class SavePlaceRequest extends $pb.GeneratedMessage {
  factory SavePlaceRequest({
    PlaceKind? kind,
    $core.String? name,
    $core.String? detail,
    $1.LatLon? location,
  }) {
    final result = SavePlaceRequest._();
    if (kind != null) result.kind = kind;
    if (name != null) result.name = name;
    if (detail != null) result.detail = detail;
    if (location != null) result.location = location;
    return result;
  }

  SavePlaceRequest._();

  factory SavePlaceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SavePlaceRequest()..mergeFromBuffer(data, registry);
  factory SavePlaceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SavePlaceRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SavePlaceRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: SavePlaceRequest.$_createMessage)
    ..aE<PlaceKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: PlaceKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'detail')
    ..aOM<$1.LatLon>(4, _omitFieldNames ? '' : 'location',
        subBuilder: $1.LatLon.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SavePlaceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SavePlaceRequest copyWith(void Function(SavePlaceRequest) updates) =>
      super.copyWith((message) => updates(message as SavePlaceRequest))
          as SavePlaceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SavePlaceRequest() / SavePlaceRequest.new instead')
  static SavePlaceRequest create() => SavePlaceRequest._();
  static $pb.GeneratedMessage $_createMessage() => SavePlaceRequest._();
  @$core.override
  SavePlaceRequest createEmptyInstance() => SavePlaceRequest._();
  @$core.pragma('dart2js:noInline')
  static SavePlaceRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SavePlaceRequest>(
          SavePlaceRequest.$_createMessage);
  static SavePlaceRequest? _defaultInstance;

  /// HOME or FAVOURITE.
  @$pb.TagNumber(1)
  PlaceKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(PlaceKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get detail => $_getSZ(2);
  @$pb.TagNumber(3)
  set detail($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDetail() => $_has(2);
  @$pb.TagNumber(3)
  void clearDetail() => $_clearField(3);

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
}

class SavePlaceResponse extends $pb.GeneratedMessage {
  factory SavePlaceResponse({
    Places? places,
  }) {
    final result = SavePlaceResponse._();
    if (places != null) result.places = places;
    return result;
  }

  SavePlaceResponse._();

  factory SavePlaceResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SavePlaceResponse()..mergeFromBuffer(data, registry);
  factory SavePlaceResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SavePlaceResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SavePlaceResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: SavePlaceResponse.$_createMessage)
    ..aOM<Places>(1, _omitFieldNames ? '' : 'places',
        subBuilder: Places.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SavePlaceResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SavePlaceResponse copyWith(void Function(SavePlaceResponse) updates) =>
      super.copyWith((message) => updates(message as SavePlaceResponse))
          as SavePlaceResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SavePlaceResponse() / SavePlaceResponse.new instead')
  static SavePlaceResponse create() => SavePlaceResponse._();
  static $pb.GeneratedMessage $_createMessage() => SavePlaceResponse._();
  @$core.override
  SavePlaceResponse createEmptyInstance() => SavePlaceResponse._();
  @$core.pragma('dart2js:noInline')
  static SavePlaceResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SavePlaceResponse>(
          SavePlaceResponse.$_createMessage);
  static SavePlaceResponse? _defaultInstance;

  /// After the change.
  @$pb.TagNumber(1)
  Places get places => $_getN(0);
  @$pb.TagNumber(1)
  set places(Places value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPlaces() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlaces() => $_clearField(1);
  @$pb.TagNumber(1)
  Places ensurePlaces() => $_ensure(0);
}

class RenamePlaceRequest extends $pb.GeneratedMessage {
  factory RenamePlaceRequest({
    $fixnum.Int64? id,
    $core.String? name,
  }) {
    final result = RenamePlaceRequest._();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    return result;
  }

  RenamePlaceRequest._();

  factory RenamePlaceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RenamePlaceRequest()..mergeFromBuffer(data, registry);
  factory RenamePlaceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RenamePlaceRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RenamePlaceRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: RenamePlaceRequest.$_createMessage)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'id', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RenamePlaceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RenamePlaceRequest copyWith(void Function(RenamePlaceRequest) updates) =>
      super.copyWith((message) => updates(message as RenamePlaceRequest))
          as RenamePlaceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RenamePlaceRequest() / RenamePlaceRequest.new instead')
  static RenamePlaceRequest create() => RenamePlaceRequest._();
  static $pb.GeneratedMessage $_createMessage() => RenamePlaceRequest._();
  @$core.override
  RenamePlaceRequest createEmptyInstance() => RenamePlaceRequest._();
  @$core.pragma('dart2js:noInline')
  static RenamePlaceRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RenamePlaceRequest>(
          RenamePlaceRequest.$_createMessage);
  static RenamePlaceRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);
}

class RenamePlaceResponse extends $pb.GeneratedMessage {
  factory RenamePlaceResponse({
    Places? places,
  }) {
    final result = RenamePlaceResponse._();
    if (places != null) result.places = places;
    return result;
  }

  RenamePlaceResponse._();

  factory RenamePlaceResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RenamePlaceResponse()..mergeFromBuffer(data, registry);
  factory RenamePlaceResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RenamePlaceResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RenamePlaceResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: RenamePlaceResponse.$_createMessage)
    ..aOM<Places>(1, _omitFieldNames ? '' : 'places',
        subBuilder: Places.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RenamePlaceResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RenamePlaceResponse copyWith(void Function(RenamePlaceResponse) updates) =>
      super.copyWith((message) => updates(message as RenamePlaceResponse))
          as RenamePlaceResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use RenamePlaceResponse() / RenamePlaceResponse.new instead')
  static RenamePlaceResponse create() => RenamePlaceResponse._();
  static $pb.GeneratedMessage $_createMessage() => RenamePlaceResponse._();
  @$core.override
  RenamePlaceResponse createEmptyInstance() => RenamePlaceResponse._();
  @$core.pragma('dart2js:noInline')
  static RenamePlaceResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RenamePlaceResponse>(
          RenamePlaceResponse.$_createMessage);
  static RenamePlaceResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Places get places => $_getN(0);
  @$pb.TagNumber(1)
  set places(Places value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPlaces() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlaces() => $_clearField(1);
  @$pb.TagNumber(1)
  Places ensurePlaces() => $_ensure(0);
}

class DeletePlaceRequest extends $pb.GeneratedMessage {
  factory DeletePlaceRequest({
    $fixnum.Int64? id,
  }) {
    final result = DeletePlaceRequest._();
    if (id != null) result.id = id;
    return result;
  }

  DeletePlaceRequest._();

  factory DeletePlaceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeletePlaceRequest()..mergeFromBuffer(data, registry);
  factory DeletePlaceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeletePlaceRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeletePlaceRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: DeletePlaceRequest.$_createMessage)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'id', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeletePlaceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeletePlaceRequest copyWith(void Function(DeletePlaceRequest) updates) =>
      super.copyWith((message) => updates(message as DeletePlaceRequest))
          as DeletePlaceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DeletePlaceRequest() / DeletePlaceRequest.new instead')
  static DeletePlaceRequest create() => DeletePlaceRequest._();
  static $pb.GeneratedMessage $_createMessage() => DeletePlaceRequest._();
  @$core.override
  DeletePlaceRequest createEmptyInstance() => DeletePlaceRequest._();
  @$core.pragma('dart2js:noInline')
  static DeletePlaceRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeletePlaceRequest>(
          DeletePlaceRequest.$_createMessage);
  static DeletePlaceRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

class DeletePlaceResponse extends $pb.GeneratedMessage {
  factory DeletePlaceResponse({
    Places? places,
  }) {
    final result = DeletePlaceResponse._();
    if (places != null) result.places = places;
    return result;
  }

  DeletePlaceResponse._();

  factory DeletePlaceResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeletePlaceResponse()..mergeFromBuffer(data, registry);
  factory DeletePlaceResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeletePlaceResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeletePlaceResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'f250.nav.v1'),
      createEmptyInstance: DeletePlaceResponse.$_createMessage)
    ..aOM<Places>(1, _omitFieldNames ? '' : 'places',
        subBuilder: Places.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeletePlaceResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeletePlaceResponse copyWith(void Function(DeletePlaceResponse) updates) =>
      super.copyWith((message) => updates(message as DeletePlaceResponse))
          as DeletePlaceResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use DeletePlaceResponse() / DeletePlaceResponse.new instead')
  static DeletePlaceResponse create() => DeletePlaceResponse._();
  static $pb.GeneratedMessage $_createMessage() => DeletePlaceResponse._();
  @$core.override
  DeletePlaceResponse createEmptyInstance() => DeletePlaceResponse._();
  @$core.pragma('dart2js:noInline')
  static DeletePlaceResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeletePlaceResponse>(
          DeletePlaceResponse.$_createMessage);
  static DeletePlaceResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Places get places => $_getN(0);
  @$pb.TagNumber(1)
  set places(Places value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPlaces() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlaces() => $_clearField(1);
  @$pb.TagNumber(1)
  Places ensurePlaces() => $_ensure(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
