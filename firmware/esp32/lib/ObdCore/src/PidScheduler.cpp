#include "PidScheduler.h"

#include "Decoders.h"
#include "Log.h"
#include "Units.h"

namespace obd {

static const char* kTag = "sched";

namespace {

/// Largest gap between what the responders reported, in channel units.
///
/// Decoded, not raw: two modules reporting a 690 rpm idle 30 ms apart differ in
/// bytes on nearly every sample but by ~1 rpm in meaning. Comparing bytes would
/// call that a disagreement; comparing values calls it agreement, which is what
/// it is. Returns 0 when fewer than two answers decode.
float decodedSpread(const PidDefinition& pid, const ElmResponse& rsp)
{
    const Unit chUnit = channelUnit(pid.channel);
    float lo = 0.0f;
    float hi = 0.0f;
    uint8_t decoded = 0;
    for (uint8_t i = 0; i < rsp.recordedResponders; ++i) {
        float raw = 0.0f;
        if (!decodePid(pid, rsp.responders[i].payload, rsp.responders[i].len, raw)) {
            continue;
        }
        const float v = convertUnit(raw, pid.unit, chUnit);
        if (decoded == 0 || v < lo) lo = v;
        if (decoded == 0 || v > hi) hi = v;
        ++decoded;
    }
    return decoded >= 2 ? hi - lo : 0.0f;
}

} // namespace

void PidScheduler::begin(const PidDefinition* table, size_t tableSize,
                         const PidKey* enabledKeys, size_t enabledCount,
                         const SchedulerConfig& cfg)
{
    cfg_ = cfg;
    count_ = 0;
    for (size_t k = 0; k < enabledCount; ++k) {
        const PidDefinition* def = nullptr;
        for (size_t i = 0; i < tableSize; ++i) {
            if (table[i].key == enabledKeys[k]) {
                def = &table[i];
                break;
            }
        }
        if (def == nullptr) {
            LOGW(kTag, "enabled PID key %u not in table — skipped",
                 static_cast<unsigned>(enabledKeys[k]));
            continue;
        }
        add(*def, 0);
    }
    warnIfOversubscribed();
}

bool PidScheduler::add(const PidDefinition& def, uint32_t now)
{
    if (moduleAtshHeader(def.module) == nullptr) {
        LOGW(kTag, "%s: module '%s' header UNVERIFIED — skipped (see docs/diagnostics/FORD_6_0_PIDS.md)",
             def.name, moduleName(def.module));
        return false;
    }
    if (findEntry(def.key) != nullptr) {
        LOGW(kTag, "%s: already enabled", def.name);
        return false;
    }
    if (count_ >= kMaxEntries) {
        LOGE(kTag, "scheduler full — %s not registered", def.name);
        return false;
    }
    Entry& e = entries_[count_++];
    e = Entry{};
    e.def = &def;
    e.nextDueMs = now;
    e.backoffMs = cfg_.initialBackoffMs;
    LOGI(kTag, "polling %-24s svc %02X pid %04X every %ums (prio %u)%s",
         def.name, def.service, def.pid, def.pollIntervalMs, def.priority,
         def.verified ? "" : " [UNVERIFIED — confirm on truck]");
    return true;
}

bool PidScheduler::remove(PidKey key)
{
    for (size_t i = 0; i < count_; ++i) {
        if (entries_[i].def->key != key) {
            continue;
        }
        LOGI(kTag, "stopped polling %s", entries_[i].def->name);
        for (size_t j = i + 1; j < count_; ++j) {
            entries_[j - 1] = entries_[j];
        }
        --count_;
        entries_[count_] = Entry{};
        return true;
    }
    return false;
}

bool PidScheduler::isEnabled(PidKey key) const
{
    return findEntry(key) != nullptr;
}

const PidDefinition* PidScheduler::entryDef(size_t i) const
{
    return i < count_ ? entries_[i].def : nullptr;
}

const PidStats* PidScheduler::stats(PidKey key) const
{
    const Entry* e = findEntry(key);
    return e != nullptr ? &e->stats : nullptr;
}

void PidScheduler::resetStats()
{
    for (size_t i = 0; i < count_; ++i) {
        entries_[i].stats = PidStats{};
    }
}

float PidScheduler::requestedRatePerSec() const
{
    float rate = 0.0f;
    for (size_t i = 0; i < count_; ++i) {
        const uint16_t interval = entries_[i].def->pollIntervalMs;
        if (interval > 0) {
            rate += 1000.0f / static_cast<float>(interval);
        }
    }
    return rate;
}

void PidScheduler::warnIfOversubscribed() const
{
    const float requested = requestedRatePerSec();
    const float budget = cfg_.measuredRequestsPerSec;
    if (budget <= 0.0f || requested <= budget * 0.8f) {
        return;
    }
    // Name the victims: next() serves the lowest priority number first, so the
    // highest-numbered priorities are the ones that will miss their interval.
    uint8_t worstPriority = 0;
    const char* worstName = "?";
    for (size_t i = 0; i < count_; ++i) {
        if (entries_[i].def->priority >= worstPriority) {
            worstPriority = entries_[i].def->priority;
            worstName = entries_[i].def->name;
        }
    }
    LOGW(kTag, "oversubscribed: %u PIDs want %.1f req/s but the link measures "
               "%.1f — low-priority PIDs (prio %u, e.g. %s) will miss their "
               "interval. Rebalance PidDefs.cpp against console `stats`.",
         static_cast<unsigned>(count_), static_cast<double>(requested),
         static_cast<double>(budget), worstPriority, worstName);
}

const PidDefinition* PidScheduler::next(uint32_t now)
{
    Entry* best = nullptr;
    int32_t bestOverdue = 0;
    for (size_t i = 0; i < count_; ++i) {
        Entry& e = entries_[i];
        const int32_t overdue = static_cast<int32_t>(now - e.nextDueMs);
        if (overdue < 0) {
            continue; // not due
        }
        if (best == nullptr ||
            e.def->priority < best->def->priority ||
            (e.def->priority == best->def->priority && overdue > bestOverdue)) {
            best = &e;
            bestOverdue = overdue;
        }
    }
    if (best == nullptr) {
        return nullptr;
    }
    best->nextDueMs = now + best->def->pollIntervalMs;
    return best->def;
}

void PidScheduler::onResult(const PidDefinition& pid, const ElmResponse& rsp, uint32_t now)
{
    Entry* e = findEntry(pid.key);
    if (e == nullptr) {
        return;
    }

    PidStats& s = e->stats;
    ++s.requests;
    if (rsp.responderCount > 1) {
        ++s.multiResponderSamples;
        if (rsp.respondersDiffer) {
            ++s.divergentSamples;
        }
        const float spread = decodedSpread(pid, rsp);
        if (spread > s.maxResponderSpread) {
            s.maxResponderSpread = spread;
        }
    }
    switch (rsp.result) {
    case ElmResult::Ok: break;
    case ElmResult::NoData: ++s.noData; break;
    case ElmResult::NoResponder: ++s.noResponder; break;
    case ElmResult::Timeout: ++s.timeouts; break;
    case ElmResult::Stopped:
    case ElmResult::Error: ++s.errors; break;
    }

    if (rsp.result == ElmResult::Ok) {
        ++s.ok;
        s.latencySumMs += rsp.latencyMs;
        if (rsp.latencyMs < s.minLatencyMs) {
            s.minLatencyMs = rsp.latencyMs;
        }
        if (rsp.latencyMs > s.maxLatencyMs) {
            s.maxLatencyMs = rsp.latencyMs;
        }
        e->consecutiveFailures = 0;
        e->backoffMs = cfg_.initialBackoffMs;
        e->lastSuccessMs = now;
        return;
    }
    if (e->consecutiveFailures < UINT8_MAX) {
        ++e->consecutiveFailures;
    }
    if (e->consecutiveFailures >= cfg_.failuresBeforeBackoff) {
        e->nextDueMs = now + e->backoffMs;
        LOGW(kTag, "%s: %u consecutive failures — backing off %lums",
             pid.name, e->consecutiveFailures,
             static_cast<unsigned long>(e->backoffMs));
        e->backoffMs *= 2;
        if (e->backoffMs > cfg_.maxBackoffMs) {
            e->backoffMs = cfg_.maxBackoffMs;
        }
    }
}

void PidScheduler::resetTiming(uint32_t now)
{
    for (size_t i = 0; i < count_; ++i) {
        entries_[i].nextDueMs = now;
        entries_[i].consecutiveFailures = 0;
        entries_[i].backoffMs = cfg_.initialBackoffMs;
    }
}

PidScheduler::Entry* PidScheduler::findEntry(PidKey key)
{
    return const_cast<Entry*>(static_cast<const PidScheduler*>(this)->findEntry(key));
}

const PidScheduler::Entry* PidScheduler::findEntry(PidKey key) const
{
    for (size_t i = 0; i < count_; ++i) {
        if (entries_[i].def->key == key) {
            return &entries_[i];
        }
    }
    return nullptr;
}

} // namespace obd
