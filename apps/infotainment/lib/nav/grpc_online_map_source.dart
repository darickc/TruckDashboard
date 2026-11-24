import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';

import '../data/gateway_connection.dart';
import '../gen/f250/nav/v1/online_map.pbgrpc.dart' as pb;
import 'online_map.dart';

OnlineMapSource createGrpcOnlineMapSource(GatewayEndpoint endpoint) => GrpcOnlineMapSource(endpoint: endpoint);

/// services/navigation's `OnlineMapService` (ADR-0052). Its status is asked
/// for every [poll] (a local call; nothing goes to Mapbox for it).
class GrpcOnlineMapSource implements OnlineMapSource {
  GrpcOnlineMapSource({required this.endpoint, this.poll = const Duration(seconds: 10)});

  final GatewayEndpoint endpoint;
  final Duration poll;

  final ValueNotifier<OnlineMapStatus> _status = ValueNotifier(
    const OnlineMapStatus(detail: 'asking the navigation service'),
  );
  ClientChannel? _channel;
  pb.OnlineMapServiceClient? _client;
  Timer? _timer;

  @override
  ValueListenable<OnlineMapStatus> get status => _status;

  @override
  void start() {
    if (_channel != null) return;
    final (host, port) = switch (endpoint) {
      UnixEndpoint(:final path) => (InternetAddress(path, type: InternetAddressType.unix), 0),
      TcpEndpoint(:final host, :final port) => (host as Object, port),
    };
    _channel = ClientChannel(
      host,
      port: port,
      options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
    );
    _client = pb.OnlineMapServiceClient(_channel!);
    unawaited(_ask());
    _timer = Timer.periodic(poll, (_) => _ask());
  }

  Future<void> _ask() async {
    final c = _client;
    if (c == null) return;
    try {
      final r = await c.getOnlineMapStatus(
        pb.GetOnlineMapStatusRequest(),
        options: CallOptions(timeout: const Duration(seconds: 3)),
      );
      _status.value = OnlineMapStatus(
        configured: r.configured,
        detail: r.detail,
        attribution: r.attribution,
        tileSize: r.tileSize == 0 ? 512 : r.tileSize,
        maxZoom: r.maxZoom == 0 ? 22 : r.maxZoom,
        routingOnline: r.routingOnline,
        vector: r.vector,
      );
    } catch (e) {
      // An older navigation without the service, or none: offline only.
      _status.value = OnlineMapStatus(
        detail: 'no online map: ${e is GrpcError ? (e.message ?? e.codeName) : e}',
      );
    }
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
    _channel?.shutdown();
    _channel = null;
    _client = null;
  }

  @override
  Future<Uint8List> tile(int z, int x, int y, {required bool night}) async {
    final c = _client;
    if (c == null) throw StateError('not connected to the navigation service');
    try {
      final r = await c.getTile(
        pb.GetTileRequest(
          style: night ? pb.MapStyle.MAP_STYLE_NIGHT : pb.MapStyle.MAP_STYLE_DAY,
          z: z,
          x: x,
          y: y,
        ),
        options: CallOptions(timeout: const Duration(seconds: 12)),
      );
      return Uint8List.fromList(r.data);
    } on GrpcError catch (e) {
      throw StateError(e.message ?? e.codeName);
    }
  }

  pb.MapStyle _style(bool night) => night ? pb.MapStyle.MAP_STYLE_NIGHT : pb.MapStyle.MAP_STYLE_DAY;

  @override
  Future<OnlineMapStyleData> style({required bool night, required int pixelRatio}) async {
    final c = _client;
    if (c == null) throw StateError('not connected to the navigation service');
    try {
      // The first ask fetches the style, its sprites and each source's
      // zooms from Mapbox (several requests).
      final r = await c.getMapStyle(
        pb.GetMapStyleRequest(style: _style(night), pixelRatio: pixelRatio),
        options: CallOptions(timeout: const Duration(seconds: 30)),
      );
      return OnlineMapStyleData(
        styleJson: r.styleJson,
        spriteJson: r.spriteJson,
        spritePng: Uint8List.fromList(r.spritePng),
        sources: [for (final s in r.sources) OnlineMapSourceZooms(s.id, s.minZoom, s.maxZoom)],
      );
    } on GrpcError catch (e) {
      throw StateError(e.message ?? e.codeName);
    }
  }

  @override
  Future<Uint8List> vectorTile(String source, int z, int x, int y, {required bool night}) async {
    final c = _client;
    if (c == null) throw StateError('not connected to the navigation service');
    try {
      final r = await c.getTile(
        pb.GetTileRequest(style: _style(night), source: source, z: z, x: x, y: y),
        options: CallOptions(timeout: const Duration(seconds: 12)),
      );
      return Uint8List.fromList(r.data);
    } on GrpcError catch (e) {
      throw StateError(e.message ?? e.codeName);
    }
  }
}
