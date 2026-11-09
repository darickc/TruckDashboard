#pragma once
//
// Single-slot handoff between the console (producer, loopTask) and the OBD
// task (consumer).
//
// ElmClient and PidScheduler are OBD-task-private: their state machines assume
// single-threaded access, and the console must never touch them directly. So
// the console posts a ConsoleRequest here, the OBD task picks it up at a point
// where it already knows the adapter is Idle, executes it, appends reply lines,
// and marks it done. The console then prints the reply.
//
// One request in flight at a time. The state machine is:
//
//   Idle --post--> Pending --take--> Running --finish--> Done --drain--> Idle
//
// Producer owns the Idle->Pending and Done->Idle edges; consumer owns
// Pending->Running and Running->Done. Because each transition is owned by
// exactly one thread and the payload is only touched by the thread that owns
// the current state, a single atomic with acquire/release ordering is enough —
// no mutex, no allocation.

#include <atomic>
#include <cstddef>
#include <cstdint>

#include "ConsoleCommands.h"

namespace console {

/// Room for a `pids` or `stats` dump. Sized for the 18-row table plus headers.
inline constexpr size_t kReplyCapacity = 4096;

struct ConsoleRequest {
    ParsedCommand cmd;
};

class CommandMailbox {
public:
    /// Producer: submit a request. False when one is already in flight — the
    /// console then tells the operator to wait rather than dropping it silently.
    bool post(const ParsedCommand& cmd);

    /// Consumer: claim a pending request. False if there is nothing to do.
    bool take(ConsoleRequest& out);

    /// Consumer: append one line of output for the operator. Silently stops at
    /// kReplyCapacity — a truncated dump is better than a corrupted task.
    void reply(const char* line);

    /// Consumer: printf-style convenience for reply().
    /// The format attribute is not decoration — a mismatched argument list here
    /// silently shifts every later argument, which is how a `pids` dump turns
    /// into a segfault. Let the compiler catch it.
#if defined(__GNUC__) || defined(__clang__)
    __attribute__((format(printf, 2, 3)))
#endif
    void replyf(const char* fmt, ...);

    /// Consumer: the request is finished; its reply may now be read.
    void finish();

    /// Producer: true once the consumer has called finish().
    bool isDone() const;

    /// Producer: read the accumulated reply and return the mailbox to Idle.
    /// Returns nullptr if no completed reply is waiting.
    const char* takeReply();

    /// True when a request is posted or running.
    bool busy() const;

    /// True if the last reply hit the capacity limit (so the caller can say so
    /// rather than let the operator believe they saw everything).
    bool replyTruncated() const { return truncated_; }

private:
    enum class State : uint8_t { Idle, Pending, Running, Done };

    std::atomic<State> state_{State::Idle};
    ConsoleRequest req_;
    char reply_[kReplyCapacity] = {0};
    size_t replyLen_ = 0;
    bool truncated_ = false;
};

} // namespace console
