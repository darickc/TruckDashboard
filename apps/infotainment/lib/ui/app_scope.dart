import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import '../core/settings.dart';
import '../data/gateway_connection.dart';
import '../data/simulation_controller.dart';
import '../telemetry/calibration.dart';
import '../telemetry/telemetry_store.dart';

enum AppTab { home, gauges, media, navigation, cameras, diagnostics }

/// The app's services, created once in main() (or a test) and handed down.
class AppServices {
  AppServices({
    required this.store,
    required this.settings,
    required this.config,
    this.simulation,
    this.gateway,
    this.refreshPeriod = const Duration(milliseconds: 250),
  }) : assert((simulation == null) != (gateway == null), 'exactly one data source');

  final TelemetryStore store;
  final AppSettings settings;
  final AppConfig config;
  /// In-app simulator (Phase 2 / browser preview), or null.
  final SimulationController? simulation;

  /// Vehicle gateway connection (Phase 3), or null.
  final GatewayConnection? gateway;

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
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
