// Unit tests: PID scheduler — due selection, priority, failure backoff,
// unverified-header skipping, millis() wraparound, runtime add/remove,
// per-PID statistics, and the throughput-budget calculation.

#include <unity.h>

#include "PidScheduler.h"

using namespace obd;

extern "C" {
void setUp(void) {}
void tearDown(void) {}
}

// A private mini-table so the tests control intervals/priorities exactly.
static const PidDefinition kTestTable[] = {
    // fast, highest priority
    {PidKey::RpmSae, ChannelId::Rpm, "RPM", "RPM", 0x01, 0x0C, ObdModule::Auto,
     /*resp=*/0, /*count=*/0,
     {0, 2, false, 0.25f, 0.0f}, nullptr, Unit::Rpm, 100, 0, 500, 2, true},
    // slower, lower priority
    {PidKey::EctSae, ChannelId::EctF, "ECT", "ECT", 0x01, 0x05, ObdModule::Auto,
     /*resp=*/0, /*count=*/0,
     {0, 1, false, 1.0f, -40.0f}, nullptr, Unit::Celsius, 500, 3, 500, 2, true},
    // unverified module header — must be skipped at registration
    {PidKey::TransTemp2, ChannelId::TransTempF, "TransTCM", "TT2", 0x22, 0x1674,
     ObdModule::Tcm, /*resp=*/0, /*count=*/0,
     {0, 2, false, 0.125f, 0.0f}, nullptr, Unit::Fahrenheit,
     500, 3, 500, 2, false},
};
static const size_t kTestTableSize = sizeof(kTestTable) / sizeof(kTestTable[0]);

static ElmResponse ok(uint16_t latencyMs = 40)
{
    ElmResponse r;
    r.result = ElmResult::Ok;
    r.latencyMs = latencyMs;
    r.responderId = 0x7E8;
    r.responderCount = 1;
    return r;
}

static ElmResponse fail(ElmResult which = ElmResult::Timeout)
{
    ElmResponse r;
    r.result = which;
    return r;
}

/// An Ok response where two ECUs each returned a 2-byte payload.
static ElmResponse twoResponders(uint16_t idA, uint16_t rawA, uint16_t idB,
                                 uint16_t rawB)
{
    ElmResponse r = ok();
    r.responderCount = 2;
    r.recordedResponders = 2;
    r.responders[0].canId = idA;
    r.responders[0].len = 2;
    r.responders[0].payload[0] = static_cast<uint8_t>(rawA >> 8);
    r.responders[0].payload[1] = static_cast<uint8_t>(rawA & 0xFF);
    r.responders[1].canId = idB;
    r.responders[1].len = 2;
    r.responders[1].payload[0] = static_cast<uint8_t>(rawB >> 8);
    r.responders[1].payload[1] = static_cast<uint8_t>(rawB & 0xFF);
    r.respondersDiffer = rawA != rawB;
    r.responderId = idA;
    return r;
}

static void test_unverified_header_skipped()
{
    PidScheduler s;
    const PidKey enabled[] = {PidKey::RpmSae, PidKey::TransTemp2};
    s.begin(kTestTable, kTestTableSize, enabled, 2);
    TEST_ASSERT_EQUAL_UINT(1, s.entryCount()); // TCM row refused, not guessed
}

static void test_priority_and_intervals()
{
    PidScheduler s;
    const PidKey enabled[] = {PidKey::RpmSae, PidKey::EctSae};
    s.begin(kTestTable, kTestTableSize, enabled, 2);

    uint32_t now = 1000;
    s.resetTiming(now);

    // Both due; RPM (prio 0) wins.
    const PidDefinition* p = s.next(now);
    TEST_ASSERT_NOT_NULL(p);
    TEST_ASSERT_EQUAL(PidKey::RpmSae, p->key);

    // ECT still due.
    p = s.next(now);
    TEST_ASSERT_NOT_NULL(p);
    TEST_ASSERT_EQUAL(PidKey::EctSae, p->key);

    // Nothing due now.
    TEST_ASSERT_NULL(s.next(now));

    // 100 ms later only RPM is due again.
    now += 100;
    p = s.next(now);
    TEST_ASSERT_NOT_NULL(p);
    TEST_ASSERT_EQUAL(PidKey::RpmSae, p->key);
    TEST_ASSERT_NULL(s.next(now));

    // At +500 ms ECT comes due.
    now += 400;
    bool sawEct = false;
    while (const PidDefinition* q = s.next(now)) {
        if (q->key == PidKey::EctSae) sawEct = true;
    }
    TEST_ASSERT_TRUE(sawEct);
}

static void test_failure_backoff()
{
    PidScheduler s;
    const PidKey enabled[] = {PidKey::RpmSae};
    SchedulerConfig cfg;
    cfg.initialBackoffMs = 5000;
    cfg.failuresBeforeBackoff = 3;
    s.begin(kTestTable, kTestTableSize, enabled, 1, cfg);

    uint32_t now = 1000;
    s.resetTiming(now);
    const PidDefinition* p = s.next(now);
    TEST_ASSERT_NOT_NULL(p);

    // 3 consecutive failures -> backoff kicks in.
    for (int i = 0; i < 3; ++i) {
        s.onResult(*p, fail(), now);
        now += p->pollIntervalMs;
    }
    // Immediately after the third failure the PID must NOT be due.
    TEST_ASSERT_NULL(s.next(now));
    // ...but it comes back after the backoff.
    now += 5000;
    TEST_ASSERT_NOT_NULL(s.next(now));

    // A success resets failure tracking.
    s.onResult(*p, ok(), now);
    now += p->pollIntervalMs;
    TEST_ASSERT_NOT_NULL(s.next(now));
}

static void test_millis_wraparound()
{
    PidScheduler s;
    const PidKey enabled[] = {PidKey::RpmSae};
    s.begin(kTestTable, kTestTableSize, enabled, 1);

    // Start just before uint32 wrap.
    uint32_t now = 0xFFFFFFF0u;
    s.resetTiming(now);
    TEST_ASSERT_NOT_NULL(s.next(now)); // schedules next at 0xFFFFFFF0 + 100 (wraps)

    // Not due yet just after the wrap boundary...
    now = 0xFFFFFFFEu;
    TEST_ASSERT_NULL(s.next(now));

    // ...but due once 100 ms have elapsed across the wrap.
    now = 0x00000060u; // 0xFFFFFFF0 + 0x70 = 112 ms elapsed
    TEST_ASSERT_NOT_NULL(s.next(now));
}

// ---------------------------------------------------------------------------
// Runtime add / remove (console `on` / `off`)
// ---------------------------------------------------------------------------

static void test_runtime_add_and_remove()
{
    PidScheduler s;
    s.begin(kTestTable, kTestTableSize, nullptr, 0);
    TEST_ASSERT_EQUAL_UINT(0, s.entryCount());
    TEST_ASSERT_FALSE(s.isEnabled(PidKey::RpmSae));

    TEST_ASSERT_TRUE(s.add(kTestTable[0], 1000));
    TEST_ASSERT_TRUE(s.isEnabled(PidKey::RpmSae));
    TEST_ASSERT_EQUAL_UINT(1, s.entryCount());
    // Added PIDs are due immediately at the supplied `now`.
    TEST_ASSERT_NOT_NULL(s.next(1000));

    TEST_ASSERT_TRUE(s.remove(PidKey::RpmSae));
    TEST_ASSERT_FALSE(s.isEnabled(PidKey::RpmSae));
    TEST_ASSERT_EQUAL_UINT(0, s.entryCount());
    TEST_ASSERT_NULL(s.next(9999));

    // Removing something that isn't enabled is a no-op, not a crash.
    TEST_ASSERT_FALSE(s.remove(PidKey::RpmSae));
}

static void test_add_rejects_duplicate_and_unverified()
{
    PidScheduler s;
    s.begin(kTestTable, kTestTableSize, nullptr, 0);

    TEST_ASSERT_TRUE(s.add(kTestTable[0], 0));
    TEST_ASSERT_FALSE(s.add(kTestTable[0], 0));   // duplicate
    TEST_ASSERT_EQUAL_UINT(1, s.entryCount());

    TEST_ASSERT_FALSE(s.add(kTestTable[2], 0));   // unverified TCM header
    TEST_ASSERT_EQUAL_UINT(1, s.entryCount());
}

static void test_remove_preserves_other_entries()
{
    PidScheduler s;
    const PidKey enabled[] = {PidKey::RpmSae, PidKey::EctSae};
    s.begin(kTestTable, kTestTableSize, enabled, 2);

    TEST_ASSERT_TRUE(s.remove(PidKey::RpmSae));
    TEST_ASSERT_EQUAL_UINT(1, s.entryCount());
    TEST_ASSERT_FALSE(s.isEnabled(PidKey::RpmSae));
    TEST_ASSERT_TRUE(s.isEnabled(PidKey::EctSae));
    // The survivor must still be schedulable (compaction kept def_ intact).
    const PidDefinition* p = s.next(50000);
    TEST_ASSERT_NOT_NULL(p);
    TEST_ASSERT_EQUAL(PidKey::EctSae, p->key);
}

static void test_add_rejects_when_full()
{
    PidScheduler s;
    s.begin(kTestTable, kTestTableSize, nullptr, 0);

    // Fill with distinct definitions that share nothing but a header.
    static PidDefinition filler[PidScheduler::kMaxEntries];
    for (size_t i = 0; i < PidScheduler::kMaxEntries; ++i) {
        filler[i] = kTestTable[0];
        filler[i].key = static_cast<PidKey>(i); // distinct keys
        TEST_ASSERT_TRUE(s.add(filler[i], 0));
    }
    TEST_ASSERT_EQUAL_UINT(PidScheduler::kMaxEntries, s.entryCount());

    PidDefinition extra = kTestTable[0];
    extra.key = static_cast<PidKey>(PidScheduler::kMaxEntries + 1);
    TEST_ASSERT_FALSE(s.add(extra, 0));
    TEST_ASSERT_EQUAL_UINT(PidScheduler::kMaxEntries, s.entryCount());
}

// ---------------------------------------------------------------------------
// Statistics
// ---------------------------------------------------------------------------

static void test_stats_accumulate()
{
    PidScheduler s;
    const PidKey enabled[] = {PidKey::RpmSae};
    s.begin(kTestTable, kTestTableSize, enabled, 1);
    const PidDefinition& rpm = kTestTable[0];

    s.onResult(rpm, ok(40), 1000);
    s.onResult(rpm, ok(80), 1100);
    s.onResult(rpm, ok(60), 1200);
    s.onResult(rpm, fail(ElmResult::NoData), 1300);
    s.onResult(rpm, fail(ElmResult::Timeout), 1400);
    s.onResult(rpm, fail(ElmResult::NoResponder), 1500);
    s.onResult(rpm, fail(ElmResult::Error), 1600);

    const PidStats* st = s.stats(PidKey::RpmSae);
    TEST_ASSERT_NOT_NULL(st);
    TEST_ASSERT_EQUAL_UINT32(7, st->requests);
    TEST_ASSERT_EQUAL_UINT32(3, st->ok);
    TEST_ASSERT_EQUAL_UINT32(1, st->noData);
    TEST_ASSERT_EQUAL_UINT32(1, st->timeouts);
    TEST_ASSERT_EQUAL_UINT32(1, st->noResponder);
    TEST_ASSERT_EQUAL_UINT32(1, st->errors);

    // Latency stats cover successful responses only.
    TEST_ASSERT_EQUAL_UINT16(40, st->minLatencyMs);
    TEST_ASSERT_EQUAL_UINT16(80, st->maxLatencyMs);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 60.0f, st->avgLatencyMs());
}

static void test_stats_count_multi_responder_samples()
{
    PidScheduler s;
    const PidKey enabled[] = {PidKey::RpmSae};
    s.begin(kTestTable, kTestTableSize, enabled, 1);

    s.onResult(kTestTable[0], twoResponders(0x7E9, 0x0AC4, 0x7E8, 0x0AC2), 1000);
    s.onResult(kTestTable[0], twoResponders(0x7E9, 0x0AC4, 0x7E8, 0x0AC4), 1100);
    s.onResult(kTestTable[0], ok(), 1200); // single responder

    const PidStats* st = s.stats(PidKey::RpmSae);
    TEST_ASSERT_NOT_NULL(st);
    TEST_ASSERT_EQUAL_UINT32(2, st->multiResponderSamples);
    TEST_ASSERT_EQUAL_UINT32(1, st->divergentSamples); // only the first differed
    TEST_ASSERT_EQUAL_UINT32(3, st->ok);
}

static void test_spread_is_small_for_the_same_signal_sampled_twice()
{
    // The real case from the truck: 7E9=0AC4 -> 689.00 rpm, 7E8=0AC2 -> 688.50.
    // The bytes differ on nearly every request; the MEANING does not. A spread
    // of half an rpm at a 690 rpm idle is two modules reading one crank sensor
    // milliseconds apart, and must not read as a disagreement.
    PidScheduler s;
    const PidKey enabled[] = {PidKey::RpmSae};
    s.begin(kTestTable, kTestTableSize, enabled, 1);

    s.onResult(kTestTable[0], twoResponders(0x7E9, 0x0AC4, 0x7E8, 0x0AC2), 1000);
    s.onResult(kTestTable[0], twoResponders(0x7E9, 0x0AB8, 0x7E8, 0x0ABA), 1100);
    s.onResult(kTestTable[0], twoResponders(0x7E9, 0x0AC8, 0x7E8, 0x0AC3), 1200);

    const PidStats* st = s.stats(PidKey::RpmSae);
    TEST_ASSERT_NOT_NULL(st);
    TEST_ASSERT_EQUAL_UINT32(3, st->divergentSamples); // bytes differed every time
    // ...but the largest disagreement in meaning is (0x0AC8-0x0AC3)/4 = 1.25 rpm.
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 1.25f, st->maxResponderSpread);
}

static void test_spread_is_large_when_modules_mean_different_things()
{
    // Two modules answering one DID with unrelated quantities. Same `differ`
    // flag as above; completely different spread — which is why the spread, not
    // the flag, is the diagnostic.
    PidScheduler s;
    const PidKey enabled[] = {PidKey::RpmSae};
    s.begin(kTestTable, kTestTableSize, enabled, 1);

    s.onResult(kTestTable[0], twoResponders(0x7E8, 0x0AC4, 0x7E9, 0x0000), 1000);

    const PidStats* st = s.stats(PidKey::RpmSae);
    TEST_ASSERT_NOT_NULL(st);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 689.0f, st->maxResponderSpread);
}

static void test_spread_ignored_when_only_one_ecu_answers()
{
    PidScheduler s;
    const PidKey enabled[] = {PidKey::RpmSae};
    s.begin(kTestTable, kTestTableSize, enabled, 1);

    s.onResult(kTestTable[0], ok(), 1000);

    const PidStats* st = s.stats(PidKey::RpmSae);
    TEST_ASSERT_NOT_NULL(st);
    TEST_ASSERT_EQUAL_UINT32(0, st->multiResponderSamples);
    TEST_ASSERT_EQUAL_FLOAT(0.0f, st->maxResponderSpread);
}

static void test_stats_absent_for_disabled_pid()
{
    PidScheduler s;
    s.begin(kTestTable, kTestTableSize, nullptr, 0);
    TEST_ASSERT_NULL(s.stats(PidKey::RpmSae));
}

static void test_reset_stats()
{
    PidScheduler s;
    const PidKey enabled[] = {PidKey::RpmSae};
    s.begin(kTestTable, kTestTableSize, enabled, 1);
    s.onResult(kTestTable[0], ok(40), 1000);
    s.resetStats();

    const PidStats* st = s.stats(PidKey::RpmSae);
    TEST_ASSERT_NOT_NULL(st);
    TEST_ASSERT_EQUAL_UINT32(0, st->requests);
    TEST_ASSERT_EQUAL_UINT32(0, st->ok);
    TEST_ASSERT_EQUAL_FLOAT(0.0f, st->avgLatencyMs());
}

// ---------------------------------------------------------------------------
// Throughput budget
// ---------------------------------------------------------------------------

static void test_requested_rate_per_sec()
{
    PidScheduler s;
    s.begin(kTestTable, kTestTableSize, nullptr, 0);
    TEST_ASSERT_EQUAL_FLOAT(0.0f, s.requestedRatePerSec());

    s.add(kTestTable[0], 0); // 100 ms -> 10 req/s
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 10.0f, s.requestedRatePerSec());

    s.add(kTestTable[1], 0); // 500 ms -> 2 req/s
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 12.0f, s.requestedRatePerSec());

    s.remove(PidKey::RpmSae);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 2.0f, s.requestedRatePerSec());
}

static void test_entry_def_indexing()
{
    PidScheduler s;
    const PidKey enabled[] = {PidKey::RpmSae, PidKey::EctSae};
    s.begin(kTestTable, kTestTableSize, enabled, 2);

    TEST_ASSERT_EQUAL(PidKey::RpmSae, s.entryDef(0)->key);
    TEST_ASSERT_EQUAL(PidKey::EctSae, s.entryDef(1)->key);
    TEST_ASSERT_NULL(s.entryDef(2)); // out of range, not UB
}

int main(int, char**)
{
    UNITY_BEGIN();
    RUN_TEST(test_unverified_header_skipped);
    RUN_TEST(test_priority_and_intervals);
    RUN_TEST(test_failure_backoff);
    RUN_TEST(test_millis_wraparound);
    RUN_TEST(test_runtime_add_and_remove);
    RUN_TEST(test_add_rejects_duplicate_and_unverified);
    RUN_TEST(test_remove_preserves_other_entries);
    RUN_TEST(test_add_rejects_when_full);
    RUN_TEST(test_stats_accumulate);
    RUN_TEST(test_stats_count_multi_responder_samples);
    RUN_TEST(test_spread_is_small_for_the_same_signal_sampled_twice);
    RUN_TEST(test_spread_is_large_when_modules_mean_different_things);
    RUN_TEST(test_spread_ignored_when_only_one_ecu_answers);
    RUN_TEST(test_stats_absent_for_disabled_pid);
    RUN_TEST(test_reset_stats);
    RUN_TEST(test_requested_rate_per_sec);
    RUN_TEST(test_entry_def_indexing);
    return UNITY_END();
}
