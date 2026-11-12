// The map import's status (ADR-0033) and how the offline map follows it.
import 'package:f250_infotainment/nav/map_update.dart';
import 'package:f250_infotainment/nav/offline_map.dart';
import 'package:f250_infotainment/nav/pmtiles_file.dart';
import 'package:flutter_test/flutter_test.dart';

const fixture = 'test/fixtures/maps/vector-z12-15.pmtiles';

String status(String state,
        {int percent = 0, String id = 'a', String message = 'm', String? at, String? item, List<String>? changed}) =>
    '{"state":"$state","percent":$percent,"message":"$message","id":"$id","device":"/dev/sda1",'
    '${item == null ? '' : '"item":"$item",'}'
    '${changed == null ? '' : '"changed":[${changed.map((c) => '"$c"').join(',')}],'}'
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

    test('routing data on the stick (ADR-0033 amendment)', () {
      // As map-import writes it while copying routing data, and when done.
      final copying = MapUpdateStatus.parse(
        '{"state":"copying","percent":12,"message":"Copying the routing data from USB: leave the stick in",'
        '"id":"20261112T032106Z-22578","device":"/dev/sda1","item":"routing","changed":["map"],'
        '"at":"2026-11-12T03:21:07Z"}',
      )!;
      expect(copying.item, 'routing');
      expect(copying.text, 'Copying routing data from USB: 12%. Leave the stick in.');
      expect(copying.mapChanged, isFalse, reason: 'not finished');
      final done = MapUpdateStatus.parse(
        '{"state":"updated","percent":100,"message":"Routing data updated. The map was already installed. '
        'You can remove the stick.","id":"x","device":"","item":"routing","changed":["routing"],'
        '"at":"2026-11-12T03:21:09Z"}',
      )!;
      expect(done.changed, ['routing']);
      expect(done.mapChanged, isFalse);
      expect(MapUpdateStatus.parse(status('updated', changed: ['map', 'routing']))!.mapChanged, isTrue);
      expect(MapUpdateStatus.parse(status('updated'))!.mapChanged, isTrue,
          reason: 'an import that doesn\'t say what changed only ever imported maps');
      expect(MapUpdateStatus.parse(status('copying'))!.item, 'map');
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

    test('routing data alone doesn\'t reopen the map; with a new map it does', () async {
      await map.load();
      answers.addAll([
        null,
        status('copying', id: 'r', percent: 50, item: 'routing'),
        status('updated', id: 'r', percent: 100, item: 'routing', changed: ['routing']),
        status('updated', id: 'b', percent: 100, item: 'routing', changed: ['map', 'routing']),
      ]);
      await map.checkUpdate();
      await map.checkUpdate();
      expect(map.update.value!.text, 'Copying routing data from USB: 50%. Leave the stick in.');
      await map.checkUpdate();
      expect(map.update.value!.state, MapUpdateState.updated);
      expect(opens, 1);
      await map.checkUpdate();
      expect(opens, 2);
    });

    test('a stick with the installed map is said so, and nothing reopens', () async {
      await map.load();
      final first = (map.state.value as MapReady).reader;
      answers.addAll([
        null,
        status('current', id: 'c', percent: 100, message: 'This map is already installed.'),
      ]);
      await map.checkUpdate();
      await map.checkUpdate();
      expect(map.update.value!.state, MapUpdateState.current);
      expect(map.update.value!.inProgress, isFalse);
      expect(map.update.value!.text, 'This map is already installed.');
      expect(opens, 1);
      expect(identical((map.state.value as MapReady).reader, first), isTrue);
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
