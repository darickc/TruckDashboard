// The boot screen's stages (Boot.h): every transition, and that a frame ends
// it for good.

#include <unity.h>

#include "Boot.h"

using namespace knob;

extern "C" {
void setUp(void) {}
void tearDown(void) {}
}

void test_waits_for_the_pi_then_starts()
{
    Boot b(180000);
    TEST_ASSERT_EQUAL(BootStage::WaitingForPi, b.stage(false, 0));
    TEST_ASSERT_EQUAL(BootStage::WaitingForPi, b.stage(false, 179999));
    TEST_ASSERT_EQUAL(BootStage::Starting, b.stage(true, 5000));
    // USB can go again (the Pi rebooting): back to waiting.
    TEST_ASSERT_EQUAL(BootStage::WaitingForPi, b.stage(false, 6000));
}

void test_gives_up_saying_what_is_missing()
{
    Boot b(180000);
    TEST_ASSERT_EQUAL(BootStage::NoHeadUnit, b.stage(false, 180000));
    TEST_ASSERT_EQUAL(BootStage::NoLink, b.stage(true, 180000));
    // A frame after giving up still ends it.
    b.onFrame();
    TEST_ASSERT_EQUAL(BootStage::Done, b.stage(true, 200000));
}

void test_a_frame_ends_it_for_good()
{
    Boot b(180000);
    b.onFrame();
    TEST_ASSERT_EQUAL(BootStage::Done, b.stage(true, 1000));
    // Losing USB afterwards is the gauges' NO DATA ring, not the boot screen.
    TEST_ASSERT_EQUAL(BootStage::Done, b.stage(false, 2000));
    TEST_ASSERT_EQUAL(BootStage::Done, b.stage(false, 500000));
}

void test_texts()
{
    TEST_ASSERT_EQUAL_STRING("WAITING FOR THE PI", bootStatus(BootStage::WaitingForPi));
    TEST_ASSERT_EQUAL_STRING("HEAD UNIT STARTING", bootStatus(BootStage::Starting));
    TEST_ASSERT_EQUAL_STRING("NO HEAD UNIT", bootStatus(BootStage::NoHeadUnit));
    TEST_ASSERT_EQUAL_STRING("CHECK THE USB CABLE", bootHint(BootStage::NoHeadUnit));
    TEST_ASSERT_EQUAL_STRING("NO DATA FROM THE PI", bootStatus(BootStage::NoLink));
    TEST_ASSERT_EQUAL_STRING("IS KNOB-LINK RUNNING?", bootHint(BootStage::NoLink));
    TEST_ASSERT_EQUAL_STRING("", bootHint(BootStage::Starting));
    TEST_ASSERT_EQUAL_STRING("", bootStatus(BootStage::Done));
}

int main()
{
    UNITY_BEGIN();
    RUN_TEST(test_waits_for_the_pi_then_starts);
    RUN_TEST(test_gives_up_saying_what_is_missing);
    RUN_TEST(test_a_frame_ends_it_for_good);
    RUN_TEST(test_texts);
    return UNITY_END();
}
