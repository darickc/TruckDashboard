#include "Tap.h"

#include <cstdlib>

namespace knob {

void TapDetector::onTurn(uint32_t nowMs)
{
    turned_ = true;
    turnAt_ = nowMs;
    // Turning while touching spoils the touch as a tap.
    if (down_) spoiled_ = true;
}

void TapDetector::onDown(int x, int y, uint32_t nowMs)
{
    down_ = true;
    x0_ = x_ = x;
    y0_ = y_ = y;
    downAt_ = nowMs;
    spoiled_ = turned_ && static_cast<uint32_t>(nowMs - turnAt_) < c_.quietAfterTurnMs;
}

void TapDetector::onMove(int x, int y, uint32_t)
{
    if (!down_) return;
    x_ = x;
    y_ = y;
    if (std::abs(x - x0_) > c_.maxMovePx || std::abs(y - y0_) > c_.maxMovePx) spoiled_ = true;
}

Gesture TapDetector::onUp(uint32_t nowMs)
{
    if (!down_) return Gesture::None;
    down_ = false;
    const uint32_t held = static_cast<uint32_t>(nowMs - downAt_);
    const int dx = x_ - x0_, dy = y_ - y0_;
    if (std::abs(dx) >= c_.minSwipePx && std::abs(dx) > 2 * std::abs(dy) && held <= c_.maxSwipeMs) {
        return dx < 0 ? Gesture::SwipeLeft : Gesture::SwipeRight;
    }
    if (!spoiled_ && held <= c_.maxPressMs) return Gesture::Tap;
    return Gesture::None;
}

}  // namespace knob
