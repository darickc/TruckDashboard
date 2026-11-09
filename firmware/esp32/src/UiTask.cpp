#include "UiTask.h"

#include <Arduino.h>

#include "Config.h"
#include "Derived.h"

void uiTick(UiContext& ctx)
{
    const uint32_t now = millis();

    obd::derived::update(*ctx.data, now, {config::kStaleAfterMs});

    const obd::Snapshot snap = ctx.data->snapshot(now);
    const bool connected = ctx.transport->isConnected() && ctx.elm->isReady();
    ctx.warnings->evaluate(snap, connected);

    // Warnings and derived values are updated above whatever the display is
    // doing — only the rendering is silenceable.
    if (ctx.enabled != nullptr && !*ctx.enabled) {
        return;
    }

    DisplaySnapshot ds;
    ds.data = snap;
    ds.warnings = ctx.warnings->state();
    ds.page = PageId::EngineHealth; // page navigation (touch/button) comes later
    ds.btConnected = ctx.transport->isConnected();
    ds.link = ctx.elm->state();
    ds.staleAfterMs = config::kStaleAfterMs;
    ctx.display->render(ds);
}
