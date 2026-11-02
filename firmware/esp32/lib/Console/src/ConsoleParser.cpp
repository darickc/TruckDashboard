#include "ConsoleParser.h"

#include <cstring>

namespace console {

LineReader::Event LineReader::feed(char c)
{
    if (c == '\r' || c == '\n') {
        // CRLF must not produce a phantom second line, so an empty buffer on a
        // terminator is only "Empty" when nothing was overflowed either.
        const bool wasOverflow = overflowed_;
        const size_t n = len_;
        buf_[len_ < sizeof(buf_) ? len_ : sizeof(buf_) - 1] = '\0';
        len_ = 0;
        overflowed_ = false;
        if (wasOverflow) {
            return Event::Overflow;
        }
        return n > 0 ? Event::Line : Event::Empty;
    }

    if (c == '\b' || c == 0x7F) { // backspace / delete
        if (len_ > 0) {
            --len_;
        }
        return Event::None;
    }

    if (c == '\0') {
        return Event::None;
    }

    if (len_ >= kMaxLine) {
        // Keep swallowing until the terminator so the tail of an overlong line
        // cannot be interpreted as the next command.
        overflowed_ = true;
        return Event::None;
    }

    buf_[len_++] = c;
    return Event::None;
}

void LineReader::clear()
{
    len_ = 0;
    overflowed_ = false;
    buf_[0] = '\0';
}

size_t tokenize(char* line, const char** argv, size_t maxArgs, bool* truncated)
{
    if (truncated != nullptr) {
        *truncated = false;
    }
    if (line == nullptr || argv == nullptr || maxArgs == 0) {
        return 0;
    }

    size_t argc = 0;
    char* p = line;
    for (;;) {
        while (*p == ' ' || *p == '\t') {
            ++p;
        }
        if (*p == '\0') {
            break;
        }
        if (argc >= maxArgs) {
            if (truncated != nullptr) {
                *truncated = true;
            }
            break;
        }
        argv[argc++] = p;
        while (*p != '\0' && *p != ' ' && *p != '\t') {
            ++p;
        }
        if (*p == '\0') {
            break;
        }
        *p++ = '\0';
    }
    return argc;
}

bool equalsIgnoreCase(const char* a, const char* b)
{
    if (a == nullptr || b == nullptr) {
        return false;
    }
    for (; *a != '\0' && *b != '\0'; ++a, ++b) {
        char ca = *a;
        char cb = *b;
        if (ca >= 'A' && ca <= 'Z') ca = static_cast<char>(ca - 'A' + 'a');
        if (cb >= 'A' && cb <= 'Z') cb = static_cast<char>(cb - 'A' + 'a');
        if (ca != cb) {
            return false;
        }
    }
    return *a == '\0' && *b == '\0';
}

bool parseUInt(const char* s, uint32_t& out)
{
    if (s == nullptr || *s == '\0') {
        return false;
    }
    uint32_t base = 10;
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
        base = 16;
        s += 2;
        if (*s == '\0') {
            return false;
        }
    }
    uint32_t value = 0;
    for (; *s != '\0'; ++s) {
        uint32_t digit;
        if (*s >= '0' && *s <= '9') {
            digit = static_cast<uint32_t>(*s - '0');
        } else if (base == 16 && *s >= 'a' && *s <= 'f') {
            digit = static_cast<uint32_t>(*s - 'a' + 10);
        } else if (base == 16 && *s >= 'A' && *s <= 'F') {
            digit = static_cast<uint32_t>(*s - 'A' + 10);
        } else {
            return false; // trailing garbage: reject rather than half-parse
        }
        if (value > (0xFFFFFFFFu - digit) / base) {
            return false; // overflow
        }
        value = value * base + digit;
    }
    out = value;
    return true;
}

bool parseBool(const char* s, bool& out)
{
    if (equalsIgnoreCase(s, "on") || equalsIgnoreCase(s, "true") ||
        equalsIgnoreCase(s, "1") || equalsIgnoreCase(s, "yes")) {
        out = true;
        return true;
    }
    if (equalsIgnoreCase(s, "off") || equalsIgnoreCase(s, "false") ||
        equalsIgnoreCase(s, "0") || equalsIgnoreCase(s, "no")) {
        out = false;
        return true;
    }
    return false;
}

} // namespace console
