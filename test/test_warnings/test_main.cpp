// Unit tests: warning manager — level transitions, hysteresis (no flapping),
// stale handling, low-side thresholds.

#include <unity.h>

#include "Warnings.h"

using namespace obd;

extern "C" {
void setUp(void) {}
void tearDown(void) {}
}

namespace {

const WarningRule kRules[] = {
    // ECT: high-side caution 225, critical 240, hysteresis 3.
    {ChannelId::EctF, kNoBound, kNoBound, 225.0f, 240.0f, 3.0f},
    // FICM: low-side caution 46, critical 44, hysteresis 0.5.
    {ChannelId::FicmMainV, 44.0f, 46.0f, kNoBound, kNoBound, 0.5f},
};

Snapshot makeSnap(uint32_t now)
{
    Snapshot s;
    s.nowMs = now;
    return s;
}

void setChannel(Snapshot& s, ChannelId id, float v, uint32_t at)
{
    Channel& c = s.ch[static_cast<size_t>(id)];
    c.value = v;
    c.updatedAtMs = at;
    c.everValid = true;
}

} // namespace

static void test_normal_caution_critical_escalation()
{
    WarningManager wm;
    wm.begin(kRules, 2, 3000);

    Snapshot s = makeSnap(1000);
    setChannel(s, ChannelId::EctF, 200.0f, 1000);
    wm.evaluate(s, true);
    TEST_ASSERT_EQUAL(WarnLevel::Normal, wm.state().channelLevel(ChannelId::EctF));
    TEST_ASSERT_FALSE(wm.state().anyCaution);

    setChannel(s, ChannelId::EctF, 226.0f, 1000);
    wm.evaluate(s, true);
    TEST_ASSERT_EQUAL(WarnLevel::Caution, wm.state().channelLevel(ChannelId::EctF));
    TEST_ASSERT_TRUE(wm.state().anyCaution);

    setChannel(s, ChannelId::EctF, 241.0f, 1000);
    wm.evaluate(s, true);
    TEST_ASSERT_EQUAL(WarnLevel::Critical, wm.state().channelLevel(ChannelId::EctF));
    TEST_ASSERT_TRUE(wm.state().anyCritical);
}

static void test_hysteresis_no_flapping()
{
    WarningManager wm;
    wm.begin(kRules, 2, 3000);

    Snapshot s = makeSnap(1000);
    // Cross into caution.
    setChannel(s, ChannelId::EctF, 226.0f, 1000);
    wm.evaluate(s, true);
    TEST_ASSERT_EQUAL(WarnLevel::Caution, wm.state().channelLevel(ChannelId::EctF));

    // Dip to 224 — inside the hysteresis band (225 - 3 = 222): still caution.
    setChannel(s, ChannelId::EctF, 224.0f, 1000);
    wm.evaluate(s, true);
    TEST_ASSERT_EQUAL(WarnLevel::Caution, wm.state().channelLevel(ChannelId::EctF));

    // Drop below 222 — clears.
    setChannel(s, ChannelId::EctF, 221.0f, 1000);
    wm.evaluate(s, true);
    TEST_ASSERT_EQUAL(WarnLevel::Normal, wm.state().channelLevel(ChannelId::EctF));
}

static void test_low_side_thresholds()
{
    WarningManager wm;
    wm.begin(kRules, 2, 3000);

    Snapshot s = makeSnap(1000);
    setChannel(s, ChannelId::FicmMainV, 48.2f, 1000);
    wm.evaluate(s, true);
    TEST_ASSERT_EQUAL(WarnLevel::Normal, wm.state().channelLevel(ChannelId::FicmMainV));

    setChannel(s, ChannelId::FicmMainV, 45.5f, 1000);
    wm.evaluate(s, true);
    TEST_ASSERT_EQUAL(WarnLevel::Caution, wm.state().channelLevel(ChannelId::FicmMainV));

    setChannel(s, ChannelId::FicmMainV, 43.0f, 1000);
    wm.evaluate(s, true);
    TEST_ASSERT_EQUAL(WarnLevel::Critical, wm.state().channelLevel(ChannelId::FicmMainV));
}

static void test_stale_channel_reports_stale()
{
    WarningManager wm;
    wm.begin(kRules, 2, 3000);

    // Value is critical-high, but 10 s old: Stale, not Critical — old data
    // must never be judged as if it were current.
    Snapshot s = makeSnap(11000);
    setChannel(s, ChannelId::EctF, 250.0f, 1000);
    wm.evaluate(s, true);
    TEST_ASSERT_EQUAL(WarnLevel::Stale, wm.state().channelLevel(ChannelId::EctF));
    TEST_ASSERT_TRUE(wm.state().anyStale);
    TEST_ASSERT_FALSE(wm.state().anyCritical);
}

static void test_never_valid_channel_is_normal()
{
    WarningManager wm;
    wm.begin(kRules, 2, 3000);
    Snapshot s = makeSnap(1000); // nothing ever set
    wm.evaluate(s, true);
    TEST_ASSERT_EQUAL(WarnLevel::Normal, wm.state().channelLevel(ChannelId::EctF));
    TEST_ASSERT_FALSE(wm.state().anyStale);
}

static void test_connection_flag_passthrough()
{
    WarningManager wm;
    wm.begin(kRules, 2, 3000);
    Snapshot s = makeSnap(1000);
    wm.evaluate(s, false);
    TEST_ASSERT_FALSE(wm.state().obdConnected);
    wm.evaluate(s, true);
    TEST_ASSERT_TRUE(wm.state().obdConnected);
}

int main(int, char**)
{
    UNITY_BEGIN();
    RUN_TEST(test_normal_caution_critical_escalation);
    RUN_TEST(test_hysteresis_no_flapping);
    RUN_TEST(test_low_side_thresholds);
    RUN_TEST(test_stale_channel_reports_stale);
    RUN_TEST(test_never_valid_channel_is_normal);
    RUN_TEST(test_connection_flag_passthrough);
    return UNITY_END();
}
