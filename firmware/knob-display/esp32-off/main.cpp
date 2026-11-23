// The knob board's second ESP32 (ESP32-U4WDH; ADR-0044 decision 1). As
// shipped it advertises Bluetooth audio (TAIJI_KNOB_AUDIO) and a Bluetooth
// HID knob (TAIJI_KNOB_HID). This firmware makes it do nothing: it starts
// neither Wi-Fi nor Bluetooth (Arduino starts no radio unless asked, and
// releases the Bluetooth controller's memory when nothing uses it), says so
// once on its UART, and sleeps with no wake source until the next reset.
//
// Its UART is the board's CH340, reached with the USB-C plug turned over.
// The CH340's reset lines put the chip in its loader whatever runs, so the
// sleep doesn't get in the way of flashing it again:
//
//   make knob-esp32-off PORT=/dev/cu.usbserial-XXXX
//
// Nothing in this project uses the board's DAC, this chip's knob encoder or
// its UART to the S3; the schematic gives the S3 its own I2S path to the DAC
// (a switch on S3 GPIO0). So nothing needs this chip awake.

#include <Arduino.h>
#include <esp_sleep.h>

#ifndef KNOB_ESP32_OFF_VERSION
#define KNOB_ESP32_OFF_VERSION "1.0.0"
#endif

void setup()
{
    Serial.begin(115200);
    Serial.println("knob-esp32-off " KNOB_ESP32_OFF_VERSION
                   ": no Wi-Fi, no Bluetooth; deep sleep, no wake source (ADR-0044)");
    Serial.flush();
    esp_deep_sleep_start();
}

void loop() {}
