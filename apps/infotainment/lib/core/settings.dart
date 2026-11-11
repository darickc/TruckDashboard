import 'package:flutter/foundation.dart';

import '../model/units.dart';
import 'settings_store.dart';

/// The display's mode, which picks the palette. power-manager decides it
/// (ADR-0028); see display/display_state.dart.
enum DayNight { day, night }

/// The dashboard's own preferences, kept by a [SettingsStore] (ADR-0029
/// decision 2). Day/night isn't one of them: power-manager owns it
/// (display/display_state.dart); nor are the cameras: camera-manager's.
class AppSettings extends ChangeNotifier {
  AppSettings({UnitSystem units = UnitSystem.imperial, SettingsStore? store})
      : _units = units,
        _store = store ?? MemorySettingsStore() {
    final saved = _store.load();
    if (saved == null) return;
    // A value this version doesn't know keeps its default.
    final u = UnitSystem.values.where((v) => v.name == saved['units']);
    if (u.isNotEmpty) _units = u.first;
    final p = saved['profile'];
    if (p is String) _profileId = p;
  }

  final SettingsStore _store;
  UnitSystem _units;
  String? _profileId;

  UnitSystem get units => _units;
  String? get profileId => _profileId;

  set units(UnitSystem v) => _set(() => _units = v);
  set profileId(String? v) => _set(() => _profileId = v);

  void _set(void Function() change) {
    change();
    _store.save({'units': _units.name, 'profile': ?_profileId});
    notifyListeners();
  }
}
