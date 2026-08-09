#include "ObdTask.h"

#include <Arduino.h>

#include "Config.h"
#include "Decoders.h"
#include "Log.h"
#include "Units.h"

static const char* kTag = "obd";

void obdOnResult(void* ctxPtr, const obd::PidDefinition& pid, obd::ElmResult result,
                 const uint8_t* payload, size_t len)
{
    auto* ctx = static_cast<ObdTaskContext*>(ctxPtr);
    const uint32_t now = millis();

    if (result != obd::ElmResult::Ok) {
        LOGW(kTag, "%s: %s", pid.name, obd::elmResultName(result));
        ctx->scheduler->onResult(pid, false, now);
        ctx->data->markError(pid.channel);
        return;
    }

    float value = 0.0f;
    if (!obd::decodePid(pid, payload, len, value)) {
        LOGW(kTag, "%s: decode failed (payload %u bytes)", pid.name,
             static_cast<unsigned>(len));
        ctx->scheduler->onResult(pid, false, now);
        ctx->data->markError(pid.channel);
        return;
    }

    const obd::Unit chUnit = obd::channelUnit(pid.channel);
    const float converted = obd::convertUnit(value, pid.unit, chUnit);
    ctx->data->set(pid.channel, converted, now);
    ctx->scheduler->onResult(pid, true, now);
    LOGD(kTag, "%s = %.2f %s%s", pid.name, static_cast<double>(converted),
         obd::unitSuffix(chUnit),
         pid.verified ? "" : "  [UNVERIFIED - confirm against known-good tool]");
}

namespace {

void obdTaskFn(void* param)
{
    auto& ctx = *static_cast<ObdTaskContext*>(param);
    uint32_t backoffMs = config::kReconnectMinMs;

    for (;;) {
        // --- (Re)establish the Bluetooth link -----------------------------
        if (!ctx.transport->isConnected()) {
            ctx.elm->onTransportLost();
            if (ctx.transport->connect()) { // blocks; that's fine in this task
                backoffMs = config::kReconnectMinMs;
                ctx.elm->begin();
                ctx.scheduler->resetTiming(millis());
            } else {
                LOGW(kTag, "reconnect in %lu ms", static_cast<unsigned long>(backoffMs));
                vTaskDelay(pdMS_TO_TICKS(backoffMs));
                backoffMs = backoffMs * 2 < config::kReconnectMaxMs
                                ? backoffMs * 2
                                : config::kReconnectMaxMs;
            }
            continue;
        }

        // --- Adapter gave up (unresponsive): drop BT and start over -------
        if (ctx.elm->state() == obd::ElmState::Offline) {
            LOGW(kTag, "adapter unresponsive — dropping Bluetooth link");
            ctx.transport->disconnect();
            vTaskDelay(pdMS_TO_TICKS(config::kReconnectMinMs));
            continue;
        }

        // --- Normal operation ---------------------------------------------
        ctx.elm->tick();
        if (ctx.elm->state() == obd::ElmState::Idle) {
            if (const obd::PidDefinition* pid = ctx.scheduler->next(millis())) {
                ctx.elm->submit(*pid);
            }
        }
        vTaskDelay(pdMS_TO_TICKS(2)); // yield; keeps the idle task fed (TWDT)
    }
}

} // namespace

void startObdTask(ObdTaskContext& ctx)
{
    // Core 1 keeps the OBD state machine off core 0, which the Bluetooth
    // controller/stack tasks use heavily. Priority above the UI (loopTask,
    // prio 1) but well below the BT stack.
    xTaskCreatePinnedToCore(obdTaskFn, "obd", 8192, &ctx, 3, nullptr, 1);
}
