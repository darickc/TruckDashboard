import '../data/gateway_connection.dart';
import 'display_connection_stub.dart' if (dart.library.io) 'grpc_display_source.dart' as impl;
import 'display_state.dart';

/// power-manager's display API over gRPC at [endpoint]. Not available on the
/// web build (no sockets): throws UnsupportedError there.
DisplaySource connectPowerManager(GatewayEndpoint endpoint) =>
    impl.createGrpcDisplaySource(endpoint);
