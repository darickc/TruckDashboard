import '../data/gateway_connection.dart';
import 'position_connection_stub.dart' if (dart.library.io) 'grpc_position_source.dart' as impl;
import 'position_state.dart';

/// services/navigation's position API over gRPC at [endpoint]. Not
/// available on the web build (no sockets): throws UnsupportedError there.
PositionSource connectNavigation(GatewayEndpoint endpoint) =>
    impl.createGrpcPositionSource(endpoint);
