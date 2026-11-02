import 'dart:collection';

enum EventSeverity { info, advisory, critical }

class TelemetryEvent {
  const TelemetryEvent(this.at, this.wallTime, this.severity, this.message);

  /// Monotonic time.
  final Duration at;
  final DateTime wallTime;
  final EventSeverity severity;
  final String message;
}

/// Bounded, newest-first event history. Bounded so that a flapping signal
/// cannot grow memory without limit. Phase 3's recorder persists the
/// gateway's equivalent.
class EventLog {
  EventLog({this.capacity = 300});

  final int capacity;
  final _events = ListQueue<TelemetryEvent>();
  int _dropped = 0;

  Iterable<TelemetryEvent> get newestFirst => _events;
  int get dropped => _dropped;
  int get length => _events.length;

  void add(TelemetryEvent e) {
    _events.addFirst(e);
    while (_events.length > capacity) {
      _events.removeLast();
      _dropped++;
    }
  }

  /// Replaces the history with events from elsewhere (the gateway), newest
  /// first.
  void replaceAll(Iterable<TelemetryEvent> newestFirst, {int dropped = 0}) {
    _events
      ..clear()
      ..addAll(newestFirst.take(capacity));
    _dropped = dropped;
  }

  void clear() {
    _events.clear();
    _dropped = 0;
  }
}
