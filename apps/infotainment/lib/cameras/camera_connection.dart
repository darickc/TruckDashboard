import '../data/gateway_connection.dart';
import 'camera_connection_stub.dart' if (dart.library.io) 'grpc_camera_source.dart' as impl;
import 'camera_state.dart';

/// camera-manager over gRPC at [endpoint]. Not available on the web build
/// (no sockets): throws UnsupportedError there.
CameraSource connectCameraManager(GatewayEndpoint endpoint) =>
    impl.createGrpcCameraSource(endpoint);
