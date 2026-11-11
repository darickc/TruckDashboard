import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';

import '../data/gateway_connection.dart';
import '../gen/f250/camera/v1/camera.pbgrpc.dart' as pb;
import 'camera_settings.dart';
import 'camera_state.dart';

CameraSource createGrpcCameraSource(GatewayEndpoint endpoint) =>
    GrpcCameraSource(endpoint: endpoint);

/// camera-manager's view over gRPC (`WatchView`), its recording state
/// (`WatchRecording`), moves (`Move`) and "save clip" (`SaveClip`).
/// Reconnects on its own. While there is no stream, the status says so and
/// carries no view and no recording: the dashboard never claims a camera or
/// a recording it can't confirm. Either stream failing drops both and
/// reconnects; a camera-manager that doesn't serve `WatchRecording`
/// (UNIMPLEMENTED, an older build) keeps the view, with no recording.
class GrpcCameraSource implements CameraSource {
  GrpcCameraSource({
    required this.endpoint,
    this.retryDelay = const Duration(seconds: 1),
    this.callTimeout = const Duration(seconds: 2),
  });

  final GatewayEndpoint endpoint;
  final Duration retryDelay;
  final Duration callTimeout;

  ClientChannel? _channel;
  pb.CameraServiceClient? _client;
  StreamSubscription<pb.WatchViewResponse>? _stream;
  StreamSubscription<pb.WatchRecordingResponse>? _recStream;
  CameraView? _view;
  RecordingStatus? _recording;
  Timer? _retry;
  bool _running = false;

  final _status = ValueNotifier(const CameraStatus(link: CameraLink.connecting));

  @override
  ValueListenable<CameraStatus> get status => _status;

  @override
  void start() {
    if (_running) return;
    _running = true;
    final (host, port) = switch (endpoint) {
      UnixEndpoint(:final path) => (InternetAddress(path, type: InternetAddressType.unix), 0),
      TcpEndpoint(:final host, :final port) => (host as Object, port),
    };
    _channel = ClientChannel(host,
        port: port, options: const ChannelOptions(credentials: ChannelCredentials.insecure()));
    _client = pb.CameraServiceClient(_channel!);
    _status.value = CameraStatus(link: CameraLink.connecting, detail: 'connecting to $endpoint');
    _connect();
  }

  @override
  void stop() {
    _running = false;
    _retry?.cancel();
    _stream?.cancel();
    _recStream?.cancel();
    _channel?.shutdown();
    _stream = null;
    _recStream = null;
    _channel = null;
    _client = null;
  }

  @override
  Future<CameraView> move(SwitchMove move) async {
    final client = _client;
    if (client == null) throw StateError('camera-manager not connected');
    final r = await client.move(
        pb.MoveRequest(move: switchMoveToPb(move), source: 'dashboard'),
        options: CallOptions(timeout: callTimeout));
    return viewFromPb(r.view);
  }

  @override
  Future<CameraSettingsSnapshot> getSettings() async {
    final client = _client;
    if (client == null) throw StateError('camera-manager not connected');
    final r = await client.getCameraSettings(pb.GetCameraSettingsRequest(),
        options: CallOptions(timeout: callTimeout));
    return CameraSettingsSnapshot(
      settings: cameraSettingsFromPb(r.settings),
      plugged: [for (final d in r.devices) CameraDevice(path: d.path, label: d.label)],
    );
  }

  @override
  Future<ApplyResult> setSettings(CameraSettings? settings) async {
    final client = _client;
    if (client == null) throw StateError('camera-manager not connected');
    final r = await client.setCameraSettings(cameraSettingsToPb(settings),
        options: CallOptions(timeout: callTimeout));
    return ApplyResult(applied: r.applied, detail: r.detail);
  }

  @override
  Future<SaveClipResult> saveClip() async {
    final client = _client;
    if (client == null) throw StateError('camera-manager not connected');
    final r = await client.saveClip(pb.SaveClipRequest(source: 'dashboard'),
        options: CallOptions(timeout: callTimeout));
    return saveClipFromPb(r);
  }

  void _connect() {
    final client = _client;
    if (!_running || client == null) return;
    _view = null;
    _recording = null;
    _stream = client.watchView(pb.WatchViewRequest()).listen(
      (r) {
        _view = viewFromPb(r.view);
        _publish();
      },
      onError: (Object e) => _down(e is GrpcError ? (e.message ?? e.codeName) : '$e'),
      onDone: () => _down('camera-manager ended the stream'),
    );
    _recStream = client.watchRecording(pb.WatchRecordingRequest()).listen(
      (r) {
        _recording = recordingFromPb(r.recording);
        _publish();
      },
      onError: (Object e) {
        if (e is GrpcError && e.code == StatusCode.unimplemented) {
          // An older camera-manager: no recording to report, the view stands.
          _recStream = null;
          _recording = null;
          _publish();
          return;
        }
        _down(e is GrpcError ? (e.message ?? e.codeName) : '$e');
      },
      onDone: () {
        if (_recStream != null) _down('camera-manager ended the recording stream');
      },
    );
  }

  /// Up only once the view has arrived; the recording rides along.
  void _publish() {
    final view = _view;
    if (view == null) return;
    _status.value = CameraStatus(link: CameraLink.up, view: view, recording: _recording);
  }

  void _down(String why) {
    _stream?.cancel();
    _stream = null;
    _recStream?.cancel();
    _recStream = null;
    _view = null;
    _recording = null;
    if (!_running) return;
    _status.value = CameraStatus(link: CameraLink.down, detail: why);
    _retry?.cancel();
    _retry = Timer(retryDelay, _connect);
  }
}

pb.SwitchMove switchMoveToPb(SwitchMove m) => switch (m) {
      SwitchMove.left => pb.SwitchMove.SWITCH_MOVE_LEFT,
      SwitchMove.right => pb.SwitchMove.SWITCH_MOVE_RIGHT,
      SwitchMove.back => pb.SwitchMove.SWITCH_MOVE_BACK,
      SwitchMove.forward => pb.SwitchMove.SWITCH_MOVE_FORWARD,
      SwitchMove.press => pb.SwitchMove.SWITCH_MOVE_PRESS,
    };

/// camera-manager's view as the dashboard's model. Unknown enum values (a
/// newer camera-manager) read as "no camera" rather than a guess.
CameraView viewFromPb(pb.View v) {
  final camera = _cameraFromPb(v.camera);
  return CameraView(
    camera: camera,
    reason: camera == null
        ? null
        : switch (v.reason) {
            pb.Reason.REASON_REVERSE => CameraReason.reverse,
            pb.Reason.REASON_SWITCH => CameraReason.cameraSwitch,
            _ => null,
          },
    feed: camera == null
        ? null
        : switch (v.feed) {
            pb.FeedState.FEED_STATE_LIVE => FeedState.live,
            pb.FeedState.FEED_STATE_UNAVAILABLE => FeedState.unavailable,
            _ => FeedState.starting,
          },
    feedDetail: v.feedDetail,
    reverse: switch (v.reverse) {
      pb.ReverseStatus.REVERSE_STATUS_UNKNOWN => ReverseStatus.unknown,
      pb.ReverseStatus.REVERSE_STATUS_NOT_ENGAGED => ReverseStatus.notEngaged,
      pb.ReverseStatus.REVERSE_STATUS_ENGAGED => ReverseStatus.engaged,
      _ => ReverseStatus.off,
    },
    blockedBySpeed: v.blockedBySpeed,
  );
}

RecordingState _stateFromPb(pb.RecordingState s) => switch (s) {
      pb.RecordingState.RECORDING_STATE_STARTING => RecordingState.starting,
      pb.RecordingState.RECORDING_STATE_RECORDING => RecordingState.recording,
      // NOT_RECORDING, unspecified and anything newer: never claimed as
      // recording.
      _ => RecordingState.notRecording,
    };

CameraId? _cameraFromPb(pb.Camera c) => switch (c) {
      pb.Camera.CAMERA_LEFT => CameraId.left,
      pb.Camera.CAMERA_RIGHT => CameraId.right,
      pb.Camera.CAMERA_REAR => CameraId.rear,
      pb.Camera.CAMERA_FRONT => CameraId.front,
      _ => null,
    };

/// camera-manager's recording state as the dashboard's model. An unknown
/// state reads as not recording (with a detail saying so if there is none).
RecordingStatus recordingFromPb(pb.Recording r) => RecordingStatus(
      cameras: [
        for (final c in r.cameras)
          CameraRecording(
            camera: _cameraFromPb(c.camera),
            state: _stateFromPb(c.state),
            detail: c.detail.isEmpty &&
                    c.state != pb.RecordingState.RECORDING_STATE_RECORDING &&
                    c.state != pb.RecordingState.RECORDING_STATE_STARTING &&
                    c.state != pb.RecordingState.RECORDING_STATE_NOT_RECORDING
                ? 'unknown recording state'
                : c.detail,
            segment: c.segment,
          ),
      ],
      driveMounted: r.driveMounted,
      driveFreeBytes: r.driveFreeBytes.toInt(),
      recordedBytes: r.recordedBytes.toInt(),
      protectedBytes: r.protectedBytes.toInt(),
      protectedMaxBytes: r.protectedMaxBytes.toInt(),
      clipSegmentsPending: r.clipSegmentsPending,
      clockTrusted: r.clockTrusted,
      problem: r.problem,
    );

SaveClipResult saveClipFromPb(pb.SaveClipResponse r) => SaveClipResult(
      saved: r.saved,
      detail: r.detail,
      segmentsProtected: r.segmentsProtected,
      segmentsToCome: r.segmentsToCome,
    );

pb.Camera cameraToPb(CameraId c) => switch (c) {
      CameraId.front => pb.Camera.CAMERA_FRONT,
      CameraId.left => pb.Camera.CAMERA_LEFT,
      CameraId.right => pb.Camera.CAMERA_RIGHT,
      CameraId.rear => pb.Camera.CAMERA_REAR,
    };

/// camera-manager's settings as the dashboard's model. A camera this
/// dashboard doesn't know is left out.
CameraSettings cameraSettingsFromPb(pb.CameraSettings s) => CameraSettings(
      devices: {
        for (final a in s.cameras.where((a) => a.device.isNotEmpty))
          ?_cameraFromPb(a.camera): a.device,
      },
      record: {for (final c in s.record) ?_cameraFromPb(c)},
      source: s.source == pb.SettingsSource.SETTINGS_SOURCE_SCREEN
          ? SettingsSource.screen
          : SettingsSource.defaults,
      recordingUnavailable: s.recordingUnavailable,
    );

/// The request: all four cameras (one without a device is sent empty), or
/// "use /etc/default/f250" for `null`.
pb.SetCameraSettingsRequest cameraSettingsToPb(CameraSettings? s) => s == null
    ? pb.SetCameraSettingsRequest(useDefaults: true, source: 'dashboard')
    : pb.SetCameraSettingsRequest(
        cameras: [
          for (final c in CameraId.values)
            pb.CameraAssignment(camera: cameraToPb(c), device: s.devices[c] ?? ''),
        ],
        record: [for (final c in CameraId.values) if (s.record.contains(c)) cameraToPb(c)],
        source: 'dashboard',
      );
