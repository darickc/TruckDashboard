import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';

import '../core/clock.dart';
import '../data/gateway_connection.dart';
import '../gen/f250/nav/v1/position.pbgrpc.dart' as pb;
import 'position_state.dart';

PositionSource createGrpcPositionSource(GatewayEndpoint endpoint) =>
    GrpcPositionSource(endpoint: endpoint);

/// services/navigation's position over gRPC (`WatchPosition`). Reconnects
/// on its own. While it is down the last report is kept, so the last fix
/// shows as stale with its age rather than vanishing.
class GrpcPositionSource implements PositionSource {
  GrpcPositionSource({
    required this.endpoint,
    MonotonicClock? clock,
    this.retryDelay = const Duration(seconds: 1),
  }) : clock = clock ?? SystemMonotonicClock();

  final GatewayEndpoint endpoint;
  @override
  final MonotonicClock clock;
  final Duration retryDelay;

  ClientChannel? _channel;
  pb.PositionServiceClient? _client;
  StreamSubscription<pb.WatchPositionResponse>? _stream;
  Timer? _retry;
  bool _running = false;

  final _status = ValueNotifier(const PositionState(link: PositionLink.connecting));

  @override
  ValueListenable<PositionState> get status => _status;

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
    _client = pb.PositionServiceClient(_channel!);
    _status.value = PositionState(link: PositionLink.connecting, detail: 'connecting to $endpoint');
    _connect();
  }

  @override
  void stop() {
    _running = false;
    _retry?.cancel();
    _stream?.cancel();
    _channel?.shutdown();
    _stream = null;
    _channel = null;
    _client = null;
  }

  void _connect() {
    final client = _client;
    if (!_running || client == null) return;
    _stream = client
        .watchPosition(pb.WatchPositionRequest())
        .listen(
          (r) => _status.value = PositionState(
            link: PositionLink.connected,
            report: reportFromPb(r.position, clock.now()),
          ),
          onError: (Object e) => _down(e is GrpcError ? (e.message ?? e.codeName) : '$e'),
          onDone: () => _down('the navigation service ended the stream'),
        );
  }

  void _down(String why) {
    _stream?.cancel();
    _stream = null;
    if (!_running) return;
    _status.value = PositionState(
      link: PositionLink.lost,
      report: _status.value.report,
      detail: why,
    );
    _retry?.cancel();
    _retry = Timer(retryDelay, _connect);
  }
}

/// navigation's message as the dashboard's model. An unknown status (a
/// newer service) reads as unavailable, never as a fix.
PositionReport reportFromPb(pb.Position p, Duration receivedAt) {
  final status = switch (p.status) {
    pb.FixStatus.FIX_STATUS_NO_RECEIVER => FixStatus.noReceiver,
    pb.FixStatus.FIX_STATUS_RECEIVER_SILENT => FixStatus.receiverSilent,
    pb.FixStatus.FIX_STATUS_NO_FIX => FixStatus.noFix,
    pb.FixStatus.FIX_STATUS_FIX_2D => FixStatus.fix2d,
    pb.FixStatus.FIX_STATUS_FIX_3D => FixStatus.fix3d,
    _ => FixStatus.unavailable,
  };
  final isFix = status == FixStatus.fix2d || status == FixStatus.fix3d;
  FixReport? fix;
  if (p.hasFix()) {
    final f = p.fix;
    fix = FixReport(
      lat: f.latitudeDeg,
      lon: f.longitudeDeg,
      ageAtReceipt: Duration(milliseconds: f.ageMs.toInt()),
      altitudeM: f.hasAltitudeMslM() ? f.altitudeMslM : null,
      speedMps: f.hasSpeedMps() ? f.speedMps : null,
      trackDeg: f.hasTrackDeg() ? f.trackDeg : null,
      errorM: f.hasHorizontalErrorM() ? f.horizontalErrorM : null,
      utcMs: f.hasUtcTimeMs() ? f.utcTimeMs.toInt() : null,
    );
  }
  return PositionReport(
    status: status,
    receivedAt: receivedAt,
    current: p.current && isFix && fix != null,
    staleAfter: Duration(milliseconds: p.staleAfterMs.toInt()),
    fix: fix,
    satellitesUsed: p.hasSatellitesUsed() ? p.satellitesUsed : null,
    satellitesVisible: p.hasSatellitesVisible() ? p.satellitesVisible : null,
    source: p.source,
    simulated: p.simulated,
    detail: p.detail,
  );
}
