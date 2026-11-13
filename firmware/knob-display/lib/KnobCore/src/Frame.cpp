#include "Frame.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace knob {

namespace {

const char* const kNames[kSlots] = {"spd", "fuel", "eot", "ect", "dlt"};

// Splits `s` at the first `sep`: `head` before it, `s` after it (empty when
// there is none).
std::string_view next(std::string_view& s, char sep)
{
    size_t at = s.find(sep);
    std::string_view head = s.substr(0, at);
    s = at == std::string_view::npos ? std::string_view() : s.substr(at + 1);
    return head;
}

bool toFloat(std::string_view t, float& out)
{
    if (t.empty() || t.size() > 23) return false;
    char buf[24];
    std::memcpy(buf, t.data(), t.size());
    buf[t.size()] = '\0';
    char* end = nullptr;
    float v = std::strtof(buf, &end);
    if (end != buf + t.size() || !std::isfinite(v)) return false;
    out = v;
    return true;
}

bool toU32(std::string_view t, uint32_t& out)
{
    if (t.empty() || t.size() > 10) return false;
    uint64_t v = 0;
    for (char c : t) {
        if (c < '0' || c > '9') return false;
        v = v * 10 + static_cast<uint64_t>(c - '0');
    }
    if (v > 0xFFFFFFFFull) return false;
    out = static_cast<uint32_t>(v);
    return true;
}

int hexDigit(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}

bool parseConfig(std::string_view rest, ConfigFrame& out)
{
    ConfigFrame f;
    while (!rest.empty()) {
        std::string_view tok = next(rest, ' ');
        if (tok.empty()) continue;
        Slot slot;
        std::string_view name = next(tok, ':');
        if (!slotFromName(name, slot)) continue;  // a slot from a later dial: skipped
        std::string_view unit = next(tok, ':');
        std::string_view mn = next(tok, ':');
        std::string_view mx = next(tok, ':');
        std::string_view trust = tok;
        SlotConfig c;
        if (unit.empty() || unit.size() >= sizeof(c.unit)) return false;
        if (!toFloat(mn, c.min) || !toFloat(mx, c.max) || !(c.max > c.min)) return false;
        if (trust == "v") {
            c.unverified = false;
        } else if (trust == "u") {
            c.unverified = true;
        } else {
            return false;
        }
        std::memcpy(c.unit, unit.data(), unit.size());
        c.set = true;
        f.slots[static_cast<size_t>(slot)] = c;
    }
    out = f;
    return true;
}

bool parseData(std::string_view rest, DataFrame& out)
{
    DataFrame f;
    if (!toU32(next(rest, ' '), f.seq)) return false;
    std::string_view mode = next(rest, ' ');
    if (mode == "live") {
        f.simulated = false;
    } else if (mode == "sim") {
        f.simulated = true;
    } else {
        return false;
    }
    while (!rest.empty()) {
        std::string_view tok = next(rest, ' ');
        if (tok.empty()) continue;
        Slot slot;
        if (!slotFromName(next(tok, ':'), slot)) continue;
        std::string_view st = next(tok, ':');
        SlotValue v;
        if (st.size() != 1) return false;
        switch (st[0]) {
            case 'c': v.state = State::Current; break;
            case 'a': v.state = State::Advisory; break;
            case 'k': v.state = State::Critical; break;
            case 's': v.state = State::Stale; break;
            case 'n': v.state = State::None; break;
            default: return false;
        }
        if (v.state == State::None) {
            if (!tok.empty()) return false;
        } else {
            if (!toFloat(next(tok, ':'), v.value)) return false;
            if (v.state == State::Stale) {
                if (!toFloat(tok, v.ageS) || v.ageS < 0) return false;
            } else if (!tok.empty()) {
                return false;
            }
        }
        v.set = true;
        f.slots[static_cast<size_t>(slot)] = v;
    }
    out = f;
    return true;
}

}  // namespace

const char* slotName(Slot s) { return kNames[static_cast<size_t>(s)]; }

bool slotFromName(std::string_view name, Slot& out)
{
    for (size_t i = 0; i < kSlots; ++i) {
        if (name == kNames[i]) {
            out = static_cast<Slot>(i);
            return true;
        }
    }
    return false;
}

uint8_t checksum(std::string_view body)
{
    uint8_t x = 0;
    for (char c : body) x ^= static_cast<uint8_t>(c);
    return x;
}

std::string withChecksum(std::string_view body)
{
    char cs[4];
    std::snprintf(cs, sizeof(cs), "*%02X", checksum(body));
    std::string s(body);
    s += cs;
    return s;
}

Parsed parseLine(std::string_view line, ConfigFrame& config, DataFrame& data)
{
    while (!line.empty() && (line.back() == '\r' || line.back() == '\n')) line.remove_suffix(1);
    if (!line.empty() && line[0] == '#') return Parsed::Comment;
    if (line.size() > kMaxLine || line.size() < 3) return Parsed::BadChecksum;
    size_t star = line.size() - 3;
    if (line[star] != '*') return Parsed::BadChecksum;
    int hi = hexDigit(line[star + 1]), lo = hexDigit(line[star + 2]);
    std::string_view body = line.substr(0, star);
    if (hi < 0 || lo < 0 || checksum(body) != static_cast<uint8_t>(hi * 16 + lo)) {
        return Parsed::BadChecksum;
    }
    std::string_view kind = next(body, ' ');
    if (kind == "C1") return parseConfig(body, config) ? Parsed::Config : Parsed::Malformed;
    if (kind == "D1") return parseData(body, data) ? Parsed::Data : Parsed::Malformed;
    if (kind == "H1") return Parsed::Hello;
    return Parsed::Unknown;
}

}  // namespace knob
