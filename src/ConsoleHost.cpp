#include "ConsoleHost.h"

#include <Arduino.h>

#include "ConsoleCommands.h"

namespace {

void print(const char* s) { Serial.print(s); }

void handleLine(ConsoleContext& ctx, char* line)
{
    const char* argv[console::kMaxArgs];
    bool truncated = false;
    const size_t argc = console::tokenize(line, argv, console::kMaxArgs, &truncated);
    if (argc == 0) {
        return;
    }
    if (truncated) {
        print("too many arguments\r\n");
        return;
    }

    console::ParsedCommand cmd;
    char err[160];
    if (!console::parse(argc, argv, ctx.unsafeAllowed, cmd, err, sizeof(err))) {
        print(err);
        print("\r\n");
        return;
    }

    // `unsafe` is console-local session state — it never reaches the OBD task.
    if (cmd.kind == console::ParsedCommand::Kind::Unsafe) {
        ctx.unsafeAllowed = cmd.flag;
        print(cmd.flag ? "unsafe ON — raw write/clear/control services allowed "
                         "until reboot\r\n"
                       : "unsafe OFF\r\n");
        return;
    }

    if (!ctx.mailbox->post(cmd)) {
        print("busy — a command is still running\r\n");
    }
}

} // namespace

void consoleTick(ConsoleContext& ctx)
{
    if (!ctx.greeted) {
        ctx.greeted = true;
        print("\r\nconsole ready — type `help`\r\n");
    }

    // Bounded per tick so a paste cannot monopolise the UI task.
    for (int i = 0; i < 256 && Serial.available() > 0; ++i) {
        const int c = Serial.read();
        if (c < 0) {
            break;
        }
        switch (ctx.reader.feed(static_cast<char>(c))) {
        case console::LineReader::Event::Line:
            handleLine(ctx, ctx.reader.line());
            break;
        case console::LineReader::Event::Overflow:
            print("line too long — ignored\r\n");
            break;
        case console::LineReader::Event::Empty:
        case console::LineReader::Event::None:
            break;
        }
    }

    if (const char* reply = ctx.mailbox->takeReply()) {
        print(reply);
    }
}
