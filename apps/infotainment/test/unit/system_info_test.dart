import 'dart:io';

import 'package:f250_infotainment/core/system_info.dart';
import 'package:f250_infotainment/core/system_info_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// What Settings › System reads about the head unit, from the files the
/// image provides.
void main() {
  test('f250-release: the short commit', () {
    expect(parseRelease('F250_SRCREV=6123c19d8e7f0a1b2c3d4e5f60718293a4b5c6d7\n'), '6123c19');
    expect(parseRelease('# comment\nF250_SRCREV="ABCDEF1234"\n'), 'abcdef1');
    expect(parseRelease('F250_SRCREV=\n'), isNull, reason: 'empty: not a commit');
    expect(parseRelease('OTHER=1\n'), isNull);
  });

  test('os-release: PRETTY_NAME, unquoted', () {
    expect(parseOsRelease('ID=agl\nPRETTY_NAME="Automotive Grade Linux 22.0.1 (vimba)"\n'),
        'Automotive Grade Linux 22.0.1 (vimba)');
    expect(parseOsRelease("PRETTY_NAME='Debian'\n"), 'Debian');
    expect(parseOsRelease('PRETTY_NAME=Plain\n'), 'Plain');
    expect(parseOsRelease('NAME=x\n'), isNull);
  });

  test('uptime: the first number, seconds', () {
    expect(parseUptime('12345.67 54321.00\n'), const Duration(milliseconds: 12345670));
    expect(parseUptime('nonsense'), isNull);
    expect(parseUptime('-1 0'), isNull);
  });

  test('thermal: millidegrees; impossible readings refused', () {
    expect(parseThermal('52650\n'), 52.65);
    expect(parseThermal('200000'), isNull);
    expect(parseThermal('x'), isNull);
  });

  test('uptime reads as seconds, minutes, hours or days', () {
    expect(formatUptime(const Duration(seconds: 45)), '45 s');
    expect(formatUptime(const Duration(minutes: 12, seconds: 5)), '12 min');
    expect(formatUptime(const Duration(hours: 3, minutes: 12)), '3 h 12 min');
    expect(formatUptime(const Duration(days: 2, hours: 4, minutes: 9)), '2 d 4 h');
  });

  group('the files', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('system-info'));
    tearDown(() => dir.deleteSync(recursive: true));

    FileSystemInfo info() => FileSystemInfo(
          release: '${dir.path}/f250-release',
          osRelease: '${dir.path}/os-release',
          uptime: '${dir.path}/uptime',
          thermalZone: '${dir.path}/zone0',
        );

    test('every file there: every fact known', () async {
      File('${dir.path}/f250-release').writeAsStringSync('F250_SRCREV=0f2ffac1234567\n');
      File('${dir.path}/os-release').writeAsStringSync('PRETTY_NAME="AGL"\n');
      File('${dir.path}/uptime').writeAsStringSync('600.5 1200.0\n');
      Directory('${dir.path}/zone0').createSync();
      File('${dir.path}/zone0/temp').writeAsStringSync('48000\n');
      File('${dir.path}/zone0/type').writeAsStringSync('cpu-thermal\n');
      final f = await info().read();
      expect(f.commit.value, '0f2ffac');
      expect(f.image.value, 'AGL');
      expect(f.uptime.value, const Duration(milliseconds: 600500));
      expect(f.cpuTemperature.value, (celsius: 48.0, zone: 'cpu-thermal'));
    });

    test('a missing file says which, never a value', () async {
      File('${dir.path}/uptime').writeAsStringSync('garbage');
      final f = await info().read();
      expect(f.commit.known, isFalse);
      expect(f.commit.why, 'no ${dir.path}/f250-release');
      expect(f.uptime.why, '${dir.path}/uptime unreadable');
      expect(f.cpuTemperature.known, isFalse);
    });
  });
}
