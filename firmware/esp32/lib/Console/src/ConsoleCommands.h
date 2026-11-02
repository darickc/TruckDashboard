#pragma once
//
// The console command grammar: argv in, a validated ParsedCommand out.
//
// Parsing is deliberately separated from execution. Execution needs the
// ElmClient and the PidScheduler, which are private to the OBD task; parsing
// needs nothing, so it is pure, host-testable, and the place where the safety
// rules live.

#include <cstddef>
#include <cstdint>

#include "PidDefs.h"

namespace console {

/// Longest raw command accepted by `raw`. ELM commands are short; ISO-TP
/// requests top out well inside this.
inline constexpr size_t kMaxRawCommand = 24;

struct ParsedCommand {
    enum class Kind : uint8_t {
        Help,
        Pids,      ///< list the PID table with enabled/verified state
        On,        ///< start polling one PID
        Off,       ///< stop polling one PID
        Probe,     ///< request one PID n times and report responders + latency
        Raw,       ///< send a verbatim line to the adapter
        Snap,      ///< dump every channel with age
        Stats,     ///< per-PID counters and latency
        ResetStats,
        Header,    ///< runtime module-addressing override (ATSH/ATCRA candidate)
        LogRaw,    ///< mirror raw OBD traffic
        LogLevel,
        Display,   ///< pause/resume the text display (it shares this UART)
        Unsafe,    ///< lift the `raw` deny-list for this session
    };

    Kind kind = Kind::Help;
    obd::PidKey key = obd::PidKey::Count;
    obd::ObdModule module = obd::ObdModule::Auto;
    uint8_t repeat = 1;
    uint8_t level = 0;
    bool flag = false;
    char text[kMaxRawCommand + 1] = {0}; ///< Raw payload
    char header[12] = {0};               ///< Header: ATSH argument
    char filter[12] = {0};               ///< Header: ATCRA argument ("" = none)
};

/// True for OBD services that write, clear or actuate rather than read.
/// These are refused by `raw` unless the operator has typed `unsafe on`:
///   04 clear DTCs        14 clear diagnostic information
///   2E write data by ID  2F input/output control by ID
///   31 routine control   3B write data by PID
/// This is a live truck, and a typo is cheap to make and expensive to undo.
bool isDestructiveRawCommand(const char* text);

/// Resolve a PID by table index, PidKey name, or short name — all
/// case-insensitive, so `on 7`, `on Icp` and `on hpop` are the same thing.
const obd::PidDefinition* resolvePid(const char* token);

/// Human-readable key name for a PID ("Icp", "RpmSae", ...).
const char* pidKeyName(obd::PidKey key);

/// Resolve a module by name ("pcm", "tcm", "abs", "auto", "726", "c410f1").
bool resolveModule(const char* token, obd::ObdModule& out);

/// Parse one tokenized command line.
///
/// `unsafeAllowed` reflects whether `unsafe on` has been typed this session.
/// On failure, writes a one-line explanation into `err` and returns false —
/// every rejection path must say why, because the operator is in a truck cab
/// reading a scrolling log.
bool parse(size_t argc, const char* const* argv, bool unsafeAllowed,
           ParsedCommand& out, char* err, size_t errCap);

/// The `help` text, as a NULL-terminated array of lines.
const char* const* helpLines();

} // namespace console
