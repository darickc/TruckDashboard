// The boot screen (owner, 2026-11-23): what the dial says from power-on until
// knob-link's first frame, instead of the gauges' red NO DATA ring. The knob
// is powered by the Pi's USB, so it lights as soon as the Pi has power and
// shows the Pi coming up in steps:
//
//   USB   the Pi has configured the knob's USB (its kernel is up)
//   LINK  something opened the knob's serial port (knob-link, normally)
//   DATA  the first valid frame: the boot screen goes for good
//
// After that, losing the link is the gauges' NO DATA ring as before: the boot
// screen is only for the first start. If no frame has come after
// `giveUpMs`, it says what is missing instead of spinning on.

#pragma once

#include <cstdint>

namespace knob {

enum class BootStage : uint8_t {
    WaitingForPi,  // no USB host yet
    Starting,      // USB up (and perhaps the port open); no frame yet
    NoHeadUnit,    // still no USB host after giveUpMs
    NoLink,        // USB up but still no frame after giveUpMs
    Done,          // a frame came: the dial's pages from now on
};

class Boot {
public:
    explicit Boot(uint32_t giveUpMs = 180000) : giveUpMs_(giveUpMs) {}

    // A valid frame from the Pi (any kind).
    void onFrame() { heard_ = true; }

    BootStage stage(bool usbMounted, uint32_t nowMs) const;

private:
    uint32_t giveUpMs_;
    bool heard_ = false;
};

// The status line and the line under it ("" for none) for a stage.
const char* bootStatus(BootStage s);
const char* bootHint(BootStage s);

}  // namespace knob
