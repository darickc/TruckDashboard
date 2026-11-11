// The map import's status (ADR-0033) and how the offline map follows it.
import 'package:f250_infotainment/nav/map_update.dart';
import 'package:f250_infotainment/nav/offline_map.dart';
import 'package:f250_infotainment/nav/pmtiles_file.dart';
import 'package:flutter_test/flutter_test.dart';

const fixture = 'test/fixtures/maps/vector-z12-15.pmtiles';

String status(String state, {int percent = 0, String id = 'a', String message = 'm', String? at}) =>
    '{"state":"$state","percent":$percent,"message":"$message","id":"$id","device":"/dev/sda1",'
    '"at":"${at ?? DateTime.now().toUtc().toIso8601String()}"}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MapUpdateStatus', () {
    test('reads what map-import writes', () {
      // A line as agl/rootfs/opt/f250/libexec/map-import writes it.
      final s = MapUpdateStatus.parse(
        '{"state":"copying","percent":43,"message":"Copying the map from USB: leave the stick in",'
        '"id":"20261111T215119Z-74440","device":"/dev/sda1","at":"2026-11-11T21:51:21Z"}',
      )!;
      expect(s.state, MapUpdateState.copying);
      expect(s.percent, 43);
      expect(s.id, '20261111T215119Z-74440');
      expect(s.at, DateTime.utc(2026, 11, 11, 21, 51, 21));
      expect(s.inProgress, isTrue);
      expect(s.text, 'Copying the map from USB: 43%. Leave the stick in.');
    });

    test('anything else is no status', () {
      expect(MapUpdateStatus.parse(''), isNull);
      expect(MapUpdateStatus.parse('not json'), isNull);
      expect(MapUpdateStatus.parse('[1]'), isNull);
      expect(MapUpdateStatus.parse('{"state":"exploded","id":"a"}'), isNull);
      expect(MapUpdateStatus.parse('{"state":"failed"}'), isNull, reason: 'no id');
    });

    test('a finished import shows for ten minutes; one in progress always', () {
      final at = DateTime.utc(2026, 11, 11, 12);
      final done = MapUpdateStatus(
        state: MapUpdateState.updated, percent: 100, message: 'Map updated.', id: 'a', at: at,
      );
      expect(done.shownAt(at.add(const Duration(minutes: 9))), isTrue);
      expect(done.shownAt(at.add(const Duration(minutes: 11))), isFalse);
      final copying = MapUpdateStatus(
        state: MapUpdateState.copying, percent: 5, message: '', id: 'b', at: at,
      );
      expect(copying.shownAt(at.add(const Duration(hours: 2))), isTrue);
      expect(done.text, 'Map updated.');
    });
  });

  group('OfflineMap follows the import', () {
    late List<String?> answers;
    late int opens;
    late OfflineMap map;

    setUp(() {
      answers = [];
      opens = 0;
      map = OfflineMap(
        fixture,
        statusPath: '/run/f250-maps/status.json',
        open: (p) {
          opens++;
          return openPmTilesFile(p);
        },
        readStatus: (_) async => answers.isEmpty ? null : answers.removeAt(0),
      );
    });

    test('an import finished before the dashboard started isn\'t news', () async {
      await map.load();
      answers.add(status('updated', id: 'old', percent: 100));
      await map.checkUpdate();
      expect(map.update.value, isNull);
      expect(opens, 1);
    });

    test('progress shows, and a new map is opened once it is in place', () async {
      await map.load();
      final first = (map.state.value as MapReady).reader;
      answers.addAll([
        null, // no import yet
        status('checking', id: 'n'),
        status('copying', id: 'n', percent: 40),
        status('updated', id: 'n', percent: 100),
        status('updated', id: 'n', percent: 100), // the same import again: no reload
      ]);
      await map.checkUpdate();
      expect(map.update.value, isNull);
      await map.checkUpdate();
      expect(map.update.value!.state, MapUpdateState.checking);
      await map.checkUpdate();
      expect(map.update.value!.percent, 40);
      expect(opens, 1);
      await map.checkUpdate();
      expect(map.update.value!.state, MapUpdateState.updated);
      expect(opens, 2);
      final second = (map.state.value as MapReady).reader;
      expect(identical(first, second), isFalse);
      expect((map.state.value as MapReady).vector!.generation,
          greaterThan(0));
      await map.checkUpdate();
      expect(opens, 2);
    });

    test('a failed import keeps the map and says why', () async {
      await map.load();
      answers.addAll([null, status('failed', id: 'f', message: 'The data drive is full.')]);
      await map.checkUpdate();
      await map.checkUpdate();
      expect(map.update.value!.state, MapUpdateState.failed);
      expect(map.update.value!.text, 'The data drive is full.');
      expect(map.state.value, isA<MapReady>());
      expect(opens, 1);
    });

    test('without a status path nothing is read', () async {
      var reads = 0;
      final m = OfflineMap(fixture, open: openPmTilesFile, readStatus: (_) async {
        reads++;
        return null;
      });
      m.watch();
      await m.checkUpdate();
      expect(reads, 0);
      m.dispose();
    });
  });

  group('PmTilesReader', () {
    test('the data date comes from make map-region\'s metadata', () async {
      final r = await openPmTilesFile(fixture);
      expect(r.dataDate, isNull, reason: 'the fixture is a plain Protomaps extract');
      await r.close();
    });

    test('a closed reader can\'t read', () async {
      final r = await openPmTilesFile(fixture);
      await r.close();
      expect(() => r.tile(12, 926, 1553), throwsA(anything));
    });
  });
}
