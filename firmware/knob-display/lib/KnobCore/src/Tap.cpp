#include "Tap.h"

#include <cstdlib>

namespace knob {

void TapDetector::onTurn(uint32_t nowMs)
{
    turned_ = true;
    turnAt_ = nowMs;
    // Turning while touching spoils the touch.
    if (down_) spoiled_ = true;
}

void TapDetector::onDown(int x, int y, uint32_t nowMs)
{
    down_ = true;
    x0_ = x;
    y0_ = y;
    downAt_ = nowMs;
    spoiled_ = turned_ && static_cast<uint32_t>(nowMs - turnAt_) < c_.quietAfterTurnMs;
}

void TapDetector::onMove(int x, int y, uint32_t)
{
    if (!down_) return;
    if (std::abs(x - x0_) > c_.maxMovePx || std::abs(y - y0_) > c_.maxMovePx) spoiled_ = true;
}

bool TapDetector::onUp(uint32_t nowMs)
{
    if (!down_) return false;
    down_ = false;
    return !spoiled_ && static_cast<uint32_t>(nowMs - downAt_) <= c_.maxPressMs;
}

}  // namespace knob
