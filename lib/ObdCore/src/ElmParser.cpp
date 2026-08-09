#include "ElmParser.h"

#include <cstring>

namespace obd {

// ---------------------------------------------------------------------------
// LineAccumulator
// ---------------------------------------------------------------------------
LineAccumulator::Event LineAccumulator::feed(char c)
{
    if (c == '>') {
        // Prompt arrives without a terminator; discard any partial line
        // (typically the prompt follows a '\r' so the buffer is empty).
        clear();
        return Event::Prompt;
    }
    if (c == '\r' || c == '\n') {
        if (len_ == 0) {
            return Event::None; // swallow blank lines / CRLF pairs
        }
        buf_[len_] = '\0';
        len_ = 0; // ready for next line; buf_ stays valid until next feed
        return Event::Line;
    }
    if (c == '\0') {
        return Event::None; // ELM can emit NULs at reset; ignore
    }
    if (len_ < sizeof(buf_) - 1) {
        buf_[len_++] = c;
        buf_[len_] = '\0';
    }
    // Overlong lines are silently truncated; classification will reject them.
    return Event::None;
}

void LineAccumulator::clear()
{
    len_ = 0;
    buf_[0] = '\0';
}

// ---------------------------------------------------------------------------
// Classification
// ---------------------------------------------------------------------------
namespace {

bool startsWith(const char* s, const char* prefix)
{
    return std::strncmp(s, prefix, std::strlen(prefix)) == 0;
}

bool contains(const char* s, const char* needle)
{
    return std::strstr(s, needle) != nullptr;
}

} // namespace

LineClass classifyLine(const char* line)
{
    if (line == nullptr || line[0] == '\0') {
        return LineClass::Unknown;
    }
    if (std::strcmp(line, "OK") == 0) return LineClass::Ok;
    if (startsWith(line, "NO DATA") || startsWith(line, "NODATA")) return LineClass::NoData;
    if (startsWith(line, "STOPPED")) return LineClass::Stopped;
    if (startsWith(line, "SEARCHING")) return LineClass::Searching;
    if (startsWith(line, "CAN ERROR") || startsWith(line, "CANERROR")) return LineClass::CanError;
    if (startsWith(line, "BUFFER FULL") || startsWith(line, "BUFFERFULL")) return LineClass::BufferFull;
    if (startsWith(line, "UNABLE TO CONNECT") || startsWith(line, "UNABLETOCONNECT")) {
        return LineClass::UnableToConnect;
    }
    if (std::strcmp(line, "?") == 0 || contains(line, "ERROR")) return LineClass::Error;
    // Unsolicited STN11xx (OBDLink) chatter — power management, voltage events.
    if (startsWith(line, "ACT ALERT") || startsWith(line, "LV RESET") ||
        startsWith(line, "LP ALERT") || startsWith(line, "SLEEPING") ||
        startsWith(line, "WAKE")) {
        return LineClass::Ignorable;
    }

    // Hex data line? Allow spaces (in case ATS0 is not active) between digits.
    size_t hexChars = 0;
    for (const char* p = line; *p != '\0'; ++p) {
        if (*p == ' ') continue;
        if (hexNibble(*p) == 0xFF) return LineClass::Unknown;
        ++hexChars;
    }
    return hexChars >= 2 ? LineClass::HexData : LineClass::Unknown;
}

// ---------------------------------------------------------------------------
// Hex utilities
// ---------------------------------------------------------------------------
void stripSpacesInPlace(char* s)
{
    char* w = s;
    for (const char* r = s; *r != '\0'; ++r) {
        if (*r != ' ') {
            *w++ = *r;
        }
    }
    *w = '\0';
}

uint8_t hexNibble(char c)
{
    if (c >= '0' && c <= '9') return static_cast<uint8_t>(c - '0');
    if (c >= 'A' && c <= 'F') return static_cast<uint8_t>(c - 'A' + 10);
    if (c >= 'a' && c <= 'f') return static_cast<uint8_t>(c - 'a' + 10);
    return 0xFF;
}

bool isHexString(const char* s, size_t len)
{
    for (size_t i = 0; i < len; ++i) {
        if (hexNibble(s[i]) == 0xFF) {
            return false;
        }
    }
    return true;
}

size_t hexToBytes(const char* s, uint8_t* out, size_t maxOut)
{
    const size_t len = std::strlen(s);
    if (len == 0 || (len % 2) != 0) {
        return 0;
    }
    const size_t n = len / 2;
    if (n > maxOut) {
        return 0;
    }
    for (size_t i = 0; i < n; ++i) {
        const uint8_t hi = hexNibble(s[2 * i]);
        const uint8_t lo = hexNibble(s[2 * i + 1]);
        if (hi == 0xFF || lo == 0xFF) {
            return 0;
        }
        out[i] = static_cast<uint8_t>((hi << 4) | lo);
    }
    return n;
}

// ---------------------------------------------------------------------------
// Data-line framing
// ---------------------------------------------------------------------------
bool parseDataLine(const char* line, Frame& out)
{
    out = Frame{};
    const size_t len = std::strlen(line);
    if (len < 2) {
        return false;
    }

    const char* dataStart = line;
    if ((len % 2) != 0) {
        // Odd length: 3-hex-char 11-bit CAN ID prefix (ATH1).
        if (len < 5 || !isHexString(line, 3)) {
            return false;
        }
        out.canId = static_cast<uint32_t>(hexNibble(line[0])) << 8 |
                    static_cast<uint32_t>(hexNibble(line[1])) << 4 |
                    static_cast<uint32_t>(hexNibble(line[2]));
        out.hasHeader = true;
        dataStart = line + 3;
    }

    const size_t n = hexToBytes(dataStart, out.data, sizeof(out.data));
    if (n == 0) {
        return false;
    }
    out.len = static_cast<uint8_t>(n);
    return true;
}

// ---------------------------------------------------------------------------
// ISO-TP reassembly
// ---------------------------------------------------------------------------
void IsoTpReassembler::reset()
{
    len_ = 0;
    expected_ = 0;
    srcId_ = 0;
    nextSeq_ = 0;
    inFlight_ = false;
}

bool IsoTpReassembler::feed(const Frame& f)
{
    if (f.len == 0) {
        return false;
    }

    if (!f.hasHeader) {
        // ATH0-style line: adapter already stripped header and PCI —
        // treat the whole line as a complete payload.
        len_ = f.len < sizeof(buf_) ? f.len : sizeof(buf_);
        std::memcpy(buf_, f.data, len_);
        srcId_ = 0;
        inFlight_ = false;
        return true;
    }

    const uint8_t pciType = f.data[0] >> 4;
    switch (pciType) {
    case 0x0: { // single frame: low nibble = payload length (1..7)
        const uint8_t dl = f.data[0] & 0x0F;
        if (dl == 0 || dl > 7 || dl > f.len - 1) {
            return false;
        }
        len_ = dl;
        std::memcpy(buf_, &f.data[1], dl);
        srcId_ = f.canId;
        inFlight_ = false;
        return true;
    }
    case 0x1: { // first frame: 12-bit total length, 6 payload bytes here
        const size_t total = (static_cast<size_t>(f.data[0] & 0x0F) << 8) | f.data[1];
        if (total < 8 || total > sizeof(buf_) || f.len < 8) {
            return false; // total <= 7 must use a single frame
        }
        expected_ = total;
        len_ = 6;
        std::memcpy(buf_, &f.data[2], 6);
        srcId_ = f.canId;
        nextSeq_ = 1;
        inFlight_ = true;
        return false;
    }
    case 0x2: { // consecutive frame
        if (!inFlight_ || f.canId != srcId_) {
            return false; // frame from another ECU — ignore
        }
        if ((f.data[0] & 0x0F) != (nextSeq_ & 0x0F)) {
            // Sequence error: abandon this reassembly.
            inFlight_ = false;
            len_ = 0;
            return false;
        }
        ++nextSeq_;
        const size_t remaining = expected_ - len_;
        size_t chunk = static_cast<size_t>(f.len) - 1;
        if (chunk > remaining) {
            chunk = remaining;
        }
        std::memcpy(&buf_[len_], &f.data[1], chunk);
        len_ += chunk;
        if (len_ >= expected_) {
            inFlight_ = false;
            return true;
        }
        return false;
    }
    default:
        // Flow-control (0x3) is adapter-internal; anything else is noise.
        return false;
    }
}

} // namespace obd
