// F-250 head unit: the 7" display held flush behind the dash's radio opening
// (ADR-0047). Parametric; every part prints flat on its largest face.
//
//   openscad -D 'part="glass_template"' -o glass_template.stl head_unit.scad
//   make mech-stl            renders every part into build/mechanical/
//   make mech-test           checks these numbers (tools/mechanical/check_head_unit.py)
//
// Status: DESIGN, NOT FITTED. Nothing here has been printed, held against the
// truck or screwed to the display. The truck's numbers are TODO (H34–H36 in
// docs/hardware/open-questions.md); the display's come from its drawing.
//
// Coordinates: millimetres, looking at the screen from the driver's seat.
// Origin at the cover glass's bottom-left corner on its front face; X to the
// right, Y up, Z into the dash (towards the back of the display).

part = "assembly"; // glass_template | rail_left | rail_right | assembly

$fn = 48;

// ---- The display: original Raspberry Pi 7" Touch Display (800x480) -------
// From its mechanical drawing, LMD-D/5624/KIT-LC-V3 rev 003 (Raspberry Pi
// document RP-008246-DS, read 2026-11-15). The drawing's back view is seen
// from behind, so its left edge is our right edge: the X values below are
// converted. Tolerance ±0.2 unless stated.
glass_w = 192.96;          // cover glass ("LENS")
glass_h = 110.76;
module_t = 5.96;           // glass front to the metal back (side view)
va_w = 154.88;             // touch viewable area ("TP V.A") ±0.15
va_h = 86.72;
va_x = 19.04;              // left and right margins are both 19.04
va_y = 13.03;              // bottom margin: 110.76 - 86.72 - 11.01 (top 11.01)
frame_x = 14.87;           // metal back envelope (166.2 wide, 11.89 from the
frame_w = 166.2;           //   drawing's back-view left edge = our right edge)
frame_y = 3.53;            // 100.6 tall, 3.53 above the glass's bottom edge
frame_h = 100.6;
// Four M3 holes in the metal back for mounting the display (4-M3.0).
// Back view: 20.0 from the 166.2 envelope's edge, 126.2 apart; 20.0 above
// the frame's bottom edge, 65.65 apart. Threaded, and how deep:
// UNVERIFIED (H36). The Pi's own four M2.5 standoffs (58 x 49) aren't used.
m3_x = [frame_x + frame_w - 20.0 - 126.2, frame_x + frame_w - 20.0];
m3_y = [frame_y + 20.0, frame_y + 20.0 + 65.65];
// The display's whole depth with its adapter board and standoffs: 20 mm in an
// older spec sheet, UNVERIFIED (measure). Not used yet: the rear box waits.
display_depth = 20;

// ---- Hardware (example values; set them for the inserts you buy) ---------
m3_clear = 3.4;            // M3 clearance hole
m3_head_d = 6.0;           // counterbore for an M3 socket or pan head
m3_head_h = 3.0;
insert_d = 4.0;            // hole for an M3 heat-set insert (brand-specific)
insert_h = 5.0;            // insert length + 1

// ---- Parts ----------------------------------------------------------------
template_t = 1.2;          // glass template: thin enough to slip behind the dash
rail_t = 6.0;              // rails: the display's M3 screws pass through them
rail_half = 9.0;           // rail reaches 9 mm inboard of the display's M3 holes
ear_w = 14.0;              // flange beyond the glass's side edge, for the truck
                           //   mount (side brackets, H35). Example value
ear_insert_y = [20, glass_h - 20];   // inserts in each ear, for the brackets
box_insert_y = [7, glass_h - 7];     // inserts on each rail's back, for the
                                     //   rear box (not designed yet)

// The glass template: the cover glass's outline with the viewable area cut
// out. Held behind the dash's opening it shows whether the opening falls
// inside the black border (H34). (The display's M3 holes are behind the
// viewable area, so the template can't mark them; the rails check those.)
module glass_template() {
    difference() {
        cube([glass_w, glass_h, template_t]);
        translate([va_x, va_y, -1]) cube([va_w, va_h, template_t + 2]);
        // A notch on the top edge: this side up, facing the driver.
        translate([glass_w / 2 - 3, glass_h - 3, -1]) cube([6, 4, template_t + 2]);
    }
}

// A rail: screwed to the display's two M3 holes on one side, it carries an
// ear beyond the glass for the truck mount and inserts for the rear box.
// Printed with its front face (the face against the display) on the bed.
// left = true: the left side seen from the driver's seat.
module rail(left) {
    hole_x = left ? m3_x[0] : m3_x[1];
    x0 = left ? -ear_w : hole_x - rail_half;
    x1 = left ? hole_x + rail_half : glass_w + ear_w;
    ear_x = left ? -ear_w / 2 : glass_w + ear_w / 2;
    box_x = left ? (hole_x + rail_half + frame_x) / 2 : (hole_x - rail_half + frame_x + frame_w) / 2;
    translate([0, 0, module_t]) difference() {
        translate([x0, 0, 0]) cube([x1 - x0, glass_h, rail_t]);
        // The display's M3 screws, heads at the back.
        for (y = m3_y) translate([hole_x, y, 0]) {
            translate([0, 0, -1]) cylinder(d = m3_clear, h = rail_t + 2);
            translate([0, 0, rail_t - m3_head_h]) cylinder(d = m3_head_d, h = m3_head_h + 1);
        }
        // Inserts from the back: the truck's brackets on the ear, the rear box.
        for (y = ear_insert_y) translate([ear_x, y, rail_t - insert_h])
            cylinder(d = insert_d, h = insert_h + 1);
        for (y = box_insert_y) translate([box_x, y, rail_t - insert_h])
            cylinder(d = insert_d, h = insert_h + 1);
    }
}

// The display, for the assembly view only (not a part).
module display_ghost() {
    color("black", 0.6) cube([glass_w, glass_h, 0.7]);
    color("silver", 0.6) translate([frame_x, frame_y, 0.7]) cube([frame_w, frame_h, module_t - 0.7]);
    color("royalblue", 0.4) translate([va_x, va_y, -0.01]) cube([va_w, va_h, 0.02]);
}

// Parts are laid flat for printing: the rails' front face (against the
// display) on the bed, the counterbores and insert holes opening upwards.
if (part == "glass_template") glass_template();
else if (part == "rail_left") translate([0, 0, -module_t]) rail(true);
else if (part == "rail_right") translate([0, 0, -module_t]) rail(false);
else {
    display_ghost();
    color("orange") rail(true);
    color("orange") rail(false);
    color("gold", 0.5) translate([0, 0, -template_t - 5]) glass_template();
}
