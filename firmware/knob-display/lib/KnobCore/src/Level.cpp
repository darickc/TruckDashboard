#include "Level.h"

#include <cmath>

namespace knob {

void LevelMeter::add(const int16_t* s, size_t n)
{
    for (size_t i = 0; i < n; ++i) {
        const int32_t v = s[i];
        sumSq_ += static_cast<uint64_t>(v * v);
        const int32_t a = v < 0 ? -v : v;
        if (a > peak_) peak_ = a;
    }
    n_ += n;
}

void LevelMeter::reset()
{
    sumSq_ = 0;
    n_ = 0;
    peak_ = 0;
}

namespace {

float db(double ratio) { return ratio <= 0 ? LevelMeter::kSilentDb : static_cast<float>(20.0 * std::log10(ratio)); }

}  // namespace

float LevelMeter::rmsDb() const
{
    if (n_ == 0) return kSilentDb;
    return db(std::sqrt(static_cast<double>(sumSq_) / static_cast<double>(n_)) / 32768.0);
}

float LevelMeter::peakDb() const { return db(peak_ / 32768.0); }

void applyGain(int16_t* s, size_t n, int gain)
{
    for (size_t i = 0; i < n; ++i) {
        const int32_t v = static_cast<int32_t>(s[i]) * gain;
        s[i] = static_cast<int16_t>(v > 32767 ? 32767 : v < -32768 ? -32768 : v);
    }
}

void DcBlocker::process(int16_t* s, size_t n)
{
    for (size_t i = 0; i < n; ++i) {
        const float x = s[i];
        sum_ += x;
        const float y = x - x1_ + r_ * y1_;
        x1_ = x;
        y1_ = y;
        const long v = std::lround(y);
        s[i] = static_cast<int16_t>(v > 32767 ? 32767 : v < -32768 ? -32768 : v);
    }
    n_ += n;
}

float DcBlocker::takeMean()
{
    const float m = n_ ? static_cast<float>(sum_ / static_cast<double>(n_)) : 0.0f;
    sum_ = 0;
    n_ = 0;
    return m;
}

}  // namespace knob
