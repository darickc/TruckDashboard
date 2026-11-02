#pragma once
//
// ELM327/STN response parsing primitives.
//
// The adapter is configured with ATE0 (no echo), ATL0 (no linefeeds),
// ATS0 (no spaces), ATH1 (headers ON). With those settings a CAN data line
// on an 11-bit-ID protocol looks like:
//
//     7E804410C1AF8
//     ^^^           3 hex chars: CAN ID (0x7E8 = PCM physical response)
//        ^^         ISO-TP PCI byte (0x04 = single frame, 4 data bytes)
//          ^^^^^^^^ data: 41 0C 1A F8 (positive response to 01 0C)
//
// Multi-byte responses (> 7 data bytes) arrive as ISO 15765-2 (ISO-TP)
// first frame (PCI 0x1L LL) + consecutive frames (PCI 0x2N), possibly
// interleaved from multiple ECUs — the reassembler groups frames by CAN ID.
//
// Everything here is pure logic: no Arduino, no allocation, fixed buffers.

#include <cstddef>
#include <cstdint>

namespace obd {

// ---------------------------------------------------------------------------
// Line accumulation. ELM output is '\r'-delimited (ATL0 disables '\n'); the
// '>' prompt arrives WITHOUT a terminator, so it is reported as its own event.
// ---------------------------------------------------------------------------
class LineAccumulator {
public:
    enum class Event : uint8_t {
        None,   ///< byte consumed, nothing complete yet
        Line,   ///< a complete non-empty line is available via line()
        Prompt, ///< the '>' prompt was seen (any partial line is discarded)
    };

    Event feed(char c);
    const char* line() const { return buf_; }
    size_t length() const { return len_; }
    void clear();

private:
    char buf_[96] = {0};
    size_t len_ = 0;
};

// ---------------------------------------------------------------------------
// Line classification.
// ---------------------------------------------------------------------------
enum class LineClass : uint8_t {
    HexData,         ///< looks like a hex data line (possibly with CAN ID)
    Ok,              ///< "OK"
    NoData,          ///< "NO DATA" — request sent, no ECU answered
    Stopped,         ///< "STOPPED" — adapter aborted (char arrived mid-request)
    Searching,       ///< "SEARCHING..." — protocol auto-detect in progress
    CanError,        ///< "CAN ERROR"
    BufferFull,      ///< "BUFFER FULL"
    UnableToConnect, ///< "UNABLE TO CONNECT"
    Error,           ///< "?" or "...ERROR" variants
    Ignorable,       ///< unsolicited STN chatter: ACT ALERT, LV RESET, etc.
    Unknown,         ///< anything else (banners, unrecognized text)
};

LineClass classifyLine(const char* line);

// ---------------------------------------------------------------------------
// Hex utilities.
// ---------------------------------------------------------------------------

/// In-place removal of spaces (defensive: we set ATS0, but don't rely on it).
void stripSpacesInPlace(char* s);

/// 0-15 for a hex digit, 0xFF otherwise.
uint8_t hexNibble(char c);

/// True if s[0..len) is entirely hex digits.
bool isHexString(const char* s, size_t len);

/// Decode pairs of hex chars into bytes. Returns bytes written, or 0 on
/// odd length / invalid characters / overflow of maxOut.
size_t hexToBytes(const char* s, uint8_t* out, size_t maxOut);

// ---------------------------------------------------------------------------
// Data-line framing.
// ---------------------------------------------------------------------------
struct Frame {
    uint32_t canId = 0;    ///< 0 when the line had no header
    bool hasHeader = false;
    uint8_t data[16] = {0};
    uint8_t len = 0;
};

/// Parse a space-stripped hex data line into a frame.
/// Odd-length lines are treated as 3-hex-char 11-bit CAN ID + data (ATH1 on
/// an 11-bit CAN protocol). Even-length lines are treated as raw payload
/// with no header (ATH0 style). Returns false on malformed input.
/// NOTE: 29-bit-header parsing is not implemented — this truck's HS-CAN
/// diagnostic responses use 11-bit IDs (7E8..7EF).
bool parseDataLine(const char* line, Frame& out);

// ---------------------------------------------------------------------------
// ISO-TP reassembly.
//
// Single frames complete immediately. One multi-frame message may be in
// flight at a time, keyed by source CAN ID; frames from other IDs while a
// reassembly is in flight are ignored (functional queries can make several
// ECUs answer — the client keeps the first *matching* completed payload).
// Headerless frames are treated as already-complete payloads.
// ---------------------------------------------------------------------------
class IsoTpReassembler {
public:
    void reset();

    /// Feed one frame. Returns true when a complete payload is available.
    bool feed(const Frame& f);

    const uint8_t* payload() const { return buf_; }
    size_t payloadLen() const { return len_; }
    uint32_t sourceId() const { return srcId_; }

private:
    uint8_t buf_[64] = {0};
    size_t len_ = 0;
    size_t expected_ = 0;
    uint32_t srcId_ = 0;
    uint8_t nextSeq_ = 0;
    bool inFlight_ = false;
};

} // namespace obd
