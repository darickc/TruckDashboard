import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/clock.dart';

/// The truck's position as services/navigation reports it (f250.nav.v1,
/// ADR-0030). The dashboard never talks to gpsd.
enum FixStatus { unavailable, noReceiver, receiverSilent, noFix, fix2d, fix3d }

enum PositionLink { connecting, connected, lost }

/// The last good fix, as sent.
@immutable
class FixReport {
  const FixReport({
    required this.lat,
    required this.lon,
    required this.ageAtReceipt,
    this.altitudeM,
    this.speedMps,
    this.trackDeg,
    this.errorM,
    this.utcMs,
  });

  final double lat;
  final double lon;

  /// Its age when the message arrived.
  final Duration ageAtReceipt;
  final double? altitudeM;
  final double? speedMps;

  /// Degrees clockwise from true north.
  final double? trackDeg;

  /// gpsd's estimated horizontal error, metres.
  final double? errorM;
  final int? utcMs;
}

@immutable
class PositionReport {
  const PositionReport({
    required this.status,
    required this.receivedAt,
    required this.current,
    required this.staleAfter,
    this.fix,
    this.satellitesUsed,
    this.satellitesVisible,
    this.source = '',
    this.simulated = false,
    this.detail = '',
  });

  final FixStatus status;

  /// When the message arrived, on the dashboard's monotonic clock.
  final Duration receivedAt;

  /// navigation said the fix was current when it sent this.
  final bool current;
  final Duration staleAfter;
  final FixReport? fix;
  final int? satellitesUsed;
  final int? satellitesVisible;
  final String source;

  /// Never the truck's real position.
  final bool simulated;
  final String detail;
}

/// What the screen shows: the link to navigation and its last report.
@immutable
class PositionState {
  const PositionState({required this.link, this.report, this.detail = ''});

  final PositionLink link;

  /// Kept while the link is down, so the last fix can be shown as stale.
  final PositionReport? report;

  /// Why the link is down.
  final String detail;

  /// The fix's age now, or null without one.
  Duration? fixAge(Duration now) {
    final r = report;
    final f = r?.fix;
    if (r == null || f == null) return null;
    final since = now - r.receivedAt;
    return f.ageAtReceipt + (since.isNegative ? Duration.zero : since);
  }

  /// The fix may be shown as current: linked, navigation said so, and the
  /// message isn't older than the stale limit (a stalled stream can't keep
  /// an old fix current).
  bool isCurrent(Duration now) {
    final r = report;
    if (link != PositionLink.connected || r == null || !r.current || r.fix == null) return false;
    return now - r.receivedAt <= r.staleAfter;
  }

  /// Why there is no current fix, for the screen.
  String why(Duration now) {
    switch (link) {
      case PositionLink.connecting:
        return 'Connecting to the navigation service';
      case PositionLink.lost:
        return 'Navigation service unavailable${detail.isEmpty ? '' : ': $detail'}';
      case PositionLink.connected:
        final r = report;
        if (r == null) return 'Waiting for the navigation service';
        if (r.detail.isNotEmpty) return _capitalised(r.detail);
        if (r.current && now - r.receivedAt > r.staleAfter) {
          return 'No update from the navigation service for ${(now - r.receivedAt).inSeconds} s';
        }
        return 'No GPS fix';
    }
  }
}

String _capitalised(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

abstract class PositionSource {
  ValueListenable<PositionState> get status;

  /// The clock [PositionReport.receivedAt] is on.
  MonotonicClock get clock;
  void start();
  void stop();
}

/// No navigation service: a simulated receiver driving the same loop as
/// `navigation --simulate`, labelled simulated. For the browser preview,
/// the macOS window and tests.
class SimulatedPositionSource implements PositionSource {
  SimulatedPositionSource({
    MonotonicClock? clock,
    this.period = const Duration(seconds: 1),
    this.speedMps = 80 / 3.6,
    this.staleAfter = const Duration(seconds: 3),
    this.autoRun = true,
  }) : clock = clock ?? SystemMonotonicClock();

  @override
  final MonotonicClock clock;
  final Duration period;
  final double speedMps;
  final Duration staleAfter;

  /// False in tests: [step] by hand.
  final bool autoRun;

  /// Same corners as services/navigation/src/sim.rs: an arbitrary loop near
  /// Lebanon, Kansas, not a road.
  static const corners = [
    (39.8097, -98.5556),
    (39.8097, -98.5000),
    (39.8500, -98.5000),
    (39.8500, -98.5556),
  ];

  Timer? _timer;
  Duration? _start;

  final _status = ValueNotifier(const PositionState(link: PositionLink.connecting));

  @override
  ValueListenable<PositionState> get status => _status;

  @override
  void start() {
    _start ??= clock.now();
    step();
    if (autoRun) _timer ??= Timer.periodic(period, (_) => step());
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Sends one report for the clock's current time.
  void step() {
    final now = clock.now();
    final (lat, lon, track) = along(now - (_start ?? now));
    _status.value = PositionState(
      link: PositionLink.connected,
      report: PositionReport(
        status: FixStatus.fix3d,
        receivedAt: now,
        current: true,
        staleAfter: staleAfter,
        fix: FixReport(
          lat: lat,
          lon: lon,
          ageAtReceipt: Duration.zero,
          altitudeM: 560,
          speedMps: speedMps,
          trackDeg: track,
          errorM: 4,
        ),
        satellitesUsed: 9,
        satellitesVisible: 12,
        source: 'simulated',
        simulated: true,
      ),
    );
  }

  (double, double, double) along(Duration elapsed) {
    final n = corners.length;
    final legs = [for (var i = 0; i < n; i++) distanceM(corners[i], corners[(i + 1) % n])];
    final total = legs.reduce((a, b) => a + b);
    var d = (speedMps * elapsed.inMicroseconds / 1e6) % total;
    for (var i = 0; i < n; i++) {
      final (a, b) = (corners[i], corners[(i + 1) % n]);
      if (d <= legs[i] || i == n - 1) {
        final f = legs[i] > 0 ? math.min(d / legs[i], 1.0) : 0.0;
        return (a.$1 + (b.$1 - a.$1) * f, a.$2 + (b.$2 - a.$2) * f, bearingDeg(a, b));
      }
      d -= legs[i];
    }
    return (corners[0].$1, corners[0].$2, 0);
  }
}

const _earthRadiusM = 6371008.8;

double _rad(double d) => d * math.pi / 180;

/// Great-circle distance, metres.
double distanceM((double, double) a, (double, double) b) {
  final (la1, la2) = (_rad(a.$1), _rad(b.$1));
  final h =
      math.pow(math.sin((la2 - la1) / 2), 2) +
      math.cos(la1) * math.cos(la2) * math.pow(math.sin(_rad(b.$2 - a.$2) / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.sqrt(h));
}

/// Initial bearing, degrees clockwise from true north.
double bearingDeg((double, double) a, (double, double) b) {
  final (la1, la2) = (_rad(a.$1), _rad(b.$1));
  final dlo = _rad(b.$2 - a.$2);
  final y = math.sin(dlo) * math.cos(la2);
  final x = math.cos(la1) * math.sin(la2) - math.sin(la1) * math.cos(la2) * math.cos(dlo);
  return (math.atan2(y, x) * 180 / math.pi) % 360;
}
