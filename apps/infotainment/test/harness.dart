import 'package:f250_infotainment/config/app_config.dart';
import 'package:f250_infotainment/core/clock.dart';
import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/data/simulation_controller.dart';
import 'package:f250_infotainment/model/signal_catalog.dart';
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
      {String scenario = 'drive_cycle', DayNight theme = DayNight.night}) async {
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
      settings: AppSettings(theme: theme),
      config: testConfig,
      simulation: sim,
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
      services.simulation.source!.step();
    }
    await tester.pump();
  }

  Future<void> goTo(AppTab tab) async {
    services.tab.value = tab;
    await tester.pump();
  }

  /// Visible text of a widget found by key, or null.
  String? textOf(String key) {
    final f = find.byKey(ValueKey(key));
    if (f.evaluate().isEmpty) return null;
    return (tester.widget(f) as Text).data;
  }
}
