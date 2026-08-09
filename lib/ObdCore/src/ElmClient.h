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
    Ok,      ///< positive response; payload delivered (echo already stripped)
    NoData,  ///< adapter reported NO DATA (no ECU answered)
    Timeout, ///< no prompt within the deadline
    Stopped, ///< adapter aborted the request (STOPPED)
    Error,   ///< '?', CAN ERROR, negative response (7F ...), etc.
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
    uint8_t maxConsecutiveTimeouts = 3;  ///< then escalate to full ATZ re-init
    uint8_t maxResetAttempts = 2;        ///< then go Offline (owner re-does Bluetooth)
};

class ElmClient {
public:
    /// Payload starts AFTER the positive-response echo (41 xx / 62 xx xx);
    /// payload/len are only meaningful for ElmResult::Ok.
    using ResultHandler = void (*)(void* ctx, const PidDefinition& pid,
                                   ElmResult result,
                                   const uint8_t* payload, size_t len);

    ElmClient(IObdTransport& transport, TimeFn now, const ElmConfig& cfg);

    /// Start (or restart) adapter reset + init. Call once the transport is up.
    void begin();

    /// Owner detected transport loss — abandon everything, go Offline.
    void onTransportLost();

    /// Pump received bytes and deadlines. Call frequently; never blocks.
    void tick();

    /// Submit a PID request. Only valid in Idle. Returns acceptance.
    bool submit(const PidDefinition& pid);

    void setResultHandler(ResultHandler handler, void* ctx);

    /// Mirror every raw TX/RX line at INFO level (for on-truck PID
    /// verification). Otherwise raw traffic logs at TRACE.
    void setRawLogging(bool on) { rawLog_ = on; }

    ElmState state() const { return state_.load(std::memory_order_relaxed); }
    bool isReady() const;
    const char* adapterId() const { return adapterId_; }

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
    void finishRequest(ElmResult result);
    void escalateOrReset();

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

    // request in flight
    const PidDefinition* currentPid_ = nullptr;
    bool awaitingHeaderAck_ = false;
    char pendingHeader_[12] = {0};
    char currentHeader_[12] = {0};
    uint8_t respBuf_[64] = {0};
    size_t respLen_ = 0;
    bool haveResponse_ = false;
    bool sawNoData_ = false;
    bool sawStopped_ = false;
    bool sawError_ = false;
    bool firstDataDone_ = false;

    uint8_t consecutiveTimeouts_ = 0;
    char lastSent_[24] = {0};
    char adapterId_[32] = {0};
    bool rawLog_ = false;

    ResultHandler handler_ = nullptr;
    void* handlerCtx_ = nullptr;
};

} // namespace obd
