// The round screen's layout (ADR-0044 decision 5): the arcs stay on the
// screen, don't overlap, and fill the right way.

#include <unity.h>

#include <cmath>

#include "Layout.h"

using namespace knob;

extern "C" {
void setUp(void) {}
void tearDown(void) {}
}

void test_polar_is_up_and_clockwise()
{
    Point top = polar(0, 100);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 180, top.x);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 80, top.y);
    Point right = polar(90, 100);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 280, right.x);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 180, right.y);
}

void test_every_arc_is_on_the_round_screen()
{
    const Slot arcs[] = {Slot::Fuel, Slot::Eot, Slot::Ect, Slot::Delta};
    for (Slot s : arcs) {
        Arc a;
        TEST_ASSERT_TRUE(arcFor(s, a));
        TEST_ASSERT_TRUE(a.radius + a.width / 2 <= kCentre);
        TEST_ASSERT_TRUE(a.endDeg > a.startDeg);
    }
    Arc none;
    TEST_ASSERT_FALSE(arcFor(Slot::Speed, none));
}

void test_the_top_arcs_dont_touch_and_fuel_is_at_the_bottom()
{
    Arc eot, ect, dlt, fuel;
    arcFor(Slot::Eot, eot);
    arcFor(Slot::Ect, ect);
    arcFor(Slot::Delta, dlt);
    arcFor(Slot::Fuel, fuel);
    TEST_ASSERT_TRUE(eot.endDeg < ect.startDeg);
    TEST_ASSERT_TRUE(ect.endDeg < dlt.startDeg);
    // Symmetric about the top and the bottom.
    TEST_ASSERT_EQUAL_FLOAT(0, (ect.startDeg + ect.endDeg) / 2);
    TEST_ASSERT_EQUAL_FLOAT(180, (fuel.startDeg + fuel.endDeg) / 2);
    TEST_ASSERT_EQUAL_FLOAT(-eot.startDeg, dlt.endDeg);
    // Room between the top arcs' ends and fuel's on both sides.
    TEST_ASSERT_TRUE(fuel.startDeg - dlt.endDeg >= 40);
}

void test_fills()
{
    Arc ect, fuel;
    arcFor(Slot::Ect, ect);
    arcFor(Slot::Fuel, fuel);
    TEST_ASSERT_EQUAL_FLOAT(ect.startDeg, fillEndDeg(ect, 0));
    TEST_ASSERT_EQUAL_FLOAT(ect.endDeg, fillEndDeg(ect, 1));
    TEST_ASSERT_EQUAL_FLOAT(0, fillEndDeg(ect, 0.5f));
    // Fuel fills from E, the left end.
    TEST_ASSERT_EQUAL_FLOAT(fuel.endDeg, fillEndDeg(fuel, 0));
    TEST_ASSERT_EQUAL_FLOAT(fuel.startDeg, fillEndDeg(fuel, 1));
    TEST_ASSERT_EQUAL_FLOAT(ect.endDeg, fillEndDeg(ect, 7));
}

void test_text_sits_inside_the_arcs()
{
    const Slot all[] = {Slot::Speed, Slot::Fuel, Slot::Eot, Slot::Ect, Slot::Delta};
    for (Slot s : all) {
        Point v = valueAt(s), c = captionAt(s);
        TEST_ASSERT_TRUE(std::hypot(v.x - kCentre, v.y - kCentre) < 140);
        TEST_ASSERT_TRUE(std::hypot(c.x - kCentre, c.y - kCentre) < 140);
    }
    Point spd = valueAt(Slot::Speed);
    TEST_ASSERT_EQUAL_FLOAT(kCentre, spd.x);
    // The top values are above the speed, fuel's below it.
    TEST_ASSERT_TRUE(valueAt(Slot::Ect).y < spd.y);
    TEST_ASSERT_TRUE(valueAt(Slot::Fuel).y > spd.y);
}

int main()
{
    UNITY_BEGIN();
    RUN_TEST(test_polar_is_up_and_clockwise);
    RUN_TEST(test_every_arc_is_on_the_round_screen);
    RUN_TEST(test_the_top_arcs_dont_touch_and_fuel_is_at_the_bottom);
    RUN_TEST(test_fills);
    RUN_TEST(test_text_sits_inside_the_arcs);
    return UNITY_END();
}
