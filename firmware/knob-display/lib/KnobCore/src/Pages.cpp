#include "Pages.h"

#include <cstdio>

namespace knob {

bool Pages::onGesture(Gesture g)
{
    // Round and round: from the last page to the first and back (owner,
    // 2026-11-22).
    const size_t i = index();
    if (g == Gesture::SwipeLeft) {
        page_ = static_cast<Page>((i + 1) % kPages);
        return true;
    }
    if (g == Gesture::SwipeRight) {
        page_ = static_cast<Page>((i + kPages - 1) % kPages);
        return true;
    }
    return false;
}

TouchAction Pages::onTouch(Gesture g, int x, int y, uint32_t nowMs)
{
    if (const CallFrame* c = call(nowMs)) {
        if (g != Gesture::Tap) return TouchAction::None;
        switch (callButtonAt(c->state, x, y)) {
            case CallButton::Answer: return TouchAction::Answer;
            case CallButton::Decline: return TouchAction::Decline;
            case CallButton::End: return TouchAction::End;
            case CallButton::None: return TouchAction::None;
        }
        return TouchAction::None;
    }
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

size_t callButtons(CallState s, CallButtonSpot out[2])
{
    switch (s) {
        case CallState::Ringing:
            out[0] = {CallButton::Answer, 128, kCallButtonY};
            out[1] = {CallButton::Decline, 232, kCallButtonY};
            return 2;
        case CallState::Waiting: out[0] = {CallButton::Decline, 180, kCallButtonY}; return 1;
        case CallState::Dialing:
        case CallState::Active:
        case CallState::Held: out[0] = {CallButton::End, 180, kCallButtonY}; return 1;
        case CallState::None: return 0;
    }
    return 0;
}

CallButton callButtonAt(CallState s, int x, int y)
{
    CallButtonSpot b[2];
    const size_t n = callButtons(s, b);
    for (size_t i = 0; i < n; ++i) {
        const float dx = static_cast<float>(x) - b[i].x, dy = static_cast<float>(y) - b[i].y;
        if (dx * dx + dy * dy <= kCallButtonHitRadius * kCallButtonHitRadius) return b[i].button;
    }
    return CallButton::None;
}

const char* callButtonWord(CallButton b)
{
    switch (b) {
        case CallButton::Answer: return "answer";
        case CallButton::Decline: return "decline";
        case CallButton::End: return "end";
        case CallButton::None: return "";
    }
    return "";
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
