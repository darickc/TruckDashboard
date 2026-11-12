import 'package:f250_infotainment/export/export_state.dart';
import 'package:f250_infotainment/export/grpc_export_source.dart';
import 'package:f250_infotainment/export/recording_selection.dart';
import 'package:f250_infotainment/gen/f250/export/v1/export.pb.dart' as pb;
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

/// Choosing recordings to copy to a USB stick (ADR-0037). `[SIM]`.

RecordingFile rec(
  String camera,
  int boot,
  int seq, {
  int bytes = 100,
  bool saved = false,
  bool writing = false,
}) => RecordingFile(
  camera: camera,
  fileName: 'b${'$boot'.padLeft(5, '0')}-s${'$seq'.padLeft(6, '0')}.mkv',
  bytes: bytes,
  boot: boot,
  seq: seq,
  protected: saved,
  beingWritten: writing,
);

void main() {
  final list = [
    rec('front', 1, 0),
    rec('rear', 1, 0, bytes: 400),
    rec('front', 1, 1, saved: true),
    rec('rear', 1, 1, bytes: 400),
    rec('front', 1, 2),
    rec('front', 1, 3, writing: true),
  ];
  List<String> keys(Iterable<RecordingFile> r) => [for (final x in r) x.key];

  test('a tap chooses and unchooses one; a recording being written never', () {
    final s = RecordingSelection()..setRecordings(list);
    s.tap(list[1]);
    expect(keys(s.chosen), ['rear/b00001-s000000.mkv']);
    expect(s.chosenBytes, 400);
    s.tap(list[1]);
    expect(s.chosen, isEmpty);
    s.tap(list[5]);
    expect(s.chosen, isEmpty);
  });

  test('a range is everything shown between two taps, either way round', () {
    final s = RecordingSelection()
      ..setRecordings(list)
      ..filter = RecordingFilter.front
      ..toggleRangeMode();
    s.tap(list[5]); // being written: not an anchor
    expect(s.anchor, isNull);
    s.tap(list[4]);
    expect(s.anchor, list[4].key);
    s.tap(list[0]);
    expect(s.rangeMode, isFalse, reason: 'one range per press of Range');
    expect(keys(s.chosen), [
      list[0].key,
      list[2].key,
      list[4].key,
    ], reason: 'front only (the filter), the saved clip included');
  });

  test('a filter hides but keeps choices; All shown skips the one being written', () {
    final s = RecordingSelection()..setRecordings(list);
    s.filter = RecordingFilter.rear;
    expect(keys(s.shown), [list[1].key, list[3].key]);
    s.chooseAllShown();
    s.filter = RecordingFilter.saved;
    expect(keys(s.shown), [list[2].key]);
    s.chooseAllShown();
    expect(s.chosen.length, 3);
    s.filter = RecordingFilter.all;
    s.chooseAllShown();
    expect(s.chosen.length, 5, reason: 'not the one being written');
    s.clear();
    expect(s.chosen, isEmpty);
  });

  test('a new list keeps what is still there and drops the rest', () {
    final s = RecordingSelection()..setRecordings(list);
    s.chooseAllShown();
    // Retention deleted the oldest front; the newest finished; one more is
    // being written.
    s.setRecordings([...list.sublist(1, 5), rec('front', 1, 3), rec('front', 1, 4, writing: true)]);
    expect(keys(s.chosen), keys(list.sublist(1, 5)));
  });

  test('fit: nothing chosen, no stick, a map stick, too big, FAT file limit', () {
    final s = RecordingSelection()..setRecordings(list);
    const stick = UsbStick(device: 'sda1', role: StickRole.export, freeBytes: 500);
    expect(s.fitOn(stick), Fit.nothingChosen);
    s.tap(list[1]);
    expect(s.fitOn(null), Fit.noStick);
    expect(
      s.fitOn(const UsbStick(device: 'sda1', role: StickRole.map, freeBytes: 1 << 40)),
      Fit.noStick,
    );
    expect(s.fitOn(stick), Fit.fits);
    s.tap(list[3]);
    expect(s.fitOn(stick), Fit.tooBig);
    expect(
      s.fitOn(
        const UsbStick(
          device: 'sda1',
          role: StickRole.export,
          freeBytes: 1 << 40,
          maxFileBytes: 300,
        ),
      ),
      Fit.fileTooBig,
    );
  });

  test('sizes read like a stick\'s label', () {
    expect(formatSize(28100000000), '28.1 GB');
    expect(formatSize(340400000), '340 MB');
    expect(formatSize(1), '1 kB');
  });

  test('usb-export\'s messages map to the model; unknown roles are never copied to', () {
    final r = recordingFromPb(
      pb.Recording(
        camera: 'front',
        fileName: 'b00003-s000001-20261112T045215Z.mkv',
        bytes: Int64(23645936),
        boot: 3,
        seq: 1,
        wallTime: Int64(1794459135),
      ),
    );
    expect(r.wallTime, DateTime.utc(2026, 11, 12, 4, 52, 15));
    expect(
      recordingFromPb(pb.Recording(camera: 'rear')).wallTime,
      isNull,
      reason: '0: time unknown',
    );
    final s = statusFromPb(
      pb.WatchExportResponse(
        sticks: [
          pb.Stick(device: 'sda1', role: pb.StickRole.STICK_ROLE_EXPORT, freeBytes: Int64(5)),
          pb.Stick(
            device: 'sdb1',
            role: pb.StickRole.valueOf(99) ?? pb.StickRole.STICK_ROLE_UNSPECIFIED,
          ),
        ],
        copy: pb.Copy(
          state: pb.CopyState.COPY_STATE_COPYING,
          bytesTotal: Int64(10),
          bytesDone: Int64(5),
        ),
      ),
    );
    expect(s.sticks.map((k) => k.role), [StickRole.export, StickRole.unusable]);
    expect(s.copy!.phase, CopyPhase.copying);
    expect(s.copy!.fraction, 0.5);
    expect(s.copy!.safeToUnplug, isFalse, reason: 'only when the service says so');
  });
}
