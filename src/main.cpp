//
// TruckDashboard — ESP32 digital gauge for a 2007 Ford F-250 6.0L Power Stroke.
//
// main.cpp only wires objects together and starts the tasks:
//   * ObdTask (core 1, prio 3): Bluetooth SPP to the OBDLink MX+, ELM init,
//     PID polling, decoding into VehicleData. The blocking Bluetooth connect
//     lives there and can never freeze the UI.
//   * loopTask (prio 1): derived values, warnings, display rendering — works
//     on value-copy snapshots of VehicleData.
// The single piece of shared state, VehicleData, is guarded by one FreeRTOS
// mutex installed below.

#include <Arduino.h>

#include "BtSppTransport.h"
#include "Config.h"
#include "ElmClient.h"
#include "Log.h"
#include "ObdTask.h"
#include "PidScheduler.h"
#include "SerialDisplay.h"
#include "UiTask.h"
#include "VehicleData.h"
#include "Warnings.h"

// ---------------------------------------------------------------------------
// Objects (static storage — no dynamic allocation after boot)
// ---------------------------------------------------------------------------
static BtSppTransport g_transport({
    config::kBtLocalName,
    config::kObdDeviceName,
    config::kUseObdMac,
    config::kObdMac,
    config::kObdPin,
});

static const obd::ElmConfig g_elmConfig = [] {
    obd::ElmConfig c;
    c.initCommands = config::kElmInitCommands;
    c.initCommandCount = config::kElmInitCommandCount;
    return c;
}();

static uint32_t nowMs() { return millis(); }

static obd::ElmClient g_elm(g_transport, nowMs, g_elmConfig);
static obd::VehicleData g_vehicleData;
static obd::PidScheduler g_scheduler;
static obd::WarningManager g_warnings;
static SerialDisplay g_display(config::kDisplayIntervalMs);

static ObdTaskContext g_obdCtx{&g_transport, &g_elm, &g_scheduler, &g_vehicleData};
static UiContext g_uiCtx{&g_vehicleData, &g_warnings, &g_display, &g_elm, &g_transport};

// VehicleData lock hooks: one FreeRTOS mutex.
static SemaphoreHandle_t g_vdMutex = nullptr;
static void vdLock(void*) { xSemaphoreTake(g_vdMutex, portMAX_DELAY); }
static void vdUnlock(void*) { xSemaphoreGive(g_vdMutex); }

// ---------------------------------------------------------------------------

void setup()
{
    Serial.begin(config::kSerialBaud);
    delay(100);
    tdlog::setLevel(config::kRuntimeLogLevel);
    LOGI("main", "TruckDashboard starting (build " __DATE__ " " __TIME__ ")");

    g_vdMutex = xSemaphoreCreateMutex();
    g_vehicleData.setLockHooks(vdLock, vdUnlock, nullptr);

    obd::SchedulerConfig schedCfg;
    schedCfg.measuredRequestsPerSec = config::kMeasuredRequestsPerSec;
    g_scheduler.begin(obd::kPidTable, obd::kPidTableSize,
                      config::kEnabledPids, config::kEnabledPidCount, schedCfg);
    g_warnings.begin(config::kWarningRules, config::kWarningRuleCount,
                     config::kStaleAfterMs);
    g_display.begin();

    g_elm.setResultHandler(obdOnResult, &g_obdCtx);
    g_elm.setRawLogging(config::kLogRawObdTraffic);

    if (!g_transport.begin()) {
        LOGE("main", "Bluetooth failed to start — rebooting in 5 s");
        delay(5000);
        ESP.restart();
    }

    startObdTask(g_obdCtx);
    LOGI("main", "setup complete — OBD task running");
}

void loop()
{
    uiTick(g_uiCtx);
    vTaskDelay(pdMS_TO_TICKS(config::kUiTickMs));
}
