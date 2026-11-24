#include "Mic.h"

#include <Arduino.h>
#include <ESP_I2S.h>
#include <USBAudioCard.h>

#include "Level.h"
#include "Pins.h"

namespace knob {

namespace {

I2SClass gI2s;

}  // namespace

bool Mic::begin(USBAudioCard& uac)
{
    uac_ = &uac;
    gI2s.setPinsPdmRx(pins::kMicClk, pins::kMicData);
    if (!gI2s.begin(I2S_MODE_PDM_RX, kRate, I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_MONO)) {
        error_ = "I2S PDM input didn't start";
        return false;
    }
    // Core 0, above Arduino's loop (core 1): drawing never holds it up.
    if (xTaskCreatePinnedToCore(task, "mic", 4096, this, 5, nullptr, 0) != pdPASS) {
        error_ = "no memory for the mic task";
        return false;
    }
    return true;
}

void Mic::task(void* self) { static_cast<Mic*>(self)->run(); }

void Mic::run()
{
    // One millisecond: 16 samples.
    constexpr size_t kBlock = kRate / 1000;
    int16_t buf[kBlock];
    LevelMeter meter;
    DcBlocker dc;
    for (;;) {
        const size_t got = gI2s.readBytes(reinterpret_cast<char*>(buf), sizeof(buf));
        if (got != sizeof(buf)) continue;
        blocks_.fetch_add(1);
        dc.process(buf, kBlock);
        applyGain(buf, kBlock, kGain);
        meter.add(buf, kBlock);
        if (meter.samples() >= kRate) {
            offset_.store(dc.takeMean());
            rms_.store(meter.rmsDb());
            peak_.store(meter.peakDb());
            meter.reset();
        }
        const uint16_t taken = uac_->write(buf, sizeof(buf));
        if (streaming_.load() && taken != sizeof(buf)) dropped_.fetch_add(1);
    }
}

}  // namespace knob
