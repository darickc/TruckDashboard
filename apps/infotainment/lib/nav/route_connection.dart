import '../data/gateway_connection.dart';
import 'route_connection_stub.dart' if (dart.library.io) 'grpc_route_source.dart' as impl;
import 'route_state.dart';

/// services/navigation's routing API over gRPC at [endpoint]. Not available
/// on the web build (no sockets): throws UnsupportedError there.
RouteSource connectRouting(GatewayEndpoint endpoint) => impl.createGrpcRouteSource(endpoint);
