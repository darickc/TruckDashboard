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
#include "Pages.h"
#include "Tap.h"

#ifndef KNOB_VERSION
#define KNOB_VERSION "0.1.0"
#endif

namespace {

USBHIDConsumerControl consumer;
knob::Dial dial(2000);
knob::TapDetector tap;
knob::Pages pages(3000);

char line[knob::kMaxLine + 2];
size_t lineLen = 0;
bool lineTooLong = false;

struct Counts {
    uint32_t config = 0, data = 0, nav = 0, media = 0, badChecksum = 0, malformed = 0, unknown = 0, tooLong = 0;
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
    static const char* const kPage[] = {"gauges", "navigation", "media"};
    Serial.printf("# frames: %u config, %u data, %u nav, %u media, %u bad checksum, %u malformed, %u unknown, "
                  "%u too long; %s%s; page %s\n",
                  counts.config, counts.data, counts.nav, counts.media, counts.badChecksum, counts.malformed,
                  counts.unknown, counts.tooLong, dial.linkLost(now) ? "no data" : "link up",
                  dial.simulated() ? ", SIMULATED" : "", kPage[pages.index()]);
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
    static const char* const kNav[] = {"no route", "routing", "waiting for a position", "", "arrived"};
    if (const knob::NavFrame* n = pages.nav(now)) {
        if (n->state == knob::NavState::Active) {
            Serial.printf("#   nav: %s in %s %s, %s; %s %s and %u min left\n", knob::turnName(n->turn), n->dist,
                          n->distUnit, n->text, n->left, n->leftUnit, n->minutes);
        } else {
            Serial.printf("#   nav: %s %s\n", kNav[static_cast<int>(n->state)], n->text);
        }
    } else {
        Serial.printf("#   nav: no data\n");
    }
    static const char* const kPlay[] = {"no phone", "playing", "paused", "stopped"};
    if (const knob::MediaFrame* m = pages.media(now)) {
        char t[24];
        knob::formatTrackTime(m->posS, m->durS, t, sizeof(t));
        Serial.printf("#   media: %s %s / %s (%s) %s; volume %d/%d%s\n", kPlay[static_cast<int>(m->state)], m->title,
                      m->artist, m->source, t, m->volume, m->volumeSteps, m->muted ? " muted" : "");
    } else {
        Serial.printf("#   media: no data\n");
    }
}

void onLine(uint32_t now)
{
    static knob::Frames f;
    switch (knob::parseLine(std::string_view(line, lineLen), f)) {
        case knob::Parsed::Config: dial.onConfig(f.config); counts.config++; break;
        case knob::Parsed::Data: dial.onData(f.data, now); counts.data++; break;
        case knob::Parsed::Nav: pages.onNav(f.nav, now); counts.nav++; break;
        case knob::Parsed::Media: pages.onMedia(f.media, now); counts.media++; break;
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

// down: a finger touched; move: it moved; neither: it lifted.
void onTouch(bool down, bool move, int x, int y)
{
    const uint32_t now = millis();
    if (down) {
        tap.onDown(x, y, now);
    } else if (move) {
        tap.onMove(x, y, now);
    } else {
        const knob::Gesture g = tap.onUp(now);
        if (g == knob::Gesture::Tap) {
            press(CONSUMER_CONTROL_PLAY_PAUSE);
        } else {
            pages.onGesture(g);
        }
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
