import 'dart:async';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';
import 'package:latlong2/latlong.dart';

import '../core/clock.dart';
import '../data/gateway_connection.dart';
import '../gen/f250/nav/v1/route.pbgrpc.dart' as pb;
import 'route_state.dart';

RouteSource createGrpcRouteSource(GatewayEndpoint endpoint) => GrpcRouteSource(endpoint: endpoint);

/// services/navigation's routing over gRPC (`WatchGuidance`, `GetRoute`,
/// `SetDestination`, `ClearRoute`). Reconnects on its own. While it is down
/// the last guidance and route are kept, so the screen can say guidance is
/// paused rather than lose the route.
class GrpcRouteSource implements RouteSource {
  GrpcRouteSource({
    required this.endpoint,
    MonotonicClock? clock,
    this.retryDelay = const Duration(seconds: 1),
  }) : clock = clock ?? SystemMonotonicClock();

  final GatewayEndpoint endpoint;
  @override
  final MonotonicClock clock;
  final Duration retryDelay;

  ClientChannel? _channel;
  pb.RouteServiceClient? _client;
  StreamSubscription<pb.WatchGuidanceResponse>? _stream;
  Timer? _retry;
  bool _running = false;

  /// The route id being fetched, so each is asked for once at a time.
  int? _fetching;

  final _state = ValueNotifier(const RouteView(link: RouteLink.connecting));

  @override
  ValueListenable<RouteView> get state => _state;

  @override
  void start() {
    if (_running) return;
    _running = true;
    final (host, port) = switch (endpoint) {
      UnixEndpoint(:final path) => (InternetAddress(path, type: InternetAddressType.unix), 0),
      TcpEndpoint(:final host, :final port) => (host as Object, port),
    };
    _channel = ClientChannel(
      host,
      port: port,
      options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
    );
    _client = pb.RouteServiceClient(_channel!);
    _state.value = RouteView(link: RouteLink.connecting, detail: 'connecting to $endpoint');
    _connect();
  }

  @override
  void stop() {
    _running = false;
    _retry?.cancel();
    _stream?.cancel();
    _channel?.shutdown();
    _stream = null;
    _channel = null;
    _client = null;
  }

  @override
  Future<void> setDestination(LatLng to) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.setDestination(
        pb.SetDestinationRequest(
          destination: pb.LatLon(latitudeDeg: to.latitude, longitudeDeg: to.longitude),
        ),
      );
      _state.value = _state.value.copyWith(commandError: '');
    } catch (e) {
      _state.value = _state.value.copyWith(commandError: 'Couldn\'t set the destination: ${_why(e)}');
    }
  }

  @override
  Future<void> clearRoute() async {
    final client = _client;
    if (client == null) return;
    try {
      await client.clearRoute(pb.ClearRouteRequest());
      _state.value = _state.value.copyWith(commandError: '');
    } catch (e) {
      _state.value = _state.value.copyWith(commandError: 'Couldn\'t end the route: ${_why(e)}');
    }
  }

  void _connect() {
    final client = _client;
    if (!_running || client == null) return;
    _stream = client
        .watchGuidance(pb.WatchGuidanceRequest())
        .listen(
          (r) => _onGuidance(guidanceFromPb(r.guidance, clock.now())),
          onError: (Object e) => _down(_why(e)),
          onDone: () => _down('the navigation service ended the stream'),
        );
  }

  void _onGuidance(Guidance g) {
    final old = _state.value;
    final keep = g.routeId != 0 && old.route != null;
    _state.value = RouteView(
      link: RouteLink.connected,
      guidance: g,
      // The old route stays on screen (drawn as not current) until the new
      // one arrives; none at all once there is no route.
      route: keep ? old.route : null,
      commandError: old.commandError,
    );
    if (g.routeId != 0 && old.route?.id != g.routeId) _fetch(g.routeId);
  }

  void _fetch(int id) {
    final client = _client;
    if (client == null || _fetching == id) return;
    _fetching = id;
    client
        .getRoute(pb.GetRouteRequest(routeId: Int64(id)))
        .then((r) {
          if (_state.value.guidance?.routeId == id) {
            _state.value = _state.value.copyWith(route: routeFromPb(r.route));
          }
        })
        .catchError((Object e) {
          // NOT_FOUND: a newer route replaced it; the next guidance names
          // that one. Anything else is retried on the next message.
          if (!(e is GrpcError && e.code == StatusCode.notFound)) {
            _state.value = _state.value.copyWith(commandError: 'Couldn\'t fetch the route: ${_why(e)}');
          }
        })
        .whenComplete(() {
          if (_fetching == id) _fetching = null;
        });
  }

  void _down(String why) {
    _stream?.cancel();
    _stream = null;
    if (!_running) return;
    _state.value = _state.value.copyWith(link: RouteLink.lost, detail: why);
    _retry?.cancel();
    _retry = Timer(retryDelay, _connect);
  }
}

String _why(Object e) => e is GrpcError ? (e.message ?? e.codeName) : '$e';

/// navigation's guidance as the dashboard's model. An unknown state (a newer
/// service) reads as unavailable, never as a route.
Guidance guidanceFromPb(pb.Guidance g, Duration receivedAt) {
  final state = switch (g.state) {
    pb.RouteState.ROUTE_STATE_IDLE => RouteState.idle,
    pb.RouteState.ROUTE_STATE_ROUTING => RouteState.routing,
    pb.RouteState.ROUTE_STATE_ACTIVE => RouteState.active,
    pb.RouteState.ROUTE_STATE_FAILED => RouteState.failed,
    pb.RouteState.ROUTE_STATE_ARRIVED => RouteState.arrived,
    _ => RouteState.unavailable,
  };
  RouteProgress? progress;
  if (g.hasProgress() && state == RouteState.active) {
    final p = g.progress;
    progress = RouteProgress(
      maneuverIndex: p.maneuverIndex,
      toManeuverM: p.toManeuverM,
      remainingM: p.remainingM,
      remainingS: p.remainingS,
      offRouteM: p.offRouteM,
      offRoute: p.offRoute,
    );
  }
  final unknown = state == RouteState.unavailable && g.state != pb.RouteState.ROUTE_STATE_UNAVAILABLE;
  return Guidance(
    state: state,
    receivedAt: receivedAt,
    routeId: unknown ? 0 : g.routeId.toInt(),
    destination: g.hasDestination() ? _latLng(g.destination) : null,
    progress: progress,
    detail: unknown ? 'the navigation service sent a route state this dashboard doesn\'t know' : g.detail,
    reroutes: g.reroutes,
  );
}

NavRoute routeFromPb(pb.Route r) => NavRoute(
  id: r.id.toInt(),
  shape: [for (final p in r.shape) _latLng(p)],
  maneuvers: [
    for (final m in r.maneuvers)
      Maneuver(
        type: m.type,
        instruction: m.instruction,
        streetNames: List.unmodifiable(m.streetNames),
        lengthM: m.lengthM,
        timeS: m.timeS,
        beginShapeIndex: m.beginShapeIndex,
        startM: m.startM,
      ),
  ],
  lengthM: r.lengthM,
  timeS: r.timeS,
  destination: r.hasDestination() ? _latLng(r.destination) : null,
  costing: r.costing,
  hasToll: r.hasToll,
  hasHighway: r.hasHighway,
  hasFerry: r.hasFerry,
);

LatLng _latLng(pb.LatLon p) => LatLng(p.latitudeDeg, p.longitudeDeg);
