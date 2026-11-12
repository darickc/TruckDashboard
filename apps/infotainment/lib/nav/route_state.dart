import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/clock.dart';
import '../model/units.dart';

/// Routing and guidance as services/navigation reports them (f250.nav.v1
/// RouteService, Phase 6.5.2, ADR-0035). The dashboard never talks to
/// Valhalla. Routes are not checked for heavy vehicles or trailers
/// (ADR-0010); the screen says so with every route.
enum RouteState { unavailable, idle, routing, active, failed, arrived }

enum RouteLink { connecting, connected, lost }

/// Where the truck is along the route. The service sends it only while the
/// position is current.
@immutable
class RouteProgress {
  const RouteProgress({
    required this.maneuverIndex,
    required this.toManeuverM,
    required this.remainingM,
    required this.remainingS,
    this.offRouteM = 0,
    this.offRoute = false,
  });

  /// The next maneuver, an index into [NavRoute.maneuvers].
  final int maneuverIndex;
  final double toManeuverM;
  final double remainingM;
  final double remainingS;
  final double offRouteM;
  final bool offRoute;
}

/// One guidance message.
@immutable
class Guidance {
  const Guidance({
    required this.state,
    required this.receivedAt,
    this.routeId = 0,
    this.destination,
    this.progress,
    this.detail = '',
    this.reroutes = 0,
  });

  final RouteState state;

  /// When it arrived, on the dashboard's monotonic clock.
  final Duration receivedAt;

  /// The route on screen, 0 for none.
  final int routeId;
  final LatLng? destination;
  final RouteProgress? progress;

  /// Why: unavailable, failed, waiting for a position, rerouting.
  final String detail;
  final int reroutes;
}

@immutable
class Maneuver {
  const Maneuver({
    required this.type,
    required this.instruction,
    this.streetNames = const [],
    this.lengthM = 0,
    this.timeS = 0,
    this.beginShapeIndex = 0,
    this.startM = 0,
  });

  /// Valhalla's maneuver type (odin), for the icon.
  final int type;

  /// Valhalla's text, e.g. "Turn right onto US 36/US 281."
  final String instruction;
  final List<String> streetNames;
  final double lengthM;
  final double timeS;
  final int beginShapeIndex;

  /// Distance from the route's start to this maneuver.
  final double startM;
}

/// A route from Valhalla. Named so it doesn't clash with Flutter's Route.
@immutable
class NavRoute {
  const NavRoute({
    required this.id,
    required this.shape,
    required this.maneuvers,
    required this.lengthM,
    required this.timeS,
    this.destination,
    this.costing = '',
    this.hasToll = false,
    this.hasHighway = false,
    this.hasFerry = false,
  });

  final int id;
  final List<LatLng> shape;
  final List<Maneuver> maneuvers;
  final double lengthM;
  final double timeS;
  final LatLng? destination;

  /// Valhalla's costing model: "auto", or "truck".
  final String costing;
  final bool hasToll;
  final bool hasHighway;
  final bool hasFerry;
}

/// What the screen shows: the link to navigation, its last guidance, and
/// the route that guidance names (once fetched).
@immutable
class RouteView {
  const RouteView({
    required this.link,
    this.guidance,
    this.route,
    this.detail = '',
    this.commandError = '',
  });

  /// The service sends guidance at least once a second; older than this,
  /// nothing from it is shown as current (CLAUDE.md rule 4).
  static const freshFor = Duration(seconds: 3);

  final RouteLink link;

  /// Kept while the link is down, so the screen can say what it last knew.
  final Guidance? guidance;

  /// The route [Guidance.routeId] names, or the previous one until it
  /// arrives. Null without a route.
  final NavRoute? route;

  /// Why the link is down.
  final String detail;

  /// The last SetDestination or ClearRoute that failed, for the screen.
  final String commandError;

  RouteState? get state => guidance?.state;

  RouteView copyWith({
    RouteLink? link,
    Guidance? guidance,
    NavRoute? route,
    bool dropRoute = false,
    String? detail,
    String? commandError,
  }) => RouteView(
    link: link ?? this.link,
    guidance: guidance ?? this.guidance,
    route: dropRoute ? null : (route ?? this.route),
    detail: detail ?? this.detail,
    commandError: commandError ?? this.commandError,
  );

  /// Linked, and the last message is recent.
  bool isFresh(Duration now) {
    final g = guidance;
    return link == RouteLink.connected && g != null && now - g.receivedAt <= freshFor;
  }

  /// Progress that may be shown as current: fresh, on an active route, and
  /// the service sent it (it does only with a current position).
  RouteProgress? currentProgress(Duration now) {
    final g = guidance;
    if (g == null || g.state != RouteState.active || !isFresh(now)) return null;
    return g.progress;
  }

  /// Why guidance is paused, while on an active route without current
  /// progress. Null when it isn't.
  String? pausedWhy(Duration now) {
    final g = guidance;
    if (g == null || g.state != RouteState.active) return null;
    switch (link) {
      case RouteLink.connecting:
        return 'connecting to the navigation service';
      case RouteLink.lost:
        return 'navigation service unavailable${detail.isEmpty ? '' : ': $detail'}';
      case RouteLink.connected:
        final since = now - g.receivedAt;
        if (since > freshFor) return 'no update from the navigation service for ${since.inSeconds} s';
        if (g.progress == null) return g.detail.isEmpty ? 'waiting for a current position' : g.detail;
        return null;
    }
  }
}

abstract class RouteSource {
  ValueListenable<RouteView> get state;

  /// The clock [Guidance.receivedAt] is on.
  MonotonicClock get clock;
  void start();
  void stop();

  /// Routes from the current position to [to], replacing any route. Never
  /// throws: a failure shows in [RouteView.commandError].
  Future<void> setDestination(LatLng to);

  /// Drops the destination and the route. Never throws.
  Future<void> clearRoute();
}

/// No navigation service (the in-app simulator, the browser preview):
/// routing is unavailable, and says why. Never a fake route.
class UnavailableRouteSource implements RouteSource {
  UnavailableRouteSource([this.why = 'needs services/navigation (make sim)', MonotonicClock? clock])
    : clock = clock ?? SystemMonotonicClock();

  final String why;

  @override
  final MonotonicClock clock;

  late final _state = ValueNotifier(
    RouteView(
      link: RouteLink.connected,
      guidance: Guidance(state: RouteState.unavailable, receivedAt: Duration.zero, detail: why),
    ),
  );

  @override
  ValueListenable<RouteView> get state => _state;

  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<void> setDestination(LatLng to) async {}
  @override
  Future<void> clearRoute() async {}
}

const _metresPerMile = 1609.344;
const _feetPerMetre = 3.280839895;

/// A distance for the guidance banner: feet (to 50) under 0.1 mi, else miles
/// to 0.1; metres (to 10) under 1 km, else km to 0.1.
String formatDistance(double metres, UnitSystem units) {
  final m = metres.isFinite && metres > 0 ? metres : 0.0;
  switch (units) {
    case UnitSystem.imperial:
      if (m < 0.1 * _metresPerMile) {
        return '${((m * _feetPerMetre) / 50).round() * 50} ft';
      }
      return '${(m / _metresPerMile).toStringAsFixed(1)} mi';
    case UnitSystem.metric:
      final rounded = (m / 10).round() * 10;
      if (rounded < 1000) return '$rounded m';
      return '${(m / 1000).toStringAsFixed(1)} km';
  }
}

/// A duration for the banner: "18 min", "1 h 05 min". No clock time: the
/// Pi has no clock source in the truck.
String formatDuration(double seconds) {
  final s = seconds.isFinite && seconds > 0 ? seconds : 0.0;
  final minutes = (s / 60).round();
  if (minutes < 1) return '< 1 min';
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')} min';
}
