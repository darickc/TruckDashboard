// The knob display's firmware (ADR-0044). One USB cable to the Pi: the S3's
// own USB as a composite device named "F-250 knob" — a serial port that
// receives knob-link's frames, and a HID knob (Consumer Control) that
// audio-manager reads as volume, mute and play/pause (ADR-0043).
//
// Status: builds; never run (no board yet). The display, touch and encoder
// drivers aren't written: their pins and the ST77916 panel's start-up come
// from Waveshare's demo, which hasn't been read. Until then this runs the
// link and the model, draws nothing, and says so in its log ("# ..." lines on
// the same serial port, which knob-link logs).

#include <Arduino.h>
#include <USB.h>
#include <USBHIDConsumerControl.h>

#include "Dial.h"
#include "Frame.h"
#include "Tap.h"

#ifndef KNOB_VERSION
#define KNOB_VERSION "0.1.0"
#endif

namespace {

USBHIDConsumerControl consumer;
knob::Dial dial(2000);
knob::TapDetector tap;

char line[knob::kMaxLine + 2];
size_t lineLen = 0;
bool lineTooLong = false;

struct Counts {
    uint32_t config = 0, data = 0, badChecksum = 0, malformed = 0, unknown = 0, tooLong = 0;
} counts;

uint32_t lastHelloMs = 0;
constexpr uint32_t kHelloEveryMs = 10000;

void sendLine(const std::string& s) { Serial.print((s + "\n").c_str()); }

void hello()
{
    sendLine(knob::withChecksum("H1 knob-display " KNOB_VERSION));
    Serial.printf("# no display, touch or encoder driver yet (ADR-0044): frames parsed, nothing drawn\n");
}

// What the dial would show, as a log line, so the bench can see the model
// work without a screen.
void report(uint32_t now)
{
    static const char* const kState = "cakns";
    Serial.printf("# frames: %u config, %u data, %u bad checksum, %u malformed, %u unknown, %u too long; %s%s\n",
                  counts.config, counts.data, counts.badChecksum, counts.malformed, counts.unknown,
                  counts.tooLong, dial.linkLost(now) ? "no data" : "link up",
                  dial.simulated() ? ", SIMULATED" : "");
    const knob::Slot slots[] = {knob::Slot::Speed, knob::Slot::Fuel, knob::Slot::Eot, knob::Slot::Ect,
                                knob::Slot::Delta};
    for (knob::Slot s : slots) {
        knob::View v = dial.view(s, now);
        char value[16], age[12] = "";
        knob::formatValue(s, v, value, sizeof(value));
        if (v.state == knob::State::Stale) knob::formatAge(v.ageS, age, sizeof(age));
        Serial.printf("#   %s %s %c %s%s\n", knob::slotName(s), value, kState[static_cast<int>(v.state)], age,
                      v.unverified ? " (unverified)" : "");
    }
}

void onLine(uint32_t now)
{
    knob::ConfigFrame c;
    knob::DataFrame d;
    switch (knob::parseLine(std::string_view(line, lineLen), c, d)) {
        case knob::Parsed::Config: dial.onConfig(c); counts.config++; break;
        case knob::Parsed::Data: dial.onData(d, now); counts.data++; break;
        case knob::Parsed::BadChecksum: counts.badChecksum++; break;
        case knob::Parsed::Malformed: counts.malformed++; break;
        case knob::Parsed::Unknown: counts.unknown++; break;
        case knob::Parsed::Hello:
        case knob::Parsed::Comment: break;
    }
}

void press(uint16_t usage)
{
    consumer.press(usage);
    consumer.release();
}

}  // namespace

// For the board's drivers (TODO, ADR-0044): nothing calls these yet.
void onKnobDetents(int steps)
{
    tap.onTurn(millis());
    for (int i = 0; i < (steps < 0 ? -steps : steps); ++i) {
        press(steps > 0 ? CONSUMER_CONTROL_VOLUME_INCREMENT : CONSUMER_CONTROL_VOLUME_DECREMENT);
    }
}

void onKnobPush() { press(CONSUMER_CONTROL_PLAY_PAUSE); }

void onTouch(bool down, int x, int y)
{
    const uint32_t now = millis();
    if (down) {
        tap.onDown(x, y, now);
    } else if (tap.onUp(now)) {
        press(CONSUMER_CONTROL_PLAY_PAUSE);
    }
}

void setup()
{
    USB.productName("F-250 knob");
    USB.manufacturerName("TruckDashboard");
    consumer.begin();
    USB.begin();
    Serial.begin(115200);
}

void loop()
{
    const uint32_t now = millis();
    while (Serial.available() > 0) {
        const int ch = Serial.read();
        if (ch < 0) break;
        if (ch == '\n') {
            if (lineTooLong) {
                counts.tooLong++;
            } else {
                onLine(now);
            }
            lineLen = 0;
            lineTooLong = false;
        } else if (lineLen < knob::kMaxLine + 1) {
            line[lineLen++] = static_cast<char>(ch);
        } else {
            lineTooLong = true;
        }
    }
    if (lastHelloMs == 0 || now - lastHelloMs >= kHelloEveryMs) {
        lastHelloMs = now == 0 ? 1 : now;
        hello();
        report(now);
    }
    delay(5);
}
