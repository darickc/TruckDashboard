// This is a generated file - do not edit.
//
// Generated from f250/vehicle/v1/diagnostics.proto.

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

@$core.Deprecated('Use setPollingRequestDescriptor instead')
const SetPollingRequest$json = {
  '1': 'SetPollingRequest',
  '2': [
    {'1': 'signal_id', '3': 1, '4': 1, '5': 9, '10': 'signalId'},
    {'1': 'enabled', '3': 2, '4': 1, '5': 8, '10': 'enabled'},
  ],
};

/// Descriptor for `SetPollingRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setPollingRequestDescriptor = $convert.base64Decode(
    'ChFTZXRQb2xsaW5nUmVxdWVzdBIbCglzaWduYWxfaWQYASABKAlSCHNpZ25hbElkEhgKB2VuYW'
    'JsZWQYAiABKAhSB2VuYWJsZWQ=');

@$core.Deprecated('Use setPollingResponseDescriptor instead')
const SetPollingResponse$json = {
  '1': 'SetPollingResponse',
};

/// Descriptor for `SetPollingResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setPollingResponseDescriptor =
    $convert.base64Decode('ChJTZXRQb2xsaW5nUmVzcG9uc2U=');

@$core.Deprecated('Use probeRequestDescriptor instead')
const ProbeRequest$json = {
  '1': 'ProbeRequest',
  '2': [
    {'1': 'signal_id', '3': 1, '4': 1, '5': 9, '10': 'signalId'},
    {'1': 'count', '3': 2, '4': 1, '5': 13, '10': 'count'},
  ],
};

/// Descriptor for `ProbeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List probeRequestDescriptor = $convert.base64Decode(
    'CgxQcm9iZVJlcXVlc3QSGwoJc2lnbmFsX2lkGAEgASgJUghzaWduYWxJZBIUCgVjb3VudBgCIA'
    'EoDVIFY291bnQ=');

@$core.Deprecated('Use responderDescriptor instead')
const Responder$json = {
  '1': 'Responder',
  '2': [
    {'1': 'can_id', '3': 1, '4': 1, '5': 9, '10': 'canId'},
    {'1': 'payload_hex', '3': 2, '4': 1, '5': 9, '10': 'payloadHex'},
    {
      '1': 'decoded',
      '3': 3,
      '4': 1,
      '5': 1,
      '9': 0,
      '10': 'decoded',
      '17': true
    },
  ],
  '8': [
    {'1': '_decoded'},
  ],
};

/// Descriptor for `Responder`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List responderDescriptor = $convert.base64Decode(
    'CglSZXNwb25kZXISFQoGY2FuX2lkGAEgASgJUgVjYW5JZBIfCgtwYXlsb2FkX2hleBgCIAEoCV'
    'IKcGF5bG9hZEhleBIdCgdkZWNvZGVkGAMgASgBSABSB2RlY29kZWSIAQFCCgoIX2RlY29kZWQ=');

@$core.Deprecated('Use probeAttemptDescriptor instead')
const ProbeAttempt$json = {
  '1': 'ProbeAttempt',
  '2': [
    {'1': 'outcome', '3': 1, '4': 1, '5': 9, '10': 'outcome'},
    {'1': 'latency_ms', '3': 2, '4': 1, '5': 13, '10': 'latencyMs'},
    {
      '1': 'responders',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.f250.vehicle.v1.Responder',
      '10': 'responders'
    },
    {'1': 'nrc', '3': 4, '4': 1, '5': 13, '10': 'nrc'},
    {'1': 'detail', '3': 5, '4': 1, '5': 9, '10': 'detail'},
  ],
};

/// Descriptor for `ProbeAttempt`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List probeAttemptDescriptor = $convert.base64Decode(
    'CgxQcm9iZUF0dGVtcHQSGAoHb3V0Y29tZRgBIAEoCVIHb3V0Y29tZRIdCgpsYXRlbmN5X21zGA'
    'IgASgNUglsYXRlbmN5TXMSOgoKcmVzcG9uZGVycxgDIAMoCzIaLmYyNTAudmVoaWNsZS52MS5S'
    'ZXNwb25kZXJSCnJlc3BvbmRlcnMSEAoDbnJjGAQgASgNUgNucmMSFgoGZGV0YWlsGAUgASgJUg'
    'ZkZXRhaWw=');

@$core.Deprecated('Use probeResponseDescriptor instead')
const ProbeResponse$json = {
  '1': 'ProbeResponse',
  '2': [
    {
      '1': 'attempts',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.f250.vehicle.v1.ProbeAttempt',
      '10': 'attempts'
    },
  ],
};

/// Descriptor for `ProbeResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List probeResponseDescriptor = $convert.base64Decode(
    'Cg1Qcm9iZVJlc3BvbnNlEjkKCGF0dGVtcHRzGAEgAygLMh0uZjI1MC52ZWhpY2xlLnYxLlByb2'
    'JlQXR0ZW1wdFIIYXR0ZW1wdHM=');

@$core.Deprecated('Use rawRequestDescriptor instead')
const RawRequest$json = {
  '1': 'RawRequest',
  '2': [
    {'1': 'line', '3': 1, '4': 1, '5': 9, '10': 'line'},
  ],
};

/// Descriptor for `RawRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rawRequestDescriptor =
    $convert.base64Decode('CgpSYXdSZXF1ZXN0EhIKBGxpbmUYASABKAlSBGxpbmU=');

@$core.Deprecated('Use rawResponseDescriptor instead')
const RawResponse$json = {
  '1': 'RawResponse',
  '2': [
    {'1': 'lines', '3': 1, '4': 3, '5': 9, '10': 'lines'},
    {'1': 'latency_ms', '3': 2, '4': 1, '5': 13, '10': 'latencyMs'},
    {'1': 'refused', '3': 3, '4': 1, '5': 9, '10': 'refused'},
  ],
};

/// Descriptor for `RawResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rawResponseDescriptor = $convert.base64Decode(
    'CgtSYXdSZXNwb25zZRIUCgVsaW5lcxgBIAMoCVIFbGluZXMSHQoKbGF0ZW5jeV9tcxgCIAEoDV'
    'IJbGF0ZW5jeU1zEhgKB3JlZnVzZWQYAyABKAlSB3JlZnVzZWQ=');

@$core.Deprecated('Use statsRequestDescriptor instead')
const StatsRequest$json = {
  '1': 'StatsRequest',
  '2': [
    {'1': 'reset', '3': 1, '4': 1, '5': 8, '10': 'reset'},
  ],
};

/// Descriptor for `StatsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List statsRequestDescriptor =
    $convert.base64Decode('CgxTdGF0c1JlcXVlc3QSFAoFcmVzZXQYASABKAhSBXJlc2V0');

@$core.Deprecated('Use signalStatsDescriptor instead')
const SignalStats$json = {
  '1': 'SignalStats',
  '2': [
    {'1': 'signal_id', '3': 1, '4': 1, '5': 9, '10': 'signalId'},
    {'1': 'successes', '3': 2, '4': 1, '5': 4, '10': 'successes'},
    {'1': 'failures', '3': 3, '4': 1, '5': 4, '10': 'failures'},
    {'1': 'latency_p50_ms', '3': 4, '4': 1, '5': 13, '10': 'latencyP50Ms'},
    {'1': 'latency_p95_ms', '3': 5, '4': 1, '5': 13, '10': 'latencyP95Ms'},
    {'1': 'poll_state', '3': 6, '4': 1, '5': 9, '10': 'pollState'},
    {'1': 'interval_ms', '3': 7, '4': 1, '5': 13, '10': 'intervalMs'},
  ],
};

/// Descriptor for `SignalStats`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List signalStatsDescriptor = $convert.base64Decode(
    'CgtTaWduYWxTdGF0cxIbCglzaWduYWxfaWQYASABKAlSCHNpZ25hbElkEhwKCXN1Y2Nlc3Nlcx'
    'gCIAEoBFIJc3VjY2Vzc2VzEhoKCGZhaWx1cmVzGAMgASgEUghmYWlsdXJlcxIkCg5sYXRlbmN5'
    'X3A1MF9tcxgEIAEoDVIMbGF0ZW5jeVA1ME1zEiQKDmxhdGVuY3lfcDk1X21zGAUgASgNUgxsYX'
    'RlbmN5UDk1TXMSHQoKcG9sbF9zdGF0ZRgGIAEoCVIJcG9sbFN0YXRlEh8KC2ludGVydmFsX21z'
    'GAcgASgNUgppbnRlcnZhbE1z');

@$core.Deprecated('Use statsResponseDescriptor instead')
const StatsResponse$json = {
  '1': 'StatsResponse',
  '2': [
    {
      '1': 'requests_per_second',
      '3': 1,
      '4': 1,
      '5': 1,
      '10': 'requestsPerSecond'
    },
    {
      '1': 'signals',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.f250.vehicle.v1.SignalStats',
      '10': 'signals'
    },
    {'1': 'window_ms', '3': 3, '4': 1, '5': 4, '10': 'windowMs'},
  ],
};

/// Descriptor for `StatsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List statsResponseDescriptor = $convert.base64Decode(
    'Cg1TdGF0c1Jlc3BvbnNlEi4KE3JlcXVlc3RzX3Blcl9zZWNvbmQYASABKAFSEXJlcXVlc3RzUG'
    'VyU2Vjb25kEjYKB3NpZ25hbHMYAiADKAsyHC5mMjUwLnZlaGljbGUudjEuU2lnbmFsU3RhdHNS'
    'B3NpZ25hbHMSGwoJd2luZG93X21zGAMgASgEUgh3aW5kb3dNcw==');
