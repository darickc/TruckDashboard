import '../data/gateway_connection.dart';
import 'search_state.dart';

/// Web builds have no sockets; the browser preview uses UnavailableSearchSource.
SearchSource createGrpcSearchSource(GatewayEndpoint endpoint) =>
    throw UnsupportedError('the navigation service is not reachable from a web build');
