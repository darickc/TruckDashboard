import 'package:flutter/foundation.dart';

import '../model/units.dart';

/// The display's mode, which picks the palette. power-manager decides it
/// (ADR-0028); see display/display_state.dart.
enum DayNight { day, night }

/// User preferences, in memory. Day/night isn't one of them: power-manager
/// owns it (display/display_state.dart).
class AppSettings extends ChangeNotifier {
  AppSettings({UnitSystem units = UnitSystem.imperial}) : _units = units;

  UnitSystem _units;
  String? _profileId;

  UnitSystem get units => _units;
  String? get profileId => _profileId;

  set units(UnitSystem v) => _set(() => _units = v);
  set profileId(String? v) => _set(() => _profileId = v);

  void _set(void Function() change) {
    change();
    notifyListeners();
  }
}
