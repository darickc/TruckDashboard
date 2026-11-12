import '../data/gateway_connection.dart';
import 'search_connection_stub.dart' if (dart.library.io) 'grpc_search_source.dart' as impl;
import 'search_state.dart';

/// services/navigation's search API over gRPC at [endpoint]. Not available
/// on the web build (no sockets): throws UnsupportedError there.
SearchSource connectSearch(GatewayEndpoint endpoint) => impl.createGrpcSearchSource(endpoint);
