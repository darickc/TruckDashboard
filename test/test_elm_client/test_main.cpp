// Integration tests: full ElmClient state machine over a scripted
// MockTransport with a virtual clock — init sequence, request/response,
// NO DATA, STOPPED, negative responses, timeout recovery, transport loss.

#include <unity.h>

#include <cstring>

#include "../mocks/MockTransport.h"
#include "ElmClient.h"
#include "PidDefs.h"

using namespace obd;

extern "C" {
void setUp(void) {}
void tearDown(void) {}
}

uint32_t MockTransport::s_now = 0;

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------
static const char* kInit[] = {"ATE0", "ATL0", "ATS0", "ATH1", "ATAT1", "ATSP0"};

static ElmConfig makeConfig()
{
    ElmConfig c;
    c.initCommands = kInit;
    c.initCommandCount = 6;
    return c;
}

struct ResultCapture {
    int count = 0;
    ElmResult last = ElmResult::Error;
    uint8_t payload[64] = {0};
    size_t len = 0;
    uint16_t responderId = 0;
    uint8_t responderCount = 0;
    bool conflict = false;
    uint16_t latencyMs = 0;

    static void handler(void* ctx, const PidDefinition&, const ElmResponse& rsp)
    {
        auto* self = static_cast<ResultCapture*>(ctx);
        ++self->count;
        self->last = rsp.result;
        self->len = rsp.len;
        self->responderId = rsp.responderId;
        self->responderCount = rsp.responderCount;
        self->conflict = rsp.responderConflict;
        self->latencyMs = rsp.latencyMs;
        if (rsp.payload != nullptr && rsp.len > 0 && rsp.len <= sizeof(self->payload)) {
            std::memcpy(self->payload, rsp.payload, rsp.len);
        }
    }
};

/// A copy of a table PID with responder/addressing tweaks, so tests can express
/// setups the shipped table deliberately does not contain yet.
static PidDefinition variantOf(PidKey key, uint16_t expectedResponder,
                               ObdModule module, uint8_t expectedResponses = 0)
{
    PidDefinition d = *findPid(key);
    d.expectedResponder = expectedResponder;
    d.module = module;
    d.expectedResponses = expectedResponses;
    return d;
}

/// Advance virtual time 1 ms at a time, ticking the client.
static void pump(ElmClient& elm, MockTransport& mock, uint32_t ms)
{
    for (uint32_t i = 0; i < ms; ++i) {
        mock.advance(1);
        elm.tick();
    }
}

// The standard boot script: ATZ + full init, everything happy.
static const MockTransport::Step kBootSteps[] = {
    {"ATZ", "\r\rELM327 v1.4b\r\r>", 50},
    {"ATE0", "ATE0\rOK\r\r>", 5}, // echo still on for this one command
    {"ATL0", "OK\r\r>", 5},
    {"ATS0", "OK\r\r>", 5},
    {"ATH1", "OK\r\r>", 5},
    {"ATAT1", "OK\r\r>", 5},
    {"ATSP0", "OK\r\r>", 5},
};
static constexpr size_t kBootStepCount = sizeof(kBootSteps) / sizeof(kBootSteps[0]);

/// Run boot + init, assert the client reaches Idle.
static void boot(ElmClient& elm, MockTransport& mock, const MockTransport::Step* extra,
                 size_t extraCount, MockTransport::Step* scratch)
{
    size_t n = 0;
    for (; n < kBootStepCount; ++n) scratch[n] = kBootSteps[n];
    for (size_t i = 0; i < extraCount; ++i) scratch[n++] = extra[i];
    mock.setScript(scratch, n);

    elm.begin();
    pump(elm, mock, 200);
    TEST_ASSERT_EQUAL_STRING("", mock.mismatch().c_str());
    TEST_ASSERT_EQUAL(ElmState::Idle, elm.state());
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
static void test_init_sequence_reaches_idle()
{
    MockTransport::s_now = 0;
    MockTransport mock;
    ElmClient elm(mock, MockTransport::nowFn, makeConfig());
    MockTransport::Step scratch[16];
    boot(elm, mock, nullptr, 0, scratch);
    TEST_ASSERT_EQUAL_STRING("ELM327 v1.4b", elm.adapterId());
}

static void test_rpm_request_happy_path()
{
    MockTransport::s_now = 0;
    MockTransport mock;
    ElmClient elm(mock, MockTransport::nowFn, makeConfig());
    ResultCapture cap;
    elm.setResultHandler(ResultCapture::handler, &cap);

    const MockTransport::Step extra[] = {
        // First data request: adapter searches for the protocol first.
        {"010C", "SEARCHING...\r7E804410C1AF8\r\r>", 300},
    };
    MockTransport::Step scratch[16];
    boot(elm, mock, extra, 1, scratch);

    const PidDefinition* rpm = findPid(PidKey::RpmSae);
    TEST_ASSERT_NOT_NULL(rpm);
    TEST_ASSERT_TRUE(elm.submit(*rpm));
    TEST_ASSERT_EQUAL(ElmState::AwaitingResponse, elm.state());
    TEST_ASSERT_FALSE(elm.submit(*rpm)); // no double submit

    pump(elm, mock, 400);
    TEST_ASSERT_EQUAL_STRING("", mock.mismatch().c_str());
    TEST_ASSERT_EQUAL_INT(1, cap.count);
    TEST_ASSERT_EQUAL(ElmResult::Ok, cap.last);
    // Payload is echo-stripped: raw bytes A=0x1A B=0xF8 -> 1726 rpm.
    TEST_ASSERT_EQUAL_UINT(2, cap.len);
    TEST_ASSERT_EQUAL_HEX8(0x1A, cap.payload[0]);
    TEST_ASSERT_EQUAL_HEX8(0xF8, cap.payload[1]);
    TEST_ASSERT_EQUAL(ElmState::Idle, elm.state());
}

static void test_no_data_and_stopped()
{
    MockTransport::s_now = 0;
    MockTransport mock;
    ElmClient elm(mock, MockTransport::nowFn, makeConfig());
    ResultCapture cap;
    elm.setResultHandler(ResultCapture::handler, &cap);

    const MockTransport::Step extra[] = {
        {"010C", "7E804410C1AF8\r\r>", 20}, // first request OK (clears SEARCHING window)
        {"010C", "NO DATA\r\r>", 20},
        {"010C", "STOPPED\r\r>", 20},
    };
    MockTransport::Step scratch[16];
    boot(elm, mock, extra, 3, scratch);

    const PidDefinition* rpm = findPid(PidKey::RpmSae);
    TEST_ASSERT_TRUE(elm.submit(*rpm));
    pump(elm, mock, 100);
    TEST_ASSERT_EQUAL(ElmResult::Ok, cap.last);

    TEST_ASSERT_TRUE(elm.submit(*rpm));
    pump(elm, mock, 100);
    TEST_ASSERT_EQUAL(ElmResult::NoData, cap.last);
    TEST_ASSERT_EQUAL(ElmState::Idle, elm.state()); // NO DATA is not fatal

    TEST_ASSERT_TRUE(elm.submit(*rpm));
    pump(elm, mock, 100);
    TEST_ASSERT_EQUAL(ElmResult::Stopped, cap.last);
    TEST_ASSERT_EQUAL(ElmState::Idle, elm.state());
    TEST_ASSERT_EQUAL_STRING("", mock.mismatch().c_str());
}

static void test_negative_response_is_error()
{
    MockTransport::s_now = 0;
    MockTransport mock;
    ElmClient elm(mock, MockTransport::nowFn, makeConfig());
    ResultCapture cap;
    elm.setResultHandler(ResultCapture::handler, &cap);

    const MockTransport::Step extra[] = {
        // 7F 22 31 = negative response, requestOutOfRange.
        {"221310", "7E8037F2231\r\r>", 20},
    };
    MockTransport::Step scratch[16];
    boot(elm, mock, extra, 1, scratch);

    const PidDefinition* eot = findPid(PidKey::Eot);
    TEST_ASSERT_TRUE(elm.submit(*eot));
    pump(elm, mock, 12000); // inside the first-request SEARCHING window
    TEST_ASSERT_EQUAL(ElmResult::Error, cap.last);
    TEST_ASSERT_EQUAL_STRING("", mock.mismatch().c_str());
}

static void test_timeout_then_recovery()
{
    MockTransport::s_now = 0;
    MockTransport mock;
    ElmClient elm(mock, MockTransport::nowFn, makeConfig());
    ResultCapture cap;
    elm.setResultHandler(ResultCapture::handler, &cap);

    const MockTransport::Step extra[] = {
        {"010C", "7E804410C1AF8\r\r>", 20}, // first request OK
        {"010C", "", 0},                    // adapter goes silent
        {"", "\r>", 20},                    // recovery CR gets a prompt back
    };
    MockTransport::Step scratch[16];
    boot(elm, mock, extra, 3, scratch);

    const PidDefinition* rpm = findPid(PidKey::RpmSae);
    TEST_ASSERT_TRUE(elm.submit(*rpm));
    pump(elm, mock, 100);
    TEST_ASSERT_EQUAL(ElmResult::Ok, cap.last);

    TEST_ASSERT_TRUE(elm.submit(*rpm));
    pump(elm, mock, 600); // past the 500 ms per-PID timeout
    TEST_ASSERT_EQUAL(ElmResult::Timeout, cap.last);
    pump(elm, mock, 100); // recovery prompt arrives
    TEST_ASSERT_EQUAL(ElmState::Idle, elm.state());
    TEST_ASSERT_EQUAL_STRING("", mock.mismatch().c_str());
}

static void test_transport_loss_and_reinit()
{
    MockTransport::s_now = 0;
    MockTransport mock;
    ElmClient elm(mock, MockTransport::nowFn, makeConfig());
    ResultCapture cap;
    elm.setResultHandler(ResultCapture::handler, &cap);

    MockTransport::Step scratch[16];
    boot(elm, mock, nullptr, 0, scratch);

    // Link drops mid-flight.
    const PidDefinition* rpm = findPid(PidKey::RpmSae);
    TEST_ASSERT_TRUE(elm.submit(*rpm));
    mock.dropLink();
    elm.onTransportLost();
    TEST_ASSERT_EQUAL(ElmState::Offline, elm.state());
    TEST_ASSERT_EQUAL(ElmResult::Timeout, cap.last); // in-flight request aborted

    // Owner reconnects and re-inits; a fresh boot script runs cleanly.
    mock.restoreLink();
    boot(elm, mock, nullptr, 0, scratch);
}

static void test_unverified_header_refused()
{
    MockTransport::s_now = 0;
    MockTransport mock;
    ElmClient elm(mock, MockTransport::nowFn, makeConfig());
    MockTransport::Step scratch[16];
    boot(elm, mock, nullptr, 0, scratch);

    // TransTemp2 uses ObdModule::Tcm whose ATSH header is unverified (nullptr).
    const PidDefinition* tt2 = findPid(PidKey::TransTemp2);
    TEST_ASSERT_NOT_NULL(tt2);
    TEST_ASSERT_FALSE(elm.submit(*tt2));
    TEST_ASSERT_EQUAL(ElmState::Idle, elm.state()); // still usable
}

// ---------------------------------------------------------------------------
// Responder identity
//
// A functional (7DF) request is a broadcast: on this truck both 7E8 and 7E9
// answer 010C, in varying order. Which one supplied the value has to be part of
// the result, or an on-truck reading is an anecdote rather than evidence.
// ---------------------------------------------------------------------------

static void test_responder_id_and_count_reported()
{
    MockTransport::s_now = 0;
    MockTransport mock;
    ElmClient elm(mock, MockTransport::nowFn, makeConfig());
    ResultCapture cap;
    elm.setResultHandler(ResultCapture::handler, &cap);

    // 7E9 answers first, exactly as the truck log shows.
    const MockTransport::Step extra[] = {
        {"010C", "7E904410C0AE0\r7E804410C0AE0\r\r>", 20},
    };
    MockTransport::Step scratch[16];
    boot(elm, mock, extra, 1, scratch);

    const PidDefinition* rpm = findPid(PidKey::RpmSae);
    TEST_ASSERT_TRUE(elm.submit(*rpm));
    pump(elm, mock, 12000);

    TEST_ASSERT_EQUAL(ElmResult::Ok, cap.last);
    TEST_ASSERT_EQUAL_HEX16(0x7E9, cap.responderId); // first to answer wins
    TEST_ASSERT_EQUAL_UINT8(2, cap.responderCount);
    TEST_ASSERT_FALSE(cap.conflict); // identical bytes: corroboration
    TEST_ASSERT_EQUAL_STRING("", mock.mismatch().c_str());
}

static void test_agreeing_responders_not_flagged()
{
    MockTransport::s_now = 0;
    MockTransport mock;
    ElmClient elm(mock, MockTransport::nowFn, makeConfig());
    ResultCapture cap;
    elm.setResultHandler(ResultCapture::handler, &cap);

    const MockTransport::Step extra[] = {
        {"010C", "7E804410C1AF8\r7E904410C1AF8\r\r>", 20},
    };
    MockTransport::Step scratch[16];
    boot(elm, mock, extra, 1, scratch);

    TEST_ASSERT_TRUE(elm.submit(*findPid(PidKey::RpmSae)));
    pump(elm, mock, 12000);
    TEST_ASSERT_EQUAL(ElmResult::Ok, cap.last);
    TEST_ASSERT_EQUAL_UINT8(2, cap.responderCount);
    TEST_ASSERT_FALSE(cap.conflict);
}

static void test_conflicting_responders_flagged()
{
    MockTransport::s_now = 0;
    MockTransport mock;
    ElmClient elm(mock, MockTransport::nowFn, makeConfig());
    ResultCapture cap;
    elm.setResultHandler(ResultCapture::handler, &cap);

    // Two modules answer 22 1674 (trans temp) with DIFFERENT values — exactly
    // the case where first-wins would have silently reported either one.
    const MockTransport::Step extra[] = {
        {"221674", "7E805621674" "0A2C\r" "7E905621674" "0000\r\r>", 20},
    };
    MockTransport::Step scratch[16];
    boot(elm, mock, extra, 1, scratch);

    TEST_ASSERT_TRUE(elm.submit(*findPid(PidKey::TransTemp1)));
    pump(elm, mock, 12000);

    TEST_ASSERT_EQUAL(ElmResult::Ok, cap.last);
    TEST_ASSERT_EQUAL_HEX16(0x7E8, cap.responderId);
    TEST_ASSERT_EQUAL_UINT8(2, cap.responderCount);
    TEST_ASSERT_TRUE(cap.conflict);
    TEST_ASSERT_EQUAL_STRING("", mock.mismatch().c_str());
}

static void test_expected_responder_preferred_when_it_answers_second()
{
    MockTransport::s_now = 0;
    MockTransport mock;
    ElmClient elm(mock, MockTransport::nowFn, makeConfig());
    ResultCapture cap;
    elm.setResultHandler(ResultCapture::handler, &cap);

    const MockTransport::Step extra[] = {
        {"221674", "7E905621674" "0000\r" "7E805621674" "0A2C\r\r>", 20},
    };
    MockTransport::Step scratch[16];
    boot(elm, mock, extra, 1, scratch);

    // Pinned to the PCM: 7E9's earlier answer must be dropped, not raced.
    const PidDefinition pinned = variantOf(PidKey::TransTemp1, 0x7E8, ObdModule::Auto);
    TEST_ASSERT_TRUE(elm.submit(pinned));
    pump(elm, mock, 12000);

    TEST_ASSERT_EQUAL(ElmResult::Ok, cap.last);
    TEST_ASSERT_EQUAL_HEX16(0x7E8, cap.responderId);
    TEST_ASSERT_EQUAL_UINT8(1, cap.responderCount); // 7E9 never counted
    TEST_ASSERT_FALSE(cap.conflict);
    TEST_ASSERT_EQUAL_UINT(2, cap.len);
    TEST_ASSERT_EQUAL_HEX8(0x0A, cap.payload[0]);
    TEST_ASSERT_EQUAL_HEX8(0x2C, cap.payload[1]);
}

static void test_expected_responder_absent_yields_no_responder()
{
    MockTransport::s_now = 0;
    MockTransport mock;
    ElmClient elm(mock, MockTransport::nowFn, makeConfig());
    ResultCapture cap;
    elm.setResultHandler(ResultCapture::handler, &cap);

    const MockTransport::Step extra[] = {
        {"221674", "7E905621674" "0000\r\r>", 20},
    };
    MockTransport::Step scratch[16];
    boot(elm, mock, extra, 1, scratch);

    const PidDefinition pinned = variantOf(PidKey::TransTemp1, 0x7E8, ObdModule::Auto);
    TEST_ASSERT_TRUE(elm.submit(pinned));
    pump(elm, mock, 12000);

    // Somebody answered — just not the pinned module. That is a different
    // diagnosis from "no ECU answered" and must not look like a dead PID.
    TEST_ASSERT_EQUAL(ElmResult::NoResponder, cap.last);
    TEST_ASSERT_EQUAL_UINT(0, cap.len);
}

static void test_pinned_multiframe_survives_interleaving()
{
    MockTransport::s_now = 0;
    MockTransport mock;
    ElmClient elm(mock, MockTransport::nowFn, makeConfig());
    ResultCapture cap;
    elm.setResultHandler(ResultCapture::handler, &cap);

    // Two ECUs send interleaved ISO-TP multi-frame answers. The reassembler has
    // a single in-flight slot, so without responder filtering the pinned ECU's
    // message would be abandoned when the other one's frames arrive.
    // Total payload 9 bytes: 62 16 74 (echo) + AA BB CC DD EE FF.
    // First frame carries 6, the consecutive frame the remaining 3.
    const MockTransport::Step extra[] = {
        {"221674",
         "7E81009621674AABBCC\r" // 7E8 first frame  (PCI 10 09)
         "7E91009621674110022\r" // 7E9 first frame  — must be ignored
         "7E921334455\r"         // 7E9 consecutive  — must be ignored
         "7E821DDEEFF\r"         // 7E8 consecutive  — completes the pinned message
         "\r>",
         20},
    };
    MockTransport::Step scratch[16];
    boot(elm, mock, extra, 1, scratch);

    const PidDefinition pinned = variantOf(PidKey::TransTemp1, 0x7E8, ObdModule::Auto);
    TEST_ASSERT_TRUE(elm.submit(pinned));
    pump(elm, mock, 12000);

    TEST_ASSERT_EQUAL(ElmResult::Ok, cap.last);
    TEST_ASSERT_EQUAL_HEX16(0x7E8, cap.responderId);
    TEST_ASSERT_EQUAL_UINT(6, cap.len); // 9 bytes - 3 echo bytes (62 16 74)
    TEST_ASSERT_EQUAL_HEX8(0xAA, cap.payload[0]);
    TEST_ASSERT_EQUAL_HEX8(0xBB, cap.payload[1]);
    TEST_ASSERT_EQUAL_HEX8(0xFF, cap.payload[5]);
}

// ---------------------------------------------------------------------------
// Latency
// ---------------------------------------------------------------------------

static void test_latency_is_measured()
{
    MockTransport::s_now = 0;
    MockTransport mock;
    ElmClient elm(mock, MockTransport::nowFn, makeConfig());
    ResultCapture cap;
    elm.setResultHandler(ResultCapture::handler, &cap);

    const MockTransport::Step extra[] = {
        {"010C", "7E804410C1AF8\r\r>", 20},  // first request clears SEARCHING
        {"010C", "7E804410C1AF8\r\r>", 90},  // ~the 96 ms measured on the truck
    };
    MockTransport::Step scratch[16];
    boot(elm, mock, extra, 2, scratch);

    TEST_ASSERT_TRUE(elm.submit(*findPid(PidKey::RpmSae)));
    pump(elm, mock, 200);
    TEST_ASSERT_EQUAL(ElmResult::Ok, cap.last);

    TEST_ASSERT_TRUE(elm.submit(*findPid(PidKey::RpmSae)));
    pump(elm, mock, 200);
    TEST_ASSERT_EQUAL(ElmResult::Ok, cap.last);
    TEST_ASSERT_UINT_WITHIN(3, 90, cap.latencyMs);
}

// ---------------------------------------------------------------------------
// Addressing: ATSH / ATCRA sequencing and cache invalidation
// ---------------------------------------------------------------------------

static void test_atsh_sent_on_header_change_and_not_resent()
{
    MockTransport::s_now = 0;
    MockTransport mock;
    ElmClient elm(mock, MockTransport::nowFn, makeConfig());
    ResultCapture cap;
    elm.setResultHandler(ResultCapture::handler, &cap);
    clearModuleAddressingOverrides();

    // Hdr726 has a real, non-functional header ("726") in the shipped table.
    const MockTransport::Step extra[] = {
        {"ATSH726", "OK\r\r>", 5},
        {"221674", "7E805621674" "0A2C\r\r>", 20},
        // Second request on the SAME header: no ATSH, straight to the request.
        {"221674", "7E805621674" "0A2C\r\r>", 20},
        // Back to a functional PID: ATSH must be re-sent to restore 7DF.
        {"ATSH7DF", "OK\r\r>", 5},
        {"010C", "7E804410C1AF8\r\r>", 20},
    };
    MockTransport::Step scratch[16];
    boot(elm, mock, extra, 5, scratch);

    const PidDefinition on726 = variantOf(PidKey::TransTemp1, 0, ObdModule::Hdr726);
    TEST_ASSERT_TRUE(elm.submit(on726));
    pump(elm, mock, 12000);
    TEST_ASSERT_EQUAL(ElmResult::Ok, cap.last);

    TEST_ASSERT_TRUE(elm.submit(on726));
    pump(elm, mock, 200);
    TEST_ASSERT_EQUAL(ElmResult::Ok, cap.last);

    TEST_ASSERT_TRUE(elm.submit(*findPid(PidKey::RpmSae)));
    pump(elm, mock, 200);
    TEST_ASSERT_EQUAL(ElmResult::Ok, cap.last);

    // The mock asserts on every write, so an unexpected/missing ATSH shows here.
    TEST_ASSERT_EQUAL_STRING("", mock.mismatch().c_str());
}

static void test_atcra_follows_atsh_and_is_cleared_on_return()
{
    MockTransport::s_now = 0;
    MockTransport mock;
    ElmClient elm(mock, MockTransport::nowFn, makeConfig());
    ResultCapture cap;
    elm.setResultHandler(ResultCapture::handler, &cap);

    // The "try ATSH 7E0 + ATCRA 7E8 for the PCM" experiment, as a runtime
    // override rather than a guess compiled into the table.
    clearModuleAddressingOverrides();
    TEST_ASSERT_TRUE(setModuleAddressingOverride(ObdModule::Pcm, "7E0", "7E8"));

    const MockTransport::Step extra[] = {
        {"ATSH7E0", "OK\r\r>", 5},   // header first...
        {"ATCRA7E8", "OK\r\r>", 5},  // ...then the receive filter
        {"221446", "7E805621446" "1234\r\r>", 20},
        // Returning to functional addressing must BOTH restore 7DF and clear
        // the filter — a bare ATCRA resets it.
        {"ATSH7DF", "OK\r\r>", 5},
        {"ATCRA", "OK\r\r>", 5},
        {"010C", "7E804410C1AF8\r\r>", 20},
    };
    MockTransport::Step scratch[16];
    boot(elm, mock, extra, 6, scratch);

    const PidDefinition icpOnPcm = variantOf(PidKey::Icp, 0, ObdModule::Pcm);
    TEST_ASSERT_TRUE(elm.submit(icpOnPcm));
    pump(elm, mock, 12000);
    TEST_ASSERT_EQUAL(ElmResult::Ok, cap.last);

    TEST_ASSERT_TRUE(elm.submit(*findPid(PidKey::RpmSae)));
    pump(elm, mock, 200);
    TEST_ASSERT_EQUAL(ElmResult::Ok, cap.last);
    TEST_ASSERT_EQUAL_STRING("", mock.mismatch().c_str());

    clearModuleAddressingOverrides();
}

static void test_header_cache_invalidated_by_atz_recovery()
{
    // Regression: the recovery ladder reaches startReset() WITHOUT going
    // through begin(). If the cached header survived that ATZ, the next request
    // would skip its ATSH and be sent on whatever header the adapter actually
    // reverted to (7DF) while the code believed it was on 726.
    MockTransport::s_now = 0;
    MockTransport mock;
    ElmClient elm(mock, MockTransport::nowFn, makeConfig());
    ResultCapture cap;
    elm.setResultHandler(ResultCapture::handler, &cap);
    clearModuleAddressingOverrides();

    const MockTransport::Step extra[] = {
        {"ATSH726", "OK\r\r>", 5},
        {"221674", "7E805621674" "0A2C\r\r>", 20}, // now cached on "726"
        // Three silent requests, each answered by a recovery CR, drive the
        // client through its timeout ladder into a full ATZ.
        {"221674", "", 0},
        {"", "\r>", 20},
        {"221674", "", 0},
        {"", "\r>", 20},
        {"221674", "", 0},
        {"ATZ", "\r\rELM327 v1.4b\r\r>", 50},
        {"ATE0", "OK\r\r>", 5},
        {"ATL0", "OK\r\r>", 5},
        {"ATS0", "OK\r\r>", 5},
        {"ATH1", "OK\r\r>", 5},
        {"ATAT1", "OK\r\r>", 5},
        {"ATSP0", "OK\r\r>", 5},
        // THE ASSERTION: the ATSH must come back, because ATZ reverted the
        // adapter to 7DF. A stale cache would jump straight to "221674".
        {"ATSH726", "OK\r\r>", 5},
        {"221674", "7E805621674" "0A2C\r\r>", 20},
    };
    MockTransport::Step scratch[32];
    boot(elm, mock, extra, sizeof(extra) / sizeof(extra[0]), scratch);

    const PidDefinition on726 = variantOf(PidKey::TransTemp1, 0, ObdModule::Hdr726);
    TEST_ASSERT_TRUE(elm.submit(on726));
    pump(elm, mock, 12000);
    TEST_ASSERT_EQUAL(ElmResult::Ok, cap.last);

    for (int i = 0; i < 3; ++i) {
        TEST_ASSERT_TRUE(elm.submit(on726));
        pump(elm, mock, 700); // past the 500 ms per-PID timeout
        TEST_ASSERT_EQUAL(ElmResult::Timeout, cap.last);
        pump(elm, mock, 200); // recovery prompt / ATZ banner
    }
    pump(elm, mock, 500); // finish re-init
    TEST_ASSERT_EQUAL(ElmState::Idle, elm.state());

    TEST_ASSERT_TRUE(elm.submit(on726));
    pump(elm, mock, 12000);
    TEST_ASSERT_EQUAL(ElmResult::Ok, cap.last);
    TEST_ASSERT_EQUAL_STRING("", mock.mismatch().c_str());
}

static void test_rejected_addressing_command_fails_the_request()
{
    MockTransport::s_now = 0;
    MockTransport mock;
    ElmClient elm(mock, MockTransport::nowFn, makeConfig());
    ResultCapture cap;
    elm.setResultHandler(ResultCapture::handler, &cap);
    clearModuleAddressingOverrides();

    const MockTransport::Step extra[] = {
        {"ATSH726", "?\r\r>", 5}, // adapter rejects the header
    };
    MockTransport::Step scratch[16];
    boot(elm, mock, extra, 1, scratch);

    const PidDefinition on726 = variantOf(PidKey::TransTemp1, 0, ObdModule::Hdr726);
    TEST_ASSERT_TRUE(elm.submit(on726));
    pump(elm, mock, 200);

    TEST_ASSERT_EQUAL(ElmResult::Error, cap.last);
    TEST_ASSERT_EQUAL(ElmState::Idle, elm.state()); // still usable
    TEST_ASSERT_EQUAL_STRING("", mock.mismatch().c_str());
}

// ---------------------------------------------------------------------------
// Response-count digit
// ---------------------------------------------------------------------------

static void test_response_count_digit_appended()
{
    MockTransport::s_now = 0;
    MockTransport mock;
    ElmClient elm(mock, MockTransport::nowFn, makeConfig());
    ResultCapture cap;
    elm.setResultHandler(ResultCapture::handler, &cap);
    clearModuleAddressingOverrides();
    TEST_ASSERT_TRUE(setModuleAddressingOverride(ObdModule::Pcm, "7E0", nullptr));

    const MockTransport::Step extra[] = {
        {"ATSH7E0", "OK\r\r>", 5},
        // 3-byte Mode 22 request + count digit: odd length, so the ELM reads
        // the trailing digit as a response count rather than as data.
        {"2213101", "7E805621310" "1234\r\r>", 20},
    };
    MockTransport::Step scratch[16];
    boot(elm, mock, extra, 2, scratch);

    const PidDefinition eotOnPcm = variantOf(PidKey::Eot, 0, ObdModule::Pcm, /*count=*/1);
    TEST_ASSERT_TRUE(elm.submit(eotOnPcm));
    pump(elm, mock, 12000);

    TEST_ASSERT_EQUAL(ElmResult::Ok, cap.last);
    TEST_ASSERT_EQUAL_STRING("", mock.mismatch().c_str());
    clearModuleAddressingOverrides();
}

int main(int, char**)
{
    UNITY_BEGIN();
    RUN_TEST(test_init_sequence_reaches_idle);
    RUN_TEST(test_rpm_request_happy_path);
    RUN_TEST(test_no_data_and_stopped);
    RUN_TEST(test_negative_response_is_error);
    RUN_TEST(test_timeout_then_recovery);
    RUN_TEST(test_transport_loss_and_reinit);
    RUN_TEST(test_unverified_header_refused);
    RUN_TEST(test_responder_id_and_count_reported);
    RUN_TEST(test_agreeing_responders_not_flagged);
    RUN_TEST(test_conflicting_responders_flagged);
    RUN_TEST(test_expected_responder_preferred_when_it_answers_second);
    RUN_TEST(test_expected_responder_absent_yields_no_responder);
    RUN_TEST(test_pinned_multiframe_survives_interleaving);
    RUN_TEST(test_latency_is_measured);
    RUN_TEST(test_atsh_sent_on_header_change_and_not_resent);
    RUN_TEST(test_atcra_follows_atsh_and_is_cleared_on_return);
    RUN_TEST(test_header_cache_invalidated_by_atz_recovery);
    RUN_TEST(test_rejected_addressing_command_fails_the_request);
    RUN_TEST(test_response_count_digit_appended);
    return UNITY_END();
}
