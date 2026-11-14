// The dial's pages (ADR-0044 decision 9): order, swipes stopping at the
// ends, and navigation and media shown only while their frames keep coming.

#include <unity.h>

#include "Pages.h"

using namespace knob;

extern "C" {
void setUp(void) {}
void tearDown(void) {}
}

void test_swipes_move_through_the_pages_and_stop_at_the_ends()
{
    Pages p;
    TEST_ASSERT_EQUAL(Page::Gauges, p.page());
    TEST_ASSERT_FALSE(p.onGesture(Gesture::SwipeRight));
    TEST_ASSERT_TRUE(p.onGesture(Gesture::SwipeLeft));
    TEST_ASSERT_EQUAL(Page::Navigation, p.page());
    TEST_ASSERT_TRUE(p.onGesture(Gesture::SwipeLeft));
    TEST_ASSERT_EQUAL(Page::Media, p.page());
    TEST_ASSERT_FALSE(p.onGesture(Gesture::SwipeLeft));
    TEST_ASSERT_FALSE(p.onGesture(Gesture::Tap));
    TEST_ASSERT_EQUAL(Page::Media, p.page());
    TEST_ASSERT_TRUE(p.onGesture(Gesture::SwipeRight));
    TEST_ASSERT_EQUAL(Page::Navigation, p.page());
}

void test_nav_and_media_only_while_they_keep_coming()
{
    Pages p(3000);
    TEST_ASSERT_NULL(p.nav(0));
    TEST_ASSERT_NULL(p.media(0));
    NavFrame n;
    n.state = NavState::Active;
    p.onNav(n, 1000);
    TEST_ASSERT_NOT_NULL(p.nav(3999));
    TEST_ASSERT_NULL(p.nav(4000));
    MediaFrame m;
    m.state = PlayState::Playing;
    p.onMedia(m, 5000);
    TEST_ASSERT_EQUAL(PlayState::Playing, p.media(6000)->state);
    TEST_ASSERT_NULL(p.media(8000));
    // Across the clock wrapping.
    p.onNav(n, 0xFFFFFF00u);
    TEST_ASSERT_NOT_NULL(p.nav(0x00000200u));
}

void test_track_times()
{
    char b[24];
    formatTrackTime(94, 242, b, sizeof(b));
    TEST_ASSERT_EQUAL_STRING("1:34 / 4:02", b);
    formatTrackTime(5, -1, b, sizeof(b));
    TEST_ASSERT_EQUAL_STRING("0:05", b);
    formatTrackTime(-1, 242, b, sizeof(b));
    TEST_ASSERT_EQUAL_STRING("", b);
    formatTrackTime(3725, 4000, b, sizeof(b));
    TEST_ASSERT_EQUAL_STRING("62:05 / 66:40", b);
}

int main()
{
    UNITY_BEGIN();
    RUN_TEST(test_swipes_move_through_the_pages_and_stop_at_the_ends);
    RUN_TEST(test_nav_and_media_only_while_they_keep_coming);
    RUN_TEST(test_track_times);
    return UNITY_END();
}
