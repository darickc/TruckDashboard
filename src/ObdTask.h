#pragma once
//
// OBD task: owns everything Bluetooth/adapter-facing.
//   connect (blocking, with backoff) -> ELM init -> scheduled PID polling ->
//   decode -> VehicleData. Reconnects forever on any loss.

#include "BtSppTransport.h"
#include "ElmClient.h"
#include "PidScheduler.h"
#include "VehicleData.h"

struct ObdTaskContext {
    BtSppTransport* transport;
    obd::ElmClient* elm;
    obd::PidScheduler* scheduler;
    obd::VehicleData* data;
};

/// Spawn the OBD FreeRTOS task. `ctx` must outlive the task (file-scope).
void startObdTask(ObdTaskContext& ctx);

/// ElmClient result handler (decode + store); registered by main.cpp.
void obdOnResult(void* ctx, const obd::PidDefinition& pid, obd::ElmResult result,
                 const uint8_t* payload, size_t len);
