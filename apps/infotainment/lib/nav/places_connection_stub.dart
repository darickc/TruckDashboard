import '../data/gateway_connection.dart';
import 'places_state.dart';

/// Web builds have no sockets; the browser preview uses UnavailablePlacesSource.
PlacesSource createGrpcPlacesSource(GatewayEndpoint endpoint) =>
    throw UnsupportedError('the navigation service is not reachable from a web build');
