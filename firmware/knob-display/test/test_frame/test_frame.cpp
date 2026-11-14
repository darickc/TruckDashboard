// The line protocol (ADR-0044 decision 3): checksums, config and data
// frames, and everything that must be dropped.

#include <unity.h>

#include <cstring>

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

Frames all;

Parsed parseAll(const std::string& line)
{
    all = Frames();
    return parseLine(line, all);
}

void test_nav_frames()
{
    TEST_ASSERT_EQUAL(Parsed::Nav, parseAll(withChecksum("N1 go right 0.4 mi 12 mi 18 Main Street")));
    TEST_ASSERT_EQUAL(NavState::Active, all.nav.state);
    TEST_ASSERT_EQUAL(Turn::Right, all.nav.turn);
    TEST_ASSERT_EQUAL_STRING("0.4", all.nav.dist);
    TEST_ASSERT_EQUAL_STRING("mi", all.nav.distUnit);
    TEST_ASSERT_EQUAL_STRING("12", all.nav.left);
    TEST_ASSERT_EQUAL_UINT16(18, all.nav.minutes);
    TEST_ASSERT_EQUAL_STRING("Main Street", all.nav.text);
    // No street.
    TEST_ASSERT_EQUAL(Parsed::Nav, parseAll(withChecksum("N1 go dest 300 ft 300 ft 1")));
    TEST_ASSERT_EQUAL(Turn::Destination, all.nav.turn);
    TEST_ASSERT_EQUAL_STRING("", all.nav.text);
    TEST_ASSERT_EQUAL(Parsed::Nav, parseAll(withChecksum("N1 wait")));
    TEST_ASSERT_EQUAL(NavState::Waiting, all.nav.state);
    TEST_ASSERT_EQUAL(Parsed::Nav, parseAll(withChecksum("N1 none")));
    TEST_ASSERT_EQUAL(Parsed::Nav, parseAll(withChecksum("N1 route")));
    TEST_ASSERT_EQUAL(NavState::Routing, all.nav.state);
    TEST_ASSERT_EQUAL(Parsed::Nav, parseAll(withChecksum("N1 arr Home")));
    TEST_ASSERT_EQUAL(NavState::Arrived, all.nav.state);
    TEST_ASSERT_EQUAL_STRING("Home", all.nav.text);
    const char* bad[] = {"N1", "N1 maybe", "N1 wait now", "N1 go hop 1 mi 2 mi 3", "N1 go right 1 mi 2 mi",
                         "N1 go right 1 mi 2 mi x", "N1 go right 123456789 mi 2 mi 3"};
    for (const char* b : bad) TEST_ASSERT_EQUAL_MESSAGE(Parsed::Malformed, parseAll(withChecksum(b)), b);
}

void test_every_turn_name_round_trips()
{
    for (int i = 0; i <= static_cast<int>(Turn::Ferry); ++i) {
        std::string line = std::string("N1 go ") + turnName(static_cast<Turn>(i)) + " 1 mi 2 mi 3";
        TEST_ASSERT_EQUAL(Parsed::Nav, parseAll(withChecksum(line)));
        TEST_ASSERT_EQUAL(i, static_cast<int>(all.nav.turn));
    }
}

void test_long_or_odd_text_is_cut_safely()
{
    // A street longer than the field, ending in a multi-byte character that
    // would be split: cut before it.
    std::string street(94, 'a');
    street += "\xC3\xA9\xC3\xA9";  // "éé"
    TEST_ASSERT_EQUAL(Parsed::Nav, parseAll(withChecksum("N1 go left 1 mi 2 mi 3 " + street)));
    // 95 bytes fit; the 95th would be the first half of an "é", so it stops
    // at 94.
    TEST_ASSERT_EQUAL_size_t(94, std::strlen(all.nav.text));
    TEST_ASSERT_EQUAL_CHAR('a', all.nav.text[93]);
    // Control characters become spaces.
    TEST_ASSERT_EQUAL(Parsed::Media, parseAll(withChecksum("M1 play - 1 2 A\x01" "B\tC\tD")));
    TEST_ASSERT_EQUAL_STRING("A B", all.media.title);
}

// The exact nav and media lines knob-link's pages.rs tests produce.
void test_golden_page_lines_from_knob_link()
{
    TEST_ASSERT_EQUAL(Parsed::Nav, parseAll("N1 go right 0.4 mi 12 mi 18 Main Street*1D"));
    TEST_ASSERT_EQUAL(Turn::Right, all.nav.turn);
    TEST_ASSERT_EQUAL_STRING("Main Street", all.nav.text);
    TEST_ASSERT_EQUAL(Parsed::Media, parseAll("M1 play 18/30 94 242 Second Simulated Song\tThe Test Tones\tPixel 8*67"));
    TEST_ASSERT_EQUAL_STRING("Pixel 8", all.media.source);
    TEST_ASSERT_EQUAL_INT32(94, all.media.posS);
}

void test_media_frames()
{
    TEST_ASSERT_EQUAL(Parsed::Media,
                      parseAll(withChecksum("M1 play 18/30 94 242 Second Simulated Song\tThe Test Tones\tPixel 8")));
    TEST_ASSERT_EQUAL(PlayState::Playing, all.media.state);
    TEST_ASSERT_EQUAL_INT16(18, all.media.volume);
    TEST_ASSERT_EQUAL_INT16(30, all.media.volumeSteps);
    TEST_ASSERT_FALSE(all.media.muted);
    TEST_ASSERT_EQUAL_INT32(94, all.media.posS);
    TEST_ASSERT_EQUAL_INT32(242, all.media.durS);
    TEST_ASSERT_EQUAL_STRING("Second Simulated Song", all.media.title);
    TEST_ASSERT_EQUAL_STRING("The Test Tones", all.media.artist);
    TEST_ASSERT_EQUAL_STRING("Pixel 8", all.media.source);
    TEST_ASSERT_EQUAL(Parsed::Media, parseAll(withChecksum("M1 pause m12/30 - - Podcast\t\tPixel 8")));
    TEST_ASSERT_TRUE(all.media.muted);
    TEST_ASSERT_EQUAL_INT32(-1, all.media.posS);
    TEST_ASSERT_EQUAL_STRING("", all.media.artist);
    TEST_ASSERT_EQUAL(Parsed::Media, parseAll(withChecksum("M1 none 15/30")));
    TEST_ASSERT_EQUAL(PlayState::None, all.media.state);
    TEST_ASSERT_EQUAL_INT16(15, all.media.volume);
    TEST_ASSERT_EQUAL(Parsed::Media, parseAll(withChecksum("M1 none -")));
    TEST_ASSERT_EQUAL_INT16(-1, all.media.volume);
    const char* bad[] = {"M1 jam 1/30 - - x", "M1 play 31/30 - - x", "M1 play 1/0 - - x", "M1 play 1/30 x - y",
                         "M1 none", "M1 none 1/30 extra"};
    for (const char* b : bad) TEST_ASSERT_EQUAL_MESSAGE(Parsed::Malformed, parseAll(withChecksum(b)), b);
    // The gauge-only parser leaves its frames alone on these.
    DataFrame d;
    d.seq = 5;
    ConfigFrame c;
    TEST_ASSERT_EQUAL(Parsed::Media, parseLine(withChecksum("M1 none -"), c, d));
    TEST_ASSERT_EQUAL_UINT32(5, d.seq);
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
    RUN_TEST(test_nav_frames);
    RUN_TEST(test_every_turn_name_round_trips);
    RUN_TEST(test_long_or_odd_text_is_cut_safely);
    RUN_TEST(test_media_frames);
    RUN_TEST(test_golden_page_lines_from_knob_link);
    return UNITY_END();
}
