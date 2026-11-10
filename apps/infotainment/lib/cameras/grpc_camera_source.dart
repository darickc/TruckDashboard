import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';

import '../data/gateway_connection.dart';
import '../gen/f250/camera/v1/camera.pbgrpc.dart' as pb;
import 'camera_state.dart';

CameraSource createGrpcCameraSource(GatewayEndpoint endpoint) =>
    GrpcCameraSource(endpoint: endpoint);

/// camera-manager's view over gRPC (`WatchView`), and moves (`Move`).
/// Reconnects on its own. While there is no stream, the status says so and
/// carries no view: the dashboard never claims a camera it can't confirm.
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
    _channel?.shutdown();
    _stream = null;
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

  void _connect() {
    final client = _client;
    if (!_running || client == null) return;
    _stream = client.watchView(pb.WatchViewRequest()).listen(
      (r) => _status.value = CameraStatus(link: CameraLink.up, view: viewFromPb(r.view)),
      onError: (Object e) => _down(e is GrpcError ? (e.message ?? e.codeName) : '$e'),
      onDone: () => _down('camera-manager ended the stream'),
    );
  }

  void _down(String why) {
    _stream?.cancel();
    _stream = null;
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
  final camera = switch (v.camera) {
    pb.Camera.CAMERA_LEFT => CameraId.left,
    pb.Camera.CAMERA_RIGHT => CameraId.right,
    pb.Camera.CAMERA_REAR => CameraId.rear,
    _ => null,
  };
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
