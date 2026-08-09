#include "ElmClient.h"

#include <cstdio>
#include <cstring>

#include "Log.h"

namespace obd {

static const char* kTag = "elm";

const char* elmStateName(ElmState s)
{
    switch (s) {
    case ElmState::Offline: return "OFFLINE";
    case ElmState::Resetting: return "RESETTING";
    case ElmState::Initializing: return "INITIALIZING";
    case ElmState::Idle: return "IDLE";
    case ElmState::AwaitingResponse: return "AWAITING";
    case ElmState::Recovering: return "RECOVERING";
    }
    return "?";
}

const char* elmResultName(ElmResult r)
{
    switch (r) {
    case ElmResult::Ok: return "OK";
    case ElmResult::NoData: return "NO_DATA";
    case ElmResult::NoResponder: return "NO_RESPONDER";
    case ElmResult::Timeout: return "TIMEOUT";
    case ElmResult::Stopped: return "STOPPED";
    case ElmResult::Error: return "ERROR";
    }
    return "?";
}

namespace {

/// Hex-dump into a caller-supplied buffer (no allocation). Truncates silently
/// — this only ever feeds log lines.
void hexDump(const uint8_t* data, size_t len, char* out, size_t cap)
{
    size_t o = 0;
    for (size_t i = 0; i < len && o + 3 < cap; ++i) {
        o += static_cast<size_t>(std::snprintf(out + o, cap - o, "%02X", data[i]));
    }
    out[o < cap ? o : cap - 1] = '\0';
}

} // namespace

ElmClient::ElmClient(IObdTransport& transport, TimeFn now, const ElmConfig& cfg)
    : transport_(transport), now_(now), cfg_(cfg)
{
}

void ElmClient::setResultHandler(ResultHandler handler, void* ctx)
{
    handler_ = handler;
    handlerCtx_ = ctx;
}

void ElmClient::setRawLineHandler(RawLineHandler handler, void* ctx)
{
    rawHandler_ = handler;
    rawHandlerCtx_ = ctx;
}

bool ElmClient::submitRaw(const char* cmd)
{
    if (state() != ElmState::Idle || cmd == nullptr || cmd[0] == '\0') {
        return false;
    }
    currentPid_ = nullptr;
    prepCount_ = 0;
    prepIndex_ = 0;
    haveResponse_ = false;
    respLen_ = 0;
    sawNoData_ = false;
    sawStopped_ = false;
    sawError_ = false;
    assembler_.reset();
    rawMode_ = true;
    setState(ElmState::AwaitingResponse);
    sendLine(cmd);
    deadlineMs_ = now_() + cfg_.rawTimeoutMs;
    return true;
}

bool ElmClient::isReady() const
{
    const ElmState s = state();
    return s == ElmState::Idle || s == ElmState::AwaitingResponse;
}

void ElmClient::setState(ElmState s)
{
    const ElmState old = state();
    if (old != s) {
        LOGD(kTag, "state %s -> %s", elmStateName(old), elmStateName(s));
        state_.store(s, std::memory_order_relaxed);
    }
}

void ElmClient::begin()
{
    acc_.clear();
    assembler_.reset();
    currentPid_ = nullptr;
    prepCount_ = 0;
    prepIndex_ = 0;
    consecutiveTimeouts_ = 0;
    resetAttempts_ = 0;
    firstDataDone_ = false;
    adapterId_[0] = '\0';
    startReset();
}

void ElmClient::resetAddressingCacheToDefaults()
{
    // ATZ restores the adapter's default CAN functional header (7DF) and drops
    // any receive filter. This MUST run on every reset path — the recovery
    // ladder reaches startReset() without going through begin(), and a stale
    // cache there would make submit() skip the ATSH and quietly send the next
    // request on whatever header the adapter actually has.
    std::snprintf(currentHeader_, sizeof(currentHeader_), "7DF");
    currentFilter_[0] = '\0';
}

void ElmClient::markAddressingUnknown()
{
    // After a raw command we know only that the adapter's addressing MAY have
    // changed — `raw ATSH 7E0` leaves it on 7E0, not on the ATZ default. Saying
    // "it is 7DF" here would be a guess, and a wrong one; the honest state is
    // "unknown", encoded as a sentinel no real header or filter can equal, so
    // the next request re-establishes both explicitly. Costs one ATSH and one
    // ATCRA, once.
    std::snprintf(currentHeader_, sizeof(currentHeader_), "?");
    std::snprintf(currentFilter_, sizeof(currentFilter_), "?");
}

void ElmClient::onTransportLost()
{
    if (currentPid_ != nullptr || rawMode_) {
        finishRequest(ElmResult::Timeout);
    }
    acc_.clear();
    setState(ElmState::Offline);
    LOGW(kTag, "transport lost");
}

void ElmClient::startReset()
{
    resetAddressingCacheToDefaults();
    prepCount_ = 0;
    prepIndex_ = 0;
    setState(ElmState::Resetting);
    sendLine("ATZ");
    deadlineMs_ = now_() + cfg_.resetTimeoutMs;
}

void ElmClient::sendLine(const char* cmd)
{
    char buf[32];
    const int n = std::snprintf(buf, sizeof(buf), "%s\r", cmd);
    if (n <= 0 || static_cast<size_t>(n) >= sizeof(buf)) {
        LOGE(kTag, "command too long: %s", cmd);
        return;
    }
    transport_.write(reinterpret_cast<const uint8_t*>(buf), static_cast<size_t>(n));
    std::snprintf(lastSent_, sizeof(lastSent_), "%s", cmd);
    if (rawLog_) {
        LOGI(kTag, "TX> %s", cmd);
    } else {
        LOGT(kTag, "TX> %s", cmd);
    }
}

void ElmClient::tick()
{
    if (state() == ElmState::Offline) {
        return;
    }

    // Drain received bytes (bounded per tick to stay cooperative).
    for (int i = 0; i < 256; ++i) {
        const int c = transport_.read();
        if (c < 0) {
            break;
        }
        const LineAccumulator::Event ev = acc_.feed(static_cast<char>(c));
        if (ev == LineAccumulator::Event::Line) {
            if (rawLog_) {
                LOGI(kTag, "RX< %s", acc_.line());
            } else {
                LOGT(kTag, "RX< %s", acc_.line());
            }
            handleLine(acc_.line());
        } else if (ev == LineAccumulator::Event::Prompt) {
            LOGT(kTag, "RX< >");
            handlePrompt();
        }
    }

    if (state() != ElmState::Offline && timeReached(now_(), deadlineMs_)) {
        handleTimeout();
    }
}

void ElmClient::handleLine(const char* line)
{
    // Echo suppression: before ATE0 takes effect the adapter repeats every
    // command back. A line identical to what we last sent is never data.
    if (lastSent_[0] != '\0' && std::strcmp(line, lastSent_) == 0) {
        return;
    }

    // Raw passthrough: the operator asked for exactly what the adapter said,
    // so no classification, no echo validation, no interpretation.
    if (rawMode_ && state() == ElmState::AwaitingResponse) {
        if (rawHandler_ != nullptr) {
            rawHandler_(rawHandlerCtx_, line);
        }
        return;
    }

    const LineClass cls = classifyLine(line);

    switch (state()) {
    case ElmState::Resetting:
        // First meaningful line after ATZ is the ident banner ("ELM327 v1.4b").
        if (cls == LineClass::Unknown && adapterId_[0] == '\0') {
            std::snprintf(adapterId_, sizeof(adapterId_), "%s", line);
        }
        break;

    case ElmState::Initializing:
        if (cls == LineClass::Error) {
            LOGW(kTag, "init command '%s' rejected: %s", lastSent_, line);
            initCmdFailed_ = true;
        }
        break;

    case ElmState::AwaitingResponse:
        switch (cls) {
        case LineClass::HexData:
            handleDataLine(line);
            break;
        case LineClass::NoData:
            sawNoData_ = true;
            break;
        case LineClass::Stopped:
            sawStopped_ = true;
            break;
        case LineClass::Searching:
            // Protocol auto-detect in progress — give it the long deadline.
            deadlineMs_ = now_() + cfg_.firstDataTimeoutMs;
            LOGD(kTag, "adapter searching for protocol...");
            break;
        case LineClass::Ok:
            // Expected while a header change (ATSH) is being acknowledged.
            break;
        case LineClass::CanError:
        case LineClass::BufferFull:
        case LineClass::UnableToConnect:
        case LineClass::Error:
            LOGW(kTag, "adapter error during request: %s", line);
            sawError_ = true;
            break;
        case LineClass::Ignorable:
            LOGD(kTag, "unsolicited: %s", line);
            break;
        case LineClass::Unknown:
            LOGD(kTag, "unrecognized line: %s", line);
            break;
        }
        break;

    case ElmState::Idle:
    case ElmState::Recovering:
        if (cls == LineClass::Ignorable || cls == LineClass::Unknown) {
            LOGD(kTag, "unsolicited: %s", line);
        }
        break;

    case ElmState::Offline:
        break;
    }
}

void ElmClient::handleDataLine(const char* line)
{
    char tmp[96];
    std::snprintf(tmp, sizeof(tmp), "%s", line);
    stripSpacesInPlace(tmp);

    Frame f;
    if (!parseDataLine(tmp, f)) {
        LOGD(kTag, "malformed data line: %s", line);
        return;
    }

    const PidDefinition* pid = currentPid_;
    if (pid == nullptr) {
        return;
    }

    // Drop frames from other ECUs BEFORE reassembly. The reassembler has a
    // single in-flight slot, so two ECUs answering a pinned PID with
    // interleaved multi-frame messages would otherwise lose one of them.
    if (pid->expectedResponder != 0 && f.hasHeader &&
        f.canId != pid->expectedResponder) {
        ++wrongResponderCount_;
        if (rawLog_) {
            LOGI(kTag, "RSP %s <- %03X : IGNORED (pinned to %03X)", pid->name,
                 static_cast<unsigned>(f.canId),
                 static_cast<unsigned>(pid->expectedResponder));
        }
        return;
    }

    if (!assembler_.feed(f)) {
        return; // multi-frame in progress, or frame ignored
    }

    const uint8_t* p = assembler_.payload();
    const size_t n = assembler_.payloadLen();
    if (n == 0) {
        return;
    }

    // Negative response: 7F <service> <NRC>.
    if (p[0] == 0x7F) {
        LOGW(kTag, "negative response to %02X %04X (NRC %02X)",
             pid->service, pid->pid, n >= 3 ? p[2] : 0);
        sawError_ = true;
        return;
    }

    // Validate the positive-response echo, then strip it.
    const size_t echo = responseEchoLen(pid->service);
    if (n <= echo || p[0] != pid->service + 0x40) {
        LOGD(kTag, "response echo mismatch (got %02X)", p[0]);
        return;
    }
    const bool pidMatches =
        (pid->service == 0x22)
            ? (p[1] == ((pid->pid >> 8) & 0xFF) && p[2] == (pid->pid & 0xFF))
            : (p[1] == (pid->pid & 0xFF));
    if (!pidMatches) {
        LOGD(kTag, "response PID mismatch");
        return;
    }

    const uint8_t* body = p + echo;
    size_t bodyLen = n - echo;
    if (bodyLen > sizeof(respBuf_)) {
        bodyLen = sizeof(respBuf_);
    }
    const uint16_t srcId = static_cast<uint16_t>(assembler_.sourceId());
    ++responderCount_;

    // Log every matching answer with its source. This is the line that turns a
    // verification session into evidence: two ECUs answering 221674 show up
    // side by side instead of one silently winning the race.
    if (rawLog_) {
        char hex[2 * sizeof(respBuf_) + 1];
        hexDump(body, bodyLen, hex, sizeof(hex));
        LOGI(kTag, "RSP %s <- %03X : %s", pid->name, static_cast<unsigned>(srcId), hex);
    }

    if (!haveResponse_) { // keep the FIRST matching ECU's answer
        respLen_ = bodyLen;
        std::memcpy(respBuf_, body, respLen_);
        responderId_ = srcId;
        haveResponse_ = true;
        return;
    }

    // A second ECU answered. Same bytes is corroboration; different bytes means
    // the two modules disagree about what this PID means, and whichever won the
    // race would have been reported as fact.
    if (bodyLen != respLen_ || std::memcmp(body, respBuf_, bodyLen) != 0) {
        responderConflict_ = true;
        char mine[2 * sizeof(respBuf_) + 1];
        char theirs[2 * sizeof(respBuf_) + 1];
        hexDump(respBuf_, respLen_, mine, sizeof(mine));
        hexDump(body, bodyLen, theirs, sizeof(theirs));
        LOGW(kTag, "%s: RESPONDER CONFLICT %03X=%s vs %03X=%s — pin "
                   "expectedResponder once the truck says which module owns it",
             pid->name, static_cast<unsigned>(responderId_), mine,
             static_cast<unsigned>(srcId), theirs);
    } else {
        LOGD(kTag, "%s: %03X agrees with %03X", pid->name,
             static_cast<unsigned>(srcId), static_cast<unsigned>(responderId_));
    }
}

void ElmClient::handlePrompt()
{
    switch (state()) {
    case ElmState::Resetting:
        LOGI(kTag, "adapter reset complete (%s)",
             adapterId_[0] != '\0' ? adapterId_ : "no ident");
        initIndex_ = 0;
        initRetries_ = 0;
        initCmdFailed_ = false;
        if (cfg_.initCommandCount == 0) {
            resetAttempts_ = 0;
            setState(ElmState::Idle);
            LOGI(kTag, "OBDLink connected");
        } else {
            setState(ElmState::Initializing);
            sendInitCommand();
        }
        break;

    case ElmState::Initializing:
        if (initCmdFailed_ && initRetries_ < 1) {
            ++initRetries_;
            initCmdFailed_ = false;
            sendInitCommand(); // retry the same command once
            break;
        }
        if (initCmdFailed_) {
            // Command keeps failing — continue, but loudly. Some settings may
            // simply be unsupported; the request path will surface real damage.
            LOGE(kTag, "init command '%s' failed twice — continuing",
                 cfg_.initCommands[initIndex_]);
        }
        ++initIndex_;
        initRetries_ = 0;
        initCmdFailed_ = false;
        if (initIndex_ >= cfg_.initCommandCount) {
            resetAttempts_ = 0;
            setState(ElmState::Idle);
            LOGI(kTag, "OBDLink connected"); // milestone-1 marker
        } else {
            sendInitCommand();
        }
        break;

    case ElmState::AwaitingResponse:
        if (rawMode_) {
            finishRequest(ElmResult::Ok); // no PID: just returns to Idle
            break;
        }
        if (prepIndex_ < prepCount_) {
            if (sawError_) {
                LOGW(kTag, "addressing command '%s' rejected", prepCmds_[prepIndex_]);
                finishRequest(ElmResult::Error);
                break;
            }
            // Command accepted — commit its effect to the cache.
            const char* acked = prepCmds_[prepIndex_];
            if (std::strncmp(acked, "ATSH", 4) == 0) {
                std::snprintf(currentHeader_, sizeof(currentHeader_), "%s", acked + 4);
            } else if (std::strncmp(acked, "ATCRA", 5) == 0) {
                std::snprintf(currentFilter_, sizeof(currentFilter_), "%s", acked + 5);
            }
            ++prepIndex_;
            if (prepIndex_ < prepCount_) {
                sendNextPrepCommand();
            } else {
                prepOverheadMs_ += now_() - prepStartMs_;
                sendPidRequest();
            }
            break;
        }
        if (haveResponse_) {
            finishRequest(ElmResult::Ok);
        } else if (sawStopped_) {
            finishRequest(ElmResult::Stopped);
        } else if (wrongResponderCount_ > 0) {
            // Somebody answered, just not the module this PID is pinned to.
            finishRequest(ElmResult::NoResponder);
        } else if (sawNoData_) {
            finishRequest(ElmResult::NoData);
        } else if (sawError_) {
            finishRequest(ElmResult::Error);
        } else {
            LOGD(kTag, "prompt with empty response");
            finishRequest(ElmResult::Error);
        }
        break;

    case ElmState::Recovering:
        LOGI(kTag, "recovered — adapter prompt OK");
        setState(ElmState::Idle);
        break;

    case ElmState::Idle:
    case ElmState::Offline:
        break;
    }
}

void ElmClient::sendInitCommand()
{
    const char* cmd = cfg_.initCommands[initIndex_];
    sendLine(cmd);
    deadlineMs_ = now_() + cfg_.initTimeoutMs;
}

bool ElmClient::submit(const PidDefinition& pid)
{
    if (state() != ElmState::Idle) {
        return false;
    }
    const ObdAddressing addr = moduleAddressing(pid.module);
    if (addr.txHeader == nullptr) {
        // Unverified module addressing — refuse rather than guess.
        LOGW(kTag, "%s: module '%s' header unverified — request refused",
             pid.name, moduleName(pid.module));
        return false;
    }

    currentPid_ = &pid;
    haveResponse_ = false;
    respLen_ = 0;
    responderId_ = 0;
    responderCount_ = 0;
    wrongResponderCount_ = 0;
    responderConflict_ = false;
    sawNoData_ = false;
    sawStopped_ = false;
    sawError_ = false;
    assembler_.reset();
    setState(ElmState::AwaitingResponse);

    // Queue whatever addressing commands the adapter still needs. Order
    // matters: ATSH first, because on 11-bit CAN it also sets the expected
    // receive address, and any ATCRA must override that rather than be
    // overridden by it.
    prepCount_ = 0;
    prepIndex_ = 0;
    if (std::strcmp(addr.txHeader, currentHeader_) != 0) {
        std::snprintf(prepCmds_[prepCount_++], sizeof(prepCmds_[0]), "ATSH%s",
                      addr.txHeader);
    }
    const char* wantFilter = addr.rxFilter != nullptr ? addr.rxFilter : "";
    if (std::strcmp(wantFilter, currentFilter_) != 0) {
        // Bare "ATCRA" clears the filter.
        std::snprintf(prepCmds_[prepCount_++], sizeof(prepCmds_[0]), "ATCRA%s",
                      wantFilter);
    }

    if (prepCount_ > 0) {
        prepStartMs_ = now_();
        sendNextPrepCommand();
    } else {
        sendPidRequest();
    }
    return true;
}

void ElmClient::sendNextPrepCommand()
{
    sendLine(prepCmds_[prepIndex_]);
    ++prepCommandCount_;
    deadlineMs_ = now_() + cfg_.initTimeoutMs;
}

void ElmClient::sendPidRequest()
{
    const PidDefinition& pid = *currentPid_;
    char cmd[16];
    int n;
    if (pid.service == 0x22) {
        n = std::snprintf(cmd, sizeof(cmd), "22%04X", pid.pid);
    } else {
        n = std::snprintf(cmd, sizeof(cmd), "%02X%02X", pid.service, pid.pid & 0xFF);
    }
    // Optional ELM response-count digit: the adapter returns as soon as N
    // replies arrive instead of waiting out its P2 timeout. Never valid on a
    // functional header — see PidDefinition::expectedResponses.
    if (pid.expectedResponses != 0 && n > 0 &&
        static_cast<size_t>(n) + 1 < sizeof(cmd)) {
        cmd[n] = static_cast<char>('0' + (pid.expectedResponses % 10));
        cmd[n + 1] = '\0';
    }
    sendLine(cmd);
    requestSentMs_ = now_();
    // The very first data request can trigger protocol SEARCHING — give it
    // the long deadline; afterwards use the per-PID timeout.
    deadlineMs_ = now_() + (firstDataDone_ ? pid.timeoutMs : cfg_.firstDataTimeoutMs);
}

void ElmClient::finishRequest(ElmResult result)
{
    const PidDefinition* pid = currentPid_;
    currentPid_ = nullptr;
    prepCount_ = 0;
    prepIndex_ = 0;
    if (rawMode_) {
        // A raw command may have been ATZ/ATSH/ATCRA/ATSP. Assume it changed the
        // adapter's addressing and make the next request re-establish it.
        rawMode_ = false;
        markAddressingUnknown();
    }
    if (state() == ElmState::AwaitingResponse) {
        setState(ElmState::Idle);
        deadlineMs_ = now_() + cfg_.recoveryTimeoutMs; // benign idle deadline
    }
    if (result == ElmResult::Ok) {
        consecutiveTimeouts_ = 0;
        firstDataDone_ = true;
    }
    if (pid == nullptr || handler_ == nullptr) {
        return;
    }

    ElmResponse rsp;
    rsp.result = result;
    rsp.responderCount = responderCount_;
    rsp.responderConflict = responderConflict_;
    if (result == ElmResult::Ok) {
        rsp.payload = respBuf_;
        rsp.len = respLen_;
        rsp.responderId = responderId_;
    }
    // requestSentMs_ is 0 until the request line actually went out (a prep
    // command can fail before that), in which case there is no latency to report.
    if (requestSentMs_ != 0) {
        const uint32_t elapsed = now_() - requestSentMs_;
        rsp.latencyMs = elapsed > 0xFFFFu ? 0xFFFFu : static_cast<uint16_t>(elapsed);
    }
    requestSentMs_ = 0;
    handler_(handlerCtx_, *pid, rsp);
}

void ElmClient::handleTimeout()
{
    switch (state()) {
    case ElmState::Resetting:
        LOGW(kTag, "no response to ATZ");
        escalateOrReset();
        break;

    case ElmState::Initializing:
        LOGW(kTag, "init command '%s' timed out", lastSent_);
        escalateOrReset();
        break;

    case ElmState::AwaitingResponse: {
        LOGW(kTag, "request '%s' timed out", lastSent_);
        ++consecutiveTimeouts_;
        finishRequest(ElmResult::Timeout);
        if (consecutiveTimeouts_ >= cfg_.maxConsecutiveTimeouts) {
            // Repeated timeouts on a previously healthy link usually mean the
            // STN went to sleep or the bus dropped — full re-init.
            LOGW(kTag, "%u consecutive timeouts — full adapter reset",
                 consecutiveTimeouts_);
            consecutiveTimeouts_ = 0;
            escalateOrReset();
        } else {
            // Provoke a fresh prompt so we know the adapter is listening.
            setState(ElmState::Recovering);
            sendLine("");
            deadlineMs_ = now_() + cfg_.recoveryTimeoutMs;
        }
        break;
    }

    case ElmState::Recovering:
        LOGW(kTag, "no prompt during recovery");
        escalateOrReset();
        break;

    case ElmState::Idle:
        // Idle deadline is benign — refresh it.
        deadlineMs_ = now_() + cfg_.recoveryTimeoutMs;
        break;

    case ElmState::Offline:
        break;
    }
}

void ElmClient::escalateOrReset()
{
    if (resetAttempts_ < cfg_.maxResetAttempts) {
        ++resetAttempts_;
        LOGW(kTag, "adapter reset attempt %u/%u", resetAttempts_, cfg_.maxResetAttempts);
        startReset();
    } else {
        LOGE(kTag, "adapter unresponsive — going offline (owner will reconnect)");
        setState(ElmState::Offline);
    }
}

} // namespace obd
