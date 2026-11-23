// The CST816 touch controller (I2C 0x15), polled. Register layout as in
// Waveshare's demo (cst816.cpp): read 7 bytes from 0x00; byte 2 is the number
// of fingers, bytes 3..6 hold X and Y in 12 bits each.

#pragma once

#include <cstdint>

namespace knob {

class Touch {
public:
    bool begin();
    // True while a finger is down, with its position in screen pixels. A
    // read that fails (the chip can sleep between touches) is "no finger".
    bool read(int& x, int& y);
    uint32_t failedReads() const { return failed_; }

private:
    uint32_t failed_ = 0;
};

}  // namespace knob
