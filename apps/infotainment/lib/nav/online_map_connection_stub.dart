import '../data/gateway_connection.dart';
import 'online_map.dart';

/// Web builds have no sockets; the browser preview has no online map.
OnlineMapSource createGrpcOnlineMapSource(GatewayEndpoint endpoint) =>
    throw UnsupportedError('the navigation service is not reachable from a web build');
