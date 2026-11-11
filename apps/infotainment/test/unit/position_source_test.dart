import 'dart:async';
import 'dart:io';

import 'package:f250_infotainment/core/clock.dart';
import 'package:f250_infotainment/data/gateway_connection.dart';
import 'package:f250_infotainment/gen/f250/nav/v1/position.pbgrpc.dart' as pb;
import 'package:f250_infotainment/nav/grpc_position_source.dart';
import 'package:f250_infotainment/nav/position_state.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart' as grpc;

/// A stand-in services/navigation: streams what the test pushes.
class FakeNavigation extends pb.PositionServiceBase {
  var updates = StreamController<pb.WatchPositionResponse>.broadcast();
  pb.Position current = fix3d();

  void push(pb.Position p) {
    current = p;
    updates.add(pb.WatchPositionResponse(position: p));
  }

  @override
  Stream<pb.WatchPositionResponse> watchPosition(
    grpc.ServiceCall call,
    pb.WatchPositionRequest request,
  ) async* {
    yield pb.WatchPositionResponse(position: current);
    yield* updates.stream;
  }
}

pb.Position fix3d({int ageMs = 200, bool current = true}) => pb.Position(
  status: pb.FixStatus.FIX_STATUS_FIX_3D,
  fix: pb.Fix(
    latitudeDeg: 39.8287,
    longitudeDeg: -98.5791,
    ageMs: Int64(ageMs),
    altitudeMslM: 560,
    speedMps: 15.433,
    trackDeg: 45,
    horizontalErrorM: 22.8,
    utcTimeMs: Int64(1794420006000),
  ),
  current: current,
  staleAfterMs: Int64(3000),
  satellitesUsed: 8,
  satellitesVisible: 8,
  source: 'gpsd 3.27.5: /dev/ttyACM0',
);

Future<PositionState> until(PositionSource src, bool Function(PositionState) pred) async {
  if (pred(src.status.value)) return src.status.value;
  final done = Completer<PositionState>();
  void check() {
    if (!done.isCompleted && pred(src.status.value)) done.complete(src.status.value);
  }

  src.status.addListener(check);
  try {
    return await done.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException('last status ${src.status.value.link}'),
    );
  } finally {
    src.status.removeListener(check);
  }
}

void main() {
  group('reportFromPb', () {
    test('a 3D fix', () {
      final r = reportFromPb(fix3d(), const Duration(seconds: 7));
      expect(r.status, FixStatus.fix3d);
      expect(r.current, isTrue);
      expect(r.receivedAt, const Duration(seconds: 7));
      expect(r.staleAfter, const Duration(seconds: 3));
      expect(r.fix!.lat, 39.8287);
      expect(r.fix!.ageAtReceipt, const Duration(milliseconds: 200));
      expect(r.fix!.trackDeg, 45);
      expect(r.fix!.errorM, 22.8);
      expect(r.fix!.utcMs, 1794420006000);
      expect(r.satellitesUsed, 8);
      expect(r.simulated, isFalse);
    });

    test('absent optional fields stay absent', () {
      final p = pb.Position(
        status: pb.FixStatus.FIX_STATUS_FIX_2D,
        fix: pb.Fix(latitudeDeg: 1, longitudeDeg: 2),
        current: true,
        staleAfterMs: Int64(3000),
      );
      final r = reportFromPb(p, Duration.zero);
      expect(r.fix!.altitudeM, isNull);
      expect(r.fix!.speedMps, isNull);
      expect(r.fix!.trackDeg, isNull);
      expect(r.satellitesUsed, isNull);
    });

    test('never current without a fix status and a fix', () {
      expect(
        reportFromPb(
          pb.Position(
            status: pb.FixStatus.FIX_STATUS_NO_FIX,
            fix: pb.Fix(latitudeDeg: 1, longitudeDeg: 2),
            current: true,
          ),
          Duration.zero,
        ).current,
        isFalse,
      );
      expect(
        reportFromPb(
          pb.Position(status: pb.FixStatus.FIX_STATUS_FIX_3D, current: true),
          Duration.zero,
        ).current,
        isFalse,
      );
    });

    test('an unknown status (a newer service) is unavailable, never a fix', () {
      final p = fix3d()..status = pb.FixStatus.valueOf(99) ?? pb.FixStatus.FIX_STATUS_UNSPECIFIED;
      final r = reportFromPb(p, Duration.zero);
      expect(r.status, FixStatus.unavailable);
      expect(r.current, isFalse);
    });
  });

  group('PositionState', () {
    PositionState connected(PositionReport r) =>
        PositionState(link: PositionLink.connected, report: r);

    test('ages from the message\'s age plus time since it arrived', () {
      final s = connected(reportFromPb(fix3d(ageMs: 500), const Duration(seconds: 10)));
      expect(s.fixAge(const Duration(seconds: 12)), const Duration(milliseconds: 2500));
      expect(s.isCurrent(const Duration(seconds: 12)), isTrue);
    });

    test('a stalled stream can\'t keep a fix current', () {
      final s = connected(reportFromPb(fix3d(), const Duration(seconds: 10)));
      expect(s.isCurrent(const Duration(seconds: 13)), isTrue, reason: 'at the limit');
      expect(s.isCurrent(const Duration(milliseconds: 13001)), isFalse);
      expect(s.why(const Duration(seconds: 15)), contains('No update from the navigation service'));
    });

    test('not current when navigation says so, with its reason', () {
      final p = fix3d(current: false)
        ..status = pb.FixStatus.FIX_STATUS_NO_FIX
        ..detail = 'no GPS fix yet (needs a view of the sky)';
      final s = connected(reportFromPb(p, Duration.zero));
      expect(s.isCurrent(Duration.zero), isFalse);
      expect(s.why(Duration.zero), 'No GPS fix yet (needs a view of the sky)');
    });

    test('never current while the link is down, and says why', () {
      final s = PositionState(
        link: PositionLink.lost,
        report: reportFromPb(fix3d(), Duration.zero),
        detail: 'connection refused',
      );
      expect(s.isCurrent(Duration.zero), isFalse);
      expect(s.fixAge(const Duration(seconds: 4)), const Duration(milliseconds: 4200));
      expect(s.why(Duration.zero), 'Navigation service unavailable: connection refused');
    });
  });

  group('SimulatedPositionSource', () {
    test('drives the loop, labelled simulated, and goes stale if not stepped', () {
      final clock = FakeMonotonicClock();
      final src = SimulatedPositionSource(clock: clock, autoRun: false)..start();
      var s = src.status.value;
      expect(s.report!.simulated, isTrue);
      expect(s.report!.fix!.lat, SimulatedPositionSource.corners.first.$1);
      expect(s.report!.fix!.trackDeg, closeTo(90, 0.1), reason: 'first leg heads east');
      expect(s.isCurrent(clock.now()), isTrue);
      clock.advance(const Duration(seconds: 60));
      expect(s.isCurrent(clock.now()), isFalse);
      src.step();
      s = src.status.value;
      expect(s.isCurrent(clock.now()), isTrue);
      expect(s.report!.fix!.lon, greaterThan(SimulatedPositionSource.corners.first.$2));
    });
  });

  group('GrpcPositionSource', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('f250-nav');
      path = '${dir.path}/n.sock';
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('follows navigation, keeps the last fix when it goes, and reconnects', () async {
      final fake = FakeNavigation();
      final server = grpc.Server.create(services: [fake]);
      await server.serve(address: InternetAddress(path, type: InternetAddressType.unix), port: 0);
      final clock = FakeMonotonicClock(const Duration(seconds: 100));
      final src = GrpcPositionSource(
        endpoint: UnixEndpoint(path),
        clock: clock,
        retryDelay: const Duration(milliseconds: 100),
      )..start();

      var s = await until(src, (s) => s.link == PositionLink.connected);
      expect(s.isCurrent(clock.now()), isTrue);
      expect(s.report!.receivedAt, const Duration(seconds: 100));
      expect(s.report!.source, 'gpsd 3.27.5: /dev/ttyACM0');

      fake.updates.addError(const grpc.GrpcError.unavailable('navigation stopping'));
      s = await until(src, (s) => s.link == PositionLink.lost);
      expect(s.isCurrent(clock.now()), isFalse);
      expect(s.report!.fix!.lat, 39.8287, reason: 'kept, to show as last known');
      expect(s.why(clock.now()), contains('navigation stopping'));

      fake.updates = StreamController<pb.WatchPositionResponse>.broadcast();
      s = await until(src, (s) => s.link == PositionLink.connected);
      expect(s.isCurrent(clock.now()), isTrue);

      src.stop();
      await server.shutdown();
    });

    test('nothing listening: lost, with no fix', () async {
      final src = GrpcPositionSource(
        endpoint: UnixEndpoint('${dir.path}/none.sock'),
        retryDelay: const Duration(milliseconds: 100),
      )..start();
      final s = await until(src, (s) => s.link == PositionLink.lost);
      expect(s.report, isNull);
      expect(s.why(Duration.zero), startsWith('Navigation service unavailable'));
      src.stop();
    });
  });
}
