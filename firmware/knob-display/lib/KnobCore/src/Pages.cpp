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

TouchAction Pages::onTouch(Gesture g, uint32_t nowMs)
{
    if (call(nowMs) != nullptr) return TouchAction::None;
    if (g == Gesture::Tap) return TouchAction::PlayPause;
    return onGesture(g) ? TouchAction::PageChanged : TouchAction::None;
}

void Pages::onCall(const CallFrame& c, uint32_t nowMs)
{
    call_ = c;
    callAt_ = nowMs;
    hasCall_ = true;
}

const CallFrame* Pages::call(uint32_t nowMs) const
{
    return hasCall_ && call_.state != CallState::None && static_cast<uint32_t>(nowMs - callAt_) < timeoutMs_
               ? &call_
               : nullptr;
}

const char* callHint(CallState s)
{
    switch (s) {
        case CallState::Ringing: return "Push to answer";
        case CallState::Waiting: return "Answer on the phone";
        case CallState::Dialing:
        case CallState::Active:
        case CallState::Held: return "Push to hang up";
        case CallState::None: break;
    }
    return "";
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
