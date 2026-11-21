// Runs the real services/power-manager binary with the 5-way switch on a
// FIFO (evdev events written here) and reads it through the app's switch
// source: the Rust server and the Dart client agree on f250.power.v1
// SwitchService, learning reports presses, and a saved mapping comes back.
// Skipped unless the binary is built: `cargo build -p power-manager`
// (make ui-test does this).
@Tags(['integration'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:f250_infotainment/data/gateway_connection.dart';
import 'package:f250_infotainment/switch/grpc_switch_source.dart';
import 'package:f250_infotainment/switch/switch_state.dart';
import 'package:flutter_test/flutter_test.dart';

final _root = Directory.current.parent.parent.path; // apps/infotainment → repo
final _bin = File('$_root/target/debug/power-manager');

Future<void> _until(bool Function() ok, {Duration timeout = const Duration(seconds: 10)}) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('condition not met within $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// One evdev key event, as the kernel writes it (24 bytes on 64-bit).
Uint8List _key(int code, bool down) {
  final b = ByteData(24);
  b.setUint16(16, 1, Endian.host); // EV_KEY
  b.setUint16(18, code, Endian.host);
  b.setInt32(20, down ? 1 : 0, Endian.host);
  return b.buffer.asUint8List();
}

void main() {
  final skip = _bin.existsSync() ? false : 'build power-manager first: cargo build -p power-manager';

  test('the switch\'s state, learning and a saved mapping between the app and power-manager', () async {
    final dir = Directory.systemTemp.createTempSync('f250-swit');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/sys').createSync();
    final fifo = '${dir.path}/switch';
    await Process.run('mkfifo', [fifo]);
    final sock = '${dir.path}/p.sock';
    final pm = await Process.start(_bin.path, [
      '--dry-run',
      '--sysfs', '${dir.path}/sys',
      '--backlight=none',
      '--display-listen', 'unix:$sock',
      '--switch-device', fifo,
      '--switch-state', '${dir.path}/mapping',
      '--switch-debounce-ms=10',
      '--switch-long-press-ms=300',
    ]);
    pm.stdout.listen((_) {});
    pm.stderr.listen((_) {});
    addTearDown(pm.kill);
    await _until(() => File(sock).existsSync());

    final src = GrpcSwitchSource(endpoint: UnixEndpoint(sock), retryDelay: const Duration(milliseconds: 200))
      ..start();
    addTearDown(src.stop);
    // Opening the FIFO waits for power-manager's reader.
    final w = File(fifo).openSync(mode: FileMode.writeOnly);
    addTearDown(w.closeSync);
    Future<void> push(int code) async {
      w.writeFromSync(_key(code, true));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      w.writeFromSync(_key(code, false));
    }

    await _until(() => src.status.value.report?.wires.every((x) => x.present) ?? false);
    var r = src.status.value.report!;
    expect(src.status.value.link, SwitchLink.connected);
    expect(r.defaultMapping, isTrue);
    expect(r.longPressMs, 300);
    expect(r.wireFor(SwitchRole.up)!.pin, 'BCM6, pin 31');

    await push(186); // F16, up by default
    await _until(() => src.status.value.lastPress?.result.contains('not sent') ?? false);
    final p = src.status.value.lastPress!;
    expect((p.wire, p.role, p.kind), (SwitchWire.f16, SwitchRole.up, PressKind.short));
    expect(p.result, 'volume up: not sent: no audio-manager');

    await src.setLearning(true);
    expect(src.status.value.report!.learning, isTrue);
    await push(183); // F13
    await _until(() => src.status.value.lastPress?.wire == SwitchWire.f13);
    expect(src.status.value.lastPress!.result, 'learning: not sent');

    final turned = {
      SwitchWire.f13: SwitchRole.up,
      SwitchWire.f14: SwitchRole.down,
      SwitchWire.f15: SwitchRole.left,
      SwitchWire.f16: SwitchRole.right,
      SwitchWire.f17: SwitchRole.press,
    };
    final saved = await src.setMapping(turned);
    expect(saved.saved, isTrue, reason: saved.detail);
    r = src.status.value.report!;
    expect(r.learning, isFalse);
    expect(r.defaultMapping, isFalse);
    expect(r.wireFor(SwitchRole.up)!.wire, SwitchWire.f13);
    expect(File('${dir.path}/mapping').readAsStringSync(), contains('F13 up\n'));

    final reset = await src.resetMapping();
    expect(reset.saved, isTrue);
    expect(src.status.value.report!.defaultMapping, isTrue);

    // power-manager gone: nothing shown as current.
    pm.kill();
    await _until(() => src.status.value.link == SwitchLink.lost);
    expect(src.status.value.report, isNull);
  }, skip: skip);
}
