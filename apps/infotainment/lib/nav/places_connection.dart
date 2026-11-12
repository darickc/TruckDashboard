import '../data/gateway_connection.dart';
import 'places_connection_stub.dart' if (dart.library.io) 'grpc_places_source.dart' as impl;
import 'places_state.dart';

/// services/navigation's saved places over gRPC at [endpoint]. Not available
/// on the web build (no sockets): throws UnsupportedError there.
PlacesSource connectPlaces(GatewayEndpoint endpoint) => impl.createGrpcPlacesSource(endpoint);
