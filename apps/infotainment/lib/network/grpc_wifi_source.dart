import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';

import '../data/gateway_connection.dart';
import '../gen/f250/network/v1/wifi.pbgrpc.dart' as pb;
import 'wifi_state.dart';

WifiSource createGrpcWifiSource(GatewayEndpoint endpoint) => GrpcWifiSource(endpoint: endpoint);

/// services/network's `WifiService` over gRPC (ADR-0052). Watches the status
/// and reconnects after a lost link; calls that fail are answers, never
/// exceptions.
class GrpcWifiSource implements WifiSource {
  GrpcWifiSource({required this.endpoint, this.retry = const Duration(seconds: 2)});

  final GatewayEndpoint endpoint;
  final Duration retry;

  final ValueNotifier<WifiView> _view = ValueNotifier(const WifiView(link: WifiLink.connecting));
  ClientChannel? _channel;
  pb.WifiServiceClient? _client;
  StreamSubscription<pb.WatchWifiResponse>? _sub;
  Timer? _retryTimer;
  bool _running = false;

  @override
  ValueListenable<WifiView> get view => _view;

  @override
  void start() {
    if (_running) return;
    _running = true;
    final (host, port) = switch (endpoint) {
      UnixEndpoint(:final path) => (InternetAddress(path, type: InternetAddressType.unix), 0),
      TcpEndpoint(:final host, :final port) => (host as Object, port),
    };
    _channel = ClientChannel(
      host,
      port: port,
      options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
    );
    _client = pb.WifiServiceClient(_channel!);
    _watch();
  }

  void _watch() {
    final client = _client;
    if (!_running || client == null) return;
    _sub?.cancel();
    _sub = client.watchWifi(pb.WatchWifiRequest()).listen(
      (r) => _view.value = wifiViewFromPb(r.status),
      onError: (Object e) => _lost(e is GrpcError ? (e.message ?? e.codeName) : '$e'),
      onDone: () => _lost('the network service closed the stream'),
    );
  }

  void _lost(String why) {
    _view.value = WifiView(link: WifiLink.lost, detail: 'network service unavailable: $why');
    _retryTimer?.cancel();
    if (_running) _retryTimer = Timer(retry, _watch);
  }

  @override
  void stop() {
    _running = false;
    _retryTimer?.cancel();
    _sub?.cancel();
    _channel?.shutdown();
    _channel = null;
    _client = null;
  }

  Future<String?> _call(Future<void> Function(pb.WifiServiceClient c) f) async {
    final c = _client;
    if (c == null) return 'not connected to the network service';
    try {
      await f(c);
      return null;
    } catch (e) {
      return e is GrpcError ? (e.message ?? e.codeName) : '$e';
    }
  }

  @override
  Future<String?> setEnabled(bool on) =>
      _call((c) => c.setWifiEnabled(pb.SetWifiEnabledRequest(enabled: on)));

  @override
  Future<String?> scan() =>
      _call((c) => c.scanWifi(pb.ScanWifiRequest(), options: CallOptions(timeout: const Duration(seconds: 40))));

  @override
  Future<WifiJoin> connect(String id, {String passphrase = ''}) async {
    final c = _client;
    if (c == null) return const WifiJoin(connected: false, detail: 'not connected to the network service');
    try {
      final r = await c.connectWifi(
        pb.ConnectWifiRequest(id: id, passphrase: passphrase),
        options: CallOptions(timeout: const Duration(seconds: 75)),
      );
      return WifiJoin(connected: r.connected, detail: r.detail);
    } catch (e) {
      return WifiJoin(connected: false, detail: e is GrpcError ? (e.message ?? e.codeName) : '$e');
    }
  }

  @override
  Future<String?> disconnect(String id) => _call((c) => c.disconnectWifi(pb.DisconnectWifiRequest(id: id)));

  @override
  Future<String?> forget(String id) => _call((c) => c.forgetWifi(pb.ForgetWifiRequest(id: id)));
}

/// The service's status as the dashboard's model. Values a newer service
/// adds read as unknown.
WifiView wifiViewFromPb(pb.WifiStatus s) => WifiView(
  link: WifiLink.connected,
  available: s.available,
  enabled: s.enabled,
  connectivity: switch (s.connectivity) {
    pb.Connectivity.CONNECTIVITY_OFFLINE => Connectivity.offline,
    pb.Connectivity.CONNECTIVITY_CONNECTED => Connectivity.connected,
    pb.Connectivity.CONNECTIVITY_ONLINE => Connectivity.online,
    _ => Connectivity.unknown,
  },
  networks: List.unmodifiable([
    for (final n in s.networks)
      WifiNetwork(
        id: n.id,
        name: n.name,
        strength: n.strength,
        security: switch (n.security) {
          pb.Security.SECURITY_OPEN => WifiSecurity.open,
          pb.Security.SECURITY_PSK => WifiSecurity.psk,
          pb.Security.SECURITY_WEP => WifiSecurity.wep,
          pb.Security.SECURITY_ENTERPRISE => WifiSecurity.enterprise,
          _ => WifiSecurity.unknown,
        },
        saved: n.saved,
        state: switch (n.state) {
          pb.NetworkState.NETWORK_STATE_IDLE => WifiNetworkState.idle,
          pb.NetworkState.NETWORK_STATE_CONNECTING => WifiNetworkState.connecting,
          pb.NetworkState.NETWORK_STATE_CONNECTED => WifiNetworkState.connected,
          pb.NetworkState.NETWORK_STATE_ONLINE => WifiNetworkState.online,
          pb.NetworkState.NETWORK_STATE_DISCONNECTING => WifiNetworkState.disconnecting,
          pb.NetworkState.NETWORK_STATE_FAILED => WifiNetworkState.failed,
          _ => WifiNetworkState.unknown,
        },
        error: n.error,
      ),
  ]),
  detail: s.detail,
  simulated: s.simulated,
  address: s.address,
  scanning: s.scanning,
);
