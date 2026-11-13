// What the dial shows (ADR-0044 decision 4): current, alerts, stale with its
// age, nothing, and the link going quiet.

#include <unity.h>

#include <cstring>

#include "Dial.h"

using namespace knob;

extern "C" {
void setUp(void) {}
void tearDown(void) {}
}

namespace {

void feed(Dial& d, const std::string& body, uint32_t now)
{
    ConfigFrame c;
    DataFrame f;
    Parsed p = parseLine(withChecksum(body), c, f);
    if (p == Parsed::Config) d.onConfig(c);
    if (p == Parsed::Data) d.onData(f, now);
    TEST_ASSERT_TRUE(p == Parsed::Config || p == Parsed::Data);
}

Dial configured()
{
    Dial d(2000);
    feed(d, "C1 spd:mph:0:100:v fuel:%:0:100:u eot:F:100:260:u ect:F:100:260:v dlt:F:-10:40:v", 0);
    return d;
}

std::string text(Slot s, const View& v)
{
    char buf[16];
    formatValue(s, v, buf, sizeof(buf));
    return buf;
}

}  // namespace

void test_nothing_before_the_first_frame()
{
    Dial d = configured();
    TEST_ASSERT_TRUE(d.linkLost(0));
    TEST_ASSERT_FALSE(d.everHadData());
    View v = d.view(Slot::Speed, 0);
    TEST_ASSERT_EQUAL(State::None, v.state);
    TEST_ASSERT_EQUAL_STRING("\xE2\x80\x94", text(Slot::Speed, v).c_str());
}

void test_current_values_and_their_arcs()
{
    Dial d = configured();
    feed(d, "D1 1 live spd:c:62 fuel:c:61 eot:c:180 ect:c:196 dlt:c:9", 1000);
    TEST_ASSERT_FALSE(d.linkLost(1500));
    TEST_ASSERT_FALSE(d.simulated());
    View e = d.view(Slot::Eot, 1500);
    TEST_ASSERT_EQUAL(State::Current, e.state);
    TEST_ASSERT_EQUAL_FLOAT(0.5f, e.fraction);
    TEST_ASSERT_TRUE(e.unverified);
    TEST_ASSERT_EQUAL_STRING("F", e.unit);
    TEST_ASSERT_EQUAL_STRING("62", text(Slot::Speed, d.view(Slot::Speed, 1500)).c_str());
    TEST_ASSERT_EQUAL_STRING("61%", text(Slot::Fuel, d.view(Slot::Fuel, 1500)).c_str());
    TEST_ASSERT_EQUAL_STRING("196\xC2\xB0", text(Slot::Ect, d.view(Slot::Ect, 1500)).c_str());
    TEST_ASSERT_EQUAL_STRING("+9\xC2\xB0", text(Slot::Delta, d.view(Slot::Delta, 1500)).c_str());
    TEST_ASSERT_FALSE(d.view(Slot::Ect, 1500).unverified);
}

void test_arcs_clamp_outside_their_range()
{
    Dial d = configured();
    feed(d, "D1 1 live eot:c:300 dlt:c:-20", 0);
    TEST_ASSERT_EQUAL_FLOAT(1, d.view(Slot::Eot, 0).fraction);
    TEST_ASSERT_EQUAL_FLOAT(0, d.view(Slot::Delta, 0).fraction);
    TEST_ASSERT_EQUAL_STRING("-20\xC2\xB0", text(Slot::Delta, d.view(Slot::Delta, 0)).c_str());
}

void test_alerts_and_stale_come_from_the_pi()
{
    Dial d = configured();
    feed(d, "D1 1 sim ect:k:241 eot:s:205:12 dlt:n", 0);
    TEST_ASSERT_TRUE(d.simulated());
    TEST_ASSERT_EQUAL(State::Critical, d.view(Slot::Ect, 0).state);
    View e = d.view(Slot::Eot, 500);
    TEST_ASSERT_EQUAL(State::Stale, e.state);
    TEST_ASSERT_EQUAL_FLOAT(205, e.value);
    TEST_ASSERT_EQUAL_FLOAT(12, e.ageS);
    TEST_ASSERT_EQUAL(State::None, d.view(Slot::Delta, 0).state);
    TEST_ASSERT_EQUAL(State::None, d.view(Slot::Speed, 0).state);  // left out
}

void test_a_quiet_link_makes_everything_stale_and_ages_on()
{
    Dial d = configured();
    feed(d, "D1 1 live spd:c:62 eot:s:205:12 dlt:n", 10000);
    TEST_ASSERT_FALSE(d.linkLost(11999));
    TEST_ASSERT_TRUE(d.linkLost(12000));
    View s = d.view(Slot::Speed, 13000);
    TEST_ASSERT_EQUAL(State::Stale, s.state);
    TEST_ASSERT_EQUAL_FLOAT(62, s.value);
    TEST_ASSERT_EQUAL_FLOAT(3, s.ageS);
    TEST_ASSERT_EQUAL_FLOAT(15, d.view(Slot::Eot, 13000).ageS);
    TEST_ASSERT_EQUAL(State::None, d.view(Slot::Delta, 13000).state);
    // The next frame brings it back.
    feed(d, "D1 2 live spd:c:60", 14000);
    TEST_ASSERT_EQUAL(State::Current, d.view(Slot::Speed, 14000).state);
}

void test_the_clock_wrapping_doesnt_matter()
{
    Dial d = configured();
    feed(d, "D1 1 live spd:c:62", 0xFFFFFF00u);
    TEST_ASSERT_FALSE(d.linkLost(0x00000100u));  // 512 ms later
    TEST_ASSERT_TRUE(d.linkLost(0x00000800u));
}

void test_ages_read_plainly()
{
    char b[12];
    formatAge(12.4f, b, sizeof(b));
    TEST_ASSERT_EQUAL_STRING("12 s", b);
    formatAge(185, b, sizeof(b));
    TEST_ASSERT_EQUAL_STRING("3 min", b);
    formatAge(7300, b, sizeof(b));
    TEST_ASSERT_EQUAL_STRING("2 h", b);
}

int main()
{
    UNITY_BEGIN();
    RUN_TEST(test_nothing_before_the_first_frame);
    RUN_TEST(test_current_values_and_their_arcs);
    RUN_TEST(test_arcs_clamp_outside_their_range);
    RUN_TEST(test_alerts_and_stale_come_from_the_pi);
    RUN_TEST(test_a_quiet_link_makes_everything_stale_and_ages_on);
    RUN_TEST(test_the_clock_wrapping_doesnt_matter);
    RUN_TEST(test_ages_read_plainly);
    return UNITY_END();
}
