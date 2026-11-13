// The line protocol (ADR-0044 decision 3): checksums, config and data
// frames, and everything that must be dropped.

#include <unity.h>

#include "Frame.h"

using namespace knob;

extern "C" {
void setUp(void) {}
void tearDown(void) {}
}

namespace {

ConfigFrame cfg;
DataFrame dat;

Parsed parse(const std::string& line)
{
    cfg = ConfigFrame();
    dat = DataFrame();
    return parseLine(line, cfg, dat);
}

const SlotValue& slot(Slot s) { return dat.slots[static_cast<size_t>(s)]; }

}  // namespace

void test_checksum_is_nmea_xor()
{
    // "H1 x" = 0x48 ^ 0x31 ^ 0x20 ^ 0x78.
    TEST_ASSERT_EQUAL_HEX8(0x48 ^ 0x31 ^ 0x20 ^ 0x78, checksum("H1 x"));
    TEST_ASSERT_EQUAL_STRING("H1 x*21", withChecksum("H1 x").c_str());
    TEST_ASSERT_EQUAL(Parsed::Hello, parse("H1 x*21"));
    TEST_ASSERT_EQUAL(Parsed::Hello, parse("H1 x*21\r\n"));
    TEST_ASSERT_EQUAL(Parsed::Hello, parse("H1 x*21\n"));
}

void test_a_bad_or_missing_checksum_is_dropped()
{
    TEST_ASSERT_EQUAL(Parsed::BadChecksum, parse("H1 x*22"));
    TEST_ASSERT_EQUAL(Parsed::BadChecksum, parse("H1 x"));
    TEST_ASSERT_EQUAL(Parsed::BadChecksum, parse("H1 x*2G"));
    TEST_ASSERT_EQUAL(Parsed::BadChecksum, parse(""));
    TEST_ASSERT_EQUAL(Parsed::BadChecksum, parse(std::string(300, 'A')));
    // One character changed in transit.
    std::string good = withChecksum("D1 7 live spd:c:62");
    good[9] = '3';
    TEST_ASSERT_EQUAL(Parsed::BadChecksum, parse(good));
}

void test_comments_and_unknown_kinds()
{
    TEST_ASSERT_EQUAL(Parsed::Comment, parse("# booting"));
    TEST_ASSERT_EQUAL(Parsed::Unknown, parse(withChecksum("D2 1 live spd:c:1")));
    TEST_ASSERT_EQUAL(Parsed::Unknown, parse(withChecksum("X1")));
}

void test_config_frame()
{
    TEST_ASSERT_EQUAL(Parsed::Config,
                      parse(withChecksum("C1 spd:mph:0:100:v fuel:%:0:100:u eot:F:100:260:u "
                                         "ect:F:100:260:v dlt:F:-10:40:v")));
    const SlotConfig& f = cfg.slots[static_cast<size_t>(Slot::Fuel)];
    TEST_ASSERT_TRUE(f.set);
    TEST_ASSERT_EQUAL_STRING("%", f.unit);
    TEST_ASSERT_TRUE(f.unverified);
    const SlotConfig& d = cfg.slots[static_cast<size_t>(Slot::Delta)];
    TEST_ASSERT_EQUAL_FLOAT(-10, d.min);
    TEST_ASSERT_EQUAL_FLOAT(40, d.max);
    TEST_ASSERT_FALSE(d.unverified);
}

void test_config_skips_unknown_slots_and_refuses_bad_ones()
{
    TEST_ASSERT_EQUAL(Parsed::Config, parse(withChecksum("C1 boost:psi:0:40:v spd:mph:0:100:v")));
    TEST_ASSERT_TRUE(cfg.slots[0].set);
    TEST_ASSERT_EQUAL(Parsed::Malformed, parse(withChecksum("C1 spd:mph:100:0:v")));  // max <= min
    TEST_ASSERT_EQUAL(Parsed::Malformed, parse(withChecksum("C1 spd:mph:0:100:x")));
    TEST_ASSERT_EQUAL(Parsed::Malformed, parse(withChecksum("C1 spd:mph:zero:100:v")));
    TEST_ASSERT_EQUAL(Parsed::Malformed, parse(withChecksum("C1 spd:toolongunit:0:100:v")));
}

void test_data_frame_states()
{
    TEST_ASSERT_EQUAL(Parsed::Data,
                      parse(withChecksum("D1 1234 sim spd:c:62.4 fuel:a:12 eot:s:205:12.5 "
                                         "ect:k:241 dlt:n")));
    TEST_ASSERT_EQUAL_UINT32(1234, dat.seq);
    TEST_ASSERT_TRUE(dat.simulated);
    TEST_ASSERT_EQUAL(State::Current, slot(Slot::Speed).state);
    TEST_ASSERT_EQUAL_FLOAT(62.4f, slot(Slot::Speed).value);
    TEST_ASSERT_EQUAL(State::Advisory, slot(Slot::Fuel).state);
    TEST_ASSERT_EQUAL(State::Stale, slot(Slot::Eot).state);
    TEST_ASSERT_EQUAL_FLOAT(205, slot(Slot::Eot).value);
    TEST_ASSERT_EQUAL_FLOAT(12.5f, slot(Slot::Eot).ageS);
    TEST_ASSERT_EQUAL(State::Critical, slot(Slot::Ect).state);
    TEST_ASSERT_EQUAL(State::None, slot(Slot::Delta).state);
    TEST_ASSERT_TRUE(slot(Slot::Delta).set);
}

void test_data_frame_refusals()
{
    const char* bad[] = {
        "D1 x live spd:c:1",         // seq
        "D1 1 maybe spd:c:1",        // mode
        "D1 1 live spd:q:1",         // state
        "D1 1 live spd:c",           // a current value without a number
        "D1 1 live spd:s:1",         // stale without an age
        "D1 1 live spd:s:1:-2",      // negative age
        "D1 1 live spd:n:5",         // nothing, with a number
        "D1 1 live spd:c:1:2",       // an age on a current value
        "D1 1 live spd:c:nan",       // not finite
        "D1 99999999999 live",       // seq overflows
    };
    for (const char* b : bad) {
        TEST_ASSERT_EQUAL_MESSAGE(Parsed::Malformed, parse(withChecksum(b)), b);
    }
    // A malformed line leaves the frames alone.
    DataFrame before;
    before.seq = 9;
    ConfigFrame c;
    TEST_ASSERT_EQUAL(Parsed::Malformed, parseLine(withChecksum("D1 1 live spd:q:1"), c, before));
    TEST_ASSERT_EQUAL_UINT32(9, before.seq);
}

void test_a_slot_left_out_is_unset()
{
    TEST_ASSERT_EQUAL(Parsed::Data, parse(withChecksum("D1 2 live spd:c:10")));
    TEST_ASSERT_FALSE(slot(Slot::Eot).set);
}

// The exact lines services/knob-link writes (its frame.rs golden tests):
// the two sides agree on the format and the checksum.
void test_golden_lines_from_knob_link()
{
    TEST_ASSERT_EQUAL(Parsed::Config,
                      parse("C1 spd:mph:0:100:v fuel:%:0:100:u eot:F:100:260:u ect:F:100:260:v "
                            "dlt:F:-10:40:u*14"));
    TEST_ASSERT_TRUE(cfg.slots[static_cast<size_t>(Slot::Delta)].unverified);
    TEST_ASSERT_EQUAL(Parsed::Data, parse("D1 7 sim spd:c:62.1 fuel:c:61 eot:s:204.8:12.4 ect:k:230 dlt:n*7A"));
    TEST_ASSERT_EQUAL_UINT32(7, dat.seq);
    TEST_ASSERT_TRUE(dat.simulated);
    TEST_ASSERT_EQUAL_FLOAT(62.1f, slot(Slot::Speed).value);
    TEST_ASSERT_EQUAL(State::Stale, slot(Slot::Eot).state);
    TEST_ASSERT_EQUAL_FLOAT(12.4f, slot(Slot::Eot).ageS);
    TEST_ASSERT_EQUAL(State::Critical, slot(Slot::Ect).state);
    TEST_ASSERT_EQUAL(State::None, slot(Slot::Delta).state);
}

int main()
{
    UNITY_BEGIN();
    RUN_TEST(test_checksum_is_nmea_xor);
    RUN_TEST(test_a_bad_or_missing_checksum_is_dropped);
    RUN_TEST(test_comments_and_unknown_kinds);
    RUN_TEST(test_config_frame);
    RUN_TEST(test_config_skips_unknown_slots_and_refuses_bad_ones);
    RUN_TEST(test_data_frame_states);
    RUN_TEST(test_data_frame_refusals);
    RUN_TEST(test_a_slot_left_out_is_unset);
    RUN_TEST(test_golden_lines_from_knob_link);
    return UNITY_END();
}
