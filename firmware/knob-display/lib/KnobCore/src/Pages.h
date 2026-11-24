// The dial's pages (ADR-0044 decision 9): gauges, navigation, media, in that
// order; a swipe left goes to the next, right to the previous, round from
// the last to the first and back (owner, 2026-11-22). The navigation and media frames are shown only while they keep
// coming: after `infoTimeoutMs` without one the page says it has no data,
// never an old distance or track as current (CLAUDE.md rule 4).
//
// A phone call takes over the dial on any page (ADR-0045 decision 6) while
// its frames keep coming. During a call only a tap on one of the call
// screen's buttons does anything (owner, 2026-11-23; ADR-0045 amendment):
// Answer and Decline while it rings, End during it, Decline for a waiting
// call (answering that one would end or hold the first: the phone's
// choice). Elsewhere a tap is ignored and swipes don't change the page; the
// knob's turn is still the volume. The dial only asks: knob-link checks the
// call is still the one the button was for, and audio-manager decides.

#pragma once

#include <cstddef>
#include <cstdint>

#include "Frame.h"
#include "Tap.h"

namespace knob {

enum class Page : uint8_t { Gauges, Navigation, Media };
constexpr size_t kPages = 3;

// What a touch does.
enum class TouchAction : uint8_t { None, PlayPause, PageChanged, Answer, Decline, End };

// The call screen's buttons: 76 px circles on y = 272; Answer on the left
// and Decline on the right while ringing (owner), one in the middle
// otherwise.
enum class CallButton : uint8_t { None, Answer, Decline, End };
struct CallButtonSpot {
    CallButton button = CallButton::None;
    float x = 0, y = 0;
};
constexpr float kCallButtonY = 272;
constexpr int kCallButtonSize = 76;
// A tap this close to a button's centre presses it (a little beyond its edge).
constexpr float kCallButtonHitRadius = 44;

// The buttons shown for `s` (0, 1 or 2) into `out`.
size_t callButtons(CallState s, CallButtonSpot out[2]);
// The button under (x, y) for `s`, or None.
CallButton callButtonAt(CallState s, int x, int y);
// The word knob-link gets for it ("answer", "decline", "end"; "" for None).
const char* callButtonWord(CallButton b);

class Pages {
public:
    explicit Pages(uint32_t infoTimeoutMs = 3000) : timeoutMs_(infoTimeoutMs) {}

    Page page() const { return page_; }
    size_t index() const { return static_cast<size_t>(page_); }
    // Swipes change the page; anything else is ignored. True if it changed.
    bool onGesture(Gesture g);
    // A finished touch that started at (x, y): a tap plays or pauses, a
    // swipe changes the page; during a call only a tap on a call button
    // does anything.
    TouchAction onTouch(Gesture g, int x, int y, uint32_t nowMs);

    void onNav(const NavFrame& n, uint32_t nowMs);
    void onMedia(const MediaFrame& m, uint32_t nowMs);
    void onCall(const CallFrame& c, uint32_t nowMs);

    // The last frame, if it is recent.
    const NavFrame* nav(uint32_t nowMs) const;
    const MediaFrame* media(uint32_t nowMs) const;
    // The call to show over every page, if a recent frame has one.
    const CallFrame* call(uint32_t nowMs) const;

private:
    uint32_t timeoutMs_;
    Page page_ = Page::Gauges;
    NavFrame nav_;
    MediaFrame media_;
    CallFrame call_;
    bool hasNav_ = false, hasMedia_ = false, hasCall_ = false;
    uint32_t navAt_ = 0, mediaAt_ = 0, callAt_ = 0;
};

// What the dial says under the caller: "Push to answer", "Push to hang up",
// "Answer on the phone"; "" for none.
const char* callHint(CallState s);

// "1:34 / 4:02", "1:34", or "" (unknown).
void formatTrackTime(int32_t posS, int32_t durS, char* buf, size_t size);

}  // namespace knob
