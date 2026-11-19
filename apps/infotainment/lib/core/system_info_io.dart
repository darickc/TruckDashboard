import 'dart:io';

import 'system_info.dart';

SystemInfo platformSystemInfo() => FileSystemInfo();

/// Reads the facts from the files the image provides. A file that isn't
/// there (the Mac window, a Raspberry Pi OS install without the image's
/// files) says so.
class FileSystemInfo implements SystemInfo {
  FileSystemInfo({
    this.release = '/etc/f250-release',
    this.osRelease = '/etc/os-release',
    this.uptime = '/proc/uptime',
    this.thermalZone = '/sys/class/thermal/thermal_zone0',
  });

  final String release, osRelease, uptime, thermalZone;

  static Future<String?> _read(String path) async {
    try {
      return await File(path).readAsString();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<SystemFacts> read() async {
    Fact<T> fact<T>(String path, String? text, T? Function(String) parse) {
      if (text == null) return Fact.unknown('no $path');
      final v = parse(text);
      return v == null ? Fact.unknown('$path unreadable') : Fact.known(v);
    }

    final temp = await _read('$thermalZone/temp');
    final zone = (await _read('$thermalZone/type'))?.trim() ?? '';
    return SystemFacts(
      commit: fact(release, await _read(release), parseRelease),
      image: fact(osRelease, await _read(osRelease), parseOsRelease),
      uptime: fact(uptime, await _read(uptime), parseUptime),
      cpuTemperature: fact('$thermalZone/temp', temp, (t) {
        final c = parseThermal(t);
        return c == null ? null : (celsius: c, zone: zone);
      }),
    );
  }
}
