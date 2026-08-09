// Unit tests: ELM line accumulation, classification, hex parsing, and ISO-TP
// reassembly (single frame, multi-frame, interleaved ECUs).

#include <unity.h>

#include <cstring>

#include "ElmParser.h"

using namespace obd;

extern "C" {
void setUp(void) {}
void tearDown(void) {}
}

// ---------------------------------------------------------------------------
// LineAccumulator
// ---------------------------------------------------------------------------
static void test_accumulator_cr_terminated_lines()
{
    LineAccumulator acc;
    const char* input = "OK\r";
    LineAccumulator::Event ev = LineAccumulator::Event::None;
    for (const char* p = input; *p; ++p) {
        ev = acc.feed(*p);
    }
    TEST_ASSERT_EQUAL(LineAccumulator::Event::Line, ev);
    TEST_ASSERT_EQUAL_STRING("OK", acc.line());
}

static void test_accumulator_prompt_event()
{
    LineAccumulator acc;
    TEST_ASSERT_EQUAL(LineAccumulator::Event::Prompt, acc.feed('>'));
}

static void test_accumulator_blank_lines_swallowed()
{
    LineAccumulator acc;
    TEST_ASSERT_EQUAL(LineAccumulator::Event::None, acc.feed('\r'));
    TEST_ASSERT_EQUAL(LineAccumulator::Event::None, acc.feed('\n'));
    TEST_ASSERT_EQUAL(LineAccumulator::Event::None, acc.feed('\r'));
}

static void test_accumulator_crlf_and_multiple_lines()
{
    LineAccumulator acc;
    int lines = 0;
    for (const char* p = "ELM327 v1.4b\r\nOK\r\n"; *p; ++p) {
        if (acc.feed(*p) == LineAccumulator::Event::Line) {
            ++lines;
            if (lines == 1) {
                TEST_ASSERT_EQUAL_STRING("ELM327 v1.4b", acc.line());
            } else {
                TEST_ASSERT_EQUAL_STRING("OK", acc.line());
            }
        }
    }
    TEST_ASSERT_EQUAL_INT(2, lines);
}

// ---------------------------------------------------------------------------
// Classification
// ---------------------------------------------------------------------------
static void test_classify_statuses()
{
    TEST_ASSERT_EQUAL(LineClass::Ok, classifyLine("OK"));
    TEST_ASSERT_EQUAL(LineClass::NoData, classifyLine("NO DATA"));
    TEST_ASSERT_EQUAL(LineClass::Stopped, classifyLine("STOPPED"));
    TEST_ASSERT_EQUAL(LineClass::Searching, classifyLine("SEARCHING..."));
    TEST_ASSERT_EQUAL(LineClass::CanError, classifyLine("CAN ERROR"));
    TEST_ASSERT_EQUAL(LineClass::BufferFull, classifyLine("BUFFER FULL"));
    TEST_ASSERT_EQUAL(LineClass::UnableToConnect, classifyLine("UNABLE TO CONNECT"));
    TEST_ASSERT_EQUAL(LineClass::Error, classifyLine("?"));
    TEST_ASSERT_EQUAL(LineClass::Ignorable, classifyLine("ACT ALERT"));
    TEST_ASSERT_EQUAL(LineClass::Ignorable, classifyLine("LV RESET"));
    TEST_ASSERT_EQUAL(LineClass::Unknown, classifyLine("ELM327 v1.4b"));
}

static void test_classify_hex_data()
{
    TEST_ASSERT_EQUAL(LineClass::HexData, classifyLine("7E804410C1AF8"));
    TEST_ASSERT_EQUAL(LineClass::HexData, classifyLine("41 0C 1A F8")); // spaces tolerated
    TEST_ASSERT_EQUAL(LineClass::Unknown, classifyLine("41 0C 1A FX"));
}

// ---------------------------------------------------------------------------
// Hex utilities
// ---------------------------------------------------------------------------
static void test_hex_to_bytes()
{
    uint8_t out[8];
    TEST_ASSERT_EQUAL_UINT(4, hexToBytes("410C1AF8", out, sizeof(out)));
    TEST_ASSERT_EQUAL_HEX8(0x41, out[0]);
    TEST_ASSERT_EQUAL_HEX8(0xF8, out[3]);
    TEST_ASSERT_EQUAL_UINT(0, hexToBytes("410C1", out, sizeof(out)));  // odd length
    TEST_ASSERT_EQUAL_UINT(0, hexToBytes("41ZZ", out, sizeof(out)));   // invalid chars
    TEST_ASSERT_EQUAL_UINT(0, hexToBytes("0102030405060708FF", out, sizeof(out))); // overflow
}

static void test_strip_spaces()
{
    char s[] = "41 0C 1A F8";
    stripSpacesInPlace(s);
    TEST_ASSERT_EQUAL_STRING("410C1AF8", s);
}

// ---------------------------------------------------------------------------
// Data-line framing
// ---------------------------------------------------------------------------
static void test_parse_data_line_with_header()
{
    Frame f;
    TEST_ASSERT_TRUE(parseDataLine("7E804410C1AF8", f));
    TEST_ASSERT_TRUE(f.hasHeader);
    TEST_ASSERT_EQUAL_HEX32(0x7E8, f.canId);
    TEST_ASSERT_EQUAL_UINT8(5, f.len);
    TEST_ASSERT_EQUAL_HEX8(0x04, f.data[0]); // PCI
    TEST_ASSERT_EQUAL_HEX8(0x41, f.data[1]);
}

static void test_parse_data_line_headerless()
{
    Frame f;
    TEST_ASSERT_TRUE(parseDataLine("410C1AF8", f));
    TEST_ASSERT_FALSE(f.hasHeader);
    TEST_ASSERT_EQUAL_UINT8(4, f.len);
    TEST_ASSERT_EQUAL_HEX8(0x41, f.data[0]);
}

static void test_parse_data_line_malformed()
{
    Frame f;
    TEST_ASSERT_FALSE(parseDataLine("4", f));
    TEST_ASSERT_FALSE(parseDataLine("", f));
    TEST_ASSERT_FALSE(parseDataLine("XYZ12", f));
}

// ---------------------------------------------------------------------------
// ISO-TP reassembly
// ---------------------------------------------------------------------------
static void test_isotp_single_frame()
{
    IsoTpReassembler r;
    r.reset();
    Frame f;
    TEST_ASSERT_TRUE(parseDataLine("7E804410C1AF8", f));
    TEST_ASSERT_TRUE(r.feed(f));
    TEST_ASSERT_EQUAL_UINT(4, r.payloadLen());
    const uint8_t expect[] = {0x41, 0x0C, 0x1A, 0xF8};
    TEST_ASSERT_EQUAL_HEX8_ARRAY(expect, r.payload(), 4);
    TEST_ASSERT_EQUAL_HEX32(0x7E8, r.sourceId());
}

static void test_isotp_multi_frame()
{
    // 8-byte payload: 62 13 46 AA BB CC DD EE
    // FF: PCI 10 08 + first 6 bytes; CF: PCI 21 + last 2.
    IsoTpReassembler r;
    r.reset();
    Frame f;
    TEST_ASSERT_TRUE(parseDataLine("7E81008621346AABBCC", f));
    TEST_ASSERT_FALSE(r.feed(f)); // incomplete
    TEST_ASSERT_TRUE(parseDataLine("7E821DDEE", f));
    TEST_ASSERT_TRUE(r.feed(f));
    TEST_ASSERT_EQUAL_UINT(8, r.payloadLen());
    const uint8_t expect[] = {0x62, 0x13, 0x46, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE};
    TEST_ASSERT_EQUAL_HEX8_ARRAY(expect, r.payload(), 8);
}

static void test_isotp_interleaved_ecu_ignored()
{
    // A single frame from another ECU (7E9) arriving mid-reassembly of 7E8
    // must not corrupt the multi-frame message.
    IsoTpReassembler r;
    r.reset();
    Frame f;
    TEST_ASSERT_TRUE(parseDataLine("7E81008621346AABBCC", f));
    TEST_ASSERT_FALSE(r.feed(f));
    // Consecutive frame from the WRONG ECU: ignored.
    TEST_ASSERT_TRUE(parseDataLine("7E92100FF", f));
    TEST_ASSERT_FALSE(r.feed(f));
    // Correct ECU finishes.
    TEST_ASSERT_TRUE(parseDataLine("7E821DDEE", f));
    TEST_ASSERT_TRUE(r.feed(f));
    TEST_ASSERT_EQUAL_UINT(8, r.payloadLen());
    TEST_ASSERT_EQUAL_HEX8(0xEE, r.payload()[7]);
}

static void test_isotp_sequence_error_abandons()
{
    IsoTpReassembler r;
    r.reset();
    Frame f;
    TEST_ASSERT_TRUE(parseDataLine("7E81008621346AABBCC", f));
    TEST_ASSERT_FALSE(r.feed(f));
    TEST_ASSERT_TRUE(parseDataLine("7E822DDEE", f)); // seq 2, expected 1
    TEST_ASSERT_FALSE(r.feed(f));
    TEST_ASSERT_EQUAL_UINT(0, r.payloadLen());
}

static void test_isotp_headerless_passthrough()
{
    IsoTpReassembler r;
    r.reset();
    Frame f;
    TEST_ASSERT_TRUE(parseDataLine("410C1AF8", f)); // ATH0-style line
    TEST_ASSERT_TRUE(r.feed(f));
    TEST_ASSERT_EQUAL_UINT(4, r.payloadLen());
    TEST_ASSERT_EQUAL_HEX8(0x41, r.payload()[0]);
}

int main(int, char**)
{
    UNITY_BEGIN();
    RUN_TEST(test_accumulator_cr_terminated_lines);
    RUN_TEST(test_accumulator_prompt_event);
    RUN_TEST(test_accumulator_blank_lines_swallowed);
    RUN_TEST(test_accumulator_crlf_and_multiple_lines);
    RUN_TEST(test_classify_statuses);
    RUN_TEST(test_classify_hex_data);
    RUN_TEST(test_hex_to_bytes);
    RUN_TEST(test_strip_spaces);
    RUN_TEST(test_parse_data_line_with_header);
    RUN_TEST(test_parse_data_line_headerless);
    RUN_TEST(test_parse_data_line_malformed);
    RUN_TEST(test_isotp_single_frame);
    RUN_TEST(test_isotp_multi_frame);
    RUN_TEST(test_isotp_interleaved_ecu_ignored);
    RUN_TEST(test_isotp_sequence_error_abandons);
    RUN_TEST(test_isotp_headerless_passthrough);
    return UNITY_END();
}
