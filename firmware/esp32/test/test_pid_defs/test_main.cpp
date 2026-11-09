// Unit tests: PID table invariants.
//
// These guard rules that otherwise live only in comments — the kind that are
// true today, stay true by accident for a while, and then quietly stop being
// true during an on-truck session when someone pastes a value into a row.

#include <unity.h>

#include <cstring>

#include "Config.h"
#include "PidDefs.h"

using namespace obd;

extern "C" {
void setUp(void) {}
void tearDown(void) {}
}

static void test_no_duplicate_pid_keys()
{
    for (size_t i = 0; i < kPidTableSize; ++i) {
        for (size_t j = i + 1; j < kPidTableSize; ++j) {
            if (kPidTable[i].key == kPidTable[j].key) {
                char msg[128];
                std::snprintf(msg, sizeof(msg),
                              "duplicate PidKey: rows %u and %u (%s / %s)",
                              static_cast<unsigned>(i), static_cast<unsigned>(j),
                              kPidTable[i].name, kPidTable[j].name);
                TEST_FAIL_MESSAGE(msg);
            }
        }
    }
}

static void test_findPid_resolves_every_row()
{
    for (size_t i = 0; i < kPidTableSize; ++i) {
        const PidDefinition* d = findPid(kPidTable[i].key);
        TEST_ASSERT_NOT_NULL(d);
        TEST_ASSERT_EQUAL_PTR(&kPidTable[i], d);
    }
}

static void test_response_count_digit_never_on_functional_header()
{
    // The hazard: on 7DF several ECUs answer. Telling the adapter to return
    // after N replies leaves the straggler to land mid-way through the NEXT
    // request, which desyncs it (STOPPED). The count digit is only safe once
    // the PID is physically addressed to a single module.
    clearModuleAddressingOverrides();
    for (size_t i = 0; i < kPidTableSize; ++i) {
        const PidDefinition& d = kPidTable[i];
        if (d.expectedResponses == 0) {
            continue;
        }
        const char* hdr = moduleAddressing(d.module).txHeader;
        char msg[160];
        std::snprintf(msg, sizeof(msg),
                      "%s sets expectedResponses=%u on header '%s' — only valid "
                      "with physical addressing",
                      d.name, d.expectedResponses, hdr != nullptr ? hdr : "(unverified)");
        TEST_ASSERT_FALSE_MESSAGE(isFunctionalHeader(hdr), msg);
    }
}

static void test_expected_responder_is_a_plausible_response_id()
{
    // ISO 15765-4 physical response IDs are 7E8..7EF. Anything else in this
    // field is a typo (a REQUEST id like 7E0 is the easy mistake) and would
    // silently reject every answer the module sends.
    for (size_t i = 0; i < kPidTableSize; ++i) {
        const PidDefinition& d = kPidTable[i];
        if (d.expectedResponder == 0) {
            continue; // "accept any" — the honest default
        }
        char msg[160];
        std::snprintf(msg, sizeof(msg),
                      "%s pins expectedResponder=%03X, outside the 7E8..7EF "
                      "response range (did you use the request ID?)",
                      d.name, d.expectedResponder);
        TEST_ASSERT_TRUE_MESSAGE(
            d.expectedResponder >= 0x7E8 && d.expectedResponder <= 0x7EF, msg);
    }
}

static void test_decode_widths_are_supported()
{
    for (size_t i = 0; i < kPidTableSize; ++i) {
        const PidDefinition& d = kPidTable[i];
        if (d.decodeFn != nullptr) {
            continue; // custom decoder owns its own layout
        }
        char msg[128];
        std::snprintf(msg, sizeof(msg), "%s has decode width %u (must be 1 or 2)",
                      d.name, d.decode.width);
        TEST_ASSERT_TRUE_MESSAGE(d.decode.width == 1 || d.decode.width == 2, msg);
    }
}

static void test_service_22_pids_use_two_byte_dids()
{
    for (size_t i = 0; i < kPidTableSize; ++i) {
        const PidDefinition& d = kPidTable[i];
        char msg[128];
        std::snprintf(msg, sizeof(msg), "%s: service %02X with pid %04X", d.name,
                      d.service, d.pid);
        if (d.service == 0x01) {
            TEST_ASSERT_TRUE_MESSAGE(d.pid <= 0xFF, msg);
        } else {
            TEST_ASSERT_EQUAL_HEX8_MESSAGE(0x22, d.service, msg);
        }
    }
}

static void test_every_enabled_key_exists_in_the_table()
{
    for (size_t i = 0; i < config::kEnabledPidCount; ++i) {
        const PidDefinition* d = findPid(config::kEnabledPids[i]);
        char msg[96];
        std::snprintf(msg, sizeof(msg), "kEnabledPids[%u] is not in the PID table",
                      static_cast<unsigned>(i));
        TEST_ASSERT_NOT_NULL_MESSAGE(d, msg);
    }
}

// ---------------------------------------------------------------------------
// Runtime addressing overrides — the on-truck experiment hook.
// ---------------------------------------------------------------------------

static void test_unverified_modules_stay_unverified_by_default()
{
    clearModuleAddressingOverrides();
    // The no-guessing rule, asserted: these must remain nullptr until a real
    // session fills them in, because nullptr is what makes the client refuse.
    TEST_ASSERT_NULL(moduleAddressing(ObdModule::Pcm).txHeader);
    TEST_ASSERT_NULL(moduleAddressing(ObdModule::Tcm).txHeader);
    TEST_ASSERT_NULL(moduleAddressing(ObdModule::Abs).txHeader);
    TEST_ASSERT_EQUAL_STRING("7DF", moduleAddressing(ObdModule::Auto).txHeader);
}

static void test_addressing_override_applies_and_clears()
{
    clearModuleAddressingOverrides();
    TEST_ASSERT_FALSE(hasModuleAddressingOverride(ObdModule::Pcm));

    TEST_ASSERT_TRUE(setModuleAddressingOverride(ObdModule::Pcm, "7E0", "7E8"));
    TEST_ASSERT_TRUE(hasModuleAddressingOverride(ObdModule::Pcm));
    TEST_ASSERT_EQUAL_STRING("7E0", moduleAddressing(ObdModule::Pcm).txHeader);
    TEST_ASSERT_EQUAL_STRING("7E8", moduleAddressing(ObdModule::Pcm).rxFilter);

    // An empty filter means "no filter", not an empty ATCRA argument.
    TEST_ASSERT_TRUE(setModuleAddressingOverride(ObdModule::Tcm, "7E1", nullptr));
    TEST_ASSERT_EQUAL_STRING("7E1", moduleAddressing(ObdModule::Tcm).txHeader);
    TEST_ASSERT_NULL(moduleAddressing(ObdModule::Tcm).rxFilter);

    clearModuleAddressingOverrides();
    TEST_ASSERT_NULL(moduleAddressing(ObdModule::Pcm).txHeader);
    TEST_ASSERT_NULL(moduleAddressing(ObdModule::Tcm).txHeader);
}

static void test_addressing_override_rejects_overlong_input()
{
    clearModuleAddressingOverrides();
    TEST_ASSERT_FALSE(setModuleAddressingOverride(ObdModule::Pcm,
                                                  "7E0777777777777777", nullptr));
    TEST_ASSERT_FALSE(setModuleAddressingOverride(ObdModule::Pcm, "7E0",
                                                  "7E8777777777777777"));
    TEST_ASSERT_FALSE(setModuleAddressingOverride(ObdModule::Pcm, nullptr, nullptr));
    TEST_ASSERT_FALSE(hasModuleAddressingOverride(ObdModule::Pcm));
}

static void test_is_functional_header()
{
    TEST_ASSERT_TRUE(isFunctionalHeader("7DF"));
    TEST_ASSERT_FALSE(isFunctionalHeader("7E0"));
    TEST_ASSERT_FALSE(isFunctionalHeader(nullptr));
}

int main(int, char**)
{
    UNITY_BEGIN();
    RUN_TEST(test_no_duplicate_pid_keys);
    RUN_TEST(test_findPid_resolves_every_row);
    RUN_TEST(test_response_count_digit_never_on_functional_header);
    RUN_TEST(test_expected_responder_is_a_plausible_response_id);
    RUN_TEST(test_decode_widths_are_supported);
    RUN_TEST(test_service_22_pids_use_two_byte_dids);
    RUN_TEST(test_every_enabled_key_exists_in_the_table);
    RUN_TEST(test_unverified_modules_stay_unverified_by_default);
    RUN_TEST(test_addressing_override_applies_and_clears);
    RUN_TEST(test_addressing_override_rejects_overlong_input);
    RUN_TEST(test_is_functional_header);
    return UNITY_END();
}
