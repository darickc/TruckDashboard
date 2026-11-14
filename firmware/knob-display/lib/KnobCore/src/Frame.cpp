#include "Frame.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace knob {

namespace {

const char* const kNames[kSlots] = {"spd", "fuel", "eot", "ect", "dlt"};

const char* const kTurns[] = {
    "other", "start", "dest", "straight", "slight-right", "right", "sharp-right", "uturn-right",
    "uturn-left", "sharp-left", "left", "slight-left", "ramp-right", "ramp-left", "fork-right",
    "fork-left", "merge", "roundabout", "ferry",
};
constexpr size_t kTurnCount = sizeof(kTurns) / sizeof(kTurns[0]);

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

// Copies `t` into `out` (size `n`, always terminated), cut at a UTF-8
// character boundary when it doesn't fit; control characters become spaces.
void copyText(std::string_view t, char* out, size_t n)
{
    size_t len = t.size() < n - 1 ? t.size() : n - 1;
    // Don't end inside a multi-byte character.
    while (len > 0 && len < t.size() && (static_cast<uint8_t>(t[len]) & 0xC0) == 0x80) --len;
    for (size_t i = 0; i < len; ++i) {
        const char c = t[i];
        out[i] = (static_cast<uint8_t>(c) < 0x20 || c == 0x7F) ? ' ' : c;
    }
    out[len] = '\0';
}

// A short field ("0.4", "mi"): non-empty, fits, printable ASCII.
bool copyField(std::string_view t, char* out, size_t n)
{
    if (t.empty() || t.size() >= n) return false;
    for (char c : t) {
        if (c <= ' ' || c > '~') return false;
    }
    std::memcpy(out, t.data(), t.size());
    out[t.size()] = '\0';
    return true;
}

// "-" (unknown, -1) or a whole number.
bool optionalInt(std::string_view t, int32_t& out)
{
    if (t == "-") {
        out = -1;
        return true;
    }
    uint32_t v;
    if (!toU32(t, v) || v > 0x7FFFFFFF) return false;
    out = static_cast<int32_t>(v);
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

bool parseNav(std::string_view rest, NavFrame& out)
{
    NavFrame f;
    std::string_view st = next(rest, ' ');
    if (st == "none" || st == "route" || st == "wait") {
        if (!rest.empty()) return false;
        f.state = st == "none" ? NavState::None : (st == "route" ? NavState::Routing : NavState::Waiting);
    } else if (st == "arr") {
        f.state = NavState::Arrived;
        copyText(rest, f.text, sizeof(f.text));
    } else if (st == "go") {
        f.state = NavState::Active;
        std::string_view turn = next(rest, ' ');
        size_t i = 0;
        while (i < kTurnCount && turn != kTurns[i]) ++i;
        if (i == kTurnCount) return false;
        f.turn = static_cast<Turn>(i);
        if (!copyField(next(rest, ' '), f.dist, sizeof(f.dist))) return false;
        if (!copyField(next(rest, ' '), f.distUnit, sizeof(f.distUnit))) return false;
        if (!copyField(next(rest, ' '), f.left, sizeof(f.left))) return false;
        if (!copyField(next(rest, ' '), f.leftUnit, sizeof(f.leftUnit))) return false;
        uint32_t m;
        if (!toU32(next(rest, ' '), m) || m > 0xFFFF) return false;
        f.minutes = static_cast<uint16_t>(m);
        copyText(rest, f.text, sizeof(f.text));
    } else {
        return false;
    }
    out = f;
    return true;
}

// "12/30", "m12/30" (muted) or "-".
bool parseVolume(std::string_view t, MediaFrame& f)
{
    if (t == "-") return true;
    if (!t.empty() && t[0] == 'm') {
        f.muted = true;
        t.remove_prefix(1);
    }
    uint32_t level, steps;
    if (!toU32(next(t, '/'), level) || !toU32(t, steps)) return false;
    if (steps == 0 || steps > 1000 || level > steps) return false;
    f.volume = static_cast<int16_t>(level);
    f.volumeSteps = static_cast<int16_t>(steps);
    return true;
}

bool parseMedia(std::string_view rest, MediaFrame& out)
{
    MediaFrame f;
    std::string_view st = next(rest, ' ');
    if (st == "none") {
        f.state = PlayState::None;
        if (!parseVolume(next(rest, ' '), f) || !rest.empty()) return false;
        out = f;
        return true;
    }
    if (st == "play") {
        f.state = PlayState::Playing;
    } else if (st == "pause") {
        f.state = PlayState::Paused;
    } else if (st == "stop") {
        f.state = PlayState::Stopped;
    } else {
        return false;
    }
    if (!parseVolume(next(rest, ' '), f)) return false;
    if (!optionalInt(next(rest, ' '), f.posS) || !optionalInt(next(rest, ' '), f.durS)) return false;
    copyText(next(rest, '\t'), f.title, sizeof(f.title));
    copyText(next(rest, '\t'), f.artist, sizeof(f.artist));
    copyText(rest, f.source, sizeof(f.source));
    out = f;
    return true;
}

bool parseCall(std::string_view rest, CallFrame& out)
{
    CallFrame f;
    std::string_view st = next(rest, ' ');
    if (st == "none") {
        if (!rest.empty()) return false;
        out = f;
        return true;
    }
    if (st == "ring") {
        f.state = CallState::Ringing;
    } else if (st == "wait") {
        f.state = CallState::Waiting;
    } else if (st == "dial") {
        f.state = CallState::Dialing;
    } else if (st == "call") {
        f.state = CallState::Active;
    } else if (st == "hold") {
        f.state = CallState::Held;
    } else {
        return false;
    }
    if (!toU32(next(rest, ' '), f.activeS)) return false;
    std::string_view caller = next(rest, '\t');
    if (caller.empty()) return false;
    copyText(caller, f.caller, sizeof(f.caller));
    copyText(rest, f.number, sizeof(f.number));
    out = f;
    return true;
}

}  // namespace

const char* turnName(Turn t)
{
    const size_t i = static_cast<size_t>(t);
    return i < kTurnCount ? kTurns[i] : "other";
}

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
    Frames f;
    const Parsed p = parseLine(line, f);
    if (p == Parsed::Config) config = f.config;
    if (p == Parsed::Data) data = f.data;
    return p;
}

Parsed parseLine(std::string_view line, Frames& out)
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
    if (kind == "C1") return parseConfig(body, out.config) ? Parsed::Config : Parsed::Malformed;
    if (kind == "D1") return parseData(body, out.data) ? Parsed::Data : Parsed::Malformed;
    if (kind == "N1") return parseNav(body, out.nav) ? Parsed::Nav : Parsed::Malformed;
    if (kind == "M1") return parseMedia(body, out.media) ? Parsed::Media : Parsed::Malformed;
    if (kind == "P1") return parseCall(body, out.call) ? Parsed::Call : Parsed::Malformed;
    if (kind == "H1") return Parsed::Hello;
    return Parsed::Unknown;
}

}  // namespace knob
