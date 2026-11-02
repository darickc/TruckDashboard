#pragma once
//
// Bluetooth Classic SPP transport to the OBDLink MX+.
//
// The ESP32 runs as SPP *master* (BluetoothSerial::begin(name, true)) and
// initiates the connection to the adapter. Notes:
//   * connect(name) performs a discovery scan first — 10-30 s, blocking.
//   * connect(mac) skips discovery — a few seconds. The remote MAC is logged
//     on every successful connection so it can be pasted into Config.h.
//   * ESP_SPP_CLOSE_EVT from the BT stack is the authoritative disconnect
//     signal; polling connected() alone reacts late.
//
// connect() blocks by design (see IObdTransport contract) and must only be
// called from the OBD task.

#include <BluetoothSerial.h>

#include "IObdTransport.h"

class BtSppTransport : public obd::IObdTransport {
public:
    struct Config {
        const char* localName;      ///< name this ESP32 advertises
        const char* remoteName;     ///< adapter's Bluetooth name
        bool useMac;                ///< connect by MAC (fast) instead of name
        const uint8_t* mac;         ///< 6 bytes, used when useMac
        const char* pin;            ///< SPP pairing PIN ("1234" on the MX+)
    };

    explicit BtSppTransport(const Config& cfg);

    /// Start the Bluetooth stack in master mode. Call once from setup().
    bool begin();

    // IObdTransport
    bool connect() override;
    void disconnect() override;
    bool isConnected() override;
    size_t write(const uint8_t* data, size_t len) override;
    int read() override;
    size_t available() override;

private:
    static void sppCallback(esp_spp_cb_event_t event, esp_spp_cb_param_t* param);
    static BtSppTransport* s_instance; // BluetoothSerial callback has no ctx arg

    BluetoothSerial bt_;
    Config cfg_;
    uint8_t mac_[6] = {0};
    volatile bool linkUp_ = false;
};
