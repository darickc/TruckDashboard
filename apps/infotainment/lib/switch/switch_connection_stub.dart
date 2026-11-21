import '../data/gateway_connection.dart';
import 'switch_state.dart';

/// Web builds have no sockets; the browser preview uses SimulatedSwitchSource.
SwitchSource createGrpcSwitchSource(GatewayEndpoint endpoint) =>
    throw UnsupportedError('power-manager is not reachable from a web build');
