#include "BtSppTransport.h"

#include <cstring>

#include "Log.h"

static const char* kTag = "bt";

BtSppTransport* BtSppTransport::s_instance = nullptr;

BtSppTransport::BtSppTransport(const Config& cfg) : cfg_(cfg)
{
    if (cfg_.mac != nullptr) {
        std::memcpy(mac_, cfg_.mac, sizeof(mac_));
    }
    s_instance = this;
}

bool BtSppTransport::begin()
{
    bt_.register_callback(&BtSppTransport::sppCallback);
    // `true` = master mode; required to initiate connections to the adapter.
    if (!bt_.begin(cfg_.localName, true)) {
        LOGE(kTag, "BluetoothSerial begin() failed");
        return false;
    }
    if (cfg_.pin != nullptr && cfg_.pin[0] != '\0') {
        bt_.setPin(cfg_.pin);
    }
    LOGI(kTag, "Bluetooth Classic up as '%s' (master)", cfg_.localName);
    return true;
}

bool BtSppTransport::connect()
{
    // BLOCKING (seconds to tens of seconds) — only called from the OBD task.
    bool ok;
    if (cfg_.useMac) {
        LOGI(kTag, "connecting by MAC %02X:%02X:%02X:%02X:%02X:%02X ...",
             mac_[0], mac_[1], mac_[2], mac_[3], mac_[4], mac_[5]);
        ok = bt_.connect(mac_);
    } else {
        LOGI(kTag, "connecting by name '%s' (discovery scan, may take ~10-30 s;"
                   " set kUseObdMac in Config.h to speed this up) ...",
             cfg_.remoteName);
        ok = bt_.connect(cfg_.remoteName);
    }
    if (!ok) {
        LOGW(kTag, "connect failed");
        return false;
    }
    linkUp_ = true;
    LOGI(kTag, "SPP link established");
    return true;
}

void BtSppTransport::disconnect()
{
    bt_.disconnect();
    linkUp_ = false;
}

bool BtSppTransport::isConnected()
{
    return linkUp_;
}

size_t BtSppTransport::write(const uint8_t* data, size_t len)
{
    if (!linkUp_) {
        return 0;
    }
    return bt_.write(data, len);
}

int BtSppTransport::read()
{
    return bt_.read(); // -1 when empty
}

size_t BtSppTransport::available()
{
    const int n = bt_.available();
    return n > 0 ? static_cast<size_t>(n) : 0;
}

void BtSppTransport::sppCallback(esp_spp_cb_event_t event, esp_spp_cb_param_t* param)
{
    BtSppTransport* self = s_instance;
    if (self == nullptr) {
        return;
    }
    switch (event) {
    case ESP_SPP_OPEN_EVT: {
        // Master-mode connection established: log the adapter's MAC so the
        // user can pin it in Config.h for fast reconnects.
        const uint8_t* b = param->open.rem_bda;
        LOGI(kTag, "connected to %02X:%02X:%02X:%02X:%02X:%02X"
                   " — paste into Config.h kObdMac for fast reconnects",
             b[0], b[1], b[2], b[3], b[4], b[5]);
        self->linkUp_ = true;
        break;
    }
    case ESP_SPP_CLOSE_EVT:
        LOGW(kTag, "SPP link closed");
        self->linkUp_ = false;
        break;
    default:
        break;
    }
}
