import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/app_config.dart';
import 'core/clock.dart';
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
  switch (source) {
    case 'gateway':
      final connection = GatewayConnection.create(store, GatewayEndpoint.parse(gateway))..start();
      return AppServices(
          store: store, settings: AppSettings(), config: config, gateway: connection);
    case 'sim':
      final scenarios = await SimulationController.loadAll(bundle);
      final simulation =
          SimulationController(store: store, bundle: bundle, available: scenarios)
            ..select(scenarios.containsKey(scenario) ? scenario : scenarios.keys.first,
                startAt: startAt);
      return AppServices(
          store: store, settings: AppSettings(), config: config, simulation: simulation);
    default:
      throw FormatException('VEHICLE_SOURCE must be sim or gateway, got "$source"');
  }
}
