// The knob display's line protocol (ADR-0044 decision 3). Plain C++ with no
// Arduino: parsed here and host-tested; services/knob-link writes the same
// lines.
//
//   C1 <slot>:<unit>:<min>:<max>:<trust> ...*CS          what each slot shows
//   D1 <seq> <live|sim> <slot>:<state>[:<value>[:<age_s>]] ...*CS
//   N1 go <turn> <dist> <dunit> <left> <lunit> <min> [<street>]*CS
//   N1 <none|route|wait>*CS | N1 arr [<destination>]*CS   the next turn
//   M1 <play|pause|stop> <vol> <pos_s|-> <dur_s|-> <title>\t<artist>\t<source>*CS
//   M1 none <vol>*CS                                      what's playing
//   P1 <ring|wait|dial|call|hold> <active_s> <caller>\t<number>*CS
//   P1 none*CS                                            a phone call
//   A1 begin|data|none ...*CS                             the cover (Art.h)
//   H1 <name> <version>*CS                               from the dial
//
// <vol> is <level>/<steps>, m<level>/<steps> when muted, or "-".
// CS is the XOR of every character before '*', as two hex digits (NMEA).

#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

#include "Art.h"

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

// The navigation page (ADR-0044 amendment, swipe pages).
enum class NavState : uint8_t {
    None,     // no destination, or routing isn't available
    Routing,  // asking for a route
    Waiting,  // a route, but no current position: no distance is shown
    Active,   // following the route
    Arrived,
};

// The next maneuver's arrow, from Valhalla's type (knob-link maps it).
enum class Turn : uint8_t {
    Other, Start, Destination, Straight, SlightRight, Right, SharpRight, UTurnRight,
    UTurnLeft, SharpLeft, Left, SlightLeft, RampRight, RampLeft, ForkRight, ForkLeft,
    Merge, Roundabout, Ferry,
};
const char* turnName(Turn t);

struct NavFrame {
    NavState state = NavState::None;
    Turn turn = Turn::Other;
    // Display-ready text from the Pi: "0.4" "mi", "500" "ft".
    char dist[8] = {};
    char distUnit[4] = {};
    char left[8] = {};
    char leftUnit[4] = {};
    uint16_t minutes = 0;
    // The street of the next turn, or the destination when arrived.
    char text[96] = {};
};

enum class PlayState : uint8_t { None, Playing, Paused, Stopped };

struct MediaFrame {
    PlayState state = PlayState::None;
    // -1: unknown.
    int16_t volume = -1;
    int16_t volumeSteps = -1;
    bool muted = false;
    int32_t posS = -1;
    int32_t durS = -1;
    char title[64] = {};
    char artist[48] = {};
    char source[32] = {};
};

// A phone call on the connected phone (ADR-0045 decision 6): it takes over
// the dial.
enum class CallState : uint8_t {
    None,
    Ringing,  // incoming: push to answer
    Waiting,  // another call during this one: answered on the phone
    Dialing,  // an outgoing call being set up
    Active,
    Held,
};

struct CallFrame {
    CallState state = CallState::None;
    // Seconds since it became active (0 before).
    uint32_t activeS = 0;
    // As the dashboard says it: the name, the number, or why neither.
    char caller[48] = {};
    // The number under a name; empty otherwise.
    char number[28] = {};
};

struct Frames {
    ConfigFrame config;
    DataFrame data;
    NavFrame nav;
    MediaFrame media;
    CallFrame call;
    ArtFrame art;
};

enum class Parsed {
    Config,
    Data,
    Nav,
    Media,
    Call,
    Art,
    Hello,
    Comment,      // "# ..." (the dial's log)
    BadChecksum,  // no '*', or it doesn't match
    Malformed,    // a known kind whose fields don't parse
    Unknown,      // another kind or version
};

uint8_t checksum(std::string_view body);

// `body` followed by "*CS".
std::string withChecksum(std::string_view body);

// One line, without its line ending. Fills only the frame it returns
// (Config, Data, Nav, Media, Call or Art); a Malformed line changes nothing.
Parsed parseLine(std::string_view line, Frames& out);

// The same, for the gauge frames only (Nav, Media, Call and Art lines are parsed
// and dropped).
Parsed parseLine(std::string_view line, ConfigFrame& config, DataFrame& data);

}  // namespace knob
