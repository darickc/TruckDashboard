import 'settings_store_stub.dart' if (dart.library.io) 'settings_store_io.dart' as impl;

/// Where the dashboard keeps its own preferences (ADR-0029 decision 2).
abstract class SettingsStore {
  /// The saved preferences, or null when there are none or they can't be
  /// read (then the defaults apply).
  Map<String, Object?>? load();

  /// Saves them whole. Never throws: a failed save is logged, and the
  /// preferences still apply until the app stops.
  void save(Map<String, Object?> values);

  /// The file named by `F250_SETTINGS_FILE`
  /// (`/var/lib/f250-dashboard/settings.json` on AGL), or a store that keeps
  /// nothing (the browser, the Mac window, tests).
  static SettingsStore forPlatform() => impl.platformSettingsStore();
}

/// Keeps nothing: preferences last until the app stops.
class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore([this.values]);

  Map<String, Object?>? values;

  @override
  Map<String, Object?>? load() => values;

  @override
  void save(Map<String, Object?> v) => values = {...v};
}
