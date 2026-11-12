// This is a generated file - do not edit.
//
// Generated from f250/nav/v1/search.proto.

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

@$core.Deprecated('Use matchKindDescriptor instead')
const MatchKind$json = {
  '1': 'MatchKind',
  '2': [
    {'1': 'MATCH_KIND_UNSPECIFIED', '2': 0},
    {'1': 'MATCH_KIND_ADDRESS', '2': 1},
    {'1': 'MATCH_KIND_STREET', '2': 2},
    {'1': 'MATCH_KIND_LOCALITY', '2': 3},
    {'1': 'MATCH_KIND_PLACE', '2': 4},
  ],
};

/// Descriptor for `MatchKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List matchKindDescriptor = $convert.base64Decode(
    'CglNYXRjaEtpbmQSGgoWTUFUQ0hfS0lORF9VTlNQRUNJRklFRBAAEhYKEk1BVENIX0tJTkRfQU'
    'REUkVTUxABEhUKEU1BVENIX0tJTkRfU1RSRUVUEAISFwoTTUFUQ0hfS0lORF9MT0NBTElUWRAD'
    'EhQKEE1BVENIX0tJTkRfUExBQ0UQBA==');

@$core.Deprecated('Use rankedFromDescriptor instead')
const RankedFrom$json = {
  '1': 'RankedFrom',
  '2': [
    {'1': 'RANKED_FROM_UNSPECIFIED', '2': 0},
    {'1': 'RANKED_FROM_NONE', '2': 1},
    {'1': 'RANKED_FROM_CURRENT', '2': 2},
    {'1': 'RANKED_FROM_LAST_KNOWN', '2': 3},
  ],
};

/// Descriptor for `RankedFrom`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List rankedFromDescriptor = $convert.base64Decode(
    'CgpSYW5rZWRGcm9tEhsKF1JBTktFRF9GUk9NX1VOU1BFQ0lGSUVEEAASFAoQUkFOS0VEX0ZST0'
    '1fTk9ORRABEhcKE1JBTktFRF9GUk9NX0NVUlJFTlQQAhIaChZSQU5LRURfRlJPTV9MQVNUX0tO'
    'T1dOEAM=');

@$core.Deprecated('Use searchRequestDescriptor instead')
const SearchRequest$json = {
  '1': 'SearchRequest',
  '2': [
    {'1': 'query', '3': 1, '4': 1, '5': 9, '10': 'query'},
    {'1': 'limit', '3': 2, '4': 1, '5': 13, '10': 'limit'},
  ],
};

/// Descriptor for `SearchRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List searchRequestDescriptor = $convert.base64Decode(
    'Cg1TZWFyY2hSZXF1ZXN0EhQKBXF1ZXJ5GAEgASgJUgVxdWVyeRIUCgVsaW1pdBgCIAEoDVIFbG'
    'ltaXQ=');

@$core.Deprecated('Use searchResultDescriptor instead')
const SearchResult$json = {
  '1': 'SearchResult',
  '2': [
    {
      '1': 'kind',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.f250.nav.v1.MatchKind',
      '10': 'kind'
    },
    {'1': 'title', '3': 2, '4': 1, '5': 9, '10': 'title'},
    {'1': 'subtitle', '3': 3, '4': 1, '5': 9, '10': 'subtitle'},
    {
      '1': 'location',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.f250.nav.v1.LatLon',
      '10': 'location'
    },
    {
      '1': 'distance_m',
      '3': 5,
      '4': 1,
      '5': 1,
      '9': 0,
      '10': 'distanceM',
      '17': true
    },
    {
      '1': 'house_number_missing',
      '3': 6,
      '4': 1,
      '5': 8,
      '10': 'houseNumberMissing'
    },
    {'1': 'unmatched_words', '3': 7, '4': 3, '5': 9, '10': 'unmatchedWords'},
  ],
  '8': [
    {'1': '_distance_m'},
  ],
};

/// Descriptor for `SearchResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List searchResultDescriptor = $convert.base64Decode(
    'CgxTZWFyY2hSZXN1bHQSKgoEa2luZBgBIAEoDjIWLmYyNTAubmF2LnYxLk1hdGNoS2luZFIEa2'
    'luZBIUCgV0aXRsZRgCIAEoCVIFdGl0bGUSGgoIc3VidGl0bGUYAyABKAlSCHN1YnRpdGxlEi8K'
    'CGxvY2F0aW9uGAQgASgLMhMuZjI1MC5uYXYudjEuTGF0TG9uUghsb2NhdGlvbhIiCgpkaXN0YW'
    '5jZV9tGAUgASgBSABSCWRpc3RhbmNlTYgBARIwChRob3VzZV9udW1iZXJfbWlzc2luZxgGIAEo'
    'CFISaG91c2VOdW1iZXJNaXNzaW5nEicKD3VubWF0Y2hlZF93b3JkcxgHIAMoCVIOdW5tYXRjaG'
    'VkV29yZHNCDQoLX2Rpc3RhbmNlX20=');

@$core.Deprecated('Use searchResponseDescriptor instead')
const SearchResponse$json = {
  '1': 'SearchResponse',
  '2': [
    {'1': 'available', '3': 1, '4': 1, '5': 8, '10': 'available'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
    {
      '1': 'results',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.f250.nav.v1.SearchResult',
      '10': 'results'
    },
    {'1': 'regions', '3': 4, '4': 3, '5': 9, '10': 'regions'},
    {'1': 'data_date', '3': 5, '4': 1, '5': 9, '10': 'dataDate'},
    {
      '1': 'ranked_from',
      '3': 6,
      '4': 1,
      '5': 14,
      '6': '.f250.nav.v1.RankedFrom',
      '10': 'rankedFrom'
    },
    {'1': 'position_age_s', '3': 7, '4': 1, '5': 1, '10': 'positionAgeS'},
    {'1': 'query', '3': 8, '4': 1, '5': 9, '10': 'query'},
  ],
};

/// Descriptor for `SearchResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List searchResponseDescriptor = $convert.base64Decode(
    'Cg5TZWFyY2hSZXNwb25zZRIcCglhdmFpbGFibGUYASABKAhSCWF2YWlsYWJsZRIWCgZkZXRhaW'
    'wYAiABKAlSBmRldGFpbBIzCgdyZXN1bHRzGAMgAygLMhkuZjI1MC5uYXYudjEuU2VhcmNoUmVz'
    'dWx0UgdyZXN1bHRzEhgKB3JlZ2lvbnMYBCADKAlSB3JlZ2lvbnMSGwoJZGF0YV9kYXRlGAUgAS'
    'gJUghkYXRhRGF0ZRI4CgtyYW5rZWRfZnJvbRgGIAEoDjIXLmYyNTAubmF2LnYxLlJhbmtlZEZy'
    'b21SCnJhbmtlZEZyb20SJAoOcG9zaXRpb25fYWdlX3MYByABKAFSDHBvc2l0aW9uQWdlUxIUCg'
    'VxdWVyeRgIIAEoCVIFcXVlcnk=');
