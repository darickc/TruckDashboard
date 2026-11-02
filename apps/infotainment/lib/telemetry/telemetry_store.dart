import 'package:flutter/foundation.dart';

import '../core/clock.dart';
import '../model/signal.dart';
import 'event_log.dart';
import 'poll_result.dart';
import 'signal_state.dart';
import 'warnings.dart';

/// Health of the vehicle-data link as the UI sees it.
enum LinkState {
  /// Nothing heard yet.
  connecting,

  /// Requests are being answered.
  up,

  /// Link is up but some watched signals are not updating.
  degraded,

  /// No vehicle data at all.
  down,
}

/// The UI's model of the vehicle: per-signal state, link health, alerts and
/// an event history.
///
/// Validity is computed here from timestamps on a monotonic clock, every time
/// [refresh] runs, not only when data arrives. So if the data source itself
/// dies, every value still ages into STALE and the dashboard says so.
class TelemetryStore extends ChangeNotifier {
  TelemetryStore({
    required List<SignalDef> catalog,
    required this.clock,
    required List<WarningRule> rules,
    this.watchedSignals = const [],
    this.linkLostAfter = const Duration(seconds: 3),
  })  : warnings = WarningEngine(rules),
        _order = [for (final d in catalog) d.id],
        states = {for (final d in catalog) d.id: SignalState(d)..reset()} {
    _linkSince = _startedAt = clock.now();
  }

  final MonotonicClock clock;
  final WarningEngine warnings;

  /// Signals whose silence raises a "not updating" alert.
  final List<String> watchedSignals;

  /// With no successful response for this long, the link counts as down.
  final Duration linkLostAfter;

  final Map<String, SignalState> states;
  final List<String> _order;
  final events = EventLog();

  LinkState _link = LinkState.connecting;
  late Duration _linkSince;
  late Duration _startedAt;
  bool _sourceReportsLinkDown = false;
  Duration? _lastAnyResponse;
  List<Alert> _alerts = const [];

  /// Recent request timestamps, for the requests/s readout.
  final _recentRequests = <Duration>[];

  LinkState get link => _link;
  Duration get linkSince => _linkSince;

  /// Active alerts, critical first, then oldest first.
  List<Alert> get alerts => _alerts;

  Iterable<SignalState> get ordered => _order.map((id) => states[id]!);

  SignalState? operator [](String id) => states[id];

  double requestsPerSecond(Duration now) {
    _recentRequests.removeWhere((t) => now - t > const Duration(seconds: 10));
    return _recentRequests.length / 10.0;
  }

  /// Clears everything (used when the simulated scenario changes).
  void reset() {
    for (final s in states.values) {
      s.reset();
    }
    warnings.reset();
    events.clear();
    _recentRequests.clear();
    _alerts = const [];
    _lastAnyResponse = null;
    _sourceReportsLinkDown = false;
    _link = LinkState.connecting;
    _linkSince = _startedAt = clock.now();
    notifyListeners();
  }

  /// Records one request outcome. Does not notify; call [refresh].
  void apply(PollResult r) {
    final s = states[r.signalId];
    if (s == null || !s.def.enabled || s.def.isComputed) return;
    if (r.outcome != PollOutcome.linkDown) _recentRequests.add(r.at);
    s.lastOutcome = r.outcome;
    s.lastOutcomeAt = r.at;
    s.lastLatencyMs = r.latencyMs ?? s.lastLatencyMs;
    if (r.responder != null) s.lastResponder = r.responder;
    switch (r.outcome) {
      case PollOutcome.response:
        final v = r.value!;
        _lastAnyResponse = r.at;
        if (v.isFinite && v >= s.def.min && v <= s.def.max) {
          s.lastGoodValue = v;
          s.lastGoodAt = r.at;
          s.lastRejectedValue = null;
          s.successes++;
          s.consecutiveFailures = 0;
        } else {
          s.lastRejectedValue = v;
          s.failures++;
          s.consecutiveFailures++;
        }
      case PollOutcome.negativeResponse:
        _lastAnyResponse = r.at; // the module answered; the link works
        s.lastNrc = r.nrc;
        s.failures++;
        s.consecutiveFailures++;
      case PollOutcome.invalidResponse:
        _lastAnyResponse = r.at;
        s.failures++;
        s.consecutiveFailures++;
      case PollOutcome.noResponse:
      case PollOutcome.linkDown:
        s.failures++;
        s.consecutiveFailures++;
    }
  }

  /// The data source's own view of the link (e.g. the adapter disconnected).
  void setSourceLinkDown(bool down) => _sourceReportsLinkDown = down;

  /// Recomputes validity, computed signals, link state and alerts.
  void refresh() {
    final now = clock.now();
    for (final s in states.values) {
      if (!s.def.isComputed) _updateValidity(s, now);
    }
    for (final s in states.values) {
      if (s.def.isComputed) _updateComputed(s);
    }
    _updateLink(now);
    _updateAlerts(now);
    notifyListeners();
  }

  void _updateValidity(SignalState s, Duration now) {
    final before = s.validity;
    final Validity next;
    if (!s.def.enabled) {
      next = Validity.disabled;
    } else if (s.lastRejectedValue != null && s.lastOutcome == PollOutcome.response) {
      // The latest answer was implausible. Say so; the last good value must
      // not stand in for it, however recent.
      next = Validity.outOfRange;
    } else if (s.lastGoodAt == null) {
      next = switch (s.lastOutcome) {
        PollOutcome.negativeResponse => Validity.unsupported,
        PollOutcome.invalidResponse => Validity.decodeError,
        _ => Validity.noData,
      };
    } else if (now - s.lastGoodAt! > s.def.staleAfter) {
      next = Validity.stale;
    } else {
      next = Validity.valid;
    }
    s.validity = next;
    s.value = next == Validity.valid ? s.lastGoodValue : null;
    if (before != next) _logTransition(s, before, next, now);
  }

  void _updateComputed(SignalState s) {
    final before = s.validity;
    final inputs = [for (final id in s.def.inputs) states[id]!];
    final bad = [for (final i in inputs) if (!i.isValid) i.def.id];
    Validity next;
    if (!s.def.enabled) {
      next = Validity.disabled;
    } else if (bad.isNotEmpty) {
      next = _worst(inputs.where((i) => !i.isValid).map((i) => i.validity));
    } else {
      final times = inputs.map((i) => i.lastGoodAt!).toList()..sort();
      next = times.last - times.first > s.def.maxInputSkew
          ? Validity.stale
          : Validity.valid;
    }
    double? v;
    if (next == Validity.valid) {
      v = s.def.compute!([for (final i in inputs) i.value!]);
      if (!v.isFinite || v < s.def.min || v > s.def.max) {
        next = Validity.outOfRange;
        v = null;
      }
    }
    s.invalidInputs = bad;
    s.validity = next;
    s.value = v;
    if (v != null) {
      s.lastGoodValue = v;
      s.lastGoodAt = inputs.map((i) => i.lastGoodAt!).reduce((a, b) => a < b ? a : b);
    }
    if (before != next) _logTransition(s, before, next, clock.now());
  }

  static Validity _worst(Iterable<Validity> vs) {
    const rank = [
      Validity.disabled,
      Validity.noData,
      Validity.unsupported,
      Validity.decodeError,
      Validity.stale,
      Validity.outOfRange,
    ];
    for (final r in rank) {
      if (vs.contains(r)) return r;
    }
    return Validity.stale;
  }

  void _updateLink(Duration now) {
    final before = _link;
    final last = _lastAnyResponse;
    final LinkState next;
    if (_sourceReportsLinkDown) {
      next = LinkState.down;
    } else if (last == null) {
      // Never answered: give it a grace period after start before calling
      // the link down.
      next = now - _startedAt > linkLostAfter ? LinkState.down : LinkState.connecting;
    } else if (now - last > linkLostAfter) {
      next = LinkState.down;
    } else if (watchedSignals.any((id) => states[id]?.isValid == false)) {
      next = LinkState.degraded;
    } else {
      next = LinkState.up;
    }
    if (next != before) {
      _link = next;
      _linkSince = now;
      events.add(TelemetryEvent(
          now,
          DateTime.now(),
          next == LinkState.down ? EventSeverity.critical : EventSeverity.info,
          'Link ${before.name} → ${next.name}'));
    }
  }

  void _updateAlerts(Duration now) {
    final (thresholds, changes) = warnings.evaluate(states, now);
    for (final (rule, from, to) in changes) {
      events.add(TelemetryEvent(
          now,
          DateTime.now(),
          switch (to) {
            AlertLevel.critical => EventSeverity.critical,
            AlertLevel.advisory => EventSeverity.advisory,
            AlertLevel.none => EventSeverity.info,
          },
          'Warning ${rule.id}: ${from.name} → ${to.name}'));
    }
    final comm = <Alert>[];
    if (_link == LinkState.down) {
      comm.add(Alert(
          id: 'link', kind: AlertKind.linkLost, level: AlertLevel.critical, since: _linkSince));
    } else if (_link != LinkState.connecting) {
      for (final id in watchedSignals) {
        final s = states[id];
        if (s == null || !s.def.enabled || s.isValid) continue;
        comm.add(Alert(
            id: 'stale:$id',
            kind: AlertKind.signalNotUpdating,
            level: AlertLevel.advisory,
            since: s.lastGoodAt ?? _linkSince,
            signalId: id));
      }
    }
    _alerts = [...comm, ...thresholds]
      ..sort((a, b) {
        final byLevel = b.level.index.compareTo(a.level.index);
        return byLevel != 0 ? byLevel : a.since.compareTo(b.since);
      });
  }

  void _logTransition(SignalState s, Validity from, Validity to, Duration now) {
    // Start-up noise (noData → valid) is not worth a log line.
    if (from == Validity.noData && to == Validity.valid) return;
    events.add(TelemetryEvent(
        now,
        DateTime.now(),
        to == Validity.valid ? EventSeverity.info : EventSeverity.advisory,
        '${s.def.shortName}: ${from.name} → ${to.name}'));
  }
}
