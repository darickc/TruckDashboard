import 'dart:convert';

import 'package:flutter/services.dart';

import '../model/signal.dart';
import '../telemetry/calibration.dart';
import '../telemetry/warnings.dart';

enum GaugeStyle { digital, circular, compact }

class GaugeTileSpec {
  const GaugeTileSpec(this.signalId, this.style);

  final String signalId;
  final GaugeStyle style;
}

class GaugeProfile {
  const GaugeProfile(this.id, this.name, this.tiles);

  final String id;
  final String name;
  final List<GaugeTileSpec> tiles;
}

/// Configuration loaded from assets/config/. Validated against the signal
/// catalog at load time: a typo in a signal id fails fast with a message,
/// rather than a tile quietly showing nothing.
class AppConfig {
  const AppConfig({
    required this.rules,
    required this.watched,
    required this.profiles,
    this.calibrations = const {},
  });

  final List<WarningRule> rules;
  final List<String> watched;
  final List<GaugeProfile> profiles;

  /// Signal id → correction from assets/config/calibration.json.
  final Map<String, Calibration> calibrations;

  static const maxTilesPerProfile = 8;

  static Future<AppConfig> load(AssetBundle bundle, Map<String, SignalDef> signals) async {
    return parse(
      await bundle.loadString('assets/config/warning_rules.json'),
      await bundle.loadString('assets/config/gauge_profiles.json'),
      signals,
      calibrationJson: await bundle.loadString('assets/config/calibration.json'),
    );
  }

  static AppConfig parse(String rulesJson, String profilesJson, Map<String, SignalDef> signals,
      {String? calibrationJson}) {
    void known(String id, String where) {
      if (!signals.containsKey(id)) throw FormatException('$where: unknown signal "$id"');
    }

    final r = jsonDecode(rulesJson) as Map<String, dynamic>;
    final rules = [
      for (final j in r['rules'] as List) WarningRule.fromJson(j as Map<String, dynamic>)
    ];
    for (final rule in rules) {
      known(rule.signalId, 'warning rule ${rule.id}');
      if (rule.gate != null) known(rule.gate!.signalId, 'warning rule ${rule.id} gate');
    }
    final watched = [for (final id in r['comm_watch'] as List? ?? const []) id as String];
    for (final id in watched) {
      known(id, 'comm_watch');
    }

    final p = jsonDecode(profilesJson) as Map<String, dynamic>;
    final profiles = <GaugeProfile>[];
    for (final j in p['profiles'] as List) {
      final m = j as Map<String, dynamic>;
      final tiles = <GaugeTileSpec>[];
      for (final t in m['tiles'] as List) {
        final tm = t as Map<String, dynamic>;
        final id = tm['signal'] as String;
        known(id, 'gauge profile ${m['id']}');
        final style = GaugeStyle.values.firstWhere((s) => s.name == tm['style'],
            orElse: () => throw FormatException('gauge profile ${m['id']}: bad style ${tm['style']}'));
        tiles.add(GaugeTileSpec(id, style));
      }
      if (tiles.isEmpty || tiles.length > maxTilesPerProfile) {
        throw FormatException('gauge profile ${m['id']}: 1..$maxTilesPerProfile tiles');
      }
      profiles.add(GaugeProfile(m['id'] as String, m['name'] as String, tiles));
    }
    if (profiles.isEmpty) throw const FormatException('no gauge profiles');

    final calibrations = <String, Calibration>{};
    if (calibrationJson != null) {
      final c = jsonDecode(calibrationJson) as Map<String, dynamic>;
      for (final MapEntry(key: id, value: j) in (c['signals'] as Map<String, dynamic>? ?? {}).entries) {
        known(id, 'calibration');
        if (signals[id]!.isComputed) {
          throw FormatException('calibration $id: computed signals follow their inputs; calibrate those');
        }
        calibrations[id] = Calibration.fromJson(id, j as Map<String, dynamic>);
      }
    }
    return AppConfig(
        rules: rules, watched: watched, profiles: profiles, calibrations: calibrations);
  }
}
