// The knob's encoder (ADR-0044). Not a quadrature encoder: Waveshare's
// schematic and encoder demo treat it as a "bidirectional switch", where line
// A pulses low once per detent one way and line B the other way (both pulled
// up, 10 kΩ). The demo samples both every 3 ms and counts a step when a line
// comes back high after being low for at least two samples; this does the
// same. A is clockwise (louder): checked on the bench, 2026-11-22.

#pragma once

#include <cstdint>

namespace knob {

class PulseKnob {
public:
    // Samples a line must stay low before its release counts as a step.
    explicit PulseKnob(uint8_t minLowSamples = 2) : minLow_(minLowSamples) {}

    // One sample of both lines (true = high). Returns +1 for a step on A,
    // -1 for a step on B, 0 for neither (both at once: they cancel).
    int sample(bool aHigh, bool bHigh);

private:
    struct Line {
        bool high = true;
        uint8_t lowFor = 0;
    };
    // True when this sample released a line that had been low long enough.
    bool step(Line& l, bool high);

    uint8_t minLow_;
    Line a_, b_;
};

}  // namespace knob
