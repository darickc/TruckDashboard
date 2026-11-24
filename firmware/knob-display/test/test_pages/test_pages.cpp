// The dial's pages (ADR-0044 decision 9): order, swipes going round from the
// last page to the first and back, and navigation and media shown only while their frames keep coming.

#include <unity.h>

#include "Pages.h"

using namespace knob;

extern "C" {
void setUp(void) {}
void tearDown(void) {}
}

void test_swipes_move_through_the_pages_and_wrap_around()
{
    Pages p;
    TEST_ASSERT_EQUAL(Page::Gauges, p.page());
    TEST_ASSERT_TRUE(p.onGesture(Gesture::SwipeLeft));
    TEST_ASSERT_EQUAL(Page::Navigation, p.page());
    TEST_ASSERT_TRUE(p.onGesture(Gesture::SwipeLeft));
    TEST_ASSERT_EQUAL(Page::Media, p.page());
    // From the last to the first.
    TEST_ASSERT_TRUE(p.onGesture(Gesture::SwipeLeft));
    TEST_ASSERT_EQUAL(Page::Gauges, p.page());
    // And from the first back to the last.
    TEST_ASSERT_TRUE(p.onGesture(Gesture::SwipeRight));
    TEST_ASSERT_EQUAL(Page::Media, p.page());
    TEST_ASSERT_TRUE(p.onGesture(Gesture::SwipeRight));
    TEST_ASSERT_EQUAL(Page::Navigation, p.page());
    // Anything but a swipe leaves the page alone.
    TEST_ASSERT_FALSE(p.onGesture(Gesture::Tap));
    TEST_ASSERT_FALSE(p.onGesture(Gesture::None));
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

void test_a_call_takes_over_and_only_its_buttons_work()
{
    Pages p(3000);
    TEST_ASSERT_NULL(p.call(0));
    TEST_ASSERT_EQUAL(TouchAction::PlayPause, p.onTouch(Gesture::Tap, 0, 0, 0));
    TEST_ASSERT_EQUAL(TouchAction::PageChanged, p.onTouch(Gesture::SwipeLeft, 0, 0, 0));
    TEST_ASSERT_EQUAL(Page::Navigation, p.page());

    CallFrame c;
    c.state = CallState::Ringing;
    p.onCall(c, 1000);
    TEST_ASSERT_NOT_NULL(p.call(1000));
    TEST_ASSERT_EQUAL(TouchAction::None, p.onTouch(Gesture::Tap, 0, 0, 1500));
    TEST_ASSERT_EQUAL(TouchAction::None, p.onTouch(Gesture::SwipeLeft, 0, 0, 1500));
    TEST_ASSERT_EQUAL(Page::Navigation, p.page());
    // While it rings: Answer on the left, Decline on the right; a swipe
    // across a button is still not a press.
    TEST_ASSERT_EQUAL(TouchAction::Answer, p.onTouch(Gesture::Tap, 128, 272, 1500));
    TEST_ASSERT_EQUAL(TouchAction::Decline, p.onTouch(Gesture::Tap, 232, 272, 1500));
    TEST_ASSERT_EQUAL(TouchAction::None, p.onTouch(Gesture::SwipeLeft, 232, 272, 1500));
    TEST_ASSERT_EQUAL(TouchAction::None, p.onTouch(Gesture::Tap, 180, 160, 1500));
    TEST_ASSERT_EQUAL_STRING("Push to answer", callHint(p.call(1500)->state));

    // Frames stop: no call is shown as current, touches work again.
    TEST_ASSERT_NULL(p.call(4000));
    TEST_ASSERT_EQUAL(TouchAction::PlayPause, p.onTouch(Gesture::Tap, 0, 0, 4000));

    // The call ends: "none" clears it at once.
    c.state = CallState::Active;
    p.onCall(c, 5000);
    TEST_ASSERT_EQUAL_STRING("Push to hang up", callHint(p.call(5000)->state));
    TEST_ASSERT_EQUAL(TouchAction::End, p.onTouch(Gesture::Tap, 180, 272, 5000));
    TEST_ASSERT_EQUAL(TouchAction::None, p.onTouch(Gesture::Tap, 128, 272, 5000));
    p.onCall(CallFrame(), 5100);
    TEST_ASSERT_NULL(p.call(5100));
    TEST_ASSERT_EQUAL(TouchAction::PageChanged, p.onTouch(Gesture::SwipeRight, 0, 0, 5100));
}

void test_call_buttons_by_state()
{
    CallButtonSpot b[2];
    TEST_ASSERT_EQUAL(2, callButtons(CallState::Ringing, b));
    TEST_ASSERT_EQUAL(CallButton::Answer, b[0].button);
    TEST_ASSERT_TRUE(b[0].x < b[1].x);
    TEST_ASSERT_EQUAL(CallButton::Decline, b[1].button);
    TEST_ASSERT_EQUAL(1, callButtons(CallState::Waiting, b));
    TEST_ASSERT_EQUAL(CallButton::Decline, b[0].button);
    for (CallState s : {CallState::Dialing, CallState::Active, CallState::Held}) {
        TEST_ASSERT_EQUAL(1, callButtons(s, b));
        TEST_ASSERT_EQUAL(CallButton::End, b[0].button);
        TEST_ASSERT_EQUAL_FLOAT(180, b[0].x);
    }
    TEST_ASSERT_EQUAL(0, callButtons(CallState::None, b));
    // At least the 60 px CLAUDE.md asks for, and inside the round screen.
    TEST_ASSERT_TRUE(kCallButtonSize >= 60);
    TEST_ASSERT_TRUE(kCallButtonY + kCallButtonSize / 2.0f < 360);

    // Hits: the centre, just past the edge, and not beyond the radius.
    TEST_ASSERT_EQUAL(CallButton::Decline, callButtonAt(CallState::Ringing, 232 + 43, 272));
    TEST_ASSERT_EQUAL(CallButton::None, callButtonAt(CallState::Ringing, 232 + 46, 272));
    TEST_ASSERT_EQUAL(CallButton::None, callButtonAt(CallState::Ringing, 180, 272));  // between them
    TEST_ASSERT_EQUAL(CallButton::Decline, callButtonAt(CallState::Waiting, 180, 272));
    TEST_ASSERT_EQUAL(CallButton::None, callButtonAt(CallState::None, 180, 272));
    TEST_ASSERT_EQUAL_STRING("answer", callButtonWord(CallButton::Answer));
    TEST_ASSERT_EQUAL_STRING("decline", callButtonWord(CallButton::Decline));
    TEST_ASSERT_EQUAL_STRING("end", callButtonWord(CallButton::End));
    TEST_ASSERT_EQUAL_STRING("", callButtonWord(CallButton::None));
}

void test_call_hints()
{
    TEST_ASSERT_EQUAL_STRING("Push to answer", callHint(CallState::Ringing));
    TEST_ASSERT_EQUAL_STRING("Answer on the phone", callHint(CallState::Waiting));
    TEST_ASSERT_EQUAL_STRING("Push to hang up", callHint(CallState::Dialing));
    TEST_ASSERT_EQUAL_STRING("Push to hang up", callHint(CallState::Held));
    TEST_ASSERT_EQUAL_STRING("", callHint(CallState::None));
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
    RUN_TEST(test_swipes_move_through_the_pages_and_wrap_around);
    RUN_TEST(test_nav_and_media_only_while_they_keep_coming);
    RUN_TEST(test_a_call_takes_over_and_only_its_buttons_work);
    RUN_TEST(test_call_buttons_by_state);
    RUN_TEST(test_call_hints);
    RUN_TEST(test_track_times);
    return UNITY_END();
}
