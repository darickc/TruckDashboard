import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'settings_store.dart';

SettingsStore platformSettingsStore() {
  final path = Platform.environment['F250_SETTINGS_FILE'];
  return path == null || path.isEmpty ? MemorySettingsStore() : FileSettingsStore(path);
}

/// A JSON file, written whole (temporary file, then renamed) so a power cut
/// leaves the old preferences or the new ones.
class FileSettingsStore implements SettingsStore {
  FileSettingsStore(this.path);

  final String path;

  @override
  Map<String, Object?>? load() {
    try {
      final f = File(path);
      if (!f.existsSync()) return null;
      final v = jsonDecode(f.readAsStringSync());
      return v is Map<String, Object?> ? v : null;
    } catch (e) {
      debugPrint('[settings] $path: $e: the defaults');
      return null;
    }
  }

  @override
  void save(Map<String, Object?> values) {
    try {
      final tmp = File('$path.new');
      tmp.writeAsStringSync(jsonEncode(values), flush: true);
      tmp.renameSync(path);
    } catch (e) {
      debugPrint('[settings] can\'t save $path: $e');
    }
  }
}
