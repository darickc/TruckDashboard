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

#include "ElmClient.h"
#include "PidDefs.h"
#include "TimeSource.h"

namespace obd {

struct SchedulerConfig {
    uint32_t initialBackoffMs = 5000;   ///< backoff after repeated failures
    uint32_t maxBackoffMs = 60000;
    uint8_t failuresBeforeBackoff = 3;

    /// Measured adapter throughput, requests/s. The table's poll intervals are
    /// wishes; this is the budget they are spent from. Oversubscription is not
    /// an error (the scheduler degrades by priority) but it IS worth saying out
    /// loud — a table promising 10 Hz while delivering 2 Hz is a lie the code
    /// tells the driver.
    float measuredRequestsPerSec = 10.0f;
};

/// Per-PID counters, for the console `stats` command and for deciding poll
/// intervals from measurement rather than hope.
struct PidStats {
    uint32_t requests = 0;
    uint32_t ok = 0;
    uint32_t noData = 0;
    uint32_t noResponder = 0;
    uint32_t timeouts = 0;
    uint32_t errors = 0;

    /// Responder observations. `divergentSamples` counts responses where two
    /// ECUs returned different BYTES, which for a live signal like RPM is nearly
    /// every sample and means nothing on its own. `maxResponderSpread` is the
    /// number that actually diagnoses: the largest gap between responders'
    /// DECODED values, in channel units. ~1 rpm means two modules reporting the
    /// same signal a few milliseconds apart; a spread the size of the value
    /// itself means they disagree about what the DID is.
    uint32_t multiResponderSamples = 0;
    uint32_t divergentSamples = 0;
    float maxResponderSpread = 0.0f;

    uint32_t latencySumMs = 0; ///< over `ok` responses only
    uint16_t minLatencyMs = 0xFFFF;
    uint16_t maxLatencyMs = 0;

    float avgLatencyMs() const
    {
        return ok == 0 ? 0.0f : static_cast<float>(latencySumMs) / static_cast<float>(ok);
    }
};

class PidScheduler {
public:
    static constexpr size_t kMaxEntries = 32;

    /// Register the enabled subset of the PID table. PIDs whose module header
    /// is unverified (nullptr) are skipped with a warning — never guessed.
    void begin(const PidDefinition* table, size_t tableSize,
               const PidKey* enabledKeys, size_t enabledCount,
               const SchedulerConfig& cfg = {});

    /// Enable one PID at runtime (console `on`). Returns false — with a logged
    /// reason — when the table is full, the PID is already enabled, or its
    /// module header is unverified.
    bool add(const PidDefinition& def, uint32_t now);

    /// Disable one PID at runtime (console `off`). False if it wasn't enabled.
    bool remove(PidKey key);

    bool isEnabled(PidKey key) const;

    /// Highest-priority due PID, or nullptr. SIDE EFFECT: schedules the
    /// returned PID's next poll (caller must submit it).
    const PidDefinition* next(uint32_t now);

    /// Report the outcome of a submitted request.
    void onResult(const PidDefinition& pid, const ElmResponse& rsp, uint32_t now);

    /// Make everything due immediately (e.g. after reconnect).
    void resetTiming(uint32_t now);

    size_t entryCount() const { return count_; }
    const PidDefinition* entryDef(size_t i) const;
    const PidStats* stats(PidKey key) const;
    void resetStats();

    /// Requests/s the enabled set is asking for. Compare against
    /// SchedulerConfig::measuredRequestsPerSec.
    float requestedRatePerSec() const;

private:
    struct Entry {
        const PidDefinition* def = nullptr;
        uint32_t nextDueMs = 0;
        uint32_t lastSuccessMs = 0;
        uint8_t consecutiveFailures = 0;
        uint32_t backoffMs = 0;
        PidStats stats;
    };

    Entry* findEntry(PidKey key);
    const Entry* findEntry(PidKey key) const;
    void warnIfOversubscribed() const;

    Entry entries_[kMaxEntries];
    size_t count_ = 0;
    SchedulerConfig cfg_;
};

} // namespace obd
