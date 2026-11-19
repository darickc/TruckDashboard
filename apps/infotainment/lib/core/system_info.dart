import 'package:flutter/foundation.dart';

import 'system_info_stub.dart' if (dart.library.io) 'system_info_io.dart' as impl;

/// The commit this dashboard was built from: `make deploy` sets it
/// (`F250_COMMIT`, with "+changes" for a build of uncommitted files), and so
/// does the image's recipe. Empty in other builds.
const kBuildCommit = String.fromEnvironment('F250_COMMIT');

/// [commit] (a hash, perhaps with "+changes") as "commit 1234567" or
/// "commit 1234567 (uncommitted changes)"; null when it isn't one.
String? describeCommit(String commit) {
  final m = RegExp(r'^([0-9a-fA-F]{7,40})(\+changes)?$').firstMatch(commit.trim());
  if (m == null) return null;
  return 'commit ${m.group(1)!.substring(0, 7).toLowerCase()}${m.group(2) == null ? '' : ' (uncommitted changes)'}';
}

/// The dashboard's own build, from [kBuildCommit] (or [commit] in tests).
Fact<String> dashboardCommit([String commit = kBuildCommit]) {
  final d = describeCommit(commit);
  return d == null ? const Fact.unknown('not recorded in this build') : Fact.known(d);
}

/// One fact about the head unit, or why it isn't known. Never a made-up
/// value: a file that isn't there is said to be missing.
@immutable
class Fact<T> {
  const Fact.known(T this.value) : why = '';
  const Fact.unknown(this.why) : value = null;

  final T? value;
  final String why;

  bool get known => value != null;
}

/// What the dashboard can read about the head unit it runs on (Settings ›
/// System). From files the image provides; none of it is vehicle data.
@immutable
class SystemFacts {
  const SystemFacts({
    this.dashboard = const Fact.unknown('not recorded in this build'),
    required this.commit,
    required this.image,
    required this.uptime,
    required this.cpuTemperature,
  });

  /// The commit this dashboard was built from ([kBuildCommit]). It can be
  /// newer than the image's: `make deploy` sideloads it.
  final Fact<String> dashboard;

  /// The commit the image was built from (`F250_SRCREV` in
  /// `/etc/f250-release`, written by f250-system).
  final Fact<String> commit;

  /// The operating system (`PRETTY_NAME` in `/etc/os-release`).
  final Fact<String> image;

  /// Time since boot (`/proc/uptime`).
  final Fact<Duration> uptime;

  /// The first thermal zone (`/sys/class/thermal/thermal_zone0`), °C, with
  /// its type ("cpu-thermal" on the bench Pi 5: bench log 2026-11-19).
  final Fact<({double celsius, String zone})> cpuTemperature;

  static SystemFacts unavailable(String why) => SystemFacts(
        dashboard: dashboardCommit(),
        commit: Fact.unknown(why),
        image: Fact.unknown(why),
        uptime: Fact.unknown(why),
        cpuTemperature: Fact.unknown(why),
      );
}

abstract class SystemInfo {
  /// Reads the facts now. Never throws: what can't be read says why.
  Future<SystemFacts> read();

  /// The files on Linux; nothing in the browser.
  static SystemInfo forPlatform() => impl.platformSystemInfo();
}

/// Facts set by a test.
class FixedSystemInfo implements SystemInfo {
  FixedSystemInfo(this.facts);

  SystemFacts facts;

  @override
  Future<SystemFacts> read() async => facts;
}

/// `F250_SRCREV=<sha>` → the short commit, or null.
String? parseRelease(String text) {
  for (final line in text.split('\n')) {
    final m = RegExp(r'^\s*F250_SRCREV\s*=\s*"?([0-9a-fA-F]{7,40})"?\s*$').firstMatch(line);
    if (m != null) return m.group(1)!.substring(0, 7).toLowerCase();
  }
  return null;
}

/// os-release(5): `PRETTY_NAME`, unquoted, or null.
String? parseOsRelease(String text) {
  for (final line in text.split('\n')) {
    final m = RegExp(r'^\s*PRETTY_NAME\s*=\s*(.*)$').firstMatch(line);
    if (m == null) continue;
    var v = m.group(1)!.trim();
    if (v.length >= 2 && (v.startsWith('"') || v.startsWith("'")) && v.endsWith(v[0])) {
      v = v.substring(1, v.length - 1);
    }
    return v.isEmpty ? null : v;
  }
  return null;
}

/// proc(5): the first number of `/proc/uptime`, seconds.
Duration? parseUptime(String text) {
  final s = double.tryParse(text.trim().split(RegExp(r'\s+')).first);
  if (s == null || s < 0 || !s.isFinite) return null;
  return Duration(milliseconds: (s * 1000).round());
}

/// A thermal zone's `temp`: millidegrees Celsius, or null.
double? parseThermal(String text) {
  final m = int.tryParse(text.trim());
  if (m == null) return null;
  final c = m / 1000;
  // Outside what a running board can read: not a temperature.
  return c < -40 || c > 150 ? null : c;
}

/// "45 s", "12 min", "3 h 12 min", "2 d 4 h".
String formatUptime(Duration d) {
  if (d.inMinutes < 1) return '${d.inSeconds} s';
  if (d.inHours < 1) return '${d.inMinutes} min';
  if (d.inDays < 1) return '${d.inHours} h ${d.inMinutes % 60} min';
  return '${d.inDays} d ${d.inHours % 24} h';
}
