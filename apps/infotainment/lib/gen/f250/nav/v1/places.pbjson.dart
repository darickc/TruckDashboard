// This is a generated file - do not edit.
//
// Generated from f250/nav/v1/places.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use placeKindDescriptor instead')
const PlaceKind$json = {
  '1': 'PlaceKind',
  '2': [
    {'1': 'PLACE_KIND_UNSPECIFIED', '2': 0},
    {'1': 'PLACE_KIND_HOME', '2': 1},
    {'1': 'PLACE_KIND_FAVOURITE', '2': 2},
    {'1': 'PLACE_KIND_RECENT', '2': 3},
  ],
};

/// Descriptor for `PlaceKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List placeKindDescriptor = $convert.base64Decode(
    'CglQbGFjZUtpbmQSGgoWUExBQ0VfS0lORF9VTlNQRUNJRklFRBAAEhMKD1BMQUNFX0tJTkRfSE'
    '9NRRABEhgKFFBMQUNFX0tJTkRfRkFWT1VSSVRFEAISFQoRUExBQ0VfS0lORF9SRUNFTlQQAw==');

@$core.Deprecated('Use placeDescriptor instead')
const Place$json = {
  '1': 'Place',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 4, '10': 'id'},
    {
      '1': 'kind',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.f250.nav.v1.PlaceKind',
      '10': 'kind'
    },
    {'1': 'name', '3': 3, '4': 1, '5': 9, '10': 'name'},
    {'1': 'detail', '3': 4, '4': 1, '5': 9, '10': 'detail'},
    {
      '1': 'location',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.f250.nav.v1.LatLon',
      '10': 'location'
    },
  ],
};

/// Descriptor for `Place`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List placeDescriptor = $convert.base64Decode(
    'CgVQbGFjZRIOCgJpZBgBIAEoBFICaWQSKgoEa2luZBgCIAEoDjIWLmYyNTAubmF2LnYxLlBsYW'
    'NlS2luZFIEa2luZBISCgRuYW1lGAMgASgJUgRuYW1lEhYKBmRldGFpbBgEIAEoCVIGZGV0YWls'
    'Ei8KCGxvY2F0aW9uGAUgASgLMhMuZjI1MC5uYXYudjEuTGF0TG9uUghsb2NhdGlvbg==');

@$core.Deprecated('Use placesStorageDescriptor instead')
const PlacesStorage$json = {
  '1': 'PlacesStorage',
  '2': [
    {'1': 'writable', '3': 1, '4': 1, '5': 8, '10': 'writable'},
    {'1': 'location', '3': 2, '4': 1, '5': 9, '10': 'location'},
    {'1': 'problem', '3': 3, '4': 1, '5': 9, '10': 'problem'},
  ],
};

/// Descriptor for `PlacesStorage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List placesStorageDescriptor = $convert.base64Decode(
    'Cg1QbGFjZXNTdG9yYWdlEhoKCHdyaXRhYmxlGAEgASgIUgh3cml0YWJsZRIaCghsb2NhdGlvbh'
    'gCIAEoCVIIbG9jYXRpb24SGAoHcHJvYmxlbRgDIAEoCVIHcHJvYmxlbQ==');

@$core.Deprecated('Use placesDescriptor instead')
const Places$json = {
  '1': 'Places',
  '2': [
    {
      '1': 'home',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.nav.v1.Place',
      '10': 'home'
    },
    {
      '1': 'favourites',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.f250.nav.v1.Place',
      '10': 'favourites'
    },
    {
      '1': 'recents',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.f250.nav.v1.Place',
      '10': 'recents'
    },
    {
      '1': 'storage',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.f250.nav.v1.PlacesStorage',
      '10': 'storage'
    },
    {'1': 'max_favourites', '3': 5, '4': 1, '5': 13, '10': 'maxFavourites'},
    {'1': 'max_recents', '3': 6, '4': 1, '5': 13, '10': 'maxRecents'},
    {'1': 'max_name_chars', '3': 7, '4': 1, '5': 13, '10': 'maxNameChars'},
  ],
};

/// Descriptor for `Places`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List placesDescriptor = $convert.base64Decode(
    'CgZQbGFjZXMSJgoEaG9tZRgBIAEoCzISLmYyNTAubmF2LnYxLlBsYWNlUgRob21lEjIKCmZhdm'
    '91cml0ZXMYAiADKAsyEi5mMjUwLm5hdi52MS5QbGFjZVIKZmF2b3VyaXRlcxIsCgdyZWNlbnRz'
    'GAMgAygLMhIuZjI1MC5uYXYudjEuUGxhY2VSB3JlY2VudHMSNAoHc3RvcmFnZRgEIAEoCzIaLm'
    'YyNTAubmF2LnYxLlBsYWNlc1N0b3JhZ2VSB3N0b3JhZ2USJQoObWF4X2Zhdm91cml0ZXMYBSAB'
    'KA1SDW1heEZhdm91cml0ZXMSHwoLbWF4X3JlY2VudHMYBiABKA1SCm1heFJlY2VudHMSJAoObW'
    'F4X25hbWVfY2hhcnMYByABKA1SDG1heE5hbWVDaGFycw==');

@$core.Deprecated('Use listPlacesRequestDescriptor instead')
const ListPlacesRequest$json = {
  '1': 'ListPlacesRequest',
};

/// Descriptor for `ListPlacesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listPlacesRequestDescriptor =
    $convert.base64Decode('ChFMaXN0UGxhY2VzUmVxdWVzdA==');

@$core.Deprecated('Use listPlacesResponseDescriptor instead')
const ListPlacesResponse$json = {
  '1': 'ListPlacesResponse',
  '2': [
    {
      '1': 'places',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.nav.v1.Places',
      '10': 'places'
    },
  ],
};

/// Descriptor for `ListPlacesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listPlacesResponseDescriptor = $convert.base64Decode(
    'ChJMaXN0UGxhY2VzUmVzcG9uc2USKwoGcGxhY2VzGAEgASgLMhMuZjI1MC5uYXYudjEuUGxhY2'
    'VzUgZwbGFjZXM=');

@$core.Deprecated('Use savePlaceRequestDescriptor instead')
const SavePlaceRequest$json = {
  '1': 'SavePlaceRequest',
  '2': [
    {
      '1': 'kind',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.f250.nav.v1.PlaceKind',
      '10': 'kind'
    },
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'detail', '3': 3, '4': 1, '5': 9, '10': 'detail'},
    {
      '1': 'location',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.f250.nav.v1.LatLon',
      '10': 'location'
    },
  ],
};

/// Descriptor for `SavePlaceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List savePlaceRequestDescriptor = $convert.base64Decode(
    'ChBTYXZlUGxhY2VSZXF1ZXN0EioKBGtpbmQYASABKA4yFi5mMjUwLm5hdi52MS5QbGFjZUtpbm'
    'RSBGtpbmQSEgoEbmFtZRgCIAEoCVIEbmFtZRIWCgZkZXRhaWwYAyABKAlSBmRldGFpbBIvCghs'
    'b2NhdGlvbhgEIAEoCzITLmYyNTAubmF2LnYxLkxhdExvblIIbG9jYXRpb24=');

@$core.Deprecated('Use savePlaceResponseDescriptor instead')
const SavePlaceResponse$json = {
  '1': 'SavePlaceResponse',
  '2': [
    {
      '1': 'places',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.nav.v1.Places',
      '10': 'places'
    },
  ],
};

/// Descriptor for `SavePlaceResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List savePlaceResponseDescriptor = $convert.base64Decode(
    'ChFTYXZlUGxhY2VSZXNwb25zZRIrCgZwbGFjZXMYASABKAsyEy5mMjUwLm5hdi52MS5QbGFjZX'
    'NSBnBsYWNlcw==');

@$core.Deprecated('Use renamePlaceRequestDescriptor instead')
const RenamePlaceRequest$json = {
  '1': 'RenamePlaceRequest',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 4, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
  ],
};

/// Descriptor for `RenamePlaceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List renamePlaceRequestDescriptor = $convert.base64Decode(
    'ChJSZW5hbWVQbGFjZVJlcXVlc3QSDgoCaWQYASABKARSAmlkEhIKBG5hbWUYAiABKAlSBG5hbW'
    'U=');

@$core.Deprecated('Use renamePlaceResponseDescriptor instead')
const RenamePlaceResponse$json = {
  '1': 'RenamePlaceResponse',
  '2': [
    {
      '1': 'places',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.nav.v1.Places',
      '10': 'places'
    },
  ],
};

/// Descriptor for `RenamePlaceResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List renamePlaceResponseDescriptor = $convert.base64Decode(
    'ChNSZW5hbWVQbGFjZVJlc3BvbnNlEisKBnBsYWNlcxgBIAEoCzITLmYyNTAubmF2LnYxLlBsYW'
    'Nlc1IGcGxhY2Vz');

@$core.Deprecated('Use deletePlaceRequestDescriptor instead')
const DeletePlaceRequest$json = {
  '1': 'DeletePlaceRequest',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 4, '10': 'id'},
  ],
};

/// Descriptor for `DeletePlaceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deletePlaceRequestDescriptor =
    $convert.base64Decode('ChJEZWxldGVQbGFjZVJlcXVlc3QSDgoCaWQYASABKARSAmlk');

@$core.Deprecated('Use deletePlaceResponseDescriptor instead')
const DeletePlaceResponse$json = {
  '1': 'DeletePlaceResponse',
  '2': [
    {
      '1': 'places',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.nav.v1.Places',
      '10': 'places'
    },
  ],
};

/// Descriptor for `DeletePlaceResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deletePlaceResponseDescriptor = $convert.base64Decode(
    'ChNEZWxldGVQbGFjZVJlc3BvbnNlEisKBnBsYWNlcxgBIAEoCzITLmYyNTAubmF2LnYxLlBsYW'
    'Nlc1IGcGxhY2Vz');
