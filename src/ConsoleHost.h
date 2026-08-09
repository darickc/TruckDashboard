#pragma once
//
// Arduino glue for the serial console: reads Serial, echoes, parses, posts to
// the mailbox, prints replies. Runs on loopTask — it must never touch ElmClient
// or PidScheduler directly (see lib/Console/src/CommandMailbox.h).

#include "CommandMailbox.h"
#include "ConsoleParser.h"

struct ConsoleContext {
    console::CommandMailbox* mailbox;

    /// Shared with UiTask (same task, so a plain bool is enough). The text
    /// display writes to this same UART, so it has to be silenceable
    /// independently of the log level.
    bool* displayEnabled;

    console::LineReader reader;
    bool unsafeAllowed = false;
    bool greeted = false;
    bool autoMuted = false; ///< the display has been paused once, on first input
};

/// Drain Serial, dispatch at most one command, print any completed reply.
/// Never blocks.
void consoleTick(ConsoleContext& ctx);
