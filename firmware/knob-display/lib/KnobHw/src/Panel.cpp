#include "Panel.h"

#include <Arduino.h>
#include <driver/spi_master.h>
#include <esp_lcd_panel_io.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>

#include "Pins.h"

namespace knob {

namespace {

struct InitCmd {
    uint8_t cmd;
    uint8_t len;
    uint8_t delayMs;
    uint8_t data[14];
};

const InitCmd kInit[] = {
#include "PanelInit.inc"
};

constexpr spi_host_device_t kHost = SPI2_HOST;
constexpr uint32_t kOpWriteCmd = 0x02;
constexpr uint32_t kOpWriteColor = 0x32;
constexpr uint8_t kRamWrite = 0x2C;
constexpr uint8_t kColumns = 0x2A;
constexpr uint8_t kRows = 0x2B;
constexpr uint8_t kMadctl = 0x36;
constexpr uint8_t kColmod = 0x3A;
// The most one draw() sends: 40 full rows (DMA-capable RAM is the limit).
constexpr size_t kMaxTransfer = static_cast<size_t>(Panel::kWidth) * 40 * 2;

bool onColorDone(esp_lcd_panel_io_handle_t, esp_lcd_panel_io_event_data_t*, void* ctx)
{
    BaseType_t woke = pdFALSE;
    xSemaphoreGiveFromISR(static_cast<SemaphoreHandle_t>(ctx), &woke);
    return woke == pdTRUE;
}

}  // namespace

bool Panel::command(uint8_t cmd, const uint8_t* data, size_t len)
{
    const int word = static_cast<int>((kOpWriteCmd << 24) | (static_cast<uint32_t>(cmd) << 8));
    return esp_lcd_panel_io_tx_param(static_cast<esp_lcd_panel_io_handle_t>(io_), word, data, len) == ESP_OK;
}

bool Panel::begin()
{
    done_ = xSemaphoreCreateBinary();
    if (!done_) {
        error_ = "no memory for a semaphore";
        return false;
    }

    spi_bus_config_t bus = {};
    bus.sclk_io_num = pins::kLcdClk;
    bus.data0_io_num = pins::kLcdD0;
    bus.data1_io_num = pins::kLcdD1;
    bus.data2_io_num = pins::kLcdD2;
    bus.data3_io_num = pins::kLcdD3;
    bus.data4_io_num = -1;
    bus.data5_io_num = -1;
    bus.data6_io_num = -1;
    bus.data7_io_num = -1;
    bus.max_transfer_sz = kMaxTransfer;
    bus.flags = SPICOMMON_BUSFLAG_MASTER | SPICOMMON_BUSFLAG_QUAD;
    if (spi_bus_initialize(kHost, &bus, SPI_DMA_CH_AUTO) != ESP_OK) {
        error_ = "spi_bus_initialize failed";
        return false;
    }

    // As the demo's QSPI configuration: mode 0, 40 MHz, 32-bit command word.
    esp_lcd_panel_io_spi_config_t cfg = {};
    cfg.cs_gpio_num = static_cast<gpio_num_t>(pins::kLcdCs);
    cfg.dc_gpio_num = GPIO_NUM_NC;
    cfg.spi_mode = 0;
    cfg.pclk_hz = 40 * 1000 * 1000;
    cfg.trans_queue_depth = 4;
    cfg.on_color_trans_done = onColorDone;
    cfg.user_ctx = done_;
    cfg.lcd_cmd_bits = 32;
    cfg.lcd_param_bits = 8;
    cfg.flags.quad_mode = 1;
    esp_lcd_panel_io_handle_t io = nullptr;
    if (esp_lcd_new_panel_io_spi(static_cast<esp_lcd_spi_bus_handle_t>(kHost), &cfg, &io) != ESP_OK) {
        error_ = "esp_lcd_new_panel_io_spi failed";
        return false;
    }
    io_ = io;

    // Hardware reset, timings as the demo's.
    pinMode(pins::kLcdRst, OUTPUT);
    digitalWrite(pins::kLcdRst, LOW);
    delay(10);
    digitalWrite(pins::kLcdRst, HIGH);
    delay(150);

    const uint8_t madctl = 0x00, colmod = 0x55;  // RGB order, 16 bits a pixel
    if (!command(kMadctl, &madctl, 1) || !command(kColmod, &colmod, 1)) {
        error_ = "the panel didn't take MADCTL/COLMOD";
        return false;
    }
    for (const InitCmd& c : kInit) {
        if (!command(c.cmd, c.len ? c.data : nullptr, c.len)) {
            error_ = "the panel didn't take its start-up commands";
            return false;
        }
        if (c.delayMs) delay(c.delayMs);
    }
    error_ = "";
    return true;
}

bool Panel::draw(int x0, int y0, int x1, int y1, const uint16_t* pixels)
{
    if (!io_ || x0 < 0 || y0 < 0 || x1 > kWidth || y1 > kHeight || x0 >= x1 || y0 >= y1 || (x0 | y0 | x1 | y1) & 1) {
        error_ = "draw: bad window";
        return false;
    }
    const size_t bytes = static_cast<size_t>(x1 - x0) * (y1 - y0) * 2;
    if (bytes > kMaxTransfer) {
        error_ = "draw: window larger than one transfer";
        return false;
    }
    const uint8_t cols[] = {static_cast<uint8_t>(x0 >> 8), static_cast<uint8_t>(x0), static_cast<uint8_t>((x1 - 1) >> 8),
                            static_cast<uint8_t>(x1 - 1)};
    const uint8_t rows[] = {static_cast<uint8_t>(y0 >> 8), static_cast<uint8_t>(y0), static_cast<uint8_t>((y1 - 1) >> 8),
                            static_cast<uint8_t>(y1 - 1)};
    if (!command(kColumns, cols, sizeof(cols)) || !command(kRows, rows, sizeof(rows))) {
        error_ = "draw: window commands failed";
        return false;
    }
    const int word = static_cast<int>((kOpWriteColor << 24) | (static_cast<uint32_t>(kRamWrite) << 8));
    if (esp_lcd_panel_io_tx_color(static_cast<esp_lcd_panel_io_handle_t>(io_), word, pixels, bytes) != ESP_OK) {
        error_ = "draw: tx_color failed";
        return false;
    }
    if (xSemaphoreTake(static_cast<SemaphoreHandle_t>(done_), pdMS_TO_TICKS(200)) != pdTRUE) {
        error_ = "draw: the transfer didn't finish in 200 ms";
        return false;
    }
    return true;
}

void Panel::backlight(uint8_t level)
{
    static bool attached = false;
    if (!attached) {
        // 50 kHz, 8 bits, as the demo.
        attached = ledcAttach(pins::kLcdBacklight, 50000, 8);
        if (!attached) {
            error_ = "backlight: ledcAttach failed";
            return;
        }
    }
    ledcWrite(pins::kLcdBacklight, level);
}

}  // namespace knob
