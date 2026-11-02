#include "CommandMailbox.h"

#include <cstdarg>
#include <cstdio>
#include <cstring>

namespace console {

bool CommandMailbox::post(const ParsedCommand& cmd)
{
    if (state_.load(std::memory_order_acquire) != State::Idle) {
        return false;
    }
    req_.cmd = cmd;
    replyLen_ = 0;
    reply_[0] = '\0';
    truncated_ = false;
    // Release: the consumer's acquire in take() must see the payload above.
    state_.store(State::Pending, std::memory_order_release);
    return true;
}

bool CommandMailbox::take(ConsoleRequest& out)
{
    if (state_.load(std::memory_order_acquire) != State::Pending) {
        return false;
    }
    out = req_;
    state_.store(State::Running, std::memory_order_release);
    return true;
}

void CommandMailbox::reply(const char* line)
{
    if (line == nullptr) {
        return;
    }
    const size_t n = std::strlen(line);
    // +1 for the newline, +1 for the terminator.
    if (replyLen_ + n + 2 > sizeof(reply_)) {
        truncated_ = true;
        return;
    }
    std::memcpy(reply_ + replyLen_, line, n);
    replyLen_ += n;
    reply_[replyLen_++] = '\n';
    reply_[replyLen_] = '\0';
}

void CommandMailbox::replyf(const char* fmt, ...)
{
    char buf[192];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    reply(buf);
}

void CommandMailbox::finish()
{
    if (truncated_) {
        // Say so rather than let a clipped dump read as a complete one.
        const char* note = "[output truncated]\n";
        const size_t n = std::strlen(note);
        if (replyLen_ + n + 1 <= sizeof(reply_)) {
            std::memcpy(reply_ + replyLen_, note, n + 1);
            replyLen_ += n;
        }
    }
    state_.store(State::Done, std::memory_order_release);
}

bool CommandMailbox::isDone() const
{
    return state_.load(std::memory_order_acquire) == State::Done;
}

const char* CommandMailbox::takeReply()
{
    if (state_.load(std::memory_order_acquire) != State::Done) {
        return nullptr;
    }
    // The reply text stays valid until the next post(), which only this thread
    // performs — so returning the buffer directly is safe.
    state_.store(State::Idle, std::memory_order_release);
    return reply_;
}

bool CommandMailbox::busy() const
{
    const State s = state_.load(std::memory_order_acquire);
    return s == State::Pending || s == State::Running;
}

} // namespace console
