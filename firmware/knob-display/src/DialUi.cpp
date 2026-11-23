#include "DialUi.h"

#include <Arduino.h>
#include <esp_heap_caps.h>
#include <lvgl.h>

#include <cmath>
#include <cstdio>
#include <cstring>

#include "Layout.h"

// The look follows the "proposed" row of the design canvas (owner,
// 2026-11-22): thin tracks with thick rounded fills, small letter-spaced
// capitals for names, page dots, an outlined SIMULATED / NO DATA tag, a large
// turn arrow, the track's progress across the top of the media page, and the
// caller's initials.

namespace knob {

namespace {

// ---- Colours (ADR-0044 decision 4) ---------------------------------------
// Current: white text, a cyan fill. Alerts: amber (advisory), red (critical),
// the gateway's rules. Stale: amber, dimmed, with its age. Nothing: a grey
// dash and no fill.
constexpr uint32_t kWhite = 0xFFFFFF;
constexpr uint32_t kGrey = 0x9A9A9A;
constexpr uint32_t kDash = 0x6E6E6E;
constexpr uint32_t kTrack = 0x333333;
constexpr uint32_t kTrackCritical = 0x5A1A16;
constexpr uint32_t kDotOff = 0x4A4A4A;
constexpr uint32_t kAvatar = 0x2A2A2A;
constexpr uint32_t kCyan = 0x5CC8FF;
constexpr uint32_t kAmber = 0xFFB300;
constexpr uint32_t kRed = 0xFF4A3D;
constexpr uint32_t kStale = 0xB88A2A;
constexpr lv_opa_t kStaleFillOpa = 89;  // 35 %
constexpr lv_opa_t kOpaque = LV_OPA_COVER;
constexpr lv_opa_t kClear = LV_OPA_TRANSP;

// The arcs: a thin track on the outer edge, a thick rounded fill over it.
constexpr int kTrackWidth = 4;
constexpr int kFillWidth = 14;

// ---- Small wrappers that only touch LVGL when something changed ----------

void showObj(lv_obj_t* o, bool on)
{
    if (on == !lv_obj_has_flag(o, LV_OBJ_FLAG_HIDDEN)) return;
    if (on) {
        lv_obj_clear_flag(o, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(o, LV_OBJ_FLAG_HIDDEN);
    }
}

struct Label {
    lv_obj_t* obj = nullptr;
    uint32_t color = 0xFFFFFFFF;

    void text(const char* t)
    {
        const char* cur = lv_label_get_text(obj);
        if (!cur || std::strcmp(cur, t) != 0) lv_label_set_text(obj, t);
    }
    void colour(uint32_t c)
    {
        if (c == color) return;
        color = c;
        lv_obj_set_style_text_color(obj, lv_color_hex(c), 0);
    }
    void show(bool on) { showObj(obj, on); }
};

lv_coord_t px(float v) { return static_cast<lv_coord_t>(std::lround(v)); }

// Places an object's centre on (x, y) of the 360 x 360 screen.
void centreOn(lv_obj_t* o, float x, float y) { lv_obj_align(o, LV_ALIGN_CENTER, px(x - kCentre), px(y - kCentre)); }

// A label centred on (x, y). `spacing`: letter spacing in px (the small
// capitals use 2-3).
Label makeLabel(lv_obj_t* parent, const lv_font_t* font, float x, float y, uint32_t c, int spacing = 0,
                int wrapWidth = 0, int maxLines = 0)
{
    Label l;
    l.obj = lv_label_create(parent);
    lv_obj_set_style_text_font(l.obj, font, 0);
    lv_obj_set_style_text_align(l.obj, LV_TEXT_ALIGN_CENTER, 0);
    if (spacing) lv_obj_set_style_text_letter_space(l.obj, static_cast<lv_coord_t>(spacing), 0);
    if (wrapWidth > 0) {
        lv_obj_set_width(l.obj, wrapWidth);
        if (maxLines > 0) {
            lv_label_set_long_mode(l.obj, LV_LABEL_LONG_DOT);
            lv_obj_set_height(l.obj, static_cast<lv_coord_t>(lv_font_get_line_height(font) * maxLines));
        } else {
            lv_label_set_long_mode(l.obj, LV_LABEL_LONG_WRAP);
        }
    }
    lv_label_set_text(l.obj, "");
    centreOn(l.obj, x, y);
    l.colour(c);
    return l;
}

// Turns a label by `deg` (clockwise positive) about its centre. The box gets
// a fixed size, so the pivot doesn't move as the text changes.
void rotate(Label& l, float deg, int width)
{
    const lv_font_t* font = lv_obj_get_style_text_font(l.obj, 0);
    const lv_coord_t h = lv_font_get_line_height(font);
    lv_obj_set_size(l.obj, width, h);
    lv_label_set_long_mode(l.obj, LV_LABEL_LONG_CLIP);
    lv_obj_set_style_transform_pivot_x(l.obj, width / 2, 0);
    lv_obj_set_style_transform_pivot_y(l.obj, h / 2, 0);
    lv_obj_set_style_transform_angle(l.obj, px(deg * 10), 0);
}

// A page or overlay: the whole screen, no style of its own.
lv_obj_t* makeLayer(lv_obj_t* parent, bool opaque)
{
    lv_obj_t* o = lv_obj_create(parent);
    lv_obj_remove_style_all(o);
    lv_obj_set_size(o, 360, 360);
    lv_obj_clear_flag(o, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_clear_flag(o, LV_OBJ_FLAG_CLICKABLE);
    if (opaque) {
        lv_obj_set_style_bg_color(o, lv_color_black(), 0);
        lv_obj_set_style_bg_opa(o, LV_OPA_COVER, 0);
    }
    return o;
}

// A plain object with no theme styling.
lv_obj_t* makeBox(lv_obj_t* parent)
{
    lv_obj_t* o = lv_obj_create(parent);
    lv_obj_remove_style_all(o);
    lv_obj_clear_flag(o, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_clear_flag(o, LV_OBJ_FLAG_CLICKABLE);
    return o;
}

// A circle of diameter `d` centred on (x, y).
lv_obj_t* makeCircle(lv_obj_t* parent, int d, float x, float y)
{
    lv_obj_t* o = makeBox(parent);
    lv_obj_set_size(o, d, d);
    lv_obj_set_style_radius(o, LV_RADIUS_CIRCLE, 0);
    centreOn(o, x, y);
    return o;
}

// Layout.h's degrees (0 up, clockwise) to LVGL's (0 at three o'clock).
uint16_t lvDeg(float deg)
{
    long d = std::lround(deg + 270.0f) % 360;
    if (d < 0) d += 360;
    return static_cast<uint16_t>(d);
}

// A full ring at the screen's edge (NO DATA, a ringing call).
lv_obj_t* makeRing(lv_obj_t* parent, int width, uint32_t c)
{
    lv_obj_t* r = lv_arc_create(parent);
    lv_obj_set_size(r, 358, 358);
    lv_obj_center(r);
    lv_obj_remove_style(r, nullptr, LV_PART_KNOB);
    lv_obj_clear_flag(r, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_pad_all(r, 0, 0);
    lv_obj_set_style_bg_opa(r, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(r, 0, 0);
    lv_obj_set_style_arc_width(r, static_cast<lv_coord_t>(width), LV_PART_MAIN);
    lv_obj_set_style_arc_color(r, lv_color_hex(c), LV_PART_MAIN);
    lv_obj_set_style_arc_opa(r, LV_OPA_TRANSP, LV_PART_INDICATOR);
    lv_arc_set_bg_angles(r, 0, 360);
    return r;
}

// One of Layout.h's arcs: a thin track on its outer edge and a thick fill
// with rounded ends over it (LVGL draws both inward from the outer edge).
struct Gauge {
    lv_obj_t* obj = nullptr;
    Arc arc{};
    float insetDeg = 0;  // the rounded ends, kept inside the arc's angles
    uint32_t color = 0xFFFFFFFF, track = 0xFFFFFFFF;
    lv_opa_t opa = 0;
    uint16_t a0 = 0xFFFF, a1 = 0xFFFF;

    void make(lv_obj_t* parent, const Arc& a, int trackWidth = kTrackWidth, int fillWidth = kFillWidth)
    {
        arc = a;
        const float outer = a.radius + a.width / 2;
        insetDeg = (fillWidth / 2.0f) / (outer - fillWidth / 2.0f) * 180.0f / 3.14159265f;
        obj = lv_arc_create(parent);
        const lv_coord_t size = px(2 * outer);
        lv_obj_set_size(obj, size, size);
        lv_obj_center(obj);
        lv_obj_remove_style(obj, nullptr, LV_PART_KNOB);
        lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_set_style_pad_all(obj, 0, 0);
        lv_obj_set_style_bg_opa(obj, LV_OPA_TRANSP, 0);
        lv_obj_set_style_border_width(obj, 0, 0);
        lv_obj_set_style_arc_width(obj, static_cast<lv_coord_t>(trackWidth), LV_PART_MAIN);
        lv_obj_set_style_arc_width(obj, static_cast<lv_coord_t>(fillWidth), LV_PART_INDICATOR);
        lv_obj_set_style_arc_rounded(obj, false, LV_PART_MAIN);
        lv_obj_set_style_arc_rounded(obj, true, LV_PART_INDICATOR);
        lv_arc_set_bg_angles(obj, lvDeg(a.startDeg), lvDeg(a.endDeg));
        trackColour(kTrack);
        fill(0, kCyan);
    }

    void trackColour(uint32_t c)
    {
        if (c == track) return;
        track = c;
        lv_obj_set_style_arc_color(obj, lv_color_hex(c), LV_PART_MAIN);
    }

    // Fills `fraction` (0..1) of the arc; nothing at 0.
    void fill(float fraction, uint32_t c, lv_opa_t o = LV_OPA_COVER)
    {
        const bool on = fraction > 0.001f;
        const lv_opa_t want = on ? o : kClear;
        if (want != opa) {
            opa = want;
            lv_obj_set_style_arc_opa(obj, want, LV_PART_INDICATOR);
        }
        if (c != color) {
            color = c;
            lv_obj_set_style_arc_color(obj, lv_color_hex(c), LV_PART_INDICATOR);
        }
        if (!on) return;
        const float end = fillEndDeg(arc, fraction);
        const float s = (arc.fromEnd ? end : arc.startDeg) + insetDeg;
        float e = (arc.fromEnd ? arc.endDeg : end) - insetDeg;
        if (e < s + 1) e = s + 1;  // a small value is a dot, not nothing
        const uint16_t ls = lvDeg(s), le = lvDeg(e);
        if (ls != a0 || le != a1) {
            a0 = ls;
            a1 = le;
            lv_arc_set_angles(obj, ls, le);
        }
    }
};

// Three page dots centred on y; `active` is white.
void makeDots(lv_obj_t* parent, float y, size_t active)
{
    for (size_t i = 0; i < kPages; ++i) {
        lv_obj_t* d = makeCircle(parent, 6, kCentre + (static_cast<float>(i) - 1) * 14, y);
        lv_obj_set_style_bg_opa(d, LV_OPA_COVER, 0);
        lv_obj_set_style_bg_color(d, lv_color_hex(i == active ? kWhite : kDotOff), 0);
    }
}

// An outlined tag: SIMULATED, NO DATA.
Label makeTag(lv_obj_t* parent, float x, float y)
{
    Label l = makeLabel(parent, &dial_caps, x, y, kAmber, 2);
    lv_obj_set_style_border_width(l.obj, 2, 0);
    lv_obj_set_style_border_color(l.obj, lv_color_hex(kAmber), 0);
    lv_obj_set_style_radius(l.obj, 11, 0);
    lv_obj_set_style_pad_hor(l.obj, 8, 0);
    lv_obj_set_style_pad_ver(l.obj, 3, 0);
    return l;
}

void tagColour(Label& l, uint32_t c)
{
    if (c == l.color) return;
    l.colour(c);
    lv_obj_set_style_border_color(l.obj, lv_color_hex(c), 0);
}

// ASCII letters to capitals, in place (others are left as they are).
void upper(char* s)
{
    for (; *s; ++s) {
        if (*s >= 'a' && *s <= 'z') *s = static_cast<char>(*s - 'a' + 'A');
    }
}

// ---- The screens ---------------------------------------------------------

struct SlotUi {
    Slot slot;
    Gauge gauge;
    Label value, caption;
    const char* name;
};

struct {
    lv_obj_t* gauges = nullptr;
    lv_obj_t* nav = nullptr;
    lv_obj_t* media = nullptr;
    lv_obj_t* call = nullptr;

    // Gauges.
    SlotUi slots[4];
    Label speed, speedCaption, tag;
    lv_obj_t* noDataRing = nullptr;

    // Navigation.
    Label navDistNum, navDistUnit, navText, navLeft, navMessage;
    lv_obj_t* navDist = nullptr;
    lv_obj_t* arrowShaft = nullptr;
    lv_obj_t* arrowHead = nullptr;
    lv_obj_t* arrowDot = nullptr;
    lv_point_t shaftPts[4];
    lv_point_t headPts[3];
    int arrowTurn = -1;

    // Media.
    Label mediaSource, mediaSymbol, mediaName, mediaArtist, mediaTime, mediaVolCaption, mediaVolume, mediaMessage;
    lv_obj_t* playRing = nullptr;
    Gauge progress, volume;

    // Call.
    lv_obj_t* callRing = nullptr;
    lv_obj_t* avatar = nullptr;
    Label callInitials, callPhone, callState, callCaller, callNumber, callTime, callHint;

    int page = -1;
} ui;

Panel* gPanel = nullptr;
uint32_t gFlushes = 0;
const char* gError = "";
lv_disp_draw_buf_t gDrawBuf;
lv_disp_drv_t gDrv;

void flush(lv_disp_drv_t* drv, const lv_area_t* a, lv_color_t* pixels)
{
    if (!gPanel->draw(a->x1, a->y1, a->x2 + 1, a->y2 + 1, reinterpret_cast<const uint16_t*>(pixels))) {
        gError = gPanel->lastError();
    } else {
        gFlushes++;
    }
    lv_disp_flush_ready(drv);
}

// The panel takes windows that start and end on even pixels.
void round(lv_disp_drv_t*, lv_area_t* a)
{
    a->x1 &= ~1;
    a->y1 &= ~1;
    a->x2 |= 1;
    a->y2 |= 1;
}

void buildGauges()
{
    lv_obj_t* p = ui.gauges;
    const struct {
        Slot s;
        const char* name;
    } kSlots[] = {{Slot::Fuel, "FUEL"}, {Slot::Eot, "EOT"}, {Slot::Ect, "ECT"}, {Slot::Delta, "DELTA"}};
    for (int i = 0; i < 4; ++i) {
        SlotUi& u = ui.slots[i];
        u.slot = kSlots[i].s;
        u.name = kSlots[i].name;
        Arc a;
        arcFor(u.slot, a);
        u.gauge.make(p, a);
        const Point v = valueAt(u.slot), c = captionAt(u.slot);
        u.value = makeLabel(p, &dial_value, v.x, v.y, kWhite);
        u.caption = makeLabel(p, &dial_caps, c.x, c.y, kGrey, 2);
        // EOT and EOT - ECT turn with their arcs (owner, 2026-11-22): EOT
        // counter-clockwise, EOT - ECT clockwise, by the arc's middle angle.
        if (u.slot == Slot::Eot || u.slot == Slot::Delta) {
            const float mid = (a.startDeg + a.endDeg) / 2;
            rotate(u.value, mid, 110);
            rotate(u.caption, mid, 130);
        }
    }
    // E and F beyond the fuel arc's ends (it fills from E, at the left).
    makeLabel(p, &dial_caps, 38, 242, kGrey).text("E");
    makeLabel(p, &dial_caps, 322, 242, kGrey).text("F");

    ui.speed = makeLabel(p, &dial_speed, kCentre, 160, kWhite, -4);
    ui.speedCaption = makeLabel(p, &dial_caps, kCentre, 216, kGrey, 3);
    makeDots(p, 238, 0);
    ui.tag = makeTag(p, kCentre, 260);
    ui.noDataRing = makeRing(p, 3, kRed);
}

void buildNav()
{
    lv_obj_t* p = ui.nav;
    makeLabel(p, &dial_caps, kCentre, 40, kGrey, 3).text("NAVIGATION");

    // The distance: a large number and its unit in small capitals beside it.
    ui.navDist = makeBox(p);
    lv_obj_set_size(ui.navDist, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(ui.navDist, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(ui.navDist, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_END, LV_FLEX_ALIGN_END);
    lv_obj_set_style_pad_column(ui.navDist, 6, 0);
    centreOn(ui.navDist, kCentre, 216);
    ui.navDistNum.obj = lv_label_create(ui.navDist);
    lv_obj_set_style_text_font(ui.navDistNum.obj, &dial_big, 0);
    lv_obj_set_style_text_letter_space(ui.navDistNum.obj, -1, 0);
    ui.navDistNum.colour(kWhite);
    ui.navDistUnit.obj = lv_label_create(ui.navDist);
    lv_obj_set_style_text_font(ui.navDistUnit.obj, &dial_caps, 0);
    lv_obj_set_style_text_letter_space(ui.navDistUnit.obj, 2, 0);
    lv_obj_set_style_pad_bottom(ui.navDistUnit.obj, 9, 0);
    ui.navDistUnit.colour(kGrey);

    ui.navText = makeLabel(p, &dial_text, kCentre, 262, kWhite, 0, 250, 2);
    ui.navLeft = makeLabel(p, &dial_caps, kCentre, 300, kGrey, 2);
    ui.navMessage = makeLabel(p, &dial_text, kCentre, 200, kWhite, 0, 250);
    makeDots(p, 326, 1);

    ui.arrowShaft = lv_line_create(p);
    ui.arrowHead = lv_line_create(p);
    for (lv_obj_t* l : {ui.arrowShaft, ui.arrowHead}) {
        lv_obj_set_style_line_width(l, 14, 0);
        lv_obj_set_style_line_color(l, lv_color_hex(kWhite), 0);
        lv_obj_set_style_line_rounded(l, true, 0);
    }
    ui.arrowDot = makeCircle(p, 44, kCentre, 118);
    lv_obj_set_style_border_width(ui.arrowDot, 9, 0);
    lv_obj_set_style_border_color(ui.arrowDot, lv_color_hex(kWhite), 0);
}

void buildMedia()
{
    lv_obj_t* p = ui.media;
    const Arc top = {-50, 50, 160, 12, false};  // outer edge 166, as the gauges
    ui.progress.make(p, top, 4, 6);
    ui.mediaSource = makeLabel(p, &dial_caps, kCentre, 52, kGrey, 2, 210, 1);
    ui.playRing = makeCircle(p, 54, kCentre, 102);
    lv_obj_set_style_border_width(ui.playRing, 2, 0);
    lv_obj_set_style_border_color(ui.playRing, lv_color_hex(kWhite), 0);
    ui.mediaSymbol = makeLabel(p, &lv_font_montserrat_20, kCentre + 2, 102, kWhite);
    ui.mediaName = makeLabel(p, &dial_title, kCentre, 164, kWhite, 0, 260, 2);
    ui.mediaArtist = makeLabel(p, &dial_small, kCentre, 204, kGrey, 0, 250, 1);
    ui.mediaTime = makeLabel(p, &dial_caps, kCentre, 230, kGrey, 1);
    ui.mediaMessage = makeLabel(p, &dial_text, kCentre, 150, kWhite, 0, 250);
    makeDots(p, 254, 2);
    Arc vol;
    arcFor(Slot::Fuel, vol);
    ui.volume.make(p, vol);
    ui.mediaVolCaption = makeLabel(p, &dial_caps, kCentre, 280, kGrey, 2);
    ui.mediaVolume = makeLabel(p, &dial_value, kCentre, 302, kWhite);
}

void buildCall()
{
    lv_obj_t* p = ui.call;
    ui.callRing = makeRing(p, 4, kAmber);
    ui.avatar = makeCircle(p, 72, kCentre, 106);
    lv_obj_set_style_bg_opa(ui.avatar, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(ui.avatar, lv_color_hex(kAvatar), 0);
    ui.callInitials.obj = lv_label_create(ui.avatar);
    lv_obj_set_style_text_font(ui.callInitials.obj, &dial_caller, 0);
    lv_obj_set_style_text_letter_space(ui.callInitials.obj, 1, 0);
    lv_obj_center(ui.callInitials.obj);
    ui.callInitials.colour(kWhite);
    ui.callPhone.obj = lv_label_create(ui.avatar);
    lv_obj_set_style_text_font(ui.callPhone.obj, &lv_font_montserrat_20, 0);
    lv_obj_center(ui.callPhone.obj);
    lv_label_set_text(ui.callPhone.obj, LV_SYMBOL_CALL);
    ui.callPhone.colour(kWhite);
    ui.callState = makeLabel(p, &dial_caps, kCentre, 166, kAmber, 3);
    ui.callCaller = makeLabel(p, &dial_caller, kCentre, 204, kWhite, 0, 280, 2);
    ui.callNumber = makeLabel(p, &dial_small, kCentre, 244, kGrey);
    ui.callTime = makeLabel(p, &dial_text, kCentre, 278, kWhite);
    ui.callHint = makeLabel(p, &dial_small, kCentre, 304, kGrey, 0, 240);
}

// ---- Updating ------------------------------------------------------------

uint32_t valueColour(State s)
{
    switch (s) {
        case State::Current: return kWhite;
        case State::Advisory: return kAmber;
        case State::Critical: return kRed;
        case State::Stale: return kStale;
        case State::None: return kDash;
    }
    return kDash;
}

uint32_t fillColour(State s)
{
    switch (s) {
        case State::Current: return kCyan;
        case State::Advisory:
        case State::Stale: return kAmber;
        case State::Critical: return kRed;
        case State::None: return kCyan;
    }
    return kCyan;
}

// "14 S AGO": a stale value's age in small capitals.
void staleCaption(float ageS, char* buf, size_t size)
{
    char age[16];
    formatAge(ageS, age, sizeof(age));
    std::snprintf(buf, size, "%s AGO", age);
    upper(buf);
}

void updateGauges(const Dial& dial, uint32_t now)
{
    char buf[32];
    for (SlotUi& u : ui.slots) {
        const View v = dial.view(u.slot, now);
        formatValue(u.slot, v, buf, sizeof(buf));
        u.value.text(buf);
        u.value.colour(valueColour(v.state));
        u.gauge.fill(v.state == State::None ? 0 : v.fraction, fillColour(v.state),
                     v.state == State::Stale ? kStaleFillOpa : kOpaque);
        u.gauge.trackColour(v.state == State::Critical ? kTrackCritical : kTrack);
        if (v.state == State::Stale) {
            staleCaption(v.ageS, buf, sizeof(buf));
            u.caption.text(buf);
            u.caption.colour(kStale);
        } else if (v.state == State::Advisory || v.state == State::Critical) {
            std::snprintf(buf, sizeof(buf), "%s ALERT", u.name);
            u.caption.text(buf);
            u.caption.colour(valueColour(v.state));
        } else {
            u.caption.text(u.name);
            u.caption.colour(kGrey);
        }
    }

    const View s = dial.view(Slot::Speed, now);
    formatValue(Slot::Speed, s, buf, sizeof(buf));
    ui.speed.text(buf);
    ui.speed.colour(valueColour(s.state));
    if (s.state == State::Stale) {
        staleCaption(s.ageS, buf, sizeof(buf));
        ui.speedCaption.colour(kStale);
    } else if (s.state == State::Advisory || s.state == State::Critical) {
        std::snprintf(buf, sizeof(buf), "%s ALERT", s.unit && *s.unit ? s.unit : "SPEED");
        upper(buf);
        ui.speedCaption.colour(valueColour(s.state));
    } else {
        std::snprintf(buf, sizeof(buf), "%s", s.unit ? s.unit : "");
        upper(buf);
        ui.speedCaption.colour(kGrey);
    }
    ui.speedCaption.text(buf);

    const bool lost = dial.linkLost(now);
    showObj(ui.noDataRing, lost);
    if (lost) {
        ui.tag.text("NO DATA");
        tagColour(ui.tag, kRed);
        ui.tag.show(true);
    } else {
        ui.tag.text("SIMULATED");
        tagColour(ui.tag, kAmber);
        ui.tag.show(dial.simulated());
    }
}

// The next turn's arrow: a shaft up from below, bending by the turn's angle
// at the elbow, the head at the tip; shifted against the turn so the whole
// arrow sits in the middle.
void drawArrow(Turn t)
{
    const int key = static_cast<int>(t);
    if (key == ui.arrowTurn) return;
    ui.arrowTurn = key;

    int angle = 0;  // 0 straight on, positive right
    bool uturn = false, dot = false, none = false;
    switch (t) {
        case Turn::Straight:
        case Turn::Merge:
        case Turn::Start: angle = 0; break;
        case Turn::SlightRight:
        case Turn::RampRight:
        case Turn::ForkRight: angle = 45; break;
        case Turn::Right: angle = 90; break;
        case Turn::SharpRight: angle = 135; break;
        case Turn::SlightLeft:
        case Turn::RampLeft:
        case Turn::ForkLeft: angle = -45; break;
        case Turn::Left: angle = -90; break;
        case Turn::SharpLeft: angle = -135; break;
        case Turn::UTurnRight: uturn = true; angle = 1; break;
        case Turn::UTurnLeft: uturn = true; angle = -1; break;
        case Turn::Destination:
        case Turn::Roundabout: dot = true; break;
        case Turn::Ferry:
        case Turn::Other: none = true; break;
    }
    showObj(ui.arrowDot, dot);
    showObj(ui.arrowShaft, !dot && !none);
    showObj(ui.arrowHead, !dot && !none);
    if (dot || none) return;

    const float baseY = 178, elbowY = 112, len = 48;
    float tx, ty, dirx, diry;
    uint16_t n = 3;
    if (uturn) {
        // Up, across, and back down: the head points down.
        const float side = angle > 0 ? 1.f : -1.f;
        const float x0 = kCentre - side * 18, x1 = kCentre + side * 18;
        ui.shaftPts[0] = {px(x0), px(baseY)};
        ui.shaftPts[1] = {px(x0), px(elbowY - 8)};
        ui.shaftPts[2] = {px(x1), px(elbowY - 8)};
        ui.shaftPts[3] = {px(x1), px(baseY - 26)};
        n = 4;
        tx = x1;
        ty = baseY - 26;
        dirx = 0;
        diry = 1;
    } else {
        const float rad = angle * 3.14159265f / 180.f;
        dirx = std::sin(rad);
        diry = -std::cos(rad);
        const float ex = kCentre - dirx * 20;
        tx = ex + dirx * len;
        ty = elbowY + diry * len;
        ui.shaftPts[0] = {px(ex), px(baseY)};
        ui.shaftPts[1] = {px(ex), px(elbowY)};
        ui.shaftPts[2] = {px(tx), px(ty)};
    }
    // The head: two strokes back from the tip, 35 degrees either side.
    const float back = 24, c = std::cos(0.61f), s = std::sin(0.61f);
    const float lx = -dirx * c - diry * s, ly = -diry * c + dirx * s;
    const float rx = -dirx * c + diry * s, ry = -diry * c - dirx * s;
    ui.headPts[0] = {px(tx + lx * back), px(ty + ly * back)};
    ui.headPts[1] = {px(tx), px(ty)};
    ui.headPts[2] = {px(tx + rx * back), px(ty + ry * back)};
    lv_line_set_points(ui.arrowShaft, ui.shaftPts, n);
    lv_line_set_points(ui.arrowHead, ui.headPts, 3);
}

void updateNav(const Pages& pages, uint32_t now)
{
    const NavFrame* n = pages.nav(now);
    const bool active = n && n->state == NavState::Active;
    showObj(ui.navDist, active);
    ui.navText.show(active);
    ui.navLeft.show(active);
    ui.navMessage.show(!active);
    if (!active) {
        drawArrow(n && n->state == NavState::Arrived ? Turn::Destination : Turn::Other);
        char msg[128];
        if (!n) {
            std::snprintf(msg, sizeof(msg), "No navigation data");
        } else if (n->state == NavState::None) {
            std::snprintf(msg, sizeof(msg), "No route");
        } else if (n->state == NavState::Routing) {
            std::snprintf(msg, sizeof(msg), "Finding a route…");
        } else if (n->state == NavState::Waiting) {
            std::snprintf(msg, sizeof(msg), "Waiting for a position");
        } else {
            std::snprintf(msg, sizeof(msg), "Arrived%s%s", n->text[0] ? "\n" : "", n->text);
        }
        ui.navMessage.text(msg);
        ui.navMessage.colour(n ? kWhite : kGrey);
        return;
    }
    drawArrow(n->turn);
    char buf[48];
    ui.navDistNum.text(n->dist);
    std::snprintf(buf, sizeof(buf), "%s", n->distUnit);
    upper(buf);
    ui.navDistUnit.text(buf);
    ui.navText.text(n->text);
    std::snprintf(buf, sizeof(buf), "%s %s  ·  %u MIN", n->left, n->leftUnit, static_cast<unsigned>(n->minutes));
    upper(buf);
    ui.navLeft.text(buf);
}

void updateMedia(const Pages& pages, uint32_t now)
{
    const MediaFrame* m = pages.media(now);
    const bool playing = m && m->state != PlayState::None;
    showObj(ui.playRing, playing);
    ui.mediaSymbol.show(playing);
    ui.mediaName.show(playing);
    ui.mediaArtist.show(playing);
    ui.mediaTime.show(playing);
    ui.mediaMessage.show(!playing);

    char buf[48];
    std::snprintf(buf, sizeof(buf), "%s", m && m->source[0] ? m->source : "MEDIA");
    upper(buf);
    ui.mediaSource.text(buf);

    // The track's progress across the top, while both ends are known.
    const bool hasProgress = playing && m->posS >= 0 && m->durS > 0;
    showObj(ui.progress.obj, hasProgress);
    if (hasProgress) ui.progress.fill(static_cast<float>(m->posS) / m->durS, kWhite);

    // The volume shows whenever audio-manager says it, phone or not.
    const bool hasVolume = m && m->volume >= 0 && m->volumeSteps > 0;
    ui.mediaVolCaption.show(hasVolume);
    ui.mediaVolume.show(hasVolume);
    if (hasVolume) {
        std::snprintf(buf, sizeof(buf), "%d", m->volume);
        ui.mediaVolume.text(buf);
        ui.mediaVolume.colour(m->muted ? kStale : kWhite);
        ui.mediaVolCaption.text(m->muted ? "MUTED" : "VOLUME");
        ui.mediaVolCaption.colour(m->muted ? kAmber : kGrey);
        ui.volume.fill(static_cast<float>(m->volume) / m->volumeSteps, m->muted ? kAmber : kCyan,
                       m->muted ? kStaleFillOpa : kOpaque);
    } else {
        ui.volume.fill(0, kCyan);
    }

    if (!playing) {
        ui.mediaMessage.text(m ? "No phone" : "No media data");
        return;
    }
    ui.mediaSymbol.text(m->state == PlayState::Playing ? LV_SYMBOL_PLAY
                        : m->state == PlayState::Paused ? LV_SYMBOL_PAUSE
                                                         : LV_SYMBOL_STOP);
    ui.mediaName.text(m->title[0] ? m->title : "—");
    ui.mediaArtist.text(m->artist);
    formatTrackTime(m->posS, m->durS, buf, sizeof(buf));
    ui.mediaTime.text(buf);
}

// The first character of `s` (a whole UTF-8 sequence), ASCII in capitals.
size_t firstChar(const char* s, char* out)
{
    const unsigned char c = static_cast<unsigned char>(*s);
    size_t n = c < 0x80 ? 1 : (c >> 5) == 0x6 ? 2 : (c >> 4) == 0xE ? 3 : (c >> 3) == 0x1E ? 4 : 1;
    for (size_t i = 0; i < n; ++i) {
        if (!s[i]) {
            n = i;
            break;
        }
        out[i] = s[i];
    }
    if (n == 1 && out[0] >= 'a' && out[0] <= 'z') out[0] = static_cast<char>(out[0] - 'a' + 'A');
    return n;
}

// The caller's initials: the first letters of the first and last words.
void initials(const char* name, char* out)
{
    size_t n = 0;
    while (*name == ' ') ++name;
    if (*name) n += firstChar(name, out);
    const char* last = std::strrchr(name, ' ');
    if (last && last[1]) n += firstChar(last + 1, out + n);
    out[n] = '\0';
}

void updateCall(const Pages& pages, uint32_t now)
{
    const CallFrame* c = pages.call(now);
    showObj(ui.call, c != nullptr);
    if (!c) return;
    const char* state = "";
    bool alerting = false;
    switch (c->state) {
        case CallState::Ringing: state = "INCOMING CALL"; alerting = true; break;
        case CallState::Waiting: state = "CALL WAITING"; alerting = true; break;
        case CallState::Dialing: state = "CALLING…"; break;
        case CallState::Active: state = "ON A CALL"; break;
        case CallState::Held: state = "ON HOLD"; break;
        case CallState::None: break;
    }
    showObj(ui.callRing, alerting);
    ui.callState.text(state);
    ui.callState.colour(alerting ? kAmber : kGrey);
    // A number under the caller means the caller is a name (ADR-0045): its
    // initials; otherwise (a bare number, withheld, unknown) a phone.
    const bool named = c->number[0] != '\0';
    ui.callInitials.show(named);
    ui.callPhone.show(!named);
    if (named) {
        char in[12];
        initials(c->caller, in);
        ui.callInitials.text(in);
    }
    ui.callCaller.text(c->caller);
    ui.callNumber.text(c->number);
    char buf[16] = "";
    if (c->state == CallState::Active || c->state == CallState::Held) {
        std::snprintf(buf, sizeof(buf), "%lu:%02lu", static_cast<unsigned long>(c->activeS / 60),
                      static_cast<unsigned long>(c->activeS % 60));
    }
    ui.callTime.text(buf);
    // The board has no push switch (ADR-0044 amendment), so "Push to answer"
    // and "Push to hang up" would name a button that isn't there: only the
    // hint that doesn't need one is shown.
    ui.callHint.text(c->state == CallState::Waiting ? callHint(c->state) : "");
}

// LVGL's warnings go to the serial log as "# lvgl: ..." lines (knob-link
// logs them); the first 20 only, as one can repeat every frame.
void logLvgl(const char* msg)
{
    static uint32_t lines = 0;
    if (lines++ < 20) Serial.printf("# lvgl: %s", msg);
}

}  // namespace

bool uiBegin(Panel& panel)
{
    gPanel = &panel;
    lv_log_register_print_cb(logLvgl);
    lv_init();
    // 40 rows: the most one Panel::draw sends.
    constexpr uint32_t kBufPx = Panel::kWidth * 40;
    auto* buf = static_cast<lv_color_t*>(heap_caps_malloc(kBufPx * sizeof(lv_color_t), MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL));
    if (!buf) {
        gError = "no memory for LVGL's draw buffer";
        return false;
    }
    lv_disp_draw_buf_init(&gDrawBuf, buf, nullptr, kBufPx);
    lv_disp_drv_init(&gDrv);
    gDrv.hor_res = Panel::kWidth;
    gDrv.ver_res = Panel::kHeight;
    gDrv.flush_cb = flush;
    gDrv.rounder_cb = round;
    gDrv.draw_buf = &gDrawBuf;
    lv_disp_drv_register(&gDrv);

    lv_obj_t* scr = lv_scr_act();
    lv_obj_set_style_bg_color(scr, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);
    lv_obj_clear_flag(scr, LV_OBJ_FLAG_SCROLLABLE);

    ui.gauges = makeLayer(scr, false);
    ui.nav = makeLayer(scr, false);
    ui.media = makeLayer(scr, false);
    ui.call = makeLayer(lv_layer_top(), true);
    buildGauges();
    buildNav();
    buildMedia();
    buildCall();
    showObj(ui.nav, false);
    showObj(ui.media, false);
    showObj(ui.call, false);
    return true;
}

void uiUpdate(const Dial& dial, const Pages& pages, uint32_t nowMs)
{
    const int page = static_cast<int>(pages.index());
    if (page != ui.page) {
        ui.page = page;
        showObj(ui.gauges, page == 0);
        showObj(ui.nav, page == 1);
        showObj(ui.media, page == 2);
    }
    updateCall(pages, nowMs);
    // Only the page on screen is kept current.
    switch (pages.page()) {
        case Page::Gauges: updateGauges(dial, nowMs); break;
        case Page::Navigation: updateNav(pages, nowMs); break;
        case Page::Media: updateMedia(pages, nowMs); break;
    }
}

void uiRun() { lv_timer_handler(); }

uint32_t uiFlushes() { return gFlushes; }
const char* uiError() { return gError; }

}  // namespace knob
