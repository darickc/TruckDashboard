// Unit tests: PID decoding against the ACTUAL table entries (verifies the
// generated scale/bias values, signed handling, truncation rejection) plus
// unit conversions.

#include <unity.h>

#include "Decoders.h"
#include "PidDefs.h"
#include "Units.h"

using namespace obd;

extern "C" {
void setUp(void) {}
void tearDown(void) {}
}

static float decode(PidKey key, const uint8_t* payload, size_t len, bool* ok = nullptr)
{
    const PidDefinition* pid = findPid(key);
    TEST_ASSERT_NOT_NULL(pid);
    float v = 0.0f;
    const bool good = decodePid(*pid, payload, len, v);
    if (ok != nullptr) {
        *ok = good;
    } else {
        TEST_ASSERT_TRUE(good);
    }
    return v;
}

static void test_rpm_sae()
{
    // (0x1A*256 + 0xF8) / 4 = 6904/4 = 1726 rpm
    const uint8_t p[] = {0x1A, 0xF8};
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 1726.0f, decode(PidKey::RpmSae, p, 2));
}

static void test_ect_sae_and_conversion()
{
    // A - 40: 0x87 = 135 -> 95 C -> 203 F
    const uint8_t p[] = {0x87};
    const float c = decode(PidKey::EctSae, p, 1);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 95.0f, c);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 203.0f, convertUnit(c, Unit::Celsius, Unit::Fahrenheit));
}

static void test_baro_sae()
{
    // A kPa: 101 kPa -> 14.65 psi
    const uint8_t p[] = {101};
    const float kpa = decode(PidKey::BaroSae, p, 1);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 101.0f, kpa);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 14.65f, convertUnit(kpa, Unit::Kpa, Unit::Psi));
}

static void test_speed_conversion()
{
    // 100 km/h -> 62.14 mph
    const uint8_t p[] = {100};
    const float kmh = decode(PidKey::SpeedSae, p, 1);
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 62.14f, convertUnit(kmh, Unit::Kmh, Unit::Mph));
}

static void test_eot_ford()
{
    // (((A*256)+B)/100)-40: raw 24040 -> 200.4 C
    const uint8_t p[] = {0x5D, 0xE8}; // 0x5DE8 = 24040
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 200.4f, decode(PidKey::Eot, p, 2));
}

static void test_ficm_ford()
{
    // raw/256: 0x3000 = 12288 -> 48.0 V
    const uint8_t p[] = {0x30, 0x00};
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 48.0f, decode(PidKey::FicmMainPower, p, 2));
}

static void test_icp_ford()
{
    // raw*0.57: 1000 -> 570 psi
    const uint8_t p[] = {0x03, 0xE8};
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 570.0f, decode(PidKey::Icp, p, 2));
}

static void test_ipr_ford()
{
    // A*13.53/35: 90 -> 34.79 %
    const uint8_t p[] = {90};
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 34.79f, decode(PidKey::IprDuty, p, 1));
}

static void test_vgt_ford()
{
    // raw*100/32767: 16384 -> ~50.0 %
    const uint8_t p[] = {0x40, 0x00};
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 50.0f, decode(PidKey::VgtDuty, p, 2));
}

static void test_map_ford()
{
    // raw*0.03625: 400 -> 14.5 psi (about atmospheric at idle)
    const uint8_t p[] = {0x01, 0x90};
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 14.5f, decode(PidKey::Map, p, 2));
}

static void test_trans_temp_ford()
{
    // raw/8: 1344 -> 168 F
    const uint8_t p[] = {0x05, 0x40};
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 168.0f, decode(PidKey::TransTemp1, p, 2));
}

static void test_trans_temp3_signed()
{
    // signed 16-bit: raw -1000 (0xFC18) * -0.0036 + 212.98 = 216.58 F
    const uint8_t p[] = {0xFC, 0x18};
    TEST_ASSERT_FLOAT_WITHIN(0.01f, 216.58f, decode(PidKey::TransTemp3, p, 2));
}

static void test_gear_ford()
{
    const uint8_t p[] = {6};
    TEST_ASSERT_FLOAT_WITHIN(0.001f, 3.0f, decode(PidKey::Gear1, p, 1));
}

static void test_battery_ford()
{
    // A/16: 0xE2 = 226 -> 14.125 V
    const uint8_t p[] = {0xE2};
    TEST_ASSERT_FLOAT_WITHIN(0.001f, 14.125f, decode(PidKey::BatteryVoltage, p, 1));
}

static void test_truncated_payload_rejected()
{
    bool ok = true;
    const uint8_t p[] = {0x1A}; // RPM needs 2 bytes
    decode(PidKey::RpmSae, p, 1, &ok);
    TEST_ASSERT_FALSE(ok);

    decode(PidKey::Eot, p, 0, &ok);
    TEST_ASSERT_FALSE(ok);
}

static void test_channel_units_are_display_units()
{
    // Project defaults: Fahrenheit / PSI / MPH / Volts.
    TEST_ASSERT_EQUAL(Unit::Fahrenheit, channelUnit(ChannelId::EotF));
    TEST_ASSERT_EQUAL(Unit::Psi, channelUnit(ChannelId::BoostPsi));
    TEST_ASSERT_EQUAL(Unit::Mph, channelUnit(ChannelId::SpeedMph));
    TEST_ASSERT_EQUAL(Unit::Volts, channelUnit(ChannelId::FicmMainV));
}

int main(int, char**)
{
    UNITY_BEGIN();
    RUN_TEST(test_rpm_sae);
    RUN_TEST(test_ect_sae_and_conversion);
    RUN_TEST(test_baro_sae);
    RUN_TEST(test_speed_conversion);
    RUN_TEST(test_eot_ford);
    RUN_TEST(test_ficm_ford);
    RUN_TEST(test_icp_ford);
    RUN_TEST(test_ipr_ford);
    RUN_TEST(test_vgt_ford);
    RUN_TEST(test_map_ford);
    RUN_TEST(test_trans_temp_ford);
    RUN_TEST(test_trans_temp3_signed);
    RUN_TEST(test_gear_ford);
    RUN_TEST(test_battery_ford);
    RUN_TEST(test_truncated_payload_rejected);
    RUN_TEST(test_channel_units_are_display_units);
    return UNITY_END();
}
