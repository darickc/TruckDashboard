#include "PulseKnob.h"

namespace knob {

bool PulseKnob::step(Line& l, bool high)
{
    bool released = false;
    if (!high) {
        if (l.lowFor < 255) l.lowFor++;
    } else {
        released = !l.high && l.lowFor >= minLow_;
        l.lowFor = 0;
    }
    l.high = high;
    return released;
}

int PulseKnob::sample(bool aHigh, bool bHigh)
{
    int steps = 0;
    if (step(a_, aHigh)) steps++;
    if (step(b_, bHigh)) steps--;
    return steps;
}

}  // namespace knob
