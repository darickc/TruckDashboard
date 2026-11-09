// This is a generated file - do not edit.
//
// Generated from f250/vehicle/v1/vehicle.proto.

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

@$core.Deprecated('Use quantityDescriptor instead')
const Quantity$json = {
  '1': 'Quantity',
  '2': [
    {'1': 'QUANTITY_UNSPECIFIED', '2': 0},
    {'1': 'QUANTITY_TEMPERATURE', '2': 1},
    {'1': 'QUANTITY_TEMPERATURE_DELTA', '2': 2},
    {'1': 'QUANTITY_PRESSURE', '2': 3},
    {'1': 'QUANTITY_VOLTAGE', '2': 4},
    {'1': 'QUANTITY_SPEED', '2': 5},
    {'1': 'QUANTITY_ROTATION', '2': 6},
    {'1': 'QUANTITY_PERCENT', '2': 7},
  ],
};

/// Descriptor for `Quantity`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List quantityDescriptor = $convert.base64Decode(
    'CghRdWFudGl0eRIYChRRVUFOVElUWV9VTlNQRUNJRklFRBAAEhgKFFFVQU5USVRZX1RFTVBFUk'
    'FUVVJFEAESHgoaUVVBTlRJVFlfVEVNUEVSQVRVUkVfREVMVEEQAhIVChFRVUFOVElUWV9QUkVT'
    'U1VSRRADEhQKEFFVQU5USVRZX1ZPTFRBR0UQBBISCg5RVUFOVElUWV9TUEVFRBAFEhUKEVFVQU'
    '5USVRZX1JPVEFUSU9OEAYSFAoQUVVBTlRJVFlfUEVSQ0VOVBAH');

@$core.Deprecated('Use provenanceDescriptor instead')
const Provenance$json = {
  '1': 'Provenance',
  '2': [
    {'1': 'PROVENANCE_UNSPECIFIED', '2': 0},
    {'1': 'PROVENANCE_SAE', '2': 1},
    {'1': 'PROVENANCE_VERIFIED_ON_TRUCK', '2': 2},
    {'1': 'PROVENANCE_IMPORTED_UNVERIFIED', '2': 3},
    {'1': 'PROVENANCE_COMPUTED', '2': 4},
    {'1': 'PROVENANCE_AUX_SENSOR', '2': 5},
    {'1': 'PROVENANCE_BROADCAST_DECODED', '2': 6},
  ],
};

/// Descriptor for `Provenance`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List provenanceDescriptor = $convert.base64Decode(
    'CgpQcm92ZW5hbmNlEhoKFlBST1ZFTkFOQ0VfVU5TUEVDSUZJRUQQABISCg5QUk9WRU5BTkNFX1'
    'NBRRABEiAKHFBST1ZFTkFOQ0VfVkVSSUZJRURfT05fVFJVQ0sQAhIiCh5QUk9WRU5BTkNFX0lN'
    'UE9SVEVEX1VOVkVSSUZJRUQQAxIXChNQUk9WRU5BTkNFX0NPTVBVVEVEEAQSGQoVUFJPVkVOQU'
    '5DRV9BVVhfU0VOU09SEAUSIAocUFJPVkVOQU5DRV9CUk9BRENBU1RfREVDT0RFRBAG');

@$core.Deprecated('Use validityDescriptor instead')
const Validity$json = {
  '1': 'Validity',
  '2': [
    {'1': 'VALIDITY_UNSPECIFIED', '2': 0},
    {'1': 'VALIDITY_VALID', '2': 1},
    {'1': 'VALIDITY_STALE', '2': 2},
    {'1': 'VALIDITY_NO_DATA', '2': 3},
    {'1': 'VALIDITY_OUT_OF_RANGE', '2': 4},
    {'1': 'VALIDITY_DECODE_ERROR', '2': 5},
    {'1': 'VALIDITY_UNSUPPORTED', '2': 6},
    {'1': 'VALIDITY_DISABLED', '2': 7},
  ],
};

/// Descriptor for `Validity`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List validityDescriptor = $convert.base64Decode(
    'CghWYWxpZGl0eRIYChRWQUxJRElUWV9VTlNQRUNJRklFRBAAEhIKDlZBTElESVRZX1ZBTElEEA'
    'ESEgoOVkFMSURJVFlfU1RBTEUQAhIUChBWQUxJRElUWV9OT19EQVRBEAMSGQoVVkFMSURJVFlf'
    'T1VUX09GX1JBTkdFEAQSGQoVVkFMSURJVFlfREVDT0RFX0VSUk9SEAUSGAoUVkFMSURJVFlfVU'
    '5TVVBQT1JURUQQBhIVChFWQUxJRElUWV9ESVNBQkxFRBAH');

@$core.Deprecated('Use linkStateDescriptor instead')
const LinkState$json = {
  '1': 'LinkState',
  '2': [
    {'1': 'LINK_STATE_UNSPECIFIED', '2': 0},
    {'1': 'LINK_STATE_CONNECTING', '2': 1},
    {'1': 'LINK_STATE_UP', '2': 2},
    {'1': 'LINK_STATE_DEGRADED', '2': 3},
    {'1': 'LINK_STATE_DOWN', '2': 4},
  ],
};

/// Descriptor for `LinkState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List linkStateDescriptor = $convert.base64Decode(
    'CglMaW5rU3RhdGUSGgoWTElOS19TVEFURV9VTlNQRUNJRklFRBAAEhkKFUxJTktfU1RBVEVfQ0'
    '9OTkVDVElORxABEhEKDUxJTktfU1RBVEVfVVAQAhIXChNMSU5LX1NUQVRFX0RFR1JBREVEEAMS'
    'EwoPTElOS19TVEFURV9ET1dOEAQ=');

@$core.Deprecated('Use alertLevelDescriptor instead')
const AlertLevel$json = {
  '1': 'AlertLevel',
  '2': [
    {'1': 'ALERT_LEVEL_UNSPECIFIED', '2': 0},
    {'1': 'ALERT_LEVEL_ADVISORY', '2': 1},
    {'1': 'ALERT_LEVEL_CRITICAL', '2': 2},
  ],
};

/// Descriptor for `AlertLevel`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List alertLevelDescriptor = $convert.base64Decode(
    'CgpBbGVydExldmVsEhsKF0FMRVJUX0xFVkVMX1VOU1BFQ0lGSUVEEAASGAoUQUxFUlRfTEVWRU'
    'xfQURWSVNPUlkQARIYChRBTEVSVF9MRVZFTF9DUklUSUNBTBAC');

@$core.Deprecated('Use alertKindDescriptor instead')
const AlertKind$json = {
  '1': 'AlertKind',
  '2': [
    {'1': 'ALERT_KIND_UNSPECIFIED', '2': 0},
    {'1': 'ALERT_KIND_THRESHOLD', '2': 1},
    {'1': 'ALERT_KIND_SIGNAL_NOT_UPDATING', '2': 2},
    {'1': 'ALERT_KIND_LINK_LOST', '2': 3},
  ],
};

/// Descriptor for `AlertKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List alertKindDescriptor = $convert.base64Decode(
    'CglBbGVydEtpbmQSGgoWQUxFUlRfS0lORF9VTlNQRUNJRklFRBAAEhgKFEFMRVJUX0tJTkRfVE'
    'hSRVNIT0xEEAESIgoeQUxFUlRfS0lORF9TSUdOQUxfTk9UX1VQREFUSU5HEAISGAoUQUxFUlRf'
    'S0lORF9MSU5LX0xPU1QQAw==');

@$core.Deprecated('Use eventSeverityDescriptor instead')
const EventSeverity$json = {
  '1': 'EventSeverity',
  '2': [
    {'1': 'EVENT_SEVERITY_UNSPECIFIED', '2': 0},
    {'1': 'EVENT_SEVERITY_INFO', '2': 1},
    {'1': 'EVENT_SEVERITY_ADVISORY', '2': 2},
    {'1': 'EVENT_SEVERITY_CRITICAL', '2': 3},
  ],
};

/// Descriptor for `EventSeverity`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List eventSeverityDescriptor = $convert.base64Decode(
    'Cg1FdmVudFNldmVyaXR5Eh4KGkVWRU5UX1NFVkVSSVRZX1VOU1BFQ0lGSUVEEAASFwoTRVZFTl'
    'RfU0VWRVJJVFlfSU5GTxABEhsKF0VWRU5UX1NFVkVSSVRZX0FEVklTT1JZEAISGwoXRVZFTlRf'
    'U0VWRVJJVFlfQ1JJVElDQUwQAw==');

@$core.Deprecated('Use signalDefinitionDescriptor instead')
const SignalDefinition$json = {
  '1': 'SignalDefinition',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'short_name', '3': 3, '4': 1, '5': 9, '10': 'shortName'},
    {
      '1': 'quantity',
      '3': 4,
      '4': 1,
      '5': 14,
      '6': '.f250.vehicle.v1.Quantity',
      '10': 'quantity'
    },
    {'1': 'unit', '3': 5, '4': 1, '5': 9, '10': 'unit'},
    {
      '1': 'provenance',
      '3': 6,
      '4': 1,
      '5': 14,
      '6': '.f250.vehicle.v1.Provenance',
      '10': 'provenance'
    },
    {'1': 'min', '3': 7, '4': 1, '5': 1, '10': 'min'},
    {'1': 'max', '3': 8, '4': 1, '5': 1, '10': 'max'},
    {'1': 'stale_after_ms', '3': 9, '4': 1, '5': 13, '10': 'staleAfterMs'},
    {'1': 'request', '3': 10, '4': 1, '5': 9, '10': 'request'},
    {'1': 'responder', '3': 11, '4': 1, '5': 9, '10': 'responder'},
    {'1': 'evidence', '3': 12, '4': 1, '5': 9, '10': 'evidence'},
    {'1': 'enabled', '3': 13, '4': 1, '5': 8, '10': 'enabled'},
    {'1': 'disabled_reason', '3': 14, '4': 1, '5': 9, '10': 'disabledReason'},
    {'1': 'inputs', '3': 15, '4': 3, '5': 9, '10': 'inputs'},
    {
      '1': 'calibration_scale',
      '3': 16,
      '4': 1,
      '5': 1,
      '10': 'calibrationScale'
    },
    {
      '1': 'calibration_offset',
      '3': 17,
      '4': 1,
      '5': 1,
      '10': 'calibrationOffset'
    },
  ],
};

/// Descriptor for `SignalDefinition`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List signalDefinitionDescriptor = $convert.base64Decode(
    'ChBTaWduYWxEZWZpbml0aW9uEg4KAmlkGAEgASgJUgJpZBISCgRuYW1lGAIgASgJUgRuYW1lEh'
    '0KCnNob3J0X25hbWUYAyABKAlSCXNob3J0TmFtZRI1CghxdWFudGl0eRgEIAEoDjIZLmYyNTAu'
    'dmVoaWNsZS52MS5RdWFudGl0eVIIcXVhbnRpdHkSEgoEdW5pdBgFIAEoCVIEdW5pdBI7Cgpwcm'
    '92ZW5hbmNlGAYgASgOMhsuZjI1MC52ZWhpY2xlLnYxLlByb3ZlbmFuY2VSCnByb3ZlbmFuY2US'
    'EAoDbWluGAcgASgBUgNtaW4SEAoDbWF4GAggASgBUgNtYXgSJAoOc3RhbGVfYWZ0ZXJfbXMYCS'
    'ABKA1SDHN0YWxlQWZ0ZXJNcxIYCgdyZXF1ZXN0GAogASgJUgdyZXF1ZXN0EhwKCXJlc3BvbmRl'
    'chgLIAEoCVIJcmVzcG9uZGVyEhoKCGV2aWRlbmNlGAwgASgJUghldmlkZW5jZRIYCgdlbmFibG'
    'VkGA0gASgIUgdlbmFibGVkEicKD2Rpc2FibGVkX3JlYXNvbhgOIAEoCVIOZGlzYWJsZWRSZWFz'
    'b24SFgoGaW5wdXRzGA8gAygJUgZpbnB1dHMSKwoRY2FsaWJyYXRpb25fc2NhbGUYECABKAFSEG'
    'NhbGlicmF0aW9uU2NhbGUSLQoSY2FsaWJyYXRpb25fb2Zmc2V0GBEgASgBUhFjYWxpYnJhdGlv'
    'bk9mZnNldA==');

@$core.Deprecated('Use listSignalsRequestDescriptor instead')
const ListSignalsRequest$json = {
  '1': 'ListSignalsRequest',
};

/// Descriptor for `ListSignalsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listSignalsRequestDescriptor =
    $convert.base64Decode('ChJMaXN0U2lnbmFsc1JlcXVlc3Q=');

@$core.Deprecated('Use listSignalsResponseDescriptor instead')
const ListSignalsResponse$json = {
  '1': 'ListSignalsResponse',
  '2': [
    {
      '1': 'signals',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.f250.vehicle.v1.SignalDefinition',
      '10': 'signals'
    },
  ],
};

/// Descriptor for `ListSignalsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listSignalsResponseDescriptor = $convert.base64Decode(
    'ChNMaXN0U2lnbmFsc1Jlc3BvbnNlEjsKB3NpZ25hbHMYASADKAsyIS5mMjUwLnZlaGljbGUudj'
    'EuU2lnbmFsRGVmaW5pdGlvblIHc2lnbmFscw==');

@$core.Deprecated('Use sampleDescriptor instead')
const Sample$json = {
  '1': 'Sample',
  '2': [
    {'1': 'signal_id', '3': 1, '4': 1, '5': 9, '10': 'signalId'},
    {
      '1': 'validity',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.f250.vehicle.v1.Validity',
      '10': 'validity'
    },
    {'1': 'value', '3': 3, '4': 1, '5': 1, '9': 0, '10': 'value', '17': true},
    {
      '1': 'last_good_value',
      '3': 4,
      '4': 1,
      '5': 1,
      '9': 1,
      '10': 'lastGoodValue',
      '17': true
    },
    {
      '1': 'last_good_raw',
      '3': 5,
      '4': 1,
      '5': 1,
      '9': 2,
      '10': 'lastGoodRaw',
      '17': true
    },
    {
      '1': 'last_good_age_ms',
      '3': 6,
      '4': 1,
      '5': 4,
      '9': 3,
      '10': 'lastGoodAgeMs',
      '17': true
    },
    {
      '1': 'rejected_value',
      '3': 7,
      '4': 1,
      '5': 1,
      '9': 4,
      '10': 'rejectedValue',
      '17': true
    },
    {'1': 'last_nrc', '3': 8, '4': 1, '5': 13, '10': 'lastNrc'},
    {'1': 'last_responder', '3': 9, '4': 1, '5': 9, '10': 'lastResponder'},
    {'1': 'last_latency_ms', '3': 10, '4': 1, '5': 13, '10': 'lastLatencyMs'},
    {'1': 'successes', '3': 11, '4': 1, '5': 4, '10': 'successes'},
    {'1': 'failures', '3': 12, '4': 1, '5': 4, '10': 'failures'},
    {
      '1': 'consecutive_failures',
      '3': 13,
      '4': 1,
      '5': 13,
      '10': 'consecutiveFailures'
    },
    {'1': 'invalid_inputs', '3': 14, '4': 3, '5': 9, '10': 'invalidInputs'},
    {'1': 'poll_state', '3': 15, '4': 1, '5': 9, '10': 'pollState'},
  ],
  '8': [
    {'1': '_value'},
    {'1': '_last_good_value'},
    {'1': '_last_good_raw'},
    {'1': '_last_good_age_ms'},
    {'1': '_rejected_value'},
  ],
};

/// Descriptor for `Sample`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sampleDescriptor = $convert.base64Decode(
    'CgZTYW1wbGUSGwoJc2lnbmFsX2lkGAEgASgJUghzaWduYWxJZBI1Cgh2YWxpZGl0eRgCIAEoDj'
    'IZLmYyNTAudmVoaWNsZS52MS5WYWxpZGl0eVIIdmFsaWRpdHkSGQoFdmFsdWUYAyABKAFIAFIF'
    'dmFsdWWIAQESKwoPbGFzdF9nb29kX3ZhbHVlGAQgASgBSAFSDWxhc3RHb29kVmFsdWWIAQESJw'
    'oNbGFzdF9nb29kX3JhdxgFIAEoAUgCUgtsYXN0R29vZFJhd4gBARIsChBsYXN0X2dvb2RfYWdl'
    'X21zGAYgASgESANSDWxhc3RHb29kQWdlTXOIAQESKgoOcmVqZWN0ZWRfdmFsdWUYByABKAFIBF'
    'INcmVqZWN0ZWRWYWx1ZYgBARIZCghsYXN0X25yYxgIIAEoDVIHbGFzdE5yYxIlCg5sYXN0X3Jl'
    'c3BvbmRlchgJIAEoCVINbGFzdFJlc3BvbmRlchImCg9sYXN0X2xhdGVuY3lfbXMYCiABKA1SDW'
    'xhc3RMYXRlbmN5TXMSHAoJc3VjY2Vzc2VzGAsgASgEUglzdWNjZXNzZXMSGgoIZmFpbHVyZXMY'
    'DCABKARSCGZhaWx1cmVzEjEKFGNvbnNlY3V0aXZlX2ZhaWx1cmVzGA0gASgNUhNjb25zZWN1dG'
    'l2ZUZhaWx1cmVzEiUKDmludmFsaWRfaW5wdXRzGA4gAygJUg1pbnZhbGlkSW5wdXRzEh0KCnBv'
    'bGxfc3RhdGUYDyABKAlSCXBvbGxTdGF0ZUIICgZfdmFsdWVCEgoQX2xhc3RfZ29vZF92YWx1ZU'
    'IQCg5fbGFzdF9nb29kX3Jhd0ITChFfbGFzdF9nb29kX2FnZV9tc0IRCg9fcmVqZWN0ZWRfdmFs'
    'dWU=');

@$core.Deprecated('Use linkStatusDescriptor instead')
const LinkStatus$json = {
  '1': 'LinkStatus',
  '2': [
    {
      '1': 'state',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.f250.vehicle.v1.LinkState',
      '10': 'state'
    },
    {'1': 'since_mono_ms', '3': 2, '4': 1, '5': 4, '10': 'sinceMonoMs'},
    {'1': 'transport', '3': 3, '4': 1, '5': 9, '10': 'transport'},
    {'1': 'simulated', '3': 4, '4': 1, '5': 8, '10': 'simulated'},
    {'1': 'transmit_enabled', '3': 5, '4': 1, '5': 8, '10': 'transmitEnabled'},
    {
      '1': 'requests_per_second',
      '3': 6,
      '4': 1,
      '5': 1,
      '10': 'requestsPerSecond'
    },
    {'1': 'machine_state', '3': 7, '4': 1, '5': 9, '10': 'machineState'},
    {'1': 'detail', '3': 8, '4': 1, '5': 9, '10': 'detail'},
    {
      '1': 'adapter_voltage',
      '3': 9,
      '4': 1,
      '5': 1,
      '9': 0,
      '10': 'adapterVoltage',
      '17': true
    },
    {'1': 'scenario', '3': 10, '4': 1, '5': 9, '10': 'scenario'},
    {'1': 'scenario_seconds', '3': 11, '4': 1, '5': 1, '10': 'scenarioSeconds'},
  ],
  '8': [
    {'1': '_adapter_voltage'},
  ],
};

/// Descriptor for `LinkStatus`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List linkStatusDescriptor = $convert.base64Decode(
    'CgpMaW5rU3RhdHVzEjAKBXN0YXRlGAEgASgOMhouZjI1MC52ZWhpY2xlLnYxLkxpbmtTdGF0ZV'
    'IFc3RhdGUSIgoNc2luY2VfbW9ub19tcxgCIAEoBFILc2luY2VNb25vTXMSHAoJdHJhbnNwb3J0'
    'GAMgASgJUgl0cmFuc3BvcnQSHAoJc2ltdWxhdGVkGAQgASgIUglzaW11bGF0ZWQSKQoQdHJhbn'
    'NtaXRfZW5hYmxlZBgFIAEoCFIPdHJhbnNtaXRFbmFibGVkEi4KE3JlcXVlc3RzX3Blcl9zZWNv'
    'bmQYBiABKAFSEXJlcXVlc3RzUGVyU2Vjb25kEiMKDW1hY2hpbmVfc3RhdGUYByABKAlSDG1hY2'
    'hpbmVTdGF0ZRIWCgZkZXRhaWwYCCABKAlSBmRldGFpbBIsCg9hZGFwdGVyX3ZvbHRhZ2UYCSAB'
    'KAFIAFIOYWRhcHRlclZvbHRhZ2WIAQESGgoIc2NlbmFyaW8YCiABKAlSCHNjZW5hcmlvEikKEH'
    'NjZW5hcmlvX3NlY29uZHMYCyABKAFSD3NjZW5hcmlvU2Vjb25kc0ISChBfYWRhcHRlcl92b2x0'
    'YWdl');

@$core.Deprecated('Use alertDescriptor instead')
const Alert$json = {
  '1': 'Alert',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {
      '1': 'kind',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.f250.vehicle.v1.AlertKind',
      '10': 'kind'
    },
    {
      '1': 'level',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.f250.vehicle.v1.AlertLevel',
      '10': 'level'
    },
    {'1': 'since_mono_ms', '3': 4, '4': 1, '5': 4, '10': 'sinceMonoMs'},
    {'1': 'signal_id', '3': 5, '4': 1, '5': 9, '10': 'signalId'},
    {'1': 'rule_id', '3': 6, '4': 1, '5': 9, '10': 'ruleId'},
    {'1': 'threshold', '3': 7, '4': 1, '5': 1, '10': 'threshold'},
    {'1': 'above', '3': 8, '4': 1, '5': 8, '10': 'above'},
  ],
};

/// Descriptor for `Alert`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List alertDescriptor = $convert.base64Decode(
    'CgVBbGVydBIOCgJpZBgBIAEoCVICaWQSLgoEa2luZBgCIAEoDjIaLmYyNTAudmVoaWNsZS52MS'
    '5BbGVydEtpbmRSBGtpbmQSMQoFbGV2ZWwYAyABKA4yGy5mMjUwLnZlaGljbGUudjEuQWxlcnRM'
    'ZXZlbFIFbGV2ZWwSIgoNc2luY2VfbW9ub19tcxgEIAEoBFILc2luY2VNb25vTXMSGwoJc2lnbm'
    'FsX2lkGAUgASgJUghzaWduYWxJZBIXCgdydWxlX2lkGAYgASgJUgZydWxlSWQSHAoJdGhyZXNo'
    'b2xkGAcgASgBUgl0aHJlc2hvbGQSFAoFYWJvdmUYCCABKAhSBWFib3Zl');

@$core.Deprecated('Use snapshotDescriptor instead')
const Snapshot$json = {
  '1': 'Snapshot',
  '2': [
    {'1': 'mono_ms', '3': 1, '4': 1, '5': 4, '10': 'monoMs'},
    {
      '1': 'samples',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.f250.vehicle.v1.Sample',
      '10': 'samples'
    },
    {
      '1': 'link',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.f250.vehicle.v1.LinkStatus',
      '10': 'link'
    },
    {
      '1': 'alerts',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.f250.vehicle.v1.Alert',
      '10': 'alerts'
    },
  ],
};

/// Descriptor for `Snapshot`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List snapshotDescriptor = $convert.base64Decode(
    'CghTbmFwc2hvdBIXCgdtb25vX21zGAEgASgEUgZtb25vTXMSMQoHc2FtcGxlcxgCIAMoCzIXLm'
    'YyNTAudmVoaWNsZS52MS5TYW1wbGVSB3NhbXBsZXMSLwoEbGluaxgDIAEoCzIbLmYyNTAudmVo'
    'aWNsZS52MS5MaW5rU3RhdHVzUgRsaW5rEi4KBmFsZXJ0cxgEIAMoCzIWLmYyNTAudmVoaWNsZS'
    '52MS5BbGVydFIGYWxlcnRz');

@$core.Deprecated('Use streamSnapshotsRequestDescriptor instead')
const StreamSnapshotsRequest$json = {
  '1': 'StreamSnapshotsRequest',
  '2': [
    {'1': 'period_ms', '3': 1, '4': 1, '5': 13, '10': 'periodMs'},
  ],
};

/// Descriptor for `StreamSnapshotsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List streamSnapshotsRequestDescriptor =
    $convert.base64Decode(
        'ChZTdHJlYW1TbmFwc2hvdHNSZXF1ZXN0EhsKCXBlcmlvZF9tcxgBIAEoDVIIcGVyaW9kTXM=');

@$core.Deprecated('Use streamSnapshotsResponseDescriptor instead')
const StreamSnapshotsResponse$json = {
  '1': 'StreamSnapshotsResponse',
  '2': [
    {
      '1': 'snapshot',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.vehicle.v1.Snapshot',
      '10': 'snapshot'
    },
  ],
};

/// Descriptor for `StreamSnapshotsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List streamSnapshotsResponseDescriptor =
    $convert.base64Decode(
        'ChdTdHJlYW1TbmFwc2hvdHNSZXNwb25zZRI1CghzbmFwc2hvdBgBIAEoCzIZLmYyNTAudmVoaW'
        'NsZS52MS5TbmFwc2hvdFIIc25hcHNob3Q=');

@$core.Deprecated('Use eventDescriptor instead')
const Event$json = {
  '1': 'Event',
  '2': [
    {'1': 'mono_ms', '3': 1, '4': 1, '5': 4, '10': 'monoMs'},
    {'1': 'wall_ms', '3': 2, '4': 1, '5': 3, '10': 'wallMs'},
    {
      '1': 'severity',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.f250.vehicle.v1.EventSeverity',
      '10': 'severity'
    },
    {'1': 'message', '3': 4, '4': 1, '5': 9, '10': 'message'},
  ],
};

/// Descriptor for `Event`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List eventDescriptor = $convert.base64Decode(
    'CgVFdmVudBIXCgdtb25vX21zGAEgASgEUgZtb25vTXMSFwoHd2FsbF9tcxgCIAEoA1IGd2FsbE'
    '1zEjoKCHNldmVyaXR5GAMgASgOMh4uZjI1MC52ZWhpY2xlLnYxLkV2ZW50U2V2ZXJpdHlSCHNl'
    'dmVyaXR5EhgKB21lc3NhZ2UYBCABKAlSB21lc3NhZ2U=');

@$core.Deprecated('Use listEventsRequestDescriptor instead')
const ListEventsRequest$json = {
  '1': 'ListEventsRequest',
  '2': [
    {'1': 'limit', '3': 1, '4': 1, '5': 13, '10': 'limit'},
  ],
};

/// Descriptor for `ListEventsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listEventsRequestDescriptor = $convert
    .base64Decode('ChFMaXN0RXZlbnRzUmVxdWVzdBIUCgVsaW1pdBgBIAEoDVIFbGltaXQ=');

@$core.Deprecated('Use listEventsResponseDescriptor instead')
const ListEventsResponse$json = {
  '1': 'ListEventsResponse',
  '2': [
    {
      '1': 'events',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.f250.vehicle.v1.Event',
      '10': 'events'
    },
    {'1': 'dropped', '3': 2, '4': 1, '5': 4, '10': 'dropped'},
  ],
};

/// Descriptor for `ListEventsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listEventsResponseDescriptor = $convert.base64Decode(
    'ChJMaXN0RXZlbnRzUmVzcG9uc2USLgoGZXZlbnRzGAEgAygLMhYuZjI1MC52ZWhpY2xlLnYxLk'
    'V2ZW50UgZldmVudHMSGAoHZHJvcHBlZBgCIAEoBFIHZHJvcHBlZA==');

@$core.Deprecated('Use setCalibrationRequestDescriptor instead')
const SetCalibrationRequest$json = {
  '1': 'SetCalibrationRequest',
  '2': [
    {'1': 'signal_id', '3': 1, '4': 1, '5': 9, '10': 'signalId'},
    {'1': 'scale', '3': 2, '4': 1, '5': 1, '10': 'scale'},
    {'1': 'offset', '3': 3, '4': 1, '5': 1, '10': 'offset'},
  ],
};

/// Descriptor for `SetCalibrationRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setCalibrationRequestDescriptor = $convert.base64Decode(
    'ChVTZXRDYWxpYnJhdGlvblJlcXVlc3QSGwoJc2lnbmFsX2lkGAEgASgJUghzaWduYWxJZBIUCg'
    'VzY2FsZRgCIAEoAVIFc2NhbGUSFgoGb2Zmc2V0GAMgASgBUgZvZmZzZXQ=');

@$core.Deprecated('Use setCalibrationResponseDescriptor instead')
const SetCalibrationResponse$json = {
  '1': 'SetCalibrationResponse',
  '2': [
    {
      '1': 'signal',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.f250.vehicle.v1.SignalDefinition',
      '10': 'signal'
    },
  ],
};

/// Descriptor for `SetCalibrationResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setCalibrationResponseDescriptor =
    $convert.base64Decode(
        'ChZTZXRDYWxpYnJhdGlvblJlc3BvbnNlEjkKBnNpZ25hbBgBIAEoCzIhLmYyNTAudmVoaWNsZS'
        '52MS5TaWduYWxEZWZpbml0aW9uUgZzaWduYWw=');
