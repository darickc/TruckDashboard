import '../data/gateway_connection.dart';
import 'display_state.dart';

/// Web builds have no sockets; the browser preview uses SimulatedDisplaySource.
DisplaySource createGrpcDisplaySource(GatewayEndpoint endpoint) =>
    throw UnsupportedError('power-manager is not reachable from a web build');
