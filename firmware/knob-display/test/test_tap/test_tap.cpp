// A tap plays or pauses (ADR-0044 decision 6): only short, still taps, and
// none while the knob is turning. A swipe changes the page (decision 9).

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
    TEST_ASSERT_EQUAL(Gesture::Tap, t.onUp(1200));
}

void test_a_long_press_or_a_short_drag_is_nothing()
{
    TapDetector t;
    t.onDown(180, 180, 0);
    TEST_ASSERT_EQUAL(Gesture::None, t.onUp(401));
    // Moved too far for a tap, not far enough for a swipe.
    t.onDown(180, 180, 1000);
    t.onMove(230, 180, 1050);
    TEST_ASSERT_EQUAL(Gesture::None, t.onUp(1100));
}

void test_swipes()
{
    TapDetector t;
    t.onDown(260, 180, 0);
    t.onMove(200, 185, 50);
    t.onMove(150, 190, 100);
    TEST_ASSERT_EQUAL(Gesture::SwipeLeft, t.onUp(200));
    t.onDown(100, 180, 1000);
    t.onMove(250, 170, 1100);
    TEST_ASSERT_EQUAL(Gesture::SwipeRight, t.onUp(1200));
    // Mostly up or down: not a swipe.
    t.onDown(180, 100, 2000);
    t.onMove(250, 260, 2100);
    TEST_ASSERT_EQUAL(Gesture::None, t.onUp(2200));
    // Too slow.
    t.onDown(260, 180, 3000);
    t.onMove(100, 180, 3500);
    TEST_ASSERT_EQUAL(Gesture::None, t.onUp(3900));
    // A swipe right after turning the knob still counts (only taps wait).
    t.onTurn(5000);
    t.onDown(260, 180, 5100);
    t.onMove(120, 180, 5200);
    TEST_ASSERT_EQUAL(Gesture::SwipeLeft, t.onUp(5300));
}

void test_not_while_turning()
{
    TapDetector t;
    // Just after a turn.
    t.onTurn(1000);
    t.onDown(180, 180, 1300);
    TEST_ASSERT_EQUAL(Gesture::None, t.onUp(1400));
    // Long enough after it.
    t.onDown(180, 180, 1700);
    TEST_ASSERT_EQUAL(Gesture::Tap, t.onUp(1800));
    // A turn while the finger is down.
    t.onDown(180, 180, 3000);
    t.onTurn(3050);
    TEST_ASSERT_EQUAL(Gesture::None, t.onUp(3100));
}

void test_an_up_without_a_down_is_nothing()
{
    TapDetector t;
    TEST_ASSERT_EQUAL(Gesture::None, t.onUp(10));
    t.onDown(1, 1, 20);
    TEST_ASSERT_EQUAL(Gesture::Tap, t.onUp(30));
    TEST_ASSERT_EQUAL(Gesture::None, t.onUp(40));
}

int main()
{
    UNITY_BEGIN();
    RUN_TEST(test_a_short_still_tap_counts);
    RUN_TEST(test_a_long_press_or_a_short_drag_is_nothing);
    RUN_TEST(test_swipes);
    RUN_TEST(test_not_while_turning);
    RUN_TEST(test_an_up_without_a_down_is_nothing);
    return UNITY_END();
}
