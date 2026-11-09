#pragma once
//
// Debug renderer: draws the gauge pages as text on USB Serial. This is the
// milestone-1 "display" and remains useful on the bench forever.

#include "IDisplay.h"

class SerialDisplay : public IDisplay {
public:
    explicit SerialDisplay(uint32_t intervalMs) : intervalMs_(intervalMs) {}

    void begin() override;
    void render(const DisplaySnapshot& snap) override;
    void setPage(PageId page) override { page_ = page; }

private:
    void printValue(const DisplaySnapshot& snap, obd::ChannelId id);
    void printRow(const DisplaySnapshot& snap, obd::ChannelId left, obd::ChannelId right);

    uint32_t intervalMs_;
    uint32_t lastRenderMs_ = 0;
    PageId page_ = PageId::EngineHealth;
};
