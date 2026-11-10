import 'dart:async';
import 'dart:io';

import 'package:f250_infotainment/cameras/camera_state.dart';
import 'package:f250_infotainment/cameras/grpc_camera_source.dart';
import 'package:f250_infotainment/cameras/simulated_camera_source.dart';
import 'package:f250_infotainment/data/gateway_connection.dart';
import 'package:f250_infotainment/gen/f250/camera/v1/camera.pbgrpc.dart' as pb;
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart' as grpc;

/// A stand-in camera-manager: streams the views the test pushes and records
/// moves.
class FakeCameraManager extends pb.CameraServiceBase {
  var views = StreamController<pb.WatchViewResponse>.broadcast();
  final moves = <(pb.SwitchMove, String)>[];
  pb.View current = pb.View();

  void show(pb.View v) {
    current = v;
    views.add(pb.WatchViewResponse(view: v));
  }

  @override
  Stream<pb.WatchViewResponse> watchView(grpc.ServiceCall call, pb.WatchViewRequest request) async* {
    yield pb.WatchViewResponse(view: current);
    yield* views.stream;
  }

  @override
  Future<pb.MoveResponse> move(grpc.ServiceCall call, pb.MoveRequest request) async {
    moves.add((request.move, request.source));
    if (request.move == pb.SwitchMove.SWITCH_MOVE_BACK) {
      show(pb.View(
          camera: pb.Camera.CAMERA_REAR,
          reason: pb.Reason.REASON_SWITCH,
          feed: pb.FeedState.FEED_STATE_STARTING));
    }
    return pb.MoveResponse(view: current);
  }
}

Future<grpc.Server> serve(FakeCameraManager fake, String path) async {
  final server = grpc.Server.create(services: [fake]);
  await server.serve(address: InternetAddress(path, type: InternetAddressType.unix), port: 0);
  return server;
}

Future<CameraStatus> until(GrpcCameraSource src, bool Function(CameraStatus) pred) async {
  if (pred(src.status.value)) return src.status.value;
  final done = Completer<CameraStatus>();
  void check() {
    if (!done.isCompleted && pred(src.status.value)) done.complete(src.status.value);
  }

  src.status.addListener(check);
  try {
    return await done.future.timeout(const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('last status ${src.status.value}'));
  } finally {
    src.status.removeListener(check);
  }
}

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('f250-cam');
    path = '${dir.path}/c.sock';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('views arrive, moves are sent, and the link follows camera-manager', () async {
    final fake = FakeCameraManager();
    final server = await serve(fake, path);
    final src = GrpcCameraSource(
        endpoint: UnixEndpoint(path), retryDelay: const Duration(milliseconds: 100))
      ..start();

    var s = await until(src, (s) => s.link == CameraLink.up);
    expect(s.camera, isNull);
    expect(s.simulated, isFalse);

    final view = await src.move(SwitchMove.back);
    expect(view.camera, CameraId.rear);
    expect(fake.moves.single, (pb.SwitchMove.SWITCH_MOVE_BACK, 'dashboard'));
    s = await until(src, (s) => s.camera == CameraId.rear);
    expect(s.view!.feed, FeedState.starting);

    fake.show(pb.View(
        camera: pb.Camera.CAMERA_REAR,
        reason: pb.Reason.REASON_SWITCH,
        feed: pb.FeedState.FEED_STATE_UNAVAILABLE,
        feedDetail: 'no frame for 1000 ms'));
    s = await until(src, (s) => s.view?.feed == FeedState.unavailable);
    expect(s.view!.feedDetail, 'no frame for 1000 ms');

    // The stream fails (camera-manager stopping): no view is claimed.
    fake.views.addError(grpc.GrpcError.unavailable('camera-manager stopping'));
    s = await until(src, (s) => s.link == CameraLink.down);
    expect(s.camera, isNull);
    expect(s.detail, 'camera-manager stopping');

    // The source reconnects on its own and reads the view again.
    fake.current = pb.View();
    s = await until(src, (s) => s.link == CameraLink.up);
    expect(s.camera, isNull);

    // The client goes first, or the Dart server's graceful shutdown waits on
    // its connection.
    src.stop();
    await fake.views.close();
    await server.shutdown().timeout(const Duration(seconds: 5));
  });

  test('a move without camera-manager fails, it never hangs', () async {
    final src = GrpcCameraSource(endpoint: UnixEndpoint(path), callTimeout: const Duration(seconds: 1))
      ..start();
    addTearDown(src.stop);
    await until(src, (s) => s.link == CameraLink.down);
    await expectLater(src.move(SwitchMove.left), throwsA(anything));
  });

  test('views map from the API, unknown values read as no camera', () {
    expect(viewFromPb(pb.View()), CameraView.none);
    expect(
        viewFromPb(pb.View(
            camera: pb.Camera.CAMERA_LEFT,
            reason: pb.Reason.REASON_REVERSE,
            feed: pb.FeedState.FEED_STATE_LIVE,
            reverse: pb.ReverseStatus.REVERSE_STATUS_ENGAGED,
            blockedBySpeed: true)),
        const CameraView(
            camera: CameraId.left,
            reason: CameraReason.reverse,
            feed: FeedState.live,
            reverse: ReverseStatus.engaged,
            blockedBySpeed: true));
    expect(viewFromPb(pb.View(camera: pb.Camera.CAMERA_FRONT)).camera, CameraId.front);
    // A camera with no feed state yet reads as starting, never live.
    expect(viewFromPb(pb.View(camera: pb.Camera.CAMERA_RIGHT)).feed, FeedState.starting);
    for (final m in SwitchMove.values) {
      expect(switchMoveToPb(m).name, 'SWITCH_MOVE_${m.name.toUpperCase()}');
    }
  });

  test('the simulation follows camera-manager\'s default switch mapping', () async {
    final sim = SimulatedCameraSource(startDelay: const Duration(milliseconds: 20));
    for (final (move, camera) in [
      (SwitchMove.left, CameraId.left),
      (SwitchMove.right, CameraId.right),
      (SwitchMove.back, CameraId.rear),
      (SwitchMove.forward, CameraId.front),
      (SwitchMove.press, null),
    ]) {
      final v = await sim.move(move);
      expect(v.camera, camera, reason: '$move');
      expect(sim.status.value.simulated, isTrue);
    }
    await sim.move(SwitchMove.back);
    expect(sim.status.value.view!.feed, FeedState.starting);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(sim.status.value.view!.feed, FeedState.live);
    sim.setMissing(CameraId.rear, true);
    expect(sim.status.value.view!.feed, FeedState.unavailable);
    sim.stop();
  });
}
