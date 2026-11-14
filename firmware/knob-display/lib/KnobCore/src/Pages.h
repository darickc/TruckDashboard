// The dial's pages (ADR-0044 decision 9): gauges, navigation, media, in that
// order; a swipe left goes to the next, right to the previous, stopping at
// the ends. The navigation and media frames are shown only while they keep
// coming: after `infoTimeoutMs` without one the page says it has no data,
// never an old distance or track as current (CLAUDE.md rule 4).

#pragma once

#include <cstddef>
#include <cstdint>

#include "Frame.h"
#include "Tap.h"

namespace knob {

enum class Page : uint8_t { Gauges, Navigation, Media };
constexpr size_t kPages = 3;

class Pages {
public:
    explicit Pages(uint32_t infoTimeoutMs = 3000) : timeoutMs_(infoTimeoutMs) {}

    Page page() const { return page_; }
    size_t index() const { return static_cast<size_t>(page_); }
    // Swipes change the page; anything else is ignored. True if it changed.
    bool onGesture(Gesture g);

    void onNav(const NavFrame& n, uint32_t nowMs);
    void onMedia(const MediaFrame& m, uint32_t nowMs);

    // The last frame, if it is recent.
    const NavFrame* nav(uint32_t nowMs) const;
    const MediaFrame* media(uint32_t nowMs) const;

private:
    uint32_t timeoutMs_;
    Page page_ = Page::Gauges;
    NavFrame nav_;
    MediaFrame media_;
    bool hasNav_ = false, hasMedia_ = false;
    uint32_t navAt_ = 0, mediaAt_ = 0;
};

// "1:34 / 4:02", "1:34", or "" (unknown).
void formatTrackTime(int32_t posS, int32_t durS, char* buf, size_t size);

}  // namespace knob
