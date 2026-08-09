#include "ConsoleExecutor.h"

#include <cstdio>
#include <cstring>

#include "Decoders.h"
#include "Log.h"
#include "Units.h"

namespace console {

using namespace obd;

static const char* kTag = "con";

namespace {

/// How long to wait for one probe request before giving up on it. Generous:
/// the very first request after a reconnect can trigger protocol SEARCHING.
constexpr uint32_t kProbeTimeoutMs = 12000;
constexpr uint32_t kRawTimeoutMs = 5000;

} // namespace

ConsoleExecutor::ConsoleExecutor(ElmClient& elm, PidScheduler& scheduler,
                                 VehicleData& data, CommandMailbox& mailbox,
                                 TimeFn now)
    : elm_(elm), scheduler_(scheduler), data_(data), mailbox_(mailbox), now_(now)
{
}

void ConsoleExecutor::begin()
{
    elm_.setRawLineHandler(&ConsoleExecutor::rawLineTrampoline, this);
}

void ConsoleExecutor::rawLineTrampoline(void* ctx, const char* line)
{
    static_cast<ConsoleExecutor*>(ctx)->onRawLine(line);
}

void ConsoleExecutor::onRawLine(const char* line)
{
    sawRawLine_ = true;
    mailbox_.replyf("  %s", line);
}

bool ConsoleExecutor::tick()
{
    const uint32_t now = now_();

    switch (phase_) {
    case Phase::ProbeWait:
        if (timeReached(now, probeDeadlineMs_)) {
            mailbox_.replyf("  #%u  <timed out>", probeAttempt_);
            --probeRemaining_;
            phase_ = Phase::ProbeSubmit;
        }
        return true;

    case Phase::ProbeSubmit:
        if (probeRemaining_ == 0) {
            finishProbe();
            return true;
        }
        if (elm_.state() != ElmState::Idle) {
            return true; // adapter busy recovering; keep the slot, try next tick
        }
        ++probeAttempt_;
        if (!elm_.submit(*probePid_)) {
            mailbox_.replyf("  #%u  refused (module '%s' header unverified — "
                            "use `hdr` to try a candidate)",
                            probeAttempt_, moduleName(probePid_->module));
            --probeRemaining_;
            return true;
        }
        probeDeadlineMs_ = now + kProbeTimeoutMs;
        phase_ = Phase::ProbeWait;
        return true;

    case Phase::RawWait:
        if (!elm_.rawInFlight() || timeReached(now, rawDeadlineMs_)) {
            if (!sawRawLine_) {
                mailbox_.reply("  <no reply>");
            }
            if (elm_.rawInFlight()) {
                mailbox_.reply("  <timed out>");
            }
            mailbox_.reply("(adapter addressing cache invalidated — the next "
                           "scheduled request re-sends its ATSH)");
            mailbox_.finish();
            phase_ = Phase::Idle;
        }
        return true;

    case Phase::Idle:
        break;
    }

    ConsoleRequest req;
    if (!mailbox_.take(req)) {
        return false;
    }

    switch (req.cmd.kind) {
    case ParsedCommand::Kind::Probe: {
        probePid_ = findPid(req.cmd.key);
        if (probePid_ == nullptr) {
            mailbox_.reply("PID vanished from the table");
            mailbox_.finish();
            return true;
        }
        probeRemaining_ = req.cmd.repeat;
        probeAttempt_ = 0;
        probeOk_ = 0;
        probeLatencySum_ = 0;
        const ObdAddressing addr = moduleAddressing(probePid_->module);
        mailbox_.replyf("probe %s  (%s %s%04X, module %s -> %s%s%s)",
                        pidKeyName(probePid_->key), probePid_->name,
                        probePid_->service == 0x22 ? "22 " : "01 ", probePid_->pid,
                        moduleName(probePid_->module),
                        addr.txHeader != nullptr ? addr.txHeader : "UNVERIFIED",
                        addr.rxFilter != nullptr ? " rx " : "",
                        addr.rxFilter != nullptr ? addr.rxFilter : "");
        if (!probePid_->verified) {
            mailbox_.reply("  [UNVERIFIED definition — compare against an "
                           "independent reference before trusting it]");
        }
        phase_ = Phase::ProbeSubmit;
        return true;
    }

    case ParsedCommand::Kind::Raw: {
        if (elm_.state() != ElmState::Idle) {
            mailbox_.replyf("adapter is %s — try again in a moment",
                            elmStateName(elm_.state()));
            mailbox_.finish();
            return true;
        }
        mailbox_.replyf("TX> %s", req.cmd.text);
        sawRawLine_ = false;
        if (!elm_.submitRaw(req.cmd.text)) {
            mailbox_.reply("  <refused>");
            mailbox_.finish();
            return true;
        }
        rawDeadlineMs_ = now + kRawTimeoutMs;
        phase_ = Phase::RawWait;
        return true;
    }

    default:
        runImmediate(req.cmd);
        mailbox_.finish();
        return true;
    }
}

void ConsoleExecutor::finishProbe()
{
    if (probeAttempt_ > 0) {
        mailbox_.replyf("%u/%u ok, avg latency %ums", probeOk_, probeAttempt_,
                        probeOk_ > 0 ? probeLatencySum_ / probeOk_ : 0);
    }
    mailbox_.finish();
    phase_ = Phase::Idle;
    probePid_ = nullptr;
}

bool ConsoleExecutor::onResult(const PidDefinition& pid, const ElmResponse& rsp)
{
    if (phase_ != Phase::ProbeWait || probePid_ == nullptr || pid.key != probePid_->key) {
        return false;
    }

    if (rsp.result != ElmResult::Ok) {
        mailbox_.replyf("  #%u  %s", probeAttempt_, elmResultName(rsp.result));
    } else {
        char hex[2 * 32 + 1] = {0};
        size_t o = 0;
        for (size_t i = 0; i < rsp.len && o + 3 < sizeof(hex); ++i) {
            o += static_cast<size_t>(std::snprintf(hex + o, sizeof(hex) - o, "%02X",
                                                   rsp.payload[i]));
        }

        float value = 0.0f;
        char decoded[48];
        if (decodePid(pid, rsp.payload, rsp.len, value)) {
            const Unit chUnit = channelUnit(pid.channel);
            std::snprintf(decoded, sizeof(decoded), "%.2f %s",
                          static_cast<double>(convertUnit(value, pid.unit, chUnit)),
                          unitSuffix(chUnit));
        } else {
            std::snprintf(decoded, sizeof(decoded), "<decode failed>");
        }

        mailbox_.replyf("  #%u  <-%03X  %-10s  %-14s %ums%s%s", probeAttempt_,
                        static_cast<unsigned>(rsp.responderId), hex, decoded,
                        rsp.latencyMs,
                        rsp.responderCount > 1 ? "  (2+ ECUs answered)" : "",
                        rsp.responderConflict ? "  *** THEY DISAGREE ***" : "");
        ++probeOk_;
        probeLatencySum_ += rsp.latencyMs;
    }

    --probeRemaining_;
    phase_ = Phase::ProbeSubmit;
    return true;
}

void ConsoleExecutor::runImmediate(const ParsedCommand& cmd)
{
    switch (cmd.kind) {
    case ParsedCommand::Kind::Help:
        for (const char* const* p = helpLines(); *p != nullptr; ++p) {
            mailbox_.reply(*p);
        }
        break;

    case ParsedCommand::Kind::Pids:
        listPids();
        break;

    case ParsedCommand::Kind::Stats:
        listStats();
        break;

    case ParsedCommand::Kind::ResetStats:
        scheduler_.resetStats();
        elm_.resetStats();
        mailbox_.reply("stats cleared");
        break;

    case ParsedCommand::Kind::Snap:
        dumpSnapshot();
        break;

    case ParsedCommand::Kind::On: {
        const PidDefinition* def = findPid(cmd.key);
        if (def == nullptr) {
            mailbox_.reply("PID vanished from the table");
        } else if (scheduler_.add(*def, now_())) {
            mailbox_.replyf("polling %s every %ums%s", def->name, def->pollIntervalMs,
                            def->verified ? "" : "  [UNVERIFIED]");
            const float requested = scheduler_.requestedRatePerSec();
            mailbox_.replyf("enabled set now asks for %.1f req/s",
                            static_cast<double>(requested));
        } else {
            mailbox_.reply("refused — already enabled, table full, or the "
                           "module header is unverified (see the log)");
        }
        break;
    }

    case ParsedCommand::Kind::Off: {
        const PidDefinition* def = findPid(cmd.key);
        if (def != nullptr && scheduler_.remove(cmd.key)) {
            mailbox_.replyf("stopped polling %s", def->name);
        } else {
            mailbox_.reply("that PID was not being polled");
        }
        break;
    }

    case ParsedCommand::Kind::Header:
        applyHeaderOverride(cmd);
        break;

    case ParsedCommand::Kind::LogRaw:
        elm_.setRawLogging(cmd.flag);
        mailbox_.replyf("raw OBD logging %s%s", cmd.flag ? "ON" : "OFF",
                        cmd.flag ? "  (costs polling throughput)" : "");
        break;

    case ParsedCommand::Kind::LogLevel:
        tdlog::setLevel(static_cast<TdLogLevel>(cmd.level));
        mailbox_.replyf("log level %u", cmd.level);
        break;

    default:
        mailbox_.reply("command not handled here");
        break;
    }
}

void ConsoleExecutor::listPids()
{
    mailbox_.reply(" idx key             request  module  hdr      every  prio  state");
    for (size_t i = 0; i < kPidTableSize; ++i) {
        const PidDefinition& d = kPidTable[i];
        const ObdAddressing addr = moduleAddressing(d.module);

        char request[12];
        if (d.service == 0x22) {
            std::snprintf(request, sizeof(request), "22%04X", d.pid);
        } else {
            std::snprintf(request, sizeof(request), "%02X%02X", d.service,
                          d.pid & 0xFF);
        }

        mailbox_.replyf("%s%3u %-15s %-8s %-7s %-8s %5u %5u  %s%s%s",
                        scheduler_.isEnabled(d.key) ? "*" : " ",
                        static_cast<unsigned>(i), pidKeyName(d.key), request,
                        moduleName(d.module),
                        addr.txHeader != nullptr ? addr.txHeader : "UNVERIF",
                        d.pollIntervalMs, d.priority,
                        d.verified ? "verified" : "unverified",
                        hasModuleAddressingOverride(d.module) ? "  [hdr override]" : "",
                        d.expectedResponder != 0 ? "  [pinned]" : "");
    }
    mailbox_.replyf("* = polling now; %u enabled, asking %.1f req/s",
                    static_cast<unsigned>(scheduler_.entryCount()),
                    static_cast<double>(scheduler_.requestedRatePerSec()));
}

void ConsoleExecutor::listStats()
{
    if (scheduler_.entryCount() == 0) {
        mailbox_.reply("nothing is being polled");
        return;
    }
    mailbox_.reply(" key              req    ok  nodata  noresp  t/o  err  conflict"
                   "   latency ms (min/avg/max)");
    for (size_t i = 0; i < scheduler_.entryCount(); ++i) {
        const PidDefinition* d = scheduler_.entryDef(i);
        const PidStats* s = scheduler_.stats(d->key);
        if (s == nullptr) {
            continue;
        }
        mailbox_.replyf(" %-15s %5lu %5lu %7lu %7lu %4lu %4lu %9lu   %5u/%5.0f/%5u",
                        pidKeyName(d->key),
                        static_cast<unsigned long>(s->requests),
                        static_cast<unsigned long>(s->ok),
                        static_cast<unsigned long>(s->noData),
                        static_cast<unsigned long>(s->noResponder),
                        static_cast<unsigned long>(s->timeouts),
                        static_cast<unsigned long>(s->errors),
                        static_cast<unsigned long>(s->conflicts),
                        s->ok > 0 ? s->minLatencyMs : 0,
                        static_cast<double>(s->avgLatencyMs()), s->maxLatencyMs);
    }
    mailbox_.replyf("addressing overhead: %lu ATSH/ATCRA commands, %lums total",
                    static_cast<unsigned long>(elm_.prepCommandCount()),
                    static_cast<unsigned long>(elm_.prepOverheadMs()));
    mailbox_.replyf("requested rate %.1f req/s (measured budget decides whether "
                    "that is honest — see Config.h kMeasuredRequestsPerSec)",
                    static_cast<double>(scheduler_.requestedRatePerSec()));
}

void ConsoleExecutor::dumpSnapshot()
{
    const uint32_t now = now_();
    const Snapshot snap = data_.snapshot(now);
    mailbox_.reply(" channel        value        age ms  errors");
    for (size_t i = 0; i < kChannelCount; ++i) {
        const ChannelId id = static_cast<ChannelId>(i);
        const Channel& ch = snap.channel(id);
        if (!ch.everValid) {
            mailbox_.replyf(" %-14s %-12s %6s  %6u", channelShortName(id), "---", "-",
                            ch.errorCount);
            continue;
        }
        char value[24];
        std::snprintf(value, sizeof(value), "%.2f %s", static_cast<double>(ch.value),
                      unitSuffix(channelUnit(id)));
        mailbox_.replyf(" %-14s %-12s %6lu  %6u", channelShortName(id), value,
                        static_cast<unsigned long>(timeSince(now, ch.updatedAtMs)),
                        ch.errorCount);
    }
}

void ConsoleExecutor::applyHeaderOverride(const ParsedCommand& cmd)
{
    if (cmd.header[0] == '\0') {
        clearModuleAddressingOverrides();
        mailbox_.reply("all runtime addressing overrides dropped — back to the "
                       "compiled-in table");
        return;
    }
    const char* filter = cmd.filter[0] != '\0' ? cmd.filter : nullptr;
    if (!setModuleAddressingOverride(cmd.module, cmd.header, filter)) {
        mailbox_.reply("refused — header or filter too long");
        return;
    }
    LOGW(kTag, "module %s addressing overridden at runtime: ATSH%s%s%s — "
               "CANDIDATE ONLY, not verified",
         moduleName(cmd.module), cmd.header, filter != nullptr ? " ATCRA" : "",
         filter != nullptr ? filter : "");
    mailbox_.replyf("%s -> ATSH%s%s%s", moduleName(cmd.module), cmd.header,
                    filter != nullptr ? " + ATCRA" : "",
                    filter != nullptr ? filter : "");
    mailbox_.reply("this is a CANDIDATE, not a verified value. It dies on reboot. "
                   "Probe a PID on this module and check what answers; if it holds "
                   "up, commit it to moduleAddressing() with the evidence.");
}

} // namespace console
