#pragma once
//
// Header-only leveled logger.
//
// Two knobs:
//   * Compile-time floor: -DTD_LOG_LEVEL=N (0=OFF..5=TRACE). Calls below the
//     floor compile out entirely — safe to leave TRACE calls in hot paths.
//   * Runtime ceiling: tdlog::setLevel(). Never exceeds the compile-time floor.
//
// Output goes to Serial.printf on Arduino targets and stdio natively, so the
// platform-independent core (lib/ObdCore) can log without touching Arduino.h.
//
// NOTE: writes from multiple FreeRTOS tasks may interleave at line granularity;
// each call formats into a stack buffer first so a single line never tears.

#include <cstdarg>
#include <cstdint>
#include <cstdio>

#ifdef ARDUINO
#include <Arduino.h>
#endif

#ifndef TD_LOG_LEVEL
#define TD_LOG_LEVEL 3 // default: INFO
#endif

enum class TdLogLevel : uint8_t {
    Off   = 0,
    Error = 1,
    Warn  = 2,
    Info  = 3,
    Debug = 4,
    Trace = 5,
};

namespace tdlog {

inline TdLogLevel g_runtimeLevel = static_cast<TdLogLevel>(TD_LOG_LEVEL);

inline void setLevel(TdLogLevel level) { g_runtimeLevel = level; }
inline TdLogLevel level() { return g_runtimeLevel; }

inline void write(TdLogLevel lvl, const char* tag, const char* fmt, ...)
{
    if (static_cast<uint8_t>(lvl) > static_cast<uint8_t>(g_runtimeLevel)) {
        return;
    }
    static const char* kNames = "?EWIDT"; // index by level
    char buf[192];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
#ifdef ARDUINO
    Serial.printf("[%8lu] %c %-4s %s\r\n",
                  static_cast<unsigned long>(millis()),
                  kNames[static_cast<uint8_t>(lvl)], tag, buf);
#else
    std::printf("%c %-4s %s\n", kNames[static_cast<uint8_t>(lvl)], tag, buf);
#endif
}

} // namespace tdlog

#if TD_LOG_LEVEL >= 1
#define LOGE(tag, ...) tdlog::write(TdLogLevel::Error, tag, __VA_ARGS__)
#else
#define LOGE(tag, ...) ((void)0)
#endif

#if TD_LOG_LEVEL >= 2
#define LOGW(tag, ...) tdlog::write(TdLogLevel::Warn, tag, __VA_ARGS__)
#else
#define LOGW(tag, ...) ((void)0)
#endif

#if TD_LOG_LEVEL >= 3
#define LOGI(tag, ...) tdlog::write(TdLogLevel::Info, tag, __VA_ARGS__)
#else
#define LOGI(tag, ...) ((void)0)
#endif

#if TD_LOG_LEVEL >= 4
#define LOGD(tag, ...) tdlog::write(TdLogLevel::Debug, tag, __VA_ARGS__)
#else
#define LOGD(tag, ...) ((void)0)
#endif

#if TD_LOG_LEVEL >= 5
#define LOGT(tag, ...) tdlog::write(TdLogLevel::Trace, tag, __VA_ARGS__)
#else
#define LOGT(tag, ...) ((void)0)
#endif
