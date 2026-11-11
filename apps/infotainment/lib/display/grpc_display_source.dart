import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';

import '../core/settings.dart';
import '../data/gateway_connection.dart';
import '../gen/f250/power/v1/display.pbgrpc.dart' as pb;
import 'display_state.dart';

DisplaySource createGrpcDisplaySource(GatewayEndpoint endpoint) =>
    GrpcDisplaySource(endpoint: endpoint);

/// power-manager's display state over gRPC (`WatchDisplay`) and the
/// driver's changes (`SetDisplay`). Reconnects on its own.
///
/// While power-manager isn't connected the theme stays as it last was (no
/// flash on a blip), the screen says the backlight isn't controlled, and Day
/// or Night can still be picked for the screen alone. The first report after
/// reconnecting replaces any such local choice: power-manager is the
/// authority (ADR-0028 decision 1).
class GrpcDisplaySource implements DisplaySource {
  GrpcDisplaySource({
    required this.endpoint,
    this.retryDelay = const Duration(seconds: 1),
    this.callTimeout = const Duration(seconds: 2),
  });

  final GatewayEndpoint endpoint;
  final Duration retryDelay;
  final Duration callTimeout;

  ClientChannel? _channel;
  pb.DisplayServiceClient? _client;
  StreamSubscription<pb.WatchDisplayResponse>? _stream;
  Timer? _retry;
  bool _running = false;

  DisplayReport? _report;
  DisplayLink _link = DisplayLink.connecting;
  String _detail = '';

  /// The theme to keep while not connected. Day until told otherwise: a
  /// dim screen in daylight can hide an alert (ADR-0028 decision 4).
  DayNight _lastMode = DayNight.day;
  DisplayChoice _lastChoice = DisplayChoice.auto;

  /// Day or Night picked while not connected.
  DayNight? _local;

  final _status = ValueNotifier(
      const DisplayStatus(link: DisplayLink.connecting, mode: DayNight.day, choice: DisplayChoice.auto));

  @override
  ValueListenable<DisplayStatus> get status => _status;

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
    _client = pb.DisplayServiceClient(_channel!);
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

  @override
  Future<void> setChoice(DisplayChoice choice) async {
    final client = _client;
    if (_link != DisplayLink.connected || client == null) {
      // The screen alone; Auto needs power-manager.
      switch (choice) {
        case DisplayChoice.auto:
          return;
        case DisplayChoice.day:
          _local = DayNight.day;
        case DisplayChoice.night:
          _local = DayNight.night;
      }
      _publish();
      return;
    }
    final r = await client.setDisplay(
        pb.SetDisplayRequest(choice: choiceToPb(choice), source: 'dashboard'),
        options: CallOptions(timeout: callTimeout));
    _take(r.display);
  }

  @override
  Future<void> setBrightness(DayNight mode, int pct) async {
    final client = _client;
    if (_link != DisplayLink.connected || client == null) {
      throw StateError('power-manager not connected');
    }
    final req = pb.SetDisplayRequest(source: 'dashboard');
    if (mode == DayNight.day) {
      req.dayBrightnessPct = pct;
    } else {
      req.nightBrightnessPct = pct;
    }
    final r = await client.setDisplay(req, options: CallOptions(timeout: callTimeout));
    _take(r.display);
  }

  void _connect() {
    final client = _client;
    if (!_running || client == null) return;
    _stream = client.watchDisplay(pb.WatchDisplayRequest()).listen(
          (r) => _take(r.display),
          onError: (Object e) => _down(e is GrpcError ? (e.message ?? e.codeName) : '$e'),
          onDone: () => _down('power-manager ended the stream'),
        );
  }

  void _take(pb.Display d) {
    final report = reportFromPb(d);
    if (report == null) return; // undecided: nothing to show yet
    _report = report;
    _link = DisplayLink.connected;
    _detail = '';
    _local = null;
    _lastMode = report.mode;
    _lastChoice = report.choice;
    _publish();
  }

  void _down(String why) {
    _stream?.cancel();
    _stream = null;
    _report = null;
    if (!_running) return;
    _link = DisplayLink.lost;
    _detail = why;
    _publish();
    _retry?.cancel();
    _retry = Timer(retryDelay, _connect);
  }

  void _publish() {
    final r = _report;
    if (_link == DisplayLink.connected && r != null) {
      _status.value = DisplayStatus(
          link: DisplayLink.connected,
          mode: r.mode,
          choice: r.choice,
          report: r,
          dayPct: r.dayPct,
          nightPct: r.nightPct,
          minPct: r.minPct);
      return;
    }
    final local = _local;
    _status.value = DisplayStatus(
        link: _link,
        mode: local ?? _lastMode,
        choice: switch (local) {
          DayNight.day => DisplayChoice.day,
          DayNight.night => DisplayChoice.night,
          null => _lastChoice,
        },
        detail: _detail);
  }
}

pb.DisplayChoice choiceToPb(DisplayChoice c) => switch (c) {
      DisplayChoice.auto => pb.DisplayChoice.DISPLAY_CHOICE_AUTO,
      DisplayChoice.day => pb.DisplayChoice.DISPLAY_CHOICE_DAY,
      DisplayChoice.night => pb.DisplayChoice.DISPLAY_CHOICE_NIGHT,
    };

/// power-manager's state as the dashboard's model; null while it has no
/// mode. An unknown basis or sun status (a newer power-manager) reads as
/// "fallback" and "unknown", never as following the sun.
DisplayReport? reportFromPb(pb.Display d) {
  final mode = switch (d.mode) {
    pb.DisplayMode.DISPLAY_MODE_DAY => DayNight.day,
    pb.DisplayMode.DISPLAY_MODE_NIGHT => DayNight.night,
    _ => null,
  };
  if (mode == null) return null;
  final sun = switch (d.sun) {
    pb.SunStatus.SUN_STATUS_KNOWN => SunStatus.known,
    pb.SunStatus.SUN_STATUS_NO_LOCATION => SunStatus.noLocation,
    pb.SunStatus.SUN_STATUS_CLOCK_NOT_SET => SunStatus.clockNotSet,
    _ => SunStatus.clockNotSynchronized,
  };
  return DisplayReport(
    mode: mode,
    choice: switch (d.choice) {
      pb.DisplayChoice.DISPLAY_CHOICE_DAY => DisplayChoice.day,
      pb.DisplayChoice.DISPLAY_CHOICE_NIGHT => DisplayChoice.night,
      _ => DisplayChoice.auto,
    },
    basis: switch (d.basis) {
      pb.ModeBasis.MODE_BASIS_SUN => ModeBasis.sun,
      pb.ModeBasis.MODE_BASIS_MANUAL => ModeBasis.manual,
      _ => ModeBasis.fallback,
    },
    sun: sun,
    sunElevationDeg: sun == SunStatus.known ? d.sunElevationDeg : null,
    dayPct: d.dayBrightnessPct,
    nightPct: d.nightBrightnessPct,
    minPct: d.minBrightnessPct,
    backlight: d.backlightPresent ? d.backlight : null,
    brightnessPct: d.brightnessPct,
    backlightProblem: d.backlightProblem,
  );
}
