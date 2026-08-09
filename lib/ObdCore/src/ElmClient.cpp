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
    case ElmResult::Timeout: return "TIMEOUT";
    case ElmResult::Stopped: return "STOPPED";
    case ElmResult::Error: return "ERROR";
    }
    return "?";
}

ElmClient::ElmClient(IObdTransport& transport, TimeFn now, const ElmConfig& cfg)
    : transport_(transport), now_(now), cfg_(cfg)
{
}

void ElmClient::setResultHandler(ResultHandler handler, void* ctx)
{
    handler_ = handler;
    handlerCtx_ = ctx;
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
    awaitingHeaderAck_ = false;
    consecutiveTimeouts_ = 0;
    resetAttempts_ = 0;
    firstDataDone_ = false;
    adapterId_[0] = '\0';
    // ATZ restores the adapter's default CAN functional header (7DF).
    std::snprintf(currentHeader_, sizeof(currentHeader_), "7DF");
    startReset();
}

void ElmClient::onTransportLost()
{
    if (currentPid_ != nullptr) {
        finishRequest(ElmResult::Timeout);
    }
    acc_.clear();
    setState(ElmState::Offline);
    LOGW(kTag, "transport lost");
}

void ElmClient::startReset()
{
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
    if (!assembler_.feed(f)) {
        return; // multi-frame in progress, or frame ignored
    }

    const uint8_t* p = assembler_.payload();
    const size_t n = assembler_.payloadLen();
    const PidDefinition* pid = currentPid_;
    if (pid == nullptr || n == 0) {
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

    if (!haveResponse_) { // keep the FIRST matching ECU's answer
        respLen_ = n - echo;
        if (respLen_ > sizeof(respBuf_)) {
            respLen_ = sizeof(respBuf_);
        }
        std::memcpy(respBuf_, p + echo, respLen_);
        haveResponse_ = true;
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
        if (awaitingHeaderAck_) {
            if (sawError_) {
                finishRequest(ElmResult::Error);
                break;
            }
            std::snprintf(currentHeader_, sizeof(currentHeader_), "%s", pendingHeader_);
            awaitingHeaderAck_ = false;
            sawError_ = false;
            sendPidRequest();
            break;
        }
        if (haveResponse_) {
            finishRequest(ElmResult::Ok);
        } else if (sawStopped_) {
            finishRequest(ElmResult::Stopped);
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
    const char* header = moduleAtshHeader(pid.module);
    if (header == nullptr) {
        // Unverified module addressing — refuse rather than guess.
        LOGW(kTag, "%s: module '%s' header unverified — request refused",
             pid.name, moduleName(pid.module));
        return false;
    }

    currentPid_ = &pid;
    haveResponse_ = false;
    respLen_ = 0;
    sawNoData_ = false;
    sawStopped_ = false;
    sawError_ = false;
    assembler_.reset();
    setState(ElmState::AwaitingResponse);

    if (std::strcmp(header, currentHeader_) != 0) {
        // Header change must be acknowledged before the actual request.
        std::snprintf(pendingHeader_, sizeof(pendingHeader_), "%s", header);
        awaitingHeaderAck_ = true;
        char cmd[24];
        std::snprintf(cmd, sizeof(cmd), "ATSH%s", header);
        sendLine(cmd);
        deadlineMs_ = now_() + cfg_.initTimeoutMs;
    } else {
        awaitingHeaderAck_ = false;
        sendPidRequest();
    }
    return true;
}

void ElmClient::sendPidRequest()
{
    const PidDefinition& pid = *currentPid_;
    char cmd[16];
    if (pid.service == 0x22) {
        std::snprintf(cmd, sizeof(cmd), "22%04X", pid.pid);
    } else {
        std::snprintf(cmd, sizeof(cmd), "%02X%02X", pid.service, pid.pid & 0xFF);
    }
    sendLine(cmd);
    // The very first data request can trigger protocol SEARCHING — give it
    // the long deadline; afterwards use the per-PID timeout.
    deadlineMs_ = now_() + (firstDataDone_ ? pid.timeoutMs : cfg_.firstDataTimeoutMs);
}

void ElmClient::finishRequest(ElmResult result)
{
    const PidDefinition* pid = currentPid_;
    currentPid_ = nullptr;
    awaitingHeaderAck_ = false;
    if (state() == ElmState::AwaitingResponse) {
        setState(ElmState::Idle);
        deadlineMs_ = now_() + cfg_.recoveryTimeoutMs; // benign idle deadline
    }
    if (result == ElmResult::Ok) {
        consecutiveTimeouts_ = 0;
        firstDataDone_ = true;
    }
    if (pid != nullptr && handler_ != nullptr) {
        handler_(handlerCtx_, *pid, result,
                 result == ElmResult::Ok ? respBuf_ : nullptr,
                 result == ElmResult::Ok ? respLen_ : 0);
    }
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
