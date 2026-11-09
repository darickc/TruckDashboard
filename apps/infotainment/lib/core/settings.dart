import 'package:flutter/foundation.dart';

import '../model/units.dart';

enum DayNight { day, night }

/// User preferences. In-memory for Phase 2; persistence and the illumination
/// input (day/night from the headlamp circuit) arrive with the power-manager.
class AppSettings extends ChangeNotifier {
  AppSettings({UnitSystem units = UnitSystem.imperial, DayNight theme = DayNight.night})
      : _units = units,
        _theme = theme;

  UnitSystem _units;
  DayNight _theme;
  String? _profileId;

  UnitSystem get units => _units;
  DayNight get theme => _theme;
  String? get profileId => _profileId;

  set units(UnitSystem v) => _set(() => _units = v);
  set theme(DayNight v) => _set(() => _theme = v);
  set profileId(String? v) => _set(() => _profileId = v);

  void _set(void Function() change) {
    change();
    notifyListeners();
  }
}
