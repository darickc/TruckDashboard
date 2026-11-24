// The ESP32-S3's pins on Waveshare's ESP32-S3-Knob-Touch-LCD-1.8 (ADR-0044).
// Source: Waveshare's schematic (2_ESP32S3-R8.png, 1_LCD&POWER.png) and demo
// (08_LVGL_Test/lcd_config.h, 04_Encoder_Test), which agree; downloaded
// 2026-11-22. [BENCH] once checked on the board: see ADR-0044.

#pragma once

namespace knob::pins {

// Display, QSPI (the tearing-effect line isn't wired to the S3).
constexpr int kLcdClk = 13;
constexpr int kLcdCs = 14;
constexpr int kLcdD0 = 15;
constexpr int kLcdD1 = 16;
constexpr int kLcdD2 = 17;
constexpr int kLcdD3 = 18;
constexpr int kLcdRst = 21;
// Backlight: PWM into a MOSFET (AO3400A) on the backlight's cathode.
constexpr int kLcdBacklight = 47;

// Touch (CST816, I2C 0x15), 5.1 kΩ pull-ups. The DRV2605 vibration driver
// shares the bus; nothing here drives it.
constexpr int kTouchSda = 11;
constexpr int kTouchScl = 12;
constexpr int kTouchInt = 9;
constexpr int kTouchRst = 10;
constexpr int kTouchAddr = 0x15;

// The knob: two switch lines to ground, 10 kΩ pull-ups (PulseKnob.h).
constexpr int kKnobA = 8;
constexpr int kKnobB = 7;

// The microphone (MIC1, MSM261D4030H1CPM, a PDM MEMS mic; 4_OTHER.png): its
// clock from the S3 and its data back, L/R tied to ground (the left half of
// each clock). Both are strapping pins (GPIO45 VDD_SPI, GPIO46 boot), so
// nothing may drive them at reset: the clock is only started by Mic, and
// the mic's data is high-impedance without a clock.
constexpr int kMicClk = 45;
constexpr int kMicData = 46;

}  // namespace knob::pins
