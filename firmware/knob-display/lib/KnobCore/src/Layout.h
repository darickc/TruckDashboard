// Where things go on the 360 x 360 round screen (ADR-0044 decision 5).
// Angles in degrees, 0 up, clockwise; the centre is (180, 180).

#pragma once

#include "Frame.h"

namespace knob {

constexpr float kSize = 360;
constexpr float kCentre = kSize / 2;

struct Point {
    float x;
    float y;
};

struct Arc {
    float startDeg;
    float endDeg;
    float radius;  // of the stroke's middle
    float width;
    // Fills from endDeg back towards startDeg (fuel: from E, at the left).
    bool fromEnd;
};

Point polar(float deg, float radius);

// The arc a slot fills. Speed has none (it is the number in the middle).
bool arcFor(Slot s, Arc& out);

// Where the arc's fill ends for `fraction` (0..1).
float fillEndDeg(const Arc& a, float fraction);

// The value's text: under its arc, or the centre for speed.
Point valueAt(Slot s);
// The slot's name or age, under the value.
Point captionAt(Slot s);

}  // namespace knob
