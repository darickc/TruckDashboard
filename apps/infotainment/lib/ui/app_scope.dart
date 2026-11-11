import 'package:flutter/widgets.dart';

import '../cameras/camera_state.dart';
import '../cameras/simulated_camera_source.dart';
import '../config/app_config.dart';
import '../core/power.dart';
import '../core/settings.dart';
import '../data/gateway_connection.dart';
import '../data/simulation_controller.dart';
import '../display/display_state.dart';
import '../telemetry/calibration.dart';
import '../telemetry/telemetry_store.dart';
import 'banner_alerts.dart';

enum AppTab { home, gauges, media, navigation, cameras, settings, diagnostics }

/// The app's services, created once in main() (or a test) and handed down.
class AppServices {
  AppServices({
    required this.store,
    required this.settings,
    required this.config,
    this.simulation,
    this.gateway,
    CameraSource? cameras,
    DisplaySource? display,
    this.power = const NoPowerControl(),
    this.refreshPeriod = const Duration(milliseconds: 250),
  })  : cameras = cameras ?? SimulatedCameraSource(),
        display = display ?? SimulatedDisplaySource(),
        assert((simulation == null) != (gateway == null), 'exactly one data source');

  final TelemetryStore store;
  final AppSettings settings;
  final AppConfig config;
  /// In-app simulator (Phase 2 / browser preview), or null.
  final SimulationController? simulation;

  /// Vehicle gateway connection (Phase 3), or null.
  final GatewayConnection? gateway;

  /// camera-manager (Phase 6.6, ADR-0026), or a simulation of it.
  final CameraSource cameras;

  /// Day/night and the backlight: power-manager (Phase 6.7, ADR-0028), or a
  /// simulation of it. Its mode picks the palette.
  final DisplaySource display;

  /// Whether, and how, the screen can shut the head unit down.
  final PowerControl power;

  /// Changes a signal's calibration wherever the data is produced.
  Future<void> setCalibration(String id, Calibration c) async {
    final g = gateway;
    if (g != null) return g.setCalibration(id, c);
    store.setCalibration(id, c);
  }

  /// The shell refreshes the store on this period, independently of the data
  /// source, so values go stale even if the source stops. Null disables the
  /// timer (tests pump refreshes explicitly).
  final Duration? refreshPeriod;

  final tab = ValueNotifier(AppTab.home);

  /// "Not polling the truck" shows only once it has lasted this long
  /// (banner_alerts.dart).
  final notPolling = Persistence(kNotPollingAfter);
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
