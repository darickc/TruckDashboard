import 'dart:async';

import 'package:f250_infotainment/core/clock.dart';
import 'package:f250_infotainment/data/gateway_connection.dart';
import 'package:f250_infotainment/data/grpc_vehicle_data_source.dart';
import 'package:f250_infotainment/gen/f250/vehicle/v1/vehicle.pbgrpc.dart' as pb;
import 'package:f250_infotainment/model/signal.dart';
import 'package:f250_infotainment/model/signal_catalog.dart';
import 'package:f250_infotainment/telemetry/calibration.dart';
import 'package:f250_infotainment/telemetry/telemetry_store.dart';
import 'package:f250_infotainment/telemetry/warnings.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';

/// A stand-in gateway: serves whatever snapshots the test pushes.
class FakeGateway extends pb.VehicleServiceBase {
  final snapshots = StreamController<pb.StreamSnapshotsResponse>.broadcast();
  double speedScale = 1.0;

  @override
  Future<pb.ListSignalsResponse> listSignals(ServiceCall call, pb.ListSignalsRequest request) async =>
      pb.ListSignalsResponse(signals: [
        pb.SignalDefinition(id: 'speed', calibrationScale: speedScale, calibrationOffset: 0),
      ]);

  @override
  Stream<pb.StreamSnapshotsResponse> streamSnapshots(
          ServiceCall call, pb.StreamSnapshotsRequest request) =>
      snapshots.stream;

  @override
  Future<pb.ListEventsResponse> listEvents(ServiceCall call, pb.ListEventsRequest request) async =>
      pb.ListEventsResponse();

  @override
  Future<pb.SetCalibrationResponse> setCalibration(
      ServiceCall call, pb.SetCalibrationRequest request) async {
    speedScale = request.scale;
    return pb.SetCalibrationResponse(
        signal: pb.SignalDefinition(id: request.signalId, calibrationScale: request.scale));
  }
}

pb.Snapshot snapshot({
  int mono = 10000,
  List<pb.Sample> samples = const [],
  pb.LinkState link = pb.LinkState.LINK_STATE_UP,
  List<pb.Alert> alerts = const [],
}) =>
    pb.Snapshot(
      monoMs: Int64(mono),
      samples: samples,
      alerts: alerts,
      link: pb.LinkStatus(
        state: link,
        sinceMonoMs: Int64(mono - 3000),
        transport: 'obdlink',
        simulated: false,
        transmitEnabled: true,
        machineState: 'POLLING',
        adapterVoltage: 12.6,
      ),
    );

void main() {
  late Server server;
  late FakeGateway gateway;
  late FakeMonotonicClock clock;
  late TelemetryStore store;
  late GrpcVehicleDataSource source;

  setUp(() async {
    gateway = FakeGateway();
    server = Server.create(services: [gateway]);
    await server.serve(address: 'localhost', port: 0);
    clock = FakeMonotonicClock(const Duration(seconds: 100));
    store = TelemetryStore(catalog: signalCatalog, clock: clock, rules: const []);
    source = GrpcVehicleDataSource(
        store: store,
        endpoint: TcpEndpoint('localhost', server.port!),
        retryDelay: const Duration(milliseconds: 50))
      ..start();
  });

  tearDown(() async {
    source.stop();
    await server.shutdown();
  });

  Future<void> push(pb.Snapshot s) async {
    gateway.snapshots.add(pb.StreamSnapshotsResponse(snapshot: s));
    // Let the stream deliver.
    for (var i = 0; i < 50 && store.source.machineState == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  Future<void> connected() async {
    for (var i = 0; i < 100 && !gateway.snapshots.hasListener; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(gateway.snapshots.hasListener, isTrue, reason: 'client subscribed');
  }

  test('mirrors validity, values, ages and link state from the gateway', () async {
    await connected();
    await push(snapshot(samples: [
      pb.Sample(
          signalId: 'eot',
          validity: pb.Validity.VALIDITY_VALID,
          value: 92,
          lastGoodValue: 92,
          lastGoodAgeMs: Int64(400),
          successes: Int64(10)),
      pb.Sample(
          signalId: 'ect',
          validity: pb.Validity.VALIDITY_STALE,
          lastGoodValue: 88,
          lastGoodAgeMs: Int64(12000),
          failures: Int64(4),
          consecutiveFailures: 4),
      pb.Sample(signalId: 'icp', validity: pb.Validity.VALIDITY_UNSUPPORTED, lastNrc: 0x31),
    ]));
    final eot = store['eot']!;
    expect(eot.validity, Validity.valid);
    expect(eot.value, 92);
    expect(eot.ageAt(clock.now()), const Duration(milliseconds: 400));
    final ect = store['ect']!;
    expect(ect.validity, Validity.stale);
    expect(ect.value, isNull, reason: 'a stale sample never carries a current value');
    expect(ect.lastGoodValue, 88);
    expect(store['icp']!.validity, Validity.unsupported);
    expect(store['icp']!.lastNrc, 0x31);
    expect(store.link, LinkState.up);
    expect(store.linkSince, clock.now() - const Duration(seconds: 3));
    expect(store.source.transport, 'gateway: obdlink');
    expect(store.source.simulated, isFalse);
    expect(store.source.adapterVoltage, 12.6);
    expect(store.source.machineState, 'POLLING');
  });

  test('a value is never shown as current unless the gateway says VALID', () async {
    await connected();
    await push(snapshot(samples: [
      // Malformed: value present on a STALE sample.
      pb.Sample(signalId: 'eot', validity: pb.Validity.VALIDITY_STALE, value: 92),
    ]));
    expect(store['eot']!.value, isNull);
  });

  test('gateway alerts are mirrored, including threshold details', () async {
    await connected();
    await push(snapshot(alerts: [
      pb.Alert(
          id: 'rule:ect_high',
          kind: pb.AlertKind.ALERT_KIND_THRESHOLD,
          level: pb.AlertLevel.ALERT_LEVEL_CRITICAL,
          sinceMonoMs: Int64(9000),
          signalId: 'ect',
          threshold: 110,
          above: true),
    ]));
    final a = store.alerts.single;
    expect(a.kind, AlertKind.threshold);
    expect(a.level, AlertLevel.critical);
    expect(a.threshold, 110);
    expect(a.since, clock.now() - const Duration(seconds: 1));
  });

  test('if snapshots stop, the watchdog makes everything stale', () async {
    await connected();
    await push(snapshot(samples: [
      pb.Sample(
          signalId: 'eot',
          validity: pb.Validity.VALIDITY_VALID,
          value: 92,
          lastGoodValue: 92,
          lastGoodAgeMs: Int64(100)),
    ]));
    expect(store['eot']!.isValid, isTrue);
    clock.advance(const Duration(seconds: 3)); // > feedTimeout, no new snapshot
    store.refresh();
    expect(store['eot']!.validity, Validity.stale);
    expect(store['eot']!.value, isNull);
    expect(store['eot']!.lastGoodValue, 92);
    expect(store.link, LinkState.down);
    expect(store.alerts.single.kind, AlertKind.sourceLost);
    expect(store.events.newestFirst.first.message, 'Gateway feed lost');
    // A new snapshot restores it.
    await push(snapshot(samples: [
      pb.Sample(signalId: 'eot', validity: pb.Validity.VALIDITY_VALID, value: 93, lastGoodValue: 93),
    ]));
    expect(store['eot']!.value, 93);
    expect(store.alerts, isEmpty);
  });

  test('calibration changes go to the gateway', () async {
    await connected();
    await source.setCalibration('speed', const Calibration(scale: 1.05));
    expect(gateway.speedScale, 1.05);
    expect(store.calibrationOf('speed').scale, 1.05);
  });

  test('endpoint parsing', () {
    expect(GatewayEndpoint.parse('unix:/run/f250/vehicle.sock'), isA<UnixEndpoint>());
    final t = GatewayEndpoint.parse('tcp:127.0.0.1:50251') as TcpEndpoint;
    expect((t.host, t.port), ('127.0.0.1', 50251));
    expect(() => GatewayEndpoint.parse('http://x'), throwsFormatException);
    expect(() => GatewayEndpoint.parse('tcp:host'), throwsFormatException);
  });
}
