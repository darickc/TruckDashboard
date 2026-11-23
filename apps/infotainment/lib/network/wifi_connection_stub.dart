import '../data/gateway_connection.dart';
import 'wifi_state.dart';

/// Web builds have no sockets; the browser preview uses SimulatedWifiSource.
WifiSource createGrpcWifiSource(GatewayEndpoint endpoint) =>
    throw UnsupportedError('the network service is not reachable from a web build');
