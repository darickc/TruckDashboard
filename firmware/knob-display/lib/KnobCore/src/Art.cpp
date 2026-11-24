#include "Art.h"

#include <cstring>

namespace knob {

namespace {

int b64Value(char c)
{
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

}  // namespace

bool base64Decode(std::string_view in, uint8_t* out, size_t cap, size_t& n)
{
    n = 0;
    if (in.size() % 4 != 0) return false;
    for (size_t i = 0; i < in.size(); i += 4) {
        int v[4];
        int pad = 0;
        for (int k = 0; k < 4; ++k) {
            const char c = in[i + k];
            if (c == '=') {
                // Only at the end, and only in the last two places.
                if (i + 4 != in.size() || k < 2) return false;
                v[k] = 0;
                pad++;
            } else {
                if (pad) return false;
                v[k] = b64Value(c);
                if (v[k] < 0) return false;
            }
        }
        const uint32_t triple = (static_cast<uint32_t>(v[0]) << 18) | (static_cast<uint32_t>(v[1]) << 12) |
                                (static_cast<uint32_t>(v[2]) << 6) | static_cast<uint32_t>(v[3]);
        const int bytes = 3 - pad;
        if (n + static_cast<size_t>(bytes) > cap) return false;
        out[n++] = static_cast<uint8_t>(triple >> 16);
        if (bytes > 1) out[n++] = static_cast<uint8_t>(triple >> 8);
        if (bytes > 2) out[n++] = static_cast<uint8_t>(triple);
    }
    return true;
}

uint32_t crc32(const uint8_t* data, size_t n)
{
    uint32_t c = 0xFFFFFFFFu;
    for (size_t i = 0; i < n; ++i) {
        c ^= data[i];
        for (int k = 0; k < 8; ++k) c = (c >> 1) ^ (0xEDB88320u & (0u - (c & 1u)));
    }
    return ~c;
}

ArtAssembler::Result ArtAssembler::feed(const ArtFrame& f)
{
    switch (f.kind) {
        case ArtKind::None:
            receiving_ = false;
            shownId_ = 0;
            return Result::Cleared;
        case ArtKind::Begin: {
            if (f.id != 0 && f.id == shownId_) {
                receiving_ = false;
                return Result::Same;
            }
            const uint32_t want = static_cast<uint32_t>(f.w) * f.h * 2;
            if (f.w == 0 || f.h == 0 || f.len != want || f.len > cap_) {
                receiving_ = false;
                return Result::Failed;
            }
            // The buffer is about to be overwritten: no complete picture now.
            shownId_ = 0;
            receiving_ = true;
            rxId_ = f.id;
            rxW_ = f.w;
            rxH_ = f.h;
            rxLen_ = f.len;
            rxCrc_ = f.crc;
            rxGot_ = 0;
            return Result::Started;
        }
        case ArtKind::Data: {
            if (!receiving_) return Result::Ignored;
            if (f.id != rxId_ || f.offset != rxGot_ || f.n == 0 || rxGot_ + f.n > rxLen_) {
                receiving_ = false;
                return Result::Failed;
            }
            std::memcpy(buf_ + rxGot_, f.bytes, f.n);
            rxGot_ += f.n;
            if (rxGot_ < rxLen_) return Result::Progress;
            receiving_ = false;
            if (crc32(buf_, rxLen_) != rxCrc_) return Result::Failed;
            shownId_ = rxId_;
            w_ = rxW_;
            h_ = rxH_;
            return Result::Complete;
        }
    }
    return Result::Ignored;
}

void scaleArt(const uint8_t* src, int sw, int sh, uint8_t* dst, int dw, int dh)
{
    auto px = [&](int x, int y) {
        const uint8_t* p = src + (static_cast<size_t>(y) * sw + x) * 2;
        return static_cast<uint16_t>((p[0] << 8) | p[1]);
    };
    for (int y = 0; y < dh; ++y) {
        // Pixel centres, in 1/256ths of a source pixel.
        int fy = ((2 * y + 1) * sh * 128) / dh - 128;
        if (fy < 0) fy = 0;
        int y0 = fy >> 8;
        if (y0 >= sh - 1) {
            y0 = sh - 1;
            fy = y0 << 8;
        }
        const int y1 = y0 + 1 < sh ? y0 + 1 : y0;
        const int wy = fy & 0xFF;
        for (int x = 0; x < dw; ++x) {
            int fx = ((2 * x + 1) * sw * 128) / dw - 128;
            if (fx < 0) fx = 0;
            int x0 = fx >> 8;
            if (x0 >= sw - 1) {
                x0 = sw - 1;
                fx = x0 << 8;
            }
            const int x1 = x0 + 1 < sw ? x0 + 1 : x0;
            const int wx = fx & 0xFF;
            const uint16_t c[4] = {px(x0, y0), px(x1, y0), px(x0, y1), px(x1, y1)};
            const int w[4] = {(256 - wx) * (256 - wy), wx * (256 - wy), (256 - wx) * wy, wx * wy};
            int r = 0, g = 0, b = 0;
            for (int k = 0; k < 4; ++k) {
                r += ((c[k] >> 11) & 0x1F) * w[k];
                g += ((c[k] >> 5) & 0x3F) * w[k];
                b += (c[k] & 0x1F) * w[k];
            }
            // Weights sum to 65536: round to nearest.
            r = (r + 32768) >> 16;
            g = (g + 32768) >> 16;
            b = (b + 32768) >> 16;
            const uint16_t out = static_cast<uint16_t>((r << 11) | (g << 5) | b);
            uint8_t* d = dst + (static_cast<size_t>(y) * dw + x) * 2;
            d[0] = static_cast<uint8_t>(out >> 8);
            d[1] = static_cast<uint8_t>(out);
        }
    }
}

}  // namespace knob
