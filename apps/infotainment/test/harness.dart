import 'package:f250_infotainment/cameras/camera_state.dart';
import 'package:f250_infotainment/cameras/simulated_camera_source.dart';
import 'package:f250_infotainment/config/app_config.dart';
import 'package:f250_infotainment/core/clock.dart';
import 'package:f250_infotainment/core/power.dart';
import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/data/simulation_controller.dart';
import 'package:f250_infotainment/display/display_state.dart';
import 'package:f250_infotainment/export/export_state.dart';
import 'package:f250_infotainment/model/signal_catalog.dart';
import 'package:f250_infotainment/nav/offline_map.dart';
import 'package:f250_infotainment/nav/position_state.dart';
import 'package:f250_infotainment/nav/route_state.dart';
import 'package:f250_infotainment/nav/search_state.dart';
import 'package:f250_infotainment/telemetry/telemetry_store.dart';
import 'package:f250_infotainment/ui/app.dart';
import 'package:f250_infotainment/ui/app_scope.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powerstroke_sim/powerstroke_sim.dart';

/// Real assets, loaded once outside the fake-async zone of testWidgets.
late AppConfig testConfig;
late Map<String, Scenario> testScenarios;

Future<void> loadTestAssets() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  testConfig = await AppConfig.load(rootBundle, signalsById);
  testScenarios = await SimulationController.loadAll(rootBundle);
}

/// The whole app on an 800×480 view, driven by a fake clock and a manually
/// stepped simulator. Nothing runs on real timers.
class Harness {
  Harness._(this.tester, this.clock, this.services);

  final WidgetTester tester;
  final FakeMonotonicClock clock;
  final AppServices services;

  TelemetryStore get store => services.store;

  static Future<Harness> start(WidgetTester tester,
      {String scenario = 'drive_cycle',
      DayNight theme = DayNight.night,
      PowerControl power = const NoPowerControl(),
      CameraSource? cameras,
      DisplaySource? display,
      PositionSource? position,
      RouteSource? route,
      SearchSource? search,
      OfflineMap? map,
      ExportSource? exports}) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final clock = FakeMonotonicClock();
    final store = TelemetryStore(
      catalog: signalCatalog,
      clock: clock,
      rules: testConfig.rules,
      watchedSignals: testConfig.watched,
      calibrations: testConfig.calibrations,
    );
    final sim = SimulationController(
        store: store, bundle: rootBundle, available: testScenarios, autoRun: false)
      ..select(scenario);
    final services = AppServices(
      store: store,
      settings: AppSettings(),
      config: testConfig,
      simulation: sim,
      cameras: cameras ?? SimulatedCameraSource(),
      display: display ?? SimulatedDisplaySource(mode: theme),
      position: position ?? (SimulatedPositionSource(clock: clock, autoRun: false)..start()),
      route: route ?? UnavailableRouteSource('needs services/navigation (make sim)', clock),
      search: search,
      map: map,
      exports: exports,
      power: power,
      refreshPeriod: null,
    );
    await tester.pumpWidget(InfotainmentApp(services: services));
    return Harness._(tester, clock, services);
  }

  /// Advances simulated time in 100 ms steps, then rebuilds.
  Future<void> advance(Duration d) async {
    const step = Duration(milliseconds: 100);
    for (var t = Duration.zero; t < d; t += step) {
      clock.advance(step);
      services.simulation!.source!.step();
    }
    await tester.pump();
  }

  /// Shows [screen] as if opened from Home.
  Future<void> goTo(AppScreen screen) async {
    services.screens
      ..home()
      ..open(screen);
    await tester.pump();
  }

  /// Visible text of a widget found by key, or null.
  String? textOf(String key) {
    final f = find.byKey(ValueKey(key));
    if (f.evaluate().isEmpty) return null;
    return (tester.widget(f) as Text).data;
  }
}
