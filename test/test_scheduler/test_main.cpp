// Unit tests: PID scheduler — due selection, priority, failure backoff,
// unverified-header skipping, millis() wraparound.

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
     {0, 2, false, 0.25f, 0.0f}, nullptr, Unit::Rpm, 100, 0, 500, 2, true},
    // slower, lower priority
    {PidKey::EctSae, ChannelId::EctF, "ECT", "ECT", 0x01, 0x05, ObdModule::Auto,
     {0, 1, false, 1.0f, -40.0f}, nullptr, Unit::Celsius, 500, 3, 500, 2, true},
    // unverified module header — must be skipped at registration
    {PidKey::TransTemp2, ChannelId::TransTempF, "TransTCM", "TT2", 0x22, 0x1674,
     ObdModule::Tcm, {0, 2, false, 0.125f, 0.0f}, nullptr, Unit::Fahrenheit,
     500, 3, 500, 2, false},
};
static const size_t kTestTableSize = sizeof(kTestTable) / sizeof(kTestTable[0]);

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
        s.onResult(*p, false, now);
        now += p->pollIntervalMs;
    }
    // Immediately after the third failure the PID must NOT be due.
    TEST_ASSERT_NULL(s.next(now));
    // ...but it comes back after the backoff.
    now += 5000;
    TEST_ASSERT_NOT_NULL(s.next(now));

    // A success resets failure tracking.
    s.onResult(*p, true, now);
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

int main(int, char**)
{
    UNITY_BEGIN();
    RUN_TEST(test_unverified_header_skipped);
    RUN_TEST(test_priority_and_intervals);
    RUN_TEST(test_failure_backoff);
    RUN_TEST(test_millis_wraparound);
    return UNITY_END();
}
