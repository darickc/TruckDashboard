import '../data/gateway_connection.dart';
import 'position_state.dart';

/// Web builds have no sockets; the browser preview uses SimulatedPositionSource.
PositionSource createGrpcPositionSource(GatewayEndpoint endpoint) =>
    throw UnsupportedError('the navigation service is not reachable from a web build');
