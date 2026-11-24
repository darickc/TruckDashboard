// The knob's microphone as a USB microphone for the Pi (ADR-0045 spike S4).
// MIC1 is a PDM MEMS mic on the S3 (Pins.h); the S3's I2S peripheral turns
// its PDM into 16 kHz, 16-bit mono PCM in hardware, and a task of its own
// hands each millisecond to TinyUSB's audio class (USBAudioCard, part of the
// same composite device as the serial port and the HID knob). Linux sees a
// USB microphone; the Pi's call path can then use it as AUDIO_CALL_MIC.
//
// A DC blocker removes the PDM filter's constant offset first, then a fixed
// gain (kGain) brings speech up to a level calls expect (Level.h).
// The level of the last second goes to the log, so the bench can tell a
// working mic from silence without recording.

#pragma once

#include <atomic>
#include <cstdint>

class USBAudioCard;

namespace knob {

class Mic {
public:
    static constexpr uint32_t kRate = 16000;
    // A fixed digital gain after the DC blocker: x16, +24 dB (an example,
    // tuned on the bench: speech at arm's length -57 dBFS raw).
    static constexpr int kGain = 16;

    // Starts the PDM input and the task; `uac` must outlive it. False (with
    // lastError) if the I2S input can't start.
    bool begin(USBAudioCard& uac);

    // The last full second.
    float rmsDb() const { return rms_.load(); }
    float peakDb() const { return peak_.load(); }
    // The raw input's offset over the last second (removed before USB).
    float offset() const { return offset_.load(); }
    // Milliseconds read from the mic, and those TinyUSB didn't take whole
    // while the host was recording.
    uint32_t blocks() const { return blocks_.load(); }
    uint32_t dropped() const { return dropped_.load(); }
    // The host has the microphone open (its streaming interface is on).
    bool streaming() const { return streaming_.load(); }
    void setStreaming(bool on) { streaming_.store(on); }
    const char* lastError() const { return error_; }

private:
    static void task(void* self);
    void run();

    USBAudioCard* uac_ = nullptr;
    std::atomic<float> rms_{-120.0f}, peak_{-120.0f}, offset_{0.0f};
    std::atomic<uint32_t> blocks_{0}, dropped_{0};
    std::atomic<bool> streaming_{false};
    const char* error_ = "";
};

}  // namespace knob
