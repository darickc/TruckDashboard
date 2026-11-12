import 'dart:async';

import 'package:flutter/foundation.dart';

/// Copying dashcam recordings to a USB stick (ADR-0037), as services/usb-export
/// reports it over `f250.export.v1`. The dashboard lists, selects and shows
/// progress; the service does the copying. Nothing here touches a stick or
/// the data drive.

/// One recording on the data drive: a segment of one camera.
@immutable
class RecordingFile {
  const RecordingFile({
    required this.camera,
    required this.fileName,
    required this.bytes,
    required this.boot,
    required this.seq,
    this.protected = false,
    this.wallTime,
    this.beingWritten = false,
  });

  /// `front` or `rear`.
  final String camera;
  final String fileName;
  final int bytes;

  /// The head unit's run and the segment's place in it: they order the
  /// recordings whatever the clock said.
  final int boot;
  final int seq;

  /// A saved clip ("Save clip"), kept from retention.
  final bool protected;

  /// When it started, only if the clock was trusted while it recorded.
  final DateTime? wallTime;

  /// Probably still being written: it can't be copied yet.
  final bool beingWritten;

  /// Unique on the drive.
  String get key => '${protected ? 'protected/' : ''}$camera/$fileName';

  @override
  bool operator ==(Object other) =>
      other is RecordingFile && other.key == key && other.bytes == bytes;

  @override
  int get hashCode => Object.hash(key, bytes);
}

@immutable
class RecordingList {
  const RecordingList({this.recordings = const [], this.driveMounted = true, this.problem = ''});

  /// Oldest first.
  final List<RecordingFile> recordings;
  final bool driveMounted;

  /// Why the list may be empty or incomplete; empty when nothing is wrong.
  final String problem;
}

enum StickRole { checking, export, map, unusable }

@immutable
class UsbStick {
  const UsbStick({
    required this.device,
    required this.role,
    this.label = '',
    this.model = '',
    this.filesystem = '',
    this.freeBytes = 0,
    this.totalBytes = 0,
    this.maxFileBytes = 0,
    this.readOnly = false,
    this.detail = '',
  });

  /// The kernel's name (`sda1`): names the stick to the service.
  final String device;
  final StickRole role;
  final String label, model, filesystem;
  final int freeBytes, totalBytes;

  /// The largest file it holds (FAT: 4 GiB − 1); 0: no limit that matters.
  final int maxFileBytes;
  final bool readOnly;

  /// Why it is unusable or what it is.
  final String detail;

  /// What to call it on screen: its label, else its model, else the device.
  String get name => label.isNotEmpty ? label : (model.isNotEmpty ? model : device);

  /// Recordings can be copied to it now.
  bool get usable => role == StickRole.export && !readOnly;
}

enum CopyPhase { idle, preparing, copying, finishing, done, failed, cancelled }

@immutable
class CopyStatus {
  const CopyStatus({
    this.phase = CopyPhase.idle,
    this.device = '',
    this.filesTotal = 0,
    this.filesDone = 0,
    this.filesSkipped = 0,
    this.filesMissing = 0,
    this.bytesTotal = 0,
    this.bytesDone = 0,
    this.current = '',
    this.detail = '',
    this.safeToUnplug = true,
    this.folder = 'F250-recordings',
    this.id = 0,
  });

  final CopyPhase phase;
  final String device;
  final int filesTotal, filesDone, filesSkipped, filesMissing;
  final int bytesTotal, bytesDone;

  /// The file being copied (camera/file name).
  final String current;
  final String detail;

  /// The stick is synced and unmounted: it can come out.
  final bool safeToUnplug;
  final String folder;
  final int id;

  bool get running =>
      phase == CopyPhase.preparing || phase == CopyPhase.copying || phase == CopyPhase.finishing;

  bool get finished =>
      phase == CopyPhase.done || phase == CopyPhase.failed || phase == CopyPhase.cancelled;

  double get fraction => bytesTotal <= 0 ? 0 : (bytesDone / bytesTotal).clamp(0, 1).toDouble();
}

enum ExportLink { connecting, up, down }

@immutable
class ExportStatus {
  const ExportStatus({
    required this.link,
    this.sticks = const [],
    this.copy,
    this.simulated = false,
    this.detail,
  });

  final ExportLink link;
  final List<UsbStick> sticks;

  /// Null while the service isn't connected: a copy's state is then unknown,
  /// and nothing claims the stick is safe to pull out.
  final CopyStatus? copy;

  /// The in-app simulation: no stick, nothing is copied.
  final bool simulated;

  /// Why the link is down.
  final String? detail;
}

@immutable
class StartResult {
  const StartResult({required this.started, this.detail = ''});

  final bool started;
  final String detail;
}

/// services/usb-export, or a simulation of it.
abstract class ExportSource {
  ValueListenable<ExportStatus> get status;
  void start();
  void stop();
  Future<RecordingList> list();
  Future<StartResult> startCopy(String device, List<RecordingFile> recordings);
  Future<bool> cancel();
}

/// usb-export isn't configured (no `EXPORT=`): the screen says so.
class UnavailableExportSource implements ExportSource {
  UnavailableExportSource([String why = 'usb-export isn\'t configured on this build (EXPORT=)'])
    : _status = ValueNotifier(ExportStatus(link: ExportLink.down, detail: why));

  final ValueNotifier<ExportStatus> _status;

  @override
  ValueListenable<ExportStatus> get status => _status;
  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<RecordingList> list() async =>
      RecordingList(driveMounted: false, problem: _status.value.detail ?? '');
  @override
  Future<StartResult> startCopy(String device, List<RecordingFile> recordings) async =>
      StartResult(started: false, detail: _status.value.detail ?? '');
  @override
  Future<bool> cancel() async => false;
}

/// A stick and recordings that don't exist, for the browser preview and the
/// tests. Labelled SIMULATED on screen. The copy moves on by itself every
/// [tick]; tests drive it with `tester.pump`.
class SimulatedExportSource implements ExportSource {
  SimulatedExportSource({
    List<RecordingFile>? recordings,
    UsbStick? stick = simulatedStick,
    this.tick = const Duration(milliseconds: 250),
    this.bytesPerTick = 40000000,
  }) : _recordings = recordings ?? simulatedRecordings(),
       _stick = stick {
    _publish();
  }

  static const simulatedStick = UsbStick(
    device: 'sdz1',
    role: StickRole.export,
    label: 'SIMULATED',
    model: 'Simulated stick',
    filesystem: 'exfat',
    freeBytes: 30000000000,
    totalBytes: 32000000000,
  );

  final Duration tick;
  final int bytesPerTick;
  List<RecordingFile> _recordings;
  UsbStick? _stick;
  CopyStatus _copy = const CopyStatus();
  Timer? _timer;
  int _nextId = 1;

  /// Pulls the stick out after this many bytes of the next copy.
  int? pullAfterBytes;

  final _status = ValueNotifier(const ExportStatus(link: ExportLink.up, simulated: true));

  @override
  ValueListenable<ExportStatus> get status => _status;

  UsbStick? get stick => _stick;

  set stick(UsbStick? s) {
    _stick = s;
    _publish();
  }

  set recordings(List<RecordingFile> r) => _recordings = r;

  void _publish() {
    _status.value = ExportStatus(
      link: ExportLink.up,
      simulated: true,
      sticks: [?_stick],
      copy: _copy,
    );
  }

  @override
  void start() {}

  @override
  void stop() => _timer?.cancel();

  @override
  Future<RecordingList> list() async => RecordingList(recordings: _recordings);

  @override
  Future<StartResult> startCopy(String device, List<RecordingFile> recordings) async {
    final s = _stick;
    if (_copy.running) {
      return const StartResult(started: false, detail: 'A copy is already running.');
    }
    if (s == null || s.device != device) {
      return const StartResult(started: false, detail: 'That stick isn\'t plugged in any more.');
    }
    if (!s.usable) return StartResult(started: false, detail: s.detail);
    if (recordings.isEmpty) {
      return const StartResult(started: false, detail: 'No recordings were chosen.');
    }
    final total = recordings.fold<int>(0, (a, r) => a + r.bytes);
    if (total > s.freeBytes) {
      _finish(
        CopyStatus(device: device, filesTotal: recordings.length, bytesTotal: total, id: _nextId++),
        CopyPhase.failed,
        'Not enough room on the stick (simulated). 0 of ${recordings.length} recordings are on the stick.',
      );
      return const StartResult(started: true);
    }
    _copy = CopyStatus(
      phase: CopyPhase.copying,
      device: device,
      filesTotal: recordings.length,
      bytesTotal: total,
      detail: 'Copying: leave the stick in.',
      safeToUnplug: false,
      id: _nextId++,
    );
    _publish();
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) => _step(recordings));
    return const StartResult(started: true);
  }

  void _step(List<RecordingFile> files) {
    final c = _copy;
    final done = (c.bytesDone + bytesPerTick).clamp(0, c.bytesTotal);
    final pull = pullAfterBytes;
    if (pull != null && done >= pull) {
      pullAfterBytes = null;
      _stick = null;
      _finish(
        c,
        CopyPhase.failed,
        'The stick was removed during the copy. ${c.filesDone} of ${c.filesTotal} recordings were finished before. Plug it in and copy again: the finished ones are skipped.',
      );
      return;
    }
    var acc = 0, filesDone = 0;
    for (final f in files) {
      if (acc + f.bytes > done) break;
      acc += f.bytes;
      filesDone++;
    }
    final current = filesDone < files.length ? files[filesDone].key : '';
    if (done >= c.bytesTotal) {
      _finish(
        _with(c, done, files.length, ''),
        CopyPhase.done,
        'Copied ${files.length} recording${files.length == 1 ? '' : 's'} to ${c.folder} on the stick.',
      );
      final s = _stick;
      if (s != null) _stick = _withFree(s, s.freeBytes - c.bytesTotal);
      _publish();
      return;
    }
    _copy = _with(c, done, filesDone, current);
    _publish();
  }

  static CopyStatus _with(CopyStatus c, int bytes, int files, String current) => CopyStatus(
    phase: c.phase,
    device: c.device,
    filesTotal: c.filesTotal,
    filesDone: files,
    bytesTotal: c.bytesTotal,
    bytesDone: bytes,
    current: current,
    detail: c.detail,
    safeToUnplug: c.safeToUnplug,
    id: c.id,
  );

  static UsbStick _withFree(UsbStick s, int free) => UsbStick(
    device: s.device,
    role: s.role,
    label: s.label,
    model: s.model,
    filesystem: s.filesystem,
    freeBytes: free,
    totalBytes: s.totalBytes,
    maxFileBytes: s.maxFileBytes,
    readOnly: s.readOnly,
    detail: s.detail,
  );

  void _finish(CopyStatus c, CopyPhase phase, String detail) {
    _timer?.cancel();
    _copy = CopyStatus(
      phase: phase,
      device: c.device,
      filesTotal: c.filesTotal,
      filesDone: c.filesDone,
      bytesTotal: c.bytesTotal,
      bytesDone: c.bytesDone,
      detail: detail,
      safeToUnplug: true,
      id: c.id,
    );
    _publish();
  }

  @override
  Future<bool> cancel() async {
    if (!_copy.running) return false;
    _finish(
      _copy,
      CopyPhase.cancelled,
      'Cancelled: ${_copy.filesDone} of ${_copy.filesTotal} recordings are on the stick.',
    );
    return true;
  }
}

/// Two runs of front and rear one-minute segments, a saved clip, and the
/// segment being written. Times are made up.
List<RecordingFile> simulatedRecordings() {
  final start = DateTime.utc(2026, 11, 12, 4, 52);
  final out = <RecordingFile>[
    // A run before the clock was trusted: no times.
    for (var s = 0; s < 2; s++)
      RecordingFile(
        camera: 'front',
        fileName: 'b00002-s${'$s'.padLeft(6, '0')}.mkv',
        bytes: 24000000,
        boot: 2,
        seq: s,
      ),
  ];
  for (var s = 0; s < 6; s++) {
    final t = start.add(Duration(minutes: s));
    final stamp = '${t.year}${_two(t.month)}${_two(t.day)}T${_two(t.hour)}${_two(t.minute)}00Z';
    for (final cam in ['front', 'rear']) {
      out.add(
        RecordingFile(
          camera: cam,
          fileName: 'b00003-s${'$s'.padLeft(6, '0')}-$stamp.mkv',
          bytes: cam == 'front' ? 24000000 : 110000000,
          boot: 3,
          seq: s,
          protected: s == 2,
          wallTime: t,
          beingWritten: s == 5,
        ),
      );
    }
  }
  return out;
}

String _two(int n) => n.toString().padLeft(2, '0');
