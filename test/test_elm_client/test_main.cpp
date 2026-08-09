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

    static void handler(void* ctx, const PidDefinition&, ElmResult r,
                        const uint8_t* p, size_t n)
    {
        auto* self = static_cast<ResultCapture*>(ctx);
        ++self->count;
        self->last = r;
        self->len = n;
        if (p != nullptr && n > 0 && n <= sizeof(self->payload)) {
            std::memcpy(self->payload, p, n);
        }
    }
};

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
    return UNITY_END();
}
