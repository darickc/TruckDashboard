#pragma once
//
// Display abstraction.
//
// The final hardware is an (as yet unselected) 1.75" round 466x466 AMOLED.
// Until the exact controller is known, nothing in the project may depend on
// a graphics library: renderers implement this interface against a value-copy
// DisplaySnapshot, so the OBD stack never touches graphics code and the
// project compiles (and runs, via SerialDisplay) with no display hardware.
//
// Adding the real display later = implement IDisplay in a new class and swap
// the instance in main.cpp. See docs/esp32/DISPLAY_PLAN.md.

#include <cstdint>

#include "ElmClient.h"
#include "VehicleData.h"
#include "Warnings.h"

enum class PageId : uint8_t {
    EngineHealth, ///< ECT/EOT, delta, FICM, ICP, IPR
    Drivetrain,   ///< boost, trans temp, RPM, VGT, battery, load
    LargeGauge,   ///< single big value (boost)
    Count,
};

/// Everything a renderer needs, copied by value — rendering never touches
/// live shared state and can never block the OBD task.
struct DisplaySnapshot {
    obd::Snapshot data;
    obd::WarningState warnings;
    PageId page = PageId::EngineHealth;
    bool btConnected = false;
    obd::ElmState link = obd::ElmState::Offline;
    uint32_t staleAfterMs = 3000;
};

class IDisplay {
public:
    virtual ~IDisplay() = default;
    virtual void begin() = 0;
    /// Must be cheap and non-blocking (renderers throttle themselves).
    virtual void render(const DisplaySnapshot& snap) = 0;
    virtual void setPage(PageId page) = 0;
};
