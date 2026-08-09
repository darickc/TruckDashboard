// Unit tests: vehicle data model — freshness, validity, error counting,
// snapshots, derived values (boost = MAP - baro, EOT-ECT delta).

#include <unity.h>

#include "Derived.h"
#include "VehicleData.h"

using namespace obd;

extern "C" {
void setUp(void) {}
void tearDown(void) {}
}

static void test_set_and_snapshot()
{
    VehicleData vd;
    vd.set(ChannelId::Rpm, 1726.0f, 1000);
    const Snapshot s = vd.snapshot(1100);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 1726.0f, s.value(ChannelId::Rpm));
    TEST_ASSERT_TRUE(s.channel(ChannelId::Rpm).everValid);
    TEST_ASSERT_EQUAL_UINT32(1000, s.channel(ChannelId::Rpm).updatedAtMs);
}

static void test_freshness()
{
    VehicleData vd;
    vd.set(ChannelId::Rpm, 800.0f, 1000);

    Snapshot s = vd.snapshot(2000);
    TEST_ASSERT_TRUE(s.isFresh(ChannelId::Rpm, 3000));  // 1 s old, 3 s window
    TEST_ASSERT_FALSE(s.isFresh(ChannelId::Rpm, 500));  // 1 s old, 0.5 s window

    // Never-set channel is never fresh.
    TEST_ASSERT_FALSE(s.isFresh(ChannelId::EotF, 999999));
}

static void test_error_counting()
{
    VehicleData vd;
    vd.markError(ChannelId::IcpPsi);
    vd.markError(ChannelId::IcpPsi);
    const Snapshot s = vd.snapshot(0);
    TEST_ASSERT_EQUAL_UINT16(2, s.channel(ChannelId::IcpPsi).errorCount);
    TEST_ASSERT_FALSE(s.channel(ChannelId::IcpPsi).everValid); // errors != data
}

static void test_derived_delta_and_boost()
{
    VehicleData vd;
    uint32_t now = 5000;
    vd.set(ChannelId::EctF, 194.0f, now);
    vd.set(ChannelId::EotF, 201.0f, now);
    vd.set(ChannelId::MapPsi, 27.1f, now);  // absolute
    vd.set(ChannelId::BaroPsi, 14.7f, now);

    derived::update(vd, now, {3000});
    const Snapshot s = vd.snapshot(now);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 7.0f, s.value(ChannelId::EctEotDeltaF));
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 12.4f, s.value(ChannelId::BoostPsi));
}

static void test_derived_requires_fresh_inputs()
{
    VehicleData vd;
    vd.set(ChannelId::MapPsi, 27.1f, 1000);
    vd.set(ChannelId::BaroPsi, 14.7f, 1000);

    // Inputs are 10 s old at evaluation time — boost must NOT be produced.
    derived::update(vd, 11000, {3000});
    const Snapshot s = vd.snapshot(11000);
    TEST_ASSERT_FALSE(s.channel(ChannelId::BoostPsi).everValid);

    // Missing baro alone also blocks boost.
    VehicleData vd2;
    vd2.set(ChannelId::MapPsi, 27.1f, 1000);
    derived::update(vd2, 1100, {3000});
    TEST_ASSERT_FALSE(vd2.snapshot(1100).channel(ChannelId::BoostPsi).everValid);
}

static void test_lock_hooks_called()
{
    static int lockCount = 0;
    static int unlockCount = 0;
    lockCount = unlockCount = 0;

    VehicleData vd;
    vd.setLockHooks([](void*) { ++lockCount; }, [](void*) { ++unlockCount; }, nullptr);
    vd.set(ChannelId::Rpm, 1.0f, 0);
    (void)vd.snapshot(0);
    TEST_ASSERT_EQUAL_INT(2, lockCount);
    TEST_ASSERT_EQUAL_INT(lockCount, unlockCount); // balanced
}

int main(int, char**)
{
    UNITY_BEGIN();
    RUN_TEST(test_set_and_snapshot);
    RUN_TEST(test_freshness);
    RUN_TEST(test_error_counting);
    RUN_TEST(test_derived_delta_and_boost);
    RUN_TEST(test_derived_requires_fresh_inputs);
    RUN_TEST(test_lock_hooks_called);
    return UNITY_END();
}
