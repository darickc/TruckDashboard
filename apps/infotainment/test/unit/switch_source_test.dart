import 'package:f250_infotainment/gen/f250/power/v1/switch.pb.dart' as pb;
import 'package:f250_infotainment/switch/grpc_switch_source.dart';
import 'package:f250_infotainment/switch/switch_state.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('power-manager\'s state reads as the model, unknown wires left out', () {
    final r = reportFromPb(pb.SwitchState(
      wires: [
        pb.WireInfo(wire: pb.Wire.WIRE_F16, pin: 'BCM6, pin 31', role: pb.Role.ROLE_UP, present: true),
        pb.WireInfo(wire: pb.Wire.WIRE_F13, pin: 'BCM12, pin 32', role: pb.Role.ROLE_LEFT),
        pb.WireInfo(wire: pb.Wire.WIRE_UNSPECIFIED, role: pb.Role.ROLE_DOWN),
      ],
      learning: true,
      learningTimeoutS: 60,
      longPressMs: 600,
      defaultMapping: true,
      problem: 'no device',
    ));
    expect(r.wires.length, 2);
    expect(r.wireFor(SwitchRole.up)!.pin, 'BCM6, pin 31');
    expect(r.info(SwitchWire.f13)!.present, isFalse);
    expect((r.learning, r.longPressMs, r.defaultMapping, r.problem), (true, 600, true, 'no device'));
  });

  test('presses read as the model; an unknown role is dropped', () {
    final p = pressFromPb(pb.Press(
        wire: pb.Wire.WIRE_F15,
        role: pb.Role.ROLE_DOWN,
        kind: pb.PressKind.PRESS_KIND_LONG,
        result: 'rear camera → rear camera (live)',
        seq: Int64(7)));
    expect(p, const SwitchPress(
        wire: SwitchWire.f15, role: SwitchRole.down, kind: PressKind.long, result: 'rear camera → rear camera (live)', seq: 7));
    expect(pressFromPb(pb.Press(wire: pb.Wire.WIRE_F15)), isNull);
  });

  test('wires and roles round-trip', () {
    for (final w in SwitchWire.values) {
      expect(wireFromPb(wireToPb(w)), w);
    }
    for (final r in SwitchRole.values) {
      expect(roleFromPb(roleToPb(r)), r);
    }
  });

  test('a mapping must put every direction on one wire', () {
    expect(checkMapping(defaultSwitchMapping), isNull);
    final twice = Map.of(defaultSwitchMapping)..[SwitchWire.f13] = SwitchRole.up;
    expect(checkMapping(twice), 'Every direction must be on one wire: Up is on 2.');
    final missing = Map.of(defaultSwitchMapping)..remove(SwitchWire.f17);
    expect(checkMapping(missing), 'Wire F17 has no direction.');
  });
}
