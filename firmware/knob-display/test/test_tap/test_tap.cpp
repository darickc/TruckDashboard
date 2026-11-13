// A tap plays or pauses (ADR-0044 decision 6): only short, still taps, and
// none while the knob is turning.

#include <unity.h>

#include "Tap.h"

using namespace knob;

extern "C" {
void setUp(void) {}
void tearDown(void) {}
}

void test_a_short_still_tap_counts()
{
    TapDetector t;
    t.onDown(180, 180, 1000);
    t.onMove(185, 178, 1100);
    TEST_ASSERT_TRUE(t.onUp(1200));
}

void test_a_long_press_or_a_swipe_doesnt()
{
    TapDetector t;
    t.onDown(180, 180, 0);
    TEST_ASSERT_FALSE(t.onUp(401));
    t.onDown(180, 180, 1000);
    t.onMove(230, 180, 1050);
    TEST_ASSERT_FALSE(t.onUp(1100));
}

void test_not_while_turning()
{
    TapDetector t;
    // Just after a turn.
    t.onTurn(1000);
    t.onDown(180, 180, 1300);
    TEST_ASSERT_FALSE(t.onUp(1400));
    // Long enough after it.
    t.onDown(180, 180, 1700);
    TEST_ASSERT_TRUE(t.onUp(1800));
    // A turn while the finger is down.
    t.onDown(180, 180, 3000);
    t.onTurn(3050);
    TEST_ASSERT_FALSE(t.onUp(3100));
}

void test_an_up_without_a_down_is_nothing()
{
    TapDetector t;
    TEST_ASSERT_FALSE(t.onUp(10));
    t.onDown(1, 1, 20);
    TEST_ASSERT_TRUE(t.onUp(30));
    TEST_ASSERT_FALSE(t.onUp(40));
}

int main()
{
    UNITY_BEGIN();
    RUN_TEST(test_a_short_still_tap_counts);
    RUN_TEST(test_a_long_press_or_a_swipe_doesnt);
    RUN_TEST(test_not_while_turning);
    RUN_TEST(test_an_up_without_a_down_is_nothing);
    return UNITY_END();
}
