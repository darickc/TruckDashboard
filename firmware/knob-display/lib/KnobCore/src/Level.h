// A sound level for the log: RMS and peak of 16-bit samples, in dB below
// full scale (ADR-0045 spike S4, the knob's microphone).

#pragma once

#include <cstddef>
#include <cstdint>

namespace knob {

class LevelMeter {
public:
    void add(const int16_t* s, size_t n);
    void reset();

    size_t samples() const { return n_; }
    // RMS in dBFS (a full-scale sine is about -3); kSilentDb with nothing or
    // only zeros.
    float rmsDb() const;
    // The largest magnitude, in dBFS.
    float peakDb() const;

    static constexpr float kSilentDb = -120.0f;

private:
    uint64_t sumSq_ = 0;
    size_t n_ = 0;
    int32_t peak_ = 0;
};

// Multiplies samples by `gain`, saturating at full scale instead of wrapping.
// The mic needs it: speech at arm's length reads about -57 dBFS RMS raw
// (bench, 2026-11-23), where calls want about -30.
void applyGain(int16_t* s, size_t n, int gain);

// Removes a constant offset (the PDM filter's output sits about -28 dBFS off
// zero on this board): y[n] = x[n] - x[n-1] + r * y[n-1], a high-pass near
// 12 Hz at 16 kHz with r = 0.995. Saturates instead of wrapping.
class DcBlocker {
public:
    explicit DcBlocker(float r = 0.995f) : r_(r) {}
    void process(int16_t* s, size_t n);
    // The input's mean over the samples processed since the last call.
    float takeMean();

private:
    float r_;
    float x1_ = 0, y1_ = 0;
    double sum_ = 0;
    size_t n_ = 0;
};

}  // namespace knob
