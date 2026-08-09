#pragma once
//
// Non-blocking ELM327/STN (OBDLink MX+) command client.
//
// Owns the request/response lifecycle over an IObdTransport:
//   * reset + configurable AT init sequence (ATZ, ATE0, ATL0, ATS0, ATH1, ...)
//   * one command in flight at a time, completed by the '>' prompt
//   * per-request timeouts, NO DATA / STOPPED / '?' / negative-response
//     handling, echo suppression, ISO-TP reassembly
//   * recovery ladder: provoke prompt with CR -> full ATZ re-init -> give up
//     (Offline) so the owning task can drop and re-establish Bluetooth
//
// tick() never blocks. All raw AT/OBD traffic stays inside this class —
// nothing else in the project writes to the adapter.

#include <atomic>
#include <cstddef>
#include <cstdint>

#include "ElmParser.h"
#include "IObdTransport.h"
#include "PidDefs.h"
#include "TimeSource.h"

namespace obd {

enum class ElmState : uint8_t {
    Offline,          ///< not started / unrecoverable — owner must (re)connect + begin()
    Resetting,        ///< ATZ sent, waiting for prompt (adapter may be waking up)
    Initializing,     ///< stepping through the init command list
    Idle,             ///< prompt seen, no command in flight — submit() allowed
    AwaitingResponse, ///< request in flight, accumulating response lines
    Recovering,       ///< provoking a fresh prompt after a fault
};

enum class ElmResult : uint8_t {
    Ok,          ///< positive response; payload delivered (echo already stripped)
    NoData,      ///< adapter reported NO DATA (no ECU answered)
    NoResponder, ///< an ECU answered, but not the one this PID is pinned to —
                 ///< distinct from NoData so a bad expectedResponder is
                 ///< diagnosable instead of looking like a dead PID
    Timeout,     ///< no prompt within the deadline
    Stopped,     ///< adapter aborted the request (STOPPED)
    Error,       ///< '?', CAN ERROR, negative response (7F ...), etc.
};

const char* elmStateName(ElmState s);
const char* elmResultName(ElmResult r);

struct ElmConfig {
    const char* const* initCommands = nullptr;
    size_t initCommandCount = 0;
    uint32_t resetTimeoutMs = 6000;      ///< ATZ can be slow while the STN wakes
    uint32_t initTimeoutMs = 2000;       ///< per init command
    uint32_t firstDataTimeoutMs = 10000; ///< first request triggers protocol SEARCHING
    uint32_t recoveryTimeoutMs = 2000;
    uint32_t rawTimeoutMs = 3000;        ///< console `raw` (ATZ needs headroom)
    uint8_t maxConsecutiveTimeouts = 3;  ///< then escalate to full ATZ re-init
    uint8_t maxResetAttempts = 2;        ///< then go Offline (owner re-does Bluetooth)
};

/// How many responders' answers are kept verbatim. Three is plenty: this truck
/// produces two, and the count is reported even when it exceeds this.
inline constexpr size_t kMaxRecordedResponders = 3;

/// What one ECU said, echo already stripped.
struct ResponderAnswer {
    uint16_t canId = 0;
    uint8_t len = 0;
    /// Longer payloads are truncated — this copy exists for display and
    /// comparison, not for decoding. The full first answer is in
    /// ElmResponse::payload.
    uint8_t payload[16] = {0};
};

/// Outcome of one request, including who answered it and what each said.
///
/// A functional (7DF) request is a broadcast: several ECUs may answer the same
/// PID, in varying order. Reporting every answer is what makes an on-truck
/// reading evidence rather than an anecdote.
///
/// Note what is deliberately NOT here: a verdict. Whether two modules "agree"
/// cannot be decided from one sample of a continuously varying signal — on this
/// truck 7E8 and 7E9 both report engine RPM and differ by a count or two on
/// nearly every request, which means they agree, not that they conflict. The
/// judgement belongs to whoever can compare DECODED values across several
/// samples (see PidStats::maxResponderSpread and the console's `probe`).
struct ElmResponse {
    ElmResult result = ElmResult::Error;

    /// Starts AFTER the positive-response echo (41 xx / 62 xx xx).
    /// Only meaningful for ElmResult::Ok.
    const uint8_t* payload = nullptr;
    size_t len = 0;

    uint16_t responderId = 0;   ///< CAN ID that supplied `payload` (0 = headerless)
    uint8_t responderCount = 0; ///< ECUs whose answer matched service+PID
    uint8_t recordedResponders = 0; ///< min(responderCount, kMaxRecordedResponders)
    ResponderAnswer responders[kMaxRecordedResponders]; ///< in arrival order
    bool respondersDiffer = false;  ///< a FACT (bytes differ), not a verdict
    uint16_t latencyMs = 0;         ///< request written -> '>' prompt (saturating)
};

class ElmClient {
public:
    using ResultHandler = void (*)(void* ctx, const PidDefinition& pid,
                                   const ElmResponse& rsp);

    ElmClient(IObdTransport& transport, TimeFn now, const ElmConfig& cfg);

    /// Start (or restart) adapter reset + init. Call once the transport is up.
    void begin();

    /// Owner detected transport loss — abandon everything, go Offline.
    void onTransportLost();

    /// Pump received bytes and deadlines. Call frequently; never blocks.
    void tick();

    /// Submit a PID request. Only valid in Idle. Returns acceptance.
    bool submit(const PidDefinition& pid);

    /// Send a verbatim line to the adapter and hand every reply line to the raw
    /// handler unparsed, until the '>' prompt. Only valid in Idle.
    ///
    /// This is the console's `raw` command: the way to try ATSH/ATCRA/ATDPN
    /// candidates on the truck without a reflash. Because such a command may
    /// have changed the adapter's addressing (ATZ, ATSH, ATCRA, ATSP), the
    /// cached header and filter are invalidated unconditionally afterwards —
    /// one redundant ATSH is far cheaper than a desynced cache quietly
    /// mislabelling the next hour of readings.
    bool submitRaw(const char* cmd);

    /// True while a submitRaw() is still collecting reply lines.
    bool rawInFlight() const { return rawMode_; }

    void setResultHandler(ResultHandler handler, void* ctx);

    using RawLineHandler = void (*)(void* ctx, const char* line);
    void setRawLineHandler(RawLineHandler handler, void* ctx);

    /// Mirror every raw TX/RX line at INFO level (for on-truck PID
    /// verification). Otherwise raw traffic logs at TRACE.
    void setRawLogging(bool on) { rawLog_ = on; }

    ElmState state() const { return state_.load(std::memory_order_relaxed); }
    bool isReady() const;
    const char* adapterId() const { return adapterId_; }

    /// Milliseconds spent on ATSH/ATCRA prep since the last resetStats(), and
    /// how many such commands were sent. Prep is real bus time that no PID's
    /// latencyMs accounts for — it is what decides whether switching a PID to
    /// physical addressing pays for itself.
    uint32_t prepOverheadMs() const { return prepOverheadMs_; }
    uint32_t prepCommandCount() const { return prepCommandCount_; }
    void resetStats() { prepOverheadMs_ = 0; prepCommandCount_ = 0; }

private:
    void setState(ElmState s);
    void sendLine(const char* cmd);
    void handleLine(const char* line);
    void handlePrompt();
    void handleTimeout();
    void handleDataLine(const char* line);
    void startReset();
    void sendInitCommand();
    void sendPidRequest();
    void sendNextPrepCommand();
    void finishRequest(ElmResult result);
    void escalateOrReset();
    void resetAddressingCacheToDefaults();
    void markAddressingUnknown();

    IObdTransport& transport_;
    TimeFn now_;
    ElmConfig cfg_;

    LineAccumulator acc_;
    IsoTpReassembler assembler_;

    std::atomic<ElmState> state_{ElmState::Offline};
    uint32_t deadlineMs_ = 0;

    // init progress
    size_t initIndex_ = 0;
    uint8_t initRetries_ = 0;
    bool initCmdFailed_ = false;
    uint8_t resetAttempts_ = 0;

    // Addressing prep queue: ATSH (and optionally ATCRA) must be acknowledged
    // before the actual request goes out. Two slots is the whole vocabulary.
    char prepCmds_[2][16] = {{0}, {0}};
    uint8_t prepCount_ = 0;
    uint8_t prepIndex_ = 0;
    uint32_t prepStartMs_ = 0;

    // Cached adapter addressing state. Only valid while the adapter has not
    // been reset or driven by a raw command — see resetAddressingCacheToDefaults()
    // (ATZ) and markAddressingUnknown() (raw), one of which must run on every
    // such path or we would silently talk on the wrong header.
    char currentHeader_[12] = {0};
    char currentFilter_[12] = {0};

    // request in flight
    const PidDefinition* currentPid_ = nullptr;
    uint8_t respBuf_[64] = {0};
    size_t respLen_ = 0;
    bool haveResponse_ = false;
    uint16_t responderId_ = 0;
    uint8_t responderCount_ = 0;
    uint8_t recordedResponders_ = 0;
    ResponderAnswer responders_[kMaxRecordedResponders];
    uint8_t wrongResponderCount_ = 0;
    uint32_t requestSentMs_ = 0;
    bool sawNoData_ = false;
    bool sawStopped_ = false;
    bool sawError_ = false;
    bool firstDataDone_ = false;

    uint32_t prepOverheadMs_ = 0;
    uint32_t prepCommandCount_ = 0;

    bool rawMode_ = false;
    RawLineHandler rawHandler_ = nullptr;
    void* rawHandlerCtx_ = nullptr;

    uint8_t consecutiveTimeouts_ = 0;
    char lastSent_[24] = {0};
    char adapterId_[32] = {0};
    bool rawLog_ = false;

    ResultHandler handler_ = nullptr;
    void* handlerCtx_ = nullptr;
};

} // namespace obd
