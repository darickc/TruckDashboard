// Integration tests: ConsoleExecutor driving a real ElmClient over a scripted
// MockTransport.
//
// `probe` and `raw` are the two commands the on-truck verification session
// actually runs, so they are tested end to end: command in through the mailbox,
// adapter traffic out, formatted evidence back.

#include <unity.h>

#include <cstdio>
#include <cstring>

#include "../mocks/MockTransport.h"
#include "CommandMailbox.h"
#include "ConsoleCommands.h"
#include "ConsoleExecutor.h"
#include "ConsoleParser.h"
#include "ElmClient.h"
#include "PidScheduler.h"
#include "VehicleData.h"

using namespace obd;
using namespace console;

extern "C" {
void setUp(void) {}
void tearDown(void) {}
}

uint32_t MockTransport::s_now = 0;

static const char* kInit[] = {"ATE0", "ATL0", "ATS0", "ATH1", "ATAT1", "ATSP0"};

static const MockTransport::Step kBootSteps[] = {
    {"ATZ", "\r\rELM327 v1.4b\r\r>", 50},
    {"ATE0", "ATE0\rOK\r\r>", 5},
    {"ATL0", "OK\r\r>", 5},
    {"ATS0", "OK\r\r>", 5},
    {"ATH1", "OK\r\r>", 5},
    {"ATAT1", "OK\r\r>", 5},
    {"ATSP0", "OK\r\r>", 5},
};
static constexpr size_t kBootStepCount = sizeof(kBootSteps) / sizeof(kBootSteps[0]);

/// Everything one test needs, wired the way main.cpp wires it.
struct Fixture {
    MockTransport mock;
    VehicleData data;
    PidScheduler scheduler;
    CommandMailbox mailbox;
    ElmClient elm;
    ConsoleExecutor exec;
    MockTransport::Step scratch[24];

    Fixture()
        : elm(mock, MockTransport::nowFn, makeConfig()),
          exec(elm, scheduler, data, mailbox, MockTransport::nowFn)
    {
        MockTransport::s_now = 0;
        exec.begin();
        elm.setResultHandler(&Fixture::onResult, this);
        scheduler.begin(kPidTable, kPidTableSize, nullptr, 0);
    }

    static ElmConfig makeConfig()
    {
        ElmConfig c;
        c.initCommands = kInit;
        c.initCommandCount = 6;
        return c;
    }

    /// Mirrors obdOnResult in src/ObdTask.cpp: the console sees the result
    /// first, then the scheduler folds it into its statistics. The order
    /// matters — `probe`'s summary reads the spread back out of the scheduler.
    static void onResult(void* ctx, const PidDefinition& pid, const ElmResponse& rsp)
    {
        auto* self = static_cast<Fixture*>(ctx);
        self->exec.onResult(pid, rsp);
        self->scheduler.onResult(pid, rsp, MockTransport::s_now);
    }

    void boot(const MockTransport::Step* extra, size_t extraCount)
    {
        size_t n = 0;
        for (; n < kBootStepCount; ++n) scratch[n] = kBootSteps[n];
        for (size_t i = 0; i < extraCount; ++i) scratch[n++] = extra[i];
        mock.setScript(scratch, n);
        elm.begin();
        pump(300);
        TEST_ASSERT_EQUAL_STRING("", mock.mismatch().c_str());
        TEST_ASSERT_EQUAL(ElmState::Idle, elm.state());
    }

    /// Advance virtual time 1 ms at a time, ticking client and executor in the
    /// same order ObdTask does.
    void pump(uint32_t ms)
    {
        for (uint32_t i = 0; i < ms; ++i) {
            mock.advance(1);
            exec.tick();
            elm.tick();
            if (!exec.busy() && elm.state() == ElmState::Idle) {
                if (const PidDefinition* pid = scheduler.next(MockTransport::s_now)) {
                    elm.submit(*pid);
                }
            }
        }
    }

    /// Post a command line and run until the reply is ready.
    const char* run(const char* line, uint32_t maxMs = 30000)
    {
        char buf[128];
        std::snprintf(buf, sizeof(buf), "%s", line);
        const char* argv[kMaxArgs];
        const size_t argc = tokenize(buf, argv, kMaxArgs, nullptr);
        ParsedCommand cmd;
        char err[160];
        if (!parse(argc, argv, /*unsafeAllowed=*/false, cmd, err, sizeof(err))) {
            TEST_FAIL_MESSAGE(err);
        }
        TEST_ASSERT_TRUE(mailbox.post(cmd));
        for (uint32_t elapsed = 0; elapsed < maxMs && !mailbox.isDone(); ++elapsed) {
            pump(1);
        }
        const char* reply = mailbox.takeReply();
        TEST_ASSERT_NOT_NULL_MESSAGE(reply, "command never completed");
        return reply;
    }
};

static void assertContains(const char* haystack, const char* needle)
{
    if (std::strstr(haystack, needle) == nullptr) {
        char msg[512];
        std::snprintf(msg, sizeof(msg), "expected to find '%s' in:\n%s", needle,
                      haystack);
        TEST_FAIL_MESSAGE(msg);
    }
}

// ---------------------------------------------------------------------------
// Immediate commands
// ---------------------------------------------------------------------------

static void test_pids_lists_the_table_and_marks_enabled()
{
    Fixture f;
    f.boot(nullptr, 0);
    f.scheduler.add(*findPid(PidKey::RpmSae), 0);

    const char* out = f.run("pids");
    assertContains(out, "RpmSae");
    assertContains(out, "010C");
    assertContains(out, "Icp");
    assertContains(out, "221446");
    assertContains(out, "verified");
    assertContains(out, "unverified");
    // The TCM rows must advertise that their header is not known.
    assertContains(out, "UNVERIF");
    assertContains(out, "* = polling now");
}

static void test_on_and_off_change_the_polled_set()
{
    Fixture f;
    f.boot(nullptr, 0);

    assertContains(f.run("on icp"), "polling");
    TEST_ASSERT_TRUE(f.scheduler.isEnabled(PidKey::Icp));

    assertContains(f.run("off icp"), "stopped polling");
    TEST_ASSERT_FALSE(f.scheduler.isEnabled(PidKey::Icp));

    assertContains(f.run("off icp"), "not being polled");
}

static void test_on_refuses_a_pid_with_an_unverified_header()
{
    Fixture f;
    f.boot(nullptr, 0);
    clearModuleAddressingOverrides();

    // TransTemp2 lives on ObdModule::Tcm, whose header is a documented TODO.
    assertContains(f.run("on transtemp2"), "refused");
    TEST_ASSERT_FALSE(f.scheduler.isEnabled(PidKey::TransTemp2));
}

static void test_stats_reports_counters_after_a_probe()
{
    Fixture f;
    const MockTransport::Step extra[] = {
        {"010C", "7E804410C1AF8\r\r>", 30},
    };
    f.boot(extra, 1);
    f.scheduler.add(*findPid(PidKey::RpmSae), 0);

    f.run("probe rpmsae 1");
    const char* out = f.run("stats");
    assertContains(out, "RpmSae");
    assertContains(out, "addressing overhead");
    assertContains(out, "requested rate");
}

static void test_snap_lists_every_channel()
{
    Fixture f;
    f.boot(nullptr, 0);
    const char* out = f.run("snap");
    assertContains(out, "RPM");
    assertContains(out, "ICP");
    assertContains(out, "---"); // nothing has ever been valid yet
}

// ---------------------------------------------------------------------------
// probe — the verification workhorse
// ---------------------------------------------------------------------------

static void test_probe_reports_responder_value_and_latency()
{
    Fixture f;
    const MockTransport::Step extra[] = {
        {"010C", "7E804410C1AF8\r\r>", 30},
    };
    f.boot(extra, 1);

    const char* out = f.run("probe rpmsae 1");
    assertContains(out, "probe RpmSae");
    assertContains(out, "7E8 1AF8"); // who answered, and with what
    assertContains(out, "1726.00"); // decoded: 0x1AF8 / 4
    assertContains(out, "rpm");
    assertContains(out, "1/1 ok");
    TEST_ASSERT_EQUAL_STRING("", f.mock.mismatch().c_str());
}

static void test_probe_repeats_and_summarises()
{
    Fixture f;
    const MockTransport::Step extra[] = {
        {"010C", "7E804410C1AF8\r\r>", 30},
        {"010C", "7E804410C1AF8\r\r>", 30},
        {"010C", "7E804410C1AF8\r\r>", 30},
    };
    f.boot(extra, 3);

    const char* out = f.run("probe rpmsae 3");
    assertContains(out, "  #1");
    assertContains(out, "  #2");
    assertContains(out, "  #3");
    assertContains(out, "3/3 ok");
    TEST_ASSERT_EQUAL_STRING("", f.mock.mismatch().c_str());
}

static void test_probe_shows_every_responder_side_by_side()
{
    Fixture f;
    // Both modules answer 2211B3 (gear), which is still unpinned — first-wins
    // would have picked one silently. Both must appear, decoded, so the operator
    // can see whether they mean the same thing.
    const MockTransport::Step extra[] = {
        {"2211B3", "7E8046211B308\r" "7E9046211B300\r\r>", 30},
    };
    f.boot(extra, 1);
    f.scheduler.add(*findPid(PidKey::Gear1), 0);

    const char* out = f.run("probe gear1 1");
    assertContains(out, "7E8 08");
    assertContains(out, "7E9 00");
    assertContains(out, "4.00"); // A/2
    assertContains(out, "0.00");
    assertContains(out, "2 ECUs answered");
    assertContains(out, "max spread 4.00");
    assertContains(out, "UNVERIFIED definition");
}

static void test_pinned_pid_ignores_the_module_that_does_not_own_it()
{
    Fixture f;
    // TransTemp1 is pinned to 7E9 after the 2026-08-09 session: the PCM answers
    // 7F 22 31 (requestOutOfRange) because it does not have the DID. That frame
    // must be dropped before it can be parsed as a negative response.
    const MockTransport::Step extra[] = {
        {"221674", "7E8037F2231\r" "7E9056216740413\r\r>", 30},
    };
    f.boot(extra, 1);
    f.scheduler.add(*findPid(PidKey::TransTemp1), 0);

    const char* out = f.run("probe transtemp1 1");
    assertContains(out, "7E9 0413");
    assertContains(out, "130.38"); // 0x0413 = 1043, /8 = 130.375
    TEST_ASSERT_NULL(std::strstr(out, "7E8"));
    // A single accepted responder: no spread line, nothing to compare.
    TEST_ASSERT_NULL(std::strstr(out, "ECUs answered"));
}

static void test_probe_reports_a_small_spread_as_agreement()
{
    Fixture f;
    // The RPM case that used to shout RESPONDER CONFLICT on every sample:
    // 7E9=0AC4 is 689.00 rpm, 7E8=0AC2 is 688.50. The summary must show a spread
    // of half an rpm, not a warning.
    const MockTransport::Step extra[] = {
        {"010C", "7E904410C0AC4\r7E804410C0AC2\r\r>", 30},
        {"010C", "7E904410C0AB8\r7E804410C0ABA\r\r>", 30},
    };
    f.boot(extra, 2);
    f.scheduler.add(*findPid(PidKey::RpmSae), 0);

    const char* out = f.run("probe rpmsae 2");
    assertContains(out, "7E9 0AC4");
    assertContains(out, "689.00");
    assertContains(out, "7E8 0AC2");
    assertContains(out, "688.50");
    assertContains(out, "2 ECUs answered, max spread 0.50 rpm");
    // Nothing anywhere should call this a conflict.
    TEST_ASSERT_NULL(std::strstr(out, "DISAGREE"));
    TEST_ASSERT_NULL(std::strstr(out, "CONFLICT"));
}

static void test_probe_reports_no_data()
{
    Fixture f;
    const MockTransport::Step extra[] = {
        {"221446", "NO DATA\r\r>", 30},
    };
    f.boot(extra, 1);

    const char* out = f.run("probe icp 1");
    assertContains(out, "NO_DATA");
    assertContains(out, "0/1 ok");
}

static void test_probe_refuses_unverified_module_and_says_how_to_proceed()
{
    Fixture f;
    f.boot(nullptr, 0);
    clearModuleAddressingOverrides();

    const char* out = f.run("probe transtemp2 1");
    assertContains(out, "refused");
    assertContains(out, "UNVERIFIED");
    assertContains(out, "hdr"); // tells the operator how to try a candidate
}

// ---------------------------------------------------------------------------
// raw — trying adapter commands without a reflash
// ---------------------------------------------------------------------------

static void test_raw_echoes_every_reply_line_verbatim()
{
    Fixture f;
    const MockTransport::Step extra[] = {
        {"ATDPN", "6\r\r>", 20},
    };
    f.boot(extra, 1);

    const char* out = f.run("raw ATDPN");
    assertContains(out, "TX> ATDPN");
    assertContains(out, "  6"); // the protocol number, uninterpreted
    TEST_ASSERT_EQUAL_STRING("", f.mock.mismatch().c_str());
}

static void test_raw_invalidates_the_addressing_cache()
{
    Fixture f;
    // A raw command may have been ATZ/ATSH/ATCRA/ATSP. Afterwards the adapter's
    // addressing is UNKNOWN — note that `raw ATSH 7E0` leaves it on 7E0, not on
    // the ATZ default, so assuming 7DF here would be a guess and a wrong one.
    // The next request must therefore re-establish BOTH header and filter.
    const MockTransport::Step extra[] = {
        {"010C", "7E804410C1AF8\r\r>", 20},  // caches "7DF", no filter
        {"ATSH7E0", "OK\r\r>", 20},          // raw: adapter now on a different header
        {"ATSH7DF", "OK\r\r>", 5},           // THE ASSERTION: header re-sent...
        {"ATCRA", "OK\r\r>", 5},             // ...and the filter explicitly cleared
        {"010C", "7E804410C1AF8\r\r>", 20},
    };
    f.boot(extra, 5);

    f.run("probe rpmsae 1");
    const char* out = f.run("raw ATSH 7E0");
    assertContains(out, "addressing cache invalidated");

    f.run("probe rpmsae 1");
    TEST_ASSERT_EQUAL_STRING("", f.mock.mismatch().c_str());
}

static void test_raw_waits_for_an_idle_adapter_while_polling()
{
    Fixture f;
    // RPM at a 100 ms interval against a 60 ms round trip leaves the adapter
    // busy nearly all the time — the state the truck is actually in. `raw` used
    // to look once, see AWAITING and give up, so it could never run at all.
    const MockTransport::Step extra[] = {
        {"010C", "7E804410C1AF8\r\r>", 60},
        {"ATDPN", "6\r\r>", 20},
    };
    f.boot(extra, 2);
    f.scheduler.add(*findPid(PidKey::RpmSae), 0);

    // Get a poll in flight, then submit the raw command mid-request.
    f.pump(10);
    TEST_ASSERT_EQUAL(ElmState::AwaitingResponse, f.elm.state());

    const char* out = f.run("raw ATDPN");
    assertContains(out, "TX> ATDPN");
    assertContains(out, "  6");
    TEST_ASSERT_EQUAL_STRING("", f.mock.mismatch().c_str());
    TEST_ASSERT_TRUE(f.mock.scriptDone());
}

static void test_raw_gives_up_if_the_adapter_never_goes_idle()
{
    Fixture f;
    const MockTransport::Step extra[] = {
        {"010C", "", 0}, // adapter goes silent mid-request
    };
    f.boot(extra, 1);
    f.scheduler.add(*findPid(PidKey::RpmSae), 0);
    f.pump(10);

    // Waiting forever would hang the console; it must say what happened.
    const char* out = f.run("raw ATDPN", 20000);
    assertContains(out, "not sent");
}

static void test_raw_reports_no_reply()
{
    Fixture f;
    const MockTransport::Step extra[] = {
        {"ATWIBBLE", "", 0}, // adapter says nothing at all
    };
    f.boot(extra, 1);

    const char* out = f.run("raw ATWIBBLE");
    assertContains(out, "<no reply>");
}

// ---------------------------------------------------------------------------
// hdr — runtime addressing candidates
// ---------------------------------------------------------------------------

static void test_hdr_override_makes_a_refused_pid_probeable()
{
    Fixture f;
    clearModuleAddressingOverrides();
    const MockTransport::Step extra[] = {
        {"ATSH7E1", "OK\r\r>", 5},
        {"ATCRA7E9", "OK\r\r>", 5},
        {"221674", "7E905621674" "0A2C\r\r>", 30},
    };
    f.boot(extra, 3);

    // Before: the TCM header is a TODO, so the request is refused outright.
    assertContains(f.run("probe transtemp2 1"), "refused");

    // The operator supplies a candidate. It is loudly labelled as such.
    const char* set = f.run("hdr tcm 7E1 7E9");
    assertContains(set, "ATSH7E1");
    assertContains(set, "CANDIDATE");
    assertContains(set, "dies on reboot");

    // After: the same PID goes out, on the candidate addressing.
    const char* out = f.run("probe transtemp2 1");
    assertContains(out, "7E9 0A2C");
    TEST_ASSERT_EQUAL_STRING("", f.mock.mismatch().c_str());

    // And it can be taken back.
    assertContains(f.run("hdr clear"), "dropped");
    TEST_ASSERT_FALSE(hasModuleAddressingOverride(ObdModule::Tcm));
    clearModuleAddressingOverrides();
}

// ---------------------------------------------------------------------------
// Console requests preempt scheduled polling
// ---------------------------------------------------------------------------

static void test_console_command_takes_priority_over_the_poll_rotation()
{
    Fixture f;
    // The mock enforces write ORDER, so this script IS the assertion: the
    // probe's 221446 must go out before the scheduler's 010C, even though RPM
    // is priority 0 and already overdue.
    const MockTransport::Step extra[] = {
        {"221446", "7E805621446" "1234\r\r>", 30},
        {"010C", "7E804410C1AF8\r\r>", 20}, // polling resumes afterwards
    };
    f.boot(extra, 2);
    f.scheduler.add(*findPid(PidKey::RpmSae), 0); // due immediately, prio 0

    const char* out = f.run("probe icp 1");
    assertContains(out, "probe Icp");
    f.pump(60); // one RPM poll's worth (its interval is 100 ms)
    TEST_ASSERT_EQUAL_STRING("", f.mock.mismatch().c_str());
    TEST_ASSERT_TRUE(f.mock.scriptDone()); // the 010C really did follow
}

int main(int, char**)
{
    UNITY_BEGIN();
    RUN_TEST(test_pids_lists_the_table_and_marks_enabled);
    RUN_TEST(test_on_and_off_change_the_polled_set);
    RUN_TEST(test_on_refuses_a_pid_with_an_unverified_header);
    RUN_TEST(test_stats_reports_counters_after_a_probe);
    RUN_TEST(test_snap_lists_every_channel);
    RUN_TEST(test_probe_reports_responder_value_and_latency);
    RUN_TEST(test_probe_repeats_and_summarises);
    RUN_TEST(test_probe_shows_every_responder_side_by_side);
    RUN_TEST(test_pinned_pid_ignores_the_module_that_does_not_own_it);
    RUN_TEST(test_probe_reports_a_small_spread_as_agreement);
    RUN_TEST(test_probe_reports_no_data);
    RUN_TEST(test_probe_refuses_unverified_module_and_says_how_to_proceed);
    RUN_TEST(test_raw_echoes_every_reply_line_verbatim);
    RUN_TEST(test_raw_waits_for_an_idle_adapter_while_polling);
    RUN_TEST(test_raw_gives_up_if_the_adapter_never_goes_idle);
    RUN_TEST(test_raw_invalidates_the_addressing_cache);
    RUN_TEST(test_raw_reports_no_reply);
    RUN_TEST(test_hdr_override_makes_a_refused_pid_probeable);
    RUN_TEST(test_console_command_takes_priority_over_the_poll_rotation);
    return UNITY_END();
}
