import 'package:f250_infotainment/core/clock.dart';
import 'package:f250_infotainment/model/signal.dart';
import 'package:f250_infotainment/model/signal_catalog.dart';
import 'package:f250_infotainment/telemetry/poll_result.dart';
import 'package:f250_infotainment/telemetry/telemetry_store.dart';
import 'package:f250_infotainment/telemetry/warnings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeMonotonicClock clock;
  late TelemetryStore store;

  setUp(() {
    clock = FakeMonotonicClock();
    store = TelemetryStore(
        catalog: signalCatalog, clock: clock, rules: const [], watchedSignals: const ['eot']);
  });

  void respond(String id, double v) => store.apply(PollResult(
      signalId: id, at: clock.now(), outcome: PollOutcome.response, value: v));

  void fail(String id, PollOutcome o, {int? nrc}) =>
      store.apply(PollResult(signalId: id, at: clock.now(), outcome: o, nrc: nrc));

  void tick(Duration d) {
    clock.advance(d);
    store.refresh();
  }

  group('validity', () {
    test('starts as NO_DATA; disabled signals are DISABLED', () {
      store.refresh();
      expect(store['eot']!.validity, Validity.noData);
      expect(store['egt']!.validity, Validity.disabled);
    });

    test('a response is VALID until staleAfter passes without another', () {
      respond('eot', 90);
      store.refresh();
      expect(store['eot']!.validity, Validity.valid);
      expect(store['eot']!.value, 90);
      tick(signalsById['eot']!.staleAfter);
      expect(store['eot']!.validity, Validity.valid, reason: 'exactly at the limit');
      tick(const Duration(milliseconds: 1));
      expect(store['eot']!.validity, Validity.stale);
    });

    test('a stale signal exposes no current value, only last-good + age', () {
      respond('eot', 90);
      tick(const Duration(seconds: 10));
      final s = store['eot']!;
      expect(s.value, isNull);
      expect(s.lastGoodValue, 90);
      expect(s.ageAt(clock.now()), const Duration(seconds: 10));
    });

    test('timeouts do not change the value; it only ages', () {
      respond('eot', 90);
      clock.advance(const Duration(seconds: 1));
      fail('eot', PollOutcome.noResponse);
      store.refresh();
      expect(store['eot']!.validity, Validity.valid);
      expect(store['eot']!.value, 90);
      expect(store['eot']!.consecutiveFailures, 1);
    });

    test('goes stale even if the data source stops entirely', () {
      // No apply() calls at all after the first: only refresh() runs.
      respond('eot', 90);
      store.refresh();
      for (var i = 0; i < 50; i++) {
        tick(const Duration(milliseconds: 100));
      }
      expect(store['eot']!.validity, Validity.stale);
    });

    test('negative response before any data → UNSUPPORTED with the NRC', () {
      fail('icp', PollOutcome.negativeResponse, nrc: 0x31);
      store.refresh();
      expect(store['icp']!.validity, Validity.unsupported);
      expect(store['icp']!.lastNrc, 0x31);
    });

    test('undecodable response before any data → DECODE_ERROR', () {
      fail('map', PollOutcome.invalidResponse);
      store.refresh();
      expect(store['map']!.validity, Validity.decodeError);
    });

    test('an implausible value is never shown and never becomes last-good', () {
      respond('trans_temp', 55);
      clock.advance(const Duration(seconds: 1));
      respond('trans_temp', 400);
      store.refresh();
      final s = store['trans_temp']!;
      expect(s.validity, Validity.outOfRange);
      expect(s.value, isNull);
      expect(s.lastGoodValue, 55);
      expect(s.lastRejectedValue, 400);
      clock.advance(const Duration(seconds: 1));
      respond('trans_temp', 56);
      store.refresh();
      expect(s.validity, Validity.valid);
      expect(s.value, 56);
    });
  });

  group('computed signals', () {
    test('EOT−ECT is computed when both inputs are current', () {
      respond('eot', 100);
      respond('ect', 90);
      store.refresh();
      expect(store['eot_ect_delta']!.validity, Validity.valid);
      expect(store['eot_ect_delta']!.value, closeTo(10, 1e-9));
    });

    test('hidden — not even last-good — when an input is stale', () {
      respond('eot', 100);
      respond('ect', 90);
      store.refresh();
      for (var i = 0; i < 10; i++) {
        clock.advance(const Duration(milliseconds: 500));
        respond('ect', 90); // ECT keeps updating; EOT has frozen
      }
      store.refresh();
      final d = store['eot_ect_delta']!;
      expect(store['eot']!.validity, Validity.stale);
      expect(d.validity, Validity.stale);
      expect(d.value, isNull);
      expect(d.invalidInputs, ['eot']);
    });

    test('inputs measured too far apart make the result stale', () {
      respond('ect', 90);
      clock.advance(const Duration(seconds: 3)); // > maxInputSkew (2 s), < staleAfter (4 s)
      respond('eot', 100);
      store.refresh();
      expect(store['eot']!.isValid, isTrue);
      expect(store['ect']!.isValid, isTrue);
      expect(store['eot_ect_delta']!.validity, Validity.stale);
    });

    test('boost = MAP − baro', () {
      respond('map', 185);
      respond('baro', 85);
      store.refresh();
      expect(store['boost']!.value, closeTo(100, 1e-9));
    });
  });

  group('link', () {
    test('connecting → up → down after silence', () {
      store.refresh();
      expect(store.link, LinkState.connecting);
      respond('eot', 90);
      store.refresh();
      expect(store.link, LinkState.up);
      tick(store.linkLostAfter + const Duration(milliseconds: 1));
      expect(store.link, LinkState.down);
      expect(store.alerts.first.kind, AlertKind.linkLost);
      expect(store.alerts.first.level, AlertLevel.critical);
    });

    test('negative responses still prove the link is alive', () {
      respond('eot', 90);
      store.refresh();
      for (var i = 0; i < 10; i++) {
        clock.advance(const Duration(seconds: 1));
        fail('icp', PollOutcome.negativeResponse, nrc: 0x31);
      }
      store.refresh();
      expect(store.link, isNot(LinkState.down));
    });

    test('a watched signal going stale degrades the link and raises an advisory', () {
      respond('eot', 90);
      store.refresh();
      for (var i = 0; i < 10; i++) {
        clock.advance(const Duration(milliseconds: 500));
        respond('rpm', 700);
      }
      store.refresh();
      expect(store.link, LinkState.degraded);
      final a = store.alerts.single;
      expect(a.kind, AlertKind.signalNotUpdating);
      expect(a.signalId, 'eot');
      expect(a.level, AlertLevel.advisory);
    });

    test('a disabled watched signal does not degrade the link', () {
      final s = TelemetryStore(
          catalog: signalCatalog, clock: clock, rules: const [], watchedSignals: const ['egt']);
      s.apply(PollResult(
          signalId: 'rpm', at: clock.now(), outcome: PollOutcome.response, value: 700));
      s.refresh();
      expect(s.link, LinkState.up, reason: 'egt is disabled (no probe), never polled');
    });

    test('source-reported link loss wins immediately', () {
      respond('eot', 90);
      store.setSourceLinkDown(true);
      store.refresh();
      expect(store.link, LinkState.down);
    });

    test('never answered: connecting during the grace period, then down', () {
      tick(const Duration(seconds: 1));
      expect(store.link, LinkState.connecting);
      tick(store.linkLostAfter);
      expect(store.link, LinkState.down);
    });
  });

  test('reset clears every reading, counter, alert and event', () {
    respond('eot', 90);
    tick(const Duration(seconds: 10));
    expect(store.events.length, greaterThan(0));
    store.reset();
    expect(store['eot']!.lastGoodValue, isNull);
    expect(store['eot']!.successes, 0);
    expect(store.alerts, isEmpty);
    expect(store.events.length, 0);
    expect(store.link, LinkState.connecting);
  });

  test('event log is bounded', () {
    for (var i = 0; i < 400; i++) {
      respond('eot', 90);
      store.refresh(); // → valid
      tick(const Duration(seconds: 5)); // → stale
    }
    expect(store.events.length, store.events.capacity);
    expect(store.events.dropped, greaterThan(0));
  });
}
