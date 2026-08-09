#include "ConsoleCommands.h"

#include <cstdarg>
#include <cstdio>
#include <cstring>

#include "ConsoleParser.h"

namespace console {

using namespace obd;

namespace {

/// Names for PidKey, in enum order. Kept adjacent to the enum in PidDefs.h —
/// the static_assert below fails loudly if the two drift apart.
const char* const kPidKeyNames[] = {
    "RpmSae", "SpeedSae", "EctSae", "BaroSae", "LoadSae",
    "Eot", "FicmMainPower", "Icp", "IprDuty", "VgtDuty", "Map", "Ebp",
    "TransTemp1", "TransTemp2", "TransTemp3", "Gear1", "Gear2", "BatteryVoltage",
};
static_assert(sizeof(kPidKeyNames) / sizeof(kPidKeyNames[0]) ==
                  static_cast<size_t>(PidKey::Count),
              "kPidKeyNames is out of sync with PidKey");

struct ModuleName {
    const char* name;
    ObdModule module;
};

const ModuleName kModuleNames[] = {
    {"auto", ObdModule::Auto},   {"pcm", ObdModule::Pcm},
    {"tcm", ObdModule::Tcm},     {"abs", ObdModule::Abs},
    {"726", ObdModule::Hdr726},  {"c410f1", ObdModule::HdrC410F1},
};

/// Services that change vehicle state rather than read it.
const uint8_t kDestructiveServices[] = {0x04, 0x14, 0x2E, 0x2F, 0x31, 0x3B};

bool isHexPair(const char* s)
{
    auto isHex = [](char c) {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    };
    return s[0] != '\0' && s[1] != '\0' && isHex(s[0]) && isHex(s[1]);
}

uint8_t hexPair(const char* s)
{
    auto nib = [](char c) -> uint8_t {
        if (c >= '0' && c <= '9') return static_cast<uint8_t>(c - '0');
        if (c >= 'a' && c <= 'f') return static_cast<uint8_t>(c - 'a' + 10);
        return static_cast<uint8_t>(c - 'A' + 10);
    };
    return static_cast<uint8_t>((nib(s[0]) << 4) | nib(s[1]));
}

bool fail(char* err, size_t cap, const char* fmt, ...)
{
    if (err != nullptr && cap > 0) {
        va_list ap;
        va_start(ap, fmt);
        vsnprintf(err, cap, fmt, ap);
        va_end(ap);
    }
    return false;
}

const char* const kHelp[] = {
    "commands:",
    "  pids                 list the PID table (index, key, request, state)",
    "  on  <idx|key>        start polling a PID",
    "  off <idx|key>        stop polling a PID",
    "  probe <idx|key> [n]  request it n times; show responder, value, latency",
    "  snap                 every channel: value, age, error count",
    "  stats [reset]        per-PID counters, latency, adapter overhead",
    "  raw <text>           send a verbatim line to the adapter",
    "  hdr <module> <tx> [rx]   runtime ATSH/ATCRA candidate for a module",
    "  hdr clear            drop all runtime addressing overrides",
    "  log raw on|off       mirror raw OBD traffic",
    "  log level <0-5>      0=off 1=err 2=warn 3=info 4=debug 5=trace",
    "  unsafe on|off        allow raw write/clear/control services",
    "  help",
    nullptr,
};

} // namespace

const char* pidKeyName(PidKey key)
{
    const size_t i = static_cast<size_t>(key);
    return i < static_cast<size_t>(PidKey::Count) ? kPidKeyNames[i] : "?";
}

const char* const* helpLines() { return kHelp; }

bool isDestructiveRawCommand(const char* text)
{
    if (text == nullptr) {
        return false;
    }
    while (*text == ' ' || *text == '\t') {
        ++text;
    }
    // AT/ST commands configure the adapter, not the vehicle.
    if (equalsIgnoreCase(text, "") ||
        ((text[0] == 'A' || text[0] == 'a') && (text[1] == 'T' || text[1] == 't')) ||
        ((text[0] == 'S' || text[0] == 's') && (text[1] == 'T' || text[1] == 't'))) {
        return false;
    }
    if (!isHexPair(text)) {
        return false; // not a recognizable OBD request; the adapter will reject it
    }
    const uint8_t service = hexPair(text);
    for (const uint8_t s : kDestructiveServices) {
        if (service == s) {
            return true;
        }
    }
    return false;
}

const PidDefinition* resolvePid(const char* token)
{
    if (token == nullptr || *token == '\0') {
        return nullptr;
    }

    // Table index first — `pids` prints indices, so that is what gets typed.
    uint32_t index = 0;
    if (parseUInt(token, index) && index < kPidTableSize) {
        return &kPidTable[index];
    }

    for (size_t i = 0; i < kPidTableSize; ++i) {
        if (equalsIgnoreCase(token, pidKeyName(kPidTable[i].key)) ||
            equalsIgnoreCase(token, kPidTable[i].shortName)) {
            return &kPidTable[i];
        }
    }
    return nullptr;
}

bool resolveModule(const char* token, ObdModule& out)
{
    for (const ModuleName& m : kModuleNames) {
        if (equalsIgnoreCase(token, m.name)) {
            out = m.module;
            return true;
        }
    }
    return false;
}

bool parse(size_t argc, const char* const* argv, bool unsafeAllowed,
           ParsedCommand& out, char* err, size_t errCap)
{
    out = ParsedCommand{};
    if (argc == 0) {
        return fail(err, errCap, "empty command");
    }
    const char* cmd = argv[0];

    if (equalsIgnoreCase(cmd, "help") || equalsIgnoreCase(cmd, "?")) {
        out.kind = ParsedCommand::Kind::Help;
        return true;
    }
    if (equalsIgnoreCase(cmd, "pids")) {
        out.kind = ParsedCommand::Kind::Pids;
        return true;
    }
    if (equalsIgnoreCase(cmd, "snap")) {
        out.kind = ParsedCommand::Kind::Snap;
        return true;
    }
    if (equalsIgnoreCase(cmd, "stats")) {
        if (argc >= 2 && equalsIgnoreCase(argv[1], "reset")) {
            out.kind = ParsedCommand::Kind::ResetStats;
        } else {
            out.kind = ParsedCommand::Kind::Stats;
        }
        return true;
    }

    if (equalsIgnoreCase(cmd, "on") || equalsIgnoreCase(cmd, "off")) {
        if (argc < 2) {
            return fail(err, errCap, "%s needs a PID (index, key or short name)", cmd);
        }
        const PidDefinition* def = resolvePid(argv[1]);
        if (def == nullptr) {
            return fail(err, errCap, "unknown PID '%s' — try `pids`", argv[1]);
        }
        out.kind = equalsIgnoreCase(cmd, "on") ? ParsedCommand::Kind::On
                                               : ParsedCommand::Kind::Off;
        out.key = def->key;
        return true;
    }

    if (equalsIgnoreCase(cmd, "probe")) {
        if (argc < 2) {
            return fail(err, errCap, "probe needs a PID (index, key or short name)");
        }
        const PidDefinition* def = resolvePid(argv[1]);
        if (def == nullptr) {
            return fail(err, errCap, "unknown PID '%s' — try `pids`", argv[1]);
        }
        uint32_t repeat = 1;
        if (argc >= 3 && (!parseUInt(argv[2], repeat) || repeat == 0 || repeat > 50)) {
            return fail(err, errCap, "probe count must be 1..50");
        }
        out.kind = ParsedCommand::Kind::Probe;
        out.key = def->key;
        out.repeat = static_cast<uint8_t>(repeat);
        return true;
    }

    if (equalsIgnoreCase(cmd, "raw")) {
        if (argc < 2) {
            return fail(err, errCap, "raw needs something to send");
        }
        // Rejoin the arguments so `raw 22 1310` and `raw 221310` both work;
        // the adapter ignores spaces in a request.
        char joined[kMaxRawCommand + 1] = {0};
        size_t o = 0;
        for (size_t i = 1; i < argc; ++i) {
            const size_t n = std::strlen(argv[i]);
            if (o + n >= sizeof(joined)) {
                return fail(err, errCap, "raw command longer than %u characters",
                            static_cast<unsigned>(kMaxRawCommand));
            }
            std::memcpy(joined + o, argv[i], n);
            o += n;
        }
        joined[o] = '\0';
        if (o == 0) {
            return fail(err, errCap, "raw needs something to send");
        }
        if (!unsafeAllowed && isDestructiveRawCommand(joined)) {
            return fail(err, errCap,
                        "refused: service %.2s writes/clears/actuates. This is a "
                        "live truck — type `unsafe on` first if you mean it.",
                        joined);
        }
        out.kind = ParsedCommand::Kind::Raw;
        std::memcpy(out.text, joined, o + 1);
        return true;
    }

    if (equalsIgnoreCase(cmd, "hdr")) {
        if (argc >= 2 && equalsIgnoreCase(argv[1], "clear")) {
            out.kind = ParsedCommand::Kind::Header;
            out.header[0] = '\0'; // empty tx header == clear all overrides
            return true;
        }
        if (argc < 3) {
            return fail(err, errCap,
                        "usage: hdr <auto|pcm|tcm|abs|726|c410f1> <txHeader> [rxFilter]"
                        " | hdr clear");
        }
        if (!resolveModule(argv[1], out.module)) {
            return fail(err, errCap, "unknown module '%s'", argv[1]);
        }
        if (std::strlen(argv[2]) >= sizeof(out.header)) {
            return fail(err, errCap, "header too long");
        }
        std::strcpy(out.header, argv[2]);
        if (argc >= 4) {
            if (std::strlen(argv[3]) >= sizeof(out.filter)) {
                return fail(err, errCap, "filter too long");
            }
            std::strcpy(out.filter, argv[3]);
        }
        out.kind = ParsedCommand::Kind::Header;
        return true;
    }

    if (equalsIgnoreCase(cmd, "log")) {
        if (argc < 3) {
            return fail(err, errCap, "usage: log raw on|off | log level <0-5>");
        }
        if (equalsIgnoreCase(argv[1], "raw")) {
            if (!parseBool(argv[2], out.flag)) {
                return fail(err, errCap, "expected on or off, got '%s'", argv[2]);
            }
            out.kind = ParsedCommand::Kind::LogRaw;
            return true;
        }
        if (equalsIgnoreCase(argv[1], "level")) {
            uint32_t level = 0;
            if (!parseUInt(argv[2], level) || level > 5) {
                return fail(err, errCap, "log level must be 0..5");
            }
            out.kind = ParsedCommand::Kind::LogLevel;
            out.level = static_cast<uint8_t>(level);
            return true;
        }
        return fail(err, errCap, "usage: log raw on|off | log level <0-5>");
    }

    if (equalsIgnoreCase(cmd, "unsafe")) {
        if (argc < 2 || !parseBool(argv[1], out.flag)) {
            return fail(err, errCap, "usage: unsafe on|off");
        }
        out.kind = ParsedCommand::Kind::Unsafe;
        return true;
    }

    return fail(err, errCap, "unknown command '%s' — try `help`", cmd);
}

} // namespace console
