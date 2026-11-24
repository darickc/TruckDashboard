// Touch gestures (ADR-0044 decisions 6 and 9). A tap plays or pauses the
// phone, but only a deliberate one: short, still, and not while the knob is
// turning (a finger resting on the screen while turning isn't a tap). A
// swipe left or right changes the page.

#pragma once

#include <cstdint>

namespace knob {

// Examples (CLAUDE.md rule 10), tuned on the board.
struct TapConfig {
    uint32_t maxPressMs = 400;
    int maxMovePx = 20;
    uint32_t quietAfterTurnMs = 600;
    // A swipe: at least this far sideways, mostly sideways, this quick.
    int minSwipePx = 60;
    uint32_t maxSwipeMs = 800;
};

enum class Gesture : uint8_t {
    None,
    Tap,
    SwipeLeft,   // the finger moved left: the next page
    SwipeRight,  // the finger moved right: the previous page
};

class TapDetector {
public:
    explicit TapDetector(TapConfig c = TapConfig()) : c_(c) {}

    void onTurn(uint32_t nowMs);
    void onDown(int x, int y, uint32_t nowMs);
    void onMove(int x, int y, uint32_t nowMs);
    // What the touch that just ended was.
    Gesture onUp(uint32_t nowMs);
    // Where the last touch started (a tap's position: it barely moves).
    int x() const { return x0_; }
    int y() const { return y0_; }

private:
    TapConfig c_;
    bool down_ = false;
    bool spoiled_ = false;
    int x0_ = 0, y0_ = 0, x_ = 0, y_ = 0;
    uint32_t downAt_ = 0;
    bool turned_ = false;
    uint32_t turnAt_ = 0;
};

}  // namespace knob
