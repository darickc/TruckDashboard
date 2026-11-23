// The dial's pages (ADR-0044 decision 9): gauges, navigation, media, in that
// order; a swipe left goes to the next, right to the previous, round from
// the last to the first and back (owner, 2026-11-22). The navigation and media frames are shown only while they keep
// coming: after `infoTimeoutMs` without one the page says it has no data,
// never an old distance or track as current (CLAUDE.md rule 4).
//
// A phone call takes over the dial on any page (ADR-0045 decision 6) while
// its frames keep coming: the caller, and what the push does. During a call
// touches do nothing — a tap is too easy by accident, and the page stays
// put; the knob's push answers or hangs up (audio-manager decides, the push
// is the same key as play/pause) and its turn is still the volume.

#pragma once

#include <cstddef>
#include <cstdint>

#include "Frame.h"
#include "Tap.h"

namespace knob {

enum class Page : uint8_t { Gauges, Navigation, Media };
constexpr size_t kPages = 3;

// What a touch does.
enum class TouchAction : uint8_t { None, PlayPause, PageChanged };

class Pages {
public:
    explicit Pages(uint32_t infoTimeoutMs = 3000) : timeoutMs_(infoTimeoutMs) {}

    Page page() const { return page_; }
    size_t index() const { return static_cast<size_t>(page_); }
    // Swipes change the page; anything else is ignored. True if it changed.
    bool onGesture(Gesture g);
    // A finished touch: a tap plays or pauses, a swipe changes the page,
    // and during a call neither.
    TouchAction onTouch(Gesture g, uint32_t nowMs);

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
