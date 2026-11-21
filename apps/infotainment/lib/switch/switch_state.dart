import 'dart:async';

import 'package:flutter/foundation.dart';

/// The 5-way switch in the cab, as power-manager reports it (f250.power.v1
/// SwitchService, ADR-0051). power-manager reads the switch and sends each
/// press itself: a short press to audio-manager (media and calls), a long one
/// to camera-manager. The dashboard only shows the switch and sets which wire
/// is which direction, since that depends on how the switch is mounted.

/// One of the switch's five wires, named by the key the kernel gives it.
enum SwitchWire { f13, f14, f15, f16, f17 }

/// What a wire does.
enum SwitchRole { up, down, left, right, press }

enum PressKind { short, long }

extension SwitchWireName on SwitchWire {
  String get key => name.toUpperCase();
}

extension SwitchRoleText on SwitchRole {
  String get label => switch (this) {
        SwitchRole.up => 'Up',
        SwitchRole.down => 'Down',
        SwitchRole.left => 'Left',
        SwitchRole.right => 'Right',
        SwitchRole.press => 'Press',
      };

  /// What a short press does (as power-manager says it).
  String get shortAction => switch (this) {
        SwitchRole.up => 'volume up',
        SwitchRole.down => 'volume down',
        SwitchRole.left => 'previous track',
        SwitchRole.right => 'next track',
        SwitchRole.press => 'play/pause or call',
      };

  /// A short press, short enough for the drawn switch's tile.
  String get tileAction => switch (this) {
        SwitchRole.up => 'Volume +',
        SwitchRole.down => 'Volume −',
        SwitchRole.left => 'Previous',
        SwitchRole.right => 'Next',
        SwitchRole.press => 'Play/Pause',
      };

  /// A long press, for the tile.
  String get tileHold => switch (this) {
        SwitchRole.up => 'hold: Front',
        SwitchRole.down => 'hold: Rear',
        SwitchRole.left => 'hold: Left',
        SwitchRole.right => 'hold: Right',
        SwitchRole.press => 'hold: Close',
      };

  /// What a long press does.
  String get longAction => switch (this) {
        SwitchRole.up => 'front camera',
        SwitchRole.down => 'rear camera',
        SwitchRole.left => 'left camera',
        SwitchRole.right => 'right camera',
        SwitchRole.press => 'close camera',
      };
}

/// The wiring doc's: BCM6 up, BCM16 down, BCM12 left, BCM13 right, BCM17
/// press (docs/wiring/power-and-inputs.md).
const defaultSwitchMapping = {
  SwitchWire.f13: SwitchRole.left,
  SwitchWire.f14: SwitchRole.right,
  SwitchWire.f15: SwitchRole.down,
  SwitchWire.f16: SwitchRole.up,
  SwitchWire.f17: SwitchRole.press,
};

/// The GPIO each wire is on, as power-manager says (for the simulation).
const defaultSwitchPins = {
  SwitchWire.f13: 'BCM12, pin 32',
  SwitchWire.f14: 'BCM13, pin 33',
  SwitchWire.f15: 'BCM16, pin 36',
  SwitchWire.f16: 'BCM6, pin 31',
  SwitchWire.f17: 'BCM17, pin 11',
};

@immutable
class WireInfo {
  const WireInfo({required this.wire, required this.pin, required this.role, required this.present});

  final SwitchWire wire;

  /// "BCM12, pin 32".
  final String pin;
  final SwitchRole role;

  /// An input device with this wire's key is open.
  final bool present;

  @override
  bool operator ==(Object other) =>
      other is WireInfo &&
      other.wire == wire &&
      other.pin == pin &&
      other.role == role &&
      other.present == present;

  @override
  int get hashCode => Object.hash(wire, pin, role, present);
}

/// power-manager's state of the switch.
@immutable
class SwitchReport {
  const SwitchReport({
    required this.wires,
    required this.learning,
    required this.learningTimeoutS,
    required this.longPressMs,
    required this.defaultMapping,
    this.problem = '',
  });

  /// All five, in wire order.
  final List<WireInfo> wires;

  /// Presses are reported, not sent.
  final bool learning;
  final int learningTimeoutS;
  final int longPressMs;
  final bool defaultMapping;

  /// Why the switch can't be read or the directions weren't loaded or saved.
  final String problem;

  /// The wire with [role], if any.
  WireInfo? wireFor(SwitchRole role) {
    for (final w in wires) {
      if (w.role == role) return w;
    }
    return null;
  }

  WireInfo? info(SwitchWire wire) {
    for (final w in wires) {
      if (w.wire == wire) return w;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is SwitchReport &&
      listEquals(other.wires, wires) &&
      other.learning == learning &&
      other.learningTimeoutS == learningTimeoutS &&
      other.longPressMs == longPressMs &&
      other.defaultMapping == defaultMapping &&
      other.problem == problem;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(wires), learning, learningTimeoutS, longPressMs, defaultMapping, problem);
}

/// One press as power-manager reported it. The same [seq] may come twice:
/// first what it will do, then what became of it.
@immutable
class SwitchPress {
  const SwitchPress(
      {required this.wire, required this.role, required this.kind, required this.result, required this.seq});

  final SwitchWire wire;
  final SwitchRole role;
  final PressKind kind;

  /// "volume up → Volume 16.", "learning: not sent".
  final String result;
  final int seq;

  @override
  bool operator ==(Object other) =>
      other is SwitchPress &&
      other.wire == wire &&
      other.role == role &&
      other.kind == kind &&
      other.result == result &&
      other.seq == seq;

  @override
  int get hashCode => Object.hash(wire, role, kind, result, seq);
}

enum SwitchLink {
  /// No power-manager: the browser preview, the macOS window, tests.
  simulated,
  connecting,
  connected,
  lost,
}

@immutable
class SwitchStatus {
  const SwitchStatus({required this.link, this.report, this.lastPress, this.detail = ''});

  final SwitchLink link;

  /// The last report while connected (or simulated); null otherwise.
  final SwitchReport? report;

  /// The latest press since the link came up; null before one.
  final SwitchPress? lastPress;

  /// Why the link is down.
  final String detail;

  bool get usable => report != null && (link == SwitchLink.connected || link == SwitchLink.simulated);

  @override
  bool operator ==(Object other) =>
      other is SwitchStatus &&
      other.link == link &&
      other.report == report &&
      other.lastPress == lastPress &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(link, report, lastPress, detail);
}

/// What a change of the directions came to.
@immutable
class SwitchSaveResult {
  const SwitchSaveResult({required this.saved, required this.detail});

  final bool saved;
  final String detail;
}

/// Where the switch comes from: power-manager, or a simulation.
abstract class SwitchSource {
  ValueListenable<SwitchStatus> get status;

  void start();
  void stop();

  /// While on, power-manager reports presses and sends none.
  Future<void> setLearning(bool on);

  /// Saves which wire is which direction (every wire a different one) and
  /// ends learning.
  Future<SwitchSaveResult> setMapping(Map<SwitchWire, SwitchRole> mapping);

  /// Back to [defaultSwitchMapping], saved.
  Future<SwitchSaveResult> resetMapping();
}

/// No power-manager and no switch: the screen can be tried with
/// [simulatePress], which the screen offers as SIMULATED buttons.
class SimulatedSwitchSource implements SwitchSource {
  SimulatedSwitchSource({this.longPressMs = 600, this.learningTimeoutS = 60}) {
    _publish();
  }

  final int longPressMs;
  final int learningTimeoutS;

  Map<SwitchWire, SwitchRole> _mapping = Map.of(defaultSwitchMapping);
  bool _learning = false;
  SwitchPress? _last;
  int _seq = 0;
  final _status = ValueNotifier(const SwitchStatus(link: SwitchLink.simulated));

  @override
  ValueListenable<SwitchStatus> get status => _status;

  @override
  void start() {}

  @override
  void stop() {}

  /// A press of [wire], as if the switch were there. Nothing is sent
  /// anywhere: there is no audio-manager or camera-manager behind it.
  void simulatePress(SwitchWire wire, {PressKind kind = PressKind.short}) {
    final role = _mapping[wire]!;
    final action = kind == PressKind.short ? role.shortAction : role.longAction;
    _last = SwitchPress(
        wire: wire,
        role: role,
        kind: kind,
        result: _learning ? 'learning: not sent' : '$action: simulated, not sent',
        seq: ++_seq);
    _publish();
  }

  @override
  Future<void> setLearning(bool on) async {
    _learning = on;
    _publish();
  }

  @override
  Future<SwitchSaveResult> setMapping(Map<SwitchWire, SwitchRole> mapping) async {
    final why = checkMapping(mapping);
    if (why != null) return SwitchSaveResult(saved: false, detail: why);
    _mapping = Map.of(mapping);
    _learning = false;
    _publish();
    return const SwitchSaveResult(saved: true, detail: 'Simulated: kept until the app closes.');
  }

  @override
  Future<SwitchSaveResult> resetMapping() => setMapping(defaultSwitchMapping);

  void _publish() {
    _status.value = SwitchStatus(
      link: SwitchLink.simulated,
      lastPress: _last,
      report: SwitchReport(
        wires: [
          for (final w in SwitchWire.values)
            WireInfo(wire: w, pin: defaultSwitchPins[w]!, role: _mapping[w]!, present: true),
        ],
        learning: _learning,
        learningTimeoutS: learningTimeoutS,
        longPressMs: longPressMs,
        defaultMapping: mapEquals(_mapping, defaultSwitchMapping),
      ),
    );
  }
}

/// Why [mapping] can't be saved, in words for the screen; null if it can.
String? checkMapping(Map<SwitchWire, SwitchRole> mapping) {
  for (final w in SwitchWire.values) {
    if (!mapping.containsKey(w)) return 'Wire ${w.key} has no direction.';
  }
  for (final r in SwitchRole.values) {
    final n = mapping.values.where((v) => v == r).length;
    if (n != 1) return 'Every direction must be on one wire: ${r.label} is on $n.';
  }
  return null;
}
