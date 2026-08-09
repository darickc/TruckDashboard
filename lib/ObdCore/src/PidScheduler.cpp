#include "PidScheduler.h"

#include "Log.h"

namespace obd {

static const char* kTag = "sched";

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
        if (moduleAtshHeader(def->module) == nullptr) {
            LOGW(kTag, "%s: module '%s' header UNVERIFIED — skipped (see docs/FORD_6_0_PIDS.md)",
                 def->name, moduleName(def->module));
            continue;
        }
        if (count_ >= kMaxEntries) {
            LOGE(kTag, "scheduler full — %s not registered", def->name);
            continue;
        }
        Entry& e = entries_[count_++];
        e = Entry{};
        e.def = def;
        e.backoffMs = cfg_.initialBackoffMs;
        LOGI(kTag, "polling %-24s svc %02X pid %04X every %ums (prio %u)%s",
             def->name, def->service, def->pid, def->pollIntervalMs, def->priority,
             def->verified ? "" : " [UNVERIFIED — confirm on truck]");
    }
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

void PidScheduler::onResult(const PidDefinition& pid, bool success, uint32_t now)
{
    Entry* e = findEntry(pid.key);
    if (e == nullptr) {
        return;
    }
    if (success) {
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
    for (size_t i = 0; i < count_; ++i) {
        if (entries_[i].def->key == key) {
            return &entries_[i];
        }
    }
    return nullptr;
}

} // namespace obd
