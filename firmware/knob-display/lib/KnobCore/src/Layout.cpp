#include "Layout.h"

#include <cmath>

namespace knob {

namespace {

constexpr float kPi = 3.14159265358979f;
constexpr float kArcRadius = 158;
constexpr float kArcWidth = 16;

// Fuel across the bottom; EOT, ECT and EOT - ECT across the top.
constexpr Arc kFuel = {122, 238, kArcRadius, kArcWidth, true};
constexpr Arc kEot = {-72, -28, kArcRadius, kArcWidth, false};
constexpr Arc kEct = {-21, 21, kArcRadius, kArcWidth, false};
constexpr Arc kDelta = {28, 72, kArcRadius, kArcWidth, false};

float mid(const Arc& a) { return (a.startDeg + a.endDeg) / 2; }

}  // namespace

Point polar(float deg, float radius)
{
    const float t = deg * kPi / 180;
    return {kCentre + radius * std::sin(t), kCentre - radius * std::cos(t)};
}

bool arcFor(Slot s, Arc& out)
{
    switch (s) {
        case Slot::Fuel: out = kFuel; return true;
        case Slot::Eot: out = kEot; return true;
        case Slot::Ect: out = kEct; return true;
        case Slot::Delta: out = kDelta; return true;
        case Slot::Speed: return false;
    }
    return false;
}

float fillEndDeg(const Arc& a, float fraction)
{
    const float f = fraction < 0 ? 0 : (fraction > 1 ? 1 : fraction);
    if (a.fromEnd) return a.endDeg - (a.endDeg - a.startDeg) * f;
    return a.startDeg + (a.endDeg - a.startDeg) * f;
}

Point valueAt(Slot s)
{
    Arc a;
    if (!arcFor(s, a)) return {kCentre, kCentre};
    return polar(mid(a), s == Slot::Fuel ? 122 : 124);
}

Point captionAt(Slot s)
{
    Arc a;
    if (!arcFor(s, a)) return {kCentre, kCentre + 34};
    if (s == Slot::Fuel) return polar(180, 100);
    return polar(mid(a), 100);
}

}  // namespace knob
