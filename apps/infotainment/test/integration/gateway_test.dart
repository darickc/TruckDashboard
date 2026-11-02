// Runs the real services/vehicle-gateway binary (simulated transport) and
// reads it through the app's gRPC data source. Skipped unless the binary is
// built: `cargo build -p vehicle-gateway` (make test does this).
@Tags(['integration'])
library;

import 'dart:io';

import 'package:f250_infotainment/core/clock.dart';
import 'package:f250_infotainment/data/gateway_connection.dart';
import 'package:f250_infotainment/data/grpc_vehicle_data_source.dart';
import 'package:f250_infotainment/model/signal.dart';
import 'package:f250_infotainment/model/signal_catalog.dart';
import 'package:f250_infotainment/telemetry/calibration.dart';
import 'package:f250_infotainment/telemetry/telemetry_store.dart';
import 'package:f250_infotainment/telemetry/warnings.dart';
import 'package:flutter_test/flutter_test.dart';

final _root = Directory.current.parent.parent.path; // apps/infotainment → repo
final _bin = File('$_root/target/debug/vehicle-gateway');

Future<(Process, int)> _startGateway(String scenario, int startS) async {
  final port = 50300 + (pid % 500);
  final p = await Process.start(
    _bin.path,
    [
      '--listen', 'tcp:127.0.0.1:$port',
      '--scenario', scenario,
      '--sim-start-s', '$startS',
    ],
    workingDirectory: _root,
  );
  p.stderr.listen((_) {});
  p.stdout.listen((_) {});
  await Future<void>.delayed(const Duration(milliseconds: 800));
  return (p, port);
}

Future<void> _until(bool Function() ok, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('condition not met within $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  final skip = _bin.existsSync() ? false : 'build the gateway first: cargo build -p vehicle-gateway';

  test('live data, unverified PIDs and link state come through from the gateway', () async {
    final (gw, port) = await _startGateway('drive_cycle', 60);
    addTearDown(gw.kill);
    final store = TelemetryStore(catalog: signalCatalog, clock: SystemMonotonicClock(), rules: const []);
    final src = GrpcVehicleDataSource(store: store, endpoint: TcpEndpoint('127.0.0.1', port))..start();
    addTearDown(src.stop);

    await _until(() => store['rpm']!.isValid && store['eot']!.isValid);
    expect(store.source.simulated, isTrue);
    expect(store.source.transport, 'gateway: simulated');
    expect(store.source.machineState, 'POLLING');
    expect(store['rpm']!.value, inInclusiveRange(600, 3000));
    // Valid whenever both inputs are fresh and close together; under a
    // stretched schedule that's not every instant, so wait for it.
    await _until(() => store['eot_ect_delta']!.isValid);
    expect(store['egt']!.validity, Validity.disabled);
    expect(store.link, anyOf(LinkState.up, LinkState.degraded));
  }, skip: skip, timeout: const Timeout(Duration(seconds: 60)));

  test('EOT/ECT freeze reaches the app as stale with a not-updating alert', () async {
    final (gw, port) = await _startGateway('eot_ect_freeze', 110);
    addTearDown(gw.kill);
    final store = TelemetryStore(catalog: signalCatalog, clock: SystemMonotonicClock(), rules: const []);
    final src = GrpcVehicleDataSource(store: store, endpoint: TcpEndpoint('127.0.0.1', port))..start();
    addTearDown(src.stop);

    await _until(() => store['eot']!.isValid);
    await _until(() => store['eot']!.validity == Validity.stale, timeout: const Duration(seconds: 30));
    expect(store['eot']!.value, isNull);
    expect(store['eot']!.lastGoodValue, isNotNull);
    expect(store['rpm']!.isValid, isTrue, reason: 'other PIDs keep working');
    expect(store['eot_ect_delta']!.value, isNull);
    await _until(() => store.alerts.any((a) => a.kind == AlertKind.signalNotUpdating));
    expect(store.link, LinkState.degraded);
  }, skip: skip, timeout: const Timeout(Duration(seconds: 90)));

  test('killing the gateway makes the app go stale on its own', () async {
    final (gw, port) = await _startGateway('drive_cycle', 60);
    final store = TelemetryStore(catalog: signalCatalog, clock: SystemMonotonicClock(), rules: const []);
    final src = GrpcVehicleDataSource(store: store, endpoint: TcpEndpoint('127.0.0.1', port))..start();
    addTearDown(src.stop);
    await _until(() => store['rpm']!.isValid);
    gw.kill();
    await gw.exitCode;
    await Future<void>.delayed(store.feedTimeout + const Duration(milliseconds: 500));
    store.refresh();
    expect(store['rpm']!.isValid, isFalse);
    expect(store.alerts.single.kind, AlertKind.sourceLost);
  }, skip: skip, timeout: const Timeout(Duration(seconds: 60)));

  test('calibration set from the app is applied by the gateway', () async {
    final (gw, port) = await _startGateway('drive_cycle', 120);
    addTearDown(gw.kill);
    final store = TelemetryStore(catalog: signalCatalog, clock: SystemMonotonicClock(), rules: const []);
    final src = GrpcVehicleDataSource(store: store, endpoint: TcpEndpoint('127.0.0.1', port))..start();
    addTearDown(src.stop);
    await _until(() => store['speed']!.isValid);
    await src.setCalibration('speed', const Calibration(scale: 1.1));
    await _until(() {
      final s = store['speed']!;
      return s.isValid && s.lastGoodRaw != null && (s.value! - s.lastGoodRaw! * 1.1).abs() < 1e-6;
    });
    expect(store.calibrationOf('speed').scale, closeTo(1.1, 1e-9));
  }, skip: skip, timeout: const Timeout(Duration(seconds: 60)));
}
