import 'settings_store.dart';

/// Web builds have no files: preferences last until the page closes.
SettingsStore platformSettingsStore() => MemorySettingsStore();
