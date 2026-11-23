import '../data/gateway_connection.dart';
import 'online_map_connection_stub.dart' if (dart.library.io) 'grpc_online_map_source.dart' as impl;
import 'online_map.dart';

/// services/navigation's online map (Mapbox's tiles, ADR-0052) over gRPC at
/// [endpoint]. Not available on the web build: throws UnsupportedError there.
OnlineMapSource connectOnlineMap(GatewayEndpoint endpoint) => impl.createGrpcOnlineMapSource(endpoint);
