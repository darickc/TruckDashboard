import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';

import '../data/gateway_connection.dart';
import '../gen/f250/power/v1/switch.pbgrpc.dart' as pb;
import 'switch_state.dart';

SwitchSource createGrpcSwitchSource(GatewayEndpoint endpoint) => GrpcSwitchSource(endpoint: endpoint);

/// power-manager's 5-way switch over gRPC (`WatchSwitch`) and the driver's
/// changes (`SetLearning`, `SetMapping`, `ResetMapping`). Reconnects on its
/// own. While not connected nothing is shown as current and nothing can be
/// changed.
class GrpcSwitchSource implements SwitchSource {
  GrpcSwitchSource({
    required this.endpoint,
    this.retryDelay = const Duration(seconds: 1),
    this.callTimeout = const Duration(seconds: 2),
  });

  final GatewayEndpoint endpoint;
  final Duration retryDelay;
  final Duration callTimeout;

  ClientChannel? _channel;
  pb.SwitchServiceClient? _client;
  StreamSubscription<pb.WatchSwitchResponse>? _stream;
  Timer? _retry;
  bool _running = false;

  SwitchReport? _report;
  SwitchPress? _last;
  SwitchLink _link = SwitchLink.connecting;
  String _detail = '';

  final _status = ValueNotifier(const SwitchStatus(link: SwitchLink.connecting));

  @override
  ValueListenable<SwitchStatus> get status => _status;

  @override
  void start() {
    if (_running) return;
    _running = true;
    final (host, port) = switch (endpoint) {
      UnixEndpoint(:final path) => (InternetAddress(path, type: InternetAddressType.unix), 0),
      TcpEndpoint(:final host, :final port) => (host as Object, port),
    };
    _channel = ClientChannel(host,
        port: port, options: const ChannelOptions(credentials: ChannelCredentials.insecure()));
    _client = pb.SwitchServiceClient(_channel!);
    _detail = 'connecting to $endpoint';
    _publish();
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

  pb.SwitchServiceClient _connected() {
    final c = _client;
    if (_link != SwitchLink.connected || c == null) throw StateError('power-manager not connected');
    return c;
  }

  @override
  Future<void> setLearning(bool on) async {
    final r = await _connected().setLearning(pb.SetLearningRequest(on: on, source: 'dashboard'),
        options: CallOptions(timeout: callTimeout));
    if (r.hasState()) _take(r.state);
  }

  @override
  Future<SwitchSaveResult> setMapping(Map<SwitchWire, SwitchRole> mapping) async {
    final why = checkMapping(mapping);
    if (why != null) return SwitchSaveResult(saved: false, detail: why);
    final r = await _connected().setMapping(
        pb.SetMappingRequest(
          source: 'dashboard',
          wires: [
            for (final e in mapping.entries) pb.WireRole(wire: wireToPb(e.key), role: roleToPb(e.value)),
          ],
        ),
        options: CallOptions(timeout: callTimeout));
    if (r.hasState()) _take(r.state);
    return SwitchSaveResult(saved: r.saved, detail: r.detail);
  }

  @override
  Future<SwitchSaveResult> resetMapping() async {
    final r = await _connected()
        .resetMapping(pb.ResetMappingRequest(source: 'dashboard'), options: CallOptions(timeout: callTimeout));
    if (r.hasState()) _take(r.state);
    return SwitchSaveResult(saved: r.saved, detail: r.detail);
  }

  void _connect() {
    final client = _client;
    if (!_running || client == null) return;
    _stream = client.watchSwitch(pb.WatchSwitchRequest()).listen(
          (r) {
            if (r.hasState()) _take(r.state);
            if (r.hasPress()) _press(r.press);
          },
          onError: (Object e) => _down(e is GrpcError ? (e.message ?? e.codeName) : '$e'),
          onDone: () => _down('power-manager ended the stream'),
        );
  }

  void _take(pb.SwitchState s) {
    _report = reportFromPb(s);
    _link = SwitchLink.connected;
    _detail = '';
    _publish();
  }

  void _press(pb.Press p) {
    final press = pressFromPb(p);
    if (press == null) return;
    _last = press;
    _publish();
  }

  void _down(String why) {
    _stream?.cancel();
    _stream = null;
    _report = null;
    _last = null;
    if (!_running) return;
    _link = SwitchLink.lost;
    _detail = why;
    _publish();
    _retry?.cancel();
    _retry = Timer(retryDelay, _connect);
  }

  void _publish() {
    _status.value = SwitchStatus(
      link: _link,
      report: _link == SwitchLink.connected ? _report : null,
      lastPress: _link == SwitchLink.connected ? _last : null,
      detail: _detail,
    );
  }
}

pb.Wire wireToPb(SwitchWire w) => switch (w) {
      SwitchWire.f13 => pb.Wire.WIRE_F13,
      SwitchWire.f14 => pb.Wire.WIRE_F14,
      SwitchWire.f15 => pb.Wire.WIRE_F15,
      SwitchWire.f16 => pb.Wire.WIRE_F16,
      SwitchWire.f17 => pb.Wire.WIRE_F17,
    };

SwitchWire? wireFromPb(pb.Wire w) => switch (w) {
      pb.Wire.WIRE_F13 => SwitchWire.f13,
      pb.Wire.WIRE_F14 => SwitchWire.f14,
      pb.Wire.WIRE_F15 => SwitchWire.f15,
      pb.Wire.WIRE_F16 => SwitchWire.f16,
      pb.Wire.WIRE_F17 => SwitchWire.f17,
      _ => null,
    };

pb.Role roleToPb(SwitchRole r) => switch (r) {
      SwitchRole.up => pb.Role.ROLE_UP,
      SwitchRole.down => pb.Role.ROLE_DOWN,
      SwitchRole.left => pb.Role.ROLE_LEFT,
      SwitchRole.right => pb.Role.ROLE_RIGHT,
      SwitchRole.press => pb.Role.ROLE_PRESS,
    };

SwitchRole? roleFromPb(pb.Role r) => switch (r) {
      pb.Role.ROLE_UP => SwitchRole.up,
      pb.Role.ROLE_DOWN => SwitchRole.down,
      pb.Role.ROLE_LEFT => SwitchRole.left,
      pb.Role.ROLE_RIGHT => SwitchRole.right,
      pb.Role.ROLE_PRESS => SwitchRole.press,
      _ => null,
    };

/// power-manager's state as the dashboard's model. A wire with an unknown
/// name or role (a newer power-manager) is left out, and the mapping can't
/// then be shown whole.
SwitchReport reportFromPb(pb.SwitchState s) {
  final wires = <WireInfo>[];
  for (final w in s.wires) {
    final wire = wireFromPb(w.wire);
    final role = roleFromPb(w.role);
    if (wire == null || role == null) continue;
    wires.add(WireInfo(wire: wire, pin: w.pin, role: role, present: w.present));
  }
  return SwitchReport(
    wires: wires,
    learning: s.learning,
    learningTimeoutS: s.learningTimeoutS,
    longPressMs: s.longPressMs,
    defaultMapping: s.defaultMapping,
    problem: s.problem,
  );
}

SwitchPress? pressFromPb(pb.Press p) {
  final wire = wireFromPb(p.wire);
  final role = roleFromPb(p.role);
  if (wire == null || role == null) return null;
  return SwitchPress(
    wire: wire,
    role: role,
    kind: p.kind == pb.PressKind.PRESS_KIND_LONG ? PressKind.long : PressKind.short,
    result: p.result,
    seq: p.seq.toInt(),
  );
}
