// The knob's encoder: a low pulse on A is a step one way, on B the other
// (Waveshare's "bidirectional switch" knob, sampled every 3 ms).

#include <unity.h>

#include "PulseKnob.h"

using namespace knob;

extern "C" {
void setUp(void) {}
void tearDown(void) {}
}

namespace {
// Holds the lines for n samples and returns the steps counted.
int hold(PulseKnob& k, bool a, bool b, int n)
{
    int steps = 0;
    for (int i = 0; i < n; ++i) steps += k.sample(a, b);
    return steps;
}
}  // namespace

void test_idle_is_nothing()
{
    PulseKnob k;
    TEST_ASSERT_EQUAL(0, hold(k, true, true, 100));
}

void test_a_pulse_on_a_is_plus_one_on_its_release()
{
    PulseKnob k;
    TEST_ASSERT_EQUAL(0, hold(k, false, true, 5));  // nothing while low
    TEST_ASSERT_EQUAL(1, k.sample(true, true));     // counted on release
    TEST_ASSERT_EQUAL(0, hold(k, true, true, 10));  // once
}

void test_a_pulse_on_b_is_minus_one()
{
    PulseKnob k;
    hold(k, true, false, 3);
    TEST_ASSERT_EQUAL(-1, k.sample(true, true));
}

void test_a_glitch_shorter_than_two_samples_is_ignored()
{
    PulseKnob k;
    k.sample(false, true);
    TEST_ASSERT_EQUAL(0, k.sample(true, true));
    // Exactly two low samples is enough.
    hold(k, false, true, 2);
    TEST_ASSERT_EQUAL(1, k.sample(true, true));
}

void test_the_minimum_is_configurable()
{
    PulseKnob k(4);
    hold(k, false, true, 3);
    TEST_ASSERT_EQUAL(0, k.sample(true, true));
    hold(k, false, true, 4);
    TEST_ASSERT_EQUAL(1, k.sample(true, true));
}

void test_quick_turns_count_every_detent()
{
    PulseKnob k;
    int steps = 0;
    for (int i = 0; i < 5; ++i) {
        steps += hold(k, false, true, 2);
        steps += hold(k, true, true, 1);
    }
    TEST_ASSERT_EQUAL(5, steps);
}

void test_both_released_together_cancel()
{
    PulseKnob k;
    hold(k, false, false, 3);
    TEST_ASSERT_EQUAL(0, k.sample(true, true));
}

void test_a_line_held_low_for_a_long_time_counts_once()
{
    PulseKnob k;
    TEST_ASSERT_EQUAL(0, hold(k, true, false, 1000));
    TEST_ASSERT_EQUAL(-1, k.sample(true, true));
}

int main(int, char**)
{
    UNITY_BEGIN();
    RUN_TEST(test_idle_is_nothing);
    RUN_TEST(test_a_pulse_on_a_is_plus_one_on_its_release);
    RUN_TEST(test_a_pulse_on_b_is_minus_one);
    RUN_TEST(test_a_glitch_shorter_than_two_samples_is_ignored);
    RUN_TEST(test_the_minimum_is_configurable);
    RUN_TEST(test_quick_turns_count_every_detent);
    RUN_TEST(test_both_released_together_cancel);
    RUN_TEST(test_a_line_held_low_for_a_long_time_counts_once);
    return UNITY_END();
}
