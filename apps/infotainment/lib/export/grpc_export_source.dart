import 'dart:async';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';

import '../data/gateway_connection.dart';
import '../gen/f250/export/v1/export.pbgrpc.dart' as pb;
import 'export_state.dart';

ExportSource createGrpcExportSource(GatewayEndpoint endpoint) =>
    GrpcExportSource(endpoint: endpoint);

/// services/usb-export over gRPC (`f250.export.v1`, ADR-0037). Reconnects on
/// its own. While there is no stream the status carries no sticks and no
/// copy: the screen never says a stick is safe to pull out, or a copy
/// finished, on its own.
class GrpcExportSource implements ExportSource {
  GrpcExportSource({
    required this.endpoint,
    this.retryDelay = const Duration(seconds: 1),
    this.callTimeout = const Duration(seconds: 5),
  });

  final GatewayEndpoint endpoint;
  final Duration retryDelay;
  final Duration callTimeout;

  ClientChannel? _channel;
  pb.ExportServiceClient? _client;
  StreamSubscription<pb.WatchExportResponse>? _stream;
  Timer? _retry;
  bool _running = false;

  final _status = ValueNotifier(const ExportStatus(link: ExportLink.connecting));

  @override
  ValueListenable<ExportStatus> get status => _status;

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
    _client = pb.ExportServiceClient(_channel!);
    _status.value = ExportStatus(link: ExportLink.connecting, detail: 'connecting to $endpoint');
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

  pb.ExportServiceClient _need() {
    final c = _client;
    if (c == null) throw StateError('usb-export not connected');
    return c;
  }

  @override
  Future<RecordingList> list() async {
    final r = await _need().listRecordings(
      pb.ListRecordingsRequest(),
      options: CallOptions(timeout: callTimeout),
    );
    return RecordingList(
      recordings: [for (final x in r.recordings) recordingFromPb(x)],
      driveMounted: r.driveMounted,
      problem: r.problem,
    );
  }

  @override
  Future<StartResult> startCopy(String device, List<RecordingFile> recordings) async {
    final r = await _need().startCopy(
      pb.StartCopyRequest(
        device: device,
        source: 'dashboard',
        recordings: [
          for (final x in recordings)
            pb.RecordingRef(camera: x.camera, fileName: x.fileName, protected: x.protected),
        ],
      ),
      options: CallOptions(timeout: callTimeout),
    );
    return StartResult(started: r.started, detail: r.detail);
  }

  @override
  Future<bool> cancel() async {
    final r = await _need().cancelCopy(
      pb.CancelCopyRequest(source: 'dashboard'),
      options: CallOptions(timeout: callTimeout),
    );
    return r.cancelling;
  }

  void _connect() {
    final client = _client;
    if (!_running || client == null) return;
    _stream = client
        .watchExport(pb.WatchExportRequest())
        .listen(
          (r) => _status.value = statusFromPb(r),
          onError: (Object e) => _down(e is GrpcError ? (e.message ?? e.codeName) : '$e'),
          onDone: () => _down('usb-export ended the stream'),
        );
  }

  void _down(String why) {
    _stream?.cancel();
    _stream = null;
    if (!_running) return;
    _status.value = ExportStatus(link: ExportLink.down, detail: why);
    _retry?.cancel();
    _retry = Timer(retryDelay, _connect);
  }
}

int _int(Int64 v) => v.toInt();

RecordingFile recordingFromPb(pb.Recording r) => RecordingFile(
  camera: r.camera,
  fileName: r.fileName,
  protected: r.protected,
  bytes: _int(r.bytes),
  boot: r.boot,
  seq: r.seq,
  wallTime: r.wallTime == Int64.ZERO
      ? null
      : DateTime.fromMillisecondsSinceEpoch(_int(r.wallTime) * 1000, isUtc: true),
  beingWritten: r.beingWritten,
);

ExportStatus statusFromPb(pb.WatchExportResponse r) => ExportStatus(
  link: ExportLink.up,
  sticks: [for (final s in r.sticks) stickFromPb(s)],
  copy: r.hasCopy() ? copyFromPb(r.copy) : null,
);

UsbStick stickFromPb(pb.Stick s) => UsbStick(
  device: s.device,
  role: switch (s.role) {
    pb.StickRole.STICK_ROLE_EXPORT => StickRole.export,
    pb.StickRole.STICK_ROLE_MAP => StickRole.map,
    pb.StickRole.STICK_ROLE_CHECKING => StickRole.checking,
    // Unusable, unspecified and anything newer: never copied to.
    _ => StickRole.unusable,
  },
  label: s.label,
  model: s.model,
  filesystem: s.filesystem,
  freeBytes: _int(s.freeBytes),
  totalBytes: _int(s.totalBytes),
  maxFileBytes: _int(s.maxFileBytes),
  readOnly: s.readOnly,
  detail: s.detail,
);

CopyStatus copyFromPb(pb.Copy c) => CopyStatus(
  phase: switch (c.state) {
    pb.CopyState.COPY_STATE_PREPARING => CopyPhase.preparing,
    pb.CopyState.COPY_STATE_COPYING => CopyPhase.copying,
    pb.CopyState.COPY_STATE_FINISHING => CopyPhase.finishing,
    pb.CopyState.COPY_STATE_DONE => CopyPhase.done,
    pb.CopyState.COPY_STATE_FAILED => CopyPhase.failed,
    pb.CopyState.COPY_STATE_CANCELLED => CopyPhase.cancelled,
    _ => CopyPhase.idle,
  },
  device: c.device,
  filesTotal: c.filesTotal,
  filesDone: c.filesDone,
  filesSkipped: c.filesSkipped,
  filesMissing: c.filesMissing,
  bytesTotal: _int(c.bytesTotal),
  bytesDone: _int(c.bytesDone),
  current: c.current,
  detail: c.detail,
  // Only ever true when the service says so.
  safeToUnplug: c.safeToUnplug,
  folder: c.folder,
  id: _int(c.id),
);
