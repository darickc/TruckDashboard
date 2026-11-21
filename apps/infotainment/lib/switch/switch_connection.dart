import '../data/gateway_connection.dart';
import 'switch_connection_stub.dart' if (dart.library.io) 'grpc_switch_source.dart' as impl;
import 'switch_state.dart';

/// power-manager's 5-way switch API over gRPC at [endpoint]. Not available
/// on the web build (no sockets): throws UnsupportedError there.
SwitchSource connectSwitch(GatewayEndpoint endpoint) => impl.createGrpcSwitchSource(endpoint);
