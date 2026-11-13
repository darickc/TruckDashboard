// The knob display's line protocol (ADR-0044 decision 3). Plain C++ with no
// Arduino: parsed here and host-tested; services/knob-link writes the same
// lines.
//
//   C1 <slot>:<unit>:<min>:<max>:<trust> ...*CS          what each slot shows
//   D1 <seq> <live|sim> <slot>:<state>[:<value>[:<age_s>]] ...*CS
//   H1 <name> <version>*CS                               from the dial
//
// CS is the XOR of every character before '*', as two hex digits (NMEA).

#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

namespace knob {

constexpr size_t kMaxLine = 255;

enum class Slot : uint8_t { Speed, Fuel, Eot, Ect, Delta };
constexpr size_t kSlots = 5;

const char* slotName(Slot s);
bool slotFromName(std::string_view name, Slot& out);

struct SlotConfig {
    bool set = false;
    char unit[8] = {};
    float min = 0;
    float max = 0;
    // Imported and not verified on the truck: the dial marks it.
    bool unverified = false;
};

struct ConfigFrame {
    SlotConfig slots[kSlots];
};

enum class State : uint8_t {
    Current,
    Advisory,  // current, with an advisory alert
    Critical,  // current, with a critical alert
    Stale,     // the last good value, `ageS` old
    None,      // nothing to show
};

struct SlotValue {
    bool set = false;
    State state = State::None;
    float value = 0;
    float ageS = 0;
};

struct DataFrame {
    uint32_t seq = 0;
    bool simulated = false;
    SlotValue slots[kSlots];
};

enum class Parsed {
    Config,
    Data,
    Hello,
    Comment,      // "# ..." (the dial's log)
    BadChecksum,  // no '*', or it doesn't match
    Malformed,    // a known kind whose fields don't parse
    Unknown,      // another kind or version
};

uint8_t checksum(std::string_view body);

// `body` followed by "*CS".
std::string withChecksum(std::string_view body);

// One line, without its line ending. Fills `config` or `data` only when it
// returns Config or Data; a Malformed line changes neither.
Parsed parseLine(std::string_view line, ConfigFrame& config, DataFrame& data);

}  // namespace knob
