import '../model/signal.dart';
import 'signal_state.dart';

enum AlertLevel { none, advisory, critical }

enum AlertKind {
  /// A valid signal is beyond a configured threshold.
  threshold,

  /// A watched signal stopped updating while the link is up.
  signalNotUpdating,

  /// The whole vehicle-data link is down.
  linkLost,
}

/// One active alert. The UI builds its text (it knows the unit preference).
class Alert {
  const Alert({
    required this.id,
    required this.kind,
    required this.level,
    required this.since,
    this.signalId,
    this.rule,
  });

  final String id;
  final AlertKind kind;
  final AlertLevel level;
  final Duration since;
  final String? signalId;
  final WarningRule? rule;
}

enum Direction { above, below }

class Threshold {
  const Threshold(this.trigger, this.clear);

  /// Canonical units.
  final double trigger;

  /// Hysteresis: once raised, the level holds until the value passes back
  /// beyond [clear].
  final double clear;
}

/// "Only evaluate while `signal` is valid and above/below `value`", e.g. the
/// EOT–ECT delta only means something on a warm engine.
class Gate {
  const Gate(this.signalId, this.direction, this.value);

  final String signalId;
  final Direction direction;
  final double value;
}

class WarningRule {
  const WarningRule({
    required this.id,
    required this.signalId,
    required this.direction,
    this.advisory,
    this.critical,
    this.minDuration = Duration.zero,
    this.gate,
    this.note,
  });

  final String id;
  final String signalId;
  final Direction direction;
  final Threshold? advisory;
  final Threshold? critical;

  /// The condition must hold this long before the level is raised.
  final Duration minDuration;
  final Gate? gate;
  final String? note;

  static WarningRule fromJson(Map<String, dynamic> j) {
    Threshold? threshold(Object? t) {
      if (t == null) return null;
      final m = t as Map<String, dynamic>;
      return Threshold((m['trigger'] as num).toDouble(), (m['clear'] as num).toDouble());
    }

    Direction dir(Object? d) => switch (d) {
          'above' => Direction.above,
          'below' => Direction.below,
          _ => throw FormatException('direction must be above|below, got $d'),
        };

    final rule = WarningRule(
      id: j['id'] as String,
      signalId: j['signal'] as String,
      direction: dir(j['direction']),
      advisory: threshold(j['advisory']),
      critical: threshold(j['critical']),
      minDuration: Duration(milliseconds: (j['min_duration_ms'] as num?)?.toInt() ?? 0),
      gate: j['when'] == null
          ? null
          : Gate(j['when']['signal'] as String, dir(j['when']['direction']),
              (j['when']['value'] as num).toDouble()),
      note: j['note'] as String?,
    );
    rule._validate();
    return rule;
  }

  void _validate() {
    if (advisory == null && critical == null) {
      throw FormatException('$id: needs advisory and/or critical');
    }
    for (final t in [advisory, critical].whereType<Threshold>()) {
      final ok = direction == Direction.above ? t.clear <= t.trigger : t.clear >= t.trigger;
      if (!ok) throw FormatException('$id: clear must be on the safe side of trigger');
    }
  }

  bool _beyond(double v, double limit) =>
      direction == Direction.above ? v > limit : v < limit;

  /// The level [value] calls for, given the level currently held.
  AlertLevel target(double value, AlertLevel current) {
    final c = critical, a = advisory;
    if (c != null &&
        (_beyond(value, c.trigger) ||
            (current == AlertLevel.critical && _beyond(value, c.clear)))) {
      return AlertLevel.critical;
    }
    if (a != null &&
        (_beyond(value, a.trigger) ||
            (current != AlertLevel.none && _beyond(value, a.clear)))) {
      return AlertLevel.advisory;
    }
    // Held at critical with no advisory band: keep advisory semantics off.
    return AlertLevel.none;
  }
}

/// Evaluates threshold rules with hysteresis and minimum durations.
///
/// Rules never fire on a signal that is not [Validity.valid]. Losing data is
/// reported separately, as a communication alert, so a stale reading can never
/// raise or hold a threshold alert.
class WarningEngine {
  WarningEngine(this.rules);

  final List<WarningRule> rules;
  final _level = <String, AlertLevel>{};
  final _since = <String, Duration>{};
  final _pendingLevel = <String, AlertLevel>{};
  final _pendingSince = <String, Duration>{};

  void reset() {
    _level.clear();
    _since.clear();
    _pendingLevel.clear();
    _pendingSince.clear();
  }

  AlertLevel levelOf(String ruleId) => _level[ruleId] ?? AlertLevel.none;

  /// Returns the threshold alerts active after this evaluation, plus the rule
  /// ids whose level changed (for the event log).
  (List<Alert>, List<(WarningRule, AlertLevel, AlertLevel)>) evaluate(
      Map<String, SignalState> states, Duration now) {
    final changes = <(WarningRule, AlertLevel, AlertLevel)>[];
    final active = <Alert>[];
    for (final rule in rules) {
      final current = levelOf(rule.id);
      final next = _next(rule, states, now, current);
      if (next != current) {
        changes.add((rule, current, next));
        _level[rule.id] = next;
        _since[rule.id] = now;
      }
      if (next != AlertLevel.none) {
        active.add(Alert(
          id: 'rule:${rule.id}',
          kind: AlertKind.threshold,
          level: next,
          since: _since[rule.id]!,
          signalId: rule.signalId,
          rule: rule,
        ));
      }
    }
    return (active, changes);
  }

  AlertLevel _next(WarningRule rule, Map<String, SignalState> states,
      Duration now, AlertLevel current) {
    final s = states[rule.signalId];
    final gate = rule.gate;
    final gateOpen = gate == null ||
        (states[gate.signalId]?.isValid == true &&
            (gate.direction == Direction.above
                ? states[gate.signalId]!.value! > gate.value
                : states[gate.signalId]!.value! < gate.value));
    if (s == null || !s.isValid || !gateOpen) {
      _pendingLevel.remove(rule.id);
      return AlertLevel.none;
    }
    final target = rule.target(s.value!, current);
    if (target.index <= current.index) {
      _pendingLevel.remove(rule.id);
      return target; // lowering is immediate; hysteresis already applied
    }
    if (_pendingLevel[rule.id] != target) {
      _pendingLevel[rule.id] = target;
      _pendingSince[rule.id] = now;
    }
    if (now - _pendingSince[rule.id]! >= rule.minDuration) {
      _pendingLevel.remove(rule.id);
      return target;
    }
    return current;
  }
}
