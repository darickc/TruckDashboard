// The knob display's firmware (ADR-0044). One USB cable to the Pi: the S3's
// own USB as a composite device named "F-250 knob" — a serial port that
// receives knob-link's frames, and a HID knob (Consumer Control) that
// audio-manager reads as volume, mute and play/pause (ADR-0043).
//
// The board's display, touch and knob (lib/KnobHw) and the dial drawn from
// the model with LVGL (DialUi): a boot screen until the Pi's first frame,
// then gauges, navigation, media (with the phone's cover behind it), and a
// call over them. The model also goes to the log ("# ..." lines on the same serial
// port, which knob-link logs), so the bench can compare the two.

#include <Arduino.h>
#include <USB.h>
#include <USBHIDConsumerControl.h>
#include <esp_heap_caps.h>
#include <esp_timer.h>

#include <atomic>

#include "Art.h"
#include "Boot.h"
#include "Dial.h"
#include "Frame.h"
#include "DialUi.h"
#include "Pages.h"
#include "Panel.h"
#include "Pins.h"
#include "PulseKnob.h"
#include "Tap.h"
#include "Touch.h"

#ifndef KNOB_VERSION
#define KNOB_VERSION "0.3.0"
#endif

// Below; the board's drivers call them.
void onKnobDetents(int steps);
void onTouch(bool down, bool move, int x, int y);

namespace {

USBHIDConsumerControl consumer;
knob::Dial dial(2000);
knob::TapDetector tap;
knob::Pages pages(3000);
knob::Boot boot;
// The cover being received (180 x 180 RGB565, in PSRAM); null if that
// couldn't be allocated, and covers are then ignored.
knob::ArtAssembler* art = nullptr;

char line[knob::kMaxLine + 2];
size_t lineLen = 0;
bool lineTooLong = false;

struct Counts {
    unsigned config = 0, data = 0, nav = 0, media = 0, call = 0, art = 0, badChecksum = 0, malformed = 0,
             unknown = 0, tooLong = 0, artShown = 0, artFailed = 0;
} counts;

uint32_t lastHelloMs = 0;
constexpr uint32_t kHelloEveryMs = 10000;

// ---- The board (lib/KnobHw) ------------------------------------------------

knob::Panel panel;
knob::Touch touch;
bool panelOk = false;
bool touchOk = false;

// The knob is sampled every 3 ms, as Waveshare's demo does (PulseKnob.h).
knob::PulseKnob pulseKnob;
std::atomic<int> knobSteps{0};
uint32_t knobStepsTotal = 0;
esp_timer_handle_t knobTimer = nullptr;

void sampleKnob(void*)
{
    const int s = pulseKnob.sample(digitalRead(knob::pins::kKnobA) == HIGH, digitalRead(knob::pins::kKnobB) == HIGH);
    if (s != 0) knobSteps.fetch_add(s);
}

bool startKnob()
{
    pinMode(knob::pins::kKnobA, INPUT_PULLUP);
    pinMode(knob::pins::kKnobB, INPUT_PULLUP);
    esp_timer_create_args_t args = {};
    args.callback = sampleKnob;
    args.name = "knob";
    return esp_timer_create(&args, &knobTimer) == ESP_OK && esp_timer_start_periodic(knobTimer, 3000) == ESP_OK;
}
bool knobOk = false;

// Touch, polled: down, moves while held, up.
bool fingerDown = false;
uint32_t lastTouchPollMs = 0;
uint32_t touchesTotal = 0;

void pollTouch(uint32_t now)
{
    if (!touchOk || now - lastTouchPollMs < 15) return;
    lastTouchPollMs = now;
    int x = 0, y = 0;
    const bool down = touch.read(x, y);
    if (down && !fingerDown) {
        touchesTotal++;
        onTouch(true, false, x, y);
    } else if (down) {
        onTouch(false, true, x, y);
    } else if (fingerDown) {
        onTouch(false, false, 0, 0);
    }
    fingerDown = down;
}

void pollKnob()
{
    const int s = knobSteps.exchange(0);
    if (s != 0) {
        knobStepsTotal += static_cast<uint32_t>(s < 0 ? -s : s);
        onKnobDetents(s);
    }
}

// ---- The link -----------------------------------------------------------

void sendLine(const std::string& s) { Serial.print((s + "\n").c_str()); }

void hello()
{
    sendLine(knob::withChecksum("H1 knob-display " KNOB_VERSION));
    Serial.printf("# display %s%s; touch %s (%lu touches, %lu failed reads); knob %s (%lu steps); PSRAM %u bytes\n",
                  panelOk ? "on" : "FAILED: ", panelOk ? "" : panel.lastError(), touchOk ? "on" : "FAILED",
                  static_cast<unsigned long>(touchesTotal), static_cast<unsigned long>(touch.failedReads()),
                  knobOk ? "on" : "FAILED", static_cast<unsigned long>(knobStepsTotal),
                  static_cast<unsigned>(ESP.getPsramSize()));
    Serial.printf("# dial: %lu flushes%s%s\n", static_cast<unsigned long>(knob::uiFlushes()), *knob::uiError() ? "; last error: " : "",
                  knob::uiError());
}

// What the dial would show, as a log line, so the bench can see the model
// work without a screen.
void report(uint32_t now)
{
    // As ADR-0044 decision 3: current, advisory, critical, stale, nothing.
    static const char* const kState = "caksn";
    static const char* const kPage[] = {"gauges", "navigation", "media"};
    static const char* const kBoot[] = {"waiting for the Pi", "head unit starting", "NO HEAD UNIT",
                                        "NO DATA FROM THE PI", "done"};
    Serial.printf("# frames: %u config, %u data, %u nav, %u media, %u call, %u art, %u bad checksum, %u malformed, "
                  "%u unknown, %u too long; %s%s; page %s; boot %s (USB %s, port %s)\n",
                  counts.config, counts.data, counts.nav, counts.media, counts.call, counts.art, counts.badChecksum,
                  counts.malformed,
                  counts.unknown, counts.tooLong, dial.linkLost(now) ? "no data" : "link up",
                  dial.simulated() ? ", SIMULATED" : "", kPage[pages.index()],
                  kBoot[static_cast<int>(boot.stage(static_cast<bool>(USB), now))], USB ? "up" : "down",
                  Serial ? "open" : "closed");
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
    if (art) {
        Serial.printf("#   cover: %s %08lx; %u shown, %u failed\n", art->id() ? "showing" : "none",
                      static_cast<unsigned long>(art->id()), counts.artShown, counts.artFailed);
    }
    // A call takes over the dial (ADR-0045).
    if (const knob::CallFrame* c = pages.call(now)) {
        static const char* const kCall[] = {"", "ringing", "waiting", "dialling", "call", "on hold"};
        Serial.printf("#   CALL %s: %s %s %lu s; %s\n", kCall[static_cast<int>(c->state)], c->caller, c->number,
                      static_cast<unsigned long>(c->activeS), knob::callHint(c->state));
    }
}

void onArt(const knob::ArtFrame& f)
{
    if (!art) return;
    using R = knob::ArtAssembler::Result;
    switch (art->feed(f)) {
        case R::Complete:
            knob::uiArt(art->pixels(), art->width(), art->height());
            counts.artShown++;
            break;
        // A new picture (another track) or none: the old one goes at once.
        case R::Started:
        case R::Cleared: knob::uiArtClear(); break;
        case R::Failed: counts.artFailed++; break;
        case R::Progress:
        case R::Same:
        case R::Ignored: break;
    }
}

void onLine(uint32_t now)
{
    static knob::Frames f;
    const knob::Parsed p = knob::parseLine(std::string_view(line, lineLen), f);
    switch (p) {
        case knob::Parsed::Config:
        case knob::Parsed::Data:
        case knob::Parsed::Nav:
        case knob::Parsed::Media:
        case knob::Parsed::Call:
        case knob::Parsed::Art: boot.onFrame(); break;
        default: break;
    }
    switch (p) {
        case knob::Parsed::Config: dial.onConfig(f.config); counts.config++; break;
        case knob::Parsed::Data: dial.onData(f.data, now); counts.data++; break;
        case knob::Parsed::Nav: pages.onNav(f.nav, now); counts.nav++; break;
        case knob::Parsed::Media: pages.onMedia(f.media, now); counts.media++; break;
        case knob::Parsed::Call: pages.onCall(f.call, now); counts.call++; break;
        case knob::Parsed::Art: onArt(f.art); counts.art++; break;
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

// Called from loop() with the knob's steps since the last call.
void onKnobDetents(int steps)
{
    tap.onTurn(millis());
    for (int i = 0; i < (steps < 0 ? -steps : steps); ++i) {
        press(steps > 0 ? CONSUMER_CONTROL_VOLUME_INCREMENT : CONSUMER_CONTROL_VOLUME_DECREMENT);
    }
}

// The Pi decides what a push would do: during a call answer or hang up
// (audio-manager, ADR-0045), otherwise play or pause. Nothing calls this:
// Waveshare's schematic shows no push switch on the knob (to confirm on the
// bench, ADR-0044).
[[maybe_unused]] void onKnobPush() { press(CONSUMER_CONTROL_PLAY_PAUSE); }

// down: a finger touched; move: it moved; neither: it lifted.
void onTouch(bool down, bool move, int x, int y)
{
    const uint32_t now = millis();
    if (down) {
        tap.onDown(x, y, now);
    } else if (move) {
        tap.onMove(x, y, now);
    } else {
        // During a call touches do nothing (ADR-0045 decision 6).
        if (pages.onTouch(tap.onUp(now), now) == knob::TouchAction::PlayPause) {
            press(CONSUMER_CONTROL_PLAY_PAUSE);
        }
    }
}

void setup()
{
    // The names come from USB_PRODUCT / USB_MANUFACTURER (platformio.ini):
    // with CDC on boot, USB is up before setup().
    consumer.begin();
    USB.begin();
    // A cover is about 86 kB of lines; knob-link paces them, and this holds
    // the bytes that arrive while LVGL draws (Arduino's 256 would drop them).
    Serial.setRxBufferSize(16384);
    Serial.begin(115200);

    if (void* buf = heap_caps_malloc(knob::kArtMaxBytes, MALLOC_CAP_SPIRAM)) {
        art = new knob::ArtAssembler(static_cast<uint8_t*>(buf), knob::kArtMaxBytes);
    }

    panelOk = panel.begin();
    if (panelOk) panelOk = knob::uiBegin(panel, KNOB_VERSION);
    if (panelOk) {
        // The first frame before the backlight comes on: the boot screen.
        knob::uiBoot(boot.stage(static_cast<bool>(USB), millis()), static_cast<bool>(USB), static_cast<bool>(Serial));
        knob::uiUpdate(dial, pages, millis());
        knob::uiRun();
    }
    // On only once there is something on the screen.
    panel.backlight(panelOk ? 200 : 0);
    touchOk = touch.begin();
    knobOk = startKnob();
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
    pollKnob();
    pollTouch(now);
    if (lastHelloMs == 0 || now - lastHelloMs >= kHelloEveryMs) {
        lastHelloMs = now == 0 ? 1 : now;
        hello();
        report(now);
    }
    if (panelOk) {
        static uint32_t lastUiMs = 0;
        if (now - lastUiMs >= 100) {
            lastUiMs = now;
            knob::uiBoot(boot.stage(static_cast<bool>(USB), now), static_cast<bool>(USB), static_cast<bool>(Serial));
            knob::uiUpdate(dial, pages, now);
        }
        knob::uiRun();
    }
    delay(5);
}
