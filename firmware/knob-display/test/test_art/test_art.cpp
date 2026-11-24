// The cover's frames (Art.h): base64 and CRC-32 against known vectors, the A1
// lines, putting a picture together (in order, out of order, a bad CRC, a
// repeat, none), and scaling it up.

#include <unity.h>

#include <cstring>
#include <string>
#include <vector>

#include "Art.h"
#include "Frame.h"

using namespace knob;

extern "C" {
void setUp(void) {}
void tearDown(void) {}
}

void test_base64()
{
    uint8_t out[8];
    size_t n = 0;
    TEST_ASSERT_TRUE(base64Decode("TWFu", out, sizeof(out), n));
    TEST_ASSERT_EQUAL(3, n);
    TEST_ASSERT_EQUAL_MEMORY("Man", out, 3);
    TEST_ASSERT_TRUE(base64Decode("TWE=", out, sizeof(out), n));
    TEST_ASSERT_EQUAL(2, n);
    TEST_ASSERT_EQUAL_MEMORY("Ma", out, 2);
    TEST_ASSERT_TRUE(base64Decode("TQ==", out, sizeof(out), n));
    TEST_ASSERT_EQUAL(1, n);
    TEST_ASSERT_TRUE(base64Decode("//79", out, sizeof(out), n));
    TEST_ASSERT_EQUAL_HEX8(0xFF, out[0]);
    TEST_ASSERT_EQUAL_HEX8(0xFE, out[1]);
    TEST_ASSERT_EQUAL_HEX8(0xFD, out[2]);
    // Not base64: wrong length, a bad character, padding in the middle, too big.
    TEST_ASSERT_FALSE(base64Decode("TWF", out, sizeof(out), n));
    TEST_ASSERT_FALSE(base64Decode("TW!u", out, sizeof(out), n));
    TEST_ASSERT_FALSE(base64Decode("TQ==TWFu", out, sizeof(out), n));
    TEST_ASSERT_FALSE(base64Decode("T===", out, sizeof(out), n));
    TEST_ASSERT_FALSE(base64Decode("TWFuTWFuTWFu", out, sizeof(out), n));
}

void test_crc32_is_zlibs()
{
    const char* s = "123456789";
    TEST_ASSERT_EQUAL_HEX32(0xCBF43926, crc32(reinterpret_cast<const uint8_t*>(s), 9));
    TEST_ASSERT_EQUAL_HEX32(0x00000000, crc32(nullptr, 0));
}

void test_a1_lines()
{
    Frames f;
    TEST_ASSERT_EQUAL(Parsed::Art, parseLine(withChecksum("A1 none"), f));
    TEST_ASSERT_EQUAL(ArtKind::None, f.art.kind);

    TEST_ASSERT_EQUAL(Parsed::Art, parseLine(withChecksum("A1 begin 0000abcd 180 180 64800 cbf43926"), f));
    TEST_ASSERT_EQUAL(ArtKind::Begin, f.art.kind);
    TEST_ASSERT_EQUAL_HEX32(0xABCD, f.art.id);
    TEST_ASSERT_EQUAL(180, f.art.w);
    TEST_ASSERT_EQUAL(180, f.art.h);
    TEST_ASSERT_EQUAL(64800, f.art.len);
    TEST_ASSERT_EQUAL_HEX32(0xCBF43926, f.art.crc);

    TEST_ASSERT_EQUAL(Parsed::Art, parseLine(withChecksum("A1 data 0000abcd 300 TWFu"), f));
    TEST_ASSERT_EQUAL(ArtKind::Data, f.art.kind);
    TEST_ASSERT_EQUAL(300, f.art.offset);
    TEST_ASSERT_EQUAL(3, f.art.n);
    TEST_ASSERT_EQUAL_MEMORY("Man", f.art.bytes, 3);

    // A full chunk fits in one line.
    const std::string full = "A1 data ffffffff 64650 " + std::string(200, 'A');
    TEST_ASSERT_TRUE(withChecksum(full).size() <= kMaxLine);
    TEST_ASSERT_EQUAL(Parsed::Art, parseLine(withChecksum(full), f));
    TEST_ASSERT_EQUAL(kArtChunk, f.art.n);

    TEST_ASSERT_EQUAL(Parsed::Malformed, parseLine(withChecksum("A1 data 0000abcd 0 TWF"), f));
    TEST_ASSERT_EQUAL(Parsed::Malformed, parseLine(withChecksum("A1 begin abcd 180 180 64800 cbf43926"), f));
    TEST_ASSERT_EQUAL(Parsed::Malformed, parseLine(withChecksum("A1 none extra"), f));
    TEST_ASSERT_EQUAL(Parsed::Malformed, parseLine(withChecksum("A1 later"), f));
    // Too much for one chunk.
    TEST_ASSERT_EQUAL(Parsed::Malformed,
                      parseLine(withChecksum("A1 data 0000abcd 0 " + std::string(204, 'A')), f));
}

// A 2 x 2 picture's frames: begin and two data chunks.
struct Pic {
    uint8_t px[8] = {0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0};
    ArtFrame begin(uint32_t id, uint32_t crc) const
    {
        ArtFrame f;
        f.kind = ArtKind::Begin;
        f.id = id;
        f.w = 2;
        f.h = 2;
        f.len = 8;
        f.crc = crc;
        return f;
    }
    ArtFrame data(uint32_t id, uint32_t offset, uint16_t n) const
    {
        ArtFrame f;
        f.kind = ArtKind::Data;
        f.id = id;
        f.offset = offset;
        f.n = n;
        std::memcpy(f.bytes, px + offset, n);
        return f;
    }
    uint32_t crc() const { return crc32(px, 8); }
};

void test_assembles_a_picture_in_order()
{
    uint8_t buf[kArtMaxBytes];
    ArtAssembler a(buf, sizeof(buf));
    Pic p;
    using R = ArtAssembler::Result;
    TEST_ASSERT_EQUAL(R::Ignored, a.feed(p.data(7, 0, 4)));
    TEST_ASSERT_EQUAL(R::Started, a.feed(p.begin(7, p.crc())));
    TEST_ASSERT_EQUAL(R::Progress, a.feed(p.data(7, 0, 4)));
    TEST_ASSERT_EQUAL(0u, a.id());
    TEST_ASSERT_EQUAL(R::Complete, a.feed(p.data(7, 4, 4)));
    TEST_ASSERT_EQUAL(7u, a.id());
    TEST_ASSERT_EQUAL(2, a.width());
    TEST_ASSERT_EQUAL(2, a.height());
    TEST_ASSERT_EQUAL_MEMORY(p.px, a.pixels(), 8);
    // knob-link's repeat of the same picture is skipped, and its data ignored.
    TEST_ASSERT_EQUAL(R::Same, a.feed(p.begin(7, p.crc())));
    TEST_ASSERT_EQUAL(R::Ignored, a.feed(p.data(7, 0, 4)));
    TEST_ASSERT_EQUAL(7u, a.id());
    // None clears it; the same picture is then taken again.
    TEST_ASSERT_EQUAL(R::Cleared, a.feed(ArtFrame{}));
    TEST_ASSERT_EQUAL(0u, a.id());
    TEST_ASSERT_EQUAL(R::Started, a.feed(p.begin(7, p.crc())));
}

void test_refuses_gaps_wrong_ids_bad_crcs_and_oversize()
{
    uint8_t buf[kArtMaxBytes];
    ArtAssembler a(buf, sizeof(buf));
    Pic p;
    using R = ArtAssembler::Result;
    // A gap (a dropped line): the picture is abandoned until the next begin.
    a.feed(p.begin(1, p.crc()));
    TEST_ASSERT_EQUAL(R::Failed, a.feed(p.data(1, 4, 4)));
    TEST_ASSERT_EQUAL(R::Ignored, a.feed(p.data(1, 0, 4)));
    // Another picture's data.
    a.feed(p.begin(2, p.crc()));
    TEST_ASSERT_EQUAL(R::Failed, a.feed(p.data(3, 0, 4)));
    // A bad CRC.
    a.feed(p.begin(4, p.crc() ^ 1));
    a.feed(p.data(4, 0, 4));
    TEST_ASSERT_EQUAL(R::Failed, a.feed(p.data(4, 4, 4)));
    TEST_ASSERT_EQUAL(0u, a.id());
    // A length that doesn't match the size, or more than the buffer holds.
    ArtFrame b = p.begin(5, 0);
    b.len = 6;
    TEST_ASSERT_EQUAL(R::Failed, a.feed(b));
    uint8_t small[4];
    ArtAssembler tiny(small, sizeof(small));
    TEST_ASSERT_EQUAL(R::Failed, tiny.feed(p.begin(6, p.crc())));
    // A new picture after a complete one replaces it.
    a.feed(p.begin(8, p.crc()));
    a.feed(p.data(8, 0, 8));
    TEST_ASSERT_EQUAL(8u, a.id());
    TEST_ASSERT_EQUAL(R::Started, a.feed(p.begin(9, p.crc())));
    TEST_ASSERT_EQUAL(0u, a.id());
}

uint16_t at(const std::vector<uint8_t>& v, int w, int x, int y)
{
    const size_t i = (static_cast<size_t>(y) * w + x) * 2;
    return static_cast<uint16_t>((v[i] << 8) | v[i + 1]);
}

void test_scaling_keeps_flat_colours_and_blends_edges()
{
    // A flat colour stays that colour.
    std::vector<uint8_t> src(3 * 3 * 2), dst(6 * 6 * 2);
    for (size_t i = 0; i < src.size(); i += 2) {
        src[i] = 0xAB;
        src[i + 1] = 0xCD;
    }
    scaleArt(src.data(), 3, 3, dst.data(), 6, 6);
    for (int y = 0; y < 6; ++y) {
        for (int x = 0; x < 6; ++x) TEST_ASSERT_EQUAL_HEX16(0xABCD, at(dst, 6, x, y));
    }
    // Black beside white, 2 x 1 to 4 x 1: the ends keep their colours, the
    // middle two blend a quarter and three quarters.
    std::vector<uint8_t> bw = {0x00, 0x00, 0xFF, 0xFF}, out(4 * 2);
    scaleArt(bw.data(), 2, 1, out.data(), 4, 1);
    TEST_ASSERT_EQUAL_HEX16(0x0000, at(out, 4, 0, 0));
    TEST_ASSERT_EQUAL_HEX16(0xFFFF, at(out, 4, 3, 0));
    const uint16_t q = at(out, 4, 1, 0), tq = at(out, 4, 2, 0);
    TEST_ASSERT_EQUAL(8, q >> 11);              // 31 / 4, rounded
    TEST_ASSERT_EQUAL(16, (q >> 5) & 0x3F);     // 63 / 4
    TEST_ASSERT_EQUAL(23, tq >> 11);            // 31 * 3 / 4
    TEST_ASSERT_EQUAL(47, (tq >> 5) & 0x3F);    // 63 * 3 / 4
    // 180 to 360, the size the dial uses: the corners keep their pixels.
    std::vector<uint8_t> big(kArtMaxBytes, 0), screen(360 * 360 * 2);
    big[0] = 0xF8;  // top left red
    big[kArtMaxBytes - 2] = 0x00;
    big[kArtMaxBytes - 1] = 0x1F;  // bottom right blue
    scaleArt(big.data(), 180, 180, screen.data(), 360, 360);
    TEST_ASSERT_EQUAL_HEX16(0xF800, at(screen, 360, 0, 0));
    TEST_ASSERT_EQUAL_HEX16(0x001F, at(screen, 360, 359, 359));
}

int main()
{
    UNITY_BEGIN();
    RUN_TEST(test_base64);
    RUN_TEST(test_crc32_is_zlibs);
    RUN_TEST(test_a1_lines);
    RUN_TEST(test_assembles_a_picture_in_order);
    RUN_TEST(test_refuses_gaps_wrong_ids_bad_crcs_and_oversize);
    RUN_TEST(test_scaling_keeps_flat_colours_and_blends_edges);
    return UNITY_END();
}
