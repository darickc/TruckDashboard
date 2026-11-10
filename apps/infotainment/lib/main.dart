import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cameras/camera_connection.dart';
import 'cameras/camera_state.dart';
import 'cameras/simulated_camera_source.dart';
import 'config/app_config.dart';
import 'core/clock.dart';
import 'core/power.dart';
import 'core/settings.dart';
import 'data/gateway_connection.dart';
import 'data/simulation_controller.dart';
import 'model/signal_catalog.dart';
import 'telemetry/telemetry_store.dart';
import 'ui/app.dart';
import 'ui/app_scope.dart';

/// Data source: `sim` (in-app simulator, the default and the only option on
/// the web) or `gateway` (services/vehicle-gateway over gRPC at [_gateway]).
const _source = String.fromEnvironment('VEHICLE_SOURCE', defaultValue: 'sim');
const _gateway = String.fromEnvironment('GATEWAY', defaultValue: 'unix:/tmp/f250/vehicle.sock');

/// Cameras: `sim` (no camera-manager: a simulation with no picture), or
/// camera-manager's endpoint (`unix:/run/f250-camera/camera.sock` on the Pi).
/// Default: `sim` with the in-app simulator, the development socket with the
/// gateway.
const _cameras = String.fromEnvironment('CAMERAS', defaultValue: 'auto');

/// In-app simulator start point (`make ui-web SCENARIO=eot_ect_freeze START=110`).
const _scenario = String.fromEnvironment('SCENARIO', defaultValue: 'drive_cycle');
const _startSeconds = int.fromEnvironment('SIM_START_S');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    runApp(InfotainmentApp(
        services: await createServices(rootBundle,
            source: _source,
            gateway: _gateway,
            cameras: _cameras,
            scenario: _scenario,
            startAt: const Duration(seconds: _startSeconds))));
  } catch (e) {
    runApp(StartupErrorApp(error: e));
  }
}

Future<AppServices> createServices(
  AssetBundle bundle, {
  String source = 'sim',
  String gateway = 'unix:/tmp/f250/vehicle.sock',
  String cameras = 'auto',
  String scenario = 'drive_cycle',
  Duration startAt = Duration.zero,
}) async {
  final config = await AppConfig.load(bundle, signalsById);
  final store = TelemetryStore(
    catalog: signalCatalog,
    clock: SystemMonotonicClock(),
    rules: config.rules,
    watchedSignals: config.watched,
    calibrations: config.calibrations,
  );
  final camerasAt = cameras == 'auto'
      ? (source == 'gateway' ? 'unix:/tmp/f250/camera.sock' : 'sim')
      : cameras;
  final CameraSource cameraSource = camerasAt == 'sim'
      ? SimulatedCameraSource()
      : connectCameraManager(GatewayEndpoint.parse(camerasAt));
  cameraSource.start();
  switch (source) {
    case 'gateway':
      final connection = GatewayConnection.create(store, GatewayEndpoint.parse(gateway))..start();
      return AppServices(
          store: store,
          settings: AppSettings(),
          config: config,
          gateway: connection,
          cameras: cameraSource,
          power: PowerControl.forPlatform());
    case 'sim':
      final scenarios = await SimulationController.loadAll(bundle);
      final simulation =
          SimulationController(store: store, bundle: bundle, available: scenarios)
            ..select(scenarios.containsKey(scenario) ? scenario : scenarios.keys.first,
                startAt: startAt);
      return AppServices(
          store: store,
          settings: AppSettings(),
          config: config,
          simulation: simulation,
          cameras: cameraSource,
          power: PowerControl.forPlatform());
    default:
      throw FormatException('VEHICLE_SOURCE must be sim or gateway, got "$source"');
  }
}
