import '../data/gateway_connection.dart';
import 'audio_connection_stub.dart' if (dart.library.io) 'grpc_audio_source.dart' as impl;
import 'audio_state.dart';

/// services/audio-manager over gRPC at [endpoint]. Not available on the web
/// build (no sockets): throws UnsupportedError there.
AudioSource connectAudioManager(GatewayEndpoint endpoint) => impl.createGrpcAudioSource(endpoint);
