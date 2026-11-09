#pragma once
//
// Byte-stream transport to the OBD adapter.
//
// Contract:
//   * connect() MAY BLOCK (BluetoothSerial master-mode connect blocks for
//     seconds). It is only ever called from the dedicated OBD task, never
//     from the UI path.
//   * read()/write()/available() must NEVER block.
//
// Implementations: BtSppTransport (Bluetooth Classic SPP to the OBDLink MX+)
// and MockTransport (scripted, for unit tests).

#include <cstddef>
#include <cstdint>

namespace obd {

class IObdTransport {
public:
    virtual ~IObdTransport() = default;

    /// Establish the link. May block for several seconds. Returns success.
    virtual bool connect() = 0;

    /// Tear down the link.
    virtual void disconnect() = 0;

    /// Current link state. Must be cheap; called every loop iteration.
    virtual bool isConnected() = 0;

    /// Queue bytes for transmission. Returns bytes accepted. Non-blocking.
    virtual size_t write(const uint8_t* data, size_t len) = 0;

    /// One received byte, or -1 if none pending. Non-blocking.
    virtual int read() = 0;

    /// Number of received bytes pending.
    virtual size_t available() = 0;
};

} // namespace obd
