#include "SerialDisplay.h"

#include <Arduino.h>

using obd::ChannelId;

namespace {

const char* warnMark(obd::WarnLevel lvl)
{
    switch (lvl) {
    case obd::WarnLevel::Caution: return " [CAUTION]";
    case obd::WarnLevel::Critical: return " [CRITICAL]";
    case obd::WarnLevel::Stale: return " [STALE]";
    case obd::WarnLevel::Normal: return "";
    }
    return "";
}

} // namespace

void SerialDisplay::begin()
{
    Serial.println();
    Serial.println("SerialDisplay ready (text renderer; real AMOLED comes later)");
}

void SerialDisplay::printValue(const DisplaySnapshot& snap, ChannelId id)
{
    const obd::Channel& c = snap.data.channel(id);
    char buf[48];
    if (!c.everValid) {
        snprintf(buf, sizeof(buf), "%-6s ---", obd::channelShortName(id));
    } else {
        const bool stale = !c.isFresh(snap.data.nowMs, snap.staleAfterMs);
        snprintf(buf, sizeof(buf), "%-6s %.1f %s%s%s",
                 obd::channelShortName(id), static_cast<double>(c.value),
                 obd::unitSuffix(obd::channelUnit(id)),
                 stale ? "*" : "",
                 warnMark(snap.warnings.channelLevel(id)));
    }
    Serial.printf("%-26s", buf);
}

void SerialDisplay::printRow(const DisplaySnapshot& snap, ChannelId left, ChannelId right)
{
    Serial.print("  ");
    printValue(snap, left);
    printValue(snap, right);
    Serial.println();
}

void SerialDisplay::render(const DisplaySnapshot& snap)
{
    const uint32_t now = millis();
    if (now - lastRenderMs_ < intervalMs_) {
        return;
    }
    lastRenderMs_ = now;
    page_ = snap.page;

    Serial.printf("---- [%s | %s]%s%s ----\r\n",
                  snap.btConnected ? "BT up" : "BT down",
                  obd::elmStateName(snap.link),
                  snap.warnings.anyCritical ? " !! CRITICAL !!"
                                            : (snap.warnings.anyCaution ? " ! caution" : ""),
                  snap.warnings.anyStale ? " (stale data)" : "");

    // Milestone-1 headline: engine RPM.
    const obd::Channel& rpm = snap.data.channel(ChannelId::Rpm);
    if (rpm.isFresh(snap.data.nowMs, snap.staleAfterMs)) {
        Serial.printf("RPM: %u\r\n", static_cast<unsigned>(rpm.value + 0.5f));
    } else {
        Serial.println("RPM: ----");
    }

    switch (page_) {
    case PageId::EngineHealth:
        Serial.println("  PAGE 1 - ENGINE HEALTH");
        printRow(snap, ChannelId::EctF, ChannelId::EotF);
        printRow(snap, ChannelId::EctEotDeltaF, ChannelId::FicmMainV);
        printRow(snap, ChannelId::IcpPsi, ChannelId::IprPct);
        break;
    case PageId::Drivetrain:
        Serial.println("  PAGE 2 - DRIVETRAIN");
        printRow(snap, ChannelId::BoostPsi, ChannelId::TransTempF);
        printRow(snap, ChannelId::Rpm, ChannelId::VgtPct);
        printRow(snap, ChannelId::BatteryV, ChannelId::EngineLoadPct);
        break;
    case PageId::LargeGauge:
        Serial.println("  PAGE 3 - LARGE GAUGE");
        Serial.print("  ");
        printValue(snap, ChannelId::BoostPsi);
        Serial.println();
        break;
    case PageId::Count:
        break;
    }
}
