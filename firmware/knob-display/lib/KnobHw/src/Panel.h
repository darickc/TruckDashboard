// The round 360 x 360 display over QSPI, and its backlight (ADR-0044).
// The framing follows Waveshare's demo driver (an Espressif QSPI panel
// driver, Apache-2.0): a 32-bit command word, opcode 0x02 for commands with
// parameters and 0x32 for pixels, the panel command in bits 8..15. RGB565,
// high byte first. Windows start and end on even pixels (the demo rounds
// them so).

#pragma once

#include <cstddef>
#include <cstdint>

namespace knob {

class Panel {
public:
    static constexpr int kWidth = 360;
    static constexpr int kHeight = 360;

    // Starts the SPI bus, resets the panel and sends its start-up commands.
    // False (and a reason in lastError()) if any step fails.
    bool begin();

    // Pixels for the window [x0, x1) x [y0, y1), row by row, RGB565 with the
    // high byte first, in DMA-capable memory. x0 and y0 even, x1 and y1 even.
    // Returns once the panel has the pixels (the buffer can be reused).
    bool draw(int x0, int y0, int x1, int y1, const uint16_t* pixels);

    // 0 (off) .. 255.
    void backlight(uint8_t level);

    const char* lastError() const { return error_; }

private:
    bool command(uint8_t cmd, const uint8_t* data, size_t len);

    void* io_ = nullptr;  // esp_lcd_panel_io_handle_t
    void* done_ = nullptr;  // SemaphoreHandle_t
    const char* error_ = "not started";
};

// RGB565, high byte first, as the panel takes it.
constexpr uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b)
{
    const uint16_t v = static_cast<uint16_t>(((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3));
    return static_cast<uint16_t>((v >> 8) | (v << 8));
}

}  // namespace knob
