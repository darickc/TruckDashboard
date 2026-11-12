import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';
import 'package:latlong2/latlong.dart';

import '../data/gateway_connection.dart';
import '../gen/f250/nav/v1/places.pbgrpc.dart' as pb;
import '../gen/f250/nav/v1/route.pb.dart' as route_pb;
import 'places_state.dart';

PlacesSource createGrpcPlacesSource(GatewayEndpoint endpoint) => GrpcPlacesSource(endpoint: endpoint);

/// services/navigation's `PlacesService` over gRPC. One call per request;
/// every change answers with all the places, which replace the old ones.
class GrpcPlacesSource implements PlacesSource {
  GrpcPlacesSource({required this.endpoint, this.timeout = const Duration(seconds: 5)});

  final GatewayEndpoint endpoint;
  final Duration timeout;

  ClientChannel? _channel;
  pb.PlacesServiceClient? _client;

  final _state = ValueNotifier(const PlacesView(link: PlacesLink.connecting));

  @override
  ValueListenable<PlacesView> get state => _state;

  @override
  void start() {
    if (_channel != null) return;
    final (host, port) = switch (endpoint) {
      UnixEndpoint(:final path) => (InternetAddress(path, type: InternetAddressType.unix), 0),
      TcpEndpoint(:final host, :final port) => (host as Object, port),
    };
    _channel = ClientChannel(
      host,
      port: port,
      options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
    );
    _client = pb.PlacesServiceClient(_channel!);
    refresh();
  }

  @override
  void stop() {
    _channel?.shutdown();
    _channel = null;
    _client = null;
  }

  CallOptions get _options => CallOptions(timeout: timeout);

  @override
  Future<void> refresh() async {
    final client = _client;
    if (client == null) return;
    try {
      final r = await client.listPlaces(pb.ListPlacesRequest(), options: _options);
      _state.value = placesFromPb(r.places);
    } catch (e) {
      _state.value = PlacesView(link: PlacesLink.lost, detail: 'navigation service unavailable: ${_why(e)}');
    }
  }

  /// Runs a change; its answer replaces the places. Null, or why not.
  Future<String?> _change(Future<pb.Places> Function(pb.PlacesServiceClient c) call) async {
    final client = _client;
    if (client == null) return 'not connected to the navigation service';
    try {
      _state.value = placesFromPb(await call(client));
      return null;
    } catch (e) {
      return _why(e);
    }
  }

  @override
  Future<String?> save(PlaceKind kind, String name, LatLng at, {String detail = ''}) => _change(
    (c) async => (await c.savePlace(
      pb.SavePlaceRequest(
        kind: kind == PlaceKind.home ? pb.PlaceKind.PLACE_KIND_HOME : pb.PlaceKind.PLACE_KIND_FAVOURITE,
        name: name,
        detail: detail,
        location: route_pb.LatLon(latitudeDeg: at.latitude, longitudeDeg: at.longitude),
      ),
      options: _options,
    )).places,
  );

  @override
  Future<String?> rename(int id, String name) => _change(
    (c) async => (await c.renamePlace(pb.RenamePlaceRequest(id: Int64(id), name: name), options: _options)).places,
  );

  @override
  Future<String?> delete(int id) =>
      _change((c) async => (await c.deletePlace(pb.DeletePlaceRequest(id: Int64(id)), options: _options)).places);
}

String _why(Object e) => e is GrpcError ? (e.message ?? e.codeName) : '$e';

/// navigation's places as the dashboard's model. A place without a location
/// is left out; an unknown kind (a newer service) reads as a recent one.
PlacesView placesFromPb(pb.Places p) {
  Place? place(pb.Place x) => x.hasLocation()
      ? Place(
          id: x.id.toInt(),
          kind: switch (x.kind) {
            pb.PlaceKind.PLACE_KIND_HOME => PlaceKind.home,
            pb.PlaceKind.PLACE_KIND_FAVOURITE => PlaceKind.favourite,
            _ => PlaceKind.recent,
          },
          name: x.name,
          detail: x.detail,
          location: LatLng(x.location.latitudeDeg, x.location.longitudeDeg),
        )
      : null;
  return PlacesView(
    link: PlacesLink.connected,
    home: p.hasHome() ? place(p.home) : null,
    favourites: List.unmodifiable(p.favourites.map(place).nonNulls),
    recents: List.unmodifiable(p.recents.map(place).nonNulls),
    writable: p.storage.writable,
    location: p.storage.location,
    problem: p.storage.problem,
    maxFavourites: p.maxFavourites == 0 ? 50 : p.maxFavourites,
    maxNameChars: p.maxNameChars == 0 ? 40 : p.maxNameChars,
  );
}
