#pragma once
//
// Per-PID polling scheduler.
//
// Each enabled PID has its own poll interval and priority. next() returns the
// highest-priority due PID (ties broken by most-overdue) so scarce adapter
// throughput (~10-15 requests/s over Bluetooth) goes to the signals that
// matter most. Poll intervals are targets — when the bus is oversubscribed,
// low-priority PIDs degrade gracefully.
//
// Failure handling: consecutive failures put a PID into exponential backoff
// (it keeps being retried — NO DATA may just mean the ignition is off) so a
// dead PID cannot starve the healthy ones.

#include <cstddef>
#include <cstdint>

#include "PidDefs.h"
#include "TimeSource.h"

namespace obd {

struct SchedulerConfig {
    uint32_t initialBackoffMs = 5000;   ///< backoff after repeated failures
    uint32_t maxBackoffMs = 60000;
    uint8_t failuresBeforeBackoff = 3;
};

class PidScheduler {
public:
    static constexpr size_t kMaxEntries = 32;

    /// Register the enabled subset of the PID table. PIDs whose module header
    /// is unverified (nullptr) are skipped with a warning — never guessed.
    void begin(const PidDefinition* table, size_t tableSize,
               const PidKey* enabledKeys, size_t enabledCount,
               const SchedulerConfig& cfg = {});

    /// Highest-priority due PID, or nullptr. SIDE EFFECT: schedules the
    /// returned PID's next poll (caller must submit it).
    const PidDefinition* next(uint32_t now);

    /// Report the outcome of a submitted request.
    void onResult(const PidDefinition& pid, bool success, uint32_t now);

    /// Make everything due immediately (e.g. after reconnect).
    void resetTiming(uint32_t now);

    size_t entryCount() const { return count_; }

private:
    struct Entry {
        const PidDefinition* def = nullptr;
        uint32_t nextDueMs = 0;
        uint32_t lastSuccessMs = 0;
        uint8_t consecutiveFailures = 0;
        uint32_t backoffMs = 0;
    };

    Entry* findEntry(PidKey key);

    Entry entries_[kMaxEntries];
    size_t count_ = 0;
    SchedulerConfig cfg_;
};

} // namespace obd
