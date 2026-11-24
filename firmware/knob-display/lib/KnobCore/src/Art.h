// The media page's album art (owner, 2026-11-23): the phone's cover, drawn
// darkened behind the page. knob-link does the picture work on the Pi —
// decodes the phone's JPEG, crops it square, scales it to 180 x 180, darkens
// it (its opacity over black, less for a bright cover) and sends it as
// RGB565, high byte first (the panel's and LVGL's order here):
//
//   A1 begin <id> <w> <h> <len> <crc32>*CS     a picture follows (hex id, crc)
//   A1 data <id> <offset> <base64>*CS          its bytes, in order
//   A1 none*CS                                 no picture for this track
//
// knob-link repeats a picture every few seconds; a begin for the picture
// already on screen is skipped, so a repeat costs only the serial bytes and
// a picture missed (bytes dropped) comes back with the next repeat. A
// picture is shown only when every byte arrived in order and its CRC-32 (the
// IEEE one, as zlib's) matches.

#pragma once

#include <cstddef>
#include <cstdint>
#include <string_view>

namespace knob {

// At most this many bytes in one data line (base64: 200 characters, so the
// line stays under kMaxLine).
constexpr size_t kArtChunk = 150;
// The largest picture knob-link sends: 180 x 180 RGB565.
constexpr uint16_t kArtMaxSide = 180;
constexpr size_t kArtMaxBytes = static_cast<size_t>(kArtMaxSide) * kArtMaxSide * 2;

enum class ArtKind : uint8_t { None, Begin, Data };

struct ArtFrame {
    ArtKind kind = ArtKind::None;
    uint32_t id = 0;
    // Begin.
    uint16_t w = 0, h = 0;
    uint32_t len = 0, crc = 0;
    // Data.
    uint32_t offset = 0;
    uint8_t bytes[kArtChunk] = {};
    uint16_t n = 0;
};

// Standard base64 (with '=' padding) into `out`; false if it isn't base64 or
// doesn't fit in `cap` bytes.
bool base64Decode(std::string_view in, uint8_t* out, size_t cap, size_t& n);

// CRC-32 (IEEE 802.3, reflected, as zlib's crc32()).
uint32_t crc32(const uint8_t* data, size_t n);

// Puts a picture together from its frames, in a buffer of the caller's.
class ArtAssembler {
public:
    enum class Result {
        Ignored,   // a data line for no picture being received
        Started,   // a begin: receiving
        Progress,  // a data line, in order
        Complete,  // the last byte, and the CRC matches: show it
        Failed,    // out of order, too big, or the CRC doesn't match
        Same,      // a begin for the picture already complete: skipped
        Cleared,   // "none": no picture
    };

    ArtAssembler(uint8_t* buf, size_t cap) : buf_(buf), cap_(cap) {}

    Result feed(const ArtFrame& f);

    // The complete picture (Complete until the next begin that starts one).
    uint32_t id() const { return shownId_; }
    uint16_t width() const { return w_; }
    uint16_t height() const { return h_; }
    const uint8_t* pixels() const { return buf_; }

private:
    uint8_t* buf_;
    size_t cap_;
    uint32_t shownId_ = 0;
    uint16_t w_ = 0, h_ = 0;
    bool receiving_ = false;
    uint32_t rxId_ = 0, rxLen_ = 0, rxCrc_ = 0, rxGot_ = 0;
    uint16_t rxW_ = 0, rxH_ = 0;
};

// Scales an RGB565 picture (high byte first) from sw x sh to dw x dh,
// bilinear, into `dst` (dw * dh * 2 bytes, the same byte order).
void scaleArt(const uint8_t* src, int sw, int sh, uint8_t* dst, int dw, int dh);

}  // namespace knob
