// The microphone's level for the log (Level.h): silence, a full-scale sine,
// a quieter one, and the peak.

#include <unity.h>

#include <cmath>
#include <vector>

#include "Level.h"

using namespace knob;

extern "C" {
void setUp(void) {}
void tearDown(void) {}
}

std::vector<int16_t> sine(double amplitude, size_t n)
{
    std::vector<int16_t> v(n);
    for (size_t i = 0; i < n; ++i) v[i] = static_cast<int16_t>(std::lround(amplitude * std::sin(2 * M_PI * 1000.0 * i / 16000.0)));
    return v;
}

void test_silence()
{
    LevelMeter m;
    TEST_ASSERT_EQUAL_FLOAT(LevelMeter::kSilentDb, m.rmsDb());
    std::vector<int16_t> z(160, 0);
    m.add(z.data(), z.size());
    TEST_ASSERT_EQUAL(160, m.samples());
    TEST_ASSERT_EQUAL_FLOAT(LevelMeter::kSilentDb, m.rmsDb());
    TEST_ASSERT_EQUAL_FLOAT(LevelMeter::kSilentDb, m.peakDb());
}

void test_sines()
{
    LevelMeter m;
    auto full = sine(32767, 1600);
    m.add(full.data(), full.size());
    TEST_ASSERT_FLOAT_WITHIN(0.1f, -3.01f, m.rmsDb());
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 0.0f, m.peakDb());
    // A tenth of full scale: 20 dB lower; reset starts again.
    m.reset();
    auto tenth = sine(3276.7, 1600);
    m.add(tenth.data(), tenth.size());
    TEST_ASSERT_FLOAT_WITHIN(0.1f, -23.01f, m.rmsDb());
    TEST_ASSERT_FLOAT_WITHIN(0.1f, -20.0f, m.peakDb());
    // The most negative sample doesn't overflow.
    int16_t low = -32768;
    m.reset();
    m.add(&low, 1);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 0.0f, m.peakDb());
}

void test_dc_blocker_removes_an_offset_and_keeps_speech_band()
{
    // A constant 1300 (the board's offset) fades to nothing within a second.
    DcBlocker dc;
    std::vector<int16_t> flat(16000, 1300);
    dc.process(flat.data(), flat.size());
    TEST_ASSERT_FLOAT_WITHIN(1.0f, 1300.0f, dc.takeMean());
    LevelMeter tail;
    tail.add(flat.data() + 15000, 1000);
    TEST_ASSERT_TRUE(tail.rmsDb() < -80.0f);
    // A 1 kHz tone on top of the offset keeps its level (within 0.5 dB).
    DcBlocker dc2;
    auto tone = sine(3276.7, 16000);
    for (auto& v : tone) v = static_cast<int16_t>(v + 1300);
    dc2.process(tone.data(), tone.size());
    LevelMeter m;
    m.add(tone.data() + 8000, 8000);
    TEST_ASSERT_FLOAT_WITHIN(0.5f, -23.01f, m.rmsDb());
    // Nothing processed: a mean of 0.
    TEST_ASSERT_EQUAL_FLOAT(0.0f, DcBlocker().takeMean());
}

void test_gain_saturates()
{
    int16_t s[] = {100, -100, 3000, -3000, 0};
    applyGain(s, 5, 16);
    TEST_ASSERT_EQUAL(1600, s[0]);
    TEST_ASSERT_EQUAL(-1600, s[1]);
    TEST_ASSERT_EQUAL(32767, s[2]);
    TEST_ASSERT_EQUAL(-32768, s[3]);
    TEST_ASSERT_EQUAL(0, s[4]);
    // x16 is +24 dB.
    auto tone = sine(100, 1600);
    LevelMeter before, after;
    before.add(tone.data(), tone.size());
    applyGain(tone.data(), tone.size(), 16);
    after.add(tone.data(), tone.size());
    TEST_ASSERT_FLOAT_WITHIN(0.1f, 24.08f, after.rmsDb() - before.rmsDb());
}

int main()
{
    UNITY_BEGIN();
    RUN_TEST(test_silence);
    RUN_TEST(test_sines);
    RUN_TEST(test_dc_blocker_removes_an_offset_and_keeps_speech_band);
    RUN_TEST(test_gain_saturates);
    return UNITY_END();
}
