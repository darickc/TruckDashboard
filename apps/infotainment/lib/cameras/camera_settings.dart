import 'package:flutter/foundation.dart';

import 'camera_state.dart';

/// Camera assignment and recording, as camera-manager keeps them
/// (f250.camera.v1 GetCameraSettings / SetCameraSettings, ADR-0029). The
/// dashboard only shows and sends them: camera-manager checks, saves and
/// applies them by restarting itself.

/// A video device plugged in now.
@immutable
class CameraDevice {
  const CameraDevice({required this.path, this.label = ''});

  /// `/dev/v4l/by-path/...-video-index0`: names the USB port.
  final String path;

  /// The camera's model from `/dev/v4l/by-id`, or empty.
  final String label;

  /// The USB port, from the by-path name: `usb-0:1.2:1.0` → `USB 1.2`.
  String get port {
    final m = RegExp(r'usb-\d+:([\d.]+):').firstMatch(path);
    return m == null ? path.split('/').last : 'USB ${m.group(1)}';
  }

  @override
  bool operator ==(Object other) => other is CameraDevice && other.path == path && other.label == label;

  @override
  int get hashCode => Object.hash(path, label);
}

/// Where the settings in use came from.
enum SettingsSource { defaults, screen }

@immutable
class CameraSettings {
  const CameraSettings({
    this.devices = const {},
    this.record = const {},
    this.source = SettingsSource.defaults,
    this.recordingUnavailable = '',
  });

  /// Each camera's device; a camera missing from the map has none.
  final Map<CameraId, String> devices;

  /// The cameras to record: front and/or rear.
  final Set<CameraId> record;
  final SettingsSource source;

  /// Why nothing can record (no data drive configured, a build that can't
  /// record); empty when recording can happen.
  final String recordingUnavailable;

  bool get canRecord => recordingUnavailable.isEmpty;

  CameraSettings withDevice(CameraId c, String? device) {
    final d = {...devices};
    if (device == null) {
      d.remove(c);
    } else {
      // A device is one camera's: take it from any other.
      d.removeWhere((_, v) => v == device);
      d[c] = device;
    }
    return CameraSettings(
        devices: d, record: record, source: source, recordingUnavailable: recordingUnavailable);
  }

  CameraSettings withRecord(CameraId c, bool on) => CameraSettings(
      devices: devices,
      record: on ? {...record, c} : ({...record}..remove(c)),
      source: source,
      recordingUnavailable: recordingUnavailable);

  /// The same assignment and recording (what Apply would change).
  bool sameChoices(CameraSettings o) =>
      mapEquals(devices, o.devices) && setEquals(record, o.record);

  @override
  bool operator ==(Object other) =>
      other is CameraSettings &&
      sameChoices(other) &&
      other.source == source &&
      other.recordingUnavailable == recordingUnavailable;

  @override
  int get hashCode => Object.hash(Object.hashAllUnordered(devices.entries.map((e) => '${e.key}=${e.value}')),
      Object.hashAllUnordered(record), source, recordingUnavailable);
}

/// The settings and the cameras plugged in, as read together.
@immutable
class CameraSettingsSnapshot {
  const CameraSettingsSnapshot({required this.settings, this.plugged = const []});

  final CameraSettings settings;
  final List<CameraDevice> plugged;
}

/// What SetCameraSettings did.
@immutable
class ApplyResult {
  const ApplyResult({required this.applied, this.detail = ''});

  /// True: saved, and camera-manager is restarting to apply them.
  final bool applied;
  final String detail;
}

/// The cameras that can record (ADR-0027 decision 1).
const recordable = [CameraId.front, CameraId.rear];
