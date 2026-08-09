#pragma once
//
// Arduino glue for the serial console: reads Serial, parses, posts to the
// mailbox, prints replies. Runs on loopTask — it must never touch ElmClient or
// PidScheduler directly (see lib/Console/src/CommandMailbox.h).

#include "CommandMailbox.h"
#include "ConsoleParser.h"

struct ConsoleContext {
    console::CommandMailbox* mailbox;
    console::LineReader reader;
    bool unsafeAllowed = false;
    bool greeted = false;
};

/// Drain Serial, dispatch at most one command, print any completed reply.
/// Never blocks.
void consoleTick(ConsoleContext& ctx);
