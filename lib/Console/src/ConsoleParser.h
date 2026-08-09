#pragma once
//
// Serial line accumulation and argv tokenization.
//
// The console shares its UART with the raw OBD log, so it has to cope with a
// human typing into a stream that is also scrolling: backspace, CR, LF, CRLF,
// and lines longer than the buffer all have to do something sensible rather
// than corrupt the next command.
//
// Pure logic — no Arduino, no allocation, fixed buffers.

#include <cstddef>
#include <cstdint>

namespace console {

/// Longest accepted command line. Raw OBD commands are short; this is roomy.
inline constexpr size_t kMaxLine = 96;

/// help/pids/on/off/raw/probe/... — no command needs more than this.
inline constexpr size_t kMaxArgs = 6;

class LineReader {
public:
    enum class Event : uint8_t {
        None,      ///< byte consumed, nothing complete yet
        Line,      ///< a complete non-empty line is available via line()
        Empty,     ///< the user pressed enter on a blank line
        Overflow,  ///< the line exceeded kMaxLine and was discarded
    };

    /// Feed one received byte.
    Event feed(char c);

    /// The completed line — valid until the next feed(). Mutable because the
    /// tokenizer writes NULs into it in place.
    char* line() { return buf_; }
    size_t length() const { return len_; }

    void clear();

private:
    char buf_[kMaxLine + 1] = {0};
    size_t len_ = 0;
    bool overflowed_ = false;
};

/// Split `line` into arguments in place (NUL-terminating each). Runs of spaces
/// and tabs are one separator; leading/trailing whitespace is ignored.
/// Returns the argument count, capped at kMaxArgs — a line with more arguments
/// than that is reported via `truncated` rather than silently losing them.
size_t tokenize(char* line, const char** argv, size_t maxArgs, bool* truncated = nullptr);

/// Case-insensitive comparison (commands and PID names are typed by hand).
bool equalsIgnoreCase(const char* a, const char* b);

/// Parse a decimal or 0x-prefixed hex integer. Returns false on any trailing
/// garbage, so "5x" is rejected rather than read as 5.
bool parseUInt(const char* s, uint32_t& out);

/// Parse on/off/true/false/1/0.
bool parseBool(const char* s, bool& out);

} // namespace console
