import 'dart:async';
import 'dart:io';

import 'package:f250_infotainment/cameras/camera_state.dart';
import 'package:f250_infotainment/cameras/grpc_camera_source.dart';
import 'package:f250_infotainment/cameras/simulated_camera_source.dart';
import 'package:f250_infotainment/data/gateway_connection.dart';
import 'package:f250_infotainment/gen/f250/camera/v1/camera.pbgrpc.dart' as pb;
import 'package:flutter_test/flutter_test.dart';
import 'package:fixnum/fixnum.dart';
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

  var recordings = StreamController<pb.WatchRecordingResponse>.broadcast();
  pb.Recording recordingNow = pb.Recording();
  final saveSources = <String>[];
  pb.SaveClipResponse saveAnswer = pb.SaveClipResponse(saved: true, segmentsProtected: 2, segmentsToCome: 4);

  /// A camera-manager from before WatchRecording.
  bool recordingUnimplemented = false;

  void record(pb.Recording r) {
    recordingNow = r;
    recordings.add(pb.WatchRecordingResponse(recording: r));
  }

  @override
  Stream<pb.WatchRecordingResponse> watchRecording(
      grpc.ServiceCall call, pb.WatchRecordingRequest request) async* {
    if (recordingUnimplemented) throw const grpc.GrpcError.unimplemented('no WatchRecording');
    yield pb.WatchRecordingResponse(recording: recordingNow);
    yield* recordings.stream;
  }

  @override
  Future<pb.SaveClipResponse> saveClip(grpc.ServiceCall call, pb.SaveClipRequest request) async {
    saveSources.add(request.source);
    return saveAnswer;
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
    await fake.recordings.close();
    await server.shutdown().timeout(const Duration(seconds: 5));
  });

  test('recording arrives with the view, save clip is sent, and a lost link drops both', () async {
    final fake = FakeCameraManager()
      ..recordingNow = pb.Recording(
          cameras: [
            pb.CameraRecording(
                camera: pb.Camera.CAMERA_FRONT,
                state: pb.RecordingState.RECORDING_STATE_RECORDING,
                segment: 'b00007-s000003.mkv'),
            pb.CameraRecording(
                camera: pb.Camera.CAMERA_REAR,
                state: pb.RecordingState.RECORDING_STATE_NOT_RECORDING,
                detail: 'no frames'),
          ],
          driveMounted: true,
          driveFreeBytes: Int64(300000000000),
          protectedMaxBytes: Int64(25000000000),
          clockTrusted: true);
    final server = await serve(fake, path);
    final src = GrpcCameraSource(
        endpoint: UnixEndpoint(path), retryDelay: const Duration(milliseconds: 100))
      ..start();

    var s = await until(src, (s) => s.recording != null);
    expect(s.link, CameraLink.up);
    final r = s.recording!;
    expect(r.records(CameraId.front), isTrue);
    expect(r.records(CameraId.rear), isFalse);
    expect(r.cameras.last,
        const CameraRecording(camera: CameraId.rear, state: RecordingState.notRecording, detail: 'no frames'));
    expect(r.driveFreeBytes, 300000000000);

    final saved = await src.saveClip();
    expect(saved.saved, isTrue);
    expect(saved.segmentsToCome, 4);
    expect(fake.saveSources.single, 'dashboard');
    fake.saveAnswer = pb.SaveClipResponse(saved: false, detail: 'saved clips are full');
    expect((await src.saveClip()).detail, 'saved clips are full');

    fake.record(pb.Recording());
    s = await until(src, (s) => s.recording?.isOff ?? false);

    // The recording stream failing drops the link: nothing is claimed.
    fake.recordings.addError(const grpc.GrpcError.unavailable('stopping'));
    s = await until(src, (s) => s.link == CameraLink.down);
    expect(s.recording, isNull);
    s = await until(src, (s) => s.link == CameraLink.up && s.recording != null);

    src.stop();
    await fake.views.close();
    await fake.recordings.close();
    await server.shutdown().timeout(const Duration(seconds: 5));
  });

  test('a camera-manager without WatchRecording keeps the view, with no recording', () async {
    final fake = FakeCameraManager()..recordingUnimplemented = true;
    final server = await serve(fake, path);
    final src = GrpcCameraSource(
        endpoint: UnixEndpoint(path), retryDelay: const Duration(milliseconds: 100))
      ..start();
    final s = await until(src, (s) => s.link == CameraLink.up);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(src.status.value.link, CameraLink.up);
    expect(s.recording, isNull);
    src.stop();
    await fake.views.close();
    await fake.recordings.close();
    await server.shutdown().timeout(const Duration(seconds: 5));
  });

  test('recording maps from the API; unknown states are never recording', () {
    expect(recordingFromPb(pb.Recording()), RecordingStatus.off);
    final r = recordingFromPb(pb.Recording(cameras: [
      pb.CameraRecording(camera: pb.Camera.CAMERA_FRONT, state: pb.RecordingState.RECORDING_STATE_STARTING),
      pb.CameraRecording(camera: pb.Camera.CAMERA_REAR),
      pb.CameraRecording(
          camera: pb.Camera.CAMERA_UNSPECIFIED, state: pb.RecordingState.RECORDING_STATE_RECORDING),
    ], problem: 'drive full', clipSegmentsPending: 3));
    expect(r.cameras[0].state, RecordingState.starting);
    expect(r.cameras[1].state, RecordingState.notRecording, reason: 'unspecified');
    expect(r.cameras[1].detail, 'unknown recording state');
    expect(r.cameras[2].camera, isNull);
    expect(r.problem, 'drive full');
    expect(r.clipSegmentsPending, 3);
    final c = saveClipFromPb(pb.SaveClipResponse(saved: true, detail: 'x', segmentsProtected: 1, segmentsToCome: 2));
    expect((c.saved, c.detail, c.segmentsProtected, c.segmentsToCome), (true, 'x', 1, 2));
  });

  test('the simulation records front and rear, and saves nothing', () async {
    final sim = SimulatedCameraSource();
    var r = sim.status.value.recording!;
    expect(r.records(CameraId.front) && r.records(CameraId.rear), isTrue);
    expect(sim.status.value.simulated, isTrue);
    final saved = await sim.saveClip();
    expect(saved.saved, isTrue);
    expect(saved.detail, startsWith('SIMULATED'));

    sim.setRecording(CameraId.rear, RecordingState.notRecording, detail: 'no frames');
    r = sim.status.value.recording!;
    expect(r.records(CameraId.rear), isFalse);
    expect(r.cameras.last.detail, 'no frames');
    // A move keeps the recording state.
    await sim.move(SwitchMove.left);
    expect(sim.status.value.recording, r);

    sim.setRecording(CameraId.front, RecordingState.notRecording);
    expect((await sim.saveClip()).saved, isFalse);
    sim.saveClipRefusal = 'saved clips are full';
    expect((await sim.saveClip()).detail, 'saved clips are full');
    sim.stop();
  });

  test('a move without camera-manager fails, it never hangs', () async {
    final src = GrpcCameraSource(endpoint: UnixEndpoint(path), callTimeout: const Duration(seconds: 1))
      ..start();
    addTearDown(src.stop);
    await until(src, (s) => s.link == CameraLink.down);
    await expectLater(src.move(SwitchMove.left), throwsA(anything));
    await expectLater(src.saveClip(), throwsA(anything));
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
