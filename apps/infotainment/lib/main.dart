import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cameras/camera_connection.dart';
import 'cameras/camera_state.dart';
import 'cameras/simulated_camera_source.dart';
import 'config/app_config.dart';
import 'core/clock.dart';
import 'core/power.dart';
import 'core/settings.dart';
import 'core/settings_store.dart';
import 'data/gateway_connection.dart';
import 'data/simulation_controller.dart';
import 'display/display_connection.dart';
import 'display/display_state.dart';
import 'export/export_connection.dart';
import 'export/export_state.dart';
import 'model/signal_catalog.dart';
import 'nav/offline_map.dart';
import 'nav/position_connection.dart';
import 'nav/position_state.dart';
import 'nav/route_connection.dart';
import 'nav/route_state.dart';
import 'nav/search_connection.dart';
import 'nav/search_state.dart';
import 'nav/vector_map.dart';
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

/// Day/night and the backlight: `sim` (no power-manager: Day or Night by
/// hand, nothing dimmed) or power-manager's endpoint
/// (`unix:/run/f250-power/power.sock` on the Pi). Default: `sim`; only the
/// Pi runs power-manager.
const _power = String.fromEnvironment('POWER', defaultValue: 'sim');

/// Position: `sim` (no navigation service: a simulated receiver, labelled
/// simulated) or services/navigation's endpoint
/// (`unix:/run/f250-nav/nav.sock` on the Pi). Default: `sim`.
const _nav = String.fromEnvironment('NAV', defaultValue: 'sim');

/// The offline map (PMTiles, vector or raster; ADR-0030, ADR-0032):
/// `/var/lib/f250/storage/maps/map.pmtiles` on the Pi, on the data drive.
/// Empty: none, and the Navigation screen says so.
const _mapFile = String.fromEnvironment('MAP_FILE');

/// The map import's status file (ADR-0033): `/run/f250-maps/status.json` on
/// the Pi. Empty: map sticks aren't watched.
const _mapStatus = String.fromEnvironment('MAP_STATUS');

/// Copying recordings to a USB stick (ADR-0037): `sim` (no usb-export: a
/// simulated stick, nothing copied) or usb-export's endpoint
/// (`unix:/run/f250-export/export.sock` on the Pi). Default: `sim`.
const _export = String.fromEnvironment('EXPORT', defaultValue: 'sim');

/// In-app simulator start point (`make ui-web SCENARIO=eot_ect_freeze START=110`).
const _scenario = String.fromEnvironment('SCENARIO', defaultValue: 'drive_cycle');
const _startSeconds = int.fromEnvironment('SIM_START_S');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  dispatcher.onError = ignoreDroppedTiles(dispatcher.onError);
  try {
    runApp(InfotainmentApp(
        services: await createServices(rootBundle,
            source: _source,
            gateway: _gateway,
            cameras: _cameras,
            power: _power,
            nav: _nav,
            mapFile: _mapFile,
            mapStatus: _mapStatus,
            export: _export,
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
  String power = 'sim',
  String nav = 'sim',
  String mapFile = '',
  String mapStatus = '',
  String export = 'sim',
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
  final DisplaySource display = power == 'sim'
      ? SimulatedDisplaySource()
      : connectPowerManager(GatewayEndpoint.parse(power));
  display.start();
  final PositionSource position =
      nav == 'sim' ? SimulatedPositionSource() : connectNavigation(GatewayEndpoint.parse(nav));
  position.start();
  // Routing comes from the same service as the position (ADR-0035).
  final RouteSource route =
      nav == 'sim' ? UnavailableRouteSource() : connectRouting(GatewayEndpoint.parse(nav));
  route.start();
  // So does search (ADR-0038).
  final SearchSource search =
      nav == 'sim' ? const UnavailableSearchSource() : connectSearch(GatewayEndpoint.parse(nav));
  search.start();
  final ExportSource exports =
      export == 'sim' ? SimulatedExportSource() : connectUsbExport(GatewayEndpoint.parse(export));
  exports.start();
  final map = OfflineMap(mapFile, statusPath: mapStatus);
  unawaited(map.load().then((_) => map.watch()));
  switch (source) {
    case 'gateway':
      final connection = GatewayConnection.create(store, GatewayEndpoint.parse(gateway))..start();
      return AppServices(
          store: store,
          settings: AppSettings(store: SettingsStore.forPlatform()),
          config: config,
          gateway: connection,
          cameras: cameraSource,
          display: display,
          position: position,
          route: route,
          search: search,
          map: map,
          exports: exports,
          power: PowerControl.forPlatform());
    case 'sim':
      final scenarios = await SimulationController.loadAll(bundle);
      final simulation =
          SimulationController(store: store, bundle: bundle, available: scenarios)
            ..select(scenarios.containsKey(scenario) ? scenario : scenarios.keys.first,
                startAt: startAt);
      return AppServices(
          store: store,
          settings: AppSettings(store: SettingsStore.forPlatform()),
          config: config,
          simulation: simulation,
          cameras: cameraSource,
          display: display,
          position: position,
          route: route,
          search: search,
          map: map,
          exports: exports,
          power: PowerControl.forPlatform());
    default:
      throw FormatException('VEHICLE_SOURCE must be sim or gateway, got "$source"');
  }
}
