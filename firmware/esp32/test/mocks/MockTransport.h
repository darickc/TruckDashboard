#pragma once
//
// Scripted IObdTransport for unit tests: a sequence of steps
// {expectWrite, response, delayMs} driven by a virtual clock, so timeout
// behavior is tested without real waiting.
//
// Each complete '\r'-terminated line the client writes must match the current
// step's expectWrite; the step's response bytes then become readable after
// delayMs of virtual time. Any mismatch or unexpected write is recorded for
// the test to assert on.

#include <cstring>
#include <string>
#include <vector>

#include "IObdTransport.h"

class MockTransport : public obd::IObdTransport {
public:
    struct Step {
        const char* expectWrite; ///< command without trailing '\r' ("" = bare CR)
        const char* response;    ///< raw bytes to feed back ('\r'-separated, may contain '>')
        uint32_t delayMs = 0;    ///< virtual delay before the response appears
    };

    // ---- virtual clock (inject MockTransport::nowFn into ElmClient) ----
    static uint32_t s_now;
    static uint32_t nowFn() { return s_now; }

    void setScript(const Step* steps, size_t count)
    {
        steps_ = steps;
        count_ = count;
        index_ = 0;
        rx_.clear();
        rxPos_ = 0;
        txLine_.clear();
        pendingActive_ = false;
        injections_.clear();
        mismatch_.clear();
    }

    /// Queue bytes to appear after `inMs` of virtual time, independently of the
    /// script. Models what the script cannot: an ECU straggler landing in the
    /// middle of the NEXT request (the response-count-digit hazard), or
    /// unsolicited STN chatter arriving at an arbitrary moment.
    void injectLater(const char* data, uint32_t inMs)
    {
        injections_.push_back({s_now + inMs, std::string(data)});
    }

    /// Advance virtual time, releasing any due response into the RX buffer.
    void advance(uint32_t ms)
    {
        s_now += ms;
        if (pendingActive_ && static_cast<int32_t>(s_now - pendingDueAt_) >= 0) {
            rx_.append(pendingData_);
            pendingActive_ = false;
        }
        for (size_t i = 0; i < injections_.size();) {
            if (static_cast<int32_t>(s_now - injections_[i].dueAt) >= 0) {
                rx_.append(injections_[i].data);
                injections_.erase(injections_.begin() + static_cast<long>(i));
            } else {
                ++i;
            }
        }
    }

    /// Simulate the SPP link dropping.
    void dropLink() { connected_ = false; }
    void restoreLink() { connected_ = true; }

    bool scriptDone() const { return index_ >= count_ && !pendingActive_; }
    const std::string& mismatch() const { return mismatch_; }

    // ---- IObdTransport ----
    bool connect() override { connected_ = true; return true; }
    void disconnect() override { connected_ = false; }
    bool isConnected() override { return connected_; }

    size_t write(const uint8_t* data, size_t len) override
    {
        for (size_t i = 0; i < len; ++i) {
            const char c = static_cast<char>(data[i]);
            if (c != '\r') {
                txLine_.push_back(c);
                continue;
            }
            // Complete command line.
            if (index_ >= count_) {
                mismatch_ = "unexpected write past end of script: '" + txLine_ + "'";
            } else if (txLine_ != steps_[index_].expectWrite) {
                mismatch_ = "expected '" + std::string(steps_[index_].expectWrite) +
                            "' got '" + txLine_ + "'";
            } else {
                pendingData_ = steps_[index_].response;
                pendingDueAt_ = s_now + steps_[index_].delayMs;
                pendingActive_ = true;
                ++index_;
                if (steps_[index_ - 1].delayMs == 0) {
                    advance(0); // release immediately
                }
            }
            txLine_.clear();
        }
        return len;
    }

    int read() override
    {
        if (!connected_ || rxPos_ >= rx_.size()) {
            return -1;
        }
        return static_cast<unsigned char>(rx_[rxPos_++]);
    }

    size_t available() override
    {
        return connected_ && rxPos_ < rx_.size() ? rx_.size() - rxPos_ : 0;
    }

private:
    const Step* steps_ = nullptr;
    size_t count_ = 0;
    size_t index_ = 0;

    std::string rx_;
    size_t rxPos_ = 0;
    std::string txLine_;

    std::string pendingData_;
    uint32_t pendingDueAt_ = 0;
    bool pendingActive_ = false;

    struct Injection {
        uint32_t dueAt;
        std::string data;
    };
    std::vector<Injection> injections_;

    bool connected_ = true;
    std::string mismatch_;
};
