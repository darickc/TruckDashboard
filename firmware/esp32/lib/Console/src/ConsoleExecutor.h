#pragma once
//
// Runs console commands on the OBD task.
//
// Everything here touches ElmClient / PidScheduler, so it must run on the task
// that owns them. It is driven from ObdTask's loop at the point where the
// adapter is known to be Idle, and it takes priority over scheduled polling so
// a typed command does not queue behind the poll rotation.
//
// Depends only on ObdCore, so it is host-testable against MockTransport.

#include <cstddef>
#include <cstdint>

#include "CommandMailbox.h"
#include "ElmClient.h"
#include "PidScheduler.h"
#include "TimeSource.h"
#include "VehicleData.h"

namespace console {

class ConsoleExecutor {
public:
    ConsoleExecutor(obd::ElmClient& elm, obd::PidScheduler& scheduler,
                    obd::VehicleData& data, CommandMailbox& mailbox, obd::TimeFn now);

    /// Install the raw-line hook on the ElmClient. Call once after construction.
    void begin();

    /// Drive one step. Call from the OBD task whenever the adapter is Idle.
    /// Returns true when the executor used this slot, in which case the caller
    /// must NOT also submit a scheduled PID this tick.
    bool tick();

    /// True while a probe or raw command is still in flight.
    bool busy() const { return phase_ != Phase::Idle; }

    /// Forward every ElmClient result here (from the task's result handler).
    /// Returns true if a probe consumed it and normal logging should be skipped.
    bool onResult(const obd::PidDefinition& pid, const obd::ElmResponse& rsp);

private:
    enum class Phase : uint8_t { Idle, ProbeSubmit, ProbeWait, RawSubmit, RawWait };

    void runImmediate(const ParsedCommand& cmd);
    void listPids();
    void listStats();
    void dumpSnapshot();
    void applyHeaderOverride(const ParsedCommand& cmd);
    void finishProbe();

    static void rawLineTrampoline(void* ctx, const char* line);
    void onRawLine(const char* line);

    obd::ElmClient& elm_;
    obd::PidScheduler& scheduler_;
    obd::VehicleData& data_;
    CommandMailbox& mailbox_;
    obd::TimeFn now_;

    Phase phase_ = Phase::Idle;

    // probe state
    const obd::PidDefinition* probePid_ = nullptr;
    uint8_t probeRemaining_ = 0;
    uint8_t probeAttempt_ = 0;
    uint8_t probeOk_ = 0;
    uint8_t probeMaxResponders_ = 0;
    uint32_t probeLatencySum_ = 0;
    uint32_t probeDeadlineMs_ = 0;

    // raw state
    char rawCmd_[kMaxRawCommand + 1] = {0};
    uint32_t rawIdleDeadlineMs_ = 0; ///< give up waiting for an idle adapter
    uint32_t rawDeadlineMs_ = 0;     ///< give up waiting for the reply
    bool sawRawLine_ = false;
};

} // namespace console
