#include "Pages.h"

#include <cstdio>

namespace knob {

bool Pages::onGesture(Gesture g)
{
    const size_t i = index();
    if (g == Gesture::SwipeLeft && i + 1 < kPages) {
        page_ = static_cast<Page>(i + 1);
        return true;
    }
    if (g == Gesture::SwipeRight && i > 0) {
        page_ = static_cast<Page>(i - 1);
        return true;
    }
    return false;
}

void Pages::onNav(const NavFrame& n, uint32_t nowMs)
{
    nav_ = n;
    navAt_ = nowMs;
    hasNav_ = true;
}

void Pages::onMedia(const MediaFrame& m, uint32_t nowMs)
{
    media_ = m;
    mediaAt_ = nowMs;
    hasMedia_ = true;
}

const NavFrame* Pages::nav(uint32_t nowMs) const
{
    return hasNav_ && static_cast<uint32_t>(nowMs - navAt_) < timeoutMs_ ? &nav_ : nullptr;
}

const MediaFrame* Pages::media(uint32_t nowMs) const
{
    return hasMedia_ && static_cast<uint32_t>(nowMs - mediaAt_) < timeoutMs_ ? &media_ : nullptr;
}

void formatTrackTime(int32_t posS, int32_t durS, char* buf, size_t size)
{
    if (posS < 0) {
        std::snprintf(buf, size, "%s", "");
    } else if (durS <= 0) {
        std::snprintf(buf, size, "%ld:%02ld", static_cast<long>(posS / 60), static_cast<long>(posS % 60));
    } else {
        std::snprintf(buf, size, "%ld:%02ld / %ld:%02ld", static_cast<long>(posS / 60),
                      static_cast<long>(posS % 60), static_cast<long>(durS / 60), static_cast<long>(durS % 60));
    }
}

}  // namespace knob
