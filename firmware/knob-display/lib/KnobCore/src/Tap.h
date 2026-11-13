// A tap on the screen plays or pauses the phone (ADR-0044 decision 6), but
// only a deliberate one: short, still, and not while the knob is turning (a
// finger resting on the screen while turning isn't a tap).

#pragma once

#include <cstdint>

namespace knob {

// Examples (CLAUDE.md rule 10), tuned on the board.
struct TapConfig {
    uint32_t maxPressMs = 400;
    int maxMovePx = 20;
    uint32_t quietAfterTurnMs = 600;
};

class TapDetector {
public:
    explicit TapDetector(TapConfig c = TapConfig()) : c_(c) {}

    void onTurn(uint32_t nowMs);
    void onDown(int x, int y, uint32_t nowMs);
    void onMove(int x, int y, uint32_t nowMs);
    // True: that was a tap.
    bool onUp(uint32_t nowMs);

private:
    TapConfig c_;
    bool down_ = false;
    bool spoiled_ = false;
    int x0_ = 0, y0_ = 0;
    uint32_t downAt_ = 0;
    bool turned_ = false;
    uint32_t turnAt_ = 0;
};

}  // namespace knob
