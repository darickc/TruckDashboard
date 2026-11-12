import '../data/gateway_connection.dart';
import 'route_state.dart';

/// Web builds have no sockets; the browser preview uses UnavailableRouteSource.
RouteSource createGrpcRouteSource(GatewayEndpoint endpoint) =>
    throw UnsupportedError('the navigation service is not reachable from a web build');
