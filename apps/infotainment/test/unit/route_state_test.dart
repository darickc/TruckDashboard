import 'package:f250_infotainment/gen/f250/nav/v1/route.pb.dart' as pb;
import 'package:f250_infotainment/model/units.dart';
import 'package:f250_infotainment/nav/grpc_route_source.dart';
import 'package:f250_infotainment/nav/route_state.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

pb.Guidance active({bool withProgress = true}) => pb.Guidance(
  state: pb.RouteState.ROUTE_STATE_ACTIVE,
  routeId: Int64(7),
  destination: pb.LatLon(latitudeDeg: 39.8103, longitudeDeg: -98.5559),
  progress: withProgress
      ? pb.Progress(
          maneuverIndex: 3,
          toManeuverM: 412.5,
          remainingM: 19876,
          remainingS: 845,
          offRouteM: 4.2,
        )
      : null,
  reroutes: 1,
);

void main() {
  group('guidanceFromPb', () {
    test('an active route with progress', () {
      final g = guidanceFromPb(active(), const Duration(seconds: 9));
      expect(g.state, RouteState.active);
      expect(g.receivedAt, const Duration(seconds: 9));
      expect(g.routeId, 7);
      expect(g.destination, const LatLng(39.8103, -98.5559));
      expect(g.progress!.maneuverIndex, 3);
      expect(g.progress!.toManeuverM, 412.5);
      expect(g.progress!.remainingS, 845);
      expect(g.progress!.offRoute, isFalse);
      expect(g.reroutes, 1);
    });

    test('every state maps; idle has no destination or progress', () {
      final states = {
        pb.RouteState.ROUTE_STATE_UNAVAILABLE: RouteState.unavailable,
        pb.RouteState.ROUTE_STATE_IDLE: RouteState.idle,
        pb.RouteState.ROUTE_STATE_ROUTING: RouteState.routing,
        pb.RouteState.ROUTE_STATE_ACTIVE: RouteState.active,
        pb.RouteState.ROUTE_STATE_FAILED: RouteState.failed,
        pb.RouteState.ROUTE_STATE_ARRIVED: RouteState.arrived,
      };
      for (final MapEntry(:key, :value) in states.entries) {
        expect(guidanceFromPb(pb.Guidance(state: key), Duration.zero).state, value);
      }
      final idle = guidanceFromPb(pb.Guidance(state: pb.RouteState.ROUTE_STATE_IDLE), Duration.zero);
      expect(idle.destination, isNull);
      expect(idle.progress, isNull);
    });

    test('an unknown state reads as unavailable, never as a route', () {
      final g = guidanceFromPb(
        pb.Guidance(state: pb.RouteState.ROUTE_STATE_UNSPECIFIED, routeId: Int64(3)),
        Duration.zero,
      );
      expect(g.state, RouteState.unavailable);
      expect(g.routeId, 0);
      expect(g.detail, contains("doesn't know"));
    });

    test('progress is ignored outside an active route', () {
      final g = guidanceFromPb(
        active()..state = pb.RouteState.ROUTE_STATE_ROUTING,
        Duration.zero,
      );
      expect(g.progress, isNull);
    });
  });

  test('routeFromPb', () {
    final r = routeFromPb(
      pb.Route(
        id: Int64(7),
        shape: [
          pb.LatLon(latitudeDeg: 39.7792, longitudeDeg: -98.7851),
          pb.LatLon(latitudeDeg: 39.7791, longitudeDeg: -98.7851),
        ],
        maneuvers: [
          pb.Maneuver(
            type: 10,
            instruction: 'Turn right onto US 36/US 281.',
            streetNames: ['US 36', 'US 281'],
            lengthM: 18989,
            timeS: 686.138,
            beginShapeIndex: 11,
            startM: 751,
          ),
        ],
        lengthM: 23351,
        timeS: 922.621,
        destination: pb.LatLon(latitudeDeg: 39.8103, longitudeDeg: -98.5559),
        costing: 'auto',
        hasHighway: true,
      ),
    );
    expect(r.id, 7);
    expect(r.shape, hasLength(2));
    expect(r.shape.first, const LatLng(39.7792, -98.7851));
    expect(r.maneuvers.single.streetNames, ['US 36', 'US 281']);
    expect(r.maneuvers.single.startM, 751);
    expect(r.costing, 'auto');
    expect(r.hasHighway, isTrue);
    expect(r.hasToll, isFalse);
  });

  group('RouteView: progress is shown as current only while fresh', () {
    const at = Duration(seconds: 10);
    final g = guidanceFromPb(active(), at);

    test('fresh and linked: current', () {
      final v = RouteView(link: RouteLink.connected, guidance: g);
      expect(v.currentProgress(at + const Duration(seconds: 3)), isNotNull);
      expect(v.pausedWhy(at), isNull);
    });

    test('no message for more than 3 s: paused, and why', () {
      final v = RouteView(link: RouteLink.connected, guidance: g);
      final later = at + const Duration(seconds: 4);
      expect(v.currentProgress(later), isNull);
      expect(v.pausedWhy(later), 'no update from the navigation service for 4 s');
    });

    test('link lost: paused at once', () {
      final v = RouteView(link: RouteLink.lost, guidance: g, detail: 'connection refused');
      expect(v.currentProgress(at), isNull);
      expect(v.pausedWhy(at), 'navigation service unavailable: connection refused');
    });

    test('the service sent no progress (no current position): its reason', () {
      final v = RouteView(
        link: RouteLink.connected,
        guidance: guidanceFromPb(active(withProgress: false)..detail = 'waiting for a GPS fix', at),
      );
      expect(v.currentProgress(at), isNull);
      expect(v.pausedWhy(at), 'waiting for a GPS fix');
    });

    test('not active: nothing to pause', () {
      final v = RouteView(
        link: RouteLink.lost,
        guidance: Guidance(state: RouteState.routing, receivedAt: at),
      );
      expect(v.pausedWhy(at), isNull);
      expect(v.currentProgress(at), isNull);
    });
  });

  test('UnavailableRouteSource says why, and never routes', () async {
    final src = UnavailableRouteSource('no Valhalla here');
    expect(src.state.value.state, RouteState.unavailable);
    expect(src.state.value.guidance!.detail, 'no Valhalla here');
    await src.setDestination(const LatLng(39.8, -98.5));
    expect(src.state.value.state, RouteState.unavailable);
    expect(src.state.value.route, isNull);
  });

  group('formatDistance', () {
    test('imperial: feet to 50 under 0.1 mi, else miles to 0.1', () {
      expect(formatDistance(0, UnitSystem.imperial), '0 ft');
      expect(formatDistance(100, UnitSystem.imperial), '350 ft'); // 328 ft
      expect(formatDistance(160, UnitSystem.imperial), '500 ft'); // 524.9 ft
      expect(formatDistance(161, UnitSystem.imperial), '0.1 mi');
      expect(formatDistance(19876, UnitSystem.imperial), '12.4 mi');
    });

    test('metric: metres to 10 under 1 km, else km to 0.1', () {
      expect(formatDistance(4, UnitSystem.metric), '0 m');
      expect(formatDistance(412.5, UnitSystem.metric), '410 m');
      expect(formatDistance(996, UnitSystem.metric), '1.0 km');
      expect(formatDistance(19876, UnitSystem.metric), '19.9 km');
    });

    test('nonsense reads as zero', () {
      expect(formatDistance(-5, UnitSystem.metric), '0 m');
      expect(formatDistance(double.nan, UnitSystem.imperial), '0 ft');
    });
  });

  test('formatDuration: minutes, then hours; no clock time', () {
    expect(formatDuration(0), '< 1 min');
    expect(formatDuration(29), '< 1 min');
    expect(formatDuration(845), '14 min');
    expect(formatDuration(3540), '59 min');
    expect(formatDuration(3900), '1 h 05 min');
    expect(formatDuration(36000), '10 h 00 min');
  });
}
