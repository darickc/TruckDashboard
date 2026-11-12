import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../cameras/camera_state.dart';
import '../cameras/simulated_camera_source.dart';
import '../config/app_config.dart';
import '../core/power.dart';
import '../core/settings.dart';
import '../data/gateway_connection.dart';
import '../data/simulation_controller.dart';
import '../display/display_state.dart';
import '../nav/offline_map.dart';
import '../nav/position_state.dart';
import '../nav/route_state.dart';
import '../telemetry/calibration.dart';
import '../telemetry/telemetry_store.dart';
import 'banner_alerts.dart';

/// The dashboard's screens. Home is a grid of buttons to the others; every
/// other screen has Back at its top left (shell/nav_buttons.dart).
enum AppScreen { home, gauges, media, navigation, cameras, settings, diagnostics }

/// Which screen is showing, and the way back to Home: a stack whose bottom is
/// always Home. Back pops one screen; Home clears the stack.
class ScreenHistory extends ChangeNotifier implements ValueListenable<AppScreen> {
  final _stack = [AppScreen.home];

  /// The screen showing.
  @override
  AppScreen get value => _stack.last;

  /// Home, then each screen opened since, the one showing last.
  List<AppScreen> get stack => List.unmodifiable(_stack);

  /// The screen Back returns to, or null on Home.
  AppScreen? get previous => _stack.length > 1 ? _stack[_stack.length - 2] : null;

  /// Opens [screen] on top of the one showing, so Back returns to it.
  /// Opening Home, or the screen already showing, doesn't stack.
  void open(AppScreen screen) {
    if (screen == AppScreen.home) return home();
    if (screen == value) return;
    // A screen already in the stack is returned to rather than stacked
    // twice, so Back never cycles.
    final at = _stack.indexOf(screen);
    if (at >= 0) {
      _stack.removeRange(at + 1, _stack.length);
    } else {
      _stack.add(screen);
    }
    notifyListeners();
  }

  /// Returns to the previous screen. Does nothing on Home.
  void back() {
    if (_stack.length == 1) return;
    _stack.removeLast();
    notifyListeners();
  }

  /// Returns straight to Home.
  void home() {
    if (_stack.length == 1) return;
    _stack.removeRange(1, _stack.length);
    notifyListeners();
  }
}

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
    PositionSource? position,
    RouteSource? route,
    OfflineMap? map,
    this.power = const NoPowerControl(),
    this.refreshPeriod = const Duration(milliseconds: 250),
  })  : cameras = cameras ?? SimulatedCameraSource(),
        display = display ?? SimulatedDisplaySource(),
        position = position ?? SimulatedPositionSource(autoRun: false),
        route = route ?? UnavailableRouteSource(),
        map = map ?? OfflineMap.none(),
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

  /// The truck's position: services/navigation (Phase 6.4, ADR-0030), or a
  /// simulated receiver.
  final PositionSource position;

  /// Routing and guidance: services/navigation with Valhalla (Phase 6.5.2,
  /// ADR-0035), or unavailable without it.
  final RouteSource route;

  /// The offline raster map (Phase 6.5.1, ADR-0030), or none.
  final OfflineMap map;

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

  /// The screen showing and the way back to Home.
  final screens = ScreenHistory();

  /// "Not polling the truck" shows only once it has lasted this long
  /// (banner_alerts.dart).
  final notPolling = Persistence(kNotPollingAfter);

  /// Advisories cleared from the banner (banner_alerts.dart).
  final cleared = ClearedAlerts(kForgetClearedAfter);
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
