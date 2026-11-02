import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:powerstroke_sim/powerstroke_sim.dart';

import '../model/signal_catalog.dart';
import '../telemetry/source_info.dart';
import '../telemetry/telemetry_store.dart';
import 'simulated_vehicle_data_source.dart';

const _scenarioPrefix = 'packages/powerstroke_sim/scenarios/';

/// Loads scenarios from the simulator package's assets and switches between
/// them, resetting the store so no reading carries over from the previous
/// scenario.
class SimulationController extends ChangeNotifier {
  SimulationController({
    required this.store,
    required this.bundle,
    required this.available,
    this.autoRun = true,
  });

  final TelemetryStore store;
  final AssetBundle bundle;
  final bool autoRun;

  /// Scenario id → parsed scenario, in display order.
  final Map<String, Scenario> available;

  SimulatedVehicleDataSource? _source;
  SimulatedVehicleDataSource? get source => _source;
  Scenario? get current => _source?.scenario;

  static Future<Map<String, Scenario>> loadAll(AssetBundle bundle) async {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    final paths = manifest
        .listAssets()
        .where((p) => p.startsWith(_scenarioPrefix) && p.endsWith('.yaml'))
        .toList()
      ..sort();
    final texts = {
      for (final p in paths)
        p.substring(_scenarioPrefix.length, p.length - 5): await bundle.loadString(p)
    };
    final out = <String, Scenario>{};
    for (final MapEntry(key: id, value: text) in texts.entries) {
      final s = Scenario.parse(id, text, resolve: (parent) {
        final t = texts[parent];
        if (t == null) throw ScenarioFormatException(id, 'extends unknown "$parent"');
        return t;
      });
      _checkAgainstCatalog(s);
      out[id] = s;
    }
    return out;
  }

  /// A scenario may only drive signals the UI knows, in their canonical units.
  static void _checkAgainstCatalog(Scenario s) {
    for (final t in s.tracks.values) {
      final def = signalsById[t.id];
      if (def == null) {
        throw ScenarioFormatException(s.id, 'signal "${t.id}" is not in the catalog');
      }
      if (def.isComputed) {
        throw ScenarioFormatException(s.id, '"${t.id}" is computed; simulate its inputs');
      }
      if (def.unit != t.unit) {
        throw ScenarioFormatException(
            s.id, '"${t.id}" unit is ${t.unit}, catalog says ${def.unit}');
      }
    }
  }

  void select(String id, {Duration startAt = Duration.zero}) {
    final scenario = available[id];
    if (scenario == null) throw ArgumentError.value(id, 'id', 'unknown scenario');
    _source?.stop();
    store.reset();
    final src = SimulatedVehicleDataSource(store: store, scenario: scenario, startAt: startAt);
    _source = src;
    store.source = SourceInfo(
        transport: 'simulator (in-app)', simulated: true, scenario: scenario.name);
    if (autoRun) {
      src.start();
    } else {
      src.startManual();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _source?.stop();
    super.dispose();
  }
}
