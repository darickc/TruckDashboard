#include "ConsoleHost.h"

#include <Arduino.h>

#include "ConsoleCommands.h"

namespace {

void print(const char* s) { Serial.print(s); }

void prompt() { Serial.print("\r\n> "); }

/// Pause the gauge text the first time somebody types. It shares this UART, and
/// five lines a second is enough to scroll a reply away before it can be read.
/// One-shot, so a later `display on` sticks.
void muteDisplayOnFirstInput(ConsoleContext& ctx)
{
    if (ctx.autoMuted) {
        return;
    }
    ctx.autoMuted = true;
    if (ctx.displayEnabled != nullptr && *ctx.displayEnabled) {
        *ctx.displayEnabled = false;
        print("\r\n[display paused while you type — `display on` to resume]\r\n");
    }
}

void handleLine(ConsoleContext& ctx, char* line)
{
    const char* argv[console::kMaxArgs];
    bool truncated = false;
    const size_t argc = console::tokenize(line, argv, console::kMaxArgs, &truncated);
    if (argc == 0) {
        prompt();
        return;
    }
    if (truncated) {
        print("too many arguments\r\n");
        prompt();
        return;
    }

    console::ParsedCommand cmd;
    char err[160];
    if (!console::parse(argc, argv, ctx.unsafeAllowed, cmd, err, sizeof(err))) {
        print(err);
        print("\r\n");
        prompt();
        return;
    }

    // Console-local session state: neither of these reaches the OBD task, so
    // they need no mailbox round trip and cannot race it.
    switch (cmd.kind) {
    case console::ParsedCommand::Kind::Unsafe:
        ctx.unsafeAllowed = cmd.flag;
        print(cmd.flag ? "unsafe ON — raw write/clear/control services allowed "
                         "until reboot\r\n"
                       : "unsafe OFF\r\n");
        prompt();
        return;

    case console::ParsedCommand::Kind::Display:
        if (ctx.displayEnabled != nullptr) {
            *ctx.displayEnabled = cmd.flag;
        }
        print(cmd.flag ? "display ON\r\n" : "display OFF\r\n");
        prompt();
        return;

    default:
        break;
    }

    if (!ctx.mailbox->post(cmd)) {
        print("busy — a command is still running\r\n");
        prompt();
    }
}

} // namespace

void consoleTick(ConsoleContext& ctx)
{
    if (!ctx.greeted) {
        ctx.greeted = true;
        print("\r\nconsole ready — type `help`");
        prompt();
    }

    // Bounded per tick so a paste cannot monopolise the UI task.
    for (int i = 0; i < 256 && Serial.available() > 0; ++i) {
        const int c = Serial.read();
        if (c < 0) {
            break;
        }
        muteDisplayOnFirstInput(ctx);

        // Echo. `pio device monitor` does not echo locally, so without this the
        // operator is typing blind.
        const char ch = static_cast<char>(c);
        if (ch == '\b' || ch == 0x7F) {
            if (ctx.reader.length() > 0) {
                Serial.print("\b \b");
            }
        } else if (ch >= 0x20 && ch < 0x7F) {
            Serial.write(ch);
        }

        switch (ctx.reader.feed(ch)) {
        case console::LineReader::Event::Line:
            print("\r\n");
            handleLine(ctx, ctx.reader.line());
            break;
        case console::LineReader::Event::Overflow:
            print("\r\nline too long — ignored\r\n");
            prompt();
            break;
        case console::LineReader::Event::Empty:
            prompt();
            break;
        case console::LineReader::Event::None:
            break;
        }
    }

    if (const char* reply = ctx.mailbox->takeReply()) {
        print(reply);
        prompt();
    }
}
