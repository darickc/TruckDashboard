import 'dart:io';

import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/core/settings_store.dart';
import 'package:f250_infotainment/core/settings_store_io.dart';
import 'package:f250_infotainment/model/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preferences are saved on each change and read back', () {
    final store = MemorySettingsStore();
    final a = AppSettings(store: store);
    expect(a.units, UnitSystem.imperial);
    a.units = UnitSystem.metric;
    a.profileId = 'towing';
    expect(store.values, {'units': 'metric', 'profile': 'towing'});
    final b = AppSettings(store: store);
    expect(b.units, UnitSystem.metric);
    expect(b.profileId, 'towing');
  });

  test('unknown or damaged values keep their defaults', () {
    final a = AppSettings(store: MemorySettingsStore({'units': 'furlongs', 'profile': 42}));
    expect(a.units, UnitSystem.imperial);
    expect(a.profileId, isNull);
  });

  test('the file store survives a missing, damaged and good file', () {
    final dir = Directory.systemTemp.createTempSync('f250-settings');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/settings.json';
    final store = FileSettingsStore(path);
    expect(store.load(), isNull);
    File(path).writeAsStringSync('{not json');
    expect(store.load(), isNull);
    File(path).writeAsStringSync('[1, 2]');
    expect(store.load(), isNull);
    store.save({'units': 'metric'});
    expect(store.load(), {'units': 'metric'});
    expect(File('$path.new').existsSync(), isFalse, reason: 'renamed into place');
    // A directory that can't be written: no throw.
    FileSettingsStore('${dir.path}/missing/settings.json').save({'units': 'metric'});
  });
}
