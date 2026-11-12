import '../data/gateway_connection.dart';
import 'audio_state.dart';

/// Web builds have no sockets; the browser preview uses SimulatedAudioSource.
AudioSource createGrpcAudioSource(GatewayEndpoint endpoint) =>
    throw UnsupportedError('audio-manager is not reachable from a web build');
