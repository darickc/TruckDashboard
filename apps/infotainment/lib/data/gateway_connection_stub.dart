import '../telemetry/telemetry_store.dart';
import 'gateway_connection.dart';

/// Web builds have no sockets; the browser preview uses the in-app simulator.
GatewayConnection createGatewayConnection(TelemetryStore store, GatewayEndpoint endpoint) =>
    throw UnsupportedError('The vehicle gateway is not reachable from a web build');
