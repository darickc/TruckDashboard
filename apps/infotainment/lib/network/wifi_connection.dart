import '../data/gateway_connection.dart';
import 'wifi_connection_stub.dart' if (dart.library.io) 'grpc_wifi_source.dart' as impl;
import 'wifi_state.dart';

/// services/network's Wi-Fi API over gRPC at [endpoint] (ADR-0052). Not
/// available on the web build (no sockets): throws UnsupportedError there.
WifiSource connectWifi(GatewayEndpoint endpoint) => impl.createGrpcWifiSource(endpoint);
