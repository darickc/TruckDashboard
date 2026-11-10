import '../data/gateway_connection.dart';
import 'camera_state.dart';

/// Web builds have no sockets; the browser preview uses SimulatedCameraSource.
CameraSource createGrpcCameraSource(GatewayEndpoint endpoint) =>
    throw UnsupportedError('camera-manager is not reachable from a web build');
