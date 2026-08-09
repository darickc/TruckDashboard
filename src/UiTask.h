#pragma once
//
// UI tick: derived values -> warnings -> render. Runs on the Arduino loop
// task; operates on a value-copy Snapshot so it can never block (or be
// blocked by) the OBD task.

#include "ElmClient.h"
#include "IDisplay.h"
#include "IObdTransport.h"
#include "VehicleData.h"
#include "Warnings.h"

struct UiContext {
    obd::VehicleData* data;
    obd::WarningManager* warnings;
    IDisplay* display;
    obd::ElmClient* elm;
    obd::IObdTransport* transport;

    /// Shared with the console (same task). False silences rendering only —
    /// derived values and warnings keep updating, so nothing goes stale while
    /// the display is paused.
    bool* enabled;
};

void uiTick(UiContext& ctx);
