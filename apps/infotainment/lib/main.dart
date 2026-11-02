import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/app_config.dart';
import 'core/clock.dart';
import 'core/settings.dart';
import 'data/simulation_controller.dart';
import 'model/signal_catalog.dart';
import 'telemetry/telemetry_store.dart';
import 'ui/app.dart';
import 'ui/app_scope.dart';

/// Development overrides (`make ui-web SCENARIO=eot_ect_freeze START=110`).
const _scenario = String.fromEnvironment('SCENARIO', defaultValue: 'drive_cycle');
const _startSeconds = int.fromEnvironment('SIM_START_S');

/// Phase 2 entry point. Vehicle data comes from the in-process simulator;
/// the gateway-backed source replaces it in Phase 3.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    runApp(InfotainmentApp(
        services: await createServices(rootBundle,
            scenario: _scenario, startAt: const Duration(seconds: _startSeconds))));
  } catch (e) {
    runApp(StartupErrorApp(error: e));
  }
}

Future<AppServices> createServices(AssetBundle bundle,
    {String scenario = 'drive_cycle', Duration startAt = Duration.zero}) async {
  final config = await AppConfig.load(bundle, signalsById);
  final scenarios = await SimulationController.loadAll(bundle);
  final store = TelemetryStore(
    catalog: signalCatalog,
    clock: SystemMonotonicClock(),
    rules: config.rules,
    watchedSignals: config.watched,
  );
  final simulation =
      SimulationController(store: store, bundle: bundle, available: scenarios)
        ..select(scenarios.containsKey(scenario) ? scenario : scenarios.keys.first,
            startAt: startAt);
  return AppServices(
    store: store,
    settings: AppSettings(),
    config: config,
    simulation: simulation,
  );
}
