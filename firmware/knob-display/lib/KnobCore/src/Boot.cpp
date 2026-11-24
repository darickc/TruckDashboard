#include "Boot.h"

namespace knob {

BootStage Boot::stage(bool usbMounted, uint32_t nowMs) const
{
    if (heard_) return BootStage::Done;
    if (nowMs >= giveUpMs_) return usbMounted ? BootStage::NoLink : BootStage::NoHeadUnit;
    return usbMounted ? BootStage::Starting : BootStage::WaitingForPi;
}

const char* bootStatus(BootStage s)
{
    switch (s) {
        case BootStage::WaitingForPi: return "WAITING FOR THE PI";
        case BootStage::Starting: return "HEAD UNIT STARTING";
        case BootStage::NoHeadUnit: return "NO HEAD UNIT";
        case BootStage::NoLink: return "NO DATA FROM THE PI";
        case BootStage::Done: return "";
    }
    return "";
}

const char* bootHint(BootStage s)
{
    switch (s) {
        case BootStage::NoHeadUnit: return "CHECK THE USB CABLE";
        case BootStage::NoLink: return "IS KNOB-LINK RUNNING?";
        default: return "";
    }
}

}  // namespace knob
