// The dial on the screen (ADR-0044 decisions 4, 5 and 9; ADR-0045 decision
// 6), drawn with LVGL from KnobCore's model: the gauges, navigation and media
// pages, and a phone call over all of them. Nothing here decides what a
// value means: Dial and Pages do, and this only draws what they say.

#pragma once

#include <cstdint>

#include "Dial.h"
#include "Pages.h"
#include "Panel.h"

namespace knob {

// Starts LVGL on the panel and builds the screens. False if LVGL's draw
// buffer can't be allocated.
bool uiBegin(Panel& panel);

// Copies the model onto the screen; call every 100 ms or so.
void uiUpdate(const Dial& dial, const Pages& pages, uint32_t nowMs);

// LVGL's own work (drawing); call from loop().
void uiRun();

// Frames drawn so far, and the last flush error ("" for none), for the log.
uint32_t uiFlushes();
const char* uiError();

}  // namespace knob
