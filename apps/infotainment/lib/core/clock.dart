/// Monotonic time source. Ages and staleness are measured on this clock, never
/// on wall time, so an RTC or GPS time jump cannot make a stale value look
/// fresh.
abstract class MonotonicClock {
  Duration now();
}

class SystemMonotonicClock implements MonotonicClock {
  SystemMonotonicClock() : _watch = Stopwatch()..start();

  final Stopwatch _watch;

  @override
  Duration now() => _watch.elapsed;
}

/// Manually advanced clock for tests.
class FakeMonotonicClock implements MonotonicClock {
  FakeMonotonicClock([this._now = Duration.zero]);

  Duration _now;

  @override
  Duration now() => _now;

  void advance(Duration d) => _now += d;
}
