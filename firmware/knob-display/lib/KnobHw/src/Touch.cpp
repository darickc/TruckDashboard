#include "Touch.h"

#include <Arduino.h>
#include <Wire.h>

#include "Panel.h"
#include "Pins.h"

namespace knob {

bool Touch::begin()
{
    // The demo leaves reset alone; a pulse puts the chip in a known state.
    pinMode(pins::kTouchRst, OUTPUT);
    digitalWrite(pins::kTouchRst, LOW);
    delay(10);
    digitalWrite(pins::kTouchRst, HIGH);
    delay(50);
    pinMode(pins::kTouchInt, INPUT);

    if (!Wire.begin(pins::kTouchSda, pins::kTouchScl, 300000)) return false;
    // As the demo: 0 into register 0 ("normal mode").
    Wire.beginTransmission(pins::kTouchAddr);
    Wire.write(0x00);
    Wire.write(0x00);
    return Wire.endTransmission() == 0;
}

bool Touch::read(int& x, int& y)
{
    Wire.beginTransmission(pins::kTouchAddr);
    Wire.write(0x00);
    if (Wire.endTransmission(false) != 0 || Wire.requestFrom(pins::kTouchAddr, 7) != 7) {
        failed_++;
        while (Wire.available()) Wire.read();
        return false;
    }
    uint8_t d[7];
    for (uint8_t& b : d) b = static_cast<uint8_t>(Wire.read());
    if (d[2] == 0) return false;
    x = ((d[3] & 0x0F) << 8) | d[4];
    y = ((d[5] & 0x0F) << 8) | d[6];
    if (x >= Panel::kWidth) x = Panel::kWidth - 1;
    if (y >= Panel::kHeight) y = Panel::kHeight - 1;
    return true;
}

}  // namespace knob
