import 'dart:async';
import 'dart:io';

import 'package:grpc/grpc.dart';

import '../gen/f250/vehicle/v1/vehicle.pbgrpc.dart' as pb;
import '../model/signal.dart';
import '../telemetry/calibration.dart';
import '../telemetry/event_log.dart';
import '../telemetry/source_info.dart';
import '../telemetry/telemetry_store.dart';
import '../telemetry/warnings.dart';
import 'gateway_connection.dart';

GatewayConnection createGatewayConnection(TelemetryStore store, GatewayEndpoint endpoint) =>
    GrpcVehicleDataSource(store: store, endpoint: endpoint);

/// Mirrors the gateway's snapshots into the store over gRPC. Reconnects on
/// its own; while disconnected, the store's watchdog marks everything stale.
class GrpcVehicleDataSource implements GatewayConnection {
  GrpcVehicleDataSource({
    required this.store,
    required this.endpoint,
    this.period = const Duration(milliseconds: 250),
    this.retryDelay = const Duration(seconds: 1),
  });

  final TelemetryStore store;
  final GatewayEndpoint endpoint;
  final Duration period;
  final Duration retryDelay;

  ClientChannel? _channel;
  pb.VehicleServiceClient? _client;
  StreamSubscription<pb.StreamSnapshotsResponse>? _stream;
  Timer? _retry;
  Timer? _events;
  bool _running = false;

  @override
  String get label => 'GATEWAY';

  @override
  bool get isSimulated => store.source.simulated;

  @override
  void start() {
    if (_running) return;
    _running = true;
    final (host, port) = switch (endpoint) {
      UnixEndpoint(:final path) => (InternetAddress(path, type: InternetAddressType.unix), 0),
      TcpEndpoint(:final host, :final port) => (host as Object, port),
    };
    _channel = ClientChannel(host,
        port: port,
        options: const ChannelOptions(credentials: ChannelCredentials.insecure()));
    _client = pb.VehicleServiceClient(_channel!);
    store.source = SourceInfo(transport: 'gateway ($endpoint)', simulated: false, detail: 'connecting');
    _connect();
    _events = Timer.periodic(const Duration(seconds: 2), (_) => _pollEvents());
  }

  @override
  void stop() {
    _running = false;
    _retry?.cancel();
    _events?.cancel();
    _stream?.cancel();
    _channel?.shutdown();
    _stream = null;
    _channel = null;
    _client = null;
  }

  @override
  Future<void> setCalibration(String signalId, Calibration c) async {
    final client = _client;
    if (client == null) throw StateError('gateway not connected');
    final r = await client.setCalibration(pb.SetCalibrationRequest(
        signalId: signalId, scale: c.scale, offset: c.offset));
    store.setExternalCalibration(
        signalId, Calibration(scale: r.signal.calibrationScale, offset: r.signal.calibrationOffset));
  }

  Future<void> _connect() async {
    final client = _client;
    if (!_running || client == null) return;
    try {
      final defs = await client.listSignals(pb.ListSignalsRequest());
      for (final d in defs.signals) {
        if (store[d.id] != null && !d.inputs.isNotEmpty) {
          store.setExternalCalibration(
              d.id, Calibration(scale: d.calibrationScale == 0 ? 1 : d.calibrationScale, offset: d.calibrationOffset));
        }
      }
      _stream = client
          .streamSnapshots(pb.StreamSnapshotsRequest(periodMs: period.inMilliseconds))
          .listen((r) => apply(r.snapshot), onError: (_) => _scheduleRetry(), onDone: _scheduleRetry);
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _stream?.cancel();
    _stream = null;
    if (!_running) return;
    _retry?.cancel();
    _retry = Timer(retryDelay, _connect);
  }

  Future<void> _pollEvents() async {
    final client = _client;
    if (client == null || !store.isExternal) return;
    try {
      final r = await client.listEvents(pb.ListEventsRequest(limit: store.events.capacity));
      final now = store.clock.now();
      final newest = r.events.isEmpty ? 0 : r.events.first.monoMs.toInt();
      store.events.replaceAll(
        r.events.map((e) => TelemetryEvent(
              now - Duration(milliseconds: newest - e.monoMs.toInt()),
              DateTime.fromMillisecondsSinceEpoch(e.wallMs.toInt()),
              switch (e.severity) {
                pb.EventSeverity.EVENT_SEVERITY_CRITICAL => EventSeverity.critical,
                pb.EventSeverity.EVENT_SEVERITY_ADVISORY => EventSeverity.advisory,
                _ => EventSeverity.info,
              },
              e.message,
            )),
        dropped: r.dropped.toInt(),
      );
    } catch (_) {
      // The snapshot stream's watchdog reports a dead gateway; nothing to add.
    }
  }

  /// Applies one snapshot (public for tests).
  void apply(pb.Snapshot snap) {
    final samples = {for (final s in snap.samples) s.signalId: s};
    final link = snap.link;
    final snapMono = snap.monoMs.toInt();
    store.source = SourceInfo(
      transport: 'gateway: ${link.transport}',
      simulated: link.simulated,
      scenario: link.scenario.isEmpty ? null : link.scenario,
      scenarioSeconds: link.scenario.isEmpty ? null : link.scenarioSeconds,
      transmitEnabled: link.transmitEnabled,
      machineState: link.machineState,
      adapterVoltage: link.hasAdapterVoltage() ? link.adapterVoltage : null,
      detail: link.detail.isEmpty ? null : link.detail,
    );
    store.applyExternal(
      update: (s, now) {
        final p = samples[s.def.id];
        if (p == null) return;
        s.validity = _validity(p.validity);
        s.value = s.validity == Validity.valid && p.hasValue() ? p.value : null;
        s.lastGoodValue = p.hasLastGoodValue() ? p.lastGoodValue : null;
        s.lastGoodRaw = p.hasLastGoodRaw() ? p.lastGoodRaw : null;
        s.lastGoodAt =
            p.hasLastGoodAgeMs() ? now - Duration(milliseconds: p.lastGoodAgeMs.toInt()) : null;
        s.lastRejectedValue = p.hasRejectedValue() ? p.rejectedValue : null;
        s.lastNrc = p.lastNrc == 0 ? null : p.lastNrc;
        s.lastResponder = p.lastResponder.isEmpty ? null : p.lastResponder;
        s.lastLatencyMs = p.lastLatencyMs == 0 ? null : p.lastLatencyMs;
        s.successes = p.successes.toInt();
        s.failures = p.failures.toInt();
        s.consecutiveFailures = p.consecutiveFailures;
        s.invalidInputs = List.of(p.invalidInputs);
      },
      link: switch (link.state) {
        pb.LinkState.LINK_STATE_UP => LinkState.up,
        pb.LinkState.LINK_STATE_DEGRADED => LinkState.degraded,
        pb.LinkState.LINK_STATE_DOWN => LinkState.down,
        _ => LinkState.connecting,
      },
      linkAge: Duration(milliseconds: (snapMono - link.sinceMonoMs.toInt()).clamp(0, 1 << 40)),
      alerts: [
        for (final a in snap.alerts)
          Alert(
            id: a.id,
            kind: switch (a.kind) {
              pb.AlertKind.ALERT_KIND_LINK_LOST => AlertKind.linkLost,
              pb.AlertKind.ALERT_KIND_SIGNAL_NOT_UPDATING => AlertKind.signalNotUpdating,
              _ => AlertKind.threshold,
            },
            level: a.level == pb.AlertLevel.ALERT_LEVEL_CRITICAL
                ? AlertLevel.critical
                : AlertLevel.advisory,
            since: store.clock.now() -
                Duration(milliseconds: (snapMono - a.sinceMonoMs.toInt()).clamp(0, 1 << 40)),
            signalId: a.signalId.isEmpty ? null : a.signalId,
            threshold: a.kind == pb.AlertKind.ALERT_KIND_THRESHOLD ? a.threshold : null,
            above: a.kind == pb.AlertKind.ALERT_KIND_THRESHOLD ? a.above : null,
          ),
      ],
    );
  }

  static Validity _validity(pb.Validity v) => switch (v) {
        pb.Validity.VALIDITY_VALID => Validity.valid,
        pb.Validity.VALIDITY_STALE => Validity.stale,
        pb.Validity.VALIDITY_OUT_OF_RANGE => Validity.outOfRange,
        pb.Validity.VALIDITY_DECODE_ERROR => Validity.decodeError,
        pb.Validity.VALIDITY_UNSUPPORTED => Validity.unsupported,
        pb.Validity.VALIDITY_DISABLED => Validity.disabled,
        _ => Validity.noData,
      };
}
