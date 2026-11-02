// Unit tests: serial console — line reading, tokenization, the command
// grammar (including the raw deny-list), and the mailbox handshake that keeps
// the console off the OBD task's state.

#include <unity.h>

#include <cstdio>
#include <cstring>

#include "CommandMailbox.h"
#include "ConsoleCommands.h"
#include "ConsoleParser.h"

using namespace console;
using namespace obd;

extern "C" {
void setUp(void) {}
void tearDown(void) {}
}

// ---------------------------------------------------------------------------
// LineReader
// ---------------------------------------------------------------------------

/// Feed a whole string, returning the last event produced.
static LineReader::Event feedAll(LineReader& r, const char* s)
{
    LineReader::Event last = LineReader::Event::None;
    for (const char* p = s; *p != '\0'; ++p) {
        last = r.feed(*p);
    }
    return last;
}

static void test_line_reader_cr_lf_and_crlf()
{
    LineReader r;
    TEST_ASSERT_EQUAL(LineReader::Event::Line, feedAll(r, "pids\r"));
    TEST_ASSERT_EQUAL_STRING("pids", r.line());

    r.clear();
    TEST_ASSERT_EQUAL(LineReader::Event::Line, feedAll(r, "snap\n"));
    TEST_ASSERT_EQUAL_STRING("snap", r.line());

    // CRLF must produce ONE line and then an Empty, not two commands.
    r.clear();
    TEST_ASSERT_EQUAL(LineReader::Event::Line, feedAll(r, "help\r"));
    TEST_ASSERT_EQUAL_STRING("help", r.line());
    TEST_ASSERT_EQUAL(LineReader::Event::Empty, r.feed('\n'));
}

static void test_line_reader_backspace()
{
    LineReader r;
    TEST_ASSERT_EQUAL(LineReader::Event::Line, feedAll(r, "pidz\b\bds\r"));
    TEST_ASSERT_EQUAL_STRING("pids", r.line());

    // Backspace on an empty buffer must not underflow.
    r.clear();
    r.feed('\b');
    r.feed('\b');
    TEST_ASSERT_EQUAL(LineReader::Event::Line, feedAll(r, "on\r"));
    TEST_ASSERT_EQUAL_STRING("on", r.line());
}

static void test_line_reader_overflow_discards_whole_line()
{
    LineReader r;
    for (size_t i = 0; i < kMaxLine + 40; ++i) {
        TEST_ASSERT_EQUAL(LineReader::Event::None, r.feed('x'));
    }
    // The tail of an overlong line must not become the next command.
    TEST_ASSERT_EQUAL(LineReader::Event::Overflow, r.feed('\r'));

    TEST_ASSERT_EQUAL(LineReader::Event::Line, feedAll(r, "pids\r"));
    TEST_ASSERT_EQUAL_STRING("pids", r.line());
}

static void test_line_reader_empty_line()
{
    LineReader r;
    TEST_ASSERT_EQUAL(LineReader::Event::Empty, r.feed('\r'));
}

// ---------------------------------------------------------------------------
// tokenize
// ---------------------------------------------------------------------------

static void test_tokenize_basic_and_extra_whitespace()
{
    char line[] = "   probe   icp    10   ";
    const char* argv[kMaxArgs];
    bool truncated = true;
    const size_t argc = tokenize(line, argv, kMaxArgs, &truncated);

    TEST_ASSERT_EQUAL_UINT(3, argc);
    TEST_ASSERT_EQUAL_STRING("probe", argv[0]);
    TEST_ASSERT_EQUAL_STRING("icp", argv[1]);
    TEST_ASSERT_EQUAL_STRING("10", argv[2]);
    TEST_ASSERT_FALSE(truncated);
}

static void test_tokenize_tabs_and_empty()
{
    char tabs[] = "log\traw\ton";
    const char* argv[kMaxArgs];
    TEST_ASSERT_EQUAL_UINT(3, tokenize(tabs, argv, kMaxArgs, nullptr));
    TEST_ASSERT_EQUAL_STRING("raw", argv[1]);

    char blank[] = "     ";
    TEST_ASSERT_EQUAL_UINT(0, tokenize(blank, argv, kMaxArgs, nullptr));
}

static void test_tokenize_reports_truncation()
{
    char line[] = "a b c d e f g h i";
    const char* argv[kMaxArgs];
    bool truncated = false;
    const size_t argc = tokenize(line, argv, kMaxArgs, &truncated);
    TEST_ASSERT_EQUAL_UINT(kMaxArgs, argc);
    TEST_ASSERT_TRUE(truncated); // silently dropping arguments would be worse
}

// ---------------------------------------------------------------------------
// Scalar parsing
// ---------------------------------------------------------------------------

static void test_parse_uint_rejects_trailing_garbage()
{
    uint32_t v = 0;
    TEST_ASSERT_TRUE(parseUInt("42", v));
    TEST_ASSERT_EQUAL_UINT32(42, v);
    TEST_ASSERT_TRUE(parseUInt("0x7E8", v));
    TEST_ASSERT_EQUAL_UINT32(0x7E8, v);

    TEST_ASSERT_FALSE(parseUInt("5x", v));   // half-parsing "5" would be a trap
    TEST_ASSERT_FALSE(parseUInt("", v));
    TEST_ASSERT_FALSE(parseUInt("0x", v));
    TEST_ASSERT_FALSE(parseUInt("99999999999", v)); // overflow
}

static void test_parse_bool_and_case_insensitivity()
{
    bool b = false;
    TEST_ASSERT_TRUE(parseBool("ON", b));
    TEST_ASSERT_TRUE(b);
    TEST_ASSERT_TRUE(parseBool("off", b));
    TEST_ASSERT_FALSE(b);
    TEST_ASSERT_FALSE(parseBool("maybe", b));

    TEST_ASSERT_TRUE(equalsIgnoreCase("PiDs", "pids"));
    TEST_ASSERT_FALSE(equalsIgnoreCase("pid", "pids"));
    TEST_ASSERT_FALSE(equalsIgnoreCase(nullptr, "pids"));
}

// ---------------------------------------------------------------------------
// PID resolution
// ---------------------------------------------------------------------------

static void test_resolve_pid_by_index_key_and_short_name()
{
    const PidDefinition* byIndex = resolvePid("0");
    TEST_ASSERT_NOT_NULL(byIndex);
    TEST_ASSERT_EQUAL(kPidTable[0].key, byIndex->key);

    const PidDefinition* byKey = resolvePid("Icp");
    TEST_ASSERT_NOT_NULL(byKey);
    TEST_ASSERT_EQUAL(PidKey::Icp, byKey->key);

    // Short names come from the table ("HPOP" for ICP) and are case-insensitive.
    const PidDefinition* byShort = resolvePid("hpop");
    TEST_ASSERT_NOT_NULL(byShort);
    TEST_ASSERT_EQUAL(PidKey::Icp, byShort->key);

    TEST_ASSERT_NULL(resolvePid("nonsense"));
    TEST_ASSERT_NULL(resolvePid("999"));
    TEST_ASSERT_NULL(resolvePid(""));
}

static void test_pid_key_names_are_unique()
{
    for (size_t i = 0; i < kPidTableSize; ++i) {
        for (size_t j = i + 1; j < kPidTableSize; ++j) {
            TEST_ASSERT_FALSE(equalsIgnoreCase(pidKeyName(kPidTable[i].key),
                                               pidKeyName(kPidTable[j].key)));
        }
    }
}

// ---------------------------------------------------------------------------
// Command grammar
// ---------------------------------------------------------------------------

/// Parse a literal command line end to end.
static bool parseLine(const char* text, bool unsafeAllowed, ParsedCommand& out,
                      char* err, size_t errCap)
{
    char buf[kMaxLine + 1];
    std::snprintf(buf, sizeof(buf), "%s", text);
    const char* argv[kMaxArgs];
    const size_t argc = tokenize(buf, argv, kMaxArgs, nullptr);
    return parse(argc, argv, unsafeAllowed, out, err, errCap);
}

static void test_parse_simple_commands()
{
    ParsedCommand c;
    char err[160];

    TEST_ASSERT_TRUE(parseLine("help", false, c, err, sizeof(err)));
    TEST_ASSERT_EQUAL(ParsedCommand::Kind::Help, c.kind);

    TEST_ASSERT_TRUE(parseLine("PIDS", false, c, err, sizeof(err)));
    TEST_ASSERT_EQUAL(ParsedCommand::Kind::Pids, c.kind);

    TEST_ASSERT_TRUE(parseLine("snap", false, c, err, sizeof(err)));
    TEST_ASSERT_EQUAL(ParsedCommand::Kind::Snap, c.kind);

    TEST_ASSERT_TRUE(parseLine("stats", false, c, err, sizeof(err)));
    TEST_ASSERT_EQUAL(ParsedCommand::Kind::Stats, c.kind);

    TEST_ASSERT_TRUE(parseLine("stats reset", false, c, err, sizeof(err)));
    TEST_ASSERT_EQUAL(ParsedCommand::Kind::ResetStats, c.kind);
}

static void test_parse_unknown_command_explains_itself()
{
    ParsedCommand c;
    char err[160] = {0};
    TEST_ASSERT_FALSE(parseLine("frobnicate", false, c, err, sizeof(err)));
    TEST_ASSERT_TRUE(std::strstr(err, "frobnicate") != nullptr);
    TEST_ASSERT_TRUE(std::strstr(err, "help") != nullptr);
}

static void test_parse_on_off()
{
    ParsedCommand c;
    char err[160] = {0};

    TEST_ASSERT_TRUE(parseLine("on rpmsae", false, c, err, sizeof(err)));
    TEST_ASSERT_EQUAL(ParsedCommand::Kind::On, c.kind);
    TEST_ASSERT_EQUAL(PidKey::RpmSae, c.key);

    TEST_ASSERT_TRUE(parseLine("off Icp", false, c, err, sizeof(err)));
    TEST_ASSERT_EQUAL(ParsedCommand::Kind::Off, c.kind);
    TEST_ASSERT_EQUAL(PidKey::Icp, c.key);

    TEST_ASSERT_FALSE(parseLine("on", false, c, err, sizeof(err)));
    TEST_ASSERT_FALSE(parseLine("on wombat", false, c, err, sizeof(err)));
    TEST_ASSERT_TRUE(std::strstr(err, "wombat") != nullptr);
}

static void test_parse_probe_count_bounds()
{
    ParsedCommand c;
    char err[160] = {0};

    TEST_ASSERT_TRUE(parseLine("probe eot", false, c, err, sizeof(err)));
    TEST_ASSERT_EQUAL(ParsedCommand::Kind::Probe, c.kind);
    TEST_ASSERT_EQUAL(PidKey::Eot, c.key);
    TEST_ASSERT_EQUAL_UINT8(1, c.repeat); // defaults to a single request

    TEST_ASSERT_TRUE(parseLine("probe eot 10", false, c, err, sizeof(err)));
    TEST_ASSERT_EQUAL_UINT8(10, c.repeat);

    TEST_ASSERT_FALSE(parseLine("probe eot 0", false, c, err, sizeof(err)));
    TEST_ASSERT_FALSE(parseLine("probe eot 51", false, c, err, sizeof(err)));
    TEST_ASSERT_FALSE(parseLine("probe eot lots", false, c, err, sizeof(err)));
    TEST_ASSERT_FALSE(parseLine("probe", false, c, err, sizeof(err)));
}

static void test_parse_raw_joins_arguments()
{
    ParsedCommand c;
    char err[160] = {0};

    TEST_ASSERT_TRUE(parseLine("raw 221310", false, c, err, sizeof(err)));
    TEST_ASSERT_EQUAL(ParsedCommand::Kind::Raw, c.kind);
    TEST_ASSERT_EQUAL_STRING("221310", c.text);

    // The adapter ignores spaces in a request, so the operator may type either.
    TEST_ASSERT_TRUE(parseLine("raw 22 13 10", false, c, err, sizeof(err)));
    TEST_ASSERT_EQUAL_STRING("221310", c.text);

    TEST_ASSERT_TRUE(parseLine("raw ATSH 7E0", false, c, err, sizeof(err)));
    TEST_ASSERT_EQUAL_STRING("ATSH7E0", c.text);

    TEST_ASSERT_FALSE(parseLine("raw", false, c, err, sizeof(err)));
}

static void test_parse_raw_rejects_overlong()
{
    ParsedCommand c;
    char err[160] = {0};
    char line[128];
    std::snprintf(line, sizeof(line), "raw %s",
                  "0123456789012345678901234567890123456789");
    TEST_ASSERT_FALSE(parseLine(line, false, c, err, sizeof(err)));
}

// ---------------------------------------------------------------------------
// The raw deny-list. This is a live truck.
// ---------------------------------------------------------------------------

static void test_destructive_service_detection()
{
    TEST_ASSERT_TRUE(isDestructiveRawCommand("04"));         // clear DTCs
    TEST_ASSERT_TRUE(isDestructiveRawCommand("14FFFFFF"));   // clear diagnostics
    TEST_ASSERT_TRUE(isDestructiveRawCommand("2E1310AA"));   // write by DID
    TEST_ASSERT_TRUE(isDestructiveRawCommand("2F110301"));   // I/O control
    TEST_ASSERT_TRUE(isDestructiveRawCommand("310102"));     // routine control
    TEST_ASSERT_TRUE(isDestructiveRawCommand("3B1C00"));     // write by PID

    TEST_ASSERT_FALSE(isDestructiveRawCommand("010C"));      // read live data
    TEST_ASSERT_FALSE(isDestructiveRawCommand("221310"));    // read by DID
    TEST_ASSERT_FALSE(isDestructiveRawCommand("03"));        // read DTCs
    TEST_ASSERT_FALSE(isDestructiveRawCommand("ATZ"));       // adapter, not vehicle
    TEST_ASSERT_FALSE(isDestructiveRawCommand("atsh7E0"));
    TEST_ASSERT_FALSE(isDestructiveRawCommand("STDI"));
    TEST_ASSERT_FALSE(isDestructiveRawCommand(nullptr));
}

static void test_raw_denied_without_unsafe_and_allowed_with_it()
{
    ParsedCommand c;
    char err[160] = {0};

    TEST_ASSERT_FALSE(parseLine("raw 04", /*unsafeAllowed=*/false, c, err, sizeof(err)));
    TEST_ASSERT_TRUE(std::strstr(err, "unsafe on") != nullptr);

    TEST_ASSERT_TRUE(parseLine("raw 04", /*unsafeAllowed=*/true, c, err, sizeof(err)));
    TEST_ASSERT_EQUAL(ParsedCommand::Kind::Raw, c.kind);
    TEST_ASSERT_EQUAL_STRING("04", c.text);

    // Read services are never gated.
    TEST_ASSERT_TRUE(parseLine("raw 010C", false, c, err, sizeof(err)));
}

static void test_parse_display_toggle()
{
    ParsedCommand c;
    char err[160] = {0};

    TEST_ASSERT_TRUE(parseLine("display off", false, c, err, sizeof(err)));
    TEST_ASSERT_EQUAL(ParsedCommand::Kind::Display, c.kind);
    TEST_ASSERT_FALSE(c.flag);

    TEST_ASSERT_TRUE(parseLine("DISPLAY ON", false, c, err, sizeof(err)));
    TEST_ASSERT_TRUE(c.flag);

    TEST_ASSERT_FALSE(parseLine("display", false, c, err, sizeof(err)));
    TEST_ASSERT_FALSE(parseLine("display sometimes", false, c, err, sizeof(err)));
}

static void test_parse_unsafe_toggle()
{
    ParsedCommand c;
    char err[160] = {0};

    TEST_ASSERT_TRUE(parseLine("unsafe on", false, c, err, sizeof(err)));
    TEST_ASSERT_EQUAL(ParsedCommand::Kind::Unsafe, c.kind);
    TEST_ASSERT_TRUE(c.flag);

    TEST_ASSERT_TRUE(parseLine("unsafe off", true, c, err, sizeof(err)));
    TEST_ASSERT_FALSE(c.flag);

    TEST_ASSERT_FALSE(parseLine("unsafe", false, c, err, sizeof(err)));
    TEST_ASSERT_FALSE(parseLine("unsafe perhaps", false, c, err, sizeof(err)));
}

// ---------------------------------------------------------------------------
// log / hdr
// ---------------------------------------------------------------------------

static void test_parse_log_commands()
{
    ParsedCommand c;
    char err[160] = {0};

    TEST_ASSERT_TRUE(parseLine("log raw on", false, c, err, sizeof(err)));
    TEST_ASSERT_EQUAL(ParsedCommand::Kind::LogRaw, c.kind);
    TEST_ASSERT_TRUE(c.flag);

    TEST_ASSERT_TRUE(parseLine("log level 5", false, c, err, sizeof(err)));
    TEST_ASSERT_EQUAL(ParsedCommand::Kind::LogLevel, c.kind);
    TEST_ASSERT_EQUAL_UINT8(5, c.level);

    TEST_ASSERT_FALSE(parseLine("log level 9", false, c, err, sizeof(err)));
    TEST_ASSERT_FALSE(parseLine("log", false, c, err, sizeof(err)));
    TEST_ASSERT_FALSE(parseLine("log wibble on", false, c, err, sizeof(err)));
}

static void test_parse_header_override()
{
    ParsedCommand c;
    char err[160] = {0};

    TEST_ASSERT_TRUE(parseLine("hdr pcm 7E0", false, c, err, sizeof(err)));
    TEST_ASSERT_EQUAL(ParsedCommand::Kind::Header, c.kind);
    TEST_ASSERT_EQUAL(ObdModule::Pcm, c.module);
    TEST_ASSERT_EQUAL_STRING("7E0", c.header);
    TEST_ASSERT_EQUAL_STRING("", c.filter);

    TEST_ASSERT_TRUE(parseLine("hdr TCM 7E1 7E9", false, c, err, sizeof(err)));
    TEST_ASSERT_EQUAL(ObdModule::Tcm, c.module);
    TEST_ASSERT_EQUAL_STRING("7E1", c.header);
    TEST_ASSERT_EQUAL_STRING("7E9", c.filter);

    // `hdr clear` is signalled by an empty header.
    TEST_ASSERT_TRUE(parseLine("hdr clear", false, c, err, sizeof(err)));
    TEST_ASSERT_EQUAL(ParsedCommand::Kind::Header, c.kind);
    TEST_ASSERT_EQUAL_STRING("", c.header);

    TEST_ASSERT_FALSE(parseLine("hdr", false, c, err, sizeof(err)));
    TEST_ASSERT_FALSE(parseLine("hdr pcm", false, c, err, sizeof(err)));
    TEST_ASSERT_FALSE(parseLine("hdr wombat 7E0", false, c, err, sizeof(err)));
    TEST_ASSERT_FALSE(
        parseLine("hdr pcm 7E0777777777777", false, c, err, sizeof(err)));
}

// ---------------------------------------------------------------------------
// CommandMailbox
// ---------------------------------------------------------------------------

static ParsedCommand cmdOf(ParsedCommand::Kind kind)
{
    ParsedCommand c;
    c.kind = kind;
    return c;
}

static void test_mailbox_full_handshake()
{
    CommandMailbox mb;
    TEST_ASSERT_FALSE(mb.busy());
    TEST_ASSERT_NULL(mb.takeReply());

    TEST_ASSERT_TRUE(mb.post(cmdOf(ParsedCommand::Kind::Pids)));
    TEST_ASSERT_TRUE(mb.busy());

    ConsoleRequest req;
    TEST_ASSERT_TRUE(mb.take(req));
    TEST_ASSERT_EQUAL(ParsedCommand::Kind::Pids, req.cmd.kind);
    TEST_ASSERT_TRUE(mb.busy());
    TEST_ASSERT_FALSE(mb.take(req)); // already claimed

    mb.reply("line one");
    mb.replyf("value %d", 42);
    TEST_ASSERT_NULL(mb.takeReply()); // not finished yet
    mb.finish();

    TEST_ASSERT_TRUE(mb.isDone());
    const char* text = mb.takeReply();
    TEST_ASSERT_NOT_NULL(text);
    TEST_ASSERT_EQUAL_STRING("line one\nvalue 42\n", text);

    TEST_ASSERT_FALSE(mb.busy());
    TEST_ASSERT_NULL(mb.takeReply()); // only once
}

static void test_mailbox_rejects_second_post_while_busy()
{
    CommandMailbox mb;
    TEST_ASSERT_TRUE(mb.post(cmdOf(ParsedCommand::Kind::Pids)));
    // Losing the operator's command silently would be worse than saying "busy".
    TEST_ASSERT_FALSE(mb.post(cmdOf(ParsedCommand::Kind::Snap)));

    ConsoleRequest req;
    mb.take(req);
    TEST_ASSERT_FALSE(mb.post(cmdOf(ParsedCommand::Kind::Snap)));

    mb.finish();
    TEST_ASSERT_FALSE(mb.post(cmdOf(ParsedCommand::Kind::Snap))); // reply unread
    mb.takeReply();
    TEST_ASSERT_TRUE(mb.post(cmdOf(ParsedCommand::Kind::Snap)));
}

static void test_mailbox_take_requires_a_pending_request()
{
    CommandMailbox mb;
    ConsoleRequest req;
    TEST_ASSERT_FALSE(mb.take(req));
}

static void test_mailbox_reply_is_cleared_between_commands()
{
    CommandMailbox mb;
    ConsoleRequest req;

    mb.post(cmdOf(ParsedCommand::Kind::Pids));
    mb.take(req);
    mb.reply("first");
    mb.finish();
    TEST_ASSERT_EQUAL_STRING("first\n", mb.takeReply());

    mb.post(cmdOf(ParsedCommand::Kind::Snap));
    mb.take(req);
    mb.reply("second");
    mb.finish();
    TEST_ASSERT_EQUAL_STRING("second\n", mb.takeReply()); // no leftovers
}

static void test_mailbox_truncation_is_announced()
{
    CommandMailbox mb;
    ConsoleRequest req;
    mb.post(cmdOf(ParsedCommand::Kind::Pids));
    mb.take(req);

    char big[160];
    std::memset(big, 'x', sizeof(big) - 1);
    big[sizeof(big) - 1] = '\0';
    for (int i = 0; i < 200; ++i) {
        mb.reply(big);
    }
    TEST_ASSERT_TRUE(mb.replyTruncated());
    mb.finish();

    const char* text = mb.takeReply();
    TEST_ASSERT_NOT_NULL(text);
    // A clipped dump must not read as a complete one.
    TEST_ASSERT_TRUE(std::strstr(text, "[output truncated]") != nullptr);
    TEST_ASSERT_TRUE(std::strlen(text) < kReplyCapacity);
}

int main(int, char**)
{
    UNITY_BEGIN();
    RUN_TEST(test_line_reader_cr_lf_and_crlf);
    RUN_TEST(test_line_reader_backspace);
    RUN_TEST(test_line_reader_overflow_discards_whole_line);
    RUN_TEST(test_line_reader_empty_line);
    RUN_TEST(test_tokenize_basic_and_extra_whitespace);
    RUN_TEST(test_tokenize_tabs_and_empty);
    RUN_TEST(test_tokenize_reports_truncation);
    RUN_TEST(test_parse_uint_rejects_trailing_garbage);
    RUN_TEST(test_parse_bool_and_case_insensitivity);
    RUN_TEST(test_resolve_pid_by_index_key_and_short_name);
    RUN_TEST(test_pid_key_names_are_unique);
    RUN_TEST(test_parse_simple_commands);
    RUN_TEST(test_parse_unknown_command_explains_itself);
    RUN_TEST(test_parse_on_off);
    RUN_TEST(test_parse_probe_count_bounds);
    RUN_TEST(test_parse_raw_joins_arguments);
    RUN_TEST(test_parse_raw_rejects_overlong);
    RUN_TEST(test_destructive_service_detection);
    RUN_TEST(test_raw_denied_without_unsafe_and_allowed_with_it);
    RUN_TEST(test_parse_display_toggle);
    RUN_TEST(test_parse_unsafe_toggle);
    RUN_TEST(test_parse_log_commands);
    RUN_TEST(test_parse_header_override);
    RUN_TEST(test_mailbox_full_handshake);
    RUN_TEST(test_mailbox_rejects_second_post_while_busy);
    RUN_TEST(test_mailbox_take_requires_a_pending_request);
    RUN_TEST(test_mailbox_reply_is_cleared_between_commands);
    RUN_TEST(test_mailbox_truncation_is_announced);
    return UNITY_END();
}
